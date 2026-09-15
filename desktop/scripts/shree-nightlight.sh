#!/usr/bin/env bash
# desktop/scripts/shree-nightlight.sh — ShreeOS Night Light
set -euo pipefail

CONFIG_DIR="${HOME}/.config/shreeos"
STATE_FILE="${CONFIG_DIR}/nightlight.state"
mkdir -p "$CONFIG_DIR"
[ -f "$STATE_FILE" ] || printf '%s\n' "off" > "$STATE_FILE"

get_status() {
  cat "$STATE_FILE" 2>/dev/null || echo "off"
}

apply_temperature() {
  local kelvin="$1"
  local gamma="$2"

  if command -v sct >/dev/null 2>&1; then
    if sct "$kelvin" >/dev/null 2>&1; then
      return 0
    fi
  fi
  if command -v xrandr >/dev/null 2>&1; then
    xrandr --gamma "$gamma" >/dev/null 2>&1
    return
  fi
  return 1
}

set_nightlight() {
  local state="$1"
  local kelvin gamma message

  case "$state" in
    on)
      kelvin=4200
      gamma="1.0:0.85:0.7"
      message="Enabled (4200K Warm Temperature)"
      ;;
    off)
      kelvin=6500
      gamma="1.0:1.0:1.0"
      message="Disabled (6500K Standard)"
      ;;
    *)
      echo "shree-nightlight: invalid state '$state'" >&2
      return 1
      ;;
  esac

  if ! apply_temperature "$kelvin" "$gamma"; then
    command -v shree-notify >/dev/null 2>&1 &&
      shree-notify "Night Light" "Unable to change display color temperature" --app="Display" --urgent
    return 1
  fi

  printf '%s\n' "$state" > "$STATE_FILE"
  command -v shree-notify >/dev/null 2>&1 &&
    shree-notify "Night Light" "$message" --app="Display"
}

toggle_nightlight() {
  local cur
  cur=$(get_status)
  if [ "$cur" = "on" ]; then
    set_nightlight "off"
  else
    set_nightlight "on"
  fi
}

case "${1:-status}" in
  status) get_status ;;
  on) set_nightlight "on" ;;
  off) set_nightlight "off" ;;
  toggle) toggle_nightlight ;;
  *)
    echo "Usage: shree-nightlight.sh [status|on|off|toggle]"
    exit 1
    ;;
esac
