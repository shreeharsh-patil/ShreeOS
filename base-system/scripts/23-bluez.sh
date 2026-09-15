#!/usr/bin/env bash
# BlueZ supplies bluetoothctl. The target build requires GLib and D-Bus;
# until those libraries are staged, Bluetooth is an explicitly deferred
# optional feature rather than a hard failure for the entire OS build.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

STATUS_DIR="${LUMEN_STAGE_ROOT}/etc/shreeos/features"
STATUS_FILE="${STATUS_DIR}/bluetooth.status"
mkdir -p "$STATUS_DIR"

if ! pkg-config --exists glib-2.0 dbus-1 2>/dev/null; then
  printf '%s\n' 'deferred: target glib-2.0 and dbus-1 are not staged' > "$STATUS_FILE"
  lumen_warn "BlueZ deferred: target GLib and D-Bus are not staged in the ShreeOS sysroot"
  exit 0
fi

version=5.79
archive="${LUMEN_BUILD_DIR}/sources/bluez-${version}.tar.xz"
source_dir="${LUMEN_BUILD_DIR}/sources/bluez-${version}"

lumen_fetch \
  "https://www.kernel.org/pub/linux/bluetooth/bluez-${version}.tar.xz" \
  "$archive" \
  "4164a5303a9f71c70f48c03ff60be34231b568d93a9ad5e79928d34e6aa0ea8a"

[ -d "$source_dir" ] || tar -xJf "$archive" -C "${LUMEN_BUILD_DIR}/sources"
mkdir -p "${LUMEN_BUILD_DIR}/build-bluez"
cd "${LUMEN_BUILD_DIR}/build-bluez"

"$source_dir/configure" \
  --prefix=/usr \
  --host="${LUMEN_TARGET_TRIPLET}" \
  --disable-systemd \
  --disable-udev \
  --disable-cups

make -j"${LUMEN_MAKE_JOBS}"
make DESTDIR="${LUMEN_STAGE_ROOT}" install
printf '%s\n' 'ready' > "$STATUS_FILE"
lumen_ok "BlueZ ${version} built successfully"
