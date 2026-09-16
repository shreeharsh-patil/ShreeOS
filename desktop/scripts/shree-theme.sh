#!/usr/bin/env bash
# desktop/scripts/shree-theme.sh — ShreeOS Dynamic Appearance Manager
#
# Manages system theme switching (Light / Dark / Auto Day-Night 07:00-19:00), updates Xresources,
# wallpaper rendering, and notifies running applications.

set -euo pipefail

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
  local mode="$1"
  if [ "$mode" = "toggle" ]; then
    local cur
    cur=$(get_current_theme)
    if [ "$cur" = "dark" ]; then mode="light"; else mode="dark"; fi
  elif [ "$mode" = "auto" ]; then
    local hour
    hour=$(date +%H)
    if [ "$hour" -ge 7 ] && [ "$hour" -lt 19 ]; then
      mode="light"
    else
      mode="dark"
    fi
  fi

  echo "THEME=${mode}" > "$THEME_FILE"

  # Update X11 root properties
  if command -v xprop >/dev/null 2>&1; then
    xprop -root -format _SHREEOS_THEME 8s -set _SHREEOS_THEME "$mode" 2>/dev/null || true
  fi

  # Notify user if notify helper is available
  if command -v shree-notify >/dev/null 2>&1; then
    shree-notify "Appearance Changed" "Switched to ${mode^} appearance" --app="Settings"
  fi

  echo "ShreeOS theme set to: ${mode}"
}

case "${1:-status}" in
  dark|light|auto|toggle)
    set_theme "$1"
    ;;
  get|status)
    get_current_theme
    ;;
  *)
    echo "Usage: shree-theme [dark|light|auto|toggle|get]"
    exit 1
    ;;
esac
