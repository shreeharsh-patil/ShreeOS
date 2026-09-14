#!/usr/bin/env bash
# desktop/wm/build-wm.sh — Build suckless tools for the ShreeOS desktop
#
# Builds dwm, st, and dmenu against the ShreeOS target sysroot.  The
# distribution-owned config headers in desktop/configs/ are copied into each
# pristine upstream source tree before compilation, then the small audited
# ShreeOS compatibility patches are applied.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DESKTOP_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
SHREEOS_ROOT_DIR="$(cd "$DESKTOP_DIR/.." && pwd)"

source "$SHREEOS_ROOT_DIR/build.conf"
source "$SHREEOS_ROOT_DIR/scripts/common.sh"
source "$SCRIPT_DIR/sources.list"

if [ "$#" -gt 0 ]; then
  COMPONENTS=("$@")
else
  COMPONENTS=(dwm st dmenu)
fi

BUILDDIR="${SHREEOS_BUILD_DIR}/desktop"
CC="${SHREEOS_TOOLS}/bin/${SHREEOS_TARGET_TRIPLET}-gcc"

shreeos_require_dir "$BUILDDIR"
lumen_require_cmd "$CC"
lumen_require_cmd patch

# These are target dependencies, not host build dependencies.  Failing here
# gives an actionable error instead of an opaque compiler/linker failure.
verify_desktop_sysroot() {
  local missing_headers=0
  local required_headers=(
    "usr/include/X11/Xlib.h"
    "usr/include/X11/Xft/Xft.h"
    "usr/include/X11/extensions/Xinerama.h"
    "usr/include/fontconfig/fontconfig.h"
    "usr/include/freetype2/ft2build.h"
  )
  local header

  for header in "${required_headers[@]}"; do
    if [ ! -f "${SHREEOS_SYSROOT}/${header}" ]; then
      shreeos_warn "Desktop target header missing: ${header}"
      missing_headers=1
    fi
  done

  if [ "$missing_headers" -ne 0 ]; then
    shreeos_die "Desktop target dependencies are incomplete. Build/stage X11, Xft, Xinerama, Fontconfig and FreeType into ${SHREEOS_SYSROOT} before building the desktop."
  fi

  export PKG_CONFIG_SYSROOT_DIR="${SHREEOS_SYSROOT}"
  export PKG_CONFIG_LIBDIR="${SHREEOS_SYSROOT}/usr/lib/pkgconfig:${SHREEOS_SYSROOT}/usr/lib64/pkgconfig:${SHREEOS_SYSROOT}/usr/share/pkgconfig"

  if command -v pkg-config >/dev/null 2>&1; then
    pkg-config --exists fontconfig freetype2 ||
      shreeos_die "Target Fontconfig/FreeType pkg-config metadata is missing from ${SHREEOS_SYSROOT}."
  fi
}

configure_upstream_makefile() {
  local config_mk="$1"

  # Keep upstream's component-specific linker flags and feature defines while
  # redirecting all target paths and the compiler to the ShreeOS sysroot.
  sed -i \
    -e 's#^PREFIX = .*#PREFIX = /usr#' \
    -e "s#^X11INC = .*#X11INC = ${SHREEOS_SYSROOT}/usr/include#" \
    -e "s#^X11LIB = .*#X11LIB = ${SHREEOS_SYSROOT}/usr/lib#" \
    -e "s#^FREETYPEINC = .*#FREETYPEINC = ${SHREEOS_SYSROOT}/usr/include/freetype2#" \
    -e "s#^CC = .*#CC = ${CC}#" \
    "$config_mk"
}

apply_component_patches() {
  local name="$1"
  local patch_file
  local found=false

  for patch_file in "$SCRIPT_DIR"/patches/"${name}"-*.patch; do
    [ -f "$patch_file" ] || continue
    found=true
    patch --batch --forward -p1 < "$patch_file"
  done

  if [ "$found" = true ]; then
    lumen_ok "Applied ShreeOS ${name} compatibility patches"
  fi
}

build_suckless() {
  local name="$1"
  local url="$2"
  local sha="$3"
  local archive
  archive="${BUILDDIR}/$(basename "$url")"
  local source_dir="${BUILDDIR}/${name}"
  local distro_config="${DESKTOP_DIR}/configs/${name}-config.h"

  lumen_step "Building ${name}"
  lumen_fetch "$url" "$archive" "$sha"

  # Always use a pristine source tree.  This makes repeat builds deterministic
  # and prevents an already-applied patch from breaking the next invocation.
  rm -rf "$source_dir"
  tar -xzf "$archive" -C "$BUILDDIR"
  mv "${BUILDDIR}/${name}-"* "$source_dir"

  cd "$source_dir"
  apply_component_patches "$name"

  if [ ! -f "$distro_config" ]; then
    shreeos_die "Missing ShreeOS config for ${name}: ${distro_config}"
  fi
  cp "$distro_config" config.h
  configure_upstream_makefile config.mk

  make clean
  make -j"${SHREEOS_MAKE_JOBS}"
  make DESTDIR="${SHREEOS_STAGE_ROOT}" install

  lumen_ok "${name} built with ShreeOS desktop configuration"
}

verify_desktop_sysroot

for comp in "${COMPONENTS[@]}"; do
  case "$comp" in
    dwm)   build_suckless "dwm"   "$DWM_URL"   "$DWM_SHA256" ;;
    st)    build_suckless "st"    "$ST_URL"    "$ST_SHA256" ;;
    dmenu) build_suckless "dmenu" "$DMENU_URL" "$DMENU_SHA256" ;;
    *)     shreeos_die "Unknown desktop component: ${comp}" ;;
  esac
done

lumen_ok "Desktop WM components built"
