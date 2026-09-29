#!/usr/bin/env bash
# 28-libcap.sh — Build libcap (POSIX capability utilities and library)
#
# libcap ships its own Makefile tree (no configure), so the cross settings
# are injected through Make.Rules overrides on the make command line.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

PKG_NAME="libcap"
PKG_VER="$(pkg_version "$PKG_NAME")"
ARCHIVE="$(pkg_archive "$PKG_NAME")"
SRCDIR="$(base_pkg_extract "$PKG_NAME")"
BUILDDIR="$(pkg_builddir "$PKG_NAME")"

lumen_step "Building ${PKG_NAME}-${PKG_VER}"

rm -rf "$BUILDDIR"
cp -a "$SRCDIR" "$BUILDDIR"
cd "$BUILDDIR"

# gperf is only needed to regenerate cap_names.h, and the shipped generated
# header is current; forcing it off avoids a host-tool dependency that does
# not affect the result.
make -j"${LUMEN_MAKE_JOBS}" \
  CC="${CC}" \
  BUILD_CC=gcc \
  AR="${AR}" \
  RANLIB="${RANLIB}" \
  COPTFLAGS="-O2" \
  GOLANG=no \
  PAM_CAP=no \
  USE_GPG=no \
  prefix=/usr \
  lib=lib \
  DESTDIR="${LUMEN_STAGE_ROOT}" \
  install-lib

base_sync_sysroot

[ -f "${LUMEN_STAGE_ROOT}/usr/lib/libcap.so" ] || \
  [ -f "${LUMEN_STAGE_ROOT}/usr/lib/libcap.so.2" ] || \
  lumen_die "Target libcap shared library was not staged"
base_assert_no_host_binary "${LUMEN_STAGE_ROOT}/usr/lib/libcap.so.2"*

lumen_ok "${PKG_NAME}-${PKG_VER} built successfully"
