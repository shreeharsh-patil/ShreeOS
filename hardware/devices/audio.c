#include "devices.h"

#include <dirent.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define MAX_AUDIO_CARDS 8

typedef struct {
    int index;
    char id[64];
    char name[128];
} audio_card_t;

int shreed_collect_audio(const char *root, char *buffer, size_t size) {
    char path[4096];
    shreed_json_t json;
    shreed_json_init(&json, buffer, size);

    audio_card_t cards[MAX_AUDIO_CARDS];
    size_t count = 0;

    if (shreed_path_join(path, sizeof(path), root, "/proc/asound/cards") == 0) {
        FILE *f = fopen(path, "r");
        if (f) {
            char line[256];
            while (fgets(line, sizeof(line), f) && count < MAX_AUDIO_CARDS) {
                int idx;
                char id[64], name[128];
                /* Format: " 0 [PCH            ]: HDA-Intel - HDA Intel PCH" */
                if (sscanf(line, " %d [%63[^]]]: %127[^\r\n]", &idx, id, name) >= 2) {
                    cards[count].index = idx;
                    /* Trim trailing spaces from ID */
                    for (int len = (int)strlen(id) - 1; len >= 0 && id[len] == ' '; len--) id[len] = '\0';
                    snprintf(cards[count].id, sizeof(cards[count].id), "%s", id);
                    snprintf(cards[count].name, sizeof(cards[count].name), "%s", name);
                    count++;
                }
            }
            fclose(f);
        }
    }

    shreed_json_append(&json, "{\"ok\":true,\"result\":{\"cards\":[");
    for (size_t i = 0; i < count; i++) {
        if (i > 0) shreed_json_append(&json, ",");
        shreed_json_append(&json, "{\"index\":"); shreed_json_uint64(&json, (uint64_t)cards[i].index);
        shreed_json_append(&json, ",\"id\":"); shreed_json_string(&json, cards[i].id);
        shreed_json_append(&json, ",\"name\":"); shreed_json_string(&json, cards[i].name);
        shreed_json_append(&json, "}");
    }
    shreed_json_append(&json, "],\"count\":"); shreed_json_uint64(&json, count);
    shreed_json_append(&json, "}}");
    return json.failed ? -1 : 0;
}
