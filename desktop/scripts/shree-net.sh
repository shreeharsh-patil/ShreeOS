#!/usr/bin/env bash
# desktop/scripts/shree-net.sh — ShreeOS Truthful Network Controller
#
# Inspects real link state via /sys/class/net and routing table.
# Refuses to report false connections.

set -euo pipefail

get_status() {
  if ip route show default 2>/dev/null | grep -q "default"; then
    echo "connected"
  else
    echo "offline"
  fi
}

get_ip() {
  ip -4 addr show scope global 2>/dev/null | awk '/inet / {print $2}' | head -n1 || echo "none"
}

scan_networks() {
  if command -v iwlist >/dev/null 2>&1; then
    local wlan_dev
    wlan_dev=$(ls /sys/class/net 2>/dev/null | grep -E '^wl' | head -n1 || echo "")
    if [ -n "$wlan_dev" ]; then
      iwlist "$wlan_dev" scan 2>/dev/null | grep -oP 'ESSID:"\K[^"]+' | sort -u || echo ""
    fi
  elif command -v nmcli >/dev/null 2>&1; then
    nmcli -t -f SSID dev wifi list 2>/dev/null | sort -u || echo ""
  fi
}

restart_network() {
  if [ -x /sbin/initctl ] || [ -x /usr/bin/initctl ]; then
    initctl restart network 2>/dev/null || true
  else
    ip link set lo up 2>/dev/null || true
  fi
  local new_ip
  new_ip=$(get_ip)
  if [ "$new_ip" != "none" ]; then
    shree-notify "Network Refreshed" "Interface active (IP: ${new_ip})" --app="Network"
  else
    shree-notify "Network Status" "No active global IP route found." --app="Network" --urgent
  fi
}

disconnect_network() {
  local iface
  iface=$(ip route show default 2>/dev/null | awk '{print $5}' | head -n1 || echo "")
  if [ -n "$iface" ]; then
    ip link set "$iface" down 2>/dev/null || true
    shree-notify "Network" "Disconnected interface ${iface}" --app="Network"
  else
    shree-notify "Network" "No active default interface to disconnect" --app="Network"
  fi
}

interactive_menu() {
  local networks
  networks=$(scan_networks)
  local menu="[Refresh Interfaces]\n[Disconnect Active Route]"

  if [ -n "$networks" ]; then
    menu+="\n${networks}"
  else
    menu+="\n(No wireless SSIDs detected or wireless adapter absent)"
  fi

  local choice
  choice=$(echo -e "$menu" | dmenu -p "Network Management" -l 6 -c || true)
  [ -z "$choice" ] && exit 0

  case "$choice" in
    "[Refresh Interfaces]")
      restart_network
      ;;
    "[Disconnect Active Route]")
      disconnect_network
      ;;
    "(*"|"")
      ;;
    *)
      # Attempt to connect to chosen SSID if wpa_supplicant toolchain exists
      if command -v nmcli >/dev/null 2>&1; then
        local pw
        pw=$(echo "" | dmenu -p "Password for ${choice}:" -c)
        if [ -n "$pw" ]; then
          if nmcli dev wifi connect "$choice" password "$pw" >/dev/null 2>&1; then
            shree-notify "Network Connected" "Connected to ${choice}" --app="Network"
          else
            shree-notify "Connection Failed" "Could not authenticate to ${choice}" --app="Network" --urgent
          fi
        fi
      else
        shree-notify "Wi-Fi Config" "nmcli/wpa_supplicant required for SSID connection" --app="Network"
      fi
      ;;
  esac
}

case "${1:-status}" in
  status) get_status ;;
  ip)     get_ip ;;
  scan)   scan_networks ;;
  restart) restart_network ;;
  disconnect) disconnect_network ;;
  menu|*) interactive_menu ;;
esac
