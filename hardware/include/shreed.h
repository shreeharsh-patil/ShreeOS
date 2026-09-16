#ifndef SHREED_H
#define SHREED_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <sys/types.h>
#include <time.h>

#define SHREED_SOCKET_PATH "/run/shreed.sock"
#define SHREED_LOG_PATH "/var/log/shreeos/shreed.log"
#define SHREED_MAX_CLIENTS 32
#define SHREED_MAX_SUBSCRIBERS 8
#define SHREED_MAX_CLIENTS_PER_UID 16
#define SHREED_CLIENT_IDLE_SECONDS 15
#define SHREED_SUBSCRIBER_IDLE_SECONDS 300
#define SHREED_MAX_MESSAGE 1024
#define SHREED_RESPONSE_MAX 16384

typedef enum {
    SHREED_REQUEST_INVALID = 0,
    SHREED_REQUEST_PING,
    SHREED_REQUEST_STATUS,
    SHREED_REQUEST_SUBSCRIBE,
    SHREED_REQUEST_HARDWARE,
    SHREED_REQUEST_CPU,
    SHREED_REQUEST_GPU,
    SHREED_REQUEST_MEMORY,
    SHREED_REQUEST_DISKS,
    SHREED_REQUEST_PCI,
    SHREED_REQUEST_USB,
    SHREED_REQUEST_NETWORK,
    SHREED_REQUEST_INTERFACES,
    SHREED_REQUEST_ETHERNET,
    SHREED_REQUEST_DRIVERS,
    SHREED_REQUEST_DRIVERS_MISSING,
    SHREED_REQUEST_FIRMWARE,
    SHREED_REQUEST_DIAGNOSE,
    SHREED_REQUEST_BATTERY,
    SHREED_REQUEST_POWER,
    SHREED_REQUEST_BRIGHTNESS,
    SHREED_REQUEST_AUDIO,
    SHREED_REQUEST_DISPLAY
} shreed_request_type_t;

typedef struct {
    shreed_request_type_t type;
} shreed_request_t;

typedef struct {
    int fd;
    unsigned char header[sizeof(uint32_t)];
    size_t header_used;
    uint32_t payload_length;
    char payload[SHREED_MAX_MESSAGE + 1];
    size_t payload_used;
    unsigned char output[SHREED_RESPONSE_MAX + sizeof(uint32_t)];
    size_t output_length;
    size_t output_sent;
    bool subscribed;
    uid_t peer_uid;
    time_t accepted_at;
    time_t last_activity;
} shreed_client_t;

int shreed_parse_request(const char *payload, size_t length,
                         shreed_request_t *request);
int shreed_read_frame(shreed_client_t *client);
int shreed_queue_response(shreed_client_t *client, const char *json);
int shreed_flush_response(shreed_client_t *client);
void shreed_reset_request(shreed_client_t *client);

bool shreed_authorize_peer(int fd, uid_t *peer_uid);
int shreed_prepare_socket_path(const char *path);
int shreed_open_log(const char *path);
void shreed_log(int fd, const char *message);

bool shreed_events_subscribe(shreed_client_t clients[], shreed_client_t *client);
void shreed_events_emit(shreed_client_t clients[], const char *event, const char *interface);
int shreed_events_open_network_monitor(void);
void shreed_events_process_network(int fd, shreed_client_t clients[]);
void shreed_events_poll_optional(shreed_client_t clients[]);

#endif
