#define _GNU_SOURCE
#include "shreed.h"

#include <linux/if_link.h>
#include <linux/netlink.h>
#include <linux/rtnetlink.h>
#include <net/if.h>
#include <dirent.h>
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

typedef struct {
    unsigned bluetooth_count;
    unsigned audio_count;
    unsigned battery_count;
    int battery_percent;
    int mains_online;
    unsigned backlight_count;
    unsigned long backlight_value;
} optional_state_t;

static unsigned count_entries(const char *path) {
    DIR *dir = opendir(path); struct dirent *entry; unsigned count = 0;
    if (!dir) return 0;
    while ((entry = readdir(dir))) if (entry->d_name[0] != '.') count++;
    closedir(dir); return count;
}

static optional_state_t collect_optional_state(void) {
    optional_state_t state = {0}; DIR *dir; struct dirent *entry;
    state.bluetooth_count = count_entries("/sys/class/bluetooth");
    state.audio_count = count_entries("/sys/class/sound");
    state.mains_online = 0;
    dir = opendir("/sys/class/power_supply");
    if (dir) {
        int capacity_total = 0;
        while ((entry = readdir(dir))) {
            char type_path[512], value_path[512], type[64] = ""; FILE *file;
            if (entry->d_name[0] == '.') continue;
            snprintf(type_path, sizeof(type_path), "/sys/class/power_supply/%s/type", entry->d_name);
            file = fopen(type_path, "r");
            if (!file || !fgets(type, sizeof(type), file)) { if (file) fclose(file); continue; }
            fclose(file); type[strcspn(type, "\r\n")] = 0;
            if (strcmp(type, "Battery") == 0) {
                snprintf(value_path, sizeof(value_path), "/sys/class/power_supply/%s/capacity", entry->d_name);
                int capacity = read_int_file(value_path);
                state.battery_count++;
                if (capacity >= 0 && capacity <= 100) capacity_total += capacity;
            } else if (strcmp(type, "Mains") == 0) {
                snprintf(value_path, sizeof(value_path), "/sys/class/power_supply/%s/online", entry->d_name);
                if (read_int_file(value_path) > 0) state.mains_online = 1;
            }
        }
        closedir(dir);
        if (state.battery_count) state.battery_percent = capacity_total / (int)state.battery_count;
        else state.battery_percent = -1;
    } else state.battery_percent = -1;
    dir = opendir("/sys/class/backlight");
    if (dir) {
        while ((entry = readdir(dir))) {
            char value_path[512]; int value;
            if (entry->d_name[0] == '.') continue;
            snprintf(value_path, sizeof(value_path), "/sys/class/backlight/%s/brightness", entry->d_name);
            value = read_int_file(value_path);
            if (value >= 0) { state.backlight_count++; state.backlight_value += (unsigned long)value; }
        }
        closedir(dir);
    }
    return state;
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
                (void)if_indextoname(link->ifi_index, name);
                if (link->ifi_index < 65536 && !known_interfaces[link->ifi_index]) {
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
    static bool initialized = false; static optional_state_t previous;
    optional_state_t current = collect_optional_state();
    if (!initialized) { previous = current; initialized = true; return; }
    if (current.bluetooth_count != previous.bluetooth_count)
        shreed_events_emit(clients, current.bluetooth_count > previous.bluetooth_count ? "BLUETOOTH_DEVICE_ADDED" : "BLUETOOTH_DEVICE_REMOVED", "bluetooth");
    if (current.audio_count != previous.audio_count)
        shreed_events_emit(clients, current.audio_count > previous.audio_count ? "AUDIO_DEVICE_ADDED" : "AUDIO_DEVICE_REMOVED", "audio");
    if (current.battery_count != previous.battery_count || current.battery_percent != previous.battery_percent)
        shreed_events_emit(clients, "BATTERY_CHANGED", "battery");
    if (previous.battery_percent > 15 && current.battery_percent >= 0 && current.battery_percent <= 15)
        shreed_events_emit(clients, "BATTERY_LOW", "battery");
    if (current.mains_online != previous.mains_online)
        shreed_events_emit(clients, current.mains_online ? "POWER_CONNECTED" : "POWER_DISCONNECTED", "power");
    if (current.backlight_count != previous.backlight_count || current.backlight_value != previous.backlight_value)
        shreed_events_emit(clients, "BRIGHTNESS_CHANGED", "backlight");
    previous = current;
}
