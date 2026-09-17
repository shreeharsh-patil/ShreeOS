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
	@command -v cpio >/dev/null 2>&1 || { echo "initramfs: cpio is required" >&2; exit 1; }
	@command -v gzip >/dev/null 2>&1 || { echo "initramfs: gzip is required" >&2; exit 1; }
	bash -o pipefail -c 'printf "%s\n" init | cpio -o -H newc --quiet | gzip -n > "$(ARCHIVE)"'
	@gzip -t "$(ARCHIVE)"
	@gzip -dc "$(ARCHIVE)" | cpio -t --quiet | grep -Fxq init || { \
		echo "initramfs: archive does not contain /init" >&2; \
		exit 1; \
	}
	@echo "  initramfs: $(ARCHIVE)"

clean:
	rm -f $(INIT_BIN) $(ARCHIVE)
