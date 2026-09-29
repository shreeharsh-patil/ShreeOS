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

# expat is dbus's only hard XML dependency, but the graphics stage builds it
# -- and the standalone Base System workflow never runs that stage, so this
# gate could never pass there (the 2026-09-29 CI failure at 38/51).
# Following the 22-wpa-supplicant.sh precedent, a missing dependency is built
# inline from the same pinned source instead of failing the whole base build.
# The checksum pin lives in the graphics stage's packages.list, which is the
# single source of record for expat; duplicating it here is what makes the
# inline fetch verifiable. When the graphics stage has already built expat,
# this block is skipped entirely and both stages install bit-identical code
# from the same tarball.
EXPAT_VERSION=2.8.5
EXPAT_URL="https://github.com/libexpat/libexpat/releases/download/R_2_8_5/expat-2.8.5.tar.xz"
EXPAT_SHA256=1e727b8933ec51a77a9a9d9afcf8e688bce45d907c13e36ab7393fe36e703182

if ! pkg-config --exists expat; then
  lumen_log "Target expat not found in the ShreeOS sysroot; building it inline for dbus"
  expat_archive="${BASE_SOURCES}/expat-${EXPAT_VERSION}.tar.xz"
  expat_srcdir="${BASE_SOURCES}/expat-${EXPAT_VERSION}"
  lumen_fetch "$EXPAT_URL" "$expat_archive" "$EXPAT_SHA256"
  [ -d "$expat_srcdir" ] || tar -xJf "$expat_archive" -C "$BASE_SOURCES"
  expat_builddir="${BASE_BUILDDIR}/build-expat"
  rm -rf "$expat_builddir"
  mkdir -p "$expat_builddir"
  cd "$expat_builddir"
  "${expat_srcdir}/configure" \
    --prefix=/usr \
    --build="$(gcc -dumpmachine)" \
    --host="${LUMEN_TARGET_TRIPLET}" \
    --without-xmlwf \
    --without-docbook \
    --without-examples \
    --without-tests \
    --disable-static
  make -j"${LUMEN_MAKE_JOBS}"
  make DESTDIR="${LUMEN_STAGE_ROOT}" install
  base_sync_sysroot
  pkg-config --exists expat || \
    lumen_die "expat was built inline but its pkg-config metadata is still missing from the sysroot"
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
