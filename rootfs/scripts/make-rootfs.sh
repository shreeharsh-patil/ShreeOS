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

# 3. Compile and install init, hardware service, and services
if [ "$SKIP_INIT" = false ]; then
  shreeos_step "Building custom init and initctl"
  export CROSS_COMPILE="${SHREEOS_TARGET_TRIPLET:-${LUMEN_TARGET_TRIPLET}}-"
  make -C "${SHREEOS_ROOT_DIR:-${LUMEN_ROOT_DIR}}/init/src" clean all
  if [ ! -f "${SHREEOS_ROOT_DIR:-${LUMEN_ROOT_DIR}}/init/src/init" ]; then
    shreeos_die "init build failed"
  fi
  mkdir -p "${SHREEOS_STAGE_ROOT:-${LUMEN_STAGE_ROOT}}/sbin"
  mkdir -p "${SHREEOS_STAGE_ROOT:-${LUMEN_STAGE_ROOT}}/etc/services.d"

  cp "${SHREEOS_ROOT_DIR:-${LUMEN_ROOT_DIR}}/init/src/init" "${SHREEOS_STAGE_ROOT:-${LUMEN_STAGE_ROOT}}/sbin/init"
  chmod 755 "${SHREEOS_STAGE_ROOT:-${LUMEN_STAGE_ROOT}}/sbin/init"
  shreeos_ok "Installed init to /sbin/init"

  if [ -f "${SHREEOS_ROOT_DIR:-${LUMEN_ROOT_DIR}}/init/src/initctl" ]; then
    cp "${SHREEOS_ROOT_DIR:-${LUMEN_ROOT_DIR}}/init/src/initctl" "${SHREEOS_STAGE_ROOT:-${LUMEN_STAGE_ROOT}}/sbin/initctl"
    chmod 755 "${SHREEOS_STAGE_ROOT:-${LUMEN_STAGE_ROOT}}/sbin/initctl"
    cp "${SHREEOS_ROOT_DIR:-${LUMEN_ROOT_DIR}}/init/src/initctl" "${SHREEOS_STAGE_ROOT:-${LUMEN_STAGE_ROOT}}/usr/bin/initctl" 2>/dev/null || true
    shreeos_ok "Installed initctl to /sbin/initctl"
  fi

  if [ -f "${SHREEOS_ROOT_DIR:-${LUMEN_ROOT_DIR}}/init/src/shree-auth" ]; then
    cp "${SHREEOS_ROOT_DIR:-${LUMEN_ROOT_DIR}}/init/src/shree-auth" "${SHREEOS_STAGE_ROOT:-${LUMEN_STAGE_ROOT}}/usr/bin/shree-auth"
    chmod 4755 "${SHREEOS_STAGE_ROOT:-${LUMEN_STAGE_ROOT}}/usr/bin/shree-auth" 2>/dev/null || chmod 755 "${SHREEOS_STAGE_ROOT:-${LUMEN_STAGE_ROOT}}/usr/bin/shree-auth"
    cp "${SHREEOS_ROOT_DIR:-${LUMEN_ROOT_DIR}}/init/src/shree-auth" "${SHREEOS_STAGE_ROOT:-${LUMEN_STAGE_ROOT}}/sbin/shree-auth" 2>/dev/null || true
    shreeos_ok "Installed shree-auth to /usr/bin/shree-auth"
  fi

  if [ -d "${SHREEOS_ROOT_DIR:-${LUMEN_ROOT_DIR}}/init/services" ]; then
    cp "${SHREEOS_ROOT_DIR:-${LUMEN_ROOT_DIR}}/init/services/"*.conf "${SHREEOS_STAGE_ROOT:-${LUMEN_STAGE_ROOT}}/etc/services.d/" 2>/dev/null || true
    shreeos_ok "Installed service definitions to /etc/services.d"
  fi

  shreeos_step "Building ShreeOS hardware service"
  make -C "${SHREEOS_ROOT_DIR:-${LUMEN_ROOT_DIR}}/hardware" clean all
  if [ -f "${SHREEOS_ROOT_DIR:-${LUMEN_ROOT_DIR}}/hardware/shreed" ]; then
    mkdir -p "${SHREEOS_STAGE_ROOT:-${LUMEN_STAGE_ROOT}}/usr/sbin"
    cp "${SHREEOS_ROOT_DIR:-${LUMEN_ROOT_DIR}}/hardware/shreed" "${SHREEOS_STAGE_ROOT:-${LUMEN_STAGE_ROOT}}/usr/sbin/shreed"
    chmod 755 "${SHREEOS_STAGE_ROOT:-${LUMEN_STAGE_ROOT}}/usr/sbin/shreed"
    cp "${SHREEOS_ROOT_DIR:-${LUMEN_ROOT_DIR}}/hardware/shreedctl" "${SHREEOS_STAGE_ROOT:-${LUMEN_STAGE_ROOT}}/usr/bin/shreedctl"
    chmod 755 "${SHREEOS_STAGE_ROOT:-${LUMEN_STAGE_ROOT}}/usr/bin/shreedctl"
    shreeos_ok "Installed shreed and shreedctl"
  else
    shreeos_die "shreed build failed"
  fi

  # 3b. Compile and install LPM package manager
  shreeos_step "Building LPM package manager"
  make -C "${SHREEOS_ROOT_DIR:-${LUMEN_ROOT_DIR}}/pkgmanager/src" clean all
  mkdir -p "${SHREEOS_STAGE_ROOT:-${LUMEN_STAGE_ROOT}}/usr/bin"
  mkdir -p "${SHREEOS_STAGE_ROOT:-${LUMEN_STAGE_ROOT}}/bin"
  mkdir -p "${SHREEOS_STAGE_ROOT:-${LUMEN_STAGE_ROOT}}/var/lib/lpm/installed"
  mkdir -p "${SHREEOS_STAGE_ROOT:-${LUMEN_STAGE_ROOT}}/var/cache/lpm/pkg"

  if [ -f "${SHREEOS_ROOT_DIR:-${LUMEN_ROOT_DIR}}/pkgmanager/src/lpm" ]; then
    cp "${SHREEOS_ROOT_DIR:-${LUMEN_ROOT_DIR}}/pkgmanager/src/lpm" "${SHREEOS_STAGE_ROOT:-${LUMEN_STAGE_ROOT}}/usr/bin/lpm"
    chmod 755 "${SHREEOS_STAGE_ROOT:-${LUMEN_STAGE_ROOT}}/usr/bin/lpm"
    cp "${SHREEOS_ROOT_DIR:-${LUMEN_ROOT_DIR}}/pkgmanager/src/lpm" "${SHREEOS_STAGE_ROOT:-${LUMEN_STAGE_ROOT}}/bin/lpm"
    chmod 755 "${SHREEOS_STAGE_ROOT:-${LUMEN_STAGE_ROOT}}/bin/lpm"
    shreeos_ok "Installed lpm to /usr/bin/lpm"
  fi

  # 3c. Install system management tools
  for tool in shreectl shree-doctor shreeinfo; do
    if [ -f "${SHREEOS_ROOT_DIR:-${LUMEN_ROOT_DIR}}/scripts/${tool}" ]; then
      cp "${SHREEOS_ROOT_DIR:-${LUMEN_ROOT_DIR}}/scripts/${tool}" "${SHREEOS_STAGE_ROOT:-${LUMEN_STAGE_ROOT}}/usr/bin/${tool}"
      chmod 755 "${SHREEOS_STAGE_ROOT:-${LUMEN_STAGE_ROOT}}/usr/bin/${tool}"
    fi
  done
  if [ -f "${SHREEOS_ROOT_DIR:-${LUMEN_ROOT_DIR}}/scripts/shree-wifi" ]; then
    mkdir -p "${SHREEOS_STAGE_ROOT:-${LUMEN_STAGE_ROOT}}/usr/sbin"
    cp "${SHREEOS_ROOT_DIR:-${LUMEN_ROOT_DIR}}/scripts/shree-wifi" "${SHREEOS_STAGE_ROOT:-${LUMEN_STAGE_ROOT}}/usr/sbin/shree-wifi"
    chmod 700 "${SHREEOS_STAGE_ROOT:-${LUMEN_STAGE_ROOT}}/usr/sbin/shree-wifi"
  fi
  for helper in shree-bluetooth shree-audio shree-powerctl; do
    if [ -f "${SHREEOS_ROOT_DIR:-${LUMEN_ROOT_DIR}}/scripts/${helper}" ]; then
      mkdir -p "${SHREEOS_STAGE_ROOT:-${LUMEN_STAGE_ROOT}}/usr/sbin"
      cp "${SHREEOS_ROOT_DIR:-${LUMEN_ROOT_DIR}}/scripts/${helper}" "${SHREEOS_STAGE_ROOT:-${LUMEN_STAGE_ROOT}}/usr/sbin/${helper}"
      chmod 755 "${SHREEOS_STAGE_ROOT:-${LUMEN_STAGE_ROOT}}/usr/sbin/${helper}"
    fi
  done

  if [ -f "${SHREEOS_ROOT_DIR:-${LUMEN_ROOT_DIR}}/installer/scripts/shree-recovery.sh" ]; then
    cp "${SHREEOS_ROOT_DIR:-${LUMEN_ROOT_DIR}}/installer/scripts/shree-recovery.sh" "${SHREEOS_STAGE_ROOT:-${LUMEN_STAGE_ROOT}}/usr/bin/shree-recovery"
    chmod 755 "${SHREEOS_STAGE_ROOT:-${LUMEN_STAGE_ROOT}}/usr/bin/shree-recovery"
  fi
