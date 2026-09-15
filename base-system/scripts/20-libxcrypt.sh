#!/usr/bin/env bash
# 20-libxcrypt.sh — Build libxcrypt for target sysroot & rootfs
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

PKG_NAME="libxcrypt"
PKG_VER="$(pkg_version "$PKG_NAME")"
PKG_URL="$(pkg_url "$PKG_NAME")"
PKG_SHA256="$(pkg_sha256 "$PKG_NAME")"
ARCHIVE="$(pkg_archive "$PKG_NAME")"
SRCDIR="$(pkg_srcdir "$PKG_NAME")"
BUILDDIR="$(pkg_builddir "$PKG_NAME")"

lumen_step "Building ${PKG_NAME}-${PKG_VER}"

lumen_fetch "$PKG_URL" "${BASE_SOURCES}/${ARCHIVE}" "$PKG_SHA256"

if [ ! -d "$SRCDIR" ]; then
  tar -xf "${BASE_SOURCES}/${ARCHIVE}" -C "${BASE_SOURCES}"
fi

mkdir -p "$BUILDDIR" && cd "$BUILDDIR"

"${SRCDIR}/configure" \
  --prefix="${LUMEN_STAGE_ROOT}/usr" \
  --build="$(gcc -dumpmachine)" \
  --host="${LUMEN_TARGET_TRIPLET}" \
  --target="${LUMEN_TARGET_TRIPLET}" \
  --enable-hashes=all \
  --enable-obsolete-api=glibc \
  --enable-static \
  --enable-shared

make -j"${LUMEN_MAKE_JOBS}"
make install

# Install headers and libraries into sysroot for cross-compiler linking.
# These are required target artifacts; never report success when staging them fails.
mkdir -p "${LUMEN_SYSROOT}/usr/include" "${LUMEN_SYSROOT}/usr/lib"
CRYPT_HEADER="${LUMEN_STAGE_ROOT}/usr/include/crypt.h"
if [ ! -f "$CRYPT_HEADER" ]; then
  lumen_die "Missing staged libxcrypt header: $CRYPT_HEADER"
fi

shopt -s nullglob
CRYPT_LIBS=("${LUMEN_STAGE_ROOT}"/usr/lib/libcrypt*)
shopt -u nullglob
if [ "${#CRYPT_LIBS[@]}" -eq 0 ]; then
  lumen_die "No staged libxcrypt libraries found under ${LUMEN_STAGE_ROOT}/usr/lib"
fi

cp -a "$CRYPT_HEADER" "${LUMEN_SYSROOT}/usr/include/"
cp -a "${CRYPT_LIBS[@]}" "${LUMEN_SYSROOT}/usr/lib/"

[ -f "${LUMEN_SYSROOT}/usr/include/crypt.h" ] || lumen_die "libxcrypt header was not installed into the sysroot"
ls "${LUMEN_SYSROOT}"/usr/lib/libcrypt* >/dev/null 2>&1 || lumen_die "libxcrypt libraries were not installed into the sysroot"

lumen_ok "${PKG_NAME}-${PKG_VER} built successfully"
