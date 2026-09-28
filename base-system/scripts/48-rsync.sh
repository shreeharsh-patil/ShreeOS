#!/usr/bin/env bash
# 48-rsync.sh — Build rsync (incremental file transfer used by the installer)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

PKG_NAME="rsync"
PKG_VER="$(pkg_version "$PKG_NAME")"
ARCHIVE="$(pkg_archive "$PKG_NAME")"
SRCDIR="$(base_pkg_extract "$PKG_NAME")"
BUILDDIR="$(pkg_builddir "$PKG_NAME")"

lumen_step "Building ${PKG_NAME}-${PKG_VER}"

for lib in popt zstd; do
  pkg-config --exists "$lib" || \
    lumen_die "Target ${lib} pkg-config metadata is missing from the ShreeOS sysroot"
done

mkdir -p "$BUILDDIR" && cd "$BUILDDIR"

"${SRCDIR}/configure" \
  --prefix=/usr \
  --build="$(gcc -dumpmachine)" \
  --host="${LUMEN_TARGET_TRIPLET}" \
  --target="${LUMEN_TARGET_TRIPLET}" \
  --with-included-popt=no \
  --disable-xxhash \
  --disable-openssl \
  --disable-md2man

make -j"${LUMEN_MAKE_JOBS}"
make DESTDIR="${LUMEN_STAGE_ROOT}" install

[ -e "${LUMEN_STAGE_ROOT}/usr/bin/rsync" ] || \
  lumen_die "Target rsync binary was not staged"

base_assert_no_host_binary "${LUMEN_STAGE_ROOT}/usr/bin/rsync"

lumen_ok "${PKG_NAME}-${PKG_VER} built successfully"
