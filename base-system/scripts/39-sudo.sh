#!/usr/bin/env bash
# 39-sudo.sh — Build sudo (privileged command execution)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

PKG_NAME="sudo"
PKG_VER="$(pkg_version "$PKG_NAME")"
ARCHIVE="$(pkg_archive "$PKG_NAME")"
SRCDIR="$(base_pkg_extract "$PKG_NAME")"
BUILDDIR="$(pkg_builddir "$PKG_NAME")"

lumen_step "Building ${PKG_NAME}-${PKG_VER}"

mkdir -p "$BUILDDIR" && cd "$BUILDDIR"

"${SRCDIR}/configure" \
  --prefix=/usr \
  --build="$(gcc -dumpmachine)" \
  --host="${LUMEN_TARGET_TRIPLET}" \
  --target="${LUMEN_TARGET_TRIPLET}" \
  --sysconfdir=/etc \
  --with-pam \
  --without-kerb5 \
  --without-sssd \
  --disable-nls \
  --disable-static-sudoers \
  --enable-zlib=builtin

make -j"${LUMEN_MAKE_JOBS}"
make DESTDIR="${LUMEN_STAGE_ROOT}" install

[ -e "${LUMEN_STAGE_ROOT}/usr/bin/sudo" ] || \
  lumen_die "Target sudo binary was not staged"
# sudo must carry its setuid bit to work for desktop users.
mode="$(stat -c '%a' "${LUMEN_STAGE_ROOT}/usr/bin/sudo")"
[ "$mode" = "4755" ] || \
  lumen_die "sudo was installed without mode 4755 (got $mode); privilege escalation would be broken"

lumen_ok "${PKG_NAME}-${PKG_VER} built successfully"
