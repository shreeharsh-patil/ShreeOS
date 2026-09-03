#!/usr/bin/env bash
# build-kernel.sh — Cross-compile the ShreeOS kernel
#
# Prerequisites:
#   - Phase 1 cross-compiler in $LUMEN_TOOLS/bin/
#   - Host packages: gcc, make, bc, flex, bison, openssl, pkg-config, cpio, gzip
#
# Usage:
#   bash kernel/scripts/build-kernel.sh              # full build
#   bash kernel/scripts/build-kernel.sh --skip-init  # skip initramfs rebuild
#   bash kernel/scripts/build-kernel.sh --help       # this message
#
# Outputs:
#   $LUMEN_BUILD_DIR/build-kernel/arch/x86/boot/bzImage   — kernel binary
#   $LUMEN_STAGE_ROOT/lib/modules/                        — kernel modules
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

SKIP_INIT=false

for arg in "$@"; do
  case "$arg" in
    --skip-init) SKIP_INIT=true ;;
    --help|-h)
      echo "Usage: build-kernel.sh [--skip-init]"
      exit 0
      ;;
  esac
done

kernel_verify_host

PKG="linux-${VER_LINUX_KERNEL}"
ARCHIVE="${PKG}.tar.xz"
SRCDIR="$(kernel_srcdir)"

lumen_step "Building kernel ${VER_LINUX_KERNEL} for ${LUMEN_ARCH}"

# 1. Download and extract kernel source
lumen_fetch "${KERNEL_URL}" "${KERNEL_SOURCES}/${ARCHIVE}" "${KERNEL_SHA256}"

if [ ! -d "$SRCDIR" ]; then
  lumen_log "Extracting kernel source..."
  tar -xJf "${KERNEL_SOURCES}/${ARCHIVE}" -C "${KERNEL_SOURCES}"
fi

# 2. The halt-only kernel/initramfs test program is intentionally restricted
# to the dedicated qemu-kernel-test profile. Production profiles boot with an
# external ShreeOS initramfs and must never embed this test payload.
EMBED_TEST_INITRAMFS=false
if [ "${PROFILE:-desktop}" = "qemu-kernel-test" ]; then
  EMBED_TEST_INITRAMFS=true
fi
if [ "$EMBED_TEST_INITRAMFS" = true ] && [ "$SKIP_INIT" = false ]; then
  lumen_step "Building initramfs for boot testing"
  make -C "$KERNEL_INITRAMFS_SRC" clean all
  if [ ! -f "${KERNEL_INITRAMFS_SRC}/initramfs.cpio.gz" ]; then
    lumen_die "initramfs build failed"
  fi
  lumen_ok "initramfs built"
fi

# 3. Configure the kernel
lumen_step "Configuring kernel (defconfig + minimal overrides)"
mkdir -p "$KERNEL_BUILDDIR"
cd "$KERNEL_BUILDDIR"

make -C "$SRCDIR" O="$KERNEL_BUILDDIR" ARCH="${LUMEN_ARCH}" defconfig

# Determine kernel config profile based on active PROFILE
KERNEL_CFG="${KERNEL_ROOT_DIR}/kernel/configs/generic.config"
if [ "${PROFILE:-desktop}" = "desktop" ] && [ -f "${KERNEL_ROOT_DIR}/kernel/configs/desktop.config" ]; then
  KERNEL_CFG="${KERNEL_ROOT_DIR}/kernel/configs/desktop.config"
elif [ "${PROFILE:-}" = "qemu" ] && [ -f "${KERNEL_ROOT_DIR}/kernel/configs/qemu.config" ]; then
  KERNEL_CFG="${KERNEL_ROOT_DIR}/kernel/configs/qemu.config"
elif [ "${PROFILE:-}" = "minimal" ] && [ -f "${KERNEL_ROOT_DIR}/kernel/configs/x86_64-minimal.config" ]; then
  KERNEL_CFG="${KERNEL_ROOT_DIR}/kernel/configs/x86_64-minimal.config"
fi

lumen_log "Applying kernel config profile: $(basename "$KERNEL_CFG")"

# Apply config overrides via merge_config.sh
"${SRCDIR}/scripts/kconfig/merge_config.sh" \
  -O "$KERNEL_BUILDDIR" \
  -m "$KERNEL_BUILDDIR/.config" \
  "$KERNEL_CFG"

# Set an embedded initramfs only for the dedicated kernel-test profile.
if [ "$EMBED_TEST_INITRAMFS" = true ]; then
  "${SRCDIR}/scripts/config" --file "$KERNEL_BUILDDIR/.config" \
    --set-str INITRAMFS_SOURCE "${KERNEL_INITRAMFS_SRC}/initramfs.cpio.gz"
else
  "${SRCDIR}/scripts/config" --file "$KERNEL_BUILDDIR/.config" \
    --set-str INITRAMFS_SOURCE ""
fi

# Resolve any new dependencies
make -C "$SRCDIR" O="$KERNEL_BUILDDIR" ARCH="${LUMEN_ARCH}" olddefconfig

lumen_ok "Kernel configured"

# 4. Build the kernel and modules
lumen_step "Compiling kernel (this may take a while)..."
make -C "$SRCDIR" O="$KERNEL_BUILDDIR" \
  ARCH="${LUMEN_ARCH}" \
  CROSS_COMPILE="${CROSS_COMPILE}" \
  -j"${LUMEN_MAKE_JOBS}" \
  all

lumen_ok "Kernel compiled"

# 5. Install modules into stage root
lumen_step "Installing kernel modules"
make -C "$SRCDIR" O="$KERNEL_BUILDDIR" \
  ARCH="${LUMEN_ARCH}" \
  CROSS_COMPILE="${CROSS_COMPILE}" \
  INSTALL_MOD_PATH="${LUMEN_STAGE_ROOT}" \
  modules_install

lumen_ok "Kernel modules installed to ${LUMEN_STAGE_ROOT}/lib/modules"

# 6. Verify output
BZIMAGE="${KERNEL_BUILDDIR}/arch/x86/boot/bzImage"
if [ ! -f "$BZIMAGE" ]; then
  lumen_die "bzImage not found at ${BZIMAGE}"
fi

BZIMAGE_SIZE=$(stat -c%s "$BZIMAGE" 2>/dev/null || stat -f%z "$BZIMAGE" 2>/dev/null || echo "unknown")
lumen_ok "Kernel built: ${BZIMAGE} (${BZIMAGE_SIZE} bytes)"

# 7. Summary
echo ""
echo "============================================"
lumen_ok "Kernel build COMPLETE"
echo "============================================"
echo "  Kernel:   ${VER_LINUX_KERNEL}"
echo "  Arch:     ${LUMEN_ARCH}"
echo "  Config:   ${KERNEL_BUILDDIR}/.config"
echo "  bzImage:  ${BZIMAGE}"
echo "  Modules:  ${LUMEN_STAGE_ROOT}/lib/modules"
echo "  Embedded test initramfs: ${EMBED_TEST_INITRAMFS}"
echo "============================================"
echo ""
echo "To boot in QEMU:"
echo "  qemu-system-x86_64 \\"
echo "    -kernel ${BZIMAGE} \\"
echo "    -initrd ${KERNEL_INITRAMFS_SRC}/initramfs.cpio.gz \\"
echo "    -nographic \\"
echo "    -append \"console=ttyS0\" \\"
echo "    -m 256M"
echo ""
