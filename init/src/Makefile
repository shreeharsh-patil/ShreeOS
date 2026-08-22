# init/src/Makefile — Cross-compile the ShreeOS init, initctl, and shree-auth binaries
#
# Usage:
#   make              # build init, initctl, shree-auth
#   make clean        # remove build artifacts

CROSS_COMPILE ?= $(or ${CROSS_COMPILE}, x86_64-shreeos-linux-gnu-)
CC := $(CROSS_COMPILE)gcc
CFLAGS := -static -Os -Wall -Wextra
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
