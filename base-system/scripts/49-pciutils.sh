#!/usr/bin/env bash
# 49-pciutils.sh — Build pciutils (lspci, setpci, libpci)
#
# pciutils ships hand-written Makefiles with a cross-friendly variable set.
# The pci.ids database is downloaded separately by the rootfs stage so the
# hardware description data can be refreshed without a library rebuild.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

PKG_NAME="pciutils"
PKG_VER="$(pkg_version "$PKG_NAME")"
ARCHIVE="$(pkg_archive "$PKG_NAME")"
SRCDIR="$(base_pkg_extract "$PKG_NAME")"
BUILDDIR="$(pkg_builddir "$PKG_NAME")"

lumen_step "Building ${PKG_NAME}-${PKG_VER}"

rm -rf "$BUILDDIR"
cp -a "$SRCDIR" "$BUILDDIR"
cd "$BUILDDIR"

make -j"${LUMEN_MAKE_JOBS}" \
  CC="${CC}" \
  AR="${AR}" \
  RANLIB="${RANLIB}" \
  HOST=glibc \
  SHARED=yes \
  ZLIB=no \
  LIBKMOD=no \
  PREFIX=/usr

make install \
  PREFIX=/usr \
  SHARED=yes \
  ZLIB=no \
  LIBKMOD=no \
  DESTDIR="${LUMEN_STAGE_ROOT}"

base_sync_sysroot

[ -e "${LUMEN_STAGE_ROOT}/usr/sbin/lspci" ] || \
  [ -e "${LUMEN_STAGE_ROOT}/usr/bin/lspci" ] || \
  lumen_die "Target lspci binary was not staged"
compgen -G "${LUMEN_STAGE_ROOT}/usr/lib/libpci.so*" >/dev/null || \
  lumen_die "Target libpci shared library was not staged"

lumen_ok "${PKG_NAME}-${PKG_VER} built successfully"
