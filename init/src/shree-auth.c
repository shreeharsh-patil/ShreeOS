/*
 * init/src/shree-auth.c — ShreeOS User Authentication & Session Switcher
 *
 * Verifies credentials against /etc/shadow, rate-limits failures,
 * initializes groups, drops UID/GID, sanitizes the environment,
 * and launches the user's desktop session unprivileged.
 */

#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <pwd.h>
#include <shadow.h>
#include <grp.h>
#include <termios.h>
#include <errno.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <time.h>

#ifdef __linux__
#include <crypt.h>
#endif

static void get_password(const char *prompt, char *buf, size_t maxlen) {
    struct termios old_term, new_term;
    printf("%s", prompt);
    fflush(stdout);

    if (tcgetattr(STDIN_FILENO, &old_term) == 0) {
        new_term = old_term;
        new_term.c_lflag &= ~(ECHO | ECHOE | ECHOK | ECHONL);
        tcsetattr(STDIN_FILENO, TCSANOW, &new_term);
    }

    if (fgets(buf, maxlen, stdin) != NULL) {
        size_t len = strlen(buf);
        if (len > 0 && buf[len - 1] == '\n') {
            buf[len - 1] = '\0';
        }
    } else {
        buf[0] = '\0';
    }

    tcsetattr(STDIN_FILENO, TCSANOW, &old_term);
    printf("\n");
}

int authenticate_user(const char *username, const char *password) {
    if (!username || !password || username[0] == '\0') {
        return 0;
    }

    struct passwd *pw = getpwnam(username);
    if (!pw) {
        return 0;
    }

    const char *hash = pw->pw_passwd;

    /* If /etc/passwd has 'x', read hash from /etc/shadow */
    if (strcmp(hash, "x") == 0) {
        struct spwd *sp = getspnam(username);
        if (!sp) {
            return 0;
        }
        hash = sp->sp_pwdp;
    }

    if (!hash || hash[0] == '\0' || hash[0] == '!' || hash[0] == '*') {
        return 0;
    }

    char *computed = crypt(password, hash);
    if (!computed) {
        return 0;
    }

    return (strcmp(computed, hash) == 0) ? 1 : 0;
}

int main(int argc, char **argv) {
    char username[64] = {0};
    char password[128] = {0};
    int attempts = 0;
    const int max_attempts = 3;

    if (argc > 1 && (strcmp(argv[1], "--help") == 0 || strcmp(argv[1], "-h") == 0)) {
        printf("Usage: shree-auth [username] [--session /usr/bin/startx]\n");
        return 0;
    }

    if (argc > 1 && strcmp(argv[1], "--check-lock") == 0) {
        return 0; /* locker capability supported */
    }

    if (argc > 1 && strcmp(argv[1], "--test") == 0 && argc > 3) {
        /* Test-only authentication mode */
        return authenticate_user(argv[2], argv[3]) ? 0 : 1;
    }

    if (argc > 1 && argv[1][0] != '-') {
        strncpy(username, argv[1], sizeof(username) - 1);
    } else {
        printf("ShreeOS Login\nUsername: ");
        fflush(stdout);
        if (!fgets(username, sizeof(username), stdin)) {
            return 1;
        }
        size_t len = strlen(username);
        if (len > 0 && username[len - 1] == '\n') username[len - 1] = '\0';
    }

    struct passwd *pw = getpwnam(username);
    if (!pw) {
        fprintf(stderr, "User '%s' not found.\n", username);
        return 1;
    }

    while (attempts < max_attempts) {
        attempts++;
        get_password("Password: ", password, sizeof(password));

        if (authenticate_user(username, password)) {
            /* Clear password buffer from memory */
            memset(password, 0, sizeof(password));
            printf("Authentication successful. Initializing session for %s...\n", username);

            /* 1. Initialize supplementary groups */
            if (initgroups(pw->pw_name, pw->pw_gid) != 0) {
                perror("initgroups failed");
                return 1;
            }

            /* 2. Switch GID & UID */
            if (setgid(pw->pw_gid) != 0) {
                perror("setgid failed");
                return 1;
            }

            if (setuid(pw->pw_uid) != 0) {
                perror("setuid failed");
                return 1;
            }

            /* 3. Sanitize and export user environment */
            setenv("USER", pw->pw_name, 1);
            setenv("LOGNAME", pw->pw_name, 1);
            setenv("HOME", pw->pw_dir, 1);
            setenv("SHELL", pw->pw_shell ? pw->pw_shell : "/bin/bash", 1);
            setenv("PATH", "/usr/local/bin:/usr/bin:/bin", 1);

            /* 4. chdir to home */
            if (chdir(pw->pw_dir) != 0) {
                if (chdir("/") != 0) {
                    perror("chdir failed");
                }
            }

            /* 5. Launch user desktop or shell */
            if (fork() == 0) {
                if (argc > 2 && strcmp(argv[2], "--session") == 0 && argc > 3) {
                    execl(argv[3], argv[3], (char *)NULL);
                } else if (access("/usr/bin/startx", X_OK) == 0) {
                    execl("/usr/bin/startx", "startx", (char *)NULL);
                } else {
                    execl(pw->pw_shell, pw->pw_shell, "--login", (char *)NULL);
                }
                perror("exec failed");
                exit(1);
            }

            int status;
            wait(&status);
            return WIFEXITED(status) ? WEXITSTATUS(status) : 0;
        }

        fprintf(stderr, "Authentication failure. (Attempt %d of %d)\n", attempts, max_attempts);
        sleep(attempts * 1); /* Progressive rate limiting */
    }

    fprintf(stderr, "Maximum authentication attempts exceeded. Session locked.\n");
    return 1;
}
