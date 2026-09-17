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
  --prefix=/usr \
  --build="$(gcc -dumpmachine)" \
  --host="${LUMEN_TARGET_TRIPLET}" \
  --target="${LUMEN_TARGET_TRIPLET}" \
  --mandir=/usr/share/man \
  --with-shared \
  --without-debug \
  --without-normal \
  --enable-widec \
  --enable-pc-files \
  --with-pkg-config-libdir=/usr/lib/pkgconfig \
  --without-ada

make -j"${LUMEN_MAKE_JOBS}"
make DESTDIR="${LUMEN_STAGE_ROOT}" install

# ncurses is built only with the wide-character ABI.  A number of otherwise
# wide-character-safe packages (notably alsa-utils) still probe the historical
# non-wide library names directly instead of using pkg-config.  Provide the
# complete compatibility set so configure checks cannot fall back to host
# libraries or fail at the first -lpanel/-lmenu/-lform probe.
for lib in ncurses curses panel menu form; do
  case "$lib" in
    curses) target="libncursesw.so" ;;
    *)      target="lib${lib}w.so" ;;
  esac
  if [ ! -e "${LUMEN_STAGE_ROOT}/usr/lib/${target}" ]; then
    lumen_die "ncurses installation is missing required wide library: ${target}"
  fi
  ln -sfn "$target" "${LUMEN_STAGE_ROOT}/usr/lib/lib${lib}.so"
done

# Keep pkg-config consumers on the same target ABI.  ncurses installs the
# wide-character .pc files but intentionally omits these compatibility names.
for lib in ncurses panel menu form; do
  wide_pc="${LUMEN_STAGE_ROOT}/usr/lib/pkgconfig/${lib}w.pc"
  if [ -f "$wide_pc" ]; then
    ln -sfn "${lib}w.pc" "${LUMEN_STAGE_ROOT}/usr/lib/pkgconfig/${lib}.pc"
  fi
done

lumen_ok "${PKG_NAME}-${PKG_VER} built successfully"
