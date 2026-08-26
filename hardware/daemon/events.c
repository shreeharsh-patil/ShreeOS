#define _GNU_SOURCE
#include "shreed.h"

#include <linux/if_link.h>
#include <linux/netlink.h>
#include <linux/rtnetlink.h>
#include <net/if.h>
#include <dirent.h>
#include <limits.h>
#include <stdio.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <unistd.h>

static int read_int_file(const char *path) {
    FILE *file = fopen(path, "r");
    int value = -1;
    if (file) { (void)fscanf(file, "%d", &value); fclose(file); }
    return value;
}

/* A compact state fingerprint avoids fixed device names while keeping the
 * optional fallback monitor cheap. Netlink remains the primary monitor. */
static unsigned long class_fingerprint(const char *directory, const char *wanted_type,
                                       const char *value_name) {
    DIR *dir = opendir(directory); struct dirent *entry; unsigned long hash = 5381;
    if (!dir) return 0;
    while ((entry = readdir(dir))) {
        char type_path[512], value_path[512], type[64] = ""; int value;
        if (entry->d_name[0] == '.') continue;
        if (wanted_type) {
            snprintf(type_path, sizeof(type_path), "%s/%s/type", directory, entry->d_name);
            FILE *file = fopen(type_path, "r");
            if (!file || !fgets(type, sizeof(type), file)) { if (file) fclose(file); continue; }
            fclose(file); type[strcspn(type, "\r\n")] = 0;
            if (strcmp(type, wanted_type) != 0) continue;
        }
        snprintf(value_path, sizeof(value_path), "%s/%s/%s", directory, entry->d_name, value_name);
        value = read_int_file(value_path);
        for (const unsigned char *p = (const unsigned char *)entry->d_name; *p; ++p) hash = ((hash << 5) + hash) ^ *p;
        hash = ((hash << 5) + hash) ^ (unsigned long)(value + 1);
    }
    closedir(dir); return hash;
}

bool shreed_events_subscribe(shreed_client_t clients[], shreed_client_t *client) {
    size_t subscribers = 0;
    if (!clients || !client) return false;
    for (size_t index = 0; index < SHREED_MAX_CLIENTS; index++) {
        if (clients[index].fd >= 0 && clients[index].subscribed) subscribers++;
    }
    if (subscribers >= SHREED_MAX_SUBSCRIBERS) return false;
    client->subscribed = true;
    return true;
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

void shreed_events_poll_optional(shreed_client_t clients[]) {
    static unsigned long bluetooth = ULONG_MAX, audio = ULONG_MAX, battery = ULONG_MAX, ac = ULONG_MAX, brightness = ULONG_MAX;
    unsigned long now_bluetooth = class_fingerprint("/sys/class/bluetooth", NULL, "uevent");
    unsigned long now_audio = class_fingerprint("/sys/class/sound", NULL, "uevent");
    unsigned long now_battery = class_fingerprint("/sys/class/power_supply", "Battery", "capacity");
    unsigned long now_ac = class_fingerprint("/sys/class/power_supply", "Mains", "online");
    unsigned long now_brightness = class_fingerprint("/sys/class/backlight", NULL, "brightness");
    if (bluetooth != ULONG_MAX && bluetooth != now_bluetooth) shreed_events_emit(clients, now_bluetooth ? "BLUETOOTH_DEVICE_ADDED" : "BLUETOOTH_DEVICE_REMOVED", "bluetooth");
    if (audio != ULONG_MAX && audio != now_audio) shreed_events_emit(clients, now_audio ? "AUDIO_DEVICE_ADDED" : "AUDIO_DEVICE_REMOVED", "audio");
    if (battery != ULONG_MAX && battery != now_battery) shreed_events_emit(clients, "BATTERY_CHANGED", "battery");
    if (ac != ULONG_MAX && ac != now_ac) shreed_events_emit(clients, now_ac ? "POWER_CONNECTED" : "POWER_DISCONNECTED", "power");
    if (brightness != ULONG_MAX && brightness != now_brightness) shreed_events_emit(clients, "BRIGHTNESS_CHANGED", "backlight");
    bluetooth = now_bluetooth; audio = now_audio; battery = now_battery; ac = now_ac; brightness = now_brightness;
}
