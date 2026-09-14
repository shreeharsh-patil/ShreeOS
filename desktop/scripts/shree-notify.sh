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
mkdir -p "$LOG_DIR"

# Keep one notification on one history line and preserve the pipe-delimited
# history format even when callers pass external text.
sanitize_log_field() {
  printf '%s' "$1" | tr '\r\n|' '   '
}

log_notification() {
  local status="$1"
  printf '%s|%s|%s|%s|%s\n' \
    "$(date +%s)" \
    "$(sanitize_log_field "$APP")" \
    "$(sanitize_log_field "$TITLE")" \
    "$(sanitize_log_field "$BODY")" \
    "$status" >> "$LOG_FILE"

  local tmp
  tmp=$(mktemp "${LOG_DIR}/notifications.log.XXXXXX")
  if tail -n 50 "$LOG_FILE" > "$tmp"; then
    mv "$tmp" "$LOG_FILE"
  else
    rm -f "$tmp"
  fi
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
