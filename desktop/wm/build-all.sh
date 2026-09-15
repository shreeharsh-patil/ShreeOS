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
SHREEOS_ROOT_DIR="$(cd "$DESKTOP_DIR/.." && pwd)"

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
ALLOW_DEFERRED_GRAPHICS="${ALLOW_DEFERRED_GRAPHICS:-0}"

shreeos_step "Building and assembling ShreeOS desktop environment"

STAGE_ROOT="${SHREEOS_STAGE_ROOT:-${LUMEN_STAGE_ROOT}}"

if [ "$ALLOW_DEFERRED_GRAPHICS" != "1" ]; then
  bash "$SHREEOS_ROOT_DIR/scripts/graphics-readiness.sh" --strict
else
  bash "$SHREEOS_ROOT_DIR/scripts/graphics-readiness.sh" || true
fi

# 1. Build window manager and tools.
# The graphical target stack is still being brought into the source build, so
# report a deferred native build explicitly instead of pretending it succeeded.
DESKTOP_NATIVE_STATUS="ready"
if [ -f "$SCRIPT_DIR/build-wm.sh" ]; then
  if ! bash "$SCRIPT_DIR/build-wm.sh"; then
    DESKTOP_NATIVE_STATUS="deferred"
    shreeos_warn "Native WM build deferred: target X11/Xft/Xinerama/Fontconfig/FreeType stack is not fully staged"
  fi
fi

# Build the persistent dock when the target X11 SDK is available.
if [ "$DESKTOP_NATIVE_STATUS" = "ready" ] && [ -f "$SCRIPT_DIR/shree-dock.c" ]; then
  DOCK_CC="${SHREEOS_TOOLS}/bin/${SHREEOS_TARGET_TRIPLET}-gcc"
  mkdir -p "${STAGE_ROOT}/usr/bin"
  if "$DOCK_CC" -std=c99 -Os -Wall -Wextra \
      --sysroot="${SHREEOS_SYSROOT}" \
      -I"${SHREEOS_SYSROOT}/usr/include" \
      "$SCRIPT_DIR/shree-dock.c" \
      -L"${SHREEOS_SYSROOT}/usr/lib" -lX11 \
      -o "${STAGE_ROOT}/usr/bin/shree-dock-ui"; then
    chmod 755 "${STAGE_ROOT}/usr/bin/shree-dock-ui"
    shreeos_ok "Built persistent ShreeOS dock"
  else
    DESKTOP_NATIVE_STATUS="deferred"
    rm -f "${STAGE_ROOT}/usr/bin/shree-dock-ui"
    shreeos_warn "Native dock build deferred"
  fi
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

# 3. Install desktop scripts and create extensionless symlinks/copies
for script in "${DESKTOP_DIR}/scripts/"*.sh; do
  [ -f "$script" ] || continue
  base=$(basename "$script")
  cp "$script" "${STAGE_ROOT}/usr/bin/${base}"
  chmod 755 "${STAGE_ROOT}/usr/bin/${base}"
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

# 6. Install recovery tool
if [ -f "${SHREEOS_ROOT_DIR}/installer/scripts/shree-recovery.sh" ]; then
  cp "${SHREEOS_ROOT_DIR}/installer/scripts/shree-recovery.sh" "${STAGE_ROOT}/usr/bin/shree-recovery"
  chmod 755 "${STAGE_ROOT}/usr/bin/shree-recovery"
fi

# 7. Install vector icon family & branding
if [ -d "${SHREEOS_ROOT_DIR}/branding/icons" ]; then
  cp "${SHREEOS_ROOT_DIR}/branding/icons/"*.svg "${STAGE_ROOT}/usr/share/icons/shreeos/" 2>/dev/null || true
fi

if [ -f "${SHREEOS_ROOT_DIR}/branding/logo/shreeos-logo.svg" ]; then
  cp "${SHREEOS_ROOT_DIR}/branding/logo/shreeos-logo.svg" "${STAGE_ROOT}/usr/share/icons/shreeos/logo.svg"
fi

if [ -d "${SHREEOS_ROOT_DIR}/branding/wallpapers" ]; then
  cp "${SHREEOS_ROOT_DIR}/branding/wallpapers/"*.svg "${STAGE_ROOT}/usr/share/wallpapers/" 2>/dev/null || true
  cp "${SHREEOS_ROOT_DIR}/branding/wallpapers/"*.png "${STAGE_ROOT}/usr/share/wallpapers/" 2>/dev/null || true
fi

# 8. Install centralized design tokens
mkdir -p "${STAGE_ROOT}/etc/shreeos"
if [ -f "${SHREEOS_ROOT_DIR}/branding/theme/tokens.conf" ]; then
  cp "${SHREEOS_ROOT_DIR}/branding/theme/tokens.conf" "${STAGE_ROOT}/etc/shreeos/tokens.conf"
fi
if [ -f "${SHREEOS_ROOT_DIR}/branding/theme/tokens.css" ]; then
  cp "${SHREEOS_ROOT_DIR}/branding/theme/tokens.css" "${STAGE_ROOT}/etc/shreeos/tokens.css"
fi
printf '%s\n' "$DESKTOP_NATIVE_STATUS" > "${STAGE_ROOT}/etc/shreeos/desktop-native.status"

BUILD_END=$(date +%s)

echo ""
echo "============================================"
if [ "$DESKTOP_NATIVE_STATUS" = "ready" ]; then
  shreeos_ok "ShreeOS Desktop build & integration COMPLETE"
else
  shreeos_warn "Desktop assets staged; native graphical build is DEFERRED"
fi
echo "============================================"
echo "  Duration:      $((BUILD_END - BUILD_START))s"
echo "  Native status: ${DESKTOP_NATIVE_STATUS}"
echo "  Components:    dwm, st, dmenu, dock, picom, launcher, settings, shreectl"
echo "  Install:       ${STAGE_ROOT}"
echo "============================================"
echo ""
echo "To launch desktop: startx"
echo ""

if [ "$DESKTOP_NATIVE_STATUS" != "ready" ] && [ "$ALLOW_DEFERRED_GRAPHICS" != "1" ]; then
  shreeos_die "Desktop build is incomplete; set ALLOW_DEFERRED_GRAPHICS=1 only for explicit development/headless ISO testing."
fi
