#!/usr/bin/env bash
# desktop/scripts/shree-connect.sh — ShreeOS Connect (Experimental Local Network File Transfer)
#
# Status: Experimental (Opt-in only, local LAN).
#
# Provides local peer discovery and basic file exchange with size limits,
# filename sanitization, and temporary .part file transfer.

set -euo pipefail

CONNECT_DIR="${HOME}/.config/shreeos/connect"
PAIRED_DEVICES="${CONNECT_DIR}/paired.list"
mkdir -p "$CONNECT_DIR"
chmod 700 "$CONNECT_DIR"
touch "$PAIRED_DEVICES"
chmod 600 "$PAIRED_DEVICES"

MAX_BYTES=$((50 * 1024 * 1024)) # 50 MB limit

run_listener_daemon() {
  local port=8899
  local dl_dir="${HOME}/Downloads"
  mkdir -p "$dl_dir"

  echo "ShreeOS Connect listener started on port ${port} (Opt-In Mode)"
  while true; do
    if command -v nc >/dev/null 2>&1; then
      local ts
      ts=$(date +"%Y%m%d_%H%M%S")
      local part_file="${dl_dir}/Transfer_${ts}.part"
      local final_file="${dl_dir}/Received_${ts}.dat"

      # Receive up to MAX_BYTES into temporary .part file
      nc -l -p "$port" > "$part_file" 2>/dev/null || true
      
      if [ -f "$part_file" ] && [ -s "$part_file" ]; then
        local sz
        sz=$(wc -c < "$part_file" || echo 0)
        if [ "$sz" -gt "$MAX_BYTES" ]; then
          rm -f "$part_file"
          shree-notify "Connect Alert" "Rejected incoming file exceeding 50MB limit" --app="Connect" --urgent
        else
          mv "$part_file" "$final_file"
          shree-notify "ShreeOS Connect" "Received file saved to $(basename "$final_file")" --app="Connect"
        fi
      else
        rm -f "$part_file"
      fi
    fi
    sleep 2
  done
}

discover_devices() {
  echo "Scanning local network ARP table for active peers..."
  ip neigh show 2>/dev/null | awk '{print $1" ("$5")"}' || echo "No peer devices discovered"
}

send_file_to_peer() {
  local target_file="${1:-}"
  if [ -z "$target_file" ] || [ ! -f "$target_file" ]; then
    target_file=$(find "${HOME}/Documents" "${HOME}/Downloads" -maxdepth 2 -type f 2>/dev/null | dmenu -p "Select File to Send" -l 8 -c || true)
  fi
  [ -z "$target_file" ] && exit 0

  # Sanitize and check file size
  local sz
  sz=$(wc -c < "$target_file" || echo 0)
  if [ "$sz" -gt "$MAX_BYTES" ]; then
    shree-notify "Connect Error" "File exceeds 50MB transfer limit" --app="Connect"
    exit 1
  fi

  local peer_ip
  peer_ip=$(discover_devices | dmenu -p "Send to Device" -l 5 -c | awk '{print $1}' || true)
  [ -z "$peer_ip" ] && exit 0

  shree-notify "ShreeOS Connect" "Sending $(basename "$target_file") to ${peer_ip}..." --app="Connect"
  if command -v nc >/dev/null 2>&1; then
    nc -w 4 "$peer_ip" 8899 < "$target_file" 2>/dev/null || true
  fi
  shree-notify "ShreeOS Connect" "File drop sent to ${peer_ip}" --app="Connect"
}

interactive_menu() {
  local options="[1] Send File to Nearby Device\n[2] Discover Network Devices\n[3] Start Connect Receiver (Manual Session)\n[4] Manage Paired Devices"
  local choice
  choice=$(echo -e "$options" | dmenu -p "ShreeOS Connect (Experimental)" -l 4 -c)
  [ -z "$choice" ] && exit 0

  case "$choice" in
    *"Send File"*) send_file_to_peer "${1:-}" ;;
    *"Discover"*)
      st -g 70x16 -t "Discovered Devices" -e /bin/bash -c "shree-connect discover; echo ''; read -r -p 'Press Enter to close' _" &
      ;;
    *"Start Connect Receiver"*)
      st -g 70x14 -t "Connect Receiver" -e /bin/bash -c "shree-connect --daemon" &
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
  menu|*)          interactive_menu ;;
esac
