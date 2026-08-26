#include "devices.h"

#include <arpa/inet.h>
#include <ifaddrs.h>
#include <net/if.h>
#include <stdio.h>
#include <string.h>

#define MAX_INTERFACES 32
typedef struct { char name[IF_NAMESIZE], mac[32], state[32], link[16]; bool ethernet; } interface_t;
typedef struct { interface_t items[MAX_INTERFACES]; size_t count; } interface_list_t;

static bool valid_name(const char *s) {
    if (!s || !*s || strlen(s) >= IF_NAMESIZE) return false;
    for (; *s; s++) if (!(*s == '-' || *s == '_' || *s == '.' || (*s >= 'a' && *s <= 'z') || (*s >= 'A' && *s <= 'Z') || (*s >= '0' && *s <= '9'))) return false;
    return true;
}
static int add_interface(const char *entry, void *opaque) {
    interface_list_t *list = opaque;
    if (valid_name(entry) && list->count < MAX_INTERFACES) snprintf(list->items[list->count++].name, IF_NAMESIZE, "%s", entry);
    return 0;
}
static void attribute(const char *root, const char *name, const char *attr, char *out, size_t size) {
    char path[256];
    if (snprintf(path, sizeof(path), "/sys/class/net/%s/%s", name, attr) >= (int)sizeof(path) || shreed_read_file(root, path, out, size) != 0) out[0] = '\0';
}
static void discover(const char *root, interface_list_t *list) {
    memset(list, 0, sizeof(*list)); (void)shreed_list_directory(root, "/sys/class/net", add_interface, list);
    for (size_t i = 0; i < list->count; i++) {
        char type[16], carrier[16]; interface_t *item = &list->items[i];
        attribute(root, item->name, "address", item->mac, sizeof(item->mac)); attribute(root, item->name, "operstate", item->state, sizeof(item->state));
        attribute(root, item->name, "carrier", carrier, sizeof(carrier)); attribute(root, item->name, "type", type, sizeof(type));
        item->ethernet = strcmp(type, "1") == 0 && strcmp(item->name, "lo") != 0;
        snprintf(item->link, sizeof(item->link), "%s", strcmp(carrier, "1") == 0 ? "up" : "down");
        if (!item->state[0]) snprintf(item->state, sizeof(item->state), "unknown");
    }
}
static void addresses(shreed_json_t *json, const char *name, int family) {
    struct ifaddrs *all = NULL; bool first = true; char value[INET6_ADDRSTRLEN];
    shreed_json_append(json, "[");
    if (getifaddrs(&all) == 0) {
        for (struct ifaddrs *a = all; a; a = a->ifa_next) {
            void *source;
            if (!a->ifa_addr || strcmp(a->ifa_name, name) || a->ifa_addr->sa_family != family) continue;
            source = family == AF_INET ? (void *)&((struct sockaddr_in *)a->ifa_addr)->sin_addr : (void *)&((struct sockaddr_in6 *)a->ifa_addr)->sin6_addr;
            if (!inet_ntop(family, source, value, sizeof(value))) continue;
            if (!first) shreed_json_append(json, ",");
            shreed_json_string(json, value);
            first = false;
        }
        freeifaddrs(all);
    }
    shreed_json_append(json, "]");
}
static void dns(shreed_json_t *json, const char *root) {
    char path[4096], line[256], value[INET6_ADDRSTRLEN]; FILE *file; bool first = true;
    shreed_json_append(json, "[");
    if (shreed_path_join(path, sizeof(path), root, "/etc/resolv.conf") == 0 && (file = fopen(path, "r"))) {
        while (fgets(line, sizeof(line), file)) {
            if (sscanf(line, " nameserver %45s", value) != 1 && sscanf(line, "nameserver %45s", value) != 1) continue;
            if (inet_pton(AF_INET, value, &(struct in_addr){0}) != 1 && inet_pton(AF_INET6, value, &(struct in6_addr){0}) != 1) continue;
            if (!first) shreed_json_append(json, ",");
            shreed_json_string(json, value);
            first = false;
        }
        fclose(file);
    }
    shreed_json_append(json, "]");
}
static void gateway(const char *root, char *out, size_t size) {
    char path[4096], line[256]; FILE *file; unsigned long destination, next_hop, flags;
    out[0] = '\0';
    if (shreed_path_join(path, sizeof(path), root, "/proc/net/route") != 0 || !(file = fopen(path, "r"))) return;
    while (fgets(line, sizeof(line), file)) if (sscanf(line, "%*s %lx %lx %lx", &destination, &next_hop, &flags) == 3 && destination == 0 && (flags & 2)) { struct in_addr ip = { .s_addr = (uint32_t)next_hop }; (void)inet_ntop(AF_INET, &ip, out, size); break; }
    fclose(file);
}
static int collect(const char *root, char *buffer, size_t size, bool ethernet_only) {
    interface_list_t list; shreed_json_t json; char route[INET_ADDRSTRLEN]; size_t count = 0;
    discover(root, &list); gateway(root, route, sizeof(route)); shreed_json_init(&json, buffer, size);
    shreed_json_append(&json, "{\"ok\":true,\"result\":{\"interfaces\":[");
    for (size_t i = 0; i < list.count; i++) { interface_t *item = &list.items[i]; if (ethernet_only && !item->ethernet) continue;
        if (count++) shreed_json_append(&json, ",");
        shreed_json_append(&json, "{\"name\":");
        shreed_json_string(&json, item->name);
        shreed_json_append(&json, ",\"type\":"); shreed_json_string(&json, item->ethernet ? "ethernet" : "other"); shreed_json_append(&json, ",\"state\":"); shreed_json_string(&json, item->state);
        shreed_json_append(&json, ",\"link_state\":"); shreed_json_string(&json, item->link); shreed_json_append(&json, ",\"connected\":"); shreed_json_append(&json, strcmp(item->link, "up") == 0 ? "true" : "false");
        shreed_json_append(&json, ",\"mac_address\":"); shreed_json_string(&json, item->mac[0] ? item->mac : NULL); shreed_json_append(&json, ",\"ipv4_addresses\":"); addresses(&json, item->name, AF_INET); shreed_json_append(&json, ",\"ipv6_addresses\":"); addresses(&json, item->name, AF_INET6); shreed_json_append(&json, "}"); }
    shreed_json_append(&json, "],\"count\":"); shreed_json_uint64(&json, count); shreed_json_append(&json, ",\"default_gateway\":"); shreed_json_string(&json, route[0] ? route : NULL); shreed_json_append(&json, ",\"dns_servers\":"); dns(&json, root); shreed_json_append(&json, "}}");
    return json.failed ? -1 : 0;
}
int shreed_collect_network(const char *root, char *buffer, size_t size) { return collect(root, buffer, size, false); }
int shreed_collect_ethernet(const char *root, char *buffer, size_t size) { return collect(root, buffer, size, true); }
