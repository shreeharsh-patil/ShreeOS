#!/usr/bin/env bash
# kernel/scripts/common.sh — shared helpers for kernel build scripts
set -euo pipefail

KERNEL_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KERNEL_ROOT_DIR="$(cd "$KERNEL_SCRIPT_DIR/../.." && pwd)"

if [ -f "$KERNEL_ROOT_DIR/build.conf" ]; then
  source "$KERNEL_ROOT_DIR/build.conf"
fi
if [ -f "$KERNEL_ROOT_DIR/scripts/common.sh" ]; then
  source "$KERNEL_ROOT_DIR/scripts/common.sh"
fi

# Kernel-specific directories
KERNEL_SOURCES="${LUMEN_BUILD_DIR}/sources"
KERNEL_BUILDDIR="${LUMEN_BUILD_DIR}/build-kernel"
KERNEL_INITRAMFS_SRC="${KERNEL_ROOT_DIR}/kernel/initramfs"
KERNEL_INITRAMFS_OUT="${LUMEN_BUILD_DIR}/initramfs.cpio.gz"

export ARCH="${LUMEN_ARCH}"
export CROSS_COMPILE="${LUMEN_TARGET_TRIPLET}-"

mkdir -p "$KERNEL_SOURCES" "$KERNEL_BUILDDIR" "${LUMEN_STAGE_ROOT}"

# Kernel source tree (extracted)
kernel_srcdir() {
  echo "${KERNEL_SOURCES}/linux-${VER_LINUX_KERNEL}"
}

# Verify host has what we need to build the kernel
kernel_verify_host() {
  local missing=()
  for cmd in gcc make bc flex bison openssl pkg-config; do
    if ! command -v "$cmd" &>/dev/null; then
      missing+=("$cmd")
    fi
  done
  if [ ${#missing[@]} -gt 0 ]; then
    lumen_die "Missing host build tools for kernel: ${missing[*]}"
  fi
  lumen_ok "All required kernel build tools found"
}
