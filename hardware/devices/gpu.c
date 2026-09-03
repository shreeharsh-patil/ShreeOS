#include "devices.h"

#include <stdio.h>
#include <string.h>

typedef struct {
    const char *root;
    char name[256];
    bool found;
} gpu_context_t;

static int collect_gpu(const char *entry, void *opaque) {
    gpu_context_t *context = opaque;
    char path[512];
    char vendor[32];
    char device[32];
    char driver[128];
    const char *vendor_name;

    if (context->found || strncmp(entry, "card", 4) != 0) return 0;
    if (snprintf(path, sizeof(path), "/sys/class/drm/%s/device", entry) >= (int)sizeof(path)) return 0;
    {
        char vendor_path[576];
        char device_path[576];
        snprintf(vendor_path, sizeof(vendor_path), "%s/vendor", path);
        snprintf(device_path, sizeof(device_path), "%s/device", path);
        if (shreed_read_file(context->root, vendor_path, vendor, sizeof(vendor)) != 0 ||
            shreed_read_file(context->root, device_path, device, sizeof(device)) != 0) return 0;
    }
    shreed_pci_driver(context->root, path, driver, sizeof(driver));
    vendor_name = shreed_pci_vendor_name(vendor);
    if (vendor_name) {
        snprintf(context->name, sizeof(context->name), "%s GPU (PCI %s:%s%s%s)",
                 vendor_name, vendor, device, driver[0] ? ", driver " : "", driver);
    } else {
        snprintf(context->name, sizeof(context->name), "PCI GPU %s:%s%s%s",
                 vendor, device, driver[0] ? ", driver " : "", driver);
    }
    context->found = true;
    return 0;
}

int shreed_collect_gpu(const char *root, char *buffer, size_t size) {
    gpu_context_t context = { .root = root };
    shreed_json_t json;

    (void)shreed_list_directory(root, "/sys/class/drm", collect_gpu, &context);
    shreed_json_init(&json, buffer, size);
    shreed_json_append(&json, "{\"ok\":true,\"result\":{\"name\":");
    shreed_json_string(&json, context.found ? context.name : NULL);
    shreed_json_append(&json, ",\"available\":");
    shreed_json_append(&json, context.found ? "true" : "false");
    shreed_json_append(&json, "}}");
    return json.failed ? -1 : 0;
}
