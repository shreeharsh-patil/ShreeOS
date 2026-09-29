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
# bzip2 1.0.8's Makefile has no shared-library support and its "all" target also
# runs the upstream self-test, which would execute a cross-built binary on the
# host. Build exactly the two real programs instead.
make -j"${LUMEN_MAKE_JOBS}" bzip2 bzip2recover \
  CC="${CC}" \
  AR="${AR}" \
  RANLIB="${RANLIB}" \
  CFLAGS="-Wall -Winline -O2 -fPIC"

# libbz2.so.1.0.8 built from every object; soname matching Debian/Ubuntu.
"${CC}" -shared -Wl,-soname,libbz2.so.1.0 -o libbz2.so.1.0.8 \
  blocksort.o huffman.o crctable.o randtable.o compress.o decompress.o bzlib.o

install -dm755 "${LUMEN_STAGE_ROOT}/usr/lib" "${LUMEN_STAGE_ROOT}/usr/bin" \
  "${LUMEN_STAGE_ROOT}/usr/include" \
  "${LUMEN_STAGE_ROOT}/usr/share/man/man1"
install -m644 bzlib.h "${LUMEN_STAGE_ROOT}/usr/include/bzlib.h"
install -m644 bzip2.1 "${LUMEN_STAGE_ROOT}/usr/share/man/man1/bzip2.1"
install -m755 libbz2.so.1.0.8 "${LUMEN_STAGE_ROOT}/usr/lib/libbz2.so.1.0.8"
ln -sfn libbz2.so.1.0.8 "${LUMEN_STAGE_ROOT}/usr/lib/libbz2.so.1.0"
ln -sfn libbz2.so.1.0.8 "${LUMEN_STAGE_ROOT}/usr/lib/libbz2.so"

# bzip2 ships a single multi-call binary: it switches compress/decompress/cat
# behaviour on argv[0] (see the strstr(progName, ...) checks in bzip2.c), which
# is why upstream installs the same executable under three names.
install -m755 bzip2 "${LUMEN_STAGE_ROOT}/usr/bin/bzip2"
ln -sfn bzip2 "${LUMEN_STAGE_ROOT}/usr/bin/bunzip2"
ln -sfn bzip2 "${LUMEN_STAGE_ROOT}/usr/bin/bzcat"

# bzip2recover is a separate program that rebuilds damaged .bz2 files; it must
# not be aliased to the compressor.
install -m755 bzip2recover "${LUMEN_STAGE_ROOT}/usr/bin/bzip2recover"

base_sync_sysroot

[ -e "${LUMEN_STAGE_ROOT}/usr/lib/libbz2.so.1.0.8" ] || \
  lumen_die "Target libbz2 shared library was not staged"
for tool in bzip2 bzip2recover; do
  [ -x "${LUMEN_STAGE_ROOT}/usr/bin/${tool}" ] || \
    lumen_die "bzip2 ${tool} was not staged as an executable"
done
for alias in bunzip2 bzcat; do
  [ -L "${LUMEN_STAGE_ROOT}/usr/bin/${alias}" ] || \
    lumen_die "bzip2 ${alias} alias is not a symlink to the multi-call binary"
done

lumen_ok "${PKG_NAME}-${PKG_VER} built successfully"
