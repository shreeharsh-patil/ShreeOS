#include "devices.h"

#include <stdio.h>
#include <string.h>

typedef struct {
    const char *root;
    shreed_json_t *json;
    uint64_t total_bytes;
    unsigned int count;
    bool first;
} storage_context_t;

static bool is_virtual_disk(const char *name) {
    return strncmp(name, "loop", 4) == 0 || strncmp(name, "ram", 3) == 0 ||
           strncmp(name, "zram", 4) == 0 || strncmp(name, "fd", 2) == 0;
}

static int collect_disk(const char *entry, void *opaque) {
    storage_context_t *context = opaque;
    char size_path[256];
    char model_path[256];
    char model[128];
    uint64_t sectors;
    uint64_t bytes;

    if (is_virtual_disk(entry) || context->count >= 32) return 0;
    snprintf(size_path, sizeof(size_path), "/sys/block/%s/size", entry);
    if (shreed_read_u64(context->root, size_path, &sectors) != 0 || sectors > UINT64_MAX / 512U) return 0;
    bytes = sectors * 512U;
    snprintf(model_path, sizeof(model_path), "/sys/block/%s/device/model", entry);
    if (shreed_read_file(context->root, model_path, model, sizeof(model)) != 0) model[0] = '\0';

    if (!context->first) shreed_json_append(context->json, ",");
    shreed_json_append(context->json, "{\"name\":");
    shreed_json_string(context->json, entry);
    shreed_json_append(context->json, ",\"model\":");
    shreed_json_string(context->json, model[0] ? model : NULL);
    shreed_json_append(context->json, ",\"size_bytes\":");
    shreed_json_uint64(context->json, bytes);
    shreed_json_append(context->json, "}");
    context->first = false;
    context->count++;
    if (bytes <= UINT64_MAX - context->total_bytes) context->total_bytes += bytes;
    return context->json->failed ? -1 : 0;
}

int shreed_collect_storage(const char *root, char *buffer, size_t size) {
    shreed_json_t json;
    storage_context_t context;

    shreed_json_init(&json, buffer, size);
    shreed_json_append(&json, "{\"ok\":true,\"result\":{\"disks\":[");
    context.root = root;
    context.json = &json;
    context.total_bytes = 0;
    context.count = 0;
    context.first = true;
    (void)shreed_list_directory(root, "/sys/block", collect_disk, &context);
    shreed_json_append(&json, "],\"count\":");
    shreed_json_uint64(&json, context.count);
    shreed_json_append(&json, ",\"total_bytes\":");
    shreed_json_uint64(&json, context.total_bytes);
    shreed_json_append(&json, "}}");
    return json.failed ? -1 : 0;
}
