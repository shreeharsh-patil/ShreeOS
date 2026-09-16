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
# Build it here so wpa_supplicant never falls back to host headers/libraries.
if ! pkg-config --exists libnl-3.0 libnl-genl-3.0; then
  build_libnl
fi

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
  -e '/^CONFIG_INTERNAL_LIBTOMMATH(_FAST)?=/d' \
  .config

cat >>.config <<'EOF'
CONFIG_DRIVER_NL80211=y
CONFIG_LIBNL32=y
CONFIG_CTRL_IFACE=y
CONFIG_SAE=y
CONFIG_IEEE80211W=y
# Keep the target build self-contained until a target OpenSSL package exists.
# Internal TLS requires LibTomMath. Use wpa_supplicant's bundled minimal
# implementation so the cross-build does not depend on host tommath headers.
CONFIG_TLS=internal
CONFIG_INTERNAL_LIBTOMMATH=y
CONFIG_INTERNAL_LIBTOMMATH_FAST=y
EOF

# Assert that D-Bus stayed disabled and that target libnl is discoverable before
# starting the expensive compile. This turns configuration drift into a clear,
# early CI failure instead of a late missing-header error.
if grep -Eq '^CONFIG_(CTRL_IFACE_DBUS|DBUS)' .config; then
  lumen_die "wpa_supplicant D-Bus support must remain disabled until target D-Bus is staged"
fi
pkg-config --exists libnl-3.0 libnl-genl-3.0

make CC="${LUMEN_TARGET_TRIPLET}-gcc" -j"${LUMEN_MAKE_JOBS}"
install -Dm755 wpa_supplicant "${LUMEN_STAGE_ROOT}/usr/sbin/wpa_supplicant"
install -Dm755 wpa_cli "${LUMEN_STAGE_ROOT}/usr/sbin/wpa_cli"
install -Dm755 wpa_passphrase "${LUMEN_STAGE_ROOT}/usr/sbin/wpa_passphrase"
