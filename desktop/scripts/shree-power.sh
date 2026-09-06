#!/usr/bin/env bash
# desktop/scripts/shree-power.sh — ShreeOS Power & Battery Management
#
# Reads sysfs battery data truthfully and executes real kernel power operations.

set -euo pipefail

get_status() {
  if [ -d /sys/class/power_supply/BAT0 ]; then
    local cap
    cap=$(cat /sys/class/power_supply/BAT0/capacity 2>/dev/null || echo "")
    local stat
    stat=$(cat /sys/class/power_supply/BAT0/status 2>/dev/null || echo "AC")
    if [ -n "$cap" ]; then
      echo "${cap}% (${stat})"
      return
    fi
  fi
  echo "AC Power (No Battery Detected)"
}

suspend_system() {
  if [ -w /sys/power/state ]; then
    shree-notify "Power" "Entering system sleep state..." --app="Power"
    echo mem > /sys/power/state 2>/dev/null || true
  elif command -v systemctl >/dev/null 2>&1; then
    systemctl suspend 2>/dev/null || true
  else
    shree-notify "Power Alert" "System suspend not supported on this kernel (no /sys/power/state)" --app="Power" --urgent
  fi
}

interactive_menu() {
  local status
  status=$(get_status)
  local options="Power Status: ${status}\nDisplay Sleep (Turn off screen now)\nSystem Suspend (Sleep)\nReboot System Cleanly\nPower Off Computer"
  local choice
  choice=$(echo -e "$options" | dmenu -p "Power Management" -l 5 -c || true)
  [ -z "$choice" ] && exit 0

  case "$choice" in
    "Display Sleep"*)
      if command -v xset >/dev/null 2>&1; then xset dpms force off; fi
      ;;
    "System Suspend"*)
      suspend_system
      ;;
    "Reboot"*)
      initctl reboot
      ;;
    "Power Off"*)
      initctl poweroff
      ;;
  esac
}

case "${1:-status}" in
  status) get_status ;;
  suspend|sleep) suspend_system ;;
  menu|*) interactive_menu ;;
esac
