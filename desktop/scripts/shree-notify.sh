#!/usr/bin/env bash
# desktop/scripts/shree-notify.sh — lightweight ShreeOS notifications
set -euo pipefail

render_terminal_card() {
  local app="$1" icon="$2" title="$3" body="$4" action_label="$5" action_cmd="$6" timeout="$7"
  local key=""

  clear
  echo '┌────────────────────────────────────────────┐'
  printf '│  %-2s %-32.32s [x] │\n' "$icon" "$app: $title"
  echo '├────────────────────────────────────────────┤'
  printf '│  %-42.42s│\n' "$body"
  if [ -n "$action_label" ]; then
    printf '│  [Enter: %-18.18s] [Esc: Close] │\n' "$action_label"
  else
    printf '│  Auto-closing in %-2ss                 │\n' "$timeout"
  fi
  echo '└────────────────────────────────────────────┘'

  # A timeout is not an action. Only execute an explicitly configured action
  # when read actually succeeds because the user pressed Enter.
  if read -t "$timeout" -r -s -n 1 key; then
    if [ -n "$action_cmd" ] && [ -z "$key" ]; then
      /bin/bash -lc "$action_cmd" >/dev/null 2>&1 &
    fi
  fi
}

if [ "${1:-}" = "--render" ]; then
  shift
  [ "$#" -eq 7 ] || exit 2
  render_terminal_card "$@"
  exit 0
fi

TITLE="${1:-Notification}"
BODY="${2:-}"
APP="System"
ICON="⟡"
ACTION_LABEL=""
ACTION_CMD=""
TIMEOUT=4
URGENT=false

shift 2 2>/dev/null || true
while [ "$#" -gt 0 ]; do
  case "$1" in
    --app=*) APP="${1#*=}" ;;
    --icon=*) ICON="${1#*=}" ;;
    --action=*) ACTION_LABEL="${1#*=}" ;;
    --action-cmd=*) ACTION_CMD="${1#*=}" ;;
    --timeout=*) TIMEOUT="${1#*=}" ;;
    --urgent) URGENT=true ;;
    *) echo "shree-notify: unknown option '$1'" >&2; exit 2 ;;
  esac
  shift
done

if ! [[ "$TIMEOUT" =~ ^[0-9]+$ ]] || [ "$TIMEOUT" -lt 1 ] || [ "$TIMEOUT" -gt 60 ]; then
  echo "shree-notify: timeout must be an integer from 1 to 60 seconds" >&2
  exit 2
fi

case "$APP" in
  Files) ICON="📁" ;;
  Terminal) ICON="💻" ;;
  Settings) ICON="⚙" ;;
  Dock) ICON="⊞" ;;
  Calculator) ICON="🧮" ;;
  Security) ICON="🔒" ;;
  Network) ICON="󰤨" ;;
  Desktop) ICON="⟡" ;;
esac

CONFIG_DIR="${HOME}/.config/shreeos"
DND_FILE="${CONFIG_DIR}/dnd.state"
LOG_DIR="${HOME}/.local/share/shreeos"
LOG_FILE="${LOG_DIR}/notifications.log"
LOCK_FILE="${LOG_DIR}/notifications.lock"
umask 077
mkdir -p "$LOG_DIR"
touch "$LOG_FILE" "$LOCK_FILE"
chmod 600 "$LOG_FILE" "$LOCK_FILE"

# Keep one notification on one history line and preserve the pipe-delimited
# history format even when callers pass external text.
sanitize_log_field() {
  printf '%s' "$1" | tr '\r\n|' '   '
}

update_notification_history() {
  local status="$1"
  local tmp

  printf '%s|%s|%s|%s|%s\n' \
    "$(date +%s)" \
    "$(sanitize_log_field "$APP")" \
    "$(sanitize_log_field "$TITLE")" \
    "$(sanitize_log_field "$BODY")" \
    "$status" >> "$LOG_FILE"
  chmod 600 "$LOG_FILE"

  tmp=$(mktemp "${LOG_DIR}/notifications.log.XXXXXX")
  chmod 600 "$tmp"
  if tail -n 50 "$LOG_FILE" > "$tmp"; then
    mv -f "$tmp" "$LOG_FILE"
    chmod 600 "$LOG_FILE"
  else
    rm -f "$tmp"
    chmod 600 "$LOG_FILE"
    return 1
  fi
}

log_notification() {
  local status="$1"

  if command -v flock >/dev/null 2>&1; then
    (
      flock -x 9
      update_notification_history "$status"
    ) 9>"$LOCK_FILE"
    chmod 600 "$LOCK_FILE"
    return
  fi

  # util-linux normally provides flock. Keep a safe atomic-directory fallback
  # for reduced environments instead of allowing concurrent history rewrites.
  local lock_dir="${LOCK_FILE}.d"
  local acquired=false
  for _attempt in {1..100}; do
    if mkdir "$lock_dir" 2>/dev/null; then
      acquired=true
      break
    fi
    sleep 0.02
  done
  if [ "$acquired" != true ]; then
    echo "shree-notify: unable to lock notification history" >&2
    return 1
  fi

  if update_notification_history "$status"; then
    rmdir "$lock_dir" 2>/dev/null || true
    return 0
  fi
  rmdir "$lock_dir" 2>/dev/null || true
  return 1
}

if [ -f "$DND_FILE" ] && [ "$(cat "$DND_FILE" 2>/dev/null || true)" = "on" ] && [ "$URGENT" = false ]; then
  log_notification silent
  exit 0
fi

log_notification displayed

if command -v notify-send >/dev/null 2>&1; then
  notify-send -a "$APP" -t "$(( TIMEOUT * 1000 ))" "$TITLE" "$BODY"
elif [ -n "${DISPLAY:-}" ] && command -v st >/dev/null 2>&1; then
  st -c "ShreeNotify" -g "44x6-20+36" -t "$APP" -e "$0" --render \
    "$APP" "$ICON" "$TITLE" "$BODY" "$ACTION_LABEL" "$ACTION_CMD" "$TIMEOUT" &
else
  printf '[%s] %s: %s\n' "$APP" "$TITLE" "$BODY"
fi
