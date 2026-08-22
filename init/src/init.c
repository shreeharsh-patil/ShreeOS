/*
 * init/src/init.c — ShreeOS PID 1 Service Supervisor & Init System
 *
 * Features:
 *   - Essential virtual filesystem mounting (/proc, /sys, /dev, /run, /dev/pts, /dev/shm)
 *   - Service descriptor parsing (/etc/services.d/*.conf) & default service fallback
 *   - Unix domain socket IPC (/run/init.sock) for service listing and management
 *   - Non-blocking SIGCHLD zombie process reaping (waitpid(-1, WNOHANG))
 *   - Service state machine (STOPPED, STARTING, RUNNING, FAILED, STOPPING)
 *   - Process group signal delivery & service stdout/stderr logging (/var/log/shreeos/services/)
 *   - Configurable restart policies (always, on-failure, never) with rate-limit backoff
 *   - Multi-stage orderly shutdown: SIGTERM -> wait -> SIGKILL -> sync -> remount ro -> reboot/poweroff/halt
 */

#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <fcntl.h>
#include <sys/stat.h>
#include <sys/mount.h>
#include <sys/reboot.h>
#include <sys/wait.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <signal.h>
#include <string.h>
#include <errno.h>
#include <time.h>
#include <dirent.h>
#include <stdbool.h>

#define MAX_SERVICES 64
#define SERVICE_DIR "/etc/services.d"
#define INIT_SOCK_PATH "/run/init.sock"
#define LOG_DIR "/var/log/shreeos/services"

typedef enum {
    SVC_STOPPED = 0,
    SVC_STARTING,
    SVC_RUNNING,
    SVC_FAILED,
    SVC_STOPPING
} svc_state_t;

typedef enum {
    RESTART_NEVER = 0,
    RESTART_ALWAYS,
    RESTART_ON_FAILURE
} restart_policy_t;

typedef struct service {
    char name[64];
    char command[256];
    char after[64];              /* Dependency name */
    restart_policy_t restart;
    bool is_oneshot;
    bool is_critical;
    svc_state_t state;
    pid_t pid;
    int restart_count;
    time_t last_start;
    time_t last_exit;
    int last_exit_status;
} service_t;

static service_t services[MAX_SERVICES];
static int num_services = 0;
static int ipc_sock_fd = -1;

static volatile sig_atomic_t sigchld_received = 0;
static volatile sig_atomic_t shutdown_requested = 0;
static volatile sig_atomic_t shutdown_mode = 0; /* 0 = reboot, 1 = poweroff, 2 = halt */
static volatile sig_atomic_t reload_requested = 0;

static const char *state_to_str(svc_state_t s) {
    switch (s) {
        case SVC_STOPPED:  return "STOPPED";
        case SVC_STARTING: return "STARTING";
        case SVC_RUNNING:  return "RUNNING";
        case SVC_FAILED:   return "FAILED";
        case SVC_STOPPING: return "STOPPING";
        default:           return "UNKNOWN";
    }
}

static void log_info(const char *svc, const char *msg) {
    if (svc && *svc) printf("[init] [%s] %s\n", svc, msg);
    else printf("[init] %s\n", msg);
    fflush(stdout);
}

static void log_warn(const char *svc, const char *msg) {
    if (svc && *svc) fprintf(stderr, "[init:warn] [%s] %s\n", svc, msg);
    else fprintf(stderr, "[init:warn] %s\n", msg);
    fflush(stderr);
}

static void log_error(const char *svc, const char *msg) {
    if (svc && *svc) fprintf(stderr, "[init:fail] [%s] %s: %s\n", svc, msg, strerror(errno));
    else fprintf(stderr, "[init:fail] %s: %s\n", msg, strerror(errno));
    fflush(stderr);
}

static void handle_signal(int sig) {
    if (sig == SIGCHLD) {
        sigchld_received = 1;
    } else if (sig == SIGTERM || sig == SIGINT) {
        shutdown_requested = 1;
        shutdown_mode = 0; /* Reboot */
    } else if (sig == SIGUSR1) {
        shutdown_requested = 1;
        shutdown_mode = 1; /* Power off */
    } else if (sig == SIGUSR2) {
        shutdown_requested = 1;
        shutdown_mode = 2; /* Halt */
    } else if (sig == SIGHUP) {
        reload_requested = 1;
    }
}