else
  if [ ! -f "${SHREEOS_STAGE_ROOT:-${LUMEN_STAGE_ROOT}}/sbin/init" ]; then
    shreeos_die "No init binary at ${SHREEOS_STAGE_ROOT:-${LUMEN_STAGE_ROOT}}/sbin/init (use --skip-init only if it already exists)"
  fi
fi

# 4. Verify base system essentials
if ! grep -q '^shree-hardware:' "${LUMEN_STAGE_ROOT}/etc/group" 2>/dev/null; then
  shree_hardware_gid=986
  while awk -F: -v gid="$shree_hardware_gid" '$3 == gid { found=1 } END { exit !found }' "${LUMEN_STAGE_ROOT}/etc/group"; do
    shree_hardware_gid=$((shree_hardware_gid + 1))
  done
  printf 'shree-hardware:x:%s:\n' "$shree_hardware_gid" >> "${LUMEN_STAGE_ROOT}/etc/group"
fi

# 4. Verify base system essentials
lumen_step "Verifying base system"
for bin in bash ls mount; do
  if [ ! -f "${LUMEN_STAGE_ROOT}/bin/${bin}" ]; then
    lumen_warn "Missing base system binary: /bin/${bin}"
  fi
done

# 5. Ensure device nodes
bash "${SCRIPT_DIR}/populate-devices.sh" "${LUMEN_STAGE_ROOT}"

# 6. Package as cpio archive for QEMU
if [ "$SKIP_ARCHIVE" = false ]; then
  lumen_step "Packaging rootfs as cpio archive"
  ROOTFS_ARCHIVE="${LUMEN_BUILD_DIR}/initramfs.cpio.gz"
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
echo "  Archive:      ${LUMEN_BUILD_DIR}/initramfs.cpio.gz"
echo "  Init:         ${LUMEN_STAGE_ROOT}/sbin/init"
echo "  Config:       /etc/{os-release,fstab,resolv.conf}"
echo "============================================"
echo ""
echo "To boot in QEMU:"
echo "  qemu-system-x86_64 \\"
echo "    -kernel ${LUMEN_BUILD_DIR}/build-kernel/arch/x86/boot/bzImage \\"
echo "    -initrd ${LUMEN_BUILD_DIR}/initramfs.cpio.gz \\"
echo "    -nographic \\"
echo "    -append \"console=ttyS0\" \\"
echo "    -m 256M"
echo ""
