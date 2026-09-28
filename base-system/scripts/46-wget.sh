#!/usr/bin/env bash
# 46-wget.sh — Build wget (network retriever)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

PKG_NAME="wget"
PKG_VER="$(pkg_version "$PKG_NAME")"
ARCHIVE="$(pkg_archive "$PKG_NAME")"
SRCDIR="$(base_pkg_extract "$PKG_NAME")"
BUILDDIR="$(pkg_builddir "$PKG_NAME")"

lumen_step "Building ${PKG_NAME}-${PKG_VER}"

if ! pkg-config --exists openssl; then
  lumen_die "Target OpenSSL pkg-config metadata is missing from the ShreeOS sysroot"
fi

mkdir -p "$BUILDDIR" && cd "$BUILDDIR"

"${SRCDIR}/configure" \
  --prefix=/usr \
  --build="$(gcc -dumpmachine)" \
  --host="${LUMEN_TARGET_TRIPLET}" \
  --target="${LUMEN_TARGET_TRIPLET}" \
  --sysconfdir=/etc \
  --with-ssl=openssl \
  --without-libpsl \
  --disable-nls \
  --disable-rpath

make -j"${LUMEN_MAKE_JOBS}"
make DESTDIR="${LUMEN_STAGE_ROOT}" install

[ -e "${LUMEN_STAGE_ROOT}/usr/bin/wget" ] || \
  lumen_die "Target wget binary was not staged"

base_assert_no_host_binary "${LUMEN_STAGE_ROOT}/usr/bin/wget"

lumen_ok "${PKG_NAME}-${PKG_VER} built successfully"
