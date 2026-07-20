#!/usr/bin/env bash
# desktop/wm/build-all.sh — Build all desktop components
#
# Orchestrates building the X11 environment and window manager.
# X11 server is fetched as a prebuilt binary for v1.
#
# Usage:
#   bash desktop/wm/build-all.sh
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DESKTOP_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
LUMEN_ROOT_DIR="$(cd "$DESKTOP_DIR/../.." && pwd)"

source "$LUMEN_ROOT_DIR/build.conf"
source "$LUMEN_ROOT_DIR/scripts/common.sh"

BUILD_START=$(date +%s)

lumen_step "Building desktop environment"

# 1. Build window manager and tools
bash "$SCRIPT_DIR/build-wm.sh"

# 2. Install config files
mkdir -p "${LUMEN_STAGE_ROOT}/etc/X11"
cp -r "${DESKTOP_DIR}/configs/"* "${LUMEN_STAGE_ROOT}/etc/" 2>/dev/null || true

# 3. Install branding
mkdir -p "${LUMEN_STAGE_ROOT}/usr/share/wallpapers"
if [ -f "${LUMEN_ROOT_DIR}/branding/wallpapers/shreeos-wallpaper.png" ]; then
  cp "${LUMEN_ROOT_DIR}/branding/wallpapers/shreeos-wallpaper.png" \
     "${LUMEN_STAGE_ROOT}/usr/share/wallpapers/"
fi

BUILD_END=$(date +%s)

echo ""
echo "============================================"
lumen_ok "Desktop build COMPLETE"
echo "============================================"
echo "  Duration: $((BUILD_END - BUILD_START))s"
echo "  Components: dwm, st, dmenu"
echo "  Install:    ${LUMEN_STAGE_ROOT}"
echo "============================================"
echo ""
echo "Start X11 with: startx"
echo ""
