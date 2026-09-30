#!/usr/bin/env bash
# 47-popt.sh — Build popt (command line option parsing library)
#
# The pinned GitHub release archive has no generated configure, so autoreconf
# runs here (automake/autoconf are installed on the build host as part of the
# base build dependencies).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

PKG_NAME="popt"
PKG_VER="$(pkg_version "$PKG_NAME")"
ARCHIVE="$(pkg_archive "$PKG_NAME")"
SRCDIR="$(base_pkg_extract "$PKG_NAME")"
BUILDDIR="$(pkg_builddir "$PKG_NAME")"

lumen_step "Building ${PKG_NAME}-${PKG_VER}"

if [ ! -x "${SRCDIR}/configure" ]; then
  lumen_log "Generating popt configure script (autoreconf)"
  (cd "$SRCDIR" && autoreconf -fi)
fi

mkdir -p "$BUILDDIR" && cd "$BUILDDIR"

"${SRCDIR}/configure" \
  --prefix=/usr \
  --build="$(gcc -dumpmachine)" \
  --host="${LUMEN_TARGET_TRIPLET}" \
  --target="${LUMEN_TARGET_TRIPLET}" \
  --disable-nls

make -j"${LUMEN_MAKE_JOBS}"
make DESTDIR="${LUMEN_STAGE_ROOT}" install

base_sync_sysroot

compgen -G "${LUMEN_STAGE_ROOT}/usr/lib/libpopt.so*" >/dev/null || \
  lumen_die "Target libpopt shared library was not staged"

lumen_ok "${PKG_NAME}-${PKG_VER} built successfully"
