#!/usr/bin/env bash
# install-kernel-headers.sh — Install Linux kernel API headers for glibc
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

lumen_step "Installing Linux kernel headers — version ${VER_LINUX_KERNEL}"

PKG="linux-${VER_LINUX_KERNEL}"
ARCHIVE="${PKG}.tar.xz"
SRCDIR="${LUMEN_BUILD_DIR}/sources/${PKG}"

lumen_fetch "${KERNEL_URL}" "${LUMEN_BUILD_DIR}/sources/${ARCHIVE}" "${KERNEL_SHA256}"

if [ ! -d "$SRCDIR" ]; then
  tar -xJf "${LUMEN_BUILD_DIR}/sources/${ARCHIVE}" -C "${LUMEN_BUILD_DIR}/sources"
fi

cd "$SRCDIR"
make mrproper
make headers
find usr/include -name '.*' -delete
cp -rv usr/include "$LUMEN_SYSROOT/usr"

if [ ! -f "$LUMEN_SYSROOT/usr/include/linux/kernel.h" ]; then
  lumen_die "Kernel headers installation failed — linux/kernel.h not found"
fi

lumen_ok "Linux kernel headers installed to ${LUMEN_SYSROOT}/usr/include"
