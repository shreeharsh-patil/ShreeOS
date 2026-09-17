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
sudo bash installer/scripts/install-to-disk.sh /dev/sda

# Non-interactive (for testing). Passwords are read from a private file and
# are never accepted as command-line arguments:
umask 077
printf '%s\n%s\n' 'root-password' 'optional-user-password' > /tmp/shreeos-credentials
sudo bash installer/scripts/install-to-disk.sh /dev/sda --yes \
  --hostname=shreeos --username=shree \
  --credentials-file=/tmp/shreeos-credentials
rm -f /tmp/shreeos-credentials
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
