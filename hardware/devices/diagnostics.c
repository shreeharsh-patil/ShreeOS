#include "devices.h"

#include <stdio.h>
#include <string.h>

typedef struct { const char *root; shreed_json_t *json; bool first; unsigned count; bool missing_only; } driver_context_t;

static int driver_entry(const char *entry, void *opaque) {
    driver_context_t *ctx = opaque; char base[256], vendor[32], device[32], driver[128], module_path[320];
    if (ctx->count >= 64 || strchr(entry, '/') || snprintf(base, sizeof(base), "/sys/bus/pci/devices/%s", entry) >= (int)sizeof(base)) return 0;
    if (snprintf(module_path, sizeof(module_path), "%s/vendor", base) >= (int)sizeof(module_path) || shreed_read_file(ctx->root, module_path, vendor, sizeof(vendor)) != 0) return 0;
    snprintf(module_path, sizeof(module_path), "%s/device", base); if (shreed_read_file(ctx->root, module_path, device, sizeof(device)) != 0) return 0;
    shreed_pci_driver(ctx->root, base, driver, sizeof(driver));
    if (ctx->missing_only && driver[0]) return 0;
    if (!ctx->first) shreed_json_append(ctx->json, ",");
    shreed_json_append(ctx->json, "{\"address\":"); shreed_json_string(ctx->json, entry);
    shreed_json_append(ctx->json, ",\"vendor\":"); shreed_json_string(ctx->json, vendor);
    shreed_json_append(ctx->json, ",\"device\":"); shreed_json_string(ctx->json, device);
    shreed_json_append(ctx->json, ",\"driver\":"); shreed_json_string(ctx->json, driver[0] ? driver : NULL);
    shreed_json_append(ctx->json, ",\"firmware\":"); shreed_json_string(ctx->json, "unknown");
    shreed_json_append(ctx->json, ",\"status\":"); shreed_json_string(ctx->json, driver[0] ? "loaded" : "attention_required");
    shreed_json_append(ctx->json, "}"); ctx->first = false; ctx->count++; return ctx->json->failed ? -1 : 0;
}

int shreed_collect_drivers(const char *root, char *buffer, size_t size, bool missing_only) {
    shreed_json_t json; driver_context_t ctx;
    shreed_json_init(&json, buffer, size); shreed_json_append(&json, "{\"ok\":true,\"result\":{\"devices\":[");
    ctx = (driver_context_t){ .root=root, .json=&json, .first=true, .count=0, .missing_only=missing_only };
    (void)shreed_list_directory(root, "/sys/bus/pci/devices", driver_entry, &ctx);
    shreed_json_append(&json, "],\"count\":"); shreed_json_uint64(&json, ctx.count); shreed_json_append(&json, "}}"); return json.failed ? -1 : 0;
}

int shreed_collect_firmware(const char *root, char *buffer, size_t size) {
    char drivers[8192]; const char *start, *end; shreed_json_t json;
    (void)shreed_collect_drivers(root, drivers, sizeof(drivers), false);
    shreed_json_init(&json, buffer, size); shreed_json_append(&json, "{\"ok\":true,\"result\":{\"policy\":\"firmware is supplied by future lpm firmware packages; no automatic download occurs\",\"devices\":");
    /* Kernel sysfs exposes drivers, but not a universal installed-firmware inventory. */
    start = strstr(drivers, "\"devices\":"); start = start ? start + 10 : "[]"; end = strchr(start, ']');
    if (end) shreed_json_append_n(&json, start, (size_t)(end - start + 1)); else shreed_json_append(&json, "[]");
    shreed_json_append(&json, "}}}"); return json.failed ? -1 : 0;
}

int shreed_collect_diagnostics(const char *root, char *buffer, size_t size) {
    char missing[8192]; const char *devices, *end; shreed_json_t json;
    (void)shreed_collect_drivers(root, missing, sizeof(missing), true); devices = strstr(missing, "\"devices\":");
    shreed_json_init(&json, buffer, size); shreed_json_append(&json, "{\"ok\":true,\"result\":{\"read_only\":true,\"findings\":");
    if (devices) { devices += 10; end = strchr(devices, ']'); if (end) shreed_json_append_n(&json, devices, (size_t)(end - devices + 1)); else shreed_json_append(&json, "[]"); }
    else shreed_json_append(&json, "[]");
    shreed_json_append(&json, "}}}"); return json.failed ? -1 : 0;
}
