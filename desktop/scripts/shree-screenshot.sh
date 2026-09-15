#!/usr/bin/env bash
# desktop/scripts/shree-screenshot.sh — ShreeOS Screenshot & Screen Capture Tool
set -euo pipefail

SHOT_DIR="${HOME}/Pictures/Screenshots"
mkdir -p "$SHOT_DIR"

TIMESTAMP=$(date +"%Y-%m-%d_%H-%M-%S")
OUT_FILE="${SHOT_DIR}/Screenshot_${TIMESTAMP}.png"
MODE="${1:-interactive}"

capture_full() {
  if command -v maim >/dev/null 2>&1; then maim "$OUT_FILE"
  elif command -v scrot >/dev/null 2>&1; then scrot "$OUT_FILE"
  elif command -v import >/dev/null 2>&1; then import -window root "$OUT_FILE"
  else return 127
  fi
}

capture_region() {
  if command -v maim >/dev/null 2>&1; then maim -s "$OUT_FILE"
  elif command -v scrot >/dev/null 2>&1; then scrot -s "$OUT_FILE"
  elif command -v import >/dev/null 2>&1; then import "$OUT_FILE"
  else return 127
  fi
}

capture_window() {
  if command -v maim >/dev/null 2>&1; then
    local win=""
    if command -v xdotool >/dev/null 2>&1; then
      win=$(xdotool getactivewindow 2>/dev/null || true)
    fi
    if [ -n "$win" ]; then maim -i "$win" "$OUT_FILE"; else maim "$OUT_FILE"; fi
  elif command -v scrot >/dev/null 2>&1; then
    scrot -u "$OUT_FILE"
  else
    return 127
  fi
}

case "$MODE" in
  full) capture_full ;;
  select|region) capture_region ;;
  window) capture_window ;;
  interactive)
    CHOICE=$(printf "Fullscreen Capture\nSelected Region (Click and Drag)\nActive Window Only" | dmenu -p "Take Screenshot" -l 3 -c || true)
    case "$CHOICE" in
      "Fullscreen"*) "$0" full ;;
      "Selected Region"*) "$0" select ;;
      "Active Window"*) "$0" window ;;
      *) exit 0 ;;
    esac
    exit 0
    ;;
  *)
    echo "Usage: shree-screenshot.sh [full|select|region|window|interactive]" >&2
    exit 2
    ;;
esac

if [ ! -s "$OUT_FILE" ]; then
  rm -f "$OUT_FILE"
  shree-notify "Screenshot Failed" "No screenshot was produced. Install maim, scrot, or ImageMagick." --app="System" --urgent
  exit 1
fi

copied=false
if command -v xclip >/dev/null 2>&1; then
  if xclip -selection clipboard -t image/png -i "$OUT_FILE" 2>/dev/null; then
    copied=true
  fi
fi

if [ "$copied" = true ]; then
  shree-notify "Screenshot Captured" "Saved to $(basename "$OUT_FILE") and copied to clipboard" --app="System"
else
  shree-notify "Screenshot Captured" "Saved to $(basename "$OUT_FILE")" --app="System"
fi
