# Installer

Guided text-mode disk installer for ShreeOS. Partitions, writes the root
filesystem, installs GRUB, and configures first boot.

## Layout

```
installer/
├── scripts/
│   └── install-to-disk.sh   # Main installer (bash, sfdisk, mkfs.ext4)
├── tests/
│   └── test-install.sh      # Non-interactive QEMU install test
└── README.md
```

## Usage

```bash
# Interactive:
bash installer/scripts/install-to-disk.sh /dev/sda

# Non-interactive (for testing):
bash installer/scripts/install-to-disk.sh /dev/sda --yes \
  --hostname=shreeos --root-password=changeme
```

## Testing

```bash
bash installer/tests/test-install.sh
```

Creates a blank 4G QEMU disk, installs to it, boots it, and checks for
the init marker.

## Requirements

- Host tools: `sfdisk`, `mkfs.ext4`, `grub-install`, `rsync` (or `cpio`)
- Run as root for block device access
