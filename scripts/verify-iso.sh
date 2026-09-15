#!/usr/bin/env bash
# Validate the generated ISO structurally and, by default, boot it in BIOS and UEFI QEMU.
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$REPO_ROOT/build.conf"
source "$REPO_ROOT/scripts/common.sh"

ISO="${ISO:-$SHREEOS_OUT/$DISTRO_ID-$DISTRO_VERSION.iso}"
SKIP_QEMU="${SKIP_QEMU:-0}"
ALLOW_DEFERRED_GRAPHICS="${ALLOW_DEFERRED_GRAPHICS:-0}"

shreeos_require_cmd sha256sum xorriso

desktop_deferred=false
if [ "${PROFILE:-desktop}" = "desktop" ]; then
  status_file="$SHREEOS_STAGE_ROOT/etc/shreeos/desktop-native.status"
  if [ ! -f "$status_file" ] || [ "$(cat "$status_file" 2>/dev/null || true)" != "ready" ]; then
    desktop_deferred=true
    if [ "$ALLOW_DEFERRED_GRAPHICS" = "1" ]; then
      shreeos_warn "Desktop-native graphics are deferred; continuing only because ALLOW_DEFERRED_GRAPHICS=1."
    else
      shreeos_die "Desktop-native graphics are not ready. Refusing to certify this desktop ISO."
    fi
  fi
fi

[ -f "$ISO" ] || shreeos_die "ISO not found: $ISO"
[ -s "$ISO" ] || shreeos_die "ISO is empty: $ISO"

shreeos_step "Verifying ISO checksum"
checksum_file="$ISO.sha256"
if [ -f "$checksum_file" ]; then
  (
    cd "$(dirname "$ISO")"
    sha256sum -c "$(basename "$checksum_file")"
  )
else
  sha256sum "$ISO"
fi

shreeos_step "Inspecting ISO filesystem"
required_paths=(
  "/boot/bzImage"
  "/boot/initramfs.cpio.gz"
  "/boot/grub/grub.cfg"
  "/boot/grub/i386-pc/eltorito.img"
  "/boot/grub/x86_64-efi/efi.img"
  "/EFI/BOOT/BOOTX64.EFI"
)
for path in "${required_paths[@]}"; do
  if xorriso -indev "$ISO" -ls "$path" >/dev/null 2>&1; then
    shreeos_ok "Found $path"
  else
    shreeos_die "ISO is missing required boot file: $path"
  fi
done

if [ "$SKIP_QEMU" = "1" ]; then
  shreeos_warn "QEMU boot validation skipped because SKIP_QEMU=1."
else
  shreeos_require_cmd qemu-system-x86_64
  bash "$REPO_ROOT/tests/qemu/boot-iso-bios.sh" --iso="$ISO"
  bash "$REPO_ROOT/tests/qemu/boot-iso-uefi.sh" --iso="$ISO"
fi

echo
if [ "$desktop_deferred" = true ]; then
  shreeos_warn "ISO boot checks passed, but desktop-native graphics remain DEFERRED."
elif [ "$SKIP_QEMU" = "1" ]; then
  shreeos_ok "ShreeOS ISO structural verification passed (QEMU boot checks were skipped)."
else
  shreeos_ok "ShreeOS ISO READY: structure plus BIOS/UEFI boot checks passed."
fi
