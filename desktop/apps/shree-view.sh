#!/usr/bin/env bash
# desktop/apps/shree-view.sh — ShreeOS Native Image Viewer
#
# Clean, minimal viewer for photos, wallpapers, and graphics.

set -euo pipefail

IMAGE="${1:-}"

if [ -z "$IMAGE" ]; then
  # Open file picker if none passed
  IMAGE=$(find "${HOME}/Pictures" "${HOME}/Desktop" -type f \( -name "*.png" -o -name "*.jpg" -o -name "*.svg" \) 2>/dev/null | dmenu -p "Select Image to View" -l 8 -c || true)
fi

[ -z "$IMAGE" ] || [ ! -f "$IMAGE" ] && exit 0

if command -v feh >/dev/null 2>&1; then
  feh --scale-down --auto-zoom --geometry 800x600 "$IMAGE" &
elif command -v sxiv >/dev/null 2>&1; then
  sxiv "$IMAGE" &
else
  # Display info
  INFO=$(file "$IMAGE")
  shree-notify "Image Viewer" "File: $(basename "$IMAGE")\n${INFO}" --app="Preview"
fi
