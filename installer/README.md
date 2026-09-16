# ShreeOS Installer

The ShreeOS installer partitions a target disk, formats the required filesystems,
copies the built ShreeOS root filesystem, installs GRUB, configures the system
identity/timezone, and writes secure credentials.

> [!WARNING]
> Installation is destructive. The selected target disk is repartitioned and
> existing data on it is lost. Always verify the device with `lsblk` before
> confirming an installation.

## Requirements

Run the installer from a **completed ShreeOS source/build tree**. It currently
uses the staged root filesystem and build artifacts from this repository; it is
not a self-contained installer embedded in the live ISO.

Before installing:

```bash
# From the ShreeOS repository root
bash scripts/doctor.sh --strict

# The supported/recommended build path today is the minimal profile.
bash scripts/build.sh minimal

# Confirm the image/build artifacts and both ISO boot paths.
make PROFILE=minimal verify-iso
```

The installer needs root privileges and host tools including `sfdisk`,
`losetup`, `mkfs.ext4`, `mkfs.vfat`, `mount`, `blkid`,
`grub-install`, `cpio`, and `gzip`. On Ubuntu/Debian these are installed by:

```bash
sudo bash scripts/install-build-deps-apt.sh
```

## Recommended: Guided TUI Installation

The guided installer performs disk safety checks, collects the hostname,
username, passwords and timezone, then shows a final destructive-operation
summary before installation.

```bash
lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINTS,MODEL
sudo bash installer/scripts/installer-tui.sh
```

Do not select the disk that contains the host system or any mounted/active
filesystem. The TUI refuses disks that it detects as actively mounted or used
for swap.

## Scripted Installation

The low-level installer supports:

```text
install-to-disk.sh <disk-device>
  [--yes]
  [--hostname=<name>]
  [--timezone=<zone>]
  --credentials-file=<path>
  [--username=<name>]
  [--boot-mode=both|uefi|bios]
```

Use `--yes` only after verifying the target disk. The default boot mode is
`both`, which requires both BIOS and UEFI GRUB installation to succeed.

### Secure credentials file

Passwords are **not** accepted as command-line arguments. A credentials file is
required for every installation and must:

- be a regular file, not a symlink;
- be owned by the invoking user;
- have mode exactly `0600`;
- contain the root password on line 1;
- optionally contain the primary user's password on line 2.

Example:

```bash
umask 077

read -r -s -p "Root password: " ROOT_PW
printf '\n'
read -r -s -p "User password: " USER_PW
printf '\n'

printf '%s\n%s\n' "$ROOT_PW" "$USER_PW" > /tmp/shreeos-credentials
unset ROOT_PW USER_PW
chmod 600 /tmp/shreeos-credentials

lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINTS,MODEL

sudo bash installer/scripts/install-to-disk.sh /dev/nvme0n1 --yes \
  --hostname=shreeos \
  --timezone=Asia/Kolkata \
  --username=shree \
  --credentials-file=/tmp/shreeos-credentials \
  --boot-mode=both

rm -f /tmp/shreeos-credentials
```

Replace `/dev/nvme0n1` with the whole target disk, not a partition such as
`/dev/nvme0n1p1`.

For a root-only installation, create a one-line credentials file and omit
`--username`.

## Boot Modes

| Mode | Use when | Result |
|---|---|---|
| `both` | General physical/VM compatibility | Installs BIOS and UEFI GRUB; both must succeed |
| `uefi` | UEFI-only systems | Installs x86_64 UEFI GRUB to the EFI System Partition |
| `bios` | Legacy BIOS-only systems | Installs i386-pc GRUB to the target disk |

## Testing the Installer Safely

Run validation tests first:

```bash
make test-installer
```

For a full installation/boot test in QEMU after building the artifacts:

```bash
REQUIRE_ARTIFACTS=1 bash tests/qemu/test-e2e-install-and-boot.sh
```

The E2E test creates a temporary raw disk image, installs ShreeOS to it, then
checks BIOS and UEFI boot paths where the host supports them.

## Troubleshooting

- **Installer says build artifacts are missing:** run `bash scripts/build.sh minimal`.
- **Target disk is refused as active:** unmount its partitions and disable swap
  on that disk, or choose a different disk. Do not bypass this safety check.
- **`grub-install`, `mkfs.vfat`, or another tool is missing:** rerun
  `sudo bash scripts/install-build-deps-apt.sh` and then
  `bash scripts/doctor.sh --strict`.
- **Wrong timezone:** use a zone present under
  `build/rootfs/usr/share/zoneinfo`, for example `UTC` or
  `Asia/Kolkata`.
- **Interrupted/failed installation:** do not assume the target disk is
  bootable. Correct the error and rerun the installer; it verifies the kernel,
  initramfs, GRUB configuration and `fstab` before reporting success.
