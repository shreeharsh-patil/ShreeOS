#include "shreed.h"

#include <arpa/inet.h>
#include <ctype.h>
#include <errno.h>
#include <string.h>
#include <sys/socket.h>
#include <unistd.h>

static void skip_space(const char **cursor, const char *end) {
    while (*cursor < end && isspace((unsigned char)**cursor)) {
        (*cursor)++;
    }
}

static int parse_plain_string(const char **cursor, const char *end,
                              char *output, size_t output_size) {
    size_t length = 0;

    if (*cursor >= end || **cursor != '"') return -1;
    (*cursor)++;

    while (*cursor < end && **cursor != '"') {
        unsigned char ch = (unsigned char)**cursor;
        if (ch < 0x20 || ch == '\\' || length + 1 >= output_size) return -1;
        output[length++] = (char)ch;
        (*cursor)++;
    }

    if (*cursor >= end || **cursor != '"') return -1;
    (*cursor)++;
    output[length] = '\0';
    return 0;
}

int shreed_parse_request(const char *payload, size_t length,
                         shreed_request_t *request) {
    const char *cursor = payload;
    const char *end = payload + length;
    char key[16];
    char action[32];

    if (!payload || !request || length == 0 || length > SHREED_MAX_MESSAGE) return -1;
    request->type = SHREED_REQUEST_INVALID;

    skip_space(&cursor, end);
    if (cursor >= end || *cursor++ != '{') return -1;
    skip_space(&cursor, end);
    if (parse_plain_string(&cursor, end, key, sizeof(key)) != 0 || strcmp(key, "action") != 0) return -1;
    skip_space(&cursor, end);
    if (cursor >= end || *cursor++ != ':') return -1;
    skip_space(&cursor, end);
    if (parse_plain_string(&cursor, end, action, sizeof(action)) != 0) return -1;
    skip_space(&cursor, end);
    if (cursor >= end || *cursor++ != '}') return -1;
    skip_space(&cursor, end);
    if (cursor != end) return -1;

    if (strcmp(action, "ping") == 0) request->type = SHREED_REQUEST_PING;
    else if (strcmp(action, "status") == 0) request->type = SHREED_REQUEST_STATUS;
    else if (strcmp(action, "subscribe") == 0) request->type = SHREED_REQUEST_SUBSCRIBE;
    else if (strcmp(action, "hardware") == 0) request->type = SHREED_REQUEST_HARDWARE;
    else if (strcmp(action, "cpu") == 0) request->type = SHREED_REQUEST_CPU;
    else if (strcmp(action, "gpu") == 0) request->type = SHREED_REQUEST_GPU;
    else if (strcmp(action, "memory") == 0) request->type = SHREED_REQUEST_MEMORY;
    else if (strcmp(action, "disks") == 0) request->type = SHREED_REQUEST_DISKS;
    else if (strcmp(action, "pci") == 0) request->type = SHREED_REQUEST_PCI;
    else if (strcmp(action, "usb") == 0) request->type = SHREED_REQUEST_USB;
    else if (strcmp(action, "network") == 0) request->type = SHREED_REQUEST_NETWORK;
    else if (strcmp(action, "interfaces") == 0) request->type = SHREED_REQUEST_INTERFACES;
    else if (strcmp(action, "ethernet") == 0) request->type = SHREED_REQUEST_ETHERNET;
    else if (strcmp(action, "drivers") == 0) request->type = SHREED_REQUEST_DRIVERS;
    else if (strcmp(action, "drivers_missing") == 0) request->type = SHREED_REQUEST_DRIVERS_MISSING;
    else if (strcmp(action, "firmware") == 0) request->type = SHREED_REQUEST_FIRMWARE;
    else if (strcmp(action, "diagnose") == 0) request->type = SHREED_REQUEST_DIAGNOSE;
    else return -1;

    return 0;
}

int shreed_read_frame(shreed_client_t *client) {
    ssize_t received;

    while (client->header_used < sizeof(client->header)) {
        received = read(client->fd, client->header + client->header_used,
                        sizeof(client->header) - client->header_used);
        if (received > 0) {
            client->header_used += (size_t)received;
            continue;
        }
        if (received == 0) return -1;
        if (errno == EINTR) continue;
        return (errno == EAGAIN || errno == EWOULDBLOCK) ? 0 : -1;
    }

    if (client->payload_length == 0) {
        uint32_t network_length;
        memcpy(&network_length, client->header, sizeof(network_length));
        client->payload_length = ntohl(network_length);
        if (client->payload_length == 0 || client->payload_length > SHREED_MAX_MESSAGE) return -2;
    }

    while (client->payload_used < client->payload_length) {
        received = read(client->fd, client->payload + client->payload_used,
                        client->payload_length - client->payload_used);
        if (received > 0) {
            client->payload_used += (size_t)received;
            continue;
        }
        if (received == 0) return -1;
        if (errno == EINTR) continue;
        return (errno == EAGAIN || errno == EWOULDBLOCK) ? 0 : -1;
    }

    client->payload[client->payload_length] = '\0';
    return 1;
}

int shreed_queue_response(shreed_client_t *client, const char *json) {
    size_t json_length;
    uint32_t network_length;

    if (!client || !json) return -1;
    json_length = strlen(json);
    if (json_length == 0 || json_length > SHREED_RESPONSE_MAX) return -1;

    network_length = htonl((uint32_t)json_length);
    memcpy(client->output, &network_length, sizeof(network_length));
    memcpy(client->output + sizeof(network_length), json, json_length);
    client->output_length = sizeof(network_length) + json_length;
    client->output_sent = 0;
    return 0;
}

int shreed_flush_response(shreed_client_t *client) {
    ssize_t sent;

    while (client->output_sent < client->output_length) {
        sent = write(client->fd, client->output + client->output_sent,
                     client->output_length - client->output_sent);
        if (sent > 0) {
            client->output_sent += (size_t)sent;
            continue;
        }
        if (sent < 0 && errno == EINTR) continue;
        return (sent < 0 && (errno == EAGAIN || errno == EWOULDBLOCK)) ? 0 : -1;
    }
    return 1;
}

void shreed_reset_request(shreed_client_t *client) {
    client->header_used = 0;
    client->payload_length = 0;
    client->payload_used = 0;
}
