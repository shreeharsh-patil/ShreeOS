#define _GNU_SOURCE
#include "shreed.h"
#include "devices.h"

#include <errno.h>
#include <fcntl.h>
#include <poll.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/un.h>
#include <unistd.h>

static volatile sig_atomic_t shutdown_requested;

static void handle_signal(int signal_number) {
    (void)signal_number;
    shutdown_requested = 1;
}

static void close_client(shreed_client_t *client) {
    if (client->fd >= 0) close(client->fd);
    memset(client, 0, sizeof(*client));
    client->fd = -1;
}

static int create_listener(const char *socket_path) {
    struct sockaddr_un address;
    int fd;

    if (shreed_prepare_socket_path(socket_path) != 0) return -1;
    fd = socket(AF_UNIX, SOCK_STREAM | SOCK_NONBLOCK | SOCK_CLOEXEC, 0);
    if (fd < 0) return -1;

    memset(&address, 0, sizeof(address));
    address.sun_family = AF_UNIX;
    if (strlen(socket_path) >= sizeof(address.sun_path)) {
        close(fd);
        errno = ENAMETOOLONG;
        return -1;
    }
    strcpy(address.sun_path, socket_path);
    if (bind(fd, (struct sockaddr *)&address, sizeof(address)) != 0 ||
        chmod(socket_path, 0666) != 0 || listen(fd, SHREED_MAX_CLIENTS) != 0) {
        close(fd);
        unlink(socket_path);
        return -1;
    }
    return fd;
}

static void queue_error(shreed_client_t *client, const char *code, const char *message) {
    char response[SHREED_RESPONSE_MAX + 1];

    snprintf(response, sizeof(response),
             "{\"ok\":false,\"error\":{\"code\":\"%s\",\"message\":\"%s\"}}",
             code, message);
    (void)shreed_queue_response(client, response);
}

static void queue_collector_response(shreed_client_t *client, const char *root,
                                     shreed_request_type_t type) {
    char response[SHREED_RESPONSE_MAX + 1];
    int result;

    switch (type) {
        case SHREED_REQUEST_HARDWARE: result = shreed_collect_hardware(root, response, sizeof(response)); break;
        case SHREED_REQUEST_CPU: result = shreed_collect_cpu(root, response, sizeof(response)); break;
        case SHREED_REQUEST_GPU: result = shreed_collect_gpu(root, response, sizeof(response)); break;
        case SHREED_REQUEST_MEMORY: result = shreed_collect_memory(root, response, sizeof(response)); break;
        case SHREED_REQUEST_DISKS: result = shreed_collect_storage(root, response, sizeof(response)); break;
        case SHREED_REQUEST_PCI: result = shreed_collect_pci(root, response, sizeof(response)); break;
        case SHREED_REQUEST_USB: result = shreed_collect_usb(root, response, sizeof(response)); break;
        case SHREED_REQUEST_NETWORK:
        case SHREED_REQUEST_INTERFACES: result = shreed_collect_network(root, response, sizeof(response)); break;
        case SHREED_REQUEST_ETHERNET: result = shreed_collect_ethernet(root, response, sizeof(response)); break;
        case SHREED_REQUEST_DRIVERS: result = shreed_collect_drivers(root, response, sizeof(response), false); break;
        case SHREED_REQUEST_DRIVERS_MISSING: result = shreed_collect_drivers(root, response, sizeof(response), true); break;
        case SHREED_REQUEST_FIRMWARE: result = shreed_collect_firmware(root, response, sizeof(response)); break;
        case SHREED_REQUEST_DIAGNOSE: result = shreed_collect_diagnostics(root, response, sizeof(response)); break;
        default: result = -1; break;
    }
    if (result == 0 && shreed_queue_response(client, response) == 0) return;
    queue_error(client, "COLLECTOR_FAILURE", "Hardware information could not be encoded");
}

static void process_request(shreed_client_t *client, const char *root) {
    shreed_request_t request;

    if (shreed_parse_request(client->payload, client->payload_length, &request) != 0) {
        queue_error(client, "INVALID_REQUEST", "Request must contain one supported action");
        return;
    }

    switch (request.type) {
        case SHREED_REQUEST_PING:
            (void)shreed_queue_response(client, "{\"ok\":true,\"result\":{\"pong\":true}}");
            break;
        case SHREED_REQUEST_STATUS:
            (void)shreed_queue_response(client,
                "{\"ok\":true,\"result\":{\"service\":\"shreed\",\"status\":\"healthy\",\"version\":\"1\"}}");
            break;
        case SHREED_REQUEST_SUBSCRIBE:
            shreed_events_subscribe(client);
            (void)shreed_queue_response(client,
                "{\"ok\":true,\"result\":{\"subscription\":\"hardware\",\"state\":\"active\"}}");
            break;
        case SHREED_REQUEST_HARDWARE:
        case SHREED_REQUEST_CPU:
        case SHREED_REQUEST_GPU:
        case SHREED_REQUEST_MEMORY:
        case SHREED_REQUEST_DISKS:
        case SHREED_REQUEST_PCI:
        case SHREED_REQUEST_USB:
        case SHREED_REQUEST_NETWORK:
        case SHREED_REQUEST_INTERFACES:
        case SHREED_REQUEST_ETHERNET:
        case SHREED_REQUEST_DRIVERS:
        case SHREED_REQUEST_DRIVERS_MISSING:
        case SHREED_REQUEST_FIRMWARE:
        case SHREED_REQUEST_DIAGNOSE:
            queue_collector_response(client, root, request.type);
            break;
        default:
            queue_error(client, "INVALID_REQUEST", "Unsupported action");
            break;
    }
}

