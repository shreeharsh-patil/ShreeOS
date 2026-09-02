#include "devices.h"

#include <dirent.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define MAX_DISPLAYS 8

typedef struct {
    char connector[256];
    char status[32];
    char enabled[32];
    char current_mode[128];
} display_info_t;

static void read_attr(const char *root, const char *conn, const char *attr, char *out, size_t sz) {
    char path[512];
    out[0] = '\0';
    if (snprintf(path, sizeof(path), "/sys/class/drm/%s/%s", conn, attr) < (int)sizeof(path)) {
        (void)shreed_read_file(root, path, out, sz);
    }
}

int shreed_collect_display(const char *root, char *buffer, size_t size) {
    char syspath[4096];
    shreed_json_t json;
    shreed_json_init(&json, buffer, size);

    if (shreed_path_join(syspath, sizeof(syspath), root, "/sys/class/drm") != 0) {
        shreed_json_append(&json, "{\"ok\":true,\"result\":{\"displays\":[],\"count\":0}}");
        return 0;
    }

    DIR *d = opendir(syspath);
    shreed_json_append(&json, "{\"ok\":true,\"result\":{\"displays\":[");
    size_t count = 0;

    if (d) {
        struct dirent *ent;
        while ((ent = readdir(d)) && count < MAX_DISPLAYS) {
            /* Look for cardX-Connector entries (e.g. card0-eDP-1, card0-HDMI-A-1) */
            if (ent->d_name[0] == '.' || !strchr(ent->d_name, '-')) continue;

            display_info_t disp;
            memset(&disp, 0, sizeof(disp));
            snprintf(disp.connector, sizeof(disp.connector), "%s", ent->d_name);

            read_attr(root, ent->d_name, "status", disp.status, sizeof(disp.status));
            read_attr(root, ent->d_name, "enabled", disp.enabled, sizeof(disp.enabled));

            /* Read first mode from modes file */
            char modes_path[512];
            char modes_buf[128];
            if (snprintf(modes_path, sizeof(modes_path), "/sys/class/drm/%s/modes", ent->d_name) < (int)sizeof(modes_path) &&
                shreed_read_file(root, modes_path, modes_buf, sizeof(modes_buf)) == 0) {
                char *nl = strchr(modes_buf, '\n');
                if (nl) *nl = '\0';
                snprintf(disp.current_mode, sizeof(disp.current_mode), "%s", modes_buf);
            }

            if (count++) shreed_json_append(&json, ",");
            shreed_json_append(&json, "{\"connector\":"); shreed_json_string(&json, disp.connector);
            shreed_json_append(&json, ",\"status\":"); shreed_json_string(&json, disp.status[0] ? disp.status : "unknown");
            shreed_json_append(&json, ",\"connected\":"); shreed_json_append(&json, strcmp(disp.status, "connected") == 0 ? "true" : "false");
            shreed_json_append(&json, ",\"enabled\":"); shreed_json_string(&json, disp.enabled[0] ? disp.enabled : "unknown");
            shreed_json_append(&json, ",\"resolution\":"); shreed_json_string(&json, disp.current_mode[0] ? disp.current_mode : NULL);
            shreed_json_append(&json, "}");
        }
        closedir(d);
    }

    shreed_json_append(&json, "],\"count\":"); shreed_json_uint64(&json, count);
    shreed_json_append(&json, "}}");
    return json.failed ? -1 : 0;
}
