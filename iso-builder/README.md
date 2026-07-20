# ISO Builder

Assembles the kernel, root filesystem, and bootloader into a hybrid BIOS/UEFI ISO.

## Layout

```
iso-builder/
├── scripts/build-iso.sh      # Hybrid ISO assembly script
└── README.md
```

## Usage

```bash
# Build the ISO (requires Phase 3 + Phase 4 artifacts):
bash iso-builder/scripts/build-iso.sh

# Output: out/shreeos-<version>.iso
```

## Prerequisites

| Phase | Artifact | Path |
|-------|----------|------|
| 3 | Kernel bzImage | `build/build-kernel/arch/x86/boot/bzImage` |
| 4 | Rootfs archive | `build/rootfs.cpio.gz` |

Host packages: `xorriso`, `grub-pc`, `grub-efi`

## Testing

```bash
# BIOS boot test:
bash tests/qemu/boot-iso-bios.sh

# UEFI boot test (requires ovmf):
bash tests/qemu/boot-iso-uefi.sh
```
