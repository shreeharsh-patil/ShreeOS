#!/usr/bin/env bash
# desktop/scripts/shree-connect.sh — ShreeOS Connect (Experimental Local Network File Transfer)
#
# Status: Disabled by default (Experimental LAN Transfer).
# Requires explicit opt-in via ~/.config/shreeos/connect/config (ENABLED=true).

set -euo pipefail

CONNECT_DIR="${HOME}/.config/shreeos/connect"
CONF_FILE="${CONNECT_DIR}/config"
PAIRED_DEVICES="${CONNECT_DIR}/paired.list"
RUNTIME_DIR="${XDG_RUNTIME_DIR:-${HOME}/.cache/shreeos}"
LISTENER_LOCK="${RUNTIME_DIR}/connect-listener.lock"

umask 077
mkdir -p "$CONNECT_DIR" "$RUNTIME_DIR"
chmod 700 "$CONNECT_DIR" "$RUNTIME_DIR" 2>/dev/null || true
touch "$PAIRED_DEVICES"
chmod 600 "$PAIRED_DEVICES"

config_value() {
  local key="$1" default_value="$2" value=""
  if [ -f "$CONF_FILE" ]; then
    value=$(awk -F= -v key="$key" '$1 == key { sub(/^[^=]*=/, ""); print; exit }' "$CONF_FILE" 2>/dev/null || true)
  fi
  printf '%s\n' "${value:-$default_value}"
}

connect_port() {
  local port
  port=$(config_value PORT 8899)
  if ! [[ "$port" =~ ^[0-9]+$ ]] || [ "$port" -lt 1024 ] || [ "$port" -gt 65535 ]; then
    echo "shree-connect: invalid PORT in $CONF_FILE: $port" >&2
    return 1
  fi
  printf '%s\n' "$port"
}

max_bytes() {
  local value
  value=$(config_value MAX_BYTES "$((50 * 1024 * 1024))")
  if ! [[ "$value" =~ ^[0-9]+$ ]] || [ "$value" -lt 1048576 ] || [ "$value" -gt 1073741824 ]; then
    echo "shree-connect: invalid MAX_BYTES in $CONF_FILE: $value" >&2
    return 1
  fi
  printf '%s\n' "$value"
}

write_enabled_state() {
  local enabled="$1"
  local tmp
  tmp=$(mktemp "${CONNECT_DIR}/config.XXXXXX")
  {
    printf 'ENABLED=%s\n' "$enabled"
    printf 'PORT=%s\n' "$(config_value PORT 8899)"
    printf 'MAX_BYTES=%s\n' "$(config_value MAX_BYTES "$((50 * 1024 * 1024))")"
  } > "$tmp"
  chmod 600 "$tmp"
  mv -f "$tmp" "$CONF_FILE"
}

is_enabled() {
  [ "$(config_value ENABLED false)" = "true" ]
}

run_listener_daemon() {
  if ! is_enabled; then
    echo "ShreeOS Connect is disabled by default. Enable it from the Connect menu before starting the listener."
    exit 0
  fi
  command -v nc >/dev/null 2>&1 || {
    echo "shree-connect: netcat (nc) is required for LAN transfers" >&2
    exit 1
  }

  if ! mkdir "$LISTENER_LOCK" 2>/dev/null; then
    local existing_pid=""
    [ -f "$LISTENER_LOCK/pid" ] && existing_pid=$(cat "$LISTENER_LOCK/pid" 2>/dev/null || true)
    if [[ "$existing_pid" =~ ^[0-9]+$ ]] && kill -0 "$existing_pid" 2>/dev/null; then
      echo "ShreeOS Connect listener is already running (PID $existing_pid)."
      exit 0
    fi
    rm -rf "$LISTENER_LOCK"
    mkdir "$LISTENER_LOCK" || {
      echo "shree-connect: unable to acquire listener lock" >&2
      exit 1
    }
  fi
  printf '%s\n' "$$" > "$LISTENER_LOCK/pid"
  chmod 600 "$LISTENER_LOCK/pid"
  trap 'rm -rf "$LISTENER_LOCK"' EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM

  local port limit dl_dir
  port=$(connect_port) || exit 1
  limit=$(max_bytes) || exit 1
  dl_dir="${HOME}/Downloads"
  mkdir -p "$dl_dir"

  echo "ShreeOS Connect listener started on port ${port} (Opt-In Mode)"
  while is_enabled; do
    local ts part_file final_file nc_status=0 size
    ts=$(date +"%Y%m%d_%H%M%S")
    part_file=$(mktemp "${dl_dir}/.shree-connect.XXXXXX.part")
    final_file="${dl_dir}/Received_${ts}_$$.dat"

    if ! nc -l -p "$port" > "$part_file" 2>/dev/null; then
      nc_status=$?
    fi

    if [ ! -s "$part_file" ]; then
      rm -f "$part_file"
      [ "$nc_status" -eq 0 ] || sleep 1
      continue
    fi

    size=$(wc -c < "$part_file" 2>/dev/null || echo 0)
    if ! [[ "$size" =~ ^[0-9]+$ ]]; then
      rm -f "$part_file"
      shree-notify "Connect Alert" "Incoming transfer size could not be verified" --app="Connect" --urgent
      continue
    fi

    if [ "$size" -gt "$limit" ]; then
      rm -f "$part_file"
      shree-notify "Connect Alert" "Rejected incoming file exceeding the configured size limit" --app="Connect" --urgent
    elif [ "$nc_status" -ne 0 ]; then
      rm -f "$part_file"
      shree-notify "Connect Alert" "Incoming transfer was interrupted and discarded" --app="Connect" --urgent
    elif mv "$part_file" "$final_file"; then
      chmod 600 "$final_file"
      shree-notify "ShreeOS Connect" "Received file saved to $(basename "$final_file")" --app="Connect"
    else
      rm -f "$part_file"
      shree-notify "Connect Alert" "Could not save the received file" --app="Connect" --urgent
    fi
  done

  echo "ShreeOS Connect listener stopped because the feature was disabled."
}

