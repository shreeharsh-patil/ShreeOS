#!/usr/bin/env bash
# Build the target OpenSSL provider used by wpa_supplicant and future TLS clients.
# This must be target-built: linking the cross-compiled OS against host libssl
# would leak the host ABI into ShreeOS and make the ISO non-reproducible.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

lumen_require_cmd perl

VERSION="$(pkg_version openssl)"
ARCHIVE="${BASE_SOURCES}/$(pkg_archive openssl)"
SOURCE="${BASE_SOURCES}/openssl-${VERSION}"

lumen_step "Building OpenSSL ${VERSION} for ${LUMEN_TARGET_TRIPLET}"
lumen_fetch "$(pkg_url openssl)" "$ARCHIVE" "$(pkg_sha256 openssl)"

# OpenSSL is intentionally rebuilt from a clean source tree. Its generated
# Makefile records compiler/sysroot settings, so reusing a tree can silently
# carry host settings across retries.
rm -rf "$SOURCE"
tar -xzf "$ARCHIVE" -C "$BASE_SOURCES"
cd "$SOURCE"

# common.sh exports CC/AR/etc. as fully-prefixed target tools. OpenSSL's
# --cross-compile-prefix applies that prefix itself; leaving those variables in
# the environment would produce a double-prefixed compiler name.
env -u CC -u CXX -u AR -u AS -u RANLIB -u LD -u STRIP \
  CC="${LUMEN_TARGET_TRIPLET}-gcc" AR="${LUMEN_TARGET_TRIPLET}-ar" RANLIB="${LUMEN_TARGET_TRIPLET}-ranlib" \
perl ./Configure linux-x86_64 \
    --prefix=/usr \
    --openssldir=/etc/ssl \
    --libdir=lib \
      --sysroot="${LUMEN_SYSROOT}" \
    shared \
    no-tests

# Guard against this regression before the expensive compile starts.
if grep -Fq "${LUMEN_TARGET_TRIPLET}-${LUMEN_TARGET_TRIPLET}-gcc" Makefile; then
  lumen_die "OpenSSL compiler was double-prefixed during cross configuration"
fi

make -j"${LUMEN_MAKE_JOBS}"
make DESTDIR="${LUMEN_STAGE_ROOT}" install_sw install_ssldirs

base_sync_sysroot

[ -f "${LUMEN_SYSROOT}/usr/include/openssl/ssl.h" ] ||
  lumen_die "Target OpenSSL headers were not installed into the sysroot"
if ! compgen -G "${LUMEN_STAGE_ROOT}/usr/lib/libcrypto.so*" >/dev/null; then
  lumen_die "Target libcrypto shared library was not staged"
fi
if ! compgen -G "${LUMEN_STAGE_ROOT}/usr/lib/libssl.so*" >/dev/null; then
  lumen_die "Target libssl shared library was not staged"
fi
pkg-config --exists openssl ||
  lumen_die "Target OpenSSL pkg-config metadata is not visible through the ShreeOS sysroot"

lumen_ok "OpenSSL ${VERSION} built successfully"
