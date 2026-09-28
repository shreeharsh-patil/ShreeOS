#!/usr/bin/env bash
# 41-elfutils.sh — Build elfutils (libelf/libdw, required by iproute2 and perf)
#
# Only the libraries are installed on the target; the tools are not needed
# and pull in extra dependencies. libdw's ELF compression support is left off
# because it drags zlib/bz2/lzma into the link for marginal benefit here.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

PKG_NAME="elfutils"
PKG_VER="$(pkg_version "$PKG_NAME")"
ARCHIVE="$(pkg_archive "$PKG_NAME")"
SRCDIR="$(base_pkg_extract "$PKG_NAME")"
BUILDDIR="$(pkg_builddir "$PKG_NAME")"

lumen_step "Building ${PKG_NAME}-${PKG_VER}"

# configure probes for a host bzlib/xz/zstd when cross-compiling; the target
# libraries are staged by now but keeping the feature off keeps the link
# surface minimal and avoids host leakage through libtool.
mkdir -p "$BUILDDIR" && cd "$BUILDDIR"

"${SRCDIR}/configure" \
  --prefix=/usr \
  --build="$(gcc -dumpmachine)" \
  --host="${LUMEN_TARGET_TRIPLET}" \
  --target="${LUMEN_TARGET_TRIPLET}" \
  --disable-debuginfod \
  --enable-libdebuginfod=dummy \
  --disable-demo \
  --disable-progs

make -j"${LUMEN_MAKE_JOBS}" -C libelf
make -j"${LUMEN_MAKE_JOBS}" -C libdw
make -C libelf install DESTDIR="${LUMEN_STAGE_ROOT}"
make -C libdw install DESTDIR="${LUMEN_STAGE_ROOT}"

base_sync_sysroot

compgen -G "${LUMEN_STAGE_ROOT}/usr/lib/libelf.so*" >/dev/null || \
  lumen_die "Target libelf shared library was not staged"
compgen -G "${LUMEN_STAGE_ROOT}/usr/lib/libdw.so*" >/dev/null || \
  lumen_die "Target libdw shared library was not staged"

lumen_ok "${PKG_NAME}-${PKG_VER} built successfully"
