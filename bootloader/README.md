# Bootloader

GRUB2 configuration templates and installation scripts for hybrid BIOS/UEFI boot.

## Layout

```
bootloader/
├── grub/grub.cfg.template    # GRUB menu config (templated with build.conf vars)
├── scripts/install-grub.sh   # Installs GRUB2 BIOS+UEFI to ISO staging directory
└── README.md
```

## Usage

```bash
# Install GRUB2 into an ISO staging directory:
bash bootloader/scripts/install-grub.sh /path/to/iso-staging
```

## Dependencies

- Host packages: `grub-pc`, `grub-efi`, `grub-common`
- GRUB2 is a host build dependency — not cross-compiled from source
- Minimum GRUB version: 2.04+ for full UEFI support
