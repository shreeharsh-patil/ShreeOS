# Root Filesystem

Assembles the base system, kernel modules, and custom init into a root filesystem layout, ready for ISO packaging or disk installation.

## Layout

```
rootfs/
├── skeleton/etc/       # Config templates (os-release, fstab, resolv.conf)
├── scripts/
│   └── make-rootfs.sh  # Assembly script
└── README.md
```

## Building

```bash
bash rootfs/scripts/make-rootfs.sh
# or via Makefile:
make rootfs
```

## Output

- `build/rootfs/` — assembled root filesystem
- `build/rootfs.cpio.gz` — cpio archive for QEMU boot testing
