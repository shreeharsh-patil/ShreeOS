#!/usr/bin/env bash
# desktop/scripts/shree-net.sh — ShreeOS Truthful Network Controller
#
# Inspects real link state via /sys/class/net and routing table.
# Refuses to report false connections. Secure Wi-Fi credential handling.

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
    local wlan_dev=""
    for dev in /sys/class/net/wl* /sys/class/net/wlan*; do
      if [ -e "$dev" ]; then
        wlan_dev="$(basename "$dev")"
        break
      fi
    done
    if [ -n "$wlan_dev" ]; then
      iwlist "$wlan_dev" scan 2>/dev/null | sed -n 's/.*ESSID:"\([^"]*\)".*/\1/p' | sort -u || echo ""
    fi
  elif command -v nmcli >/dev/null 2>&1; then
    nmcli -t -f SSID dev wifi list 2>/dev/null | sort -u || echo ""
  fi
}

restart_network() {
  if [ -x /sbin/initctl ] || [ -x /usr/bin/initctl ]; then
    if ! initctl restart network >/dev/null 2>&1; then
      shree-notify "Network" "Failed to restart the network service" --app="Network" --urgent
      return 1
    fi
  elif ! ip link set lo up >/dev/null 2>&1; then
    shree-notify "Network" "Failed to refresh network interfaces" --app="Network" --urgent
    return 1
  fi

  local new_ip
  new_ip=$(get_ip)
  if [ "$new_ip" != "none" ]; then
    shree-notify "Network Refreshed" "Interface active (IP: ${new_ip})" --app="Network"
  else
    shree-notify "Network Refreshed" "Network service restarted; no global IP is assigned yet." --app="Network"
  fi
}

disconnect_network() {
  local iface
  iface=$(ip route show default 2>/dev/null | awk '{print $5}' | head -n1 || echo "")
  if [ -z "$iface" ]; then
    shree-notify "Network" "No active default interface to disconnect" --app="Network"
    return 0
  fi

  if ip link set "$iface" down >/dev/null 2>&1; then
    shree-notify "Network" "Disconnected interface ${iface}" --app="Network"
  else
    shree-notify "Network" "Failed to disconnect interface ${iface}" --app="Network" --urgent
    return 1
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
  choice=$(printf "%b\n" "$menu" | dmenu -p "Network Management" -l 6 -c || true)
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
      if command -v wpa_supplicant >/dev/null 2>&1; then
        local pw conf_tmp wlan_dev ssid_bytes ssid_hex
        pw=$(printf "\n" | dmenu -p "Password for ${choice} (leave empty for open network):" -c || true)

        ssid_bytes=$(printf '%s' "$choice" | wc -c | tr -d '[:space:]')
        if ! [[ "$ssid_bytes" =~ ^[0-9]+$ ]] || [ "$ssid_bytes" -lt 1 ] || [ "$ssid_bytes" -gt 32 ]; then
          pw=""
          unset pw
          shree-notify "Network" "Invalid Wi-Fi network name" --app="Network" --urgent
          return 1
        fi

        conf_tmp=$(mktemp /tmp/shreeos-wpa-XXXXXX.conf)
        chmod 600 "$conf_tmp"

        if [ -n "$pw" ]; then
          if ! command -v wpa_passphrase >/dev/null 2>&1; then
            pw=""
            unset pw
            rm -f "$conf_tmp"
            shree-notify "Network" "wpa_passphrase is required for protected Wi-Fi networks" --app="Network" --urgent
            return 1
          fi
          if ! printf "%s\n" "$pw" | wpa_passphrase "$choice" 2>/dev/null | sed '/^[[:space:]]*#psk=/d; /^[[:space:]]*ssid=/a\  scan_ssid=1' > "$conf_tmp"; then
            pw=""
            unset pw
            rm -f "$conf_tmp"
            shree-notify "Network" "Failed to prepare Wi-Fi credentials for ${choice}" --app="Network" --urgent
            return 1
          fi
        else
          ssid_hex=$(printf '%s' "$choice" | od -An -tx1 | tr -d ' \n')
          printf 'ctrl_interface=/run/wpa_supplicant\nnetwork={\n  ssid=%s\n  key_mgmt=NONE\n  scan_ssid=1\n}\n' "$ssid_hex" > "$conf_tmp"
        fi
        pw=""
        unset pw

        wlan_dev=""
        for dev in /sys/class/net/wl* /sys/class/net/wlan*; do
          if [ -e "$dev" ]; then
            wlan_dev="$(basename "$dev")"
            break
          fi
        done

        if [ -z "$wlan_dev" ]; then
          rm -f "$conf_tmp"
          shree-notify "Network" "No wireless interface is available" --app="Network" --urgent
          return 1
        fi

        if wpa_supplicant -B -i "$wlan_dev" -c "$conf_tmp" >/dev/null 2>&1; then
          rm -f "$conf_tmp"
          shree-notify "Network" "Wi-Fi authentication started for ${choice}" --app="Network"
        else
          rm -f "$conf_tmp"
          shree-notify "Network" "Failed to start Wi-Fi authentication for ${choice}" --app="Network" --urgent
          return 1
        fi
      elif command -v nmcli >/dev/null 2>&1; then
        # Let NetworkManager request secrets through its normal secure prompt/
        # secret-agent path. Never place the Wi-Fi password in argv.
        if nmcli --wait 30 --ask device wifi connect "$choice"; then
          shree-notify "Network" "Connected to ${choice}" --app="Network"
        else
          shree-notify "Network" "Failed to connect to ${choice}" --app="Network" --urgent
          return 1
        fi
      else
        shree-notify "Wi-Fi Config" "Neither wpa_supplicant nor NetworkManager is available" --app="Network" --urgent
        return 1
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
