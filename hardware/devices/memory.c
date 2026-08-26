#include "devices.h"

#include <stdio.h>

int shreed_collect_memory(const char *root, char *buffer, size_t size) {
    uint64_t kibibytes = 0;
    shreed_json_t json;

    {
        char path[4096];
        char line[256];
        unsigned long long parsed;
        FILE *file = NULL;
        if (shreed_path_join(path, sizeof(path), root, "/proc/meminfo") == 0) file = fopen(path, "r");
        if (file) {
            while (fgets(line, sizeof(line), file)) {
                if (sscanf(line, "MemTotal: %llu kB", &parsed) == 1) {
                    kibibytes = (uint64_t)parsed;
                    break;
                }
            }
            fclose(file);
        }
    }
    shreed_json_init(&json, buffer, size);
    shreed_json_append(&json, "{\"ok\":true,\"result\":{\"total_bytes\":");
    shreed_json_uint64(&json, kibibytes * 1024U);
    shreed_json_append(&json, ",\"available\":");
    shreed_json_append(&json, kibibytes ? "true" : "false");
    shreed_json_append(&json, "}}");
    return json.failed ? -1 : 0;
}
