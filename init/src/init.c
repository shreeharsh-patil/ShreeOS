/*
 * init/src/init.c — ShreeOS minimal PID 1
 *
 * Mounts essential filesystems, prints a boot marker,
 * spawns a shell on the console, and handles reboot.
 *
 * Compile: x86_64-shreeos-linux-gnu-gcc -static -Os -o init init.c
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

static volatile sig_atomic_t shutdown_requested = 0;

static void handle_signal(int sig)
{
    (void)sig;
    shutdown_requested = 1;
}

static int mount_fs(const char *source, const char *target,
                    const char *type, unsigned long flags)
{
    if (mount(source, target, type, flags, NULL) < 0) {
        fprintf(stderr, "init: failed to mount %s on %s: %s\n",
                source, target, strerror(errno));
        return -1;
    }
    return 0;
}

int main(void)
{
    /* Set up signal handlers for clean shutdown */
    struct sigaction sa;
    memset(&sa, 0, sizeof(sa));
    sa.sa_handler = handle_signal;
    sigaction(SIGTERM, &sa, NULL);
    sigaction(SIGINT,  &sa, NULL);

    printf("ShreeOS init: reached PID 1\n");

    /* Mount essential virtual filesystems */
    mount_fs("proc",  "/proc",  "proc",  0);
    mount_fs("sysfs", "/sys",   "sysfs", 0);
    mount_fs("devtmpfs", "/dev", "devtmpfs", 0);

    /* Mount /dev/pts if available */
    mkdir("/dev/pts", 0755);
    mount_fs("devpts", "/dev/pts", "devpts", 0);

    printf("ShreeOS init: filesystems mounted, starting shell\n");

    /* Main loop: keep respawning a shell */
    while (!shutdown_requested) {
        pid_t pid = fork();
        if (pid < 0) {
            fprintf(stderr, "init: fork failed: %s\n", strerror(errno));
            sleep(1);
            continue;
        }

        if (pid == 0) {
            /* Child: become session leader and exec shell */
            setsid();

            /* Open console as stdin/stdout/stderr */
            int fd = open("/dev/console", O_RDWR);
            if (fd >= 0) {
                dup2(fd, STDIN_FILENO);
                dup2(fd, STDOUT_FILENO);
                dup2(fd, STDERR_FILENO);
                if (fd > 2) close(fd);
            }

            execl("/bin/bash", "bash", "--login", NULL);
            execl("/bin/sh", "sh", NULL);
            fprintf(stderr, "init: no shell found, halting\n");
            _exit(1);
        }

        /* Parent: wait for child to exit, then respawn */
        int status;
        waitpid(pid, &status, 0);
        printf("init: shell exited (status %d), respawning\n", WEXITSTATUS(status));
    }

    /* Shutdown requested: reboot */
    printf("init: shutting down\n");
    sync();
    reboot(RB_AUTOBOOT);
    return 0;
}
