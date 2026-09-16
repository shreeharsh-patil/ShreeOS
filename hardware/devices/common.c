#include "devices.h"

#include <dirent.h>
#include <errno.h>
#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

void shreed_json_init(shreed_json_t *json, char *buffer, size_t capacity) {
    json->buffer = buffer;
    json->capacity = capacity;
    json->length = 0;
    json->failed = capacity == 0;
    if (capacity > 0) buffer[0] = '\0';
}

void shreed_json_append(shreed_json_t *json, const char *text) {
    if (!text) return;
    shreed_json_append_n(json, text, strlen(text));
}

void shreed_json_append_n(shreed_json_t *json, const char *text, size_t length) {

    if (!json || !text || json->failed) return;
    if (length >= json->capacity - json->length) {
        json->failed = true;
        return;
    }
    memcpy(json->buffer + json->length, text, length);
    json->length += length;
    json->buffer[json->length] = '\0';
}

void shreed_json_string(shreed_json_t *json, const char *value) {
    if (!value) {
        shreed_json_append(json, "null");
        return;
    }
    shreed_json_append(json, "\"");
    for (const unsigned char *cursor = (const unsigned char *)value; *cursor && !json->failed; cursor++) {
        char escaped[7];
        if (*cursor == '"' || *cursor == '\\') {
            escaped[0] = '\\';
            escaped[1] = (char)*cursor;
            escaped[2] = '\0';
            shreed_json_append(json, escaped);
        } else if (*cursor < 0x20) {
            snprintf(escaped, sizeof(escaped), "\\u%04x", *cursor);
            shreed_json_append(json, escaped);
        } else {
            escaped[0] = (char)*cursor;
            escaped[1] = '\0';
            shreed_json_append(json, escaped);
        }
    }
    shreed_json_append(json, "\"");
}

void shreed_json_uint64(shreed_json_t *json, uint64_t value) {
    char number[32];
    snprintf(number, sizeof(number), "%llu", (unsigned long long)value);
    shreed_json_append(json, number);
}

int shreed_path_join(char *buffer, size_t size, const char *root, const char *path) {
    int written;
    if (!buffer || !root || !path || path[0] != '/') return -1;
    written = snprintf(buffer, size, "%s%s", root, path);
    return written >= 0 && (size_t)written < size ? 0 : -1;
}

int shreed_read_file(const char *root, const char *path, char *buffer, size_t size) {
    char full_path[PATH_MAX];
    FILE *file;
    size_t length;

    if (!buffer || size == 0 || shreed_path_join(full_path, sizeof(full_path), root, path) != 0) return -1;
    file = fopen(full_path, "r");
    if (!file) return -1;
    if (!fgets(buffer, (int)size, file)) {
        fclose(file);
        return -1;
    }
    fclose(file);
    length = strcspn(buffer, "\r\n");
    buffer[length] = '\0';
    return 0;
}

int shreed_read_u64(const char *root, const char *path, uint64_t *value) {
    char text[64];
    char *end;
    unsigned long long parsed;

    if (!value || shreed_read_file(root, path, text, sizeof(text)) != 0) return -1;
    errno = 0;
    parsed = strtoull(text, &end, 10);
    if (errno != 0 || end == text || *end != '\0') return -1;
    *value = (uint64_t)parsed;
    return 0;
}

int shreed_list_directory(const char *root, const char *path,
                          int (*visitor)(const char *, void *), void *context) {
    char full_path[PATH_MAX];
    DIR *directory;
    struct dirent *entry;
    int result = 0;

    if (!visitor || shreed_path_join(full_path, sizeof(full_path), root, path) != 0) return -1;
    directory = opendir(full_path);
    if (!directory) return -1;
    while ((entry = readdir(directory)) != NULL) {
        if (entry->d_name[0] == '.') continue;
        if (visitor(entry->d_name, context) != 0) {
            result = -1;
            break;
        }
    }
    closedir(directory);
    return result;
}

const char *shreed_pci_vendor_name(const char *vendor) {
    if (!vendor) return NULL;
    if (strcmp(vendor, "0x8086") == 0) return "Intel";
    if (strcmp(vendor, "0x1002") == 0) return "AMD";
    if (strcmp(vendor, "0x10de") == 0) return "NVIDIA";
    return NULL;
}

void shreed_pci_driver(const char *root, const char *device_path, char *buffer, size_t size) {
    char path[PATH_MAX];
    char target[PATH_MAX];
    const char *name;
    ssize_t length;

    if (!buffer || size == 0) return;
    buffer[0] = '\0';
    if (snprintf(path, sizeof(path), "%s%s/driver", root, device_path) >= (int)sizeof(path)) return;
    length = readlink(path, target, sizeof(target) - 1);
    if (length <= 0) return;
    target[length] = '\0';
    name = strrchr(target, '/');
    snprintf(buffer, size, "%s", name ? name + 1 : target);
}
