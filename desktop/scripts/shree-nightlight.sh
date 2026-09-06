#!/usr/bin/env bash
# desktop/scripts/shree-nightlight.sh — ShreeOS Night Light (Color Temperature Controller)
#
# Adjusts X11 gamma temperature to reduce blue light during evening hours.

set -euo pipefail

CONFIG_DIR="${HOME}/.config/shreeos"
STATE_FILE="${CONFIG_DIR}/nightlight.state"
mkdir -p "$CONFIG_DIR"

if [ ! -f "$STATE_FILE" ]; then
  echo "off" > "$STATE_FILE"
fi

get_status() {
  cat "$STATE_FILE" 2>/dev/null || echo "off"
}

set_nightlight() {
  local state="$1"
  if [ "$state" = "on" ]; then
    echo "on" > "$STATE_FILE"
    if command -v sct >/dev/null 2>&1; then
      sct 4200
    elif command -v xrandr >/dev/null 2>&1; then
      xrandr --gamma 1.0:0.85:0.7 >/dev/null 2>&1 || true
    fi
    if command -v shree-notify >/dev/null 2>&1; then
      shree-notify "Night Light" "Enabled (4200K Warm Temperature)" --app="Display"
    fi
  else
    echo "off" > "$STATE_FILE"
    if command -v sct >/dev/null 2>&1; then
      sct 6500
    elif command -v xrandr >/dev/null 2>&1; then
      xrandr --gamma 1.0:1.0:1.0 >/dev/null 2>&1 || true
    fi
    if command -v shree-notify >/dev/null 2>&1; then
      shree-notify "Night Light" "Disabled (6500K Standard)" --app="Display"
    fi
  fi
}

toggle_nightlight() {
  CUR=$(get_status)
  if [ "$CUR" = "on" ]; then
    set_nightlight "off"
  else
    set_nightlight "on"
  fi
}

case "${1:-status}" in
  status)
    get_status
    ;;
  on)
    set_nightlight "on"
    ;;
  off)
    set_nightlight "off"
    ;;
  toggle)
    toggle_nightlight
    ;;
  *)
    echo "Usage: shree-nightlight.sh [status|on|off|toggle]"
    exit 1
    ;;
esac
