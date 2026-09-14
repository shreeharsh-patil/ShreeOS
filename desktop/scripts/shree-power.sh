#!/usr/bin/env bash
# desktop/scripts/shree-power.sh — ShreeOS Power & Battery Management
set -euo pipefail

get_status() {
  local battery=""
  for candidate in /sys/class/power_supply/BAT*; do
    if [ -d "$candidate" ]; then
      battery="$candidate"
      break
    fi
  done

  if [ -n "$battery" ]; then
    local cap stat
    cap=$(cat "$battery/capacity" 2>/dev/null || echo "")
    stat=$(cat "$battery/status" 2>/dev/null || echo "Unknown")
    if [ -n "$cap" ]; then
      echo "${cap}% (${stat})"
      return
    fi
  fi
  echo "AC Power (No Battery Detected)"
}

suspend_system() {
  shree-notify "Power" "Requesting system sleep..." --app="Power"

  if [ -w /sys/power/state ]; then
    if printf '%s\n' mem > /sys/power/state 2>/dev/null; then
      return 0
    fi
  elif command -v systemctl >/dev/null 2>&1; then
    if systemctl suspend >/dev/null 2>&1; then
      return 0
    fi
  fi

  shree-notify "Power Alert" "System suspend request failed or is unsupported" --app="Power" --urgent
  return 1
}

interactive_menu() {
  local status choice
  status=$(get_status)
  local options="Power Status: ${status}\nDisplay Sleep (Turn off screen now)\nSystem Suspend (Sleep)\nReboot System Cleanly\nPower Off Computer"
  choice=$(printf "%b\n" "$options" | dmenu -p "Power Management" -l 5 -c || true)
  [ -z "$choice" ] && exit 0

  case "$choice" in
    "Display Sleep"*)
      if command -v xset >/dev/null 2>&1; then
        xset dpms force off || shree-notify "Power Alert" "Unable to turn off the display" --app="Power" --urgent
      fi
      ;;
    "System Suspend"*) suspend_system ;;
    "Reboot"*) initctl reboot ;;
    "Power Off"*) initctl poweroff ;;
  esac
}

case "${1:-status}" in
  status) get_status ;;
  suspend|sleep) suspend_system ;;
  menu|*) interactive_menu ;;
esac
