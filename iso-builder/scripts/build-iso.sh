#!/usr/bin/env bash
# iso-builder/scripts/build-iso.sh — Build a hybrid BIOS/UEFI bootable ISO
#
# Assembles the kernel, rootfs, and GRUB into an ISO image using xorriso.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ISOBUILDER_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
LUMEN_ROOT_DIR="$(cd "$ISOBUILDER_DIR/.." && pwd)"

source "$LUMEN_ROOT_DIR/build.conf"
source "$LUMEN_ROOT_DIR/scripts/common.sh"

NO_CLEANUP="${NO_CLEANUP:-false}"
CMDLINE_EXTRA="${CMDLINE_EXTRA:-}"
PROFILE="${PROFILE:-desktop}"
case "$PROFILE" in
  minimal|desktop|security|server) ;;
  *) lumen_die "Unsupported PROFILE: $PROFILE" ;;
esac
export PROFILE

for arg in "$@"; do
  case "$arg" in
    --no-cleanup) NO_CLEANUP=true ;;
    --cmdline=*) CMDLINE_EXTRA="${arg#*=}" ;;
    --cmdline) [ $# -ge 2 ] || lumen_die "--cmdline requires a value"; CMDLINE_EXTRA="$2"; shift ;;
    --help|-h) echo "Usage: build-iso.sh [--no-cleanup] [--cmdline=<kernel-arguments>]"; exit 0 ;;
    *) lumen_die "Unknown option: $arg" ;;
  esac
  shift
done

case "${NO_CLEANUP,,}" in
  1|true|yes|on) NO_CLEANUP=true ;;
  0|false|no|off) NO_CLEANUP=false ;;
  *) lumen_die "Invalid NO_CLEANUP value: $NO_CLEANUP" ;;
esac

lumen_require_cmd xorriso sha256sum awk

BZIMAGE="${SHREEOS_BUILD_DIR:-${LUMEN_BUILD_DIR}}/build-kernel/arch/x86/boot/bzImage"
INITRD="${SHREEOS_BUILD_DIR:-${LUMEN_BUILD_DIR}}/initramfs.cpio.gz"
ISO_STAGING="${SHREEOS_BUILD_DIR:-${LUMEN_BUILD_DIR}}/iso-staging"
if [ "$PROFILE" = "minimal" ]; then
  ISO_OUT="${SHREEOS_OUT:-${LUMEN_OUT}}/${DISTRO_ID}-${DISTRO_VERSION}.iso"
else
  ISO_OUT="${SHREEOS_OUT:-${LUMEN_OUT}}/${DISTRO_ID}-${DISTRO_VERSION}-${PROFILE}.iso"
fi

shreeos_step "Building bootable ISO: ${ISO_OUT}"

for f in "$BZIMAGE" "$INITRD"; do
  if [ ! -f "$f" ]; then
    shreeos_die "Missing: $f"
  fi
done
shreeos_ok "All build artifacts found"

rm -rf "$ISO_STAGING"
mkdir -p "${ISO_STAGING}/boot/grub"

cp "$BZIMAGE" "${ISO_STAGING}/boot/bzImage"
cp "$INITRD" "${ISO_STAGING}/boot/initramfs.cpio.gz"
shreeos_ok "Kernel and initramfs copied to staging"

bash "${SHREEOS_ROOT_DIR:-${LUMEN_ROOT_DIR}}/bootloader/scripts/install-grub-iso.sh" "$ISO_STAGING" --cmdline="$CMDLINE_EXTRA"

lumen_step "Creating hybrid ISO with xorriso"
mkdir -p "$LUMEN_OUT"

XORRISO_DATE_ARGS=()
if [[ "${SOURCE_DATE_EPOCH:-}" =~ ^[0-9]+$ ]]; then
  find "$ISO_STAGING" -exec touch -h -d "@${SOURCE_DATE_EPOCH}" {} +
  iso_date="$(date -u -d "@${SOURCE_DATE_EPOCH}" +%Y%m%d%H%M%S00)"
  XORRISO_DATE_ARGS=(--modification-date="$iso_date" --set_all_file_dates "$iso_date")
fi

