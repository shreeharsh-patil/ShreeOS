#define _GNU_SOURCE
#include "shreed.h"

#include <arpa/inet.h>
#include <errno.h>
#include <fcntl.h>
#include <grp.h>
#include <pwd.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <sys/un.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>

static int failures;

#define TEST(name, expression) do { \
    if (expression) printf("PASS: %s\n", name); \
    else { fprintf(stderr, "FAIL: %s\n", name); failures++; } \
} while (0)

static int connect_socket(const char *path) {
    struct sockaddr_un address;
    int fd = socket(AF_UNIX, SOCK_STREAM, 0);
    if (fd < 0) return -1;
    memset(&address, 0, sizeof(address));
    address.sun_family = AF_UNIX;
    strcpy(address.sun_path, path);
    if (connect(fd, (struct sockaddr *)&address, sizeof(address)) != 0) {
        close(fd);
        return -1;
    }
    return fd;
}

static int write_all(int fd, const void *buffer, size_t length) {
    const unsigned char *cursor = buffer;
    while (length > 0) {
        ssize_t count = write(fd, cursor, length);
        if (count <= 0) return -1;
        cursor += count;
        length -= (size_t)count;
    }
    return 0;
}

static int read_all(int fd, void *buffer, size_t length) {
    unsigned char *cursor = buffer;
    while (length > 0) {
        ssize_t count = read(fd, cursor, length);
        if (count <= 0) return -1;
        cursor += count;
        length -= (size_t)count;
    }
    return 0;
}

static int exchange(const char *path, const char *request, char *response, size_t response_size) {
    uint32_t length = htonl((uint32_t)strlen(request));
    int fd = connect_socket(path);
    if (fd < 0) return -1;
    if (write_all(fd, &length, sizeof(length)) != 0 || write_all(fd, request, strlen(request)) != 0 ||
        read_all(fd, &length, sizeof(length)) != 0) {
        close(fd);
        return -1;
    }
    length = ntohl(length);
    if (length == 0 || length >= response_size || read_all(fd, response, length) != 0) {
        close(fd);
        return -1;
    }
    response[length] = '\0';
    close(fd);
    return 0;
}

static int wait_for_path(const char *path, bool present) {
    for (int attempt = 0; attempt < 100; attempt++) {
        struct stat status;
        if ((lstat(path, &status) == 0) == present) return 0;
        usleep(10000);
    }
    return -1;
}

static pid_t start_daemon(const char *daemon, const char *socket_path, const char *log_path) {
    pid_t child = fork();
    if (child == 0) {
        if (geteuid() == 0) {
            struct group *hardware = getgrnam("shree-hardware");
            if (!hardware || setgid(hardware->gr_gid) != 0) _exit(126);
        }
        execl(daemon, daemon, "--foreground", "--socket", socket_path, "--log", log_path, (char *)NULL);
        _exit(127);
    }
    return child;
}

static void test_concurrent_connections(const char *socket_path) {
    pid_t children[12];
    int statuses = 0;

    for (size_t index = 0; index < 12; index++) {
        children[index] = fork();
        if (children[index] == 0) {
            char response[SHREED_RESPONSE_MAX + 1];
            _exit(exchange(socket_path, "{\"action\":\"ping\"}", response, sizeof(response)) == 0 &&
                  strstr(response, "\"pong\":true") != NULL ? 0 : 1);
        }
    }
    for (size_t index = 0; index < 12; index++) {
        int status;
        if (children[index] > 0 && waitpid(children[index], &status, 0) > 0 &&
            WIFEXITED(status) && WEXITSTATUS(status) == 0) statuses++;
    }
    TEST("concurrent client requests", statuses == 12);
}

static int reject_unprivileged_peer(const char *socket_path) {
    struct passwd *nobody = getpwnam("nobody");
    pid_t child;
    int status;

    if (!nobody) return 0;
    child = fork();
    if (child < 0) return 0;
    if (child == 0) {
        char response[SHREED_RESPONSE_MAX + 1];
        if (setgroups(0, NULL) != 0 || setgid(nobody->pw_gid) != 0 ||
            setuid(nobody->pw_uid) != 0) {
            _exit(2);
        }
        _exit(exchange(socket_path, "{\"action\":\"ping\"}", response,
                       sizeof(response)) != 0 ? 0 : 1);
    }
    if (waitpid(child, &status, 0) != child || !WIFEXITED(status)) return 0;
    return WEXITSTATUS(status) == 0;
}

