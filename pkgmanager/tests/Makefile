# pkgmanager/tests/Makefile — Unit tests for lpm
CROSS_COMPILE ?=
CC := $(CROSS_COMPILE)gcc
CFLAGS := -std=gnu11 -Wall -Wextra -Os -g -I../src
LDFLAGS := -static

SRCS := ../src/json.c ../src/manifest.c
TESTS := test-manifest

.PHONY: all clean test

all: $(TESTS)

test-manifest: test-manifest.c $(SRCS)
	$(CC) $(CFLAGS) $(LDFLAGS) -o $@ $^

test: $(TESTS)
	./test-manifest

clean:
	rm -f $(TESTS)
