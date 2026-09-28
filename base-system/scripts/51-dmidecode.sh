#!/usr/bin/env bash
# 51-dmidecode.sh — Build dmidecode (DMI/SMBIOS table decoder)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

PKG_NAME="dmidecode"
PKG_VER="$(pkg_version "$PKG_NAME")"
ARCHIVE="$(pkg_archive "$PKG_NAME")"
SRCDIR="$(base_pkg_extract "$PKG_NAME")"
BUILDDIR="$(pkg_builddir "$PKG_NAME")"

lumen_step "Building ${PKG_NAME}-${PKG_VER}"

rm -rf "$BUILDDIR"
cp -a "$SRCDIR" "$BUILDDIR"
cd "$BUILDDIR"

make -j"${LUMEN_MAKE_JOBS}" \
  CC="${CC}" \
  AR="${AR}" \
  LDFLAGS="${LDFLAGS}" \
  prefix=/usr \
  sbindir=/usr/sbin

make install \
  prefix=/usr \
  sbindir=/usr/sbin \
  DESTDIR="${LUMEN_STAGE_ROOT}"

[ -e "${LUMEN_STAGE_ROOT}/usr/sbin/dmidecode" ] || \
  lumen_die "Target dmidecode binary was not staged"

base_assert_no_host_binary "${LUMEN_STAGE_ROOT}/usr/sbin/dmidecode"

lumen_ok "${PKG_NAME}-${PKG_VER} built successfully"
