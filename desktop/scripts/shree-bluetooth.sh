#!/usr/bin/env bash
# desktop/scripts/shree-bluetooth.sh — ShreeOS Bluetooth Hardware Manager
#
# Detects real Bluetooth adapters via rfkill and /sys/class/bluetooth,
# controlling power, scanning, and pairing through bluetoothctl.

set -euo pipefail

has_bluetooth() {
  if [ -d /sys/class/bluetooth ] && [ -n "$(ls -A /sys/class/bluetooth 2>/dev/null)" ]; then
    return 0
  fi
  if command -v rfkill >/dev/null 2>&1 && rfkill list bluetooth 2>/dev/null | grep -q "bluetooth"; then
    return 0
  fi
  return 1
}

get_status() {
  if ! has_bluetooth; then
    echo "not available"
    return
  fi

  if command -v bluetoothctl >/dev/null 2>&1; then
    local powered
    powered=$(bluetoothctl show 2>/dev/null | awk '/Powered:/ {print $2}' || echo "no")
    if [ "$powered" = "yes" ]; then
      echo "active"
    else
      echo "disabled"
    fi
  else
    echo "ready"
  fi
}

toggle_power() {
  if ! has_bluetooth; then
    shree-notify "Bluetooth" "No Bluetooth hardware adapter detected on this machine" --app="Settings"
    return
  fi

  local cur
  cur=$(get_status)
  if [ "$cur" = "active" ]; then
    bluetoothctl power off >/dev/null 2>&1 || rfkill block bluetooth 2>/dev/null || true
    shree-notify "Bluetooth" "Bluetooth turned off" --app="Settings"
  else
    bluetoothctl power on >/dev/null 2>&1 || rfkill unblock bluetooth 2>/dev/null || true
    shree-notify "Bluetooth" "Bluetooth turned on" --app="Settings"
  fi
}

scan_and_pair() {
  if ! has_bluetooth; then
    shree-notify "Bluetooth" "No Bluetooth hardware adapter detected" --app="Settings"
    return
  fi

  st -g 75x20 -t "Bluetooth Discovery" -e /bin/bash -c "
    echo '=== Scanning for Nearby Bluetooth Devices ==='
    echo ''
    bluetoothctl scan on &
    SCAN_PID=\$!
    sleep 6
    kill \$SCAN_PID 2>/dev/null || true
    echo ''
    echo 'Discovered Devices:'
    bluetoothctl devices
    echo ''
    echo 'Press Enter to close.'
    read -r
  " &
}

interactive_menu() {
  local status
  status=$(get_status)
  
  if [ "$status" = "not available" ]; then
    shree-notify "Bluetooth" "No Bluetooth controller detected on this system" --app="Settings"
    return
  fi

  local options="Power: Toggle On/Off (Currently ${status})\nScan & Pair Devices\nList Paired Peripherals"
  local choice
  choice=$(echo -e "$options" | dmenu -p "Bluetooth Settings" -l 3 -c)
  [ -z "$choice" ] && return

  case "$choice" in
    "Power:"*) toggle_power ;;
    "Scan"*)   scan_and_pair ;;
    "List"*)
      st -g 70x16 -t "Paired Bluetooth Devices" -e /bin/bash -c "bluetoothctl paired-devices; echo ''; read -r -p 'Press Enter to close' _" &
      ;;
  esac
}

case "${1:-status}" in
  status) get_status ;;
  toggle) toggle_power ;;
  scan)   scan_and_pair ;;
  menu|*) interactive_menu ;;
esac
