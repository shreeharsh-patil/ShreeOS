#!/usr/bin/env bash
# 50-usbutils.sh — Build usbutils (lsusb and usbhid-dump)
#
# usbutils needs libusb and libudev at build time; both are provided by later
# stages, so this script is wired to run only when those pkg-config records
# exist and otherwise reports its dependency explicitly instead of failing
# the whole base build.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

STATUS_DIR="${LUMEN_STAGE_ROOT}/etc/shreeos/features"
STATUS_FILE="${STATUS_DIR}/usbutils.status"
mkdir -p "$STATUS_DIR"

if ! pkg-config --exists libusb-1.0 libudev; then
  printf '%s\n' 'deferred: target libusb-1.0 and libudev are not staged' > "$STATUS_FILE"
  lumen_warn "usbutils deferred: target libusb-1.0/libudev are not staged in the ShreeOS sysroot"
  exit 0
fi

PKG_NAME="usbutils"
PKG_VER="$(pkg_version "$PKG_NAME")"
ARCHIVE="$(pkg_archive "$PKG_NAME")"
SRCDIR="$(base_pkg_extract "$PKG_NAME")"
BUILDDIR="$(pkg_builddir "$PKG_NAME")"

lumen_step "Building ${PKG_NAME}-${PKG_VER}"

mkdir -p "$BUILDDIR" && cd "$BUILDDIR"

"${SRCDIR}/configure" \
  --prefix=/usr \
  --build="$(gcc -dumpmachine)" \
  --host="${LUMEN_TARGET_TRIPLET}" \
  --target="${LUMEN_TARGET_TRIPLET}" \
  --sysconfdir=/etc \
  --datadir=/usr/share \
  --disable-zlib

make -j"${LUMEN_MAKE_JOBS}"
make DESTDIR="${LUMEN_STAGE_ROOT}" install

[ -e "${LUMEN_STAGE_ROOT}/usr/bin/lsusb" ] || \
  lumen_die "Target lsusb binary was not staged"
printf '%s\n' 'ready' > "$STATUS_FILE"

lumen_ok "${PKG_NAME}-${PKG_VER} built successfully"
