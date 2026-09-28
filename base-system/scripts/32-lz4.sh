#!/usr/bin/env bash
# 32-lz4.sh — Build lz4 (fast compression library used by journald)
#
# lz4 ships plain Makefiles; its lib/ subdirectory builds the shared library
# and its programs/ subdirectory the CLI. Only the library and lz4 CLI are
# useful on the target.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

PKG_NAME="lz4"
PKG_VER="$(pkg_version "$PKG_NAME")"
ARCHIVE="$(pkg_archive "$PKG_NAME")"
SRCDIR="$(base_pkg_extract "$PKG_NAME")"
BUILDDIR="$(pkg_builddir "$PKG_NAME")"

lumen_step "Building ${PKG_NAME}-${PKG_VER}"

rm -rf "$BUILDDIR"
cp -a "$SRCDIR" "$BUILDDIR"
cd "$BUILDDIR"

make -j"${LUMEN_MAKE_JOBS}" -C lib \
  CC="${CC}" \
  AR="${AR}" \
  BUILD_SHARED=yes \
  BUILD_STATIC=no \
  PREFIX=/usr \
  LIBDIR="/usr/lib" \
  INCLUDEDIR="/usr/include"

make -j"${LUMEN_MAKE_JOBS}" -C programs \
  CC="${CC}" \
  BUILD_SHARED=yes \
  BUILD_STATIC=no \
  LZ4DIR="$(pwd)/lib" \
  PREFIX=/usr

make -C lib install \
  PREFIX=/usr \
  LIBDIR="/usr/lib" \
  INCLUDEDIR="/usr/include" \
  DESTDIR="${LUMEN_STAGE_ROOT}"
install -Dm755 programs/lz4 \
  "${LUMEN_STAGE_ROOT}/usr/bin/lz4"

base_sync_sysroot

compgen -G "${LUMEN_STAGE_ROOT}/usr/lib/liblz4.so*" >/dev/null || \
  lumen_die "Target liblz4 shared library was not staged"

lumen_ok "${PKG_NAME}-${PKG_VER} built successfully"
