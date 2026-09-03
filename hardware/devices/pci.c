#include "devices.h"

#include <stdio.h>
#include <string.h>

typedef struct {
    const char *root;
    shreed_json_t *json;
    unsigned int count;
    bool first;
} pci_context_t;

static int collect_pci_device(const char *entry, void *opaque) {
    pci_context_t *context = opaque;
    char base[256];
    char field[320];
    char vendor[32];
    char device[32];
    char class_code[32];
    char driver[128];

    if (context->count >= 64 || snprintf(base, sizeof(base), "/sys/bus/pci/devices/%s", entry) >= (int)sizeof(base)) return 0;
    snprintf(field, sizeof(field), "%s/vendor", base);
    if (shreed_read_file(context->root, field, vendor, sizeof(vendor)) != 0) return 0;
    snprintf(field, sizeof(field), "%s/device", base);
    if (shreed_read_file(context->root, field, device, sizeof(device)) != 0) return 0;
    snprintf(field, sizeof(field), "%s/class", base);
    if (shreed_read_file(context->root, field, class_code, sizeof(class_code)) != 0) class_code[0] = '\0';
    shreed_pci_driver(context->root, base, driver, sizeof(driver));

    if (!context->first) shreed_json_append(context->json, ",");
    shreed_json_append(context->json, "{\"address\":");
    shreed_json_string(context->json, entry);
    shreed_json_append(context->json, ",\"vendor\":");
    shreed_json_string(context->json, vendor);
    shreed_json_append(context->json, ",\"vendor_name\":");
    shreed_json_string(context->json, shreed_pci_vendor_name(vendor));
    shreed_json_append(context->json, ",\"device\":");
    shreed_json_string(context->json, device);
    shreed_json_append(context->json, ",\"class\":");
    shreed_json_string(context->json, class_code[0] ? class_code : NULL);
    shreed_json_append(context->json, ",\"driver\":");
    shreed_json_string(context->json, driver[0] ? driver : NULL);
    shreed_json_append(context->json, "}");
    context->first = false;
    context->count++;
    return context->json->failed ? -1 : 0;
}

int shreed_collect_pci(const char *root, char *buffer, size_t size) {
    shreed_json_t json;
    pci_context_t context;

    shreed_json_init(&json, buffer, size);
    shreed_json_append(&json, "{\"ok\":true,\"result\":{\"devices\":[");
    context.root = root;
    context.json = &json;
    context.count = 0;
    context.first = true;
    (void)shreed_list_directory(root, "/sys/bus/pci/devices", collect_pci_device, &context);
    shreed_json_append(&json, "],\"count\":");
    shreed_json_uint64(&json, context.count);
    shreed_json_append(&json, "}}");
    return json.failed ? -1 : 0;
}
