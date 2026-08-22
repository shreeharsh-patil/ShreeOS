#!/usr/bin/env bash
# desktop/scripts/shree-power.sh — ShreeOS Power & Battery Management
#
# Reads sysfs battery data, manages display sleep, and provides power actions.

set -euo pipefail

get_status() {
  if [ -d /sys/class/power_supply/BAT0 ]; then
    cap=$(cat /sys/class/power_supply/BAT0/capacity 2>/dev/null || echo "100")
    stat=$(cat /sys/class/power_supply/BAT0/status 2>/dev/null || echo "AC")
    echo "${cap}% (${stat})"
  else
    echo "100% (AC Line Connected)"
  fi
}

interactive_menu() {
  STATUS=$(get_status)
  OPTIONS="Battery Status: ${STATUS}\nDisplay Sleep (Turn off screen now)\nSleep / Suspend System\nReboot Computer\nPower Off Computer"
  CHOICE=$(echo -e "$OPTIONS" | dmenu -p "Power & Battery" -l 5 -c)
  [ -z "$CHOICE" ] && exit 0

  case "$CHOICE" in
    "Display Sleep"*)
      if command -v xset >/dev/null 2>&1; then xset dpms force off; fi
      ;;
    "Sleep"*)
      if command -v slock >/dev/null 2>&1; then slock & fi
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
  status)
    get_status
    ;;
  menu)
    interactive_menu
    ;;
  *)
    echo "Usage: shree-power.sh [status|menu]"
    exit 1
    ;;
esac
