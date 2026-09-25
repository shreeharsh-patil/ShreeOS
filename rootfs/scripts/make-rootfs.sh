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

REQUIRED_SERVICES=(
  00-sysinit.conf
  10-hostname.conf
  20-network.conf
  30-shreed.conf
  90-console.conf
)

REQUIRED_EXECUTABLES=(
  init
  sbin/init
  sbin/initctl
  usr/bin/initctl
  sbin/shree-auth
  usr/bin/shree-auth
  bin/lpm
  usr/bin/lpm
  usr/sbin/shreed
  usr/bin/shreedctl
)

for arg in "$@"; do
  case "$arg" in
    --skip-init)    SKIP_INIT=true ;;
    --skip-archive) SKIP_ARCHIVE=true ;;
    --help|-h)
      echo "Usage: make-rootfs.sh [--skip-init] [--skip-archive]"
      exit 0
      ;;
    *) lumen_die "Unknown option: $arg" ;;
  esac
done

lumen_step "Assembling root filesystem in ${LUMEN_STAGE_ROOT}"

# 1. Verify prerequisites
lumen_require_cmd curl
export PATH="${LUMEN_TOOLS}/bin:${PATH}"
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
  make -C "${SHREEOS_ROOT_DIR:-${LUMEN_ROOT_DIR}}/init/src" all
  for binary in init initctl shree-auth; do
    [ -s "${SHREEOS_ROOT_DIR:-${LUMEN_ROOT_DIR}}/init/src/${binary}" ] || \
      shreeos_die "Missing required init build output: ${binary}"
  done

  mkdir -p "${SHREEOS_STAGE_ROOT:-${LUMEN_STAGE_ROOT}}/sbin"
  mkdir -p "${SHREEOS_STAGE_ROOT:-${LUMEN_STAGE_ROOT}}/usr/bin"
  mkdir -p "${SHREEOS_STAGE_ROOT:-${LUMEN_STAGE_ROOT}}/etc/services.d"

  cp "${SHREEOS_ROOT_DIR:-${LUMEN_ROOT_DIR}}/init/src/init" "${SHREEOS_STAGE_ROOT:-${LUMEN_STAGE_ROOT}}/sbin/init"
  chmod 755 "${SHREEOS_STAGE_ROOT:-${LUMEN_STAGE_ROOT}}/sbin/init"
  cp "${SHREEOS_ROOT_DIR:-${LUMEN_ROOT_DIR}}/init/src/initctl" "${SHREEOS_STAGE_ROOT:-${LUMEN_STAGE_ROOT}}/sbin/initctl"
  chmod 755 "${SHREEOS_STAGE_ROOT:-${LUMEN_STAGE_ROOT}}/sbin/initctl"
  cp "${SHREEOS_ROOT_DIR:-${LUMEN_ROOT_DIR}}/init/src/initctl" "${SHREEOS_STAGE_ROOT:-${LUMEN_STAGE_ROOT}}/usr/bin/initctl"
  chmod 755 "${SHREEOS_STAGE_ROOT:-${LUMEN_STAGE_ROOT}}/usr/bin/initctl"
  shreeos_ok "Installed init and initctl"

  cp "${SHREEOS_ROOT_DIR:-${LUMEN_ROOT_DIR}}/init/src/shree-auth" "${SHREEOS_STAGE_ROOT:-${LUMEN_STAGE_ROOT}}/usr/bin/shree-auth"
  chmod 4755 "${SHREEOS_STAGE_ROOT:-${LUMEN_STAGE_ROOT}}/usr/bin/shree-auth"
  cp "${SHREEOS_ROOT_DIR:-${LUMEN_ROOT_DIR}}/init/src/shree-auth" "${SHREEOS_STAGE_ROOT:-${LUMEN_STAGE_ROOT}}/sbin/shree-auth"
  chmod 4755 "${SHREEOS_STAGE_ROOT:-${LUMEN_STAGE_ROOT}}/sbin/shree-auth"
  shreeos_ok "Installed shree-auth"

  for service in "${REQUIRED_SERVICES[@]}"; do
    [ -s "${SHREEOS_ROOT_DIR:-${LUMEN_ROOT_DIR}}/init/services/${service}" ] || \
      shreeos_die "Missing required service definition: ${service}"
    cp "${SHREEOS_ROOT_DIR:-${LUMEN_ROOT_DIR}}/init/services/${service}" \
      "${SHREEOS_STAGE_ROOT:-${LUMEN_STAGE_ROOT}}/etc/services.d/${service}"
  done
  shreeos_ok "Installed service definitions to /etc/services.d"

  shreeos_step "Building ShreeOS hardware service"
  make -C "${SHREEOS_ROOT_DIR:-${LUMEN_ROOT_DIR}}/hardware" all
  for binary in shreed shreedctl; do
    [ -s "${SHREEOS_ROOT_DIR:-${LUMEN_ROOT_DIR}}/hardware/${binary}" ] || \
      shreeos_die "Missing required hardware build output: ${binary}"
  done
  mkdir -p "${SHREEOS_STAGE_ROOT:-${LUMEN_STAGE_ROOT}}/usr/sbin"
  cp "${SHREEOS_ROOT_DIR:-${LUMEN_ROOT_DIR}}/hardware/shreed" "${SHREEOS_STAGE_ROOT:-${LUMEN_STAGE_ROOT}}/usr/sbin/shreed"
  chmod 755 "${SHREEOS_STAGE_ROOT:-${LUMEN_STAGE_ROOT}}/usr/sbin/shreed"
  cp "${SHREEOS_ROOT_DIR:-${LUMEN_ROOT_DIR}}/hardware/shreedctl" "${SHREEOS_STAGE_ROOT:-${LUMEN_STAGE_ROOT}}/usr/bin/shreedctl"
  chmod 755 "${SHREEOS_STAGE_ROOT:-${LUMEN_STAGE_ROOT}}/usr/bin/shreedctl"
  shreeos_ok "Installed shreed and shreedctl"

  # 3b. Compile and install LPM package manager
  shreeos_step "Building LPM package manager"
  make -C "${SHREEOS_ROOT_DIR:-${LUMEN_ROOT_DIR}}/pkgmanager/src" all
  [ -s "${SHREEOS_ROOT_DIR:-${LUMEN_ROOT_DIR}}/pkgmanager/src/lpm" ] || \
    shreeos_die "Missing required package-manager build output: lpm"
  mkdir -p "${SHREEOS_STAGE_ROOT:-${LUMEN_STAGE_ROOT}}/usr/bin"
  mkdir -p "${SHREEOS_STAGE_ROOT:-${LUMEN_STAGE_ROOT}}/bin"
  mkdir -p "${SHREEOS_STAGE_ROOT:-${LUMEN_STAGE_ROOT}}/var/lib/lpm/installed"
  mkdir -p "${SHREEOS_STAGE_ROOT:-${LUMEN_STAGE_ROOT}}/var/cache/lpm/pkg"

  cp "${SHREEOS_ROOT_DIR:-${LUMEN_ROOT_DIR}}/pkgmanager/src/lpm" "${SHREEOS_STAGE_ROOT:-${LUMEN_STAGE_ROOT}}/usr/bin/lpm"
  chmod 755 "${SHREEOS_STAGE_ROOT:-${LUMEN_STAGE_ROOT}}/usr/bin/lpm"
  cp "${SHREEOS_ROOT_DIR:-${LUMEN_ROOT_DIR}}/pkgmanager/src/lpm" "${SHREEOS_STAGE_ROOT:-${LUMEN_STAGE_ROOT}}/bin/lpm"
  chmod 755 "${SHREEOS_STAGE_ROOT:-${LUMEN_STAGE_ROOT}}/bin/lpm"
  shreeos_ok "Installed lpm to /usr/bin/lpm"

  # 3c. Install system management tools
  for tool in shreectl shree-doctor shreeinfo; do
    if [ -f "${SHREEOS_ROOT_DIR:-${LUMEN_ROOT_DIR}}/scripts/${tool}" ]; then
      cp "${SHREEOS_ROOT_DIR:-${LUMEN_ROOT_DIR}}/scripts/${tool}" "${SHREEOS_STAGE_ROOT:-${LUMEN_STAGE_ROOT}}/usr/bin/${tool}"
      chmod 755 "${SHREEOS_STAGE_ROOT:-${LUMEN_STAGE_ROOT}}/usr/bin/${tool}"
    fi
  done
  if [ -f "${SHREEOS_ROOT_DIR:-${LUMEN_ROOT_DIR}}/hardware/scripts/shree-network" ]; then
    cp "${SHREEOS_ROOT_DIR:-${LUMEN_ROOT_DIR}}/hardware/scripts/shree-network" "${SHREEOS_STAGE_ROOT:-${LUMEN_STAGE_ROOT}}/usr/bin/shree-network"
    chmod 755 "${SHREEOS_STAGE_ROOT:-${LUMEN_STAGE_ROOT}}/usr/bin/shree-network"
  fi
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
  [ -s "${SHREEOS_STAGE_ROOT:-${LUMEN_STAGE_ROOT}}/sbin/init" ] || \
    shreeos_die "No init binary at ${SHREEOS_STAGE_ROOT:-${LUMEN_STAGE_ROOT}}/sbin/init (use --skip-init only if it already exists)"
