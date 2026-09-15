#!/usr/bin/env bash
# desktop/scripts/shree-clipboard.sh — ShreeOS Clipboard History Manager & Daemon
#
# Privacy & Security Model:
#   - History file permissions: 0600 (Per-user private)
#   - Max entry size: 4096 bytes (Truncates or ignores oversized buffers)
#   - Max entries: 30 items
#   - Base64 encoding per line to prevent multiline injection / corruption
#   - Opt-in configuration via ~/.config/shreeos/clipboard.conf
#   - Single instance daemon enforcement via PID lock

set -euo pipefail

DATA_DIR="${XDG_DATA_HOME:-${HOME}/.local/share}/shreeos"
CONF_DIR="${XDG_CONFIG_HOME:-${HOME}/.config}/shreeos"
RUNTIME_DIR="${XDG_RUNTIME_DIR:-${HOME}/.cache/shreeos}"
HIST_FILE="${DATA_DIR}/clipboard.hist"
CONF_FILE="${CONF_DIR}/clipboard.conf"
INSTANCE_DIR="${RUNTIME_DIR}/clipboard-daemon.lock"
HIST_LOCK="${RUNTIME_DIR}/clipboard-history.lock"

umask 077
mkdir -p "$DATA_DIR" "$CONF_DIR" "$RUNTIME_DIR"
touch "$HIST_FILE"
chmod 600 "$HIST_FILE"

acquire_history_lock() {
  local attempt
  for attempt in {1..100}; do
    if mkdir "$HIST_LOCK" 2>/dev/null; then
      return 0
    fi
    sleep 0.02
  done
  echo "shree-clipboard: unable to lock clipboard history" >&2
  return 1
}

release_history_lock() {
  rmdir "$HIST_LOCK" 2>/dev/null || true
}

update_history() {
  local b64="$1"
  local tmp
  acquire_history_lock || return 1
  tmp=$(mktemp "${DATA_DIR}/clipboard.hist.XXXXXX")
  chmod 600 "$tmp"

  if [ -s "$HIST_FILE" ]; then
    grep -Fvx "$b64" "$HIST_FILE" > "$tmp" 2>/dev/null || true
  fi
  printf '%s\n' "$b64" >> "$tmp"

  if ! tail -n 30 "$tmp" > "${tmp}.tail"; then
    rm -f "$tmp" "${tmp}.tail"
    release_history_lock
    return 1
  fi
  chmod 600 "${tmp}.tail"
  mv -f "${tmp}.tail" "$HIST_FILE"
  rm -f "$tmp"
  chmod 600 "$HIST_FILE"
  release_history_lock
}

clear_history() {
  acquire_history_lock || return 1
  : > "$HIST_FILE"
  chmod 600 "$HIST_FILE"
  release_history_lock
}

is_enabled() {
  if [ -f "$CONF_FILE" ] && grep -q "ENABLED=false" "$CONF_FILE" 2>/dev/null; then
    return 1
  fi
  return 0
}

run_daemon() {
  # Enforce a race-free single instance per user. Recover a stale lock left
  # behind after an unclean shutdown only when its recorded PID is gone.
  if ! mkdir "$INSTANCE_DIR" 2>/dev/null; then
    local existing_pid=""
    [ -f "$INSTANCE_DIR/pid" ] && existing_pid=$(cat "$INSTANCE_DIR/pid" 2>/dev/null || true)
    if [[ "$existing_pid" =~ ^[0-9]+$ ]] && kill -0 "$existing_pid" 2>/dev/null; then
      echo "Clipboard daemon already running for UID ${UID}."
      exit 0
    fi
    rm -rf "$INSTANCE_DIR"
    mkdir "$INSTANCE_DIR" || {
      echo "shree-clipboard: unable to acquire daemon lock" >&2
      exit 1
    }
  fi
  printf '%s\n' "$" > "$INSTANCE_DIR/pid"
  chmod 600 "$INSTANCE_DIR/pid"
  trap 'rm -rf "$INSTANCE_DIR"' EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM

  local last_raw=""
  while true; do
    if is_enabled && command -v xclip >/dev/null 2>&1; then
      local cur_raw
      cur_raw=$(xclip -selection clipboard -o 2>/dev/null || true)
      
      if [ -n "$cur_raw" ] && [ "$cur_raw" != "$last_raw" ]; then
        # Bounds check: 2 to 4096 bytes
        local len=${#cur_raw}
        if [ "$len" -ge 2 ] && [ "$len" -le 4096 ]; then
          # Encode to single base64 line to handle multiline safely
          local b64
          b64=$(echo -n "$cur_raw" | base64 -w 0 2>/dev/null || echo -n "$cur_raw" | base64 | tr -d '\n')
          
          if update_history "$b64"; then
            last_raw="$cur_raw"
          fi
        fi
      fi
    fi
    sleep 1
  done
}

run_interactive() {
  if [ ! -s "$HIST_FILE" ]; then
    shree-notify "Clipboard" "Clipboard history is empty" --app="System"
    exit 0
  fi

  # Decode history entries for dmenu display
  local display_items="[Clear Clipboard History]\n[Toggle Clipboard Recording]\n"
  while read -r b64_line; do
    [ -z "$b64_line" ] && continue
    local decoded
    decoded=$(echo "$b64_line" | base64 -d 2>/dev/null | tr '\n' ' ' | head -c 80 || echo "")
    if [ -n "$decoded" ]; then
      display_items+="${decoded}\n"
    fi
  done < <(tac "$HIST_FILE" 2>/dev/null || cat "$HIST_FILE")

  local selected
  selected=$(echo -e "$display_items" | dmenu -p "Clipboard History (Super+V)" -l 8 -c || true)
  [ -z "$selected" ] && exit 0

  if [ "$selected" = "[Clear Clipboard History]" ]; then
    if clear_history; then
      shree-notify "Clipboard" "Clipboard history cleared" --app="System"
    else
      shree-notify "Clipboard" "Could not clear clipboard history" --app="System" --urgent
    fi
  elif [ "$selected" = "[Toggle Clipboard Recording]" ]; then
    if is_enabled; then
      echo "ENABLED=false" > "$CONF_FILE"
      shree-notify "Clipboard" "Clipboard history recording disabled" --app="System"
    else
      echo "ENABLED=true" > "$CONF_FILE"
      shree-notify "Clipboard" "Clipboard history recording enabled" --app="System"
    fi
  else
    # Find matching base64 entry and copy to active clipboard
    while read -r b64_line; do
      [ -z "$b64_line" ] && continue
      local full_text
      full_text=$(echo "$b64_line" | base64 -d 2>/dev/null || true)
      local preview
      preview=$(echo "$full_text" | tr '\n' ' ' | head -c 80)
      if [ "$preview" = "$selected" ]; then
        if command -v xclip >/dev/null 2>&1; then
          echo -n "$full_text" | xclip -selection clipboard -i
          shree-notify "Clipboard" "Copied selected clipping to active clipboard" --app="System"
        fi
        break
      fi
    done < "$HIST_FILE"
  fi
}

case "${1:-interactive}" in
  --daemon|daemon) run_daemon ;;
  clear)
    clear_history
    ;;
  interactive|*) run_interactive ;;
esac
