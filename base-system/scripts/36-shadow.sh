#!/usr/bin/env bash
# 36-shadow.sh — Build shadow (useradd, groupadd, passwd, login)
#
# The account-management tools a desktop user creation flow needs. login is
# disabled because util-linux login and the session manager own that path;
# shadow still supplies the account database tools.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

PKG_NAME="shadow"
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
  --disable-nls \
  --without-libintl \
  --without-libiconv \
  --without-skey \
  --without-tcb \
  --without-btrfs \
  --disable-login \
  --disable-su

make -j"${LUMEN_MAKE_JOBS}"
make DESTDIR="${LUMEN_STAGE_ROOT}" install

# The shadow suite installs into /usr by prefix but expects its binaries on
# the standard PATH for user management from rescue shells.
for tool in useradd userdel usermod groupadd groupdel groupmod; do
  [ -e "${LUMEN_STAGE_ROOT}/usr/sbin/${tool}" ] || \
    lumen_die "Shadow tool missing after install: /usr/sbin/${tool}"
done

lumen_ok "${PKG_NAME}-${PKG_VER} built successfully"
