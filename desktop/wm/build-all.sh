#!/usr/bin/env bash
# desktop/wm/build-all.sh — Build and install all ShreeOS desktop components
#
# Orchestrates building dwm, st, dmenu, installing configs, launcher, apps, and branding.
#
# Usage:
#   bash desktop/wm/build-all.sh
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DESKTOP_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
SHREEOS_ROOT_DIR="$(cd "$DESKTOP_DIR/../.." && pwd)"

source "$SHREEOS_ROOT_DIR/build.conf" 2>/dev/null || true
source "$SHREEOS_ROOT_DIR/scripts/common.sh" 2>/dev/null || {
  shreeos_step() { echo "==> $1"; }
  shreeos_ok() { echo "  [OK] $1"; }
  shreeos_warn() { echo "  [WARN] $1"; }
  shreeos_die() { echo "  [ERROR] $1" >&2; exit 1; }
  lumen_ok() { shreeos_ok "$@"; }
  lumen_step() { shreeos_step "$@"; }
}

BUILD_START=$(date +%s)

shreeos_step "Building and assembling ShreeOS desktop environment"

STAGE_ROOT="${SHREEOS_STAGE_ROOT:-${LUMEN_STAGE_ROOT}}"

# 1. Build window manager and tools
if [ -f "$SCRIPT_DIR/build-wm.sh" ]; then
  bash "$SCRIPT_DIR/build-wm.sh" || shreeos_warn "build-wm.sh skipped or partial"
fi

# 2. Install X11 and desktop configs
mkdir -p "${STAGE_ROOT}/etc/X11"
mkdir -p "${STAGE_ROOT}/usr/bin"
mkdir -p "${STAGE_ROOT}/usr/share/icons/shreeos"
mkdir -p "${STAGE_ROOT}/usr/share/wallpapers"

if [ -f "${DESKTOP_DIR}/configs/Xresources" ]; then
  cp "${DESKTOP_DIR}/configs/Xresources" "${STAGE_ROOT}/etc/X11/Xresources"
fi

if [ -f "${DESKTOP_DIR}/configs/picom.conf" ]; then
  cp "${DESKTOP_DIR}/configs/picom.conf" "${STAGE_ROOT}/etc/X11/picom.conf"
fi

if [ -f "${DESKTOP_DIR}/configs/xinitrc.template" ]; then
  cp "${DESKTOP_DIR}/configs/xinitrc.template" "${STAGE_ROOT}/etc/X11/xinitrc"
  chmod 755 "${STAGE_ROOT}/etc/X11/xinitrc"
fi

# 3. Install desktop scripts and create command symlinks without .sh
for script in "${DESKTOP_DIR}/scripts/"*.sh; do
  [ -f "$script" ] || continue
  base=$(basename "$script")
  cp "$script" "${STAGE_ROOT}/usr/bin/${base}"
  chmod 755 "${STAGE_ROOT}/usr/bin/${base}"
  # Install without .sh extension for clean CLI invocation
  clean_name="${base%.sh}"
  if [ "$clean_name" != "$base" ]; then
    cp "$script" "${STAGE_ROOT}/usr/bin/${clean_name}"
    chmod 755 "${STAGE_ROOT}/usr/bin/${clean_name}"
  fi
done

# 4. Install native applications
if [ -d "${DESKTOP_DIR}/apps" ]; then
  for app in "${DESKTOP_DIR}/apps/"*; do
    [ -f "$app" ] || continue
    base=$(basename "$app")
    cp "$app" "${STAGE_ROOT}/usr/bin/${base}"
    chmod 755 "${STAGE_ROOT}/usr/bin/${base}"
    clean_name="${base%.sh}"
    if [ "$clean_name" != "$base" ]; then
      cp "$app" "${STAGE_ROOT}/usr/bin/${clean_name}"
      chmod 755 "${STAGE_ROOT}/usr/bin/${clean_name}"
    fi
  done
fi

# 5. Install system administration tools (shreectl, shree-doctor, shreeinfo)
for tool in "${SHREEOS_ROOT_DIR}/scripts/shreectl" "${SHREEOS_ROOT_DIR}/scripts/shree-doctor" "${SHREEOS_ROOT_DIR}/scripts/shreeinfo"; do
  if [ -f "$tool" ]; then
    cp "$tool" "${STAGE_ROOT}/usr/bin/"
    chmod 755 "${STAGE_ROOT}/usr/bin/$(basename "$tool")"
  fi
done

# 6. Install vector icon family & branding
if [ -d "${SHREEOS_ROOT_DIR}/branding/icons" ]; then
  cp "${SHREEOS_ROOT_DIR}/branding/icons/"*.svg "${STAGE_ROOT}/usr/share/icons/shreeos/" 2>/dev/null || true
fi

if [ -f "${SHREEOS_ROOT_DIR}/branding/logo/shreeos-logo.svg" ]; then
  cp "${SHREEOS_ROOT_DIR}/branding/logo/shreeos-logo.svg" "${STAGE_ROOT}/usr/share/icons/shreeos/logo.svg"
fi

if [ -f "${SHREEOS_ROOT_DIR}/branding/wallpapers/shreeos-wallpaper.svg" ]; then
  cp "${SHREEOS_ROOT_DIR}/branding/wallpapers/shreeos-wallpaper.svg" \
     "${STAGE_ROOT}/usr/share/wallpapers/shreeos-wallpaper.svg"
fi

BUILD_END=$(date +%s)

echo ""
echo "============================================"
shreeos_ok "ShreeOS Desktop build & integration COMPLETE"
echo "============================================"
echo "  Duration: $((BUILD_END - BUILD_START))s"
echo "  Components: dwm, st, dmenu, picom, shree-launcher, shree-settings, shreectl"
echo "  Install:    ${STAGE_ROOT}"
echo "============================================"
echo ""
echo "To launch desktop: startx"
echo ""
