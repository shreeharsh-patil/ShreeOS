# init/src/Makefile — Cross-compile the ShreeOS init, initctl, and shree-auth binaries
#
# Usage:
#   make              # build init, initctl, shree-auth
#   make clean        # remove build artifacts

CROSS_COMPILE ?=
CC := $(CROSS_COMPILE)gcc
# The version shown by the login prompt comes from the single authoritative
# version source at the repository root, so no C source needs to hardcode one.
SHREEOS_VERSION ?= $(shell tr -d '[:space:]' < ../../VERSION 2>/dev/null || echo unknown)
CFLAGS := -static -Os -Wall -Wextra -DSHREEOS_VERSION=\"$(SHREEOS_VERSION)\"
LDFLAGS := -static
LDLIBS := -lcrypt

BINS := init initctl shree-auth

.PHONY: all clean

all: $(BINS)

init: init.c
	$(CC) $(CFLAGS) $(LDFLAGS) -o $@ $<

initctl: initctl.c
	$(CC) $(CFLAGS) $(LDFLAGS) -o $@ $<

shree-auth: shree-auth.c
	$(CC) $(CFLAGS) $(LDFLAGS) -o $@ $< $(LDLIBS)

clean:
	rm -f $(BINS) *.o
