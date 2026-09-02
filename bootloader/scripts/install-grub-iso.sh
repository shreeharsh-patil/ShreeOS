#!/usr/bin/env bash
# bootloader/scripts/install-grub-iso.sh — Install GRUB2 to ISO staging directory
#
# Installs BIOS and UEFI GRUB images into an ISO staging directory
# so the resulting ISO can boot on both legacy and UEFI systems.
#
# Usage:
#   bash bootloader/scripts/install-grub-iso.sh <staging-dir> [--cmdline=...]
#
# Prerequisites:
#   - Host packages: grub-pc-bin (or grub-pc), grub-efi-amd64-bin (or grub-efi), grub-common, xorriso
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SHREEOS_ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$SHREEOS_ROOT_DIR/build.conf" 2>/dev/null || true
source "$SHREEOS_ROOT_DIR/scripts/common.sh" 2>/dev/null || {
  shreeos_step() { echo "==> $1"; }
  shreeos_log() { echo "  -> $1"; }
  shreeos_ok() { echo "  [OK] $1"; }
  shreeos_warn() { echo "  [WARN] $1"; }
  shreeos_die() { echo "  [ERROR] $1" >&2; exit 1; }
  shreeos_require_cmd() { for c in "$@"; do command -v "$c" >/dev/null 2>&1 || { echo "Missing $c" >&2; exit 1; }; done; }
  lumen_die() { shreeos_die "$@"; }
  lumen_require_cmd() { shreeos_require_cmd "$@"; }
}

if [ $# -lt 1 ]; then
  shreeos_die "Usage: install-grub-iso.sh <staging-dir> [--cmdline=...]"
fi
STAGING="$1"
shift || true

CMDLINE_EXTRA=""
for arg in "$@"; do
  case "$arg" in
    --cmdline=*) CMDLINE_EXTRA="${arg#*=}" ;;
  esac
done

shreeos_require_cmd grub-install

shreeos_step "Installing GRUB2 for ISO staging: ${STAGING}"

mkdir -p "${STAGING}/boot/grub/i386-pc"
mkdir -p "${STAGING}/boot/grub/x86_64-efi"
mkdir -p "${STAGING}/EFI/BOOT"

# Install BIOS GRUB modules into staging
shreeos_log "Generating i386-pc eltorito image"
if command -v grub-mkrescue >/dev/null 2>&1 || command -v grub-mkimage >/dev/null 2>&1; then
  if command -v grub-mkimage >/dev/null 2>&1; then
    grub-mkimage \
      -O i386-pc \
      -o "${STAGING}/boot/grub/i386-pc/eltorito.img" \
      -p "/boot/grub" \
      biosdisk iso9660 part_msdos part_gpt normal loopback ext2 fat ls
  fi
fi

# Fallback/standard grub-install for staging modules if available
grub-install \
  --target=i386-pc \
  --boot-directory="${STAGING}/boot" \
  --modules="part_msdos part_gpt normal iso9660 loopback ext2 ntfs fat" \
  --recheck \
  --force \
  /dev/null 2>/dev/null || true

# Install UEFI GRUB image
shreeos_log "Generating x86_64-efi boot image"
if command -v grub-mkimage >/dev/null 2>&1; then
  grub-mkimage \
    -O x86_64-efi \
    -o "${STAGING}/EFI/BOOT/BOOTX64.EFI" \
    -p "/boot/grub" \
    iso9660 part_msdos part_gpt normal loopback ext2 fat search search_fs_file efi_gop efi_uga

  # Generate FAT EFI image for El-Torito alt-boot
  if command -v mformat >/dev/null 2>&1 && command -v mcopy >/dev/null 2>&1; then
    mkdir -p "${STAGING}/boot/grub/x86_64-efi"
    EFI_IMG="${STAGING}/boot/grub/x86_64-efi/efi.img"
    dd if=/dev/zero of="$EFI_IMG" bs=1k count=4096 status=none
    mformat -i "$EFI_IMG" -h 64 -s 32 -t 2 ::
    mmd -i "$EFI_IMG" ::/EFI ::/EFI/BOOT
    mcopy -i "$EFI_IMG" "${STAGING}/EFI/BOOT/BOOTX64.EFI" ::/EFI/BOOT/BOOTX64.EFI
  fi
fi

grub-install \
  --target=x86_64-efi \
  --boot-directory="${STAGING}/boot" \
  --modules="part_msdos part_gpt normal iso9660 loopback ext2 ntfs fat" \
  --efi-directory="${STAGING}" \
  --removable \
  --recheck \
  --force \
  /dev/null 2>/dev/null || true

# Copy GRUB config
if [ -f "${SHREEOS_ROOT_DIR}/bootloader/grub/grub.cfg.template" ]; then
  if command -v envsubst >/dev/null 2>&1; then
    DISTRO_NAME="${DISTRO_NAME:-ShreeOS}" DISTRO_VERSION="${DISTRO_VERSION:-0.2.0-dev}" CMDLINE_EXTRA="${CMDLINE_EXTRA}" \
      envsubst < "${SHREEOS_ROOT_DIR}/bootloader/grub/grub.cfg.template" \
      > "${STAGING}/boot/grub/grub.cfg"
  else
    sed -e "s/\${DISTRO_NAME}/${DISTRO_NAME:-ShreeOS}/g" \
        -e "s/\${DISTRO_VERSION}/${DISTRO_VERSION:-0.2.0-dev}/g" \
        -e "s/\${CMDLINE_EXTRA}/${CMDLINE_EXTRA}/g" \
        "${SHREEOS_ROOT_DIR}/bootloader/grub/grub.cfg.template" \
        > "${STAGING}/boot/grub/grub.cfg"
  fi
  shreeos_ok "GRUB config written: ${STAGING}/boot/grub/grub.cfg"
else
  shreeos_die "GRUB template not found: bootloader/grub/grub.cfg.template"
fi

shreeos_ok "GRUB2 ISO staging completed at ${STAGING}/boot/grub"
