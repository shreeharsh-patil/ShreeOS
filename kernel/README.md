# Kernel

**Status:** implemented — Phase 3 of the implementation plan.
**Kernel version:** Linux 6.18 LTS

## Purpose

Cross-compiles a mainline Linux kernel for `x86_64`, configured for
QEMU boot testing with embedded initramfs. Produces a `bzImage` and
kernel modules that later phases (rootfs, ISO builder) consume.

## Layout

```
kernel/
├── configs/
│   ├── x86_64-minimal.config      # Minimal overrides for QEMU boot
│   └── x86_64-generic.config      # Broader hardware support (planned)
├── scripts/
│   ├── common.sh                  # Shared helpers, paths, host verification
│   └── build-kernel.sh            # Fetch → configure → cross-compile → install
├── initramfs/
│   ├── init.c                     # Minimal C init (no libc, raw syscalls)
│   └── Makefile                   # Compiles init.c → cpio.gz archive
├── sources.list                   # Pinned kernel URL + SHA-256
└── README.md                      # This file
```

## Building

```bash
# Prerequisites: Phase 1 cross-compiler built in $LUMEN_TOOLS
# Host packages: gcc, make, bc, flex, bison, openssl, pkg-config, cpio, gzip

bash kernel/scripts/build-kernel.sh
```

**Options:**
- `--skip-init`: Skip rebuilding the initramfs (use if you already have one)
- `--help`: Show usage

## Outputs

| Artifact | Path |
|----------|------|
| Kernel binary | `build/build-kernel/arch/x86/boot/bzImage` |
| Kernel config | `build/build-kernel/.config` |
| Kernel modules | `build/rootfs/lib/modules/` (installed) |
| Initramfs | `kernel/initramfs/initramfs.cpio.gz` |

## Testing

```bash
# Quick syntax check
bash -n kernel/scripts/build-kernel.sh

# Verify the initramfs compiles
make -C kernel/initramfs clean all

# Full QEMU boot test (requires qemu-system-x86_64)
bash tests/qemu/boot-kernel-only.sh
```

## Config Strategy

The kernel starts from `make ARCH=x86_64 defconfig` (a good general-purpose
baseline), then applies targeted overrides from `configs/x86_64-minimal.config`
using the kernel's own `scripts/kconfig/merge_config.sh`. This keeps the
config files small (~30 lines) and maintainable — you only specify what
differs from the default.

### Minimal vs. Generic

- **`x86_64-minimal.config`** — just enough to boot under QEMU with virtio
  block/net, ext4 rootfs, serial console, and embedded initramfs. Fast to
  build (~5 minutes with `-j$(nproc)`).
- **`x86_64-generic.config`** — broader hardware support for real hardware
  and ISO builds. Planned for a later phase.

## Adding Hardware Support

To add a driver or feature:

1. Run `make ARCH=x86_64 menuconfig` in the kernel build directory
2. Enable the desired options
3. Extract the diff: `scripts/diffconfig .config.old .config`
4. Add the relevant `CONFIG_*` lines to the appropriate config file

Or use the scripting approach for CI-friendly changes:
```bash
./scripts/config --file .config --enable CONFIG_XXX
make ARCH=x86_64 olddefconfig
```
