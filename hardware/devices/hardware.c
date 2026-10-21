#include "devices.h"

#include <stdio.h>
#include <string.h>
#include <sys/utsname.h>

static void append_result(shreed_json_t *json, const char *response, bool complete) {
    const char *result;
    size_t length;

    /* A collector that ran out of buffer space leaves a truncated fragment
     * behind, so only a complete result may be embedded. */
    if (!complete) {
        shreed_json_append(json, "null");
        return;
    }
    result = strstr(response, "\"result\":");
    if (!result) {
        shreed_json_append(json, "null");
        return;
    }
    result += strlen("\"result\":");
    length = strlen(result);
    if (length == 0 || result[length - 1] != '}') {
        shreed_json_append(json, "null");
        return;
    }
    shreed_json_append_n(json, result, length - 1);
}

int shreed_collect_hardware(const char *root, char *buffer, size_t size) {
    char cpu[1024] = {0};
    char gpu[1024] = {0};
    char memory[512] = {0};
    char storage[4096] = {0};
    char network[2048] = {0};
    struct utsname system_info;
    shreed_json_t json;
    bool cpu_complete, gpu_complete, memory_complete, storage_complete, network_complete;

    /* The result document is opened before the collectors run: appending to
     * an uninitialised builder would corrupt the response. */
    shreed_json_init(&json, buffer, size);
    cpu_complete = shreed_collect_cpu(root, cpu, sizeof(cpu)) == 0;
    gpu_complete = shreed_collect_gpu(root, gpu, sizeof(gpu)) == 0;
    memory_complete = shreed_collect_memory(root, memory, sizeof(memory)) == 0;
    storage_complete = shreed_collect_storage(root, storage, sizeof(storage)) == 0;
    network_complete = shreed_collect_network(root, network, sizeof(network)) == 0;
    memset(&system_info, 0, sizeof(system_info));
    (void)uname(&system_info);

    shreed_json_append(&json, "{\"ok\":true,\"result\":{\"cpu\":");
    append_result(&json, cpu, cpu_complete);
    shreed_json_append(&json, ",\"gpu\":");
    append_result(&json, gpu, gpu_complete);
    shreed_json_append(&json, ",\"memory\":");
    append_result(&json, memory, memory_complete);
    shreed_json_append(&json, ",\"storage\":");
    append_result(&json, storage, storage_complete);
    shreed_json_append(&json, ",\"network\":");
    append_result(&json, network, network_complete);
    shreed_json_append(&json, ",\"architecture\":");
    shreed_json_string(&json, system_info.machine[0] ? system_info.machine : NULL);
    shreed_json_append(&json, ",\"kernel\":");
    shreed_json_string(&json, system_info.release[0] ? system_info.release : NULL);
    shreed_json_append(&json, "}}");
    return json.failed ? -1 : 0;
}
