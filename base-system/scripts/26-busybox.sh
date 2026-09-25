#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

PKG_NAME="busybox"
PKG_VER="$(pkg_version "$PKG_NAME")"
PKG_URL="$(pkg_url "$PKG_NAME")"
PKG_SHA256="$(pkg_sha256 "$PKG_NAME")"
ARCHIVE="$(pkg_archive "$PKG_NAME")"
SRCDIR="$(pkg_srcdir "$PKG_NAME")"
BUILDDIR="$(pkg_builddir "$PKG_NAME")"

lumen_step "Building ${PKG_NAME}-${PKG_VER}"
CROSS_COMPILE="${CROSS_COMPILE:-${LUMEN_TARGET_TRIPLET}-}"
export CROSS_COMPILE
lumen_fetch "$PKG_URL" "${BASE_SOURCES}/${ARCHIVE}" "$PKG_SHA256"
rm -rf "$SRCDIR" "$BUILDDIR"
tar -xf "${BASE_SOURCES}/${ARCHIVE}" -C "${BASE_SOURCES}"
mkdir -p "$BUILDDIR"
cp -a "${SRCDIR}/." "$BUILDDIR/"
cd "$BUILDDIR"

make ARCH="$LUMEN_ARCH" CROSS_COMPILE="${CROSS_COMPILE}" allnoconfig

set_config() {
  local option="$1"
  local value="$2"
  sed -i "/^${option}=/d;/^# ${option} /d" .config
  printf '%s=%s\n' "$option" "$value" >> .config
}

for option in \
  CONFIG_STATIC \
  CONFIG_IP \
  CONFIG_FEATURE_IP_ADDRESS \
  CONFIG_FEATURE_IP_LINK \
  CONFIG_FEATURE_IP_ROUTE \
  CONFIG_IFCONFIG \
  CONFIG_FEATURE_IFCONFIG_STATUS \
  CONFIG_ROUTE \
  CONFIG_UDHCPC \
  CONFIG_FEATURE_UDHCPC_SANITIZEOPT \
  CONFIG_MDEV \
  CONFIG_MODPROBE \
  CONFIG_INSMOD \
  CONFIG_RMMOD \
  CONFIG_LSMOD \
  CONFIG_MODINFO \
  CONFIG_PING \
  CONFIG_NETSTAT; do
  set_config "$option" y
done
set_config CONFIG_UDHCPC_DEFAULT_SCRIPT '"/usr/share/udhcpc/default.script"'

make ARCH="$LUMEN_ARCH" CROSS_COMPILE="${CROSS_COMPILE}" silentoldconfig

for option in \
  CONFIG_STATIC \
  CONFIG_IP \
  CONFIG_FEATURE_IP_ADDRESS \
  CONFIG_FEATURE_IP_LINK \
  CONFIG_FEATURE_IP_ROUTE \
  CONFIG_IFCONFIG \
  CONFIG_FEATURE_IFCONFIG_STATUS \
  CONFIG_ROUTE \
  CONFIG_UDHCPC \
  CONFIG_MDEV \
  CONFIG_MODPROBE \
  CONFIG_INSMOD \
  CONFIG_RMMOD \
  CONFIG_LSMOD \
  CONFIG_MODINFO \
  CONFIG_PING \
  CONFIG_NETSTAT; do
  grep -q "^${option}=y$" .config || lumen_die "BusyBox option did not remain enabled: ${option}"
done

make -j"${LUMEN_MAKE_JOBS}" ARCH="$LUMEN_ARCH" CROSS_COMPILE="${CROSS_COMPILE}"
[ -s "$BUILDDIR/busybox" ] || lumen_die "BusyBox binary was not produced"
file "$BUILDDIR/busybox" | grep -q 'ELF 64-bit.*x86-64' || lumen_die "BusyBox is not a target x86-64 ELF binary"
if command -v readelf >/dev/null 2>&1 && readelf -d "$BUILDDIR/busybox" 2>/dev/null | grep -q '(NEEDED)'; then
  lumen_die "BusyBox unexpectedly contains dynamic runtime dependencies"
fi

install -Dm755 "$BUILDDIR/busybox" "${LUMEN_STAGE_ROOT}/usr/bin/busybox"
for applet in ip ifconfig route udhcpc mdev modprobe modinfo insmod rmmod lsmod ping netstat; do
  ln -sfn busybox "${LUMEN_STAGE_ROOT}/usr/bin/${applet}"
done
mkdir -p "${LUMEN_STAGE_ROOT}/sbin"
ln -sfn ../usr/bin/busybox "${LUMEN_STAGE_ROOT}/sbin/mdev"
install -Dm755 "$SCRIPT_DIR/udhcpc-default.sh" "${LUMEN_STAGE_ROOT}/usr/share/udhcpc/default.script"

lumen_ok "${PKG_NAME}-${PKG_VER} built successfully"
