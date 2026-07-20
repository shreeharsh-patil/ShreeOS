#!/usr/bin/env bash
# iso-builder/scripts/build-iso.sh — Build a hybrid BIOS/UEFI bootable ISO
#
# Assembles the kernel, rootfs, and GRUB into an ISO image using xorriso.
#
# Usage:
#   bash iso-builder/scripts/build-iso.sh                # full build
#   bash iso-builder/scripts/build-iso.sh --no-cleanup   # keep staging dir
#
# Prerequisites:
#   - Phase 3: kernel bzImage at build/build-kernel/arch/x86/boot/bzImage
#   - Phase 4: rootfs archive at build/rootfs.cpio.gz
#   - Host packages: xorriso, grub-pc, grub-efi, grub-common
#
# Output:
#   $LUMEN_OUT/shreeos-<version>.iso
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ISOBUILDER_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
LUMEN_ROOT_DIR="$(cd "$ISOBUILDER_DIR/.." && pwd)"

source "$LUMEN_ROOT_DIR/build.conf"
source "$LUMEN_ROOT_DIR/scripts/common.sh"

NO_CLEANUP=false

for arg in "$@"; do
  case "$arg" in
    --no-cleanup) NO_CLEANUP=true ;;
    --help|-h) echo "Usage: build-iso.sh [--no-cleanup]"; exit 0 ;;
  esac
done

lumen_require_cmd xorriso

BZIMAGE="${LUMEN_BUILD_DIR}/build-kernel/arch/x86/boot/bzImage"
INITRD="${LUMEN_BUILD_DIR}/rootfs.cpio.gz"
ISO_STAGING="${LUMEN_BUILD_DIR}/iso-staging"
ISO_OUT="${LUMEN_OUT}/${DISTRO_ID}-${DISTRO_VERSION}.iso"

lumen_step "Building bootable ISO: ${ISO_OUT}"

# 1. Verify prerequisites
for f in "$BZIMAGE" "$INITRD"; do
  if [ ! -f "$f" ]; then
    lumen_die "Missing: $f"
  fi
done
lumen_ok "All build artifacts found"

# 2. Create ISO staging directory
rm -rf "$ISO_STAGING"
mkdir -p "${ISO_STAGING}/boot/grub"

# 3. Copy kernel and initramfs
cp "$BZIMAGE" "${ISO_STAGING}/boot/bzImage"
cp "$INITRD" "${ISO_STAGING}/boot/rootfs.cpio.gz"
lumen_ok "Kernel and rootfs copied to staging"

# 4. Install GRUB2
bash "${LUMEN_ROOT_DIR}/bootloader/scripts/install-grub.sh" "$ISO_STAGING"

# 5. Build hybrid ISO with xorriso
lumen_step "Creating hybrid ISO with xorriso"
mkdir -p "$LUMEN_OUT"

xorriso -as mkisofs \
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

# 6. Cleanup staging
if [ "$NO_CLEANUP" = false ]; then
  rm -rf "$ISO_STAGING"
  lumen_log "Cleaned up ISO staging directory"
fi

# 7. Summary
echo ""
echo "============================================"
lumen_ok "ISO build COMPLETE"
echo "============================================"
echo "  ISO:          ${ISO_OUT}"
echo "  Size:         ${ISO_SIZE} bytes"
echo "  Kernel:       ${BZIMAGE}"
echo "  Initramfs:    ${INITRD}"
echo "  Bootloader:   GRUB2 (BIOS + UEFI)"
echo "============================================"
echo ""
echo "To boot in QEMU (BIOS):"
echo "  qemu-system-x86_64 -cdrom ${ISO_OUT} -boot d -m 256M -nographic"
echo ""
echo "To boot in QEMU (UEFI):"
echo "  qemu-system-x86_64 -bios /usr/share/ovmf/OVMF.fd -cdrom ${ISO_OUT} -boot d -m 256M -nographic"
echo ""