xorriso -as mkisofs \
  "${XORRISO_DATE_ARGS[@]}" \
  -iso-level 3 \
  -full-iso9660-filenames \
  -volid "${DISTRO_ID}-${DISTRO_VERSION}" \
  -appid "${DISTRO_NAME} Live" \
  -publisher "${DISTRO_NAME}" \
  -preparer "built by ${DISTRO_NAME} build scripts" \
  -eltorito-boot boot/grub/i386-pc/eltorito.img \
  -no-emul-boot \
  -boot-load-size 4 \
  -boot-info-table \
  --eltorito-catalog boot/grub/i386-pc/boot.catalog \
  -eltorito-alt-boot \
  -e boot/grub/x86_64-efi/efi.img \
  -no-emul-boot \
  -isohybrid-gpt-basdat \
  -o "$ISO_OUT" \
  "$ISO_STAGING"

if [ ! -f "$ISO_OUT" ]; then
  lumen_die "ISO creation failed: ${ISO_OUT} not found"
fi

ISO_SIZE=$(stat -c%s "$ISO_OUT" 2>/dev/null || stat -f%z "$ISO_OUT" 2>/dev/null || echo "unknown")
lumen_ok "ISO created: ${ISO_OUT} (${ISO_SIZE} bytes)"

if command -v sha256sum &>/dev/null; then
  (
    cd "$(dirname "$ISO_OUT")"
    sha256sum "$(basename "$ISO_OUT")" > "$(basename "$ISO_OUT").sha256"
  )
  lumen_ok "Generated SHA-256 checksum: ${ISO_OUT}.sha256"
fi

BUILD_DATE="$(date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || printf 'unknown')"
if [[ "${SOURCE_DATE_EPOCH:-}" =~ ^[0-9]+$ ]]; then
  BUILD_DATE="$(date -u -d "@${SOURCE_DATE_EPOCH}" +"%Y-%m-%dT%H:%M:%SZ")"
fi
if [ -n "$(git -C "$LUMEN_ROOT_DIR" status --porcelain --untracked-files=all 2>/dev/null)" ]; then
  lumen_die "Refusing to generate a provenance-labelled ISO from a dirty worktree"
fi
COMMIT_SHA="$(git -C "$LUMEN_ROOT_DIR" rev-parse HEAD 2>/dev/null || printf 'unknown')"
MANIFEST_OUT="${LUMEN_OUT}/$(basename "${ISO_OUT%.iso}")-manifest.json"
cat > "$MANIFEST_OUT" <<MANIFEST
{
  "name": "${DISTRO_NAME}",
  "version": "${DISTRO_VERSION}",
  "profile": "${PROFILE}",
  "iso": "$(basename "$ISO_OUT")",
  "size_bytes": ${ISO_SIZE},
  "sha256": "$(sha256sum "$ISO_OUT" | awk '{print $1}')",
  "source_date_epoch": ${SOURCE_DATE_EPOCH:-0},
  "commit": "${COMMIT_SHA}",
  "created_at": "${BUILD_DATE}"
}
MANIFEST
lumen_ok "Generated build manifest: ${MANIFEST_OUT}"

if [ "$NO_CLEANUP" = false ]; then
  rm -rf "$ISO_STAGING"
  lumen_log "Cleaned up ISO staging directory"
fi

echo ""
echo "============================================"
lumen_ok "ISO build COMPLETE"
echo "============================================"
echo "  ISO:          ${ISO_OUT}"
echo "  Size:         ${ISO_SIZE} bytes"
echo "  Profile:      ${PROFILE}"
echo "  Kernel:       ${BZIMAGE}"
echo "  Initramfs:    ${INITRD}"
echo "  Bootloader:   GRUB2 (BIOS + UEFI)"
echo "============================================"
echo ""
echo "To boot in QEMU (BIOS):"
echo "  qemu-system-x86_64 -cdrom ${ISO_OUT} -boot d -m 1024M -nographic"
echo ""
echo "To boot in QEMU (UEFI):"
echo "  qemu-system-x86_64 -bios /usr/share/ovmf/OVMF.fd -cdrom ${ISO_OUT} -boot d -m 1024M -nographic"
echo ""
