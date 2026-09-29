#!/usr/bin/env bash
# 36-shadow.sh — Build shadow (useradd, groupadd, passwd, login)
#
# The account-management tools a desktop user creation flow needs. login is
# disabled because util-linux login and the session manager own that path;
# shadow still supplies the account database tools.
#
# --without-libbsd is mandatory, and upstream help text is misleading here.
# shadow 4.18.0 declares the knob at configure.ac:203-205 with the fallback
# [with_libbsd=yes], so libbsd support is ON unconditionally unless the switch
# is passed explicitly. Its help string (configure:1630) claims a default of
# yes-if-found, which is an intent the macro does not implement. Left unpinned,
# configure reaches configure.ac:357-359 and aborts with
#   checking for library containing readpassphrase... no
#   configure: error: readpassphrase() is missing, either from libc or libbsd
# because glibc supplies neither readpassphrase() nor readpassphrase.h, and
# libbsd is not in the Phase 2 package set. That is the 2026-09-29 CI failure at
# package 36/51. No functionality is lost: the AM_CONDITIONAL at
# configure.ac:376 drives lib/Makefile.am:294-299, which compiles the vendored
# lib/readpassphrase.c and lib/freezero.c when WITH_LIBBSD is false.
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
  --without-libbsd \
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
