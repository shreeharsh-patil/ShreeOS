#include "shreed.h"

#include <arpa/inet.h>
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <unistd.h>

static int write_all(int fd, const void *buffer, size_t length) {
    const unsigned char *cursor = buffer;
    while (length > 0) {
        ssize_t written = write(fd, cursor, length);
        if (written > 0) {
            cursor += written;
            length -= (size_t)written;
            continue;
        }
        if (written < 0 && errno == EINTR) continue;
        return -1;
    }
    return 0;
}

static int read_all(int fd, void *buffer, size_t length) {
    unsigned char *cursor = buffer;
    while (length > 0) {
        ssize_t received = read(fd, cursor, length);
        if (received > 0) {
            cursor += received;
            length -= (size_t)received;
            continue;
        }
        if (received < 0 && errno == EINTR) continue;
        return -1;
    }
    return 0;
}

static void usage(void) {
    fprintf(stderr, "Usage: shreedctl <ping|status> [--json] [--socket <path>]\n");
}

int main(int argc, char **argv) {
    const char *action;
    const char *socket_path = SHREED_SOCKET_PATH;
    bool json_output = false;
    const char *request;
    struct sockaddr_un address;
    uint32_t network_length;
    uint32_t response_length;
    char response[SHREED_RESPONSE_MAX + 1];
    int fd;

    if (argc < 2) {
        usage();
        return 2;
    }
    action = argv[1];
    if (strcmp(action, "ping") != 0 && strcmp(action, "status") != 0) {
        usage();
        return 2;
    }
    for (int argument = 2; argument < argc; argument++) {
        if (strcmp(argv[argument], "--json") == 0) json_output = true;
        else if (strcmp(argv[argument], "--socket") == 0 && argument + 1 < argc) socket_path = argv[++argument];
        else {
            usage();
            return 2;
        }
    }
    request = strcmp(action, "ping") == 0 ? "{\"action\":\"ping\"}" : "{\"action\":\"status\"}";

    fd = socket(AF_UNIX, SOCK_STREAM | SOCK_CLOEXEC, 0);
    if (fd < 0) {
        perror("shreedctl: socket");
        return 1;
    }
    memset(&address, 0, sizeof(address));
    address.sun_family = AF_UNIX;
    if (strlen(socket_path) >= sizeof(address.sun_path)) {
        fprintf(stderr, "shreedctl: socket path is too long\n");
        close(fd);
        return 1;
    }
    strcpy(address.sun_path, socket_path);
    if (connect(fd, (struct sockaddr *)&address, sizeof(address)) != 0) {
        fprintf(stderr, "shreedctl: cannot connect to %s: %s\n", socket_path, strerror(errno));
        close(fd);
        return 1;
    }
    network_length = htonl((uint32_t)strlen(request));
    if (write_all(fd, &network_length, sizeof(network_length)) != 0 ||
        write_all(fd, request, strlen(request)) != 0 ||
        read_all(fd, &network_length, sizeof(network_length)) != 0) {
        fprintf(stderr, "shreedctl: IPC exchange failed\n");
        close(fd);
        return 1;
    }
    response_length = ntohl(network_length);
    if (response_length == 0 || response_length > SHREED_RESPONSE_MAX ||
        read_all(fd, response, response_length) != 0) {
        fprintf(stderr, "shreedctl: invalid daemon response\n");
        close(fd);
        return 1;
    }
    close(fd);
    response[response_length] = '\0';

    if (strstr(response, "\"ok\":true") == NULL) {
        fprintf(stderr, "shreedctl: daemon returned an error\n");
        if (json_output) printf("%s\n", response);
        return 1;
    }
    if (json_output) {
        printf("%s\n", response);
    } else if (strcmp(action, "ping") == 0) {
        printf("shreed: pong\n");
    } else {
        printf("shreed: healthy\n");
    }
    return 0;
}