discover_devices() {
  echo "Scanning local network ARP table for active peers..."
  ip neigh show 2>/dev/null | awk '{print $1" ("$5")"}' || echo "No peer devices discovered"
}

send_file_to_peer() {
  local target_file="${1:-}"
  local limit port

  command -v nc >/dev/null 2>&1 || {
    shree-notify "Connect Error" "netcat (nc) is required for LAN transfers" --app="Connect" --urgent
    return 1
  }
  limit=$(max_bytes) || return 1
  port=$(connect_port) || return 1

  if [ -z "$target_file" ] || [ ! -f "$target_file" ]; then
    target_file=$(find "${HOME}/Documents" "${HOME}/Downloads" -maxdepth 2 -type f 2>/dev/null |
      dmenu -p "Select File to Send" -l 8 -c || true)
  fi
  [ -z "$target_file" ] && return 0
  [ -f "$target_file" ] || {
    shree-notify "Connect Error" "Selected file is no longer available" --app="Connect" --urgent
    return 1
  }

  local size
  size=$(wc -c < "$target_file" 2>/dev/null || echo 0)
  if ! [[ "$size" =~ ^[0-9]+$ ]] || [ "$size" -gt "$limit" ]; then
    shree-notify "Connect Error" "File exceeds the configured transfer limit or its size could not be read" --app="Connect" --urgent
    return 1
  fi

  local peer_ip
  peer_ip=$(discover_devices | dmenu -p "Send to Device" -l 5 -c | awk '{print $1}' || true)
  [ -z "$peer_ip" ] && return 0

  shree-notify "ShreeOS Connect" "Sending $(basename "$target_file") to ${peer_ip}..." --app="Connect"
  if nc -w 4 "$peer_ip" "$port" < "$target_file" 2>/dev/null; then
    shree-notify "ShreeOS Connect" "File sent to ${peer_ip}" --app="Connect"
    return 0
  fi

  shree-notify "Connect Error" "Transfer to ${peer_ip} failed" --app="Connect" --urgent
  return 1
}

interactive_menu() {
  local initial_file="${1:-}"
  local state="Disabled"
  if is_enabled; then state="Enabled"; fi

  local options="[1] Toggle Connect Feature (Currently ${state})\n[2] Send File to Nearby Device\n[3] Discover Network Devices\n[4] View Saved Peer List"
  local choice
  choice=$(echo -e "$options" | dmenu -p "ShreeOS Connect" -l 4 -c)
  [ -z "$choice" ] && exit 0

  case "$choice" in
    *"Toggle Connect"*)
      if is_enabled; then
        write_enabled_state false
        shree-notify "Connect" "ShreeOS Connect disabled" --app="Connect"
      else
        write_enabled_state true
        shree-notify "Connect" "ShreeOS Connect enabled (Local LAN only)" --app="Connect"
      fi
      ;;
    *"Send File"*) send_file_to_peer "$initial_file" ;;
    *"Discover"*)
      st -g 70x16 -t "Discovered Devices" -e /bin/bash -c "shree-connect discover; echo ''; read -r -p 'Press Enter to close' _" &
      ;;
    *"View Saved"*)
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
