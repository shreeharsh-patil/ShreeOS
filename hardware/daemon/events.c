#define _GNU_SOURCE
#include "shreed.h"

#include <linux/if_link.h>
#include <linux/netlink.h>
#include <linux/rtnetlink.h>
#include <net/if.h>
#include <stdio.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <unistd.h>

void shreed_events_subscribe(shreed_client_t *client) {
    if (client) client->subscribed = true;
}

void shreed_events_emit(shreed_client_t clients[], const char *event, const char *interface) {
    char payload[256];
    if (!clients || !event) return;
    snprintf(payload, sizeof(payload), "{\"event\":\"%s\",\"interface\":\"%s\"}",
             event, interface ? interface : "");
    for (size_t i = 0; i < SHREED_MAX_CLIENTS; i++) {
        if (clients[i].fd >= 0 && clients[i].subscribed && clients[i].output_length == 0)
            (void)shreed_queue_response(&clients[i], payload);
    }
}

int shreed_events_open_network_monitor(void) {
    struct sockaddr_nl address;
    int fd = socket(AF_NETLINK, SOCK_RAW | SOCK_NONBLOCK | SOCK_CLOEXEC, NETLINK_ROUTE);
    if (fd < 0) return -1;
    memset(&address, 0, sizeof(address));
    address.nl_family = AF_NETLINK;
    address.nl_groups = RTMGRP_LINK | RTMGRP_IPV4_IFADDR | RTMGRP_IPV6_IFADDR;
    if (bind(fd, (struct sockaddr *)&address, sizeof(address)) != 0) { close(fd); return -1; }
    return fd;
}

void shreed_events_process_network(int fd, shreed_client_t clients[]) {
    static bool known_interfaces[65536];
    char buffer[8192];
    ssize_t length;
    while ((length = recv(fd, buffer, sizeof(buffer), 0)) > 0) {
        struct nlmsghdr *message;
        int remaining = (int)length;
        for (message = (struct nlmsghdr *)buffer; NLMSG_OK(message, remaining);
             message = NLMSG_NEXT(message, remaining)) {
            char name[IF_NAMESIZE] = "";
            const char *event = NULL;
            if (message->nlmsg_type == RTM_NEWADDR || message->nlmsg_type == RTM_DELADDR) {
                struct ifaddrmsg *address = NLMSG_DATA(message);
                (void)if_indextoname(address->ifa_index, name);
                event = "IP_ADDRESS_CHANGED";
            } else if (message->nlmsg_type == RTM_DELLINK) {
                struct ifinfomsg *link = NLMSG_DATA(message);
                (void)if_indextoname(link->ifi_index, name);
                if (link->ifi_index < 65536) known_interfaces[link->ifi_index] = false;
                event = "NETWORK_INTERFACE_REMOVED";
            } else if (message->nlmsg_type == RTM_NEWLINK) {
                struct ifinfomsg *link = NLMSG_DATA(message);
                char wireless_path[128];
                (void)if_indextoname(link->ifi_index, name);
                snprintf(wireless_path, sizeof(wireless_path), "/sys/class/net/%s/wireless", name);
                if (name[0] && access(wireless_path, F_OK) == 0) {
                    event = (link->ifi_flags & IFF_LOWER_UP) ? "WIFI_CONNECTED" : "WIFI_DISCONNECTED";
                } else if (link->ifi_index < 65536 && !known_interfaces[link->ifi_index]) {
                    known_interfaces[link->ifi_index] = true;
                    event = "NETWORK_INTERFACE_ADDED";
                } else {
                    event = (link->ifi_flags & IFF_LOWER_UP) ? "NETWORK_CONNECTED" : "NETWORK_DISCONNECTED";
                }
            }
            if (event) shreed_events_emit(clients, event, name);
        }
    }
}
