#!/usr/bin/env bash
# Build the ShreeOS Wi-Fi backend with nl80211, WPA2/WPA3, and a target-only
# dependency graph. Host D-Bus, OpenSSL, and libnl must never leak into this
# cross-build.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

# nl80211 requires libnl. Build and stage it for the target before compiling
# wpa_supplicant so pkg-config resolves only ShreeOS libraries.
LIBNL_NAME="libnl"
LIBNL_VERSION="$(pkg_version "$LIBNL_NAME")"
LIBNL_ARCHIVE="${BASE_SOURCES}/$(pkg_archive "$LIBNL_NAME")"
LIBNL_SOURCE="${BASE_SOURCES}/${LIBNL_NAME}-${LIBNL_VERSION}"
LIBNL_BUILD="${BASE_BUILDDIR}/build-${LIBNL_NAME}"

lumen_step "Building ${LIBNL_NAME}-${LIBNL_VERSION} for nl80211"
lumen_fetch "$(pkg_url "$LIBNL_NAME")" "$LIBNL_ARCHIVE" "$(pkg_sha256 "$LIBNL_NAME")"

if [ ! -d "$LIBNL_SOURCE" ]; then
  tar -xzf "$LIBNL_ARCHIVE" -C "$BASE_SOURCES"
fi

rm -rf "$LIBNL_BUILD"
mkdir -p "$LIBNL_BUILD"
cd "$LIBNL_BUILD"

"$LIBNL_SOURCE/configure" \
  --prefix=/usr \
  --build="$(gcc -dumpmachine)" \
  --host="${LUMEN_TARGET_TRIPLET}" \
  --disable-static

make -j"${LUMEN_MAKE_JOBS}"
make DESTDIR="${LUMEN_STAGE_ROOT}" install
base_sync_sysroot

# Build wpa_supplicant from an explicit minimal configuration instead of the
# upstream sample defconfig. In that file, VARIABLE=n still counts as defined
# to make(1), which previously left D-Bus enabled and pulled host-only headers
# into the target build.
WPA_NAME="wpa_supplicant"
WPA_VERSION="$(pkg_version "$WPA_NAME")"
WPA_ARCHIVE="${BASE_SOURCES}/$(pkg_archive "$WPA_NAME")"
WPA_SOURCE="${BASE_SOURCES}/${WPA_NAME}-${WPA_VERSION}"

lumen_step "Building ${WPA_NAME}-${WPA_VERSION}"
lumen_fetch "$(pkg_url "$WPA_NAME")" "$WPA_ARCHIVE" "$(pkg_sha256 "$WPA_NAME")"

if [ ! -d "$WPA_SOURCE" ]; then
  tar -xzf "$WPA_ARCHIVE" -C "$BASE_SOURCES"
fi

cd "$WPA_SOURCE/wpa_supplicant"
make clean >/dev/null 2>&1 || true

cat >.config <<'EOF'
CONFIG_DRIVER_NL80211=y
CONFIG_LIBNL32=y
CONFIG_DRIVER_WEXT=y
CONFIG_CTRL_IFACE=y
CONFIG_WPA_CLI_EDIT=y

CONFIG_SAE=y
CONFIG_IEEE80211W=y
CONFIG_IEEE80211R=y
CONFIG_WPS=y

CONFIG_IEEE8021X_EAPOL=y
CONFIG_EAP_MD5=y
CONFIG_EAP_MSCHAPV2=y
CONFIG_EAP_TLS=y
CONFIG_EAP_PEAP=y
CONFIG_EAP_TTLS=y
CONFIG_EAP_GTC=y

# Keep TLS/crypto self-contained until a target OpenSSL package exists.
CONFIG_TLS=internal
CONFIG_INTERNAL_LIBTOMMATH=y
EOF

make CC="${LUMEN_TARGET_TRIPLET}-gcc" -j"${LUMEN_MAKE_JOBS}"

install -Dm755 wpa_supplicant "${LUMEN_STAGE_ROOT}/usr/sbin/wpa_supplicant"
install -Dm755 wpa_cli "${LUMEN_STAGE_ROOT}/usr/sbin/wpa_cli"
install -Dm755 wpa_passphrase "${LUMEN_STAGE_ROOT}/usr/sbin/wpa_passphrase"

lumen_ok "${WPA_NAME}-${WPA_VERSION} built successfully"
