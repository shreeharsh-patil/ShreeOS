#!/usr/bin/env bash
# Validate the generated ISO structurally and, by default, boot it in BIOS and UEFI QEMU.
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$REPO_ROOT/build.conf"
source "$REPO_ROOT/scripts/common.sh"

ISO="${ISO:-$SHREEOS_OUT/$DISTRO_ID-$DISTRO_VERSION.iso}"
SKIP_QEMU="${SKIP_QEMU:-0}"

shreeos_require_cmd sha256sum xorriso

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
listing="$(mktemp)"
trap 'rm -f "$listing"' EXIT
xorriso -indev "$ISO" -find / -type f -print >"$listing" 2>/dev/null

required_paths=(
  "/boot/bzImage"
  "/boot/initramfs.cpio.gz"
  "/boot/grub/grub.cfg"
  "/boot/grub/i386-pc/eltorito.img"
  "/boot/grub/x86_64-efi/efi.img"
)
for path in "${required_paths[@]}"; do
  grep -Fxq "$path" "$listing" || shreeos_die "ISO is missing required boot file: $path"
  shreeos_ok "Found $path"
done

if [ "$SKIP_QEMU" = "1" ]; then
  shreeos_warn "QEMU boot validation skipped because SKIP_QEMU=1."
else
  shreeos_require_cmd qemu-system-x86_64
  bash "$REPO_ROOT/tests/qemu/boot-iso-bios.sh" --iso="$ISO"
  bash "$REPO_ROOT/tests/qemu/boot-iso-uefi.sh" --iso="$ISO"
fi

echo
shreeos_ok "ShreeOS ISO READY: structural and requested boot checks passed."
