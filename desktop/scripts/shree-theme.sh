#!/bin/sh
# desktop/scripts/shree-theme.sh — ShreeOS Dynamic Appearance Manager
#
# Manages system theme switching (Light / Dark / Auto), updates Xresources,
# wallpaper rendering, and notifies running applications.

CONFIG_DIR="${HOME}/.config/shreeos"
THEME_FILE="${CONFIG_DIR}/theme.conf"
mkdir -p "$CONFIG_DIR"

if [ ! -f "$THEME_FILE" ]; then
  echo "THEME=dark" > "$THEME_FILE"
fi

get_current_theme() {
  grep -oP '^THEME=\K.*' "$THEME_FILE" 2>/dev/null || echo "dark"
}

set_theme() {
  MODE="$1"
  if [ "$MODE" = "toggle" ]; then
    CUR=$(get_current_theme)
    if [ "$CUR" = "dark" ]; then MODE="light"; else MODE="dark"; fi
  elif [ "$MODE" = "auto" ]; then
    HOUR=$(date +%H)
    if [ "$HOUR" -ge 7 ] && [ "$HOUR" -lt 19 ]; then
      MODE="light"
    else
      MODE="dark"
    fi
  fi

  echo "THEME=${MODE}" > "$THEME_FILE"

  # Update X11 root properties
  if command -v xprop >/dev/null 2>&1; then
    xprop -root -format _SHREEOS_THEME 8s -set _SHREEOS_THEME "$MODE" 2>/dev/null || true
  fi

  # Notify user if notify helper is available
  if command -v shree-notify >/dev/null 2>&1; then
    shree-notify "Appearance Changed" "Switched to ${MODE^} appearance" --app="Settings"
  fi

  echo "ShreeOS theme set to: ${MODE}"
}

case "${1:-status}" in
  dark|light|auto|toggle)
    set_theme "$1"
    ;;
  get|status)
    get_current_theme
    ;;
  *)
    echo "Usage: shree-theme.sh [dark|light|auto|toggle|get]"
    exit 1
    ;;
esac
