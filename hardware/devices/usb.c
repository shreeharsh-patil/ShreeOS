#include "devices.h"

#include <stdio.h>
#include <string.h>

typedef struct {
    const char *root;
    shreed_json_t *json;
    unsigned int count;
    bool first;
} usb_context_t;

static int collect_usb_device(const char *entry, void *opaque) {
    usb_context_t *context = opaque;
    char base[256];
    char path[320];
    char vendor[32];
    char product_id[32];
    char manufacturer[128];
    char product[256];

    if (context->count >= 64 || strchr(entry, ':') ||
        snprintf(base, sizeof(base), "/sys/bus/usb/devices/%s", entry) >= (int)sizeof(base)) return 0;
    snprintf(path, sizeof(path), "%s/idVendor", base);
    if (shreed_read_file(context->root, path, vendor, sizeof(vendor)) != 0) return 0;
    snprintf(path, sizeof(path), "%s/idProduct", base);
    if (shreed_read_file(context->root, path, product_id, sizeof(product_id)) != 0) return 0;
    snprintf(path, sizeof(path), "%s/manufacturer", base);
    if (shreed_read_file(context->root, path, manufacturer, sizeof(manufacturer)) != 0) manufacturer[0] = '\0';
    snprintf(path, sizeof(path), "%s/product", base);
    if (shreed_read_file(context->root, path, product, sizeof(product)) != 0) product[0] = '\0';

    if (!context->first) shreed_json_append(context->json, ",");
    shreed_json_append(context->json, "{\"path\":");
    shreed_json_string(context->json, entry);
    shreed_json_append(context->json, ",\"vendor_id\":");
    shreed_json_string(context->json, vendor);
    shreed_json_append(context->json, ",\"product_id\":");
    shreed_json_string(context->json, product_id);
    shreed_json_append(context->json, ",\"manufacturer\":");
    shreed_json_string(context->json, manufacturer[0] ? manufacturer : NULL);
    shreed_json_append(context->json, ",\"product\":");
    shreed_json_string(context->json, product[0] ? product : NULL);
    shreed_json_append(context->json, "}");
    context->first = false;
    context->count++;
    return context->json->failed ? -1 : 0;
}

int shreed_collect_usb(const char *root, char *buffer, size_t size) {
    shreed_json_t json;
    usb_context_t context;

    shreed_json_init(&json, buffer, size);
    shreed_json_append(&json, "{\"ok\":true,\"result\":{\"devices\":[");
    context.root = root;
    context.json = &json;
    context.count = 0;
    context.first = true;
    (void)shreed_list_directory(root, "/sys/bus/usb/devices", collect_usb_device, &context);
    shreed_json_append(&json, "],\"count\":");
    shreed_json_uint64(&json, context.count);
    shreed_json_append(&json, "}}");
    return json.failed ? -1 : 0;
}