fi

# Linux executes /init from an initramfs.  This must follow the custom-init
# build/install step so a completely empty build directory is supported.
if [ ! -x "${LUMEN_STAGE_ROOT}/sbin/init" ]; then
  lumen_die "Custom ShreeOS init is missing or not executable."
fi
ln -sfn sbin/init "${LUMEN_STAGE_ROOT}/init"
if [ ! -L "${LUMEN_STAGE_ROOT}/init" ] || [ "$(readlink "${LUMEN_STAGE_ROOT}/init")" != "sbin/init" ]; then
  lumen_die "Could not create the required relative initramfs /init -> sbin/init link."
fi

for path in "${REQUIRED_EXECUTABLES[@]}"; do
  [ -s "${LUMEN_STAGE_ROOT}/${path}" ] && [ -x "${LUMEN_STAGE_ROOT}/${path}" ] || \
    lumen_die "Missing required rootfs executable output: /${path}"
done
for path in sbin/shree-auth usr/bin/shree-auth; do
  [ "$(stat -c '%a' -- "${LUMEN_STAGE_ROOT}/${path}")" = "4755" ] || \
    lumen_die "Authentication helper has unsafe mode: /${path}"
done
for service in "${REQUIRED_SERVICES[@]}"; do
  [ -s "${LUMEN_STAGE_ROOT}/etc/services.d/${service}" ] || \
    lumen_die "Missing required rootfs service output: /etc/services.d/${service}"
