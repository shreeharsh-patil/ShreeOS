# init/src/Makefile — Cross-compile the ShreeOS init binary
#
# Usage:
#   make              # build init (requires env: CROSS_COMPILE, LUMEN_TOOLS)
#   make clean        # remove build artifacts
#
# The CROSS_COMPILE env var (e.g. x86_64-shreeos-linux-gnu-) is set
# by kernel/scripts/common.sh.  Alternatively pass it explicitly:
#   make CROSS_COMPILE=x86_64-shreeos-linux-gnu-

CROSS_COMPILE ?= $(or ${CROSS_COMPILE}, x86_64-shreeos-linux-gnu-)
CC := $(CROSS_COMPILE)gcc
CFLAGS := -static -Os -Wall -Wextra
LDFLAGS := -static

SRC := init.c
BIN := init

.PHONY: all clean

all: $(BIN)

$(BIN): $(SRC)
	$(CC) $(CFLAGS) $(LDFLAGS) -o $@ $<

clean:
	rm -f $(BIN)