static int mount_fs(const char *source, const char *target,
                    const char *type, unsigned long flags, const char *opts) {
    mkdir(target, 0755);
    if (mount(source, target, type, flags, opts) < 0) {
        if (errno != EBUSY) {
            log_error("mount", target);
            return -1;
        }
    }
    return 0;
}

static void mount_essential_filesystems(void) {
    log_info(NULL, "Mounting essential virtual filesystems...");
    mount_fs("proc",     "/proc",     "proc",     0, NULL);
    mount_fs("sysfs",    "/sys",      "sysfs",    0, NULL);
    mount_fs("devtmpfs", "/dev",      "devtmpfs", 0, NULL);
    mount_fs("tmpfs",    "/run",      "tmpfs",    MS_NOSUID | MS_NODEV, "mode=0755");
    mount_fs("devpts",   "/dev/pts",  "devpts",   MS_NOSUID | MS_NOEXEC, "gid=5,mode=620");
    mount_fs("tmpfs",    "/dev/shm",  "tmpfs",    MS_NOSUID | MS_NODEV, "mode=1777");
    mount_fs("tmpfs",    "/tmp",      "tmpfs",    MS_NOSUID | MS_NODEV, "mode=1777");
}

static service_t *find_service(const char *name) {
    if (!name || !*name) return NULL;
    for (int i = 0; i < num_services; i++) {
        if (strcmp(services[i].name, name) == 0) return &services[i];
    }
    return NULL;
}

static service_t *find_service_by_pid(pid_t pid) {
    if (pid <= 0) return NULL;
    for (int i = 0; i < num_services; i++) {
        if (services[i].pid == pid) return &services[i];
    }
    return NULL;
}

static void add_service(const char *name, const char *command, const char *after,
                        restart_policy_t restart, bool is_oneshot, bool is_critical) {
    if (num_services >= MAX_SERVICES) {
        log_warn(name, "Maximum number of services reached, skipping");
        return;
    }
    service_t *s = find_service(name);
    if (!s) {
        s = &services[num_services++];
    }
    strncpy(s->name, name, sizeof(s->name) - 1);
    strncpy(s->command, command, sizeof(s->command) - 1);
    if (after) strncpy(s->after, after, sizeof(s->after) - 1);
    else s->after[0] = '\0';

    s->restart = restart;
    s->is_oneshot = is_oneshot;
    s->is_critical = is_critical;
    s->state = SVC_STOPPED;
    s->pid = 0;
    s->restart_count = 0;
    s->last_start = 0;
    s->last_exit = 0;
    s->last_exit_status = 0;
}

static void load_service_file(const char *path) {
    FILE *f = fopen(path, "r");
    if (!f) return;

    char line[512];
    char name[64] = {0};
    char command[256] = {0};
    char after[64] = {0};
    restart_policy_t restart = RESTART_NEVER;
    bool is_oneshot = false;
    bool is_critical = false;

    while (fgets(line, sizeof(line), f)) {
        char *p = line;
        while (*p == ' ' || *p == '\t') p++;
        if (*p == '#' || *p == '\n' || *p == '\0') continue;

        char *nl = strchr(p, '\n');
        if (nl) *nl = '\0';
        char *cr = strchr(p, '\r');
        if (cr) *cr = '\0';

        char *eq = strchr(p, '=');
        if (!eq) continue;
        *eq = '\0';
        char *val = eq + 1;

        if (strcmp(p, "name") == 0) {
            strncpy(name, val, sizeof(name) - 1);
        } else if (strcmp(p, "command") == 0) {
            strncpy(command, val, sizeof(command) - 1);
        } else if (strcmp(p, "after") == 0) {
            strncpy(after, val, sizeof(after) - 1);
        } else if (strcmp(p, "restart") == 0) {
            if (strcmp(val, "always") == 0) restart = RESTART_ALWAYS;
            else if (strcmp(val, "on-failure") == 0) restart = RESTART_ON_FAILURE;
            else restart = RESTART_NEVER;
        } else if (strcmp(p, "oneshot") == 0) {
            is_oneshot = (strcmp(val, "true") == 0 || strcmp(val, "1") == 0);
        } else if (strcmp(p, "critical") == 0) {
            is_critical = (strcmp(val, "true") == 0 || strcmp(val, "1") == 0);
        }
    }
    fclose(f);

    if (name[0] && command[0]) {
        add_service(name, command, after, restart, is_oneshot, is_critical);
    }
}

