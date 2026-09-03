#include "devices.h"

#include <dirent.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef struct {
    char name[256];
    char type[32];
    char status[32];
    char health[32];
    int capacity;
    bool present;
    bool online;
} power_device_t;

#define MAX_POWER_DEVICES 16

static void read_attr(const char *root, const char *dev, const char *attr, char *out, size_t sz) {
    char path[512];
    out[0] = '\0';
    if (snprintf(path, sizeof(path), "/sys/class/power_supply/%s/%s", dev, attr) < (int)sizeof(path)) {
        (void)shreed_read_file(root, path, out, sz);
    }
}

static int read_int_attr(const char *root, const char *dev, const char *attr) {
    char buf[32];
    read_attr(root, dev, attr, buf, sizeof(buf));
    return buf[0] ? atoi(buf) : -1;
}

static size_t discover_power(const char *root, power_device_t *devs, size_t max_devs) {
    char syspath[4096];
    if (shreed_path_join(syspath, sizeof(syspath), root, "/sys/class/power_supply") != 0) return 0;
    DIR *d = opendir(syspath);
    if (!d) return 0;

    struct dirent *ent;
    size_t count = 0;
    while ((ent = readdir(d)) && count < max_devs) {
        if (ent->d_name[0] == '.') continue;
        power_device_t *p = &devs[count];
        memset(p, 0, sizeof(*p));
        snprintf(p->name, sizeof(p->name), "%s", ent->d_name);

        read_attr(root, p->name, "type", p->type, sizeof(p->type));
        read_attr(root, p->name, "status", p->status, sizeof(p->status));
        read_attr(root, p->name, "health", p->health, sizeof(p->health));
        p->capacity = read_int_attr(root, p->name, "capacity");
        p->present = read_int_attr(root, p->name, "present") != 0;
        p->online = read_int_attr(root, p->name, "online") == 1;
        count++;
    }
    closedir(d);
    return count;
}

int shreed_collect_battery(const char *root, char *buffer, size_t size) {
    power_device_t devs[MAX_POWER_DEVICES];
    size_t total = discover_power(root, devs, MAX_POWER_DEVICES);
    shreed_json_t json;
    shreed_json_init(&json, buffer, size);

    shreed_json_append(&json, "{\"ok\":true,\"result\":{\"batteries\":[");
    size_t bat_count = 0;
    for (size_t i = 0; i < total; i++) {
        if (strcmp(devs[i].type, "Battery") != 0) continue;
        if (bat_count++) shreed_json_append(&json, ",");
        shreed_json_append(&json, "{\"name\":"); shreed_json_string(&json, devs[i].name);
        shreed_json_append(&json, ",\"status\":"); shreed_json_string(&json, devs[i].status[0] ? devs[i].status : "Unknown");
        shreed_json_append(&json, ",\"health\":"); shreed_json_string(&json, devs[i].health[0] ? devs[i].health : "Good");
        shreed_json_append(&json, ",\"capacity\":"); shreed_json_uint64(&json, devs[i].capacity >= 0 ? (uint64_t)devs[i].capacity : 0);
        shreed_json_append(&json, ",\"present\":"); shreed_json_append(&json, devs[i].present ? "true" : "false");
        shreed_json_append(&json, "}");
    }
    shreed_json_append(&json, "],\"count\":"); shreed_json_uint64(&json, bat_count);
    shreed_json_append(&json, "}}");
    return json.failed ? -1 : 0;
}

int shreed_collect_power(const char *root, char *buffer, size_t size) {
    power_device_t devs[MAX_POWER_DEVICES];
    size_t total = discover_power(root, devs, MAX_POWER_DEVICES);
    shreed_json_t json;
    shreed_json_init(&json, buffer, size);

    bool ac_online = false;
    int bat_capacity_total = 0;
    size_t bat_count = 0;
    const char *overall_status = "unknown";

    for (size_t i = 0; i < total; i++) {
        if (strcmp(devs[i].type, "Mains") == 0 || strncmp(devs[i].name, "ADP", 3) == 0 || strncmp(devs[i].name, "AC", 2) == 0) {
            if (devs[i].online) ac_online = true;
        } else if (strcmp(devs[i].type, "Battery") == 0) {
            bat_count++;
            if (devs[i].capacity >= 0) bat_capacity_total += devs[i].capacity;
            if (devs[i].status[0]) overall_status = devs[i].status;
        }
    }

    int avg_capacity = bat_count > 0 ? (bat_capacity_total / (int)bat_count) : -1;

    shreed_json_append(&json, "{\"ok\":true,\"result\":{");
    shreed_json_append(&json, "\"ac_online\":"); shreed_json_append(&json, ac_online ? "true" : "false");
    shreed_json_append(&json, ",\"battery_count\":"); shreed_json_uint64(&json, bat_count);
    shreed_json_append(&json, ",\"battery_percent\":");
    if (avg_capacity >= 0) shreed_json_uint64(&json, (uint64_t)avg_capacity);
    else shreed_json_append(&json, "null");
    shreed_json_append(&json, ",\"battery_status\":"); shreed_json_string(&json, overall_status);
    shreed_json_append(&json, "}}");
    return json.failed ? -1 : 0;
}
