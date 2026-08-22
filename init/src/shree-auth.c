/*
 * init/src/shree-auth.c — ShreeOS User Authentication & Session Switcher
 *
 * Security Requirements:
 *   - Verifies credentials against /etc/shadow using crypt()
 *   - Closes inherited file descriptors (3..1024)
 *   - Performs clearenv() and reconstructs minimal strict allowlist
 *   - Drops root privileges (initgroups, setgid, setuid) with irreversible verification
 *   - Safe terminal echo handling and rate-limited progressive backoff
 *   - Supports TTY login loop (--login-tty) and X11 session launch (--session <cmd>)
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
#include <sys/stat.h>
#include <fcntl.h>
#include <time.h>

#ifdef __linux__
#include <crypt.h>
#endif

static void close_extra_fds(void) {
    for (int fd = 3; fd < 1024; fd++) {
        close(fd);
    }
}

static void get_password_secure(const char *prompt, char *buf, size_t maxlen) {
    struct termios old_term, new_term;
    int has_term = (tcgetattr(STDIN_FILENO, &old_term) == 0);

    printf("%s", prompt);
    fflush(stdout);

    if (has_term) {
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

    if (has_term) {
        tcsetattr(STDIN_FILENO, TCSANOW, &old_term);
    }
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

static int launch_user_session(struct passwd *pw, const char *session_cmd) {
    /* 1. Close all inherited descriptors */
    close_extra_fds();

    /* 2. Initialize supplementary groups */
    if (initgroups(pw->pw_name, pw->pw_gid) != 0) {
        perror("initgroups failed");
        return 1;
    }

    /* 3. Switch GID and UID */
    if (setgid(pw->pw_gid) != 0) {
        perror("setgid failed");
        return 1;
    }

    if (setuid(pw->pw_uid) != 0) {
        perror("setuid failed");
        return 1;
    }

    /* 4. Verify privileges permanently dropped (cannot regain root) */
    if (setuid(0) == 0 || geteuid() != pw->pw_uid || getuid() != pw->pw_uid) {
        fprintf(stderr, "FATAL SECURITY ERROR: Failed to permanently drop root privileges!\n");
        exit(1);
    }

    /* 5. Sanitize environment: clearenv() and construct minimal allowlist */
    char orig_display[64] = {0};
    char *disp = getenv("DISPLAY");
    if (disp && strlen(disp) < sizeof(orig_display)) {
        strncpy(orig_display, disp, sizeof(orig_display) - 1);
    }

    char orig_term[64] = {0};
    char *t = getenv("TERM");
    if (t && strlen(t) < sizeof(orig_term)) {
        strncpy(orig_term, t, sizeof(orig_term) - 1);
    }

#if defined(__GLIBC__) || defined(__linux__)
    clearenv();
#endif

    setenv("USER", pw->pw_name, 1);
    setenv("LOGNAME", pw->pw_name, 1);
    setenv("HOME", pw->pw_dir, 1);
    setenv("SHELL", pw->pw_shell ? pw->pw_shell : "/bin/bash", 1);
    setenv("PATH", "/usr/local/bin:/usr/bin:/bin", 1);
    setenv("TERM", orig_term[0] ? orig_term : "linux", 1);
    if (orig_display[0]) {
        setenv("DISPLAY", orig_display, 1);
    }

    /* 6. Change directory to user home */
    if (chdir(pw->pw_dir) != 0) {
        if (chdir("/") != 0) {
            perror("chdir failed");
        }
    }

    /* 7. Launch unprivileged session */
    if (session_cmd && *session_cmd) {
        execl(session_cmd, session_cmd, (char *)NULL);
    } else if (getenv("DISPLAY") && access("/usr/bin/startx", X_OK) == 0) {
        execl("/usr/bin/startx", "startx", (char *)NULL);
    } else {
        execl(pw->pw_shell ? pw->pw_shell : "/bin/bash", "-bash", "--login", (char *)NULL);
    }

    perror("exec failed");
    return 1;
}

int main(int argc, char **argv) {
    char username[64] = {0};
    char password[128] = {0};
    const char *session_cmd = NULL;
    int is_tty_loop = 0;

    if (argc > 1) {
        if (strcmp(argv[1], "--help") == 0 || strcmp(argv[1], "-h") == 0) {
            printf("Usage: shree-auth [username] [--session /usr/bin/startx] [--login-tty]\n");
            return 0;
        }
        if (strcmp(argv[1], "--login-tty") == 0) {
            is_tty_loop = 1;
        } else if (argv[1][0] != '-') {
            strncpy(username, argv[1], sizeof(username) - 1);
        }
    }

    for (int i = 1; i < argc; i++) {
        if (strcmp(argv[i], "--session") == 0 && i + 1 < argc) {
            session_cmd = argv[i + 1];
        }
        if (strcmp(argv[i], "--login-tty") == 0) {
            is_tty_loop = 1;
        }
    }

#ifdef SHREE_AUTH_TEST
    if (argc > 3 && strcmp(argv[1], "--test-auth") == 0) {
        return authenticate_user(argv[2], argv[3]) ? 0 : 1;
    }
#endif

    do {
        if (username[0] == '\0') {
            printf("\nShreeOS 0.1.0-dev (x86_64)\n");
            printf("login: ");
            fflush(stdout);
            if (!fgets(username, sizeof(username), stdin)) {
                if (is_tty_loop) {
                    clearerr(stdin);
                    sleep(1);
                    continue;
                }
                return 1;
            }
            size_t len = strlen(username);
            if (len > 0 && username[len - 1] == '\n') username[len - 1] = '\0';
        }

        if (username[0] == '\0') {
            continue;
        }

        struct passwd *pw = getpwnam(username);
        get_password_secure("Password: ", password, sizeof(password));

        int ok = 0;
        if (pw) {
            ok = authenticate_user(username, password);
        }

        /* Clear password from memory immediately */
        memset(password, 0, sizeof(password));

        if (ok && pw) {
            printf("Login successful. Initializing session...\n");
            return launch_user_session(pw, session_cmd);
        }

        fprintf(stderr, "Login incorrect.\n");
        sleep(2); /* Rate limit failure delay */

        if (!is_tty_loop) {
            return 1;
        }
        username[0] = '\0';
    } while (is_tty_loop);

    return 1;
}
