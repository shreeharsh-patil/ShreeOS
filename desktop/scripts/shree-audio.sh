#!/usr/bin/env bash
# desktop/scripts/shree-audio.sh — ShreeOS Sound & Audio Controller
set -euo pipefail

has_alsa() {
  [ -d /proc/asound ] &&
    [ -n "$(ls -A /proc/asound 2>/dev/null)" ] &&
    command -v amixer >/dev/null 2>&1
}

get_volume() {
  if has_alsa; then
    local vol
    vol=$(amixer sget Master 2>/dev/null | sed -n 's/.*\[\([0-9][0-9]*\)%\].*/\1/p' | head -n1 || true)
    if [ -n "$vol" ]; then
      echo "${vol}%"
      return
    fi
  fi
  echo "No Audio Device"
}

run_mixer() {
  if ! has_alsa; then
    shree-notify "Audio" "No ALSA audio device detected" --app="Sound"
    return 1
  fi
  if ! amixer "$@" >/dev/null 2>&1; then
    shree-notify "Audio" "The mixer operation failed" --app="Sound" --urgent
    return 1
  fi
}

set_volume() {
  local val="$1"
  if ! [[ "$val" =~ ^([0-9]|[1-9][0-9]|100)$ ]]; then
    echo "shree-audio: volume must be an integer from 0 to 100" >&2
    return 2
  fi
  run_mixer sset Master "${val}%"
  shree-notify "Volume" "Master volume set to ${val}%" --app="Sound"
}

interactive_menu() {
  local status choice
  status=$(get_volume)
  if [ "$status" = "No Audio Device" ]; then
    shree-notify "Sound" "No ALSA sound card detected on this machine" --app="Sound"
    return
  fi

  local presets="Mute (0%)\n25% — Low\n50% — Medium\n75% — High\n100% — Maximum\nOpen ALSA Mixer (alsamixer)"
  choice=$(printf "%b\n" "$presets" | dmenu -p "Volume Control (Current: ${status})" -l 6 -c || true)
  [ -z "$choice" ] && exit 0

  case "$choice" in
    "Mute"*) set_volume 0 ;;
    "25%"*) set_volume 25 ;;
    "50%"*) set_volume 50 ;;
    "75%"*) set_volume 75 ;;
    "100%"*) set_volume 100 ;;
    "Open ALSA"*)
      if command -v st >/dev/null 2>&1 && command -v alsamixer >/dev/null 2>&1; then
        st -e alsamixer &
      else
        shree-notify "Audio" "alsamixer or terminal is unavailable" --app="Sound" --urgent
      fi
      ;;
  esac
}

case "${1:-status}" in
  status) get_volume ;;
  set) set_volume "${2:-80}" ;;
  up) run_mixer sset Master 5%+ ;;
  down) run_mixer sset Master 5%- ;;
  mute) run_mixer sset Master toggle ;;
  menu|*) interactive_menu ;;
esac
