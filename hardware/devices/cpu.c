#include "devices.h"

#include <stdio.h>
#include <string.h>

static void trim(char *text) {
    char *start = text;
    char *end;
    while (*start == ' ' || *start == '\t') start++;
    if (start != text) memmove(text, start, strlen(start) + 1);
    end = text + strlen(text);
    while (end > text && (end[-1] == ' ' || end[-1] == '\t')) *--end = '\0';
}

int shreed_collect_cpu(const char *root, char *buffer, size_t size) {
    char path[4096];
    char line[512];
    char model[256] = {0};
    FILE *file = NULL;
    unsigned int processors = 0;
    shreed_json_t json;

    if (shreed_path_join(path, sizeof(path), root, "/proc/cpuinfo") == 0) file = fopen(path, "r");
    if (file) {
        while (fgets(line, sizeof(line), file)) {
            char *separator = strchr(line, ':');
            if (!separator) continue;
            *separator++ = '\0';
            trim(line);
            trim(separator);
            if (strcmp(line, "processor") == 0) processors++;
            if (!model[0] && (strcmp(line, "model name") == 0 || strcmp(line, "Hardware") == 0 ||
                              strcmp(line, "Processor") == 0)) {
                snprintf(model, sizeof(model), "%.255s", separator);
            }
        }
        fclose(file);
    }

    shreed_json_init(&json, buffer, size);
    shreed_json_append(&json, "{\"ok\":true,\"result\":{\"model\":");
    shreed_json_string(&json, model[0] ? model : NULL);
    shreed_json_append(&json, ",\"logical_cpus\":");
    shreed_json_uint64(&json, processors);
    shreed_json_append(&json, "}}");
    return json.failed ? -1 : 0;
}
