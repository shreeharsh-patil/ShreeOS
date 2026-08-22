#!/usr/bin/env bash
# desktop/scripts/shree-dnd.sh — ShreeOS Do Not Disturb Toggle
#
# Suppresses non-critical popups and silences notification banners.

set -euo pipefail

CONFIG_DIR="${HOME}/.config/shreeos"
DND_FILE="${CONFIG_DIR}/dnd.state"
mkdir -p "$CONFIG_DIR"

if [ ! -f "$DND_FILE" ]; then
  echo "off" > "$DND_FILE"
fi

get_status() {
  cat "$DND_FILE" 2>/dev/null || echo "off"
}

set_dnd() {
  local state="$1"
  echo "$state" > "$DND_FILE"
  if [ "$state" = "on" ]; then
    if command -v shree-notify >/dev/null 2>&1; then
      shree-notify "Focus Mode" "Do Not Disturb is now active" --app="System" --urgent
    fi
  else
    if command -v shree-notify >/dev/null 2>&1; then
      shree-notify "Focus Mode" "Do Not Disturb turned off" --app="System"
    fi
  fi
}

toggle_dnd() {
  CUR=$(get_status)
  if [ "$CUR" = "on" ]; then
    set_dnd "off"
  else
    set_dnd "on"
  fi
}

case "${1:-status}" in
  status)
    get_status
    ;;
  on)
    set_dnd "on"
    ;;
  off)
    set_dnd "off"
    ;;
  toggle)
    toggle_dnd
    ;;
  *)
    echo "Usage: shree-dnd.sh [status|on|off|toggle]"
    exit 1
    ;;
esac
