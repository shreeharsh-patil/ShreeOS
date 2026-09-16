#!/usr/bin/env bash
# 19-util-linux.sh — Build util-linux
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

PKG_NAME="util-linux"
PKG_VER="$(pkg_version "$PKG_NAME")"
PKG_URL="$(pkg_url "$PKG_NAME")"
PKG_SHA256="$(pkg_sha256 "$PKG_NAME")"
ARCHIVE="$(pkg_archive "$PKG_NAME")"
SRCDIR="$(pkg_srcdir "$PKG_NAME")"
BUILDDIR="$(pkg_builddir "$PKG_NAME")"

lumen_step "Building ${PKG_NAME}-${PKG_VER}"

lumen_fetch "$PKG_URL" "${BASE_SOURCES}/${ARCHIVE}" "$PKG_SHA256"

if [ ! -d "$SRCDIR" ]; then
  tar -xf "${BASE_SOURCES}/${ARCHIVE}" -C "${BASE_SOURCES}"
fi

mkdir -p "$BUILDDIR" && cd "$BUILDDIR"

# Minimize build: only what we need for a chroot base system
"${SRCDIR}/configure" \
  --prefix="${LUMEN_STAGE_ROOT}/usr" \
  --build="$(gcc -dumpmachine)" \
  --host="${LUMEN_TARGET_TRIPLET}" \
  --target="${LUMEN_TARGET_TRIPLET}" \
  --docdir="${LUMEN_STAGE_ROOT}/usr/share/doc/util-linux-${PKG_VER}" \
  --disable-chfn-chsh \
  --disable-login \
  --disable-nologin \
  --disable-su \
  --disable-runuser \
  --disable-makeinstall-chown \
  --disable-makeinstall-setuid \
  --without-python \
  --without-systemd \
  --without-systemdsystemunitdir

make -j"${LUMEN_MAKE_JOBS}"
make install

lumen_ok "${PKG_NAME}-${PKG_VER} built successfully"
