#!/usr/bin/env bash
# desktop/scripts/shree-audio.sh — ShreeOS Sound & Audio Controller
#
# Interacts truthfully with ALSA hardware mixer.

set -euo pipefail

has_alsa() {
  if [ -d /proc/asound ] && [ -n "$(ls -A /proc/asound 2>/dev/null)" ] && command -v amixer >/dev/null 2>&1; then
    return 0
  fi
  return 1
}

get_volume() {
  if has_alsa; then
    local vol
    vol=$(amixer sget Master 2>/dev/null | grep -oP '\[\K[0-9]+(?=%\])' | head -n1 || echo "")
    if [ -n "$vol" ]; then
      echo "${vol}%"
      return
    fi
  fi
  echo "No Audio Device"
}

set_volume() {
  local val="$1"
  if ! has_alsa; then
    shree-notify "Audio" "No ALSA audio device detected" --app="Sound"
    return
  fi

  amixer sset Master "${val}%" >/dev/null 2>&1 || true
  shree-notify "Volume" "Master volume set to ${val}%" --app="Sound"
}

interactive_menu() {
  local status
  status=$(get_volume)
  if [ "$status" = "No Audio Device" ]; then
    shree-notify "Sound" "No ALSA sound card detected on this machine" --app="Sound"
    return
  fi

  local presets="Mute (0%)\n25% — Low\n50% — Medium\n75% — High\n100% — Maximum\nOpen ALSA Mixer (alsamixer)"
  local choice
  choice=$(echo -e "$presets" | dmenu -p "Volume Control (Current: ${status})" -l 6 -c)
  [ -z "$choice" ] && exit 0

  case "$choice" in
    "Mute"*) set_volume 0 ;;
    "25%"*)  set_volume 25 ;;
    "50%"*)  set_volume 50 ;;
    "75%"*)  set_volume 75 ;;
    "100%"*) set_volume 100 ;;
    "Open ALSA"*) st -e alsamixer & ;;
  esac
}

case "${1:-status}" in
  status) get_volume ;;
  set)    set_volume "${2:-80}" ;;
  up)
    if has_alsa; then amixer sset Master 5%+ >/dev/null 2>&1 || true; fi
    ;;
  down)
    if has_alsa; then amixer sset Master 5%- >/dev/null 2>&1 || true; fi
    ;;
  mute)
    if has_alsa; then amixer sset Master toggle >/dev/null 2>&1 || true; fi
    ;;
  menu|*) interactive_menu ;;
esac
