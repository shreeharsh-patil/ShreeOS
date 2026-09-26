#!/usr/bin/env bash
# Validate the target graphical SDK and runtime required by ShreeOS Desktop.
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$REPO_ROOT/build.conf"
source "$REPO_ROOT/scripts/common.sh"

STRICT=false
if [ "${1:-}" = "--strict" ]; then STRICT=true; fi

headers=(
  "usr/include/X11/Xlib.h"
  "usr/include/X11/Xft/Xft.h"
  "usr/include/X11/extensions/Xinerama.h"
  "usr/include/fontconfig/fontconfig.h"
  "usr/include/freetype2/ft2build.h"
  "usr/include/pixman-1/pixman.h"
  "usr/include/xf86drm.h"
  "usr/include/GL/gl.h"
)
libs=(libX11 libXft libXinerama libfontconfig libfreetype libpixman-1 libdrm libGL)
runtime_bins=(
  "usr/bin/Xorg"
  "usr/bin/X"
  "usr/bin/xinit"
  "usr/bin/startx"
  "usr/bin/xauth"
)
runtime_files=(
  "usr/lib/xorg/modules/drivers/fbdev_drv.so"
  "usr/lib/xorg/modules/input/kbd_drv.so"
  "usr/lib/xorg/modules/input/mouse_drv.so"
  "etc/X11/xorg.conf"
  "etc/X11/xinit/xinitrc"
)

missing_count=0
echo "==> Target graphics readiness"

for rel in "${headers[@]}"; do
  if [ -f "$SHREEOS_SYSROOT/$rel" ]; then
    printf "  [OK]      SDK header %s\n" "$rel"
  else
    printf "  [MISSING] SDK header %s\n" "$rel"
    missing_count=$((missing_count + 1))
  fi
done

find_lib() {
  local root="$1" name="$2"
  find "$root/usr/lib" "$root/lib" \
    -maxdepth 4 \( -type f -o -type l \) \
    \( -name "${name}.so" -o -name "${name}.so.*" -o -name "${name}.a" \) \
    -print -quit 2>/dev/null || true
}

for lib in "${libs[@]}"; do
  if [ -n "$(find_lib "$SHREEOS_SYSROOT" "$lib")" ]; then
    printf "  [OK]      SDK library %s\n" "$lib"
  else
    printf "  [MISSING] SDK library %s\n" "$lib"
    missing_count=$((missing_count + 1))
  fi

  if [ -n "$(find_lib "$SHREEOS_STAGE_ROOT" "$lib")" ]; then
    printf "  [OK]      runtime library %s\n" "$lib"
  else
    printf "  [MISSING] runtime library %s\n" "$lib"
    missing_count=$((missing_count + 1))
  fi
done

for rel in "${runtime_bins[@]}"; do
  if [ -x "$SHREEOS_STAGE_ROOT/$rel" ]; then
    printf "  [OK]      runtime executable %s\n" "$rel"
  else
    printf "  [MISSING] runtime executable %s\n" "$rel"
    missing_count=$((missing_count + 1))
  fi
done

for rel in "${runtime_files[@]}"; do
  if [ -s "$SHREEOS_STAGE_ROOT/$rel" ]; then
    printf "  [OK]      runtime file %s\n" "$rel"
  else
    printf "  [MISSING] runtime file %s\n" "$rel"
    missing_count=$((missing_count + 1))
  fi
done

if find "$SHREEOS_STAGE_ROOT/usr/share/fonts" -type f \
  \( -name '*.ttf' -o -name '*.otf' \) -print -quit 2>/dev/null | grep -q .; then
  printf "  [OK]      runtime fonts\n"
else
  printf "  [MISSING] runtime fonts under /usr/share/fonts\n"
  missing_count=$((missing_count + 1))
fi

state_dir="$SHREEOS_BUILD_DIR/.state"
mkdir -p "$state_dir"
if [ "$missing_count" -eq 0 ]; then
  printf 'ready\n' > "$state_dir/graphics.status"
  shreeos_ok "Target graphical SDK and runtime are ready."
  exit 0
fi

printf 'missing:%s\n' "$missing_count" > "$state_dir/graphics.status"
shreeos_warn "Target graphical stack is incomplete ($missing_count required item(s) missing)."
echo "A desktop ISO is not considered ready until its SDK libraries, runtime"
echo "libraries, Xorg server, utilities, drivers, configuration and fonts are present."
if [ "$STRICT" = true ]; then
  shreeos_die "Refusing to certify an incomplete desktop graphics stack."
fi
exit 1
