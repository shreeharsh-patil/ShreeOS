#!/usr/bin/env bash
# 34-bzip2.sh — Build bzip2 (block-sorting compression library and CLI)
#
# bzip2 1.0.8 ships a hand-written Makefile that knows nothing about cross
# compilation or shared libraries, so the target compiler and the shared
# objects are wired up explicitly here.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

PKG_NAME="bzip2"
PKG_VER="$(pkg_version "$PKG_NAME")"
ARCHIVE="$(pkg_archive "$PKG_NAME")"
SRCDIR="$(base_pkg_extract "$PKG_NAME")"
BUILDDIR="$(pkg_builddir "$PKG_NAME")"

lumen_step "Building ${PKG_NAME}-${PKG_VER}"

rm -rf "$BUILDDIR"
cp -a "$SRCDIR" "$BUILDDIR"
cd "$BUILDDIR"

# -fPIC is required because the same objects go into the shared library.
make -j"${LUMEN_MAKE_JOBS}" \
  CC="${CC}" \
  AR="${AR}" \
  RANLIB="${RANLIB}" \
  CFLAGS="-Wall -Winline -O2 -fPIC"

# libbz2.so.1.0.8 built from every object; soname matching Debian/Ubuntu.
"${CC}" -shared -Wl,-soname,libbz2.so.1.0 -o libbz2.so.1.0.8 \
  blocksort.o huffman.o crctable.o randtable.o compress.o decompress.o bzlib.o

install -dm755 "${LUMEN_STAGE_ROOT}/usr/lib" "${LUMEN_STAGE_ROOT}/usr/bin" \
  "${LUMEN_STAGE_ROOT}/usr/include"
install -m644 bzlib.h "${LUMEN_STAGE_ROOT}/usr/include/bzlib.h"
install -m755 libbz2.so.1.0.8 "${LUMEN_STAGE_ROOT}/usr/lib/libbz2.so.1.0.8"
ln -sfn libbz2.so.1.0.8 "${LUMEN_STAGE_ROOT}/usr/lib/libbz2.so.1.0"
ln -sfn libbz2.so.1.0.8 "${LUMEN_STAGE_ROOT}/usr/lib/libbz2.so"
for tool in bzip2 bunzip2 bzcat; do
  install -m755 "$tool" "${LUMEN_STAGE_ROOT}/usr/bin/$tool"
done
ln -sfn bzip2 "${LUMEN_STAGE_ROOT}/usr/bin/bzip2recover"

base_sync_sysroot

[ -e "${LUMEN_STAGE_ROOT}/usr/lib/libbz2.so.1.0.8" ] || \
  lumen_die "Target libbz2 shared library was not staged"

lumen_ok "${PKG_NAME}-${PKG_VER} built successfully"
