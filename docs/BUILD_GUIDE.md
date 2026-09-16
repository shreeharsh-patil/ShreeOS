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
# Clone and build everything:
git clone https://github.com/shreeharsh-patil/ShreeOS.git
cd ShreeOS
make all
```

This runs Phases 1-7 end-to-end (toolchain, base system, kernel, rootfs, ISO, packages, desktop). Expect 2-4 hours depending on your machine.

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

### Phase 4: Init + Root Filesystem
```bash
make rootfs
```
Assembles init binary, skeleton configs, kernel modules. Output: `build/rootfs/`.

### Phase 5: Bootable ISO
```bash
make iso
```
Creates a hybrid BIOS/UEFI ISO. Output: `out/shreeos-<version>.iso`.

### Phase 6: Package Manager
```bash
make packages
```
Builds the `lpm` package manager. Output: `pkgmanager/src/lpm`.

### Phase 7: Desktop Environment
```bash
make desktop
```
Builds dwm window manager, st terminal, dmenu launcher. Output: installed to `build/rootfs/`.

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
├── init/                 # Phase 4: PID 1 init
├── rootfs/               # Phase 4: root filesystem assembly
├── bootloader/           # Phase 5: GRUB config
├── iso-builder/          # Phase 5: ISO creation
├── pkgmanager/           # Phase 6: lpm package manager
├── desktop/              # Phase 7: window manager
├── installer/            # Phase 7: disk installer
├── branding/             # Phase 7: distro assets
├── tests/                # Smoke tests
├── build/                # Build artifacts (gitignored)
└── out/                  # Final ISOs (gitignored)
```
