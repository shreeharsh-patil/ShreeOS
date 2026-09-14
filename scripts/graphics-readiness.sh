#!/usr/bin/env bash
# Validate that the target graphical SDK needed by the native ShreeOS desktop exists.
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$REPO_ROOT/build.conf"
source "$REPO_ROOT/scripts/common.sh"

STRICT=false
if [ "${1:-}" = "--strict" ]; then
  STRICT=true
fi

headers=(
  "usr/include/X11/Xlib.h"
  "usr/include/X11/Xft/Xft.h"
  "usr/include/X11/extensions/Xinerama.h"
  "usr/include/fontconfig/fontconfig.h"
  "usr/include/freetype2/ft2build.h"
)

libs=(
  "libX11"
  "libXft"
  "libXinerama"
  "fontconfig"
  "freetype"
)

missing_count=0

echo "==> Target graphics readiness"
for rel in "${headers[@]}"; do
  if [ -f "$SHREEOS_SYSROOT/$rel" ]; then
    printf "  [OK]      %s\n" "$rel"
  else
    printf "  [MISSING] %s\n" "$rel"
    missing_count=$((missing_count + 1))
  fi
done

find_target_lib() {
  local name="$1"
  find "$SHREEOS_SYSROOT/usr/lib" "$SHREEOS_SYSROOT/lib" \
    -maxdepth 2 -type f \( -name "${name}.so" -o -name "${name}.so.*" -o -name "${name}.a" \) \
    -print -quit 2>/dev/null
}

for lib in "${libs[@]}"; do
  if [ -n "$(find_target_lib "$lib")" ]; then
    printf "  [OK]      target library %s\n" "$lib"
  else
    printf "  [MISSING] target library %s\n" "$lib"
    missing_count=$((missing_count + 1))
  fi
done

state_dir="$SHREEOS_BUILD_DIR/.state"
mkdir -p "$state_dir"
if [ "$missing_count" -eq 0 ]; then
  printf 'ready\n' > "$state_dir/graphics.status"
  shreeos_ok "Target graphical SDK is ready."
  exit 0
fi

printf 'missing:%s\n' "$missing_count" > "$state_dir/graphics.status"
shreeos_warn "Target graphical SDK is incomplete ($missing_count required items missing)."
echo "The desktop profile currently declares the graphics stack, but those packages"
echo "are not yet source-built into the ShreeOS target sysroot."
echo
echo "Required next implementation layer includes FreeType, Fontconfig, Xorg protocol"
echo "headers, libXau/libXdmcp/libxcb/libX11, Xft, Xinerama and the Xorg runtime stack."

if [ "$STRICT" = true ]; then
  shreeos_die "Refusing a strict desktop build until the target graphics stage is complete."
fi
