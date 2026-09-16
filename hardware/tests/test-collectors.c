#include "devices.h"

#include <stdio.h>
#include <string.h>

static int failures;

#define TEST(name, expression) do { \
    if (expression) printf("PASS: %s\n", name); \
    else { fprintf(stderr, "FAIL: %s\n", name); failures++; } \
} while (0)

int main(int argc, char **argv) {
    char response[16384];
    const char *root;

    if (argc != 2) return 2;
    root = argv[1];
    TEST("CPU fixture", shreed_collect_cpu(root, response, sizeof(response)) == 0 &&
         strstr(response, "Fixture CPU 9000") != NULL && strstr(response, "\"logical_cpus\":2") != NULL);
    TEST("memory fixture", shreed_collect_memory(root, response, sizeof(response)) == 0 &&
         strstr(response, "\"total_bytes\":17179869184") != NULL);
    TEST("GPU fixture", shreed_collect_gpu(root, response, sizeof(response)) == 0 &&
         strstr(response, "Intel GPU (PCI 0x8086:0x1234") != NULL);
    TEST("storage fixture", shreed_collect_storage(root, response, sizeof(response)) == 0 &&
         strstr(response, "Fixture NVMe") != NULL && strstr(response, "\"total_bytes\":536870912000") != NULL);
    TEST("PCI fixture", shreed_collect_pci(root, response, sizeof(response)) == 0 &&
         strstr(response, "0000_00_02.0") != NULL && strstr(response, "\"vendor_name\":\"Intel\"") != NULL);
    TEST("USB fixture", shreed_collect_usb(root, response, sizeof(response)) == 0 &&
         strstr(response, "Fixture USB Device") != NULL && strstr(response, "\"vendor_id\":\"1234\"") != NULL);
    TEST("Ethernet connected", shreed_collect_network(root, response, sizeof(response)) == 0 &&
         strstr(response, "\"name\":\"eth0\"") != NULL && strstr(response, "\"link_state\":\"up\"") != NULL &&
         strstr(response, "\"default_gateway\":\"192.168.50.1\"") != NULL);
    TEST("Ethernet disconnected", strstr(response, "\"name\":\"eth1\"") != NULL &&
         strstr(response, "\"link_state\":\"down\"") != NULL);
    TEST("DNS parsing", strstr(response, "\"dns_servers\":[\"1.1.1.1\",\"2001:4860:4860::8888\"]") != NULL);
    TEST("Ethernet query excludes loopback", shreed_collect_ethernet(root, response, sizeof(response)) == 0 &&
         strstr(response, "\"name\":\"eth0\"") != NULL && strstr(response, "\"name\":\"lo\"") == NULL);
    TEST("no interfaces is graceful", shreed_collect_network("/missing-shreed-fixture", response, sizeof(response)) == 0 &&
         strstr(response, "\"count\":0") != NULL);
    TEST("malformed interface data is ignored", strstr(response, "bad@name") == NULL);
    TEST("driver inventory", shreed_collect_drivers(root, response, sizeof(response), false) == 0 && strstr(response, "0000_00_02.0") != NULL);
    TEST("missing driver", shreed_collect_drivers(root, response, sizeof(response), true) == 0 &&
         strstr(response, "\"driver\":null") != NULL && strstr(response, "attention_required") != NULL);
    TEST("firmware report is conservative", shreed_collect_firmware(root, response, sizeof(response)) == 0 && strstr(response, "no automatic download") != NULL);
    TEST("diagnostic report is read-only", shreed_collect_diagnostics(root, response, sizeof(response)) == 0 && strstr(response, "\"read_only\":true") != NULL);
    TEST("hardware summary fixture", shreed_collect_hardware(root, response, sizeof(response)) == 0 &&
         strstr(response, "Fixture CPU 9000") != NULL && strstr(response, "Fixture NVMe") != NULL);
    TEST("missing hardware is graceful", shreed_collect_cpu("/missing-shreed-fixture", response, sizeof(response)) == 0 &&
         strstr(response, "\"model\":null") != NULL);
    printf("%d failures\n", failures);
    return failures ? 1 : 0;
}
