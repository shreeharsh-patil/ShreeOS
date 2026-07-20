#!/usr/bin/env bash
# rootfs/scripts/make-rootfs.sh — Assemble the ShreeOS root filesystem
#
# Combines the base system (Phase 2), kernel modules (Phase 3),
# and custom init (Phase 4) into $LUMEN_STAGE_ROOT, then packages
# it as a cpio archive for QEMU boot testing.
#
# Usage:
#   bash rootfs/scripts/make-rootfs.sh                  # full assembly
#   bash rootfs/scripts/make-rootfs.sh --skip-init      # skip init rebuild
#   bash rootfs/scripts/make-rootfs.sh --skip-archive   # skip cpio packaging
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOTFS_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
LUMEN_ROOT_DIR="$(cd "$ROOTFS_DIR/.." && pwd)"

source "$LUMEN_ROOT_DIR/build.conf"
source "$LUMEN_ROOT_DIR/scripts/common.sh"

SKIP_INIT=false
SKIP_ARCHIVE=false

for arg in "$@"; do
  case "$arg" in
    --skip-init)    SKIP_INIT=true ;;
    --skip-archive) SKIP_ARCHIVE=true ;;
    --help|-h)
      echo "Usage: make-rootfs.sh [--skip-init] [--skip-archive]"
      exit 0
      ;;
  esac
done

lumen_step "Assembling root filesystem in ${LUMEN_STAGE_ROOT}"

# 1. Verify prerequisites
lumen_require_cmd curl
if [ "$SKIP_INIT" = false ]; then
  if ! command -v "${LUMEN_TARGET_TRIPLET}-gcc" &>/dev/null; then
    lumen_die "Cross-compiler not found: ${LUMEN_TARGET_TRIPLET}-gcc. Build Phase 1 first."
  fi
fi

# 2. Create skeleton from templates
lumen_step "Setting up rootfs skeleton"
mkdir -p "${LUMEN_STAGE_ROOT}"
"${LUMEN_ROOT_DIR}/base-system/scripts/setup-rootfs.sh"

# Templated files from rootfs/skeleton/
if [ -d "${ROOTFS_DIR}/skeleton/etc" ]; then
  for f in os-release fstab resolv.conf; do
    if [ -f "${ROOTFS_DIR}/skeleton/etc/${f}" ]; then
      envsubst < "${ROOTFS_DIR}/skeleton/etc/${f}" > "${LUMEN_STAGE_ROOT}/etc/${f}"
      lumen_ok "Configured /etc/${f}"
    fi
  done
fi

# 3. Compile and install init
if [ "$SKIP_INIT" = false ]; then
  lumen_step "Building custom init"
  export CROSS_COMPILE="${LUMEN_TARGET_TRIPLET}-"
  make -C "${LUMEN_ROOT_DIR}/init/src" clean all
  if [ ! -f "${LUMEN_ROOT_DIR}/init/src/init" ]; then
    lumen_die "init build failed"
  fi
  cp "${LUMEN_ROOT_DIR}/init/src/init" "${LUMEN_STAGE_ROOT}/sbin/init"
  chmod 755 "${LUMEN_STAGE_ROOT}/sbin/init"
  lumen_ok "Installed init to /sbin/init"
else
  if [ ! -f "${LUMEN_STAGE_ROOT}/sbin/init" ]; then
    lumen_die "No init binary at ${LUMEN_STAGE_ROOT}/sbin/init (use --skip-init only if it already exists)"
  fi
fi

# 4. Verify base system essentials
lumen_step "Verifying base system"
for bin in bash ls mount; do
  if [ ! -f "${LUMEN_STAGE_ROOT}/bin/${bin}" ]; then
    lumen_warn "Missing base system binary: /bin/${bin}"
  fi
done

# 5. Ensure device nodes for console
if [ ! -e "${LUMEN_STAGE_ROOT}/dev/console" ]; then
  mkdir -p "${LUMEN_STAGE_ROOT}/dev"
  mknod -m 622 "${LUMEN_STAGE_ROOT}/dev/console" c 5 1 2>/dev/null || true
fi

# 6. Package as cpio archive for QEMU
if [ "$SKIP_ARCHIVE" = false ]; then
  lumen_step "Packaging rootfs as cpio archive"
  ROOTFS_ARCHIVE="${LUMEN_BUILD_DIR}/rootfs.cpio.gz"
  (
    cd "${LUMEN_STAGE_ROOT}"
    find . | cpio -o -H newc --quiet | gzip -n > "${ROOTFS_ARCHIVE}"
  )
  lumen_ok "Rootfs archive: ${ROOTFS_ARCHIVE}"
fi

# 7. Summary
echo ""
echo "============================================"
lumen_ok "Root filesystem assembly COMPLETE"
echo "============================================"
echo "  Rootfs:       ${LUMEN_STAGE_ROOT}"
echo "  Archive:      ${LUMEN_BUILD_DIR}/rootfs.cpio.gz"
echo "  Init:         ${LUMEN_STAGE_ROOT}/sbin/init"
echo "  Config:       /etc/{os-release,fstab,resolv.conf}"
echo "============================================"
echo ""
echo "To boot in QEMU:"
echo "  qemu-system-x86_64 \\"
echo "    -kernel ${LUMEN_BUILD_DIR}/build-kernel/arch/x86/boot/bzImage \\"
echo "    -initrd ${LUMEN_BUILD_DIR}/rootfs.cpio.gz \\"
echo "    -nographic \\"
echo "    -append \"console=ttyS0\" \\"
echo "    -m 256M"
echo ""