static void load_service_definitions(void) {
    DIR *dir = opendir(SERVICE_DIR);
    if (dir) {
        struct dirent *ent;
        while ((ent = readdir(dir))) {
            if (ent->d_name[0] == '.') continue;
            size_t len = strlen(ent->d_name);
            if (len > 5 && strcmp(ent->d_name + len - 5, ".conf") == 0) {
                char fullpath[512];
                snprintf(fullpath, sizeof(fullpath), "%s/%s", SERVICE_DIR, ent->d_name);
                load_service_file(fullpath);
            }
        }
        closedir(dir);
    }

    if (num_services == 0) {
        log_info(NULL, "No service files in /etc/services.d; loading built-in default services");
        add_service("hostname", "hostname $(cat /etc/hostname 2>/dev/null || echo shreeos)", NULL, RESTART_NEVER, true, false);
        add_service("network", "ip link set lo up 2>/dev/null || ifconfig lo 127.0.0.1 up 2>/dev/null", "hostname", RESTART_NEVER, true, false);
        add_service("console", "/bin/bash --login", "network", RESTART_ALWAYS, false, true);
    }
}

static int start_service(service_t *s) {
    if (!s || s->state == SVC_RUNNING || s->state == SVC_STARTING) return 0;

    if (s->after[0]) {
        service_t *dep = find_service(s->after);
        if (dep) {
            if (dep->state != SVC_RUNNING && dep->state != SVC_STOPPED) {
                return -1;
            }
        }
    }

    char log_buf[128];
    snprintf(log_buf, sizeof(log_buf), "Starting service (command: %s)", s->command);
    log_info(s->name, log_buf);

    s->state = SVC_STARTING;
    s->last_start = time(NULL);

    pid_t pid = fork();
    if (pid < 0) {
        log_error(s->name, "fork failed");
        s->state = SVC_FAILED;
        return -1;
    }

    if (pid == 0) {
        setsid();
        setpgid(0, 0);

        /* Set up log output */
        mkdir("/var/log", 0755);
        mkdir("/var/log/shreeos", 0755);
        mkdir(LOG_DIR, 0755);

        if (strcmp(s->name, "console") == 0 || strcmp(s->name, "getty") == 0) {
            int fd = open("/dev/console", O_RDWR);
            if (fd >= 0) {
                dup2(fd, STDIN_FILENO);
                dup2(fd, STDOUT_FILENO);
                dup2(fd, STDERR_FILENO);
                if (fd > 2) close(fd);
            }
        } else {
            char log_path[256];
            snprintf(log_path, sizeof(log_path), "%s/%s.log", LOG_DIR, s->name);
            int fd = open(log_path, O_WRONLY | O_CREAT | O_APPEND, 0640);
            if (fd >= 0) {
                dup2(fd, STDOUT_FILENO);
                dup2(fd, STDERR_FILENO);
                if (fd > 2) close(fd);
            }
        }

        sigset_t set;
        sigemptyset(&set);
        sigprocmask(SIG_SETMASK, &set, NULL);

        execl("/bin/sh", "sh", "-c", s->command, NULL);
        fprintf(stderr, "[init:fail] [%s] exec failed: %s\n", s->name, strerror(errno));
        _exit(127);
    }

    s->pid = pid;
    s->state = SVC_RUNNING;
    return 0;
}

static void stop_service(service_t *s, int sig) {
    if (!s || s->state != SVC_RUNNING || s->pid <= 0) return;

    char msg[64];
    snprintf(msg, sizeof(msg), "Stopping service PID %d with signal %d", s->pid, sig);
    log_info(s->name, msg);

    s->state = SVC_STOPPING;
    kill(-s->pid, sig); /* Kill process group */
    kill(s->pid, sig);
}

static void restart_service(service_t *s) {
    if (!s) return;
    if (s->state == SVC_RUNNING) {
        stop_service(s, SIGTERM);
        usleep(200000);
        if (s->state == SVC_STOPPING && s->pid > 0) {
            stop_service(s, SIGKILL);
        }
    }
    s->state = SVC_STOPPED;
    s->restart_count = 0;
    start_service(s);
}

