#!/usr/bin/env bash
# Build and assemble the complete ShreeOS desktop environment.
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DESKTOP_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
SHREEOS_ROOT_DIR="$(cd "$DESKTOP_DIR/.." && pwd)"

source "$SHREEOS_ROOT_DIR/build.conf"
source "$SHREEOS_ROOT_DIR/scripts/common.sh"

BUILD_START=$(date +%s)
ALLOW_DEFERRED_GRAPHICS="${ALLOW_DEFERRED_GRAPHICS:-0}"
STAGE_ROOT="${SHREEOS_STAGE_ROOT:-${LUMEN_STAGE_ROOT}}"
ACTIVE_PROFILE="${PROFILE:-desktop}"
DESKTOP_NATIVE_STATUS="ready"

case "$ACTIVE_PROFILE" in
  desktop|security) ;;
  *) shreeos_die "Desktop assembly requires PROFILE=desktop or PROFILE=security" ;;
esac

shreeos_step "Building and assembling ShreeOS ${ACTIVE_PROFILE} desktop environment"

# 1. Build the actual target graphics stack before compiling any desktop app.
if ! bash "$DESKTOP_DIR/graphics/build-all.sh"; then
  DESKTOP_NATIVE_STATUS="deferred"
  if [ "$ALLOW_DEFERRED_GRAPHICS" != "1" ]; then
    shreeos_die "Native target graphics stack failed to build"
  fi
  shreeos_warn "Native graphics build failed; continuing only because ALLOW_DEFERRED_GRAPHICS=1"
fi

if [ "$DESKTOP_NATIVE_STATUS" = "ready" ]; then
  bash "$SHREEOS_ROOT_DIR/scripts/graphics-readiness.sh" --strict
else
  bash "$SHREEOS_ROOT_DIR/scripts/graphics-readiness.sh" || true
fi

# 2. Build window manager and terminal/launcher tools against the target sysroot.
if [ "$DESKTOP_NATIVE_STATUS" = "ready" ]; then
  if ! bash "$SCRIPT_DIR/build-wm.sh"; then
    DESKTOP_NATIVE_STATUS="deferred"
    if [ "$ALLOW_DEFERRED_GRAPHICS" != "1" ]; then
      shreeos_die "Native dwm/st/dmenu build failed"
    fi
    shreeos_warn "Native WM build failed; continuing only for explicit development testing"
  fi
fi

# 3. Build the persistent dock when the target X11 SDK is available.
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
    if [ "$ALLOW_DEFERRED_GRAPHICS" != "1" ]; then
      shreeos_die "Native dock build failed"
    fi
  fi
fi

# 4. Install X11 and desktop configuration.
mkdir -p \
  "${STAGE_ROOT}/etc/X11/xinit" \
  "${STAGE_ROOT}/usr/bin" \
  "${STAGE_ROOT}/usr/share/icons/shreeos" \
  "${STAGE_ROOT}/usr/share/wallpapers"

if [ -f "${DESKTOP_DIR}/configs/Xresources" ]; then
  cp "${DESKTOP_DIR}/configs/Xresources" "${STAGE_ROOT}/etc/X11/Xresources"
fi
if [ -f "${DESKTOP_DIR}/configs/picom.conf" ]; then
  cp "${DESKTOP_DIR}/configs/picom.conf" "${STAGE_ROOT}/etc/X11/picom.conf"
fi
if [ -f "${DESKTOP_DIR}/configs/xorg.conf" ]; then
  cp "${DESKTOP_DIR}/configs/xorg.conf" "${STAGE_ROOT}/etc/X11/xorg.conf"
fi
if [ -f "${DESKTOP_DIR}/configs/xinitrc.template" ]; then
  cp "${DESKTOP_DIR}/configs/xinitrc.template" "${STAGE_ROOT}/etc/X11/xinit/xinitrc"
  cp "${DESKTOP_DIR}/configs/xinitrc.template" "${STAGE_ROOT}/etc/X11/xinitrc"
  chmod 755 "${STAGE_ROOT}/etc/X11/xinit/xinitrc" "${STAGE_ROOT}/etc/X11/xinitrc"
fi

# 5. Install desktop scripts and extensionless command aliases.
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

