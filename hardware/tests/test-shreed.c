#include "shreed.h"

#include <arpa/inet.h>
#include <errno.h>
#include <fcntl.h>
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
    snprintf(socket_path, sizeof(socket_path), "/tmp/shreed-test-%ld.sock", (long)getpid());
    snprintf(log_path, sizeof(log_path), "/tmp/shreed-test-%ld.log", (long)getpid());
    unlink(socket_path);
    unlink(log_path);
    daemon = start_daemon(argv[1], socket_path, log_path);
    TEST("daemon starts", daemon > 0 && wait_for_path(socket_path, true) == 0);
    TEST("socket has public read-only IPC mode", lstat(socket_path, &status) == 0 && (status.st_mode & 0777) == 0666);
    TEST("ping response", exchange(socket_path, "{\"action\":\"ping\"}", response, sizeof(response)) == 0 &&
         strstr(response, "\"pong\":true") != NULL);
    TEST("status response", exchange(socket_path, "{\"action\":\"status\"}", response, sizeof(response)) == 0 &&
         strstr(response, "\"status\":\"healthy") != NULL);
    TEST("event subscription acknowledgement", exchange(socket_path, "{\"action\":\"subscribe\"}", response, sizeof(response)) == 0 &&
         strstr(response, "\"subscription\":\"hardware") != NULL);
    TEST("invalid JSON produces structured error", exchange(socket_path, "{\"secret\":\"do-not-log\"}", response, sizeof(response)) == 0 &&
         strstr(response, "\"code\":\"INVALID_REQUEST") != NULL);

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
