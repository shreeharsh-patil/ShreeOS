#!/usr/bin/env bash
# desktop/scripts/shree-connect.sh — ShreeOS Connect (Experimental Local Network File Transfer)
#
# Status: Disabled by default (Experimental LAN Transfer).
# Requires explicit opt-in via ~/.config/shreeos/connect/config (ENABLED=true).

set -euo pipefail

CONNECT_DIR="${HOME}/.config/shreeos/connect"
CONF_FILE="${CONNECT_DIR}/config"
PAIRED_DEVICES="${CONNECT_DIR}/paired.list"
mkdir -p "$CONNECT_DIR"
chmod 700 "$CONNECT_DIR"
touch "$PAIRED_DEVICES"
chmod 600 "$PAIRED_DEVICES"

MAX_BYTES=$((50 * 1024 * 1024)) # 50 MB limit

is_enabled() {
  if [ -f "$CONF_FILE" ] && grep -q "ENABLED=true" "$CONF_FILE" 2>/dev/null; then
    return 0
  fi
  return 1
}

run_listener_daemon() {
  if ! is_enabled; then
    echo "ShreeOS Connect is disabled by default. Enable it via Settings or by creating ${CONF_FILE} with ENABLED=true."
    exit 0
  fi

  local port=8899
  local dl_dir="${HOME}/Downloads"
  mkdir -p "$dl_dir"

  echo "ShreeOS Connect listener started on port ${port} (Opt-In Mode)"
  while true; do
    if is_enabled && command -v nc >/dev/null 2>&1; then
      local ts
      ts=$(date +"%Y%m%d_%H%M%S")
      local part_file="${dl_dir}/Transfer_${ts}.part"
      local final_file="${dl_dir}/Received_${ts}.dat"

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
  local initial_file="${1:-}"
  local state="Disabled"
  if is_enabled; then state="Enabled"; fi

  local options="[1] Toggle Connect Feature (Currently ${state})\n[2] Send File to Nearby Device\n[3] Discover Network Devices\n[4] Manage Paired Devices"
  local choice
  choice=$(echo -e "$options" | dmenu -p "ShreeOS Connect" -l 4 -c)
  [ -z "$choice" ] && exit 0

  case "$choice" in
    *"Toggle Connect"*)
      if is_enabled; then
        echo "ENABLED=false" > "$CONF_FILE"
        shree-notify "Connect" "ShreeOS Connect disabled" --app="Connect"
      else
        echo "ENABLED=true" > "$CONF_FILE"
        shree-notify "Connect" "ShreeOS Connect enabled (Local LAN only)" --app="Connect"
      fi
      ;;
    *"Send File"*) send_file_to_peer "$initial_file" ;;
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
  menu|*)          interactive_menu "${2:-}" ;;
esac
