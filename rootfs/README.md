# Root Filesystem

`rootfs/scripts/make-rootfs.sh` assembles the ShreeOS target root and writes
the canonical boot archive at `build/initramfs.cpio.gz`.

The ISO builder and QEMU tests consume that same filename. The assembled tree
remains at `build/rootfs/` for inspection and disk installation.
