/*
 * init/src/init.c — ShreeOS PID 1 Service Supervisor & Init System
 *
 * Features:
 *   - Essential virtual filesystem mounting (/proc, /sys, /dev, /run, /dev/pts, /dev/shm)
 *   - Service descriptor parsing (/etc/services.d/*.conf) & default service fallback
 *   - Dependency graph ordering & startup sequencing
 *   - Non-blocking SIGCHLD zombie process reaping (waitpid(-1, WNOHANG))
 *   - Service state machine (STOPPED, STARTING, RUNNING, FAILED, STOPPING)
 *   - Configurable restart policies (always, on-failure, never) with rate-limit backoff
 *   - Multi-stage orderly shutdown: SIGTERM -> wait -> SIGKILL -> sync -> remount ro -> reboot/poweroff/halt
 *   - Structured console & kernel logging
 *
 * Compile:
 *   x86_64-shreeos-linux-gnu-gcc -static -Os -Wall -Wextra -o init init.c
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
#include <signal.h>
#include <string.h>
#include <errno.h>
#include <time.h>
#include <dirent.h>
#include <stdbool.h>

#define MAX_SERVICES 64
#define SERVICE_DIR "/etc/services.d"

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

static volatile sig_atomic_t sigchld_received = 0;
static volatile sig_atomic_t shutdown_requested = 0;
static volatile sig_atomic_t shutdown_mode = 0; /* 0 = reboot, 1 = poweroff, 2 = halt */
static volatile sig_atomic_t reload_requested = 0;

static void log_info(const char *svc, const char *msg) {
    if (svc && *svc) {
        printf("[init] [%s] %s\n", svc, msg);
    } else {
        printf("[init] %s\n", msg);
    }
    fflush(stdout);
}

static void log_warn(const char *svc, const char *msg) {
    if (svc && *svc) {
        fprintf(stderr, "[init:warn] [%s] %s\n", svc, msg);
    } else {
        fprintf(stderr, "[init:warn] %s\n", msg);
    }
    fflush(stderr);
}

static void log_error(const char *svc, const char *msg) {
    if (svc && *svc) {
        fprintf(stderr, "[init:fail] [%s] %s: %s\n", svc, msg, strerror(errno));
    } else {
        fprintf(stderr, "[init:fail] %s: %s\n", msg, strerror(errno));
    }
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

    /* If no service definitions loaded, configure built-in default services */
    if (num_services == 0) {
        log_info(NULL, "No service files in /etc/services.d; loading built-in default services");
        add_service("hostname", "hostname $(cat /etc/hostname 2>/dev/null || echo shreeos)", NULL, RESTART_NEVER, true, false);
        add_service("network", "ip link set lo up 2>/dev/null || ifconfig lo 127.0.0.1 up 2>/dev/null", "hostname", RESTART_NEVER, true, false);
        add_service("console", "/bin/bash --login", "network", RESTART_ALWAYS, false, true);
    }
}

static int start_service(service_t *s) {
    if (!s || s->state == SVC_RUNNING || s->state == SVC_STARTING) return 0;

    /* Check dependency */
    if (s->after[0]) {
        service_t *dep = find_service(s->after);
        if (dep) {
            if (dep->state != SVC_RUNNING && dep->state != SVC_STOPPED) {
                /* Dependency not ready yet */
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
        /* Child process */
        setsid();

        /* Set up console fd if interactive console service */
        if (strcmp(s->name, "console") == 0 || strcmp(s->name, "getty") == 0) {
            int fd = open("/dev/console", O_RDWR);
            if (fd >= 0) {
                dup2(fd, STDIN_FILENO);
                dup2(fd, STDOUT_FILENO);
                dup2(fd, STDERR_FILENO);
                if (fd > 2) close(fd);
            }
        }

        /* Unblock signals for child */
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
    snprintf(msg, sizeof(msg), "Sending signal %d to PID %d", sig, s->pid);
    log_info(s->name, msg);

    s->state = SVC_STOPPING;
    kill(s->pid, sig);
}

/* Non-blocking zombie reaper and supervisor status updater */
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
        } else {
            /* Reaped orphaned zombie from a detached background process */
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
            /* Throttle respawns: minimum 2 second delay between restarts */
            if (now - s->last_exit >= 2) {
                start_service(s);
            }
        } else if (s->state == SVC_STOPPED && s->is_oneshot && s->last_start == 0) {
            start_service(s);
        }
    }
}

/* Orderly multi-stage shutdown */
static void perform_shutdown(void) {
    log_info(NULL, "Initiating system shutdown sequence...");

    /* Stage 1: Stop supervised services in reverse order */
    for (int i = num_services - 1; i >= 0; i--) {
        if (services[i].state == SVC_RUNNING) {
            stop_service(&services[i], SIGTERM);
        }
    }

    /* Wait up to 3 seconds for services to stop gracefully */
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

    /* Stage 2: Send SIGTERM to all other processes */
    log_info(NULL, "Sending SIGTERM to remaining processes...");
    kill(-1, SIGTERM);
    sync();
    sleep(1);

    /* Stage 3: Send SIGKILL to any remaining processes */
    log_info(NULL, "Sending SIGKILL to remaining processes...");
    kill(-1, SIGKILL);
    sleep(1);

    /* Stage 4: Sync filesystems */
    log_info(NULL, "Syncing filesystems...");
    sync();

    /* Stage 5: Remount root filesystem read-only */
    log_info(NULL, "Remounting filesystems read-only...");
    mount(NULL, "/", NULL, MS_REMOUNT | MS_RDONLY, NULL);

    /* Stage 6: Reboot / Poweroff / Halt */
    if (shutdown_mode == 1) {
        log_info(NULL, "Powering off system.");
        reboot(RB_POWER_OFF);
    } else if (shutdown_mode == 2) {
        log_info(NULL, "Halting system.");
        reboot(RB_HALT_SYSTEM);
    } else {
        log_info(NULL, "Rebooting system.");
        reboot(RB_AUTOBOOT);
    }
}

int main(void) {
    if (getpid() != 1) {
        fprintf(stderr, "init: must be run as PID 1\n");
        return 1;
    }

    /* Block signals and set up signal handlers */
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

    /* Initial service startup pass */
    for (int i = 0; i < num_services; i++) {
        start_service(&services[i]);
    }

    log_info(NULL, "Supervisor main loop active.");

    /* Main supervisor loop */
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

        supervise_services();

        /* Sleep briefly waiting for signals */
        struct timespec req = { .tv_sec = 1, .tv_nsec = 0 };
        nanosleep(&req, NULL);
    }

    perform_shutdown();
    return 0;
}
