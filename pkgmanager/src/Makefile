# pkgmanager/src/Makefile — Build the lpm package manager
#
# Usage:
#   make                         # host build (for testing)
#   make CROSS_COMPILE=<prefix>-  # cross-compile for target
#   make clean
#   make test                    # build and run unit tests

CROSS_COMPILE ?=
CC := $(CROSS_COMPILE)gcc
CFLAGS := -std=gnu11 -Wall -Wextra -Os -g
LDFLAGS := -static

SRCS := main.c manifest.c json.c install.c resolve.c sha256.c safeupdate.c
OBJS := $(SRCS:.c=.o)
BIN  := lpm

.PHONY: all clean test

all: $(BIN)

$(BIN): $(OBJS)
	$(CC) $(CFLAGS) $(LDFLAGS) -o $@ $^

%.o: %.c
	$(CC) $(CFLAGS) -c -o $@ $<

test:
	$(MAKE) -C ../tests test

clean:
	rm -f $(OBJS) $(BIN)
	$(MAKE) -C ../tests clean