static int allow_supplementary_hardware_group_peer(const char *socket_path) {
    struct passwd *nobody = getpwnam("nobody");
    struct group *hardware = getgrnam("shree-hardware");
    pid_t child;
    int status;

    if (!nobody || !hardware) return 0;
    child = fork();
    if (child < 0) return 0;
    if (child == 0) {
        gid_t groups[] = {hardware->gr_gid};
        char response[SHREED_RESPONSE_MAX + 1];
        if (setgroups(1, groups) != 0 || setgid(nobody->pw_gid) != 0 ||
            setuid(nobody->pw_uid) != 0) {
            _exit(2);
        }
        _exit(exchange(socket_path, "{\"action\":\"ping\"}", response,
                       sizeof(response)) == 0 && strstr(response, "\"pong\":true") != NULL ? 0 : 1);
    }
    if (waitpid(child, &status, 0) != child || !WIFEXITED(status)) return 0;
    return WEXITSTATUS(status) == 0;
}

static int rejected_peer_flood_is_coalesced(const char *socket_path, const char *log_path) {
    char line[512];
    int rejection_records = 0;
    FILE *log_file;

    for (int attempt = 0; attempt < 64; attempt++) {
        if (!reject_unprivileged_peer(socket_path)) return 0;
    }
    usleep(100000);
    log_file = fopen(log_path, "r");
    if (!log_file) return 0;
    while (fgets(line, sizeof(line), log_file)) {
        if (strstr(line, "rejected unauthenticated local peer")) rejection_records++;
    }
    fclose(log_file);
    return rejection_records == 1;
}

static int connect_and_hold(const char *socket_path) {
    int fd;

    /* An idle authenticated socket occupies a daemon client slot until closed. */
    for (int attempt = 0; attempt < 100; attempt++) {
        fd = connect_socket(socket_path);
        if (fd >= 0) return fd;
        if (errno != ECONNREFUSED && errno != ENOENT) return -1;
        usleep(10000);
    }
    return -1;
}

static int per_uid_rejection_log_is_coalesced(const char *socket_path, const char *log_path) {
    int held[SHREED_MAX_CLIENTS_PER_UID];
    char line[512];
    int rejection_records = 0;
    int log_opened = 0;
    FILE *log_file;

    for (size_t index = 0; index < SHREED_MAX_CLIENTS_PER_UID; index++) {
        held[index] = connect_and_hold(socket_path);
        if (held[index] < 0) {
            while (index > 0) close(held[--index]);
            return 0;
        }
    }
    for (int attempt = 0; attempt < 64; attempt++) {
        char response[SHREED_RESPONSE_MAX + 1];
        if (exchange(socket_path, "{\"action\":\"ping\"}", response,
                     sizeof(response)) == 0) {
            for (size_t index = 0; index < SHREED_MAX_CLIENTS_PER_UID; index++) close(held[index]);
            return 0;
        }
    }
    usleep(100000);
    log_file = fopen(log_path, "r");
    if (log_file) {
        log_opened = 1;
        while (fgets(line, sizeof(line), log_file)) {
            if (strstr(line, "rejected peer exceeding per-UID IPC limit")) rejection_records++;
        }
        fclose(log_file);
    }
    for (size_t index = 0; index < SHREED_MAX_CLIENTS_PER_UID; index++) close(held[index]);
    usleep(100000);
    return log_opened && rejection_records == 1;
}

