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

# util-linux prefers ncurses*-config helpers before pkg-config. During a
# cross-build, falling back to the host helper leaks Ubuntu linker flags such
# as -ltinfo into the ShreeOS target link. Force those helpers to fail so
# configure uses the target ncursesw.pc from PKG_CONFIG_LIBDIR instead.
export NCURSESW6_CONFIG=/bin/false
export NCURSESW5_CONFIG=/bin/false
export NCURSES6_CONFIG=/bin/false
export NCURSES5_CONFIG=/bin/false

if ! pkg-config --exists ncursesw; then
  lumen_die "Target ncursesw pkg-config metadata is missing from the ShreeOS sysroot"
fi
lumen_log "Target ncurses flags: $(pkg-config --libs ncursesw)"

# Minimize build: only what we need for a chroot base system.
# ShreeOS currently builds ncurses with terminfo inside libncursesw, so do not
# ask util-linux to link a separate libtinfo target library.
"${SRCDIR}/configure" \
  --prefix=/usr \
  --build="$(gcc -dumpmachine)" \
  --host="${LUMEN_TARGET_TRIPLET}" \
  --target="${LUMEN_TARGET_TRIPLET}" \
  --docdir="/usr/share/doc/util-linux-${PKG_VER}" \
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
  --without-systemdsystemunitdir \
  --without-tinfo

make -j"${LUMEN_MAKE_JOBS}"
make DESTDIR="${LUMEN_STAGE_ROOT}" install

lumen_ok "${PKG_NAME}-${PKG_VER} built successfully"
