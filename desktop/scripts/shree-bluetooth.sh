#!/usr/bin/env bash
# desktop/scripts/shree-bluetooth.sh — ShreeOS Bluetooth Hardware Manager
set -euo pipefail

has_bluetooth() {
  if [ -d /sys/class/bluetooth ] && [ -n "$(ls -A /sys/class/bluetooth 2>/dev/null)" ]; then
    return 0
  fi
  command -v rfkill >/dev/null 2>&1 &&
    rfkill list bluetooth 2>/dev/null | grep -qi "bluetooth"
}

get_status() {
  if ! has_bluetooth; then
    echo "not available"
    return
  fi

  if command -v bluetoothctl >/dev/null 2>&1; then
    local powered
    powered=$(bluetoothctl show 2>/dev/null | awk '/Powered:/ {print $2; exit}' || true)
    case "$powered" in
      yes) echo "active" ;;
      no) echo "disabled" ;;
      *) echo "ready" ;;
    esac
  else
    echo "ready"
  fi
}

set_power() {
  local target="$1"
  local action=""
  [ "$target" = "on" ] && action="unblock" || action="block"

  if ! has_bluetooth; then
    shree-notify "Bluetooth" "No Bluetooth hardware adapter detected on this machine" --app="Settings"
    return 1
  fi

  local command_succeeded=false
  if command -v bluetoothctl >/dev/null 2>&1 &&
     bluetoothctl power "$target" >/dev/null 2>&1; then
    command_succeeded=true
  elif command -v rfkill >/dev/null 2>&1 &&
       rfkill "$action" bluetooth >/dev/null 2>&1; then
    command_succeeded=true
  fi

  if [ "$command_succeeded" != true ]; then
    shree-notify "Bluetooth" "Unable to change Bluetooth power state" --app="Settings" --urgent
    return 1
  fi

  sleep 0.2
  local state
  state=$(get_status)
  if [ "$target" = "on" ] && [ "$state" = "active" ]; then
    shree-notify "Bluetooth" "Bluetooth turned on" --app="Settings"
  elif [ "$target" = "off" ] && [ "$state" = "disabled" ]; then
    shree-notify "Bluetooth" "Bluetooth turned off" --app="Settings"
  else
    shree-notify "Bluetooth" "Bluetooth power request completed (state: ${state})" --app="Settings"
  fi
}

toggle_power() {
  local cur
  cur=$(get_status)
  if [ "$cur" = "active" ]; then
    set_power off
  else
    set_power on
  fi
}

scan_and_pair() {
  if ! has_bluetooth; then
    shree-notify "Bluetooth" "No Bluetooth hardware adapter detected" --app="Settings"
    return 1
  fi
  if ! command -v bluetoothctl >/dev/null 2>&1; then
    shree-notify "Bluetooth" "bluetoothctl is required for discovery and pairing" --app="Settings" --urgent
    return 1
  fi
  if ! command -v st >/dev/null 2>&1; then
    shree-notify "Bluetooth" "Terminal application is unavailable for Bluetooth discovery" --app="Settings" --urgent
    return 1
  fi

  st -g 75x20 -t "Bluetooth Discovery" -e /bin/bash -c '
    echo "=== Scanning for Nearby Bluetooth Devices ==="
    echo
    bluetoothctl scan on >/dev/null 2>&1 &
    scan_pid=$!
    sleep 6
    kill "$scan_pid" 2>/dev/null || true
    bluetoothctl scan off >/dev/null 2>&1 || true
    echo "Discovered Devices:"
    bluetoothctl devices
    echo
    read -r -p "Press Enter to close." _
  ' &
}

interactive_menu() {
  local status choice
  status=$(get_status)

  if [ "$status" = "not available" ]; then
    shree-notify "Bluetooth" "No Bluetooth controller detected on this system" --app="Settings"
    return
  fi

  local options="Power: Toggle On/Off (Currently ${status})\nScan & Pair Devices\nList Paired Peripherals"
  choice=$(printf "%b\n" "$options" | dmenu -p "Bluetooth Settings" -l 3 -c || true)
  [ -z "$choice" ] && return

  case "$choice" in
    "Power:"*) toggle_power ;;
    "Scan"*) scan_and_pair ;;
    "List"*)
      if command -v bluetoothctl >/dev/null 2>&1 && command -v st >/dev/null 2>&1; then
        st -g 70x16 -t "Paired Bluetooth Devices" -e /bin/bash -c "bluetoothctl paired-devices; echo ''; read -r -p 'Press Enter to close' _" &
      else
        shree-notify "Bluetooth" "Bluetooth device listing is unavailable" --app="Settings" --urgent
      fi
      ;;
  esac
}

case "${1:-status}" in
  status) get_status ;;
  toggle) toggle_power ;;
  on) set_power on ;;
  off) set_power off ;;
  scan) scan_and_pair ;;
  menu|*) interactive_menu ;;
esac
