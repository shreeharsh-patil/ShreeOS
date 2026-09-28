#!/usr/bin/env bash
# 45-curl.sh — Build curl (HTTP/HTTPS client and library)
#
# Links the target OpenSSL staged by 21-openssl.sh. The CA bundle is not
# installed here; the rootfs skeleton owns /etc/ssl/certs so there is exactly
# one trust-store source of truth.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

PKG_NAME="curl"
PKG_VER="$(pkg_version "$PKG_NAME")"
ARCHIVE="$(pkg_archive "$PKG_NAME")"
SRCDIR="$(base_pkg_extract "$PKG_NAME")"
BUILDDIR="$(pkg_builddir "$PKG_NAME")"

lumen_step "Building ${PKG_NAME}-${PKG_VER}"

if ! pkg-config --exists openssl; then
  lumen_die "Target OpenSSL pkg-config metadata is missing from the ShreeOS sysroot"
fi

# configure's run-result cross checks: answer the target probes explicitly.
export ac_cv_func_getaddrinfo=yes

mkdir -p "$BUILDDIR" && cd "$BUILDDIR"

"${SRCDIR}/configure" \
  --prefix=/usr \
  --build="$(gcc -dumpmachine)" \
  --host="${LUMEN_TARGET_TRIPLET}" \
  --target="${LUMEN_TARGET_TRIPLET}" \
  --with-openssl \
  --without-libpsl \
  --without-libidn2 \
  --without-brotli \
  --without-zstd \
  --without-nghttp2 \
  --without-libssh2 \
  --without-librtmp \
  --disable-ldap \
  --disable-ldaps \
  --disable-manual

make -j"${LUMEN_MAKE_JOBS}"
make DESTDIR="${LUMEN_STAGE_ROOT}" install

base_sync_sysroot

[ -e "${LUMEN_STAGE_ROOT}/usr/bin/curl" ] || \
  lumen_die "Target curl binary was not staged"
compgen -G "${LUMEN_STAGE_ROOT}/usr/lib/libcurl.so*" >/dev/null || \
  lumen_die "Target libcurl shared library was not staged"

base_assert_no_host_binary "${LUMEN_STAGE_ROOT}/usr/bin/curl"

lumen_ok "${PKG_NAME}-${PKG_VER} built successfully"