static void accept_clients(int listener, shreed_client_t clients[], int log_fd) {
    for (;;) {
        int fd = accept4(listener, NULL, NULL, SOCK_NONBLOCK | SOCK_CLOEXEC);
        if (fd < 0) {
            if (errno != EAGAIN && errno != EWOULDBLOCK && errno != EINTR) {
                shreed_log(log_fd, "accept failed");
            }
            return;
        }
        if (!shreed_authorize_peer(fd)) {
            close(fd);
            shreed_log(log_fd, "rejected unauthenticated local peer");
            continue;
        }
        for (size_t index = 0; index < SHREED_MAX_CLIENTS; index++) {
            if (clients[index].fd < 0) {
                memset(&clients[index], 0, sizeof(clients[index]));
                clients[index].fd = fd;
                fd = -1;
                break;
            }
        }
        if (fd >= 0) close(fd);
    }
}

static void usage(void) {
    fprintf(stderr, "Usage: shreed [--foreground] [--socket <path>] [--log <path>] [--root <path>]\n");
}

int main(int argc, char **argv) {
    const char *socket_path = SHREED_SOCKET_PATH;
    const char *log_path = SHREED_LOG_PATH;
    const char *root = "";
    shreed_client_t clients[SHREED_MAX_CLIENTS];
    struct sigaction action;
    int listener = -1;
    int network_monitor = -1;
    int log_fd = -1;
    int exit_code = 1;

    for (int argument = 1; argument < argc; argument++) {
        if (strcmp(argv[argument], "--foreground") == 0) continue;
        if (strcmp(argv[argument], "--socket") == 0 && argument + 1 < argc) {
            socket_path = argv[++argument];
        } else if (strcmp(argv[argument], "--log") == 0 && argument + 1 < argc) {
            log_path = argv[++argument];
        } else if (strcmp(argv[argument], "--root") == 0 && argument + 1 < argc && argv[argument + 1][0] == '/') {
            root = argv[++argument];
        } else {
            usage();
            return 2;
        }
    }

    for (size_t index = 0; index < SHREED_MAX_CLIENTS; index++) clients[index].fd = -1;
    memset(&action, 0, sizeof(action));
    action.sa_handler = handle_signal;
    sigemptyset(&action.sa_mask);
    sigaction(SIGTERM, &action, NULL);
    sigaction(SIGINT, &action, NULL);
    signal(SIGPIPE, SIG_IGN);

    log_fd = shreed_open_log(log_path);
    if (log_fd < 0) {
        fprintf(stderr, "shreed: cannot open log: %s\n", strerror(errno));
        goto cleanup;
    }
    listener = create_listener(socket_path);
    if (listener < 0) {
        shreed_log(log_fd, "failed to create IPC socket");
        fprintf(stderr, "shreed: cannot create IPC socket: %s\n", strerror(errno));
        goto cleanup;
    }
    network_monitor = shreed_events_open_network_monitor();
    if (network_monitor < 0) shreed_log(log_fd, "network event monitor unavailable");
    shreed_log(log_fd, "started");

    while (!shutdown_requested) {
        struct pollfd poll_fds[SHREED_MAX_CLIENTS + 2];
        int client_indices[SHREED_MAX_CLIENTS + 2];
        nfds_t count = 1;

        poll_fds[0].fd = listener;
        poll_fds[0].events = POLLIN;
        poll_fds[0].revents = 0;
        client_indices[0] = -1;
        if (network_monitor >= 0) {
            poll_fds[count].fd = network_monitor;
            poll_fds[count].events = POLLIN;
            poll_fds[count].revents = 0;
            client_indices[count++] = -2;
        }
        for (size_t index = 0; index < SHREED_MAX_CLIENTS; index++) {
            if (clients[index].fd < 0) continue;
            poll_fds[count].fd = clients[index].fd;
            poll_fds[count].events = clients[index].output_length > clients[index].output_sent ? POLLOUT : POLLIN;
            poll_fds[count].revents = 0;
            client_indices[count++] = (int)index;
        }

        if (poll(poll_fds, count, 500) < 0) {
            if (errno != EINTR) shreed_log(log_fd, "poll failed");
            continue;
        }
        shreed_events_poll_optional(clients);
        if (poll_fds[0].revents & POLLIN) accept_clients(listener, clients, log_fd);
        if (network_monitor >= 0 && poll_fds[1].revents & POLLIN)
            shreed_events_process_network(network_monitor, clients);

        for (nfds_t item = 1; item < count; item++) {
            shreed_client_t *client;
            int result;

            if (client_indices[item] == -2) continue;
            client = &clients[client_indices[item]];

            if (poll_fds[item].revents & (POLLERR | POLLHUP | POLLNVAL)) {
                close_client(client);
                continue;
            }
            if (poll_fds[item].revents & POLLIN) {
                result = shreed_read_frame(client);
                if (result == 1) process_request(client, root);
                else if (result == -2) queue_error(client, "MALFORMED_FRAME", "Frame length is invalid");
                else if (result < 0) close_client(client);
            }
            if (client->fd >= 0 && poll_fds[item].revents & POLLOUT) {
                result = shreed_flush_response(client);
                if (result < 0 || (result == 1 && !client->subscribed)) {
                    close_client(client);
                } else if (result == 1) {
                    client->output_length = 0;
                    client->output_sent = 0;
                    shreed_reset_request(client);
                }
            }
        }
    }

    shreed_log(log_fd, "stopping");
    exit_code = 0;

cleanup:
    for (size_t index = 0; index < SHREED_MAX_CLIENTS; index++) close_client(&clients[index]);
    if (listener >= 0) close(listener);
    if (network_monitor >= 0) close(network_monitor);
    if (socket_path) unlink(socket_path);
    if (log_fd >= 0) close(log_fd);
    return exit_code;
}