# 6. Install ShreeOS desktop applications.
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

# 7. Install system administration and recovery tools.
for tool in \
  "${SHREEOS_ROOT_DIR}/scripts/shreectl" \
  "${SHREEOS_ROOT_DIR}/scripts/shree-doctor" \
  "${SHREEOS_ROOT_DIR}/scripts/shreeinfo"; do
  if [ -f "$tool" ]; then
    cp "$tool" "${STAGE_ROOT}/usr/bin/"
    chmod 755 "${STAGE_ROOT}/usr/bin/$(basename "$tool")"
  fi
done
if [ -f "${SHREEOS_ROOT_DIR}/installer/scripts/shree-recovery.sh" ]; then
  cp "${SHREEOS_ROOT_DIR}/installer/scripts/shree-recovery.sh" "${STAGE_ROOT}/usr/bin/shree-recovery"
  chmod 755 "${STAGE_ROOT}/usr/bin/shree-recovery"
fi

# 8. Security workstation additions. Keep the standard desktop clean when the
# same staging tree is reused after a security build.
mkdir -p "${STAGE_ROOT}/etc/shreeos"
if [ "$ACTIVE_PROFILE" = "security" ]; then
  for tool in shree-audit shree-netdiag; do
    src="${SHREEOS_ROOT_DIR}/security/scripts/${tool}"
    [ -s "$src" ] || shreeos_die "Missing security edition tool: ${src}"
    cp "$src" "${STAGE_ROOT}/usr/bin/${tool}"
    chmod 755 "${STAGE_ROOT}/usr/bin/${tool}"
  done
  printf 'security\n' > "${STAGE_ROOT}/etc/shreeos/security-edition"
  chmod 0644 "${STAGE_ROOT}/etc/shreeos/security-edition"
  shreeos_ok "Installed ShreeOS security workstation diagnostics"
else
  rm -f \
    "${STAGE_ROOT}/usr/bin/shree-audit" \
    "${STAGE_ROOT}/usr/bin/shree-netdiag" \
    "${STAGE_ROOT}/etc/shreeos/security-edition"
fi

# 9. Install branding and design tokens.
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
if [ -f "${SHREEOS_ROOT_DIR}/branding/theme/tokens.conf" ]; then
  cp "${SHREEOS_ROOT_DIR}/branding/theme/tokens.conf" "${STAGE_ROOT}/etc/shreeos/tokens.conf"
fi
if [ -f "${SHREEOS_ROOT_DIR}/branding/theme/tokens.css" ]; then
  cp "${SHREEOS_ROOT_DIR}/branding/theme/tokens.css" "${STAGE_ROOT}/etc/shreeos/tokens.css"
fi

printf '%s\n' "$DESKTOP_NATIVE_STATUS" > "${STAGE_ROOT}/etc/shreeos/desktop-native.status"
chmod 0644 "${STAGE_ROOT}/etc/shreeos/desktop-native.status"

if [ "$DESKTOP_NATIVE_STATUS" = "ready" ]; then
  PROFILE="$ACTIVE_PROFILE" bash "$SHREEOS_ROOT_DIR/scripts/graphics-readiness.sh" --strict
fi

BUILD_END=$(date +%s)
echo ""
echo "============================================"
if [ "$DESKTOP_NATIVE_STATUS" = "ready" ]; then
  shreeos_ok "ShreeOS ${ACTIVE_PROFILE} desktop build & integration COMPLETE"
else
  shreeos_warn "Desktop assets staged; native graphical build is DEFERRED"
fi
echo "============================================"
echo "  Duration:      $((BUILD_END - BUILD_START))s"
echo "  Profile:       ${ACTIVE_PROFILE}"
echo "  Native status: ${DESKTOP_NATIVE_STATUS}"
echo "  Components:    Xorg, software Mesa, dwm, st, dmenu, dock, launcher, settings"
echo "  Install:       ${STAGE_ROOT}"
echo "============================================"
echo ""
echo "To launch desktop: startx"
echo ""

if [ "$DESKTOP_NATIVE_STATUS" != "ready" ] && [ "$ALLOW_DEFERRED_GRAPHICS" != "1" ]; then
  shreeos_die "Desktop build is incomplete"
fi