static void reap_children(void) {
    int status;
    pid_t pid;

    while ((pid = waitpid(-1, &status, WNOHANG)) > 0) {
        service_t *s = find_service_by_pid(pid);
        if (s) {
            s->pid = 0;
            s->last_exit = time(NULL);
            s->last_exit_status = WIFEXITED(status) ? WEXITSTATUS(status) : -WTERMSIG(status);

            char msg[128];
            snprintf(msg, sizeof(msg), "Service exited with code %d", s->last_exit_status);
            log_info(s->name, msg);

            if (s->is_oneshot) {
                s->state = (s->last_exit_status == 0) ? SVC_STOPPED : SVC_FAILED;
            } else if (s->state == SVC_STOPPING) {
                s->state = SVC_STOPPED;
            } else {
                if (s->restart == RESTART_ALWAYS ||
                    (s->restart == RESTART_ON_FAILURE && s->last_exit_status != 0)) {
                    s->state = SVC_FAILED;
                    s->restart_count++;
                } else {
                    s->state = SVC_STOPPED;
                }
            }
        }
    }
}

static void supervise_services(void) {
    time_t now = time(NULL);

    for (int i = 0; i < num_services; i++) {
        service_t *s = &services[i];

        if (s->state == SVC_STOPPED && !s->is_oneshot && s->restart == RESTART_ALWAYS) {
            start_service(s);
        } else if (s->state == SVC_FAILED && (s->restart == RESTART_ALWAYS || s->restart == RESTART_ON_FAILURE)) {
            if (now - s->last_exit >= 2) {
                start_service(s);
            }
        } else if (s->state == SVC_STOPPED && s->is_oneshot && s->last_start == 0) {
            start_service(s);
        }
    }
}

static void init_ipc_socket(void) {
    unlink(INIT_SOCK_PATH);
    ipc_sock_fd = socket(AF_UNIX, SOCK_STREAM | SOCK_NONBLOCK, 0);
    if (ipc_sock_fd < 0) return;

    struct sockaddr_un addr;
    memset(&addr, 0, sizeof(addr));
    addr.sun_family = AF_UNIX;
    strncpy(addr.sun_path, INIT_SOCK_PATH, sizeof(addr.sun_path) - 1);

    if (bind(ipc_sock_fd, (struct sockaddr *)&addr, sizeof(addr)) == 0) {
        chmod(INIT_SOCK_PATH, 0660);
        listen(ipc_sock_fd, 8);
    } else {
        close(ipc_sock_fd);
        ipc_sock_fd = -1;
    }
}

static void handle_ipc_connections(void) {
    if (ipc_sock_fd < 0) return;

    int client_fd = accept(ipc_sock_fd, NULL, NULL);
    if (client_fd < 0) return;

    char req[256] = {0};
    ssize_t n = read(client_fd, req, sizeof(req) - 1);
    if (n <= 0) { close(client_fd); return; }

    char res[4096] = {0};
    char *cmd = req;
    while (*cmd == ' ' || *cmd == '\n' || *cmd == '\r') cmd++;
    char *nl = strchr(cmd, '\n'); if (nl) *nl = '\0';
    char *cr = strchr(cmd, '\r'); if (cr) *cr = '\0';

    if (strncmp(cmd, "LIST", 4) == 0) {
        char *p = res;
        size_t rem = sizeof(res);
        p += snprintf(p, rem, "%-16s %-10s %-8s %s\n", "SERVICE", "STATE", "PID", "COMMAND");
        for (int i = 0; i < num_services; i++) {
            rem = sizeof(res) - (p - res);
            if (rem < 80) break;
            p += snprintf(p, rem, "%-16s %-10s %-8d %s\n",
                          services[i].name, state_to_str(services[i].state),
                          services[i].pid, services[i].command);
        }
    } else if (strncmp(cmd, "START ", 6) == 0) {
        char *target = cmd + 6;
        service_t *s = find_service(target);
        if (s) {
            start_service(s);
            snprintf(res, sizeof(res), "OK: Started service '%s'\n", target);
        } else {
            snprintf(res, sizeof(res), "ERROR: Service '%s' not found\n", target);
        }
    } else if (strncmp(cmd, "STOP ", 5) == 0) {
        char *target = cmd + 5;
        service_t *s = find_service(target);
        if (s) {
            stop_service(s, SIGTERM);
            snprintf(res, sizeof(res), "OK: Stopped service '%s'\n", target);
        } else {
            snprintf(res, sizeof(res), "ERROR: Service '%s' not found\n", target);
        }
    } else if (strncmp(cmd, "RESTART ", 8) == 0) {
        char *target = cmd + 8;
        service_t *s = find_service(target);
        if (s) {
            restart_service(s);
            snprintf(res, sizeof(res), "OK: Restarted service '%s'\n", target);
        } else {
            snprintf(res, sizeof(res), "ERROR: Service '%s' not found\n", target);
        }
    } else if (strncmp(cmd, "STATUS ", 7) == 0) {
        char *target = cmd + 7;
        service_t *s = find_service(target);
        if (s) {
            snprintf(res, sizeof(res), "Service: %s\nState:   %s\nPID:     %d\nRestarts: %d\nExitCode: %d\nCommand: %s\n",
                     s->name, state_to_str(s->state), s->pid, s->restart_count, s->last_exit_status, s->command);
        } else {
            snprintf(res, sizeof(res), "ERROR: Service '%s' not found\n", target);
        }
    } else if (strncmp(cmd, "RELOAD", 6) == 0) {
        load_service_definitions();
        snprintf(res, sizeof(res), "OK: Service configuration reloaded\n");
    } else {
        snprintf(res, sizeof(res), "ERROR: Unknown IPC command\n");
    }

    write(client_fd, res, strlen(res));
    close(client_fd);
}

