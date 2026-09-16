#!/usr/bin/env bash
# BlueZ supplies bluetoothctl; it remains optional at runtime when no adapter exists.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; source "$SCRIPT_DIR/common.sh"
version=5.79; archive="${LUMEN_BUILD_DIR}/sources/bluez-${version}.tar.xz"; source="${LUMEN_BUILD_DIR}/sources/bluez-${version}"
lumen_fetch "https://www.kernel.org/pub/linux/bluetooth/bluez-${version}.tar.xz" "$archive" "4164a5303a9f71c70f48c03ff60be34231b568d93a9ad5e79928d34e6aa0ea8a"
[ -d "$source" ] || tar -xJf "$archive" -C "${LUMEN_BUILD_DIR}/sources"
mkdir -p "${LUMEN_BUILD_DIR}/build-bluez"; cd "${LUMEN_BUILD_DIR}/build-bluez"
"$source/configure" --prefix=/usr --host="${LUMEN_TARGET_TRIPLET}" --disable-systemd --disable-udev --disable-cups
make -j"${LUMEN_MAKE_JOBS}"; make DESTDIR="${LUMEN_STAGE_ROOT}" install
