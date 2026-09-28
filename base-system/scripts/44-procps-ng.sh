#!/usr/bin/env bash
# 44-procps-ng.sh — Build procps-ng (ps, top, free, pgrep, sysctl)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

PKG_NAME="procps-ng"
PKG_VER="$(pkg_version "$PKG_NAME")"
ARCHIVE="$(pkg_archive "$PKG_NAME")"
SRCDIR="$(base_pkg_extract "$PKG_NAME")"
BUILDDIR="$(pkg_builddir "$PKG_NAME")"

lumen_step "Building ${PKG_NAME}-${PKG_VER}"

if ! pkg-config --exists ncursesw; then
  lumen_die "Target ncursesw pkg-config metadata is missing from the ShreeOS sysroot"
fi

mkdir -p "$BUILDDIR" && cd "$BUILDDIR"

# watch/slabtop need ncurses; the rest of the suite needs nothing unusual.
# --enable-watch8bit keeps watch usable with UTF-8 locales later.
"${SRCDIR}/configure" \
  --prefix=/usr \
  --build="$(gcc -dumpmachine)" \
  --host="${LUMEN_TARGET_TRIPLET}" \
  --target="${LUMEN_TARGET_TRIPLET}" \
  --exec-prefix=/usr \
  --sysconfdir=/etc \
  --disable-kill \
  --enable-libselinux=no \
  --enable-watch8bit

make -j"${LUMEN_MAKE_JOBS}"
make DESTDIR="${LUMEN_STAGE_ROOT}" install

base_sync_sysroot

for tool in ps top free pgrep; do
  [ -e "${LUMEN_STAGE_ROOT}/usr/bin/${tool}" ] || \
    lumen_die "procps-ng tool missing after install: /usr/bin/${tool}"
done

lumen_ok "${PKG_NAME}-${PKG_VER} built successfully"
