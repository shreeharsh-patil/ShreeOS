#define _GNU_SOURCE
#include "shreed.h"

#include <errno.h>
#include <fcntl.h>
#include <stdarg.h>
#include <stdio.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <time.h>
#include <unistd.h>

bool shreed_authorize_peer(int fd) {
#ifdef SO_PEERCRED
    struct ucred credentials;
    socklen_t length = sizeof(credentials);

    if (getsockopt(fd, SOL_SOCKET, SO_PEERCRED, &credentials, &length) != 0) return false;
    return credentials.pid > 0 && credentials.uid != (uid_t)-1 && credentials.gid != (gid_t)-1;
#else
    (void)fd;
    return true;
#endif
}

int shreed_prepare_socket_path(const char *path) {
    struct stat status;

    if (!path || path[0] != '/') {
        errno = EINVAL;
        return -1;
    }
    if (lstat(path, &status) == 0) {
        if (!S_ISSOCK(status.st_mode)) {
            errno = EEXIST;
            return -1;
        }
        return unlink(path);
    }
    return errno == ENOENT ? 0 : -1;
}

int shreed_open_log(const char *path) {
    struct stat status;
    int fd;

    if (!path || path[0] != '/') {
        errno = EINVAL;
        return -1;
    }
    if (strcmp(path, SHREED_LOG_PATH) == 0) {
        if (mkdir("/var/log", 0755) != 0 && errno != EEXIST) return -1;
        if (mkdir("/var/log/shreeos", 0755) != 0 && errno != EEXIST) return -1;
    }

    fd = open(path, O_WRONLY | O_CREAT | O_APPEND | O_CLOEXEC | O_NOFOLLOW, 0640);
    if (fd < 0) return -1;
    if (fstat(fd, &status) != 0 || !S_ISREG(status.st_mode)) {
        close(fd);
        errno = EINVAL;
        return -1;
    }
    if (fchmod(fd, 0640) != 0) {
        close(fd);
        return -1;
    }
    return fd;
}

void shreed_log(int fd, const char *message) {
    char timestamp[32];
    char line[256];
    time_t now;
    struct tm time_info;
    int length;

    if (fd < 0 || !message) return;
    now = time(NULL);
    if (!gmtime_r(&now, &time_info) ||
        strftime(timestamp, sizeof(timestamp), "%Y-%m-%dT%H:%M:%SZ", &time_info) == 0) {
        return;
    }
    length = snprintf(line, sizeof(line), "%s shreed: %s\n", timestamp, message);
    if (length > 0) {
        size_t write_length = (size_t)length;
        if (write_length >= sizeof(line)) write_length = sizeof(line) - 1;
        (void)write(fd, line, write_length);
    }
}