done

# 4. Verify base system essentials
if ! grep -q '^shree-hardware:' "${LUMEN_STAGE_ROOT}/etc/group" 2>/dev/null; then
  shree_hardware_gid=986
  while awk -F: -v gid="$shree_hardware_gid" '$3 == gid { found=1 } END { exit !found }' "${LUMEN_STAGE_ROOT}/etc/group"; do
    shree_hardware_gid=$((shree_hardware_gid + 1))
  done
  printf 'shree-hardware:x:%s:\n' "$shree_hardware_gid" >> "${LUMEN_STAGE_ROOT}/etc/group"
fi

# 4. Stage the target C/C++ runtime from the compiler sysroot.
# The toolchain owns glibc and compiler runtime libraries; base packages are
# dynamically linked against them, so the bootable rootfs must contain them.
shreeos_step "Staging target runtime libraries from sysroot"
runtime_dirs=0
for rel in lib lib64 usr/lib usr/lib64; do
  src="${LUMEN_SYSROOT}/${rel}"
  [ -d "$src" ] || continue
  dst="${LUMEN_STAGE_ROOT}/${rel}"
  mkdir -p "$dst"
  cp -a "$src/." "$dst/"
  runtime_dirs=$((runtime_dirs + 1))
done
[ "$runtime_dirs" -gt 0 ] || lumen_die "No target runtime library directories found in ${LUMEN_SYSROOT}"

# glibc records /lib64/ld-linux-x86-64.so.2 as the ELF interpreter of every
# dynamically linked target binary, but the toolchain installs the loader itself
# under /usr/lib because the sysroot is prefixed with /usr. Without these
# compatibility links the kernel cannot open the interpreter, so each dynamic
# binary (bash, coreutils, ...) fails to exec with ENOENT (shell exit code 127).
shreeos_step "Linking the target dynamic loader into the rootfs"
loader=""
for candidate in \
  "${LUMEN_STAGE_ROOT}/lib64/ld-linux-x86-64.so.2" \
  "${LUMEN_STAGE_ROOT}/lib/ld-linux-x86-64.so.2" \
  "${LUMEN_STAGE_ROOT}/usr/lib/ld-linux-x86-64.so.2" \
  "${LUMEN_STAGE_ROOT}/usr/lib/ld-linux.so.2"
do
  if [ -e "$candidate" ]; then
    loader="$candidate"
    break
  fi
done
[ -n "$loader" ] || lumen_die "Target dynamic loader was not staged from the sysroot"

loader_name="$(basename "$loader")"
loader_rel="${loader#"${LUMEN_STAGE_ROOT}/"}"
for loader_dir in lib64 lib; do
  # A prefixed sysroot has no top-level lib/lib64, so these directories do not
  # exist yet in a fresh staging root.
  mkdir -p "${LUMEN_STAGE_ROOT}/${loader_dir}"
  loader_link="${LUMEN_STAGE_ROOT}/${loader_dir}/${loader_name}"
  if [ ! -e "$loader_link" ]; then
    ln -sfn "../${loader_rel}" "$loader_link" || \
      lumen_die "Could not link the target dynamic loader into /${loader_dir}"
  fi
  shreeos_ok "Target loader reachable at /${loader_dir}/${loader_name}"
done

