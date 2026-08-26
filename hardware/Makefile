# hardware/Makefile — Build the ShreeOS hardware service and client

CROSS_COMPILE ?= $(or ${CROSS_COMPILE}, x86_64-shreeos-linux-gnu-)
CC := $(CROSS_COMPILE)gcc
CFLAGS := -std=gnu11 -Wall -Wextra -Werror -Os -Iinclude
LDFLAGS := -static

DAEMON_SRCS := daemon/shreed.c daemon/ipc.c daemon/events.c daemon/security.c
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
