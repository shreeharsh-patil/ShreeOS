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

# util-linux probes ncurses with ncursesw6-config. During a cross-build,
# falling back to the host runner's config script leaks host-only linker flags
# (Ubuntu's script adds -ltinfo) into the ShreeOS target link. Use the config
# script installed by our target ncurses build and explicitly keep terminfo
# inside libncursesw, matching how 02-ncurses.sh is configured.
TARGET_NCURSES_CONFIG="${LUMEN_STAGE_ROOT}/usr/bin/ncursesw6-config"
if [ ! -x "$TARGET_NCURSES_CONFIG" ]; then
  lumen_die "Target ncurses config not found: ${TARGET_NCURSES_CONFIG}. Build ncurses before util-linux."
fi

# Minimize build: only what we need for a chroot base system.
NCURSESW6_CONFIG="$TARGET_NCURSES_CONFIG" \
"${SRCDIR}/configure" \
  --prefix=/usr \
  --build="$(gcc -dumpmachine)" \
  --host="${LUMEN_TARGET_TRIPLET}" \
  --target="${LUMEN_TARGET_TRIPLET}" \
  --docdir="/usr/share/doc/util-linux-${PKG_VER}" \
  --with-ncursesw \
  --without-ncurses \
  --without-tinfo \
  --disable-chfn-chsh \
  --disable-login \
  --disable-nologin \
  --disable-su \
  --disable-runuser \
  --disable-liblastlog2 \
  --disable-makeinstall-chown \
  --disable-makeinstall-setuid \
  --without-python \
  --without-systemd \
  --without-systemdsystemunitdir

make -j"${LUMEN_MAKE_JOBS}"
make DESTDIR="${LUMEN_STAGE_ROOT}" install

lumen_ok "${PKG_NAME}-${PKG_VER} built successfully"
