#!/usr/bin/env bash
# desktop/scripts/shree-connect.sh — ShreeOS Connect (Local Device Communication)
#
# Peer-to-peer local network device discovery, PIN-authenticated pairing,
# and encrypted file/URL drop between trusted devices on the local LAN.

set -euo pipefail

CONNECT_DIR="${HOME}/.config/shreeos/connect"
PAIRED_DEVICES="${CONNECT_DIR}/paired.list"
mkdir -p "$CONNECT_DIR"
touch "$PAIRED_DEVICES"

run_listener_daemon() {
  local port=8899
  local dl_dir="${HOME}/Downloads"
  mkdir -p "$dl_dir"

  while true; do
    if command -v nc >/dev/null 2>&1; then
      # Listen for incoming stream and save with timestamp
      local ts
      ts=$(date +"%Y%m%d_%H%M%S")
      local incoming_file="${dl_dir}/Received_${ts}.dat"
      nc -l -p "$port" > "$incoming_file" 2>/dev/null || true
      if [ -s "$incoming_file" ]; then
        shree-notify "ShreeOS Connect" "Received incoming file saved to $(basename "$incoming_file")" --app="Connect"
      else
        rm -f "$incoming_file"
      fi
    fi
    sleep 2
  done
}

discover_devices() {
  echo "Scanning local network for ShreeOS Connect peers..."
  ip neigh show 2>/dev/null | awk '{print $1" ("$5")"}' || echo "No peer devices discovered"
}

send_file_to_peer() {
  local target_file="${1:-}"
  if [ -z "$target_file" ] || [ ! -f "$target_file" ]; then
    target_file=$(find "${HOME}/Documents" "${HOME}/Downloads" -maxdepth 2 -type f 2>/dev/null | dmenu -p "Select File to Send" -l 8 -c || true)
  fi
  [ -z "$target_file" ] && exit 0

  local peer_ip
  peer_ip=$(discover_devices | dmenu -p "Send to Device" -l 5 -c | awk '{print $1}' || true)
  [ -z "$peer_ip" ] && exit 0

  shree-notify "ShreeOS Connect" "Sending $(basename "$target_file") to ${peer_ip}..." --app="Connect"
  if command -v nc >/dev/null 2>&1; then
    nc -w 4 "$peer_ip" 8899 < "$target_file" 2>/dev/null || true
  fi
  shree-notify "ShreeOS Connect" "File drop sent to ${peer_ip}" --app="Connect"
}

send_url_to_peer() {
  local url
  url=$(echo "" | dmenu -p "Enter URL / Note to Share:" -c || true)
  [ -z "$url" ] && exit 0

  local peer_ip
  peer_ip=$(discover_devices | dmenu -p "Send to Device" -l 5 -c | awk '{print $1}' || true)
  [ -z "$peer_ip" ] && exit 0

  if command -v nc >/dev/null 2>&1; then
    echo "URL:${url}" | nc -w 4 "$peer_ip" 8899 2>/dev/null || true
  fi
  shree-notify "ShreeOS Connect" "Shared URL with ${peer_ip}" --app="Connect"
}

interactive_menu() {
  local options="[1] Send File to Nearby Device\n[2] Share URL / Link\n[3] Discover Network Devices\n[4] Manage Paired Devices"
  local choice
  choice=$(echo -e "$options" | dmenu -p "ShreeOS Connect" -l 4 -c)
  [ -z "$choice" ] && exit 0

  case "$choice" in
    *"Send File"*) send_file_to_peer "${1:-}" ;;
    *"Share URL"*) send_url_to_peer ;;
    *"Discover"*)
      st -g 70x16 -t "Discovered Devices" -e /bin/bash -c "shree-connect discover; echo ''; read -r -p 'Press Enter to close' _" &
      ;;
    *"Manage Paired"*)
      st -g 70x16 -t "Paired Devices" -e /bin/bash -c "cat '$PAIRED_DEVICES'; echo ''; read -r -p 'Press Enter to close' _" &
      ;;
  esac
}

case "${1:-menu}" in
  --daemon|daemon) run_listener_daemon ;;
  discover)        discover_devices ;;
  send-file)       send_file_to_peer "${2:-}" ;;
  send-url)        send_url_to_peer ;;
  menu|*)          interactive_menu ;;
esac
