# hardware/Makefile — Build the ShreeOS hardware service and client

CROSS_COMPILE ?=
CC := $(CROSS_COMPILE)gcc
CFLAGS := -std=gnu11 -Wall -Wextra -Werror -Os -Iinclude
LDFLAGS := -static

DEVICE_SRCS := devices/common.c devices/cpu.c devices/gpu.c devices/memory.c devices/storage.c devices/pci.c devices/usb.c devices/network.c devices/diagnostics.c devices/hardware.c devices/power.c devices/brightness.c devices/audio.c devices/display.c
DAEMON_SRCS := daemon/shreed.c daemon/ipc.c daemon/events.c daemon/security.c $(DEVICE_SRCS)
CLIENT_SRCS := client/shreedctl.c
BINS := shreed shreedctl

.PHONY: all clean test

all: $(BINS)

shreed: $(DAEMON_SRCS) include/shreed.h

	$(CC) $(CFLAGS) $(LDFLAGS) -o $@ $(DAEMON_SRCS)

shreedctl: $(CLIENT_SRCS) include/shreed.h

	$(CC) $(CFLAGS) $(LDFLAGS) -o $@ $(CLIENT_SRCS)

test:
	$(MAKE) -C tests test

clean:
	rm -f $(BINS)
	$(MAKE) -C tests clean
