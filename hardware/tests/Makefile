# hardware/tests/Makefile — Native tests for shreed IPC lifecycle and safety

CC ?= gcc
CFLAGS := -std=gnu11 -Wall -Wextra -Werror -O2 -I../include
TEST := test-shreed
COLLECTOR_TEST := test-collectors
TEST_DAEMON := shreed-test-daemon
DEVICE_SRCS := ../devices/common.c ../devices/cpu.c ../devices/gpu.c ../devices/memory.c ../devices/storage.c ../devices/pci.c ../devices/usb.c ../devices/network.c ../devices/hardware.c
FULL_DAEMON_SRCS := ../daemon/shreed.c ../daemon/ipc.c ../daemon/events.c ../daemon/security.c $(DEVICE_SRCS)
DAEMON_SRCS := ../daemon/ipc.c ../daemon/events.c ../daemon/security.c

.PHONY: all clean test

all: $(TEST) $(COLLECTOR_TEST) $(TEST_DAEMON)

$(TEST): test-shreed.c $(DAEMON_SRCS) ../include/shreed.h $(TEST_DAEMON)

	$(CC) $(CFLAGS) -o $@ test-shreed.c $(DAEMON_SRCS)

$(TEST_DAEMON): $(FULL_DAEMON_SRCS) ../include/shreed.h
	$(CC) $(CFLAGS) -o $@ $(FULL_DAEMON_SRCS)

$(COLLECTOR_TEST): test-collectors.c $(DEVICE_SRCS) ../include/devices.h
	$(CC) $(CFLAGS) -o $@ test-collectors.c $(DEVICE_SRCS)

test: $(TEST) $(COLLECTOR_TEST)
	./$(TEST) ./$(TEST_DAEMON)
	./$(COLLECTOR_TEST) fixtures
	bash ./test-network-boot.sh

clean:
	rm -f $(TEST) $(COLLECTOR_TEST) $(TEST_DAEMON)
