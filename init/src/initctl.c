/*
 * init/src/initctl.c — ShreeOS Init Control Utility
 *
 * Sends control signals to PID 1 (reboot, poweroff, halt, status).
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <signal.h>
#include <unistd.h>
#include <errno.h>

static void usage(void) {
    fprintf(stderr,
        "initctl — ShreeOS Init System Controller\n"
        "Usage:\n"
        "  initctl status      Check init system status\n"
        "  initctl reboot      Reboot the system\n"
        "  initctl poweroff    Power off the system\n"
        "  initctl halt        Halt the system\n"
    );
}

int main(int argc, char **argv) {
    if (argc < 2) {
        usage();
        return 1;
    }

    const char *cmd = argv[1];

    if (strcmp(cmd, "status") == 0) {
        if (kill(1, 0) == 0) {
            printf("initctl: PID 1 (ShreeOS init) is running\n");
            return 0;
        } else {
            printf("initctl: PID 1 not reachable: %s\n", strerror(errno));
            return 1;
        }
    } else if (strcmp(cmd, "reboot") == 0) {
        printf("initctl: requesting system reboot...\n");
        if (kill(1, SIGTERM) < 0) {
            perror("kill");
            return 1;
        }
        return 0;
    } else if (strcmp(cmd, "poweroff") == 0) {
        printf("initctl: requesting system poweroff...\n");
        if (kill(1, SIGUSR1) < 0) {
            perror("kill");
            return 1;
        }
        return 0;
    } else if (strcmp(cmd, "halt") == 0) {
        printf("initctl: requesting system halt...\n");
        if (kill(1, SIGUSR2) < 0) {
            perror("kill");
            return 1;
        }
        return 0;
    }

    fprintf(stderr, "initctl: unknown command '%s'\n", cmd);
    usage();
    return 1;
}
