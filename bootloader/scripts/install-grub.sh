#!/usr/bin/env bash
# bootloader/scripts/install-grub.sh — Install GRUB2 to ISO staging directory
#
# Installs BIOS and UEFI GRUB images into an ISO staging directory
# so the resulting ISO can boot on both legacy and UEFI systems.
#
# Usage:
#   bash bootloader/scripts/install-grub.sh <staging-dir>
#
# Prerequisites:
#   - Host packages: grub-pc, grub-efi, grub-common
#   - Run as root OR with sudo (needs to install GRUB modules)
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LUMEN_ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$LUMEN_ROOT_DIR/build.conf"
source "$LUMEN_ROOT_DIR/scripts/common.sh"

if [ $# -lt 1 ]; then
  lumen_die "Usage: install-grub.sh <staging-dir> [--cmdline=...]"
fi
STAGING="$1"
shift || true

CMDLINE_EXTRA=""
for arg in "$@"; do
  case "$arg" in
    --cmdline=*) CMDLINE_EXTRA="${arg#*=}" ;;
  esac
done

lumen_require_cmd grub-install grub-mkrescue

lumen_step "Installing GRUB2 to ISO staging: ${STAGING}"

mkdir -p "${STAGING}/boot/grub"

# Install BIOS GRUB modules
grub-install \
  --target=i386-pc \
  --boot-directory="${STAGING}/boot" \
  --modules="part_msdos part_gpt normal iso9660 loopback ext2 ntfs fat" \
  --recheck \
  --force \
  /dev/null 2>/dev/null || true

# Install UEFI GRUB modules
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
if [ -f "${LUMEN_ROOT_DIR}/bootloader/grub/grub.cfg.template" ]; then
  DISTRO_NAME="${DISTRO_NAME}" DISTRO_VERSION="${DISTRO_VERSION}" CMDLINE_EXTRA="${CMDLINE_EXTRA}" \
    envsubst < "${LUMEN_ROOT_DIR}/bootloader/grub/grub.cfg.template" \
    > "${STAGING}/boot/grub/grub.cfg"
  lumen_ok "GRUB config written: ${STAGING}/boot/grub/grub.cfg"
else
  lumen_die "GRUB template not found: bootloader/grub/grub.cfg.template"
fi

lumen_ok "GRUB2 installed to ${STAGING}/boot/grub"
