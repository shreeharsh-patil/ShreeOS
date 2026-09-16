# Building ShreeOS from Source

## Prerequisites

- **OS:** Ubuntu 22.04/24.04 LTS (or a compatible Debian-based host)
- **Architecture:** x86_64
- **Disk:** at least 15 GB free; 30-50 GB recommended
- **RAM:** 8 GB recommended
- **CPU:** 4+ threads recommended

Install the maintained dependency set instead of copying a stale package list:

```bash
sudo bash scripts/install-build-deps-apt.sh
bash scripts/doctor.sh --strict
```

On WSL2, keep the repository under the Linux filesystem (for example
`~/ShreeOS`) and use `make bootstrap-wsl`.

## Quick Start

```bash
# Clone and build the recommended minimal profile:
git clone https://github.com/shreeharsh-patil/ShreeOS.git
cd ShreeOS
sudo bash scripts/install-build-deps-apt.sh
bash scripts/build.sh minimal
```

This runs the source-built toolchain, base system, kernel, target utilities, rootfs and ISO pipeline end-to-end. The native desktop profile is not yet certifiable because its target graphics dependency stack is incomplete; do not treat a deferred desktop build as a finished GUI image.

## Build Stages

### Phase 1: Cross-Compilation Toolchain
```bash
make toolchain
```
Builds `x86_64-shreeos-linux-gnu-` cross-compiler (binutils, GCC, glibc). Output: `build/tools/`.

### Phase 2: Base System
```bash
make base-system
```
Builds ncurses, bash, coreutils, util-linux. Output: `build/rootfs/`.

### Phase 3: Linux Kernel
```bash
make kernel
```
Cross-compiles the kernel with embedded initramfs. Output: `build/build-kernel/arch/x86/boot/bzImage`.

### Phase 4: Target Utilities
```bash
make packages
```
Cross-compiles the custom init, `lpm` package manager and hardware daemon with the ShreeOS target toolchain.

### Phase 5: Desktop Layer
```bash
make desktop
```
Requires the ShreeOS-target X11/Xft/Xinerama, Fontconfig, FreeType, Xorg, xinit and fonts stack. Until that dependency chain is source-built, the strict desktop target correctly refuses certification.

For explicit headless/integration testing only:
```bash
ALLOW_DEFERRED_GRAPHICS=1 make PROFILE=desktop desktop
```

### Phase 6: Init + Root Filesystem
```bash
make rootfs
```
Assembles the target init, runtime libraries, skeleton configs and kernel modules into `build/rootfs/`.

### Phase 7: Bootable ISO
```bash
make iso
```
Creates a hybrid BIOS/UEFI ISO. Output: `out/shreeos-<version>.iso`.

## Testing

```bash
make tests           # run all smoke tests
make toolchain-test  # verify the cross-compiler
```

QEMU boot tests (require built artifacts):
```bash
bash tests/qemu/boot-kernel-only.sh       # kernel + initramfs
bash tests/qemu/boot-full-rootfs.sh       # full rootfs
bash tests/qemu/boot-iso-bios.sh          # ISO (BIOS)
bash tests/qemu/boot-iso-uefi.sh          # ISO (UEFI)
```

## Installing to Disk

> [!CAUTION]
> The installer repartitions and formats the selected whole disk. All existing
> data on that disk is destroyed.

Run installation from a completed ShreeOS source/build tree. The current ISO is
bootable for validation, but it does not contain a self-contained copy of the
source-tree installer.

First verify the target device:

```bash
lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINTS,MODEL
```

Recommended guided installation:

```bash
sudo bash installer/scripts/installer-tui.sh
```

For scripted installation, a secure credentials file is mandatory. It must be a
regular non-symlink file owned by the invoking user with mode `0600`. Line 1
contains the root password and, when `--username` is used, line 2 contains the
user password. Passwords must be at least 8 characters.

```bash
umask 077
read -r -s -p "Root password: " ROOT_PW; printf '\n'
read -r -s -p "User password: " USER_PW; printf '\n'
printf '%s\n%s\n' "$ROOT_PW" "$USER_PW" > /tmp/shreeos-credentials
unset ROOT_PW USER_PW
chmod 600 /tmp/shreeos-credentials

sudo bash installer/scripts/install-to-disk.sh /dev/nvme0n1 --yes \
  --hostname=shreeos \
  --timezone=Asia/Kolkata \
  --username=shree \
  --credentials-file=/tmp/shreeos-credentials \
  --boot-mode=both

rm -f /tmp/shreeos-credentials
```

Replace `/dev/nvme0n1` with the whole target disk. Do not pass a partition such
as `/dev/nvme0n1p1`. Supported boot modes are `both` (default), `uefi`, and
`bios`.

See `installer/README.md` for installer safeguards and troubleshooting.

## Rebuilding

```bash
make clean           # remove build artifacts, keep sources
make distclean       # full reset (removes build/ and out/)
make PROFILE=minimal all FORCE=1  # force rebuild the supported minimal path
```

## Directory Layout

```
ShreeOS/
├── Makefile              # Top-level orchestration
├── build.conf            # Single source of truth for versions
├── toolchain/            # Phase 1: cross-compiler
├── base-system/          # Phase 2: base packages
├── kernel/               # Phase 3: Linux kernel
├── init/                 # Phase 4: target PID 1 init
├── rootfs/               # Phase 6: root filesystem assembly
├── bootloader/           # Phase 7: GRUB config
├── iso-builder/          # Phase 7: ISO creation
├── pkgmanager/           # Phase 4: lpm package manager
├── desktop/              # Phase 5: window manager
├── installer/            # Phase 7: disk installer
├── branding/             # Phase 7: distro assets
├── tests/                # Smoke tests
├── build/                # Build artifacts (gitignored)
└── out/                  # Final ISOs (gitignored)
```
