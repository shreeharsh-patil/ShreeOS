# Root Filesystem

`rootfs/scripts/make-rootfs.sh` assembles the ShreeOS target root and writes
the canonical boot archive at `build/initramfs.cpio.gz`.

The ISO builder and QEMU tests consume that same filename. The assembled tree
remains at `build/rootfs/` for inspection and disk installation.

After all packages have been staged, `scripts/prune-development-files.sh`
removes static archives, libtool metadata, C headers and build-system metadata
from the runtime tree. Shared libraries, fonts, locales and manual pages remain.
This keeps compiler inputs in the build sysroot instead of carrying them into
the boot image.
