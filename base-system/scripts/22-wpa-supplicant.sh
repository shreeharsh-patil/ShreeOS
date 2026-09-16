#!/usr/bin/env bash
# Build the ShreeOS Wi-Fi backend with nl80211, WPA3 SAE, and target libnl.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

build_libnl() {
  local name="libnl"
  local version url sha archive source builddir

  version="$(pkg_version "$name")"
  url="$(pkg_url "$name")"
  sha="$(pkg_sha256 "$name")"
  archive="${BASE_SOURCES}/$(pkg_archive "$name")"
  source="${BASE_SOURCES}/${name}-${version}"
  builddir="${BASE_BUILDDIR}/build-${name}"

  lumen_step "Building ${name}-${version} for wpa_supplicant"
  lumen_fetch "$url" "$archive" "$sha"

  if [ ! -d "$source" ]; then
    tar -xf "$archive" -C "$BASE_SOURCES"
  fi

  rm -rf "$builddir"
  mkdir -p "$builddir"
  cd "$builddir"

  "$source/configure" \
    --prefix=/usr \
    --build="$(gcc -dumpmachine)" \
    --host="${LUMEN_TARGET_TRIPLET}" \
    --disable-static

  make -j"${LUMEN_MAKE_JOBS}"
  make DESTDIR="${LUMEN_STAGE_ROOT}" install

  # Later packages resolve libnl through the target sysroot, never host pkg-config.
  base_sync_sysroot
  pkg-config --exists libnl-3.0
  pkg-config --exists libnl-genl-3.0
  lumen_ok "${name}-${version} built successfully"
}

# nl80211 is the modern Linux Wi-Fi control path and requires target libnl.
# A cached compiler sysroot can outlive the staged rootfs, so require BOTH
# pkg-config metadata and staged target libraries before reusing libnl.
libnl_is_staged() {
  compgen -G "${LUMEN_STAGE_ROOT}/usr/lib/libnl-3.so*" >/dev/null &&
    compgen -G "${LUMEN_STAGE_ROOT}/usr/lib/libnl-genl-3.so*" >/dev/null
}
if ! pkg-config --exists libnl-3.0 libnl-genl-3.0 || ! libnl_is_staged; then
  build_libnl
fi

# WPA3 SAE/DPP require the bignum/ECC API provided by crypto_openssl.
# The internal TLS backend in wpa_supplicant 2.11 does not implement the full
# crypto_bignum/crypto_ec surface and fails at link time when SAE is enabled.
[ -f "${LUMEN_SYSROOT}/usr/include/openssl/ssl.h" ] ||
  lumen_die "Target OpenSSL headers are missing; build 21-openssl first"
pkg-config --exists openssl ||
  lumen_die "Target OpenSSL libraries are missing from the ShreeOS sysroot"

VERSION=2.11
ARCHIVE="${LUMEN_BUILD_DIR}/sources/wpa_supplicant-${VERSION}.tar.gz"
SOURCE="${LUMEN_BUILD_DIR}/sources/wpa_supplicant-${VERSION}"
lumen_fetch "https://w1.fi/releases/wpa_supplicant-${VERSION}.tar.gz" "$ARCHIVE" "912ea06f74e30a8e36fbb68064d6cdff218d8d591db0fc5d75dee6c81ac7fc0a"
[ -d "$SOURCE" ] || tar -xzf "$ARCHIVE" -C "${LUMEN_BUILD_DIR}/sources"
cd "$SOURCE/wpa_supplicant"

cp defconfig .config

# defconfig enables optional host integrations that are not part of the ShreeOS
# target sysroot yet. Merely assigning '=n' is unsafe here because the upstream
# Makefile uses make-variable presence checks for some options. Remove them
# entirely, then append the exact target feature set below.
sed -i -E \
  -e '/^CONFIG_CTRL_IFACE_DBUS/d' \
  -e '/^CONFIG_DBUS/d' \
  -e '/^CONFIG_DRIVER_NL80211=/d' \
  -e '/^CONFIG_LIBNL(20|32)?=/d' \
  -e '/^CONFIG_TLS=/d' \
  -e '/^CONFIG_CRYPTO=/d' \
  -e '/^CONFIG_ECC=/d' \
  -e '/^CONFIG_INTERNAL_LIBTOMMATH(_FAST)?=/d' \
  .config

cat >>.config <<'EOF'
CONFIG_DRIVER_NL80211=y
CONFIG_LIBNL32=y
CONFIG_CTRL_IFACE=y
CONFIG_SAE=y
CONFIG_IEEE80211W=y
# OpenSSL supplies the ECC/bignum primitives required by WPA3 SAE/DPP.
# The library is target-built in 21-openssl.sh and resolved only via the
# ShreeOS compiler sysroot; host OpenSSL must never be linked here.
CONFIG_TLS=openssl
CONFIG_ECC=y
EOF

# Assert that D-Bus stayed disabled and that target libnl is discoverable before
# starting the expensive compile. This turns configuration drift into a clear,
# early CI failure instead of a late missing-header error.
if grep -Eq '^CONFIG_(CTRL_IFACE_DBUS|DBUS)' .config; then
  lumen_die "wpa_supplicant D-Bus support must remain disabled until target D-Bus is staged"
fi
if ! grep -qx 'CONFIG_TLS=openssl' .config; then
  lumen_die "wpa_supplicant must use the target OpenSSL TLS/crypto backend"
fi
if grep -Eq '^CONFIG_(CRYPTO=internal|INTERNAL_LIBTOMMATH)' .config; then
  lumen_die "wpa_supplicant internal crypto must stay disabled when WPA3 ECC is enabled"
fi
if ! grep -qx 'CONFIG_ECC=y' .config; then
  lumen_die "WPA3 SAE/DPP support requires CONFIG_ECC=y"
fi
pkg-config --exists libnl-3.0 libnl-genl-3.0 openssl

make CC="${LUMEN_TARGET_TRIPLET}-gcc" -j"${LUMEN_MAKE_JOBS}"
install -Dm755 wpa_supplicant "${LUMEN_STAGE_ROOT}/usr/sbin/wpa_supplicant"
install -Dm755 wpa_cli "${LUMEN_STAGE_ROOT}/usr/sbin/wpa_cli"
install -Dm755 wpa_passphrase "${LUMEN_STAGE_ROOT}/usr/sbin/wpa_passphrase"
