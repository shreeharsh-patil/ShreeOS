#!/usr/bin/env bash
# desktop/scripts/shree-audio.sh — ShreeOS Sound & Audio Controller
#
# Manages master volume, mute, output selection, and notifications.

set -euo pipefail

CONFIG_DIR="${HOME}/.config/shreeos"
VOL_FILE="${CONFIG_DIR}/volume.state"
mkdir -p "$CONFIG_DIR"

if [ ! -f "$VOL_FILE" ]; then
  echo "80" > "$VOL_FILE"
fi

get_volume() {
  if command -v amixer >/dev/null 2>&1; then
    amixer sget Master 2>/dev/null | grep -oP '\[\K[0-9]+(?=%\])' | head -n1 | sed 's/$/%/' || cat "$VOL_FILE" | sed 's/$/%/'
  else
    cat "$VOL_FILE" | sed 's/$/%/'
  fi
}

set_volume() {
  local val="$1"
  echo "$val" > "$VOL_FILE"
  if command -v amixer >/dev/null 2>&1; then
    amixer sset Master "${val}%" >/dev/null 2>&1 || true
  fi
  if command -v shree-notify >/dev/null 2>&1; then
    shree-notify "Volume" "Volume set to ${val}%" --app="Sound"
  fi
}

interactive_menu() {
  PRESETS="Mute (0%)\n25% — Low\n50% — Medium\n75% — High\n100% — Maximum\nOpen Sound Mixer"
  CHOICE=$(echo -e "$PRESETS" | dmenu -p "Volume Control" -l 6 -c)
  [ -z "$CHOICE" ] && exit 0

  case "$CHOICE" in
    "Mute"*) set_volume 0 ;;
    "25%"*)  set_volume 25 ;;
    "50%"*)  set_volume 50 ;;
    "75%"*)  set_volume 75 ;;
    "100%"*) set_volume 100 ;;
    "Open Sound Mixer"*)
      st -e alsamixer &
      ;;
  esac
}

case "${1:-status}" in
  status)
    get_volume
    ;;
  set)
    set_volume "${2:-80}"
    ;;
  up)
    CUR=$(cat "$VOL_FILE" 2>/dev/null || echo 80)
    NEW=$((CUR + 5))
    [ "$NEW" -gt 100 ] && NEW=100
    set_volume "$NEW"
    ;;
  down)
    CUR=$(cat "$VOL_FILE" 2>/dev/null || echo 80)
    NEW=$((CUR - 5))
    [ "$NEW" -lt 0 ] && NEW=0
    set_volume "$NEW"
    ;;
  mute)
    set_volume 0
    ;;
  menu)
    interactive_menu
    ;;
  *)
    echo "Usage: shree-audio.sh [status|set N|up|down|mute|menu]"
    exit 1
    ;;
esac