int main(int argc, char **argv) {
    char socket_path[108];
    char log_path[108];
    char response[SHREED_RESPONSE_MAX + 1];
    char log_contents[512];
    struct stat status;
    pid_t daemon;
    int malformed_fd;
    uint32_t malformed_length;
    FILE *log_file;

    if (argc != 2) {
        fprintf(stderr, "Usage: test-shreed <daemon-path>\n");
        return 2;
    }
    signal(SIGPIPE, SIG_IGN);
    snprintf(socket_path, sizeof(socket_path), "/tmp/shreed-test-%ld.sock", (long)getpid());
    snprintf(log_path, sizeof(log_path), "/tmp/shreed-test-%ld.log", (long)getpid());
    unlink(socket_path);
    unlink(log_path);
    daemon = start_daemon(argv[1], socket_path, log_path);
    TEST("daemon starts", daemon > 0 && wait_for_path(socket_path, true) == 0);
    /* Start with no other authenticated peers so only these idle sockets hit the UID limit. */
    TEST("per-UID rejection flood produces one bounded log record",
         per_uid_rejection_log_is_coalesced(socket_path, log_path));
    {
        struct group *hardware = getgrnam("shree-hardware");
        gid_t expected_gid = getegid();
        int group_expectation_available = 1;
        if (geteuid() == 0) {
            if (hardware) expected_gid = hardware->gr_gid;
            else group_expectation_available = 0;
        }
        TEST("socket mode and service group ownership",
             group_expectation_available && lstat(socket_path, &status) == 0 &&
             (status.st_mode & 0777) == 0660 && status.st_gid == expected_gid);
    }
    TEST("ping response", exchange(socket_path, "{\"action\":\"ping\"}", response, sizeof(response)) == 0 &&
         strstr(response, "\"pong\":true") != NULL);
    TEST("status response", exchange(socket_path, "{\"action\":\"status\"}", response, sizeof(response)) == 0 &&
         strstr(response, "\"status\":\"healthy") != NULL);
    TEST("network IPC query", exchange(socket_path, "{\"action\":\"network\"}", response, sizeof(response)) == 0 &&
         strstr(response, "\"interfaces\"") != NULL && strstr(response, "\"dns_servers\"") != NULL);
    TEST("Ethernet IPC query", exchange(socket_path, "{\"action\":\"ethernet\"}", response, sizeof(response)) == 0 &&
         strstr(response, "\"interfaces\"") != NULL);
    TEST("drivers IPC query", exchange(socket_path, "{\"action\":\"drivers\"}", response, sizeof(response)) == 0 &&
         strstr(response, "\"devices\"") != NULL);
    TEST("diagnose IPC query", exchange(socket_path, "{\"action\":\"diagnose\"}", response, sizeof(response)) == 0 &&
         strstr(response, "\"read_only\":true") != NULL);
    TEST("event subscription acknowledgement", exchange(socket_path, "{\"action\":\"subscribe\"}", response, sizeof(response)) == 0 &&
         strstr(response, "\"subscription\":\"hardware") != NULL);
    TEST("invalid JSON produces structured error", exchange(socket_path, "{\"secret\":\"do-not-log\"}", response, sizeof(response)) == 0 &&
         strstr(response, "\"code\":\"INVALID_REQUEST") != NULL);
    if (geteuid() == 0) {
        TEST("nonmember local peer is denied", reject_unprivileged_peer(socket_path));
        if (getgrnam("shree-hardware")) {
            TEST("supplementary shree-hardware group member is authorized",
                 allow_supplementary_hardware_group_peer(socket_path));
        } else {
            printf("SKIP: supplementary group authorization requires shree-hardware group\n");
        }
        TEST("rejected peer flood produces one bounded log record",
             rejected_peer_flood_is_coalesced(socket_path, log_path));
    } else {
        printf("SKIP: nonmember local peer authorization test requires root\n");
    }

    malformed_fd = connect_socket(socket_path);
    malformed_length = htonl(SHREED_MAX_MESSAGE + 1);
    TEST("malformed frame produces structured error", malformed_fd >= 0 &&
         write_all(malformed_fd, &malformed_length, sizeof(malformed_length)) == 0 &&
         read_all(malformed_fd, &malformed_length, sizeof(malformed_length)) == 0 &&
         ntohl(malformed_length) < sizeof(response) &&
         read_all(malformed_fd, response, ntohl(malformed_length)) == 0 &&
         (response[ntohl(malformed_length)] = '\0') == '\0' && strstr(response, "MALFORMED_FRAME") != NULL);
    if (malformed_fd >= 0) close(malformed_fd);
    test_concurrent_connections(socket_path);

    if (daemon > 0) kill(daemon, SIGTERM);
    TEST("daemon exits cleanly", daemon > 0 && waitpid(daemon, NULL, 0) == daemon &&
         wait_for_path(socket_path, false) == 0);
    daemon = start_daemon(argv[1], socket_path, log_path);
    TEST("daemon restarts cleanly", daemon > 0 && wait_for_path(socket_path, true) == 0 &&
         exchange(socket_path, "{\"action\":\"ping\"}", response, sizeof(response)) == 0 &&
         strstr(response, "\"pong\":true") != NULL);
    if (daemon > 0) kill(daemon, SIGTERM);
    if (daemon > 0) (void)waitpid(daemon, NULL, 0);
    (void)wait_for_path(socket_path, false);
    log_file = fopen(log_path, "r");
    if (log_file) {
        size_t count = fread(log_contents, 1, sizeof(log_contents) - 1, log_file);
        log_contents[count] = '\0';
        fclose(log_file);
    } else {
        log_contents[0] = '\0';
    }
    TEST("log never contains client payload", strstr(log_contents, "do-not-log") == NULL);
    TEST("log has private file permissions", lstat(log_path, &status) == 0 && (status.st_mode & 0777) == 0640);

    unlink(socket_path);
    unlink(log_path);
    printf("%d failures\n", failures);
    return failures ? 1 : 0;
}
