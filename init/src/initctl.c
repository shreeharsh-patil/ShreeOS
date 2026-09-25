/*
 * init/src/initctl.c — ShreeOS Init Control Utility (V2)
 *
 * Communicates with PID 1 via Unix domain socket IPC (/run/init.sock)
 * and fallback control signals. Returns non-zero on command failure.
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <signal.h>
#include <unistd.h>
#include <errno.h>
#include <sys/socket.h>
#include <sys/un.h>

#define DEFAULT_INIT_SOCK_PATH "/run/init.sock"

static const char *get_sock_path(void) {
    const char *env = getenv("INIT_SOCK_PATH");
    if (env && *env) return env;
    return DEFAULT_INIT_SOCK_PATH;
}

static int write_all(int fd, const char *buf, size_t len) {
    size_t written = 0;
    while (written < len) {
        ssize_t n = write(fd, buf + written, len - written);
        if (n > 0) {
            written += (size_t)n;
            continue;
        }
        if (n < 0 && errno == EINTR) continue;
        return -1;
    }
    return 0;
}

static int send_ipc_command(const char *cmd, char *out, size_t out_len) {
    if (!cmd || !out || out_len < 2) {
        errno = EINVAL;
        return -1;
    }

    int fd = socket(AF_UNIX, SOCK_STREAM, 0);
    if (fd < 0) return -1;

    struct sockaddr_un addr;
    memset(&addr, 0, sizeof(addr));
    addr.sun_family = AF_UNIX;

    const char *sock_path = get_sock_path();
    size_t sock_len = strlen(sock_path);
    if (sock_len >= sizeof(addr.sun_path)) {
        close(fd);
        errno = ENAMETOOLONG;
        return -1;
    }
    memcpy(addr.sun_path, sock_path, sock_len + 1);

    if (connect(fd, (struct sockaddr *)&addr, sizeof(addr)) != 0) {
        int saved_errno = errno;
        close(fd);
        errno = saved_errno;
        return -1;
    }

    if (write_all(fd, cmd, strlen(cmd)) != 0 || write_all(fd, "\n", 1) != 0) {
        int saved_errno = errno;
        close(fd);
        errno = saved_errno;
        return -1;
    }

    (void)shutdown(fd, SHUT_WR);

    size_t used = 0;
    while (used < out_len - 1) {
        ssize_t n = read(fd, out + used, out_len - 1 - used);
        if (n > 0) {
            used += (size_t)n;
            continue;
        }
        if (n == 0) break;
        if (errno == EINTR) continue;

        int saved_errno = errno;
        close(fd);
        out[used] = '\0';
        errno = saved_errno;
        return -1;
    }

    out[used] = '\0';

    if (used == out_len - 1) {
        char extra;
        ssize_t n;
        do {
            n = read(fd, &extra, 1);
        } while (n < 0 && errno == EINTR);

        if (n > 0) {
            close(fd);
            errno = EMSGSIZE;
            return -1;
        }
        if (n < 0) {
            int saved_errno = errno;
            close(fd);
            errno = saved_errno;
            return -1;
        }
    }

    close(fd);
    return 0;
}

static void usage(void) {
    fprintf(stderr,
        "initctl — ShreeOS Service & Init Controller (V2)\n"
        "Usage:\n"
        "  initctl list               List running and supervised services\n"
        "  initctl status [service]   Check service status / init supervisor health\n"
        "  initctl blame              Show boot duration timeline for services\n"
        "  initctl logs <service>     Display recent output logs for a service\n"
        "  initctl start <service>    Start a service\n"
        "  initctl stop <service>     Stop a running service\n"
        "  initctl restart <service>  Restart a service\n"
        "  initctl reload             Reload service descriptors from /etc/services.d\n"
        "  initctl reboot             Reboot system cleanly\n"
        "  initctl poweroff           Power off system\n"
        "  initctl halt               Halt system\n"
    );
}

int main(int argc, char **argv) {
    if (argc < 2) { usage(); return 1; }

    const char *cmd = argv[1];
    char resp[32768] = {0};

    if (strcmp(cmd, "list") == 0) {
        if (send_ipc_command("LIST", resp, sizeof(resp)) == 0) {
            printf("%s", resp);
            return 0;
        } else {
            fprintf(stderr, "initctl: IPC request failed at %s: %s\n", get_sock_path(), strerror(errno));
            return 1;
        }
    } else if (strcmp(cmd, "blame") == 0) {
        if (send_ipc_command("BLAME", resp, sizeof(resp)) == 0) {
            printf("%s", resp);
            return 0;
        } else {
            fprintf(stderr, "initctl: IPC request failed at %s: %s\n", get_sock_path(), strerror(errno));
            return 1;
        }
    } else if (strcmp(cmd, "logs") == 0) {
        if (argc < 3) { fprintf(stderr, "Usage: initctl logs <service>\n"); return 1; }
        char req[128]; snprintf(req, sizeof(req), "LOGS %s", argv[2]);
        if (send_ipc_command(req, resp, sizeof(resp)) == 0) {
            printf("%s", resp);
            return (strncmp(resp, "ERROR", 5) == 0) ? 1 : 0;
        }
        return 1;
    } else if (strcmp(cmd, "start") == 0) {
        if (argc < 3) { fprintf(stderr, "Usage: initctl start <service>\n"); return 1; }
        char req[128]; snprintf(req, sizeof(req), "START %s", argv[2]);
        if (send_ipc_command(req, resp, sizeof(resp)) == 0) {
            printf("%s", resp);
            return (strncmp(resp, "ERROR", 5) == 0) ? 1 : 0;
        }
        return 1;
    } else if (strcmp(cmd, "stop") == 0) {
        if (argc < 3) { fprintf(stderr, "Usage: initctl stop <service>\n"); return 1; }
        char req[128]; snprintf(req, sizeof(req), "STOP %s", argv[2]);
        if (send_ipc_command(req, resp, sizeof(resp)) == 0) {
            printf("%s", resp);
            return (strncmp(resp, "ERROR", 5) == 0) ? 1 : 0;
        }
        return 1;
    } else if (strcmp(cmd, "restart") == 0) {
        if (argc < 3) { fprintf(stderr, "Usage: initctl restart <service>\n"); return 1; }
        char req[128]; snprintf(req, sizeof(req), "RESTART %s", argv[2]);
        if (send_ipc_command(req, resp, sizeof(resp)) == 0) {
            printf("%s", resp);
            return (strncmp(resp, "ERROR", 5) == 0) ? 1 : 0;
        }
        return 1;
    } else if (strcmp(cmd, "status") == 0) {
        if (argc >= 3) {
            char req[128]; snprintf(req, sizeof(req), "STATUS %s", argv[2]);
            if (send_ipc_command(req, resp, sizeof(resp)) == 0) {
                printf("%s", resp);
                return (strncmp(resp, "ERROR", 5) == 0) ? 1 : 0;
            }
        }
        if (send_ipc_command("LIST", resp, sizeof(resp)) == 0) {
            printf("initctl: PID 1 active. Supervised services:\n\n%s", resp);
            return 0;
        } else {
            fprintf(stderr, "initctl: PID 1 socket IPC unavailable: %s\n", strerror(errno));
            return 1;
        }
    } else if (strcmp(cmd, "reload") == 0) {
        if (send_ipc_command("RELOAD", resp, sizeof(resp)) == 0) {
            printf("%s", resp);
            return (strncmp(resp, "ERROR", 5) == 0) ? 1 : 0;
        }
        if (kill(1, SIGHUP) == 0) {
            printf("initctl: sent SIGHUP reload signal to PID 1\n");
            return 0;
        }
        return 1;
    } else if (strcmp(cmd, "reboot") == 0) {
        printf("initctl: requesting system reboot...\n");
        if (send_ipc_command("SHUTDOWN REBOOT", resp, sizeof(resp)) == 0) {
            printf("%s", resp);
            return (strncmp(resp, "ERROR", 5) == 0) ? 1 : 0;
        }
        return kill(1, SIGTERM) == 0 ? 0 : 1;
    } else if (strcmp(cmd, "poweroff") == 0) {
        printf("initctl: requesting system poweroff...\n");
        if (send_ipc_command("SHUTDOWN POWEROFF", resp, sizeof(resp)) == 0) {
            printf("%s", resp);
            return (strncmp(resp, "ERROR", 5) == 0) ? 1 : 0;
        }
        return kill(1, SIGUSR1) == 0 ? 0 : 1;
    } else if (strcmp(cmd, "halt") == 0) {
        printf("initctl: requesting system halt...\n");
        if (send_ipc_command("SHUTDOWN HALT", resp, sizeof(resp)) == 0) {
            printf("%s", resp);
            return (strncmp(resp, "ERROR", 5) == 0) ? 1 : 0;
        }
        return kill(1, SIGUSR2) == 0 ? 0 : 1;
    }

    fprintf(stderr, "initctl: unknown command '%s'\n\n", cmd);
    usage();
    return 1;
}
