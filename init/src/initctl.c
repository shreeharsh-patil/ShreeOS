/*
 * init/src/initctl.c — ShreeOS Init Control Utility
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

#define INIT_SOCK_PATH "/run/init.sock"

static int send_ipc_command(const char *cmd, char *out, size_t out_len) {
    int fd = socket(AF_UNIX, SOCK_STREAM, 0);
    if (fd < 0) return -1;

    struct sockaddr_un addr;
    memset(&addr, 0, sizeof(addr));
    addr.sun_family = AF_UNIX;
    strncpy(addr.sun_path, INIT_SOCK_PATH, sizeof(addr.sun_path) - 1);

    if (connect(fd, (struct sockaddr *)&addr, sizeof(addr)) != 0) {
        close(fd);
        return -1;
    }

    write(fd, cmd, strlen(cmd));
    write(fd, "\n", 1);

    ssize_t n = read(fd, out, out_len - 1);
    if (n >= 0) out[n] = '\0';
    else out[0] = '\0';

    close(fd);
    return 0;
}

static void usage(void) {
    fprintf(stderr,
        "initctl — ShreeOS Service & Init Controller\n"
        "Usage:\n"
        "  initctl list               List running and supervised services\n"
        "  initctl status [service]   Check service status / init supervisor health\n"
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
    char resp[4096] = {0};

    if (strcmp(cmd, "list") == 0) {
        if (send_ipc_command("LIST", resp, sizeof(resp)) == 0) {
            printf("%s", resp);
            return 0;
        } else {
            fprintf(stderr, "initctl: could not connect to init socket at %s\n", INIT_SOCK_PATH);
            return 1;
        }
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
        } else if (kill(1, 0) == 0) {
            printf("initctl: PID 1 is running (socket IPC unavailable)\n");
            return 0;
        } else {
            fprintf(stderr, "initctl: PID 1 not reachable: %s\n", strerror(errno));
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
        return kill(1, SIGTERM) == 0 ? 0 : 1;
    } else if (strcmp(cmd, "poweroff") == 0) {
        printf("initctl: requesting system poweroff...\n");
        return kill(1, SIGUSR1) == 0 ? 0 : 1;
    } else if (strcmp(cmd, "halt") == 0) {
        printf("initctl: requesting system halt...\n");
        return kill(1, SIGUSR2) == 0 ? 0 : 1;
    }

    fprintf(stderr, "initctl: unknown command '%s'\n\n", cmd);
    usage();
    return 1;
}
