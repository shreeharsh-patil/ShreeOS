#!/usr/bin/env bash
# Build the lightweight ShreeOS Wi-Fi backend with nl80211 and WPA3 SAE.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"
VERSION=2.11
ARCHIVE="${LUMEN_BUILD_DIR}/sources/wpa_supplicant-${VERSION}.tar.gz"
SOURCE="${LUMEN_BUILD_DIR}/sources/wpa_supplicant-${VERSION}"
lumen_fetch "https://w1.fi/releases/wpa_supplicant-${VERSION}.tar.gz" "$ARCHIVE" "912ea06f74e30a8e36fbb68064d6cdff218d8d591db0fc5d75dee6c81ac7fc0a"
[ -d "$SOURCE" ] || tar -xzf "$ARCHIVE" -C "${LUMEN_BUILD_DIR}/sources"
cd "$SOURCE/wpa_supplicant"
cp defconfig .config
cat >>.config <<'EOF'
CONFIG_DRIVER_NL80211=y
CONFIG_CTRL_IFACE=y
CONFIG_CTRL_IFACE_DBUS_NEW=n
CONFIG_SAE=y
CONFIG_IEEE80211W=y
CONFIG_TLS=openssl
EOF
make CC="${LUMEN_TARGET_TRIPLET}-gcc" -j"${LUMEN_MAKE_JOBS}"
install -Dm755 wpa_supplicant "${LUMEN_STAGE_ROOT}/usr/sbin/wpa_supplicant"
install -Dm755 wpa_cli "${LUMEN_STAGE_ROOT}/usr/sbin/wpa_cli"
install -Dm755 wpa_passphrase "${LUMEN_STAGE_ROOT}/usr/sbin/wpa_passphrase"
