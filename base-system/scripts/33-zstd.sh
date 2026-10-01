#!/usr/bin/env bash
# 33-zstd.sh — Build zstd (compression library used by journald and SquashFS)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

PKG_NAME="zstd"
PKG_VER="$(pkg_version "$PKG_NAME")"
ARCHIVE="$(pkg_archive "$PKG_NAME")"
SRCDIR="$(base_pkg_extract "$PKG_NAME")"
BUILDDIR="$(pkg_builddir "$PKG_NAME")"

lumen_step "Building ${PKG_NAME}-${PKG_VER}"

rm -rf "$BUILDDIR"
cp -a "$SRCDIR" "$BUILDDIR"
cd "$BUILDDIR"

# HAVE_ macros stay unset so the build never links host libraries; zstd only
# needs libc for the shared library and CLI.
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
  ZSTD_DIR="$(pwd)/lib" \
  PREFIX=/usr

make -C lib install \
  PREFIX=/usr \
  LIBDIR="/usr/lib" \
  INCLUDEDIR="/usr/include" \
  DESTDIR="${LUMEN_STAGE_ROOT}"
# Request the metadata target directly so dependent cross builds can discover
# zstd even if the aggregate install target omits that dependency.
make -C lib install-pc \
  PREFIX=/usr \
  LIBDIR="/usr/lib" \
  INCLUDEDIR="/usr/include" \
  DESTDIR="${LUMEN_STAGE_ROOT}"
install -Dm755 programs/zstd \
  "${LUMEN_STAGE_ROOT}/usr/bin/zstd"
for link in zstdcat zstdmt unzstd; do
  ln -sfn zstd "${LUMEN_STAGE_ROOT}/usr/bin/${link}"
done

base_sync_sysroot

compgen -G "${LUMEN_STAGE_ROOT}/usr/lib/libzstd.so*" >/dev/null || \
  lumen_die "Target libzstd shared library was not staged"
[ -s "${LUMEN_STAGE_ROOT}/usr/lib/pkgconfig/libzstd.pc" ] || \
  lumen_die "Target libzstd pkg-config metadata was not staged"
[ -s "${LUMEN_SYSROOT}/usr/lib/pkgconfig/libzstd.pc" ] || \
  lumen_die "Target libzstd pkg-config metadata was not copied to the sysroot"

lumen_ok "${PKG_NAME}-${PKG_VER} built successfully"