static void perform_shutdown(void) {
    log_info(NULL, "Initiating system shutdown sequence...");
    unlink(INIT_SOCK_PATH);

    for (int i = num_services - 1; i >= 0; i--) {
        if (services[i].state == SVC_RUNNING) {
            stop_service(&services[i], SIGTERM);
        }
    }

    for (int i = 0; i < 30; i++) {
        reap_children();
        bool any_running = false;
        for (int j = 0; j < num_services; j++) {
            if (services[j].state == SVC_RUNNING || services[j].state == SVC_STOPPING) {
                any_running = true;
                break;
            }
        }
        if (!any_running) break;
        usleep(100000);
    }

    kill(-1, SIGTERM);
    sync();
    sleep(1);

    kill(-1, SIGKILL);
    sleep(1);

    sync();
    mount(NULL, "/", NULL, MS_REMOUNT | MS_RDONLY, NULL);

    if (shutdown_mode == 1) {
        reboot(RB_POWER_OFF);
    } else if (shutdown_mode == 2) {
        reboot(RB_HALT_SYSTEM);
    } else {
        reboot(RB_AUTOBOOT);
    }
}

int main(void) {
    if (getpid() != 1) {
        fprintf(stderr, "init: must be run as PID 1\n");
        return 1;
    }

    struct sigaction sa;
    memset(&sa, 0, sizeof(sa));
    sa.sa_handler = handle_signal;
    sigaction(SIGCHLD, &sa, NULL);
    sigaction(SIGTERM, &sa, NULL);
    sigaction(SIGINT,  &sa, NULL);
    sigaction(SIGUSR1, &sa, NULL);
    sigaction(SIGUSR2, &sa, NULL);
    sigaction(SIGHUP,  &sa, NULL);

    printf("\n");
    printf("=========================================\n");
    printf("  ShreeOS Init System (PID 1 Supervisor) \n");
    printf("  ShreeOS init: reached PID 1            \n");
    printf("=========================================\n\n");

    mount_essential_filesystems();
    load_service_definitions();
    init_ipc_socket();

    for (int i = 0; i < num_services; i++) {
        start_service(&services[i]);
    }

    log_info(NULL, "Supervisor main loop active.");

    while (!shutdown_requested) {
        if (sigchld_received) {
            sigchld_received = 0;
            reap_children();
        }

        if (reload_requested) {
            reload_requested = 0;
            log_info(NULL, "Reloading service configuration...");
            load_service_definitions();
        }

        handle_ipc_connections();
        supervise_services();

        struct timespec req = { .tv_sec = 0, .tv_nsec = 250000000 }; /* 250ms event tick */
        nanosleep(&req, NULL);
    }

    perform_shutdown();
    return 0;
}
