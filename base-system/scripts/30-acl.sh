#!/usr/bin/env bash
# 30-acl.sh — Build acl (POSIX ACL utilities and libacl)
#
# libacl requires libattr headers from the sysroot, so this must build after
# 29-attr.sh has staged its headers into the compiler sysroot.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

PKG_NAME="acl"
PKG_VER="$(pkg_version "$PKG_NAME")"
ARCHIVE="$(pkg_archive "$PKG_NAME")"
SRCDIR="$(base_pkg_extract "$PKG_NAME")"
BUILDDIR="$(pkg_builddir "$PKG_NAME")"

lumen_step "Building ${PKG_NAME}-${PKG_VER}"

if ! pkg-config --exists attr; then
  lumen_die "Target attr pkg-config metadata is missing from the ShreeOS sysroot (build attr first)"
fi

mkdir -p "$BUILDDIR" && cd "$BUILDDIR"

"${SRCDIR}/configure" \
  --prefix=/usr \
  --build="$(gcc -dumpmachine)" \
  --host="${LUMEN_TARGET_TRIPLET}" \
  --target="${LUMEN_TARGET_TRIPLET}"

make -j"${LUMEN_MAKE_JOBS}"
make DESTDIR="${LUMEN_STAGE_ROOT}" install

base_sync_sysroot

[ -e "${LUMEN_STAGE_ROOT}/usr/lib/libacl.so" ] || \
  [ -e "${LUMEN_STAGE_ROOT}/usr/lib/libacl.so.1" ] || \
  lumen_die "Target libacl shared library was not staged"

lumen_ok "${PKG_NAME}-${PKG_VER} built successfully"
