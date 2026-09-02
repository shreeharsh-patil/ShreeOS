#ifndef SHREED_DEVICES_H
#define SHREED_DEVICES_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

typedef struct {
    char *buffer;
    size_t capacity;
    size_t length;
    bool failed;
} shreed_json_t;

void shreed_json_init(shreed_json_t *json, char *buffer, size_t capacity);
void shreed_json_append(shreed_json_t *json, const char *text);
void shreed_json_append_n(shreed_json_t *json, const char *text, size_t length);
void shreed_json_string(shreed_json_t *json, const char *value);
void shreed_json_uint64(shreed_json_t *json, uint64_t value);
int shreed_read_file(const char *root, const char *path, char *buffer, size_t size);
int shreed_read_u64(const char *root, const char *path, uint64_t *value);
int shreed_list_directory(const char *root, const char *path,
                          int (*visitor)(const char *, void *), void *context);
int shreed_path_join(char *buffer, size_t size, const char *root, const char *path);
const char *shreed_pci_vendor_name(const char *vendor);
void shreed_pci_driver(const char *root, const char *device_path, char *buffer, size_t size);

int shreed_collect_cpu(const char *root, char *buffer, size_t size);
int shreed_collect_gpu(const char *root, char *buffer, size_t size);
int shreed_collect_memory(const char *root, char *buffer, size_t size);
int shreed_collect_storage(const char *root, char *buffer, size_t size);
int shreed_collect_pci(const char *root, char *buffer, size_t size);
int shreed_collect_usb(const char *root, char *buffer, size_t size);
int shreed_collect_network(const char *root, char *buffer, size_t size);
int shreed_collect_ethernet(const char *root, char *buffer, size_t size);
int shreed_collect_drivers(const char *root, char *buffer, size_t size, bool missing_only);
int shreed_collect_firmware(const char *root, char *buffer, size_t size);
int shreed_collect_diagnostics(const char *root, char *buffer, size_t size);
int shreed_collect_hardware(const char *root, char *buffer, size_t size);
int shreed_collect_battery(const char *root, char *buffer, size_t size);
int shreed_collect_power(const char *root, char *buffer, size_t size);
int shreed_collect_brightness(const char *root, char *buffer, size_t size);
int shreed_collect_audio(const char *root, char *buffer, size_t size);
int shreed_collect_display(const char *root, char *buffer, size_t size);

#endif
