#!/usr/bin/env bash
# desktop/scripts/shree-screenshot.sh — ShreeOS Screenshot & Screen Capture Tool
#
# Shortcuts:
#   PrintScreen       -> Fullscreen capture
#   Super + Shift + 4 -> Interactive region selection
#   Super + Shift + 3 -> Active window capture

set -euo pipefail

SHOT_DIR="${HOME}/Pictures/Screenshots"
mkdir -p "$SHOT_DIR"

TIMESTAMP=$(date +"%Y-%m-%d_%H-%M-%S")
OUT_FILE="${SHOT_DIR}/Screenshot_${TIMESTAMP}.png"
MODE="${1:-interactive}"

case "$MODE" in
  full)
    if command -v maim >/dev/null 2>&1; then
      maim "$OUT_FILE"
    elif command -v scrot >/dev/null 2>&1; then
      scrot "$OUT_FILE"
    elif command -v import >/dev/null 2>&1; then
      import -window root "$OUT_FILE"
    fi
    ;;
  select|region)
    if command -v maim >/dev/null 2>&1; then
      maim -s "$OUT_FILE"
    elif command -v scrot >/dev/null 2>&1; then
      scrot -s "$OUT_FILE"
    elif command -v import >/dev/null 2>&1; then
      import "$OUT_FILE"
    fi
    ;;
  window)
    if command -v maim >/dev/null 2>&1; then
      maim -i "$(xdotool getactivewindow 2>/dev/null || echo root)" "$OUT_FILE"
    elif command -v scrot >/dev/null 2>&1; then
      scrot -u "$OUT_FILE"
    fi
    ;;
  interactive|*)
    CHOICE=$(printf "Fullscreen Capture\nSelected Region (Click and Drag)\nActive Window Only" | dmenu -p "Take Screenshot" -l 3 -c)
    case "$CHOICE" in
      "Fullscreen"*) "$0" full ;;
      "Selected Region"*) "$0" select ;;
      "Active Window"*) "$0" window ;;
      *) exit 0 ;;
    esac
    exit 0
    ;;
esac

if [ -f "$OUT_FILE" ]; then
  if command -v xclip >/dev/null 2>&1; then
    xclip -selection clipboard -t image/png -i "$OUT_FILE" 2>/dev/null || true
  fi
  shree-notify "Screenshot Captured" "Saved to $(basename "$OUT_FILE") (Copied to clipboard)" --app="System"
fi
