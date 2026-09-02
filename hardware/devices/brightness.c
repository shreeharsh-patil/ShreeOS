#include "devices.h"

#include <dirent.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef struct {
    char name[64];
    int current;
    int max;
    int percent;
} backlight_device_t;

#define MAX_BACKLIGHTS 8

static int read_int_file(const char *root, const char *dev, const char *attr) {
    char path[256];
    char buf[32];
    buf[0] = '\0';
    if (snprintf(path, sizeof(path), "/sys/class/backlight/%s/%s", dev, attr) < (int)sizeof(path)) {
        (void)shreed_read_file(root, path, buf, sizeof(buf));
    }
    return buf[0] ? atoi(buf) : -1;
}

int shreed_collect_brightness(const char *root, char *buffer, size_t size) {
    char syspath[4096];
    shreed_json_t json;
    shreed_json_init(&json, buffer, size);

    if (shreed_path_join(syspath, sizeof(syspath), root, "/sys/class/backlight") != 0) {
        shreed_json_append(&json, "{\"ok\":true,\"result\":{\"devices\":[],\"count\":0}}");
        return 0;
    }

    DIR *d = opendir(syspath);
    shreed_json_append(&json, "{\"ok\":true,\"result\":{\"devices\":[");
    size_t count = 0;

    if (d) {
        struct dirent *ent;
        while ((ent = readdir(d)) && count < MAX_BACKLIGHTS) {
            if (ent->d_name[0] == '.') continue;
            int cur = read_int_file(root, ent->d_name, "brightness");
            int max = read_int_file(root, ent->d_name, "max_brightness");
            int pct = (cur >= 0 && max > 0) ? (cur * 100 / max) : 100;

            if (count++) shreed_json_append(&json, ",");
            shreed_json_append(&json, "{\"name\":"); shreed_json_string(&json, ent->d_name);
            shreed_json_append(&json, ",\"brightness\":"); shreed_json_uint64(&json, cur >= 0 ? (uint64_t)cur : 0);
            shreed_json_append(&json, ",\"max_brightness\":"); shreed_json_uint64(&json, max > 0 ? (uint64_t)max : 100);
            shreed_json_append(&json, ",\"percent\":"); shreed_json_uint64(&json, (uint64_t)pct);
            shreed_json_append(&json, "}");
        }
        closedir(d);
    }

    shreed_json_append(&json, "],\"count\":"); shreed_json_uint64(&json, count);
    shreed_json_append(&json, "}}");
    return json.failed ? -1 : 0;
}
