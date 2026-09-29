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

# libcap has no configure script: cross settings are injected through
# Make.Rules overrides on the make command line.
#
# Two upstream details matter here:
#   * The install target is plain "install" (it recurses into libcap/, progs/
#     and doc/). There is no "install-lib" target.
#   * Make.Rules defines FAKEROOT=$(DESTDIR) and installs everything relative
#     to it, so DESTDIR is the correct staging variable.
#
# PAM_CAP and GOLANG default to "yes" whenever the *host* happens to have
# pam_modules.h or a Go toolchain. Both are pinned off so a runner's own
# packages cannot leak into the target. RAISE_SETFCAP is already "no" by
# default, which matters: it would otherwise try to execute the freshly
# cross-compiled setcap on the build host.
make -j"${LUMEN_MAKE_JOBS}" \
  CC="${CC}" \
  BUILD_CC=gcc \
  AR="${AR}" \
  RANLIB="${RANLIB}" \
  COPTFLAGS="-O2" \
  GOLANG=no \
  PAM_CAP=no \
  prefix=/usr \
  lib=lib \
  sbin=sbin \
  DESTDIR="${LUMEN_STAGE_ROOT}" \
  install

base_sync_sysroot

# setcap/getcap/capsh live in sbin; assert the tools as well as the library,
# since a library-only build would satisfy the old check while shipping
# nothing usable.
for binary in setcap getcap capsh; do
  [ -x "${LUMEN_STAGE_ROOT}/usr/sbin/${binary}" ] || \
    lumen_die "Target ${binary} was not staged into /usr/sbin"
  base_assert_no_host_binary "${LUMEN_STAGE_ROOT}/usr/sbin/${binary}"
done

[ -f "${LUMEN_STAGE_ROOT}/usr/include/sys/capability.h" ] || \
  lumen_die "Target libcap headers were not staged"
[ -f "${LUMEN_STAGE_ROOT}/usr/lib/pkgconfig/libcap.pc" ] || \
  lumen_die "Target libcap pkg-config file was not staged"

[ -f "${LUMEN_STAGE_ROOT}/usr/lib/libcap.so" ] || \
  [ -f "${LUMEN_STAGE_ROOT}/usr/lib/libcap.so.2" ] || \
  lumen_die "Target libcap shared library was not staged"
base_assert_no_host_binary "${LUMEN_STAGE_ROOT}/usr/lib/libcap.so.2"*

lumen_ok "${PKG_NAME}-${PKG_VER} built successfully"
