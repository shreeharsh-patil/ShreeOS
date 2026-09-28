#!/usr/bin/env bash
# 29-attr.sh — Build attr (extended attribute utilities and libattr)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

PKG_NAME="attr"
PKG_VER="$(pkg_version "$PKG_NAME")"
ARCHIVE="$(pkg_archive "$PKG_NAME")"
SRCDIR="$(base_pkg_extract "$PKG_NAME")"
BUILDDIR="$(pkg_builddir "$PKG_NAME")"

lumen_step "Building ${PKG_NAME}-${PKG_VER}"

mkdir -p "$BUILDDIR" && cd "$BUILDDIR"

"${SRCDIR}/configure" \
  --prefix=/usr \
  --build="$(gcc -dumpmachine)" \
  --host="${LUMEN_TARGET_TRIPLET}" \
  --target="${LUMEN_TARGET_TRIPLET}"

make -j"${LUMEN_MAKE_JOBS}"
make DESTDIR="${LUMEN_STAGE_ROOT}" install

base_sync_sysroot

[ -e "${LUMEN_STAGE_ROOT}/usr/lib/libattr.so" ] || \
  [ -e "${LUMEN_STAGE_ROOT}/usr/lib/libattr.so.1" ] || \
  lumen_die "Target libattr shared library was not staged"

lumen_ok "${PKG_NAME}-${PKG_VER} built successfully"
