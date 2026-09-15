#!/usr/bin/env bash
# bootloader/scripts/install-grub-iso.sh — deterministically stage GRUB2 BIOS + UEFI boot files
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SHREEOS_ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$SHREEOS_ROOT_DIR/build.conf"
source "$SHREEOS_ROOT_DIR/scripts/common.sh"

if [ $# -lt 1 ]; then
  shreeos_die "Usage: install-grub-iso.sh <staging-dir> [--cmdline=...]"
fi

STAGING="$1"
shift

CMDLINE_EXTRA=""
for arg in "$@"; do
  case "$arg" in
    --cmdline=*) CMDLINE_EXTRA="${arg#*=}" ;;
    --help|-h)
      echo "Usage: install-grub-iso.sh <staging-dir> [--cmdline=...]"
      exit 0
      ;;
    *) shreeos_die "Unknown option: $arg" ;;
  esac
done

shreeos_require_cmd grub-mkimage dd mformat mmd mcopy

I386_MODULE_DIR="/usr/lib/grub/i386-pc"
if [ ! -d "$I386_MODULE_DIR" ]; then
  shreeos_die "GRUB i386-pc modules not found at $I386_MODULE_DIR (install grub-pc-bin)"
fi
if [ ! -f "$I386_MODULE_DIR/cdboot.img" ]; then
  shreeos_die "GRUB BIOS CD boot image missing: $I386_MODULE_DIR/cdboot.img"
fi

shreeos_step "Installing GRUB2 for ISO staging: ${STAGING}"
mkdir -p   "${STAGING}/boot/grub/i386-pc"   "${STAGING}/boot/grub/x86_64-efi"   "${STAGING}/EFI/BOOT"

# BIOS El Torito image: cdboot.img + a core image that knows how to read ISO9660.
BIOS_CORE="${STAGING}/boot/grub/i386-pc/core.img"
BIOS_ELTORITO="${STAGING}/boot/grub/i386-pc/eltorito.img"

shreeos_log "Generating i386-pc El Torito image"
grub-mkimage   -O i386-pc   -o "$BIOS_CORE"   -p "/boot/grub"   biosdisk iso9660 part_msdos part_gpt normal configfile search search_fs_file   loopback ext2 fat linux font gettext serial terminal test

cat "$I386_MODULE_DIR/cdboot.img" "$BIOS_CORE" > "$BIOS_ELTORITO"

# UEFI executable and FAT El Torito image.
UEFI_EFI="${STAGING}/EFI/BOOT/BOOTX64.EFI"
EFI_IMG="${STAGING}/boot/grub/x86_64-efi/efi.img"

shreeos_log "Generating x86_64-efi boot image"
grub-mkimage   -O x86_64-efi   -o "$UEFI_EFI"   -p "/boot/grub"   iso9660 part_msdos part_gpt normal configfile search search_fs_file   loopback ext2 fat linux efi_gop font gettext serial terminal test

# Use a fixed-size, freshly-created FAT image. mformat chooses a valid FAT
# geometry for the image instead of relying on a hard-coded inconsistent CHS.
rm -f "$EFI_IMG"
dd if=/dev/zero of="$EFI_IMG" bs=1M count=16 status=none
mformat -i "$EFI_IMG" ::
mmd -i "$EFI_IMG" ::/EFI
mmd -i "$EFI_IMG" ::/EFI/BOOT
mcopy -i "$EFI_IMG" "$UEFI_EFI" ::/EFI/BOOT/BOOTX64.EFI

# Generate GRUB config.
TEMPLATE="$SHREEOS_ROOT_DIR/bootloader/grub/grub.cfg.template"
[ -f "$TEMPLATE" ] || shreeos_die "GRUB template not found: $TEMPLATE"

if command -v envsubst >/dev/null 2>&1; then
  DISTRO_NAME="${DISTRO_NAME:-ShreeOS}" \
  DISTRO_VERSION="${DISTRO_VERSION:-0.2.0-dev}" \
  CMDLINE_EXTRA="$CMDLINE_EXTRA" \
    envsubst '${DISTRO_NAME} ${DISTRO_VERSION} ${CMDLINE_EXTRA}' \
      < "$TEMPLATE" > "${STAGING}/boot/grub/grub.cfg"
else
  # CMDLINE_EXTRA may contain sed-significant characters, so require envsubst
  # rather than silently producing a corrupted boot configuration.
  shreeos_die "envsubst is required to generate the GRUB configuration safely (install gettext-base)"
fi

# Hard postconditions: never allow ISO generation to continue with partial boot files.
for file in   "$BIOS_CORE"   "$BIOS_ELTORITO"   "$UEFI_EFI"   "$EFI_IMG"   "${STAGING}/boot/grub/grub.cfg"; do
  [ -s "$file" ] || shreeos_die "GRUB staging failed; required file missing or empty: $file"
done

shreeos_ok "GRUB2 BIOS/UEFI ISO staging completed"
