#!/usr/bin/env bash
# 30-acl.sh — Build acl (POSIX ACL utilities and libacl)
#
# libacl needs libattr's shared object and headers to cross-compile, so this
# must build after 29-attr.sh has staged them into the compiler sysroot.
#
# acl locates libattr with AC_CHECK_LIB/AC_CHECK_HEADERS, not pkg-config, so
# the guard asserts on those artifacts directly. See base_require_sysroot_dependency
# in common.sh for why an unqualified `pkg-config --exists attr` is the wrong
# test here.
#
# acl also pulls in AM_GNU_GETTEXT([external]). gettext is not part of the
# Phase 2 base system, so NLS is disabled explicitly rather than left to be
# discovered mid-configure as a fatal error. Phase 14 re-enables it together
# with a real gettext package and the locale tooling.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

PKG_NAME="acl"
PKG_VER="$(pkg_version "$PKG_NAME")"
ARCHIVE="$(pkg_archive "$PKG_NAME")"
SRCDIR="$(base_pkg_extract "$PKG_NAME")"
BUILDDIR="$(pkg_builddir "$PKG_NAME")"

lumen_step "Building ${PKG_NAME}-${PKG_VER}"

base_require_sysroot_dependency "attr (required by acl)" \
  "usr/include/attr/xattr.h" \
  "usr/lib/libattr.so" \
  "usr/lib/libattr.so.1"

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

[ -e "${LUMEN_STAGE_ROOT}/usr/lib/libacl.so" ] || \
  [ -e "${LUMEN_STAGE_ROOT}/usr/lib/libacl.so.1" ] || \
  lumen_die "Target libacl shared library was not staged"

lumen_ok "${PKG_NAME}-${PKG_VER} built successfully"
