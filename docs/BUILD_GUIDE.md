# Building ShreeOS from Source

## Prerequisites

- **OS:** Ubuntu 22.04+ (or Debian-based)
- **Packages:**
  ```bash
  sudo apt update
  sudo apt install -y build-essential bison flex gawk texinfo \
    curl wget patch bzip2 xz-utils bc rsync cpio \
    qemu-system-x86 xorriso grub-pc grub-efi ovmf \
    python3 libssl-dev
  ```
- **Disk:** ~20 GB free for the build

## Quick Start

```bash
# Clone and build the currently complete minimal profile:
git clone https://github.com/shreeharsh-patil/ShreeOS.git
cd ShreeOS
make PROFILE=minimal all
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

```bash
# After building the ISO, install to a target disk:
sudo bash installer/scripts/install-to-disk.sh /dev/sda --yes
```

## Rebuilding

```bash
make clean           # remove build artifacts, keep sources
make distclean       # full reset (removes build/ and out/)
make all FORCE=1     # force rebuild all phases
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
