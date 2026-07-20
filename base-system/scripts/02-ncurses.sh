#!/usr/bin/env bash
# 02-ncurses.sh — Build ncurses (terminal handling library)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

PKG_NAME="ncurses"
PKG_VER="$(pkg_version "$PKG_NAME")"
PKG_URL="$(pkg_url "$PKG_NAME")"
PKG_SHA256="$(pkg_sha256 "$PKG_NAME")"
ARCHIVE="$(pkg_archive "$PKG_NAME")"
SRCDIR="$(pkg_srcdir "$PKG_NAME")"
BUILDDIR="$(pkg_builddir "$PKG_NAME")"

lumen_step "Building ${PKG_NAME}-${PKG_VER}"

lumen_fetch "$PKG_URL" "${BASE_SOURCES}/${ARCHIVE}" "$PKG_SHA256"

if [ ! -d "$SRCDIR" ]; then
  tar -xf "${BASE_SOURCES}/${ARCHIVE}" -C "${BASE_SOURCES}"
fi

mkdir -p "$BUILDDIR" && cd "$BUILDDIR"

# Build with shared libraries, wide-character support, no Ada
"${SRCDIR}/configure" \
  --prefix="${LUMEN_STAGE_ROOT}/usr" \
  --build="$(gcc -dumpmachine)" \
  --host="${LUMEN_TARGET_TRIPLET}" \
  --target="${LUMEN_TARGET_TRIPLET}" \
  --mandir="${LUMEN_STAGE_ROOT}/usr/share/man" \
  --with-shared \
  --without-debug \
  --without-normal \
  --enable-widec \
  --enable-pc-files \
  --with-pkg-config-libdir="${LUMEN_STAGE_ROOT}/usr/lib/pkgconfig" \
  --without-ada

make -j"${LUMEN_MAKE_JOBS}"
make install

# Create symlink for non-widec compatibility (some packages expect libncurses not libncursesw)
ln -sf libncursesw.so "${LUMEN_STAGE_ROOT}/usr/lib/libncurses.so" 2>/dev/null || true

lumen_ok "${PKG_NAME}-${PKG_VER} built successfully"
