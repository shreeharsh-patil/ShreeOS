#!/usr/bin/env bash
# 38-dbus.sh — Build D-Bus (system message bus)
#
# The system bus daemon and its library; the session/user bus is provided by
# the same dbus-daemon. expat is the only hard XML dependency and is built
# earlier by the graphics stage, so its pkg-config metadata must be present.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

PKG_NAME="dbus"
PKG_VER="$(pkg_version "$PKG_NAME")"
ARCHIVE="$(pkg_archive "$PKG_NAME")"
SRCDIR="$(base_pkg_extract "$PKG_NAME")"
BUILDDIR="$(pkg_builddir "$PKG_NAME")"

lumen_step "Building ${PKG_NAME}-${PKG_VER}"

if ! pkg-config --exists expat; then
  lumen_die "Target expat pkg-config metadata is missing from the ShreeOS sysroot (build the graphics stage first)"
fi

mkdir -p "$BUILDDIR" && cd "$BUILDDIR"

"${SRCDIR}/configure" \
  --prefix=/usr \
  --build="$(gcc -dumpmachine)" \
  --host="${LUMEN_TARGET_TRIPLET}" \
  --target="${LUMEN_TARGET_TRIPLET}" \
  --sysconfdir=/etc \
  --localstatedir=/var \
  --runstatedir=/run \
  --with-system-pid-file=/run/dbus/pid \
  --with-system-socket=/run/dbus/system_bus_socket \
  --with-session-socket-dir=/tmp \
  --disable-systemd \
  --disable-user-session \
  --disable-doxygen-docs \
  --disable-xml-docs \
  --disable-ducktype-docs

make -j"${LUMEN_MAKE_JOBS}"
make DESTDIR="${LUMEN_STAGE_ROOT}" install

base_sync_sysroot

[ -e "${LUMEN_STAGE_ROOT}/usr/bin/dbus-daemon" ] || \
  lumen_die "Target dbus-daemon was not staged"
compgen -G "${LUMEN_STAGE_ROOT}/usr/lib/libdbus-1.so*" >/dev/null || \
  lumen_die "Target libdbus-1 shared library was not staged"

lumen_ok "${PKG_NAME}-${PKG_VER} built successfully"
