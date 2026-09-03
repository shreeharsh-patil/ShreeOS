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
    fprintf(stderr, "Usage: shreedctl <ping|status|hardware|cpu|gpu|memory|disks|pci|usb|network|interfaces|ethernet|drivers|drivers_missing|firmware|diagnose|battery|power|brightness|audio|display> [--json] [--socket <path>]\n");
}

static bool supported_action(const char *action) {
    return strcmp(action, "ping") == 0 || strcmp(action, "status") == 0 ||
           strcmp(action, "hardware") == 0 || strcmp(action, "cpu") == 0 ||
           strcmp(action, "gpu") == 0 || strcmp(action, "memory") == 0 ||
           strcmp(action, "disks") == 0 || strcmp(action, "pci") == 0 ||
           strcmp(action, "usb") == 0 || strcmp(action, "network") == 0 ||
           strcmp(action, "interfaces") == 0 || strcmp(action, "ethernet") == 0 ||
           strcmp(action, "drivers") == 0 || strcmp(action, "drivers_missing") == 0 ||
           strcmp(action, "firmware") == 0 || strcmp(action, "diagnose") == 0 ||
           strcmp(action, "battery") == 0 || strcmp(action, "power") == 0 ||
           strcmp(action, "brightness") == 0 || strcmp(action, "audio") == 0 ||
           strcmp(action, "display") == 0;
}

static bool json_string(const char *json, const char *key, char *output, size_t size) {
    char pattern[64];
    const char *cursor;
    size_t length = 0;

    snprintf(pattern, sizeof(pattern), "\"%s\":", key);
    cursor = strstr(json, pattern);
    if (!cursor || strncmp(cursor + strlen(pattern), "null", 4) == 0) return false;
    cursor += strlen(pattern);
    if (*cursor != '"') return false;
    cursor++;
    while (*cursor && *cursor != '"' && length + 1 < size) {
        if (*cursor == '\\' && cursor[1]) cursor++;
        output[length++] = *cursor++;
    }
    output[length] = '\0';
    return *cursor == '"';
}

static bool json_uint64(const char *json, const char *key, unsigned int occurrence, uint64_t *value) {
    char pattern[64];
    const char *cursor = json;
    char *end;

    snprintf(pattern, sizeof(pattern), "\"%s\":", key);
    for (unsigned int index = 0; index <= occurrence; index++) {
        cursor = strstr(cursor, pattern);
        if (!cursor) return false;
        cursor += strlen(pattern);
    }
    errno = 0;
    *value = strtoull(cursor, &end, 10);
    return errno == 0 && end != cursor;
}

static void print_size(uint64_t bytes) {
    printf("%llu GB", (unsigned long long)(bytes / (1024ULL * 1024ULL * 1024ULL)));
}

static void print_pretty(const char *action, const char *response) {
    char value[512];
    uint64_t amount;

    if (strcmp(action, "ping") == 0) {
        printf("shreed: pong\n");
    } else if (strcmp(action, "status") == 0) {
        printf("shreed: healthy\n");
    } else if (strcmp(action, "hardware") == 0) {
        if (json_string(response, "model", value, sizeof(value))) printf("CPU: %s\n", value);
        else printf("CPU: unavailable\n");
        if (json_string(response, "name", value, sizeof(value))) printf("GPU: %s\n", value);
        else printf("GPU: unavailable\n");
        if (json_uint64(response, "total_bytes", 0, &amount)) {
            printf("Memory: "); print_size(amount); printf("\n");
        } else printf("Memory: unavailable\n");
        if (json_uint64(response, "total_bytes", 1, &amount)) {
            printf("Storage: "); print_size(amount); printf("\n");
        } else printf("Storage: unavailable\n");
        if (json_string(response, "architecture", value, sizeof(value))) printf("Architecture: %s\n", value);
        if (json_string(response, "kernel", value, sizeof(value))) printf("Kernel: %s\n", value);
    } else if (strcmp(action, "cpu") == 0 && json_string(response, "model", value, sizeof(value))) {
        printf("CPU: %s\n", value);
    } else if (strcmp(action, "gpu") == 0 && json_string(response, "name", value, sizeof(value))) {
        printf("GPU: %s\n", value);
    } else if (strcmp(action, "memory") == 0 && json_uint64(response, "total_bytes", 0, &amount)) {
        printf("Memory: "); print_size(amount); printf("\n");
    } else {
        printf("%s\n", response);
    }
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
    if (!supported_action(action)) {
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
    {
        static char request_buffer[64];
        snprintf(request_buffer, sizeof(request_buffer), "{\"action\":\"%s\"}", action);
        request = request_buffer;
    }

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
    } else print_pretty(action, response);
    return 0;
}
