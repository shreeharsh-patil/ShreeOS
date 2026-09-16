#!/usr/bin/env bash
# desktop/wm/build-wm.sh — Build suckless tools for ShreeOS desktop
#
# Compiles dwm, st, and dmenu using the cross-compiler.
#
# Usage:
#   bash desktop/wm/build-wm.sh              # build all
#   bash desktop/wm/build-wm.sh dwm          # build specific
#   bash desktop/wm/build-wm.sh st dmenu     # build multiple
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DESKTOP_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
LUMEN_ROOT_DIR="$(cd "$DESKTOP_DIR/../.." && pwd)"

source "$LUMEN_ROOT_DIR/build.conf"
source "$LUMEN_ROOT_DIR/scripts/common.sh"
source "$SCRIPT_DIR/sources.list"

COMPONENTS=("${@:-dwm}" "${@:-st}" "${@:-dmenu}")
if [ $# -gt 0 ]; then
  COMPONENTS=("$@")
else
  COMPONENTS=(dwm st dmenu)
fi
BUILDDIR="${LUMEN_BUILD_DIR}/desktop"
export CC="${LUMEN_TARGET_TRIPLET}-gcc"
export AR="${LUMEN_TARGET_TRIPLET}-ar"

lumen_require_cmd "${CC}"

mkdir -p "$BUILDDIR"

build_suckless() {
  local name="$1" url="$2" sha="$3"
  local archive
  archive="${BUILDDIR}/$(basename "${url}")"

  lumen_step "Building ${name}"

  lumen_fetch "$url" "$archive" "$sha"

  if [ ! -d "${BUILDDIR}/${name}" ]; then
    tar -xzf "$archive" -C "$BUILDDIR"
    mv "${BUILDDIR}/${name}-"* "${BUILDDIR}/${name}" 2>/dev/null || true
  fi

  cd "${BUILDDIR}/${name}"

  # Apply distro config (config.h or patches)
  if [ -f "${SCRIPT_DIR}/patches/${name}.patch" ]; then
    patch -p1 < "${SCRIPT_DIR}/patches/${name}.patch"
  fi

  # Use distro config.mk if available
  if [ -f "${SCRIPT_DIR}/config/${name}.mk" ]; then
    cp "${SCRIPT_DIR}/config/${name}.mk" config.mk
  else
    # Override config.mk for cross-compilation
    local ver_clean="${name#*-}"
    cat > config.mk <<CONFIGMK
VERSION = ${ver_clean}
PREFIX = /usr
MANPREFIX = \${PREFIX}/share/man
X11INC = ${LUMEN_SYSROOT}/usr/include/X11
X11LIB = ${LUMEN_SYSROOT}/usr/lib
CC = ${CC}
AR = ${AR}
CFLAGS = -std=c99 -pedantic -Wall -Wextra -Os -I\${X11INC}
LDFLAGS = -L\${X11LIB} -lX11
CONFIGMK
  fi

  make -j"${LUMEN_MAKE_JOBS}"
  make DESTDIR="${LUMEN_STAGE_ROOT}" install

  lumen_ok "${name} built and installed"
}

for comp in "${COMPONENTS[@]}"; do
  case "$comp" in
    dwm)   build_suckless "dwm"   "$DWM_URL"   "$DWM_SHA256" ;;
    st)    build_suckless "st"    "$ST_URL"    "$ST_SHA256" ;;
    dmenu) build_suckless "dmenu" "$DMENU_URL" "$DMENU_SHA256" ;;
    *)     lumen_warn "Unknown component: ${comp}" ;;
  esac
done

lumen_ok "Desktop WM components built"
