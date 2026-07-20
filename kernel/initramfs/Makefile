# kernel/initramfs/Makefile
# Builds a minimal initramfs cpio archive for kernel boot testing.
#
# Usage:
#   make          # build initramfs.cpio.gz
#   make clean    # remove build artifacts
#
# The resulting archive is embedded into the kernel via
# CONFIG_INITRAMFS_SOURCE during the kernel build.

CC := gcc
CFLAGS := -static -nostdlib -Os -ffreestanding -Wall -Wextra

INIT_SRC := init.c
INIT_BIN := init
ARCHIVE := initramfs.cpio.gz

.PHONY: all clean

all: $(ARCHIVE)

$(INIT_BIN): $(INIT_SRC)
	$(CC) $(CFLAGS) -o $@ $<

$(ARCHIVE): $(INIT_BIN)
	echo init | cpio -o -H newc --quiet | gzip -n > $(ARCHIVE)
	@echo "  initramfs: $(ARCHIVE)"

clean:
	rm -f $(INIT_BIN) $(ARCHIVE)