if ! compgen -G "${LUMEN_STAGE_ROOT}/usr/lib/libc.so*" >/dev/null && \
   ! compgen -G "${LUMEN_STAGE_ROOT}/lib/libc.so*" >/dev/null; then
  lumen_die "Target libc runtime is missing from the assembled rootfs"
fi
# Target binaries only record /lib64/ld-linux-x86-64.so.2 (or /lib/...) in
# PT_INTERP, so one of those paths must resolve in the assembled rootfs.
if ! compgen -G "${LUMEN_STAGE_ROOT}/lib64/ld-linux*.so*" >/dev/null && \
   ! compgen -G "${LUMEN_STAGE_ROOT}/lib/ld-linux*.so*" >/dev/null; then
  lumen_die "Target dynamic loader is missing from the assembled rootfs (/lib64 and /lib are the interpreter paths target binaries use)"
fi

# 5. Verify base system essentials
lumen_step "Verifying base system"
for bin in bash ls mount; do
  if [ ! -x "${LUMEN_STAGE_ROOT}/usr/bin/${bin}" ]; then
    lumen_die "Missing base system binary: /usr/bin/${bin}"
  fi
done
[ -x "${LUMEN_STAGE_ROOT}/bin/bash" ] || lumen_die "Missing /bin/bash compatibility link"
[ -x "${LUMEN_STAGE_ROOT}/bin/sh" ] || lumen_die "Missing /bin/sh compatibility link"

# 6. Ensure device nodes
bash "${SCRIPT_DIR}/populate-devices.sh" "${LUMEN_STAGE_ROOT}"

# 7. Package as cpio archive for QEMU
if [ "$SKIP_ARCHIVE" = false ]; then
  lumen_step "Packaging rootfs as cpio archive"
  lumen_require_cmd cpio find sort gzip mktemp stat touch
  mkdir -p "${LUMEN_BUILD_DIR}"
  ROOTFS_ARCHIVE="${LUMEN_BUILD_DIR}/initramfs.cpio.gz"
  archive_tmp=""
  archive_list=""

  cleanup_archive() {
    if [ -n "$archive_tmp" ]; then
      rm -f -- "$archive_tmp"
    fi
    if [ -n "$archive_list" ]; then
      rm -f -- "$archive_list"
    fi
  }
  trap cleanup_archive EXIT
  archive_tmp="$(mktemp "${ROOTFS_ARCHIVE}.tmp.XXXXXX")"

  if ! (
    cd "${LUMEN_STAGE_ROOT}"
    find . -exec touch -h -d "@${SOURCE_DATE_EPOCH}" {} +
    find . -print0 | LC_ALL=C sort -z | \
      cpio --null --create --format=newc --owner=0:0 --reproducible --quiet | \
      gzip -n -c
  ) > "$archive_tmp"; then
    lumen_die "Initramfs archive creation failed"
  fi

  if ! gzip -t -- "$archive_tmp"; then
    lumen_die "Initramfs archive integrity check failed: gzip validation failed"
  fi
  if ! archive_size="$(stat -c '%s' -- "$archive_tmp")"; then
    lumen_die "Initramfs archive size check failed: could not read ${ROOTFS_ARCHIVE}"
  fi
  if [ "$archive_size" -lt 1024 ]; then
    lumen_die "Initramfs archive size check failed: ${archive_size} bytes is below the 1024-byte minimum"
  fi

  archive_list="$(mktemp "${LUMEN_BUILD_DIR}/.initramfs-list.XXXXXX")"
  if ! gzip -dc -- "$archive_tmp" | cpio --list --quiet > "$archive_list"; then
    lumen_die "Initramfs archive integrity check failed: cpio validation failed"
  fi

  required_entries=("${REQUIRED_EXECUTABLES[@]}")
  for service in "${REQUIRED_SERVICES[@]}"; do
    required_entries+=("etc/services.d/${service}")
  done
  missing_entries=()
  for entry in "${required_entries[@]}"; do
    if ! grep -Fqx -- "$entry" "$archive_list" && \
       ! grep -Fqx -- "./${entry}" "$archive_list" && \
       ! grep -Fqx -- "/${entry}" "$archive_list"; then
      missing_entries+=("/${entry}")
    fi
  done
  if [ "${#missing_entries[@]}" -gt 0 ]; then
    lumen_die "Initramfs required-entry check failed: missing ${missing_entries[*]}"
  fi

  mv -f -- "$archive_tmp" "$ROOTFS_ARCHIVE"
  archive_tmp=""
  rm -f -- "$archive_list"
  archive_list=""
  trap - EXIT
  lumen_ok "Rootfs archive: ${ROOTFS_ARCHIVE} (${archive_size} bytes)"
fi

# 8. Summary
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
