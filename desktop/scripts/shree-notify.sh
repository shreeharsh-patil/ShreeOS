#!/usr/bin/env bash
# desktop/scripts/shree-notify.sh — macOS-Inspired Lightweight Notification System
#
# Notifications appear in the upper-right corner.
# Structure:
#   - Application monogram icon
#   - Bold Title
#   - Message Body
#   - Optional Action
#   - Close Button (✕ / Esc / Click)
#
# Features:
#   - Automatic timeout (default 4s)
#   - Queue & stack limiter (maximum 3 concurrent notifications)
#   - Do Not Disturb mode check
#   - History log for Notification Center (~/.local/share/shreeos/notifications.log)
#   - Very low memory usage, 0% CPU after display
#
set -euo pipefail

TITLE="${1:-Notification}"
BODY="${2:-}"
APP="System"
ICON="⟡"
ACTION_LABEL=""
ACTION_CMD=""
TIMEOUT=4
URGENT=false

shift 2 2>/dev/null || true

while [ $# -gt 0 ]; do
  case "$1" in
    --app=*) APP="${1#*=}" ;;
    --icon=*) ICON="${1#*=}" ;;
    --action=*) ACTION_LABEL="${1#*=}" ;;
    --action-cmd=*) ACTION_CMD="${1#*=}" ;;
    --timeout=*) TIMEOUT="${1#*=}" ;;
    --urgent) URGENT=true ;;
  esac
  shift
done

# Map common app names to clean monograms
case "$APP" in
  Files)       ICON="📁" ;;
  Terminal)    ICON="💻" ;;
  Settings)    ICON="⚙" ;;
  Dock)        ICON="⊞" ;;
  Calculator)  ICON="🧮" ;;
  Security)    ICON="🔒" ;;
  Network)     ICON="󰤨" ;;
  Desktop)     ICON="⟡" ;;
esac

# 1. Check Do Not Disturb state
CONFIG_DIR="${HOME}/.config/shreeos"
DND_FILE="${CONFIG_DIR}/dnd.state"
if [ -f "$DND_FILE" ] && [ "$(cat "$DND_FILE")" = "on" ] && [ "$URGENT" = false ]; then
  LOG_DIR="${HOME}/.local/share/shreeos"
  mkdir -p "$LOG_DIR"
  echo "$(date +%s)|${APP}|${TITLE}|${BODY}|silent" >> "${LOG_DIR}/notifications.log"
  exit 0
fi

# 2. Append to Notification Center Log
LOG_DIR="${HOME}/.local/share/shreeos"
mkdir -p "$LOG_DIR"
echo "$(date +%s)|${APP}|${TITLE}|${BODY}|displayed" >> "${LOG_DIR}/notifications.log"

if tail -n 50 "${LOG_DIR}/notifications.log" > "${LOG_DIR}/notifications.log.tmp" 2>/dev/null; then
  mv "${LOG_DIR}/notifications.log.tmp" "${LOG_DIR}/notifications.log" 2>/dev/null || true
fi

# 3. Stack Limiter: Keep maximum 3 notifications active simultaneously
RUNTIME_DIR="${XDG_RUNTIME_DIR:-/tmp}/shreeos-notify"
mkdir -p "$RUNTIME_DIR"
PID_FILE="${RUNTIME_DIR}/active.pids"
touch "$PID_FILE"

# Clean dead pids
ACTIVE_PIDS=""
while read -r p; do
  if [ -n "$p" ] && kill -0 "$p" 2>/dev/null; then
    ACTIVE_PIDS+="${p} "
  fi
done < "$PID_FILE"

read -r -a PID_ARRAY <<< "$ACTIVE_PIDS"
if [ ${#PID_ARRAY[@]} -ge 3 ]; then
  # Kill oldest notification
  kill "${PID_ARRAY[0]}" 2>/dev/null || true
  PID_ARRAY=("${PID_ARRAY[@]:1}")
fi

# 4. Display Notification Card in Upper-Right
if command -v notify-send >/dev/null 2>&1; then
  notify-send -a "$APP" -t "$(( TIMEOUT * 1000 ))" "$TITLE" "$BODY" &
  NEW_PID=$!
elif [ -n "${DISPLAY:-}" ] && command -v st >/dev/null 2>&1; then
  # Position in upper-right corner (width: 44 cols, height: 6 lines)
  (
    st -c "ShreeNotify" -g "44x6-20+36" -t "${APP}" -e /bin/bash -c "
      clear
      echo '┌────────────────────────────────────────────┐'
      printf '│  %-2s %-32s [✕] │\n' '${ICON}' '${APP}: ${TITLE}'
      echo '├────────────────────────────────────────────┤'
      printf '│  %-42s│\n' '${BODY:0:40}'
      if [ -n '${ACTION_LABEL}' ]; then
        printf '│  [Enter: %-18s]  [Esc: Close] │\n' '${ACTION_LABEL}'
      else
        printf '│  (Auto-closing in %ss)         [Esc: Close] │\n' '${TIMEOUT}'
      fi
      echo '└────────────────────────────────────────────┘'
      read -t ${TIMEOUT} -r -s -n 1 KEY || true
      if [ -n '${ACTION_CMD}' ] && [ \"\$KEY\" = \"\" ]; then
        ${ACTION_CMD} &
      fi
    "
  ) &
  NEW_PID=$!
else
  # Terminal / Console fallback
  echo "[${APP}] ${TITLE}: ${BODY}"
  exit 0
fi

# Record pid in active stack
echo "$NEW_PID" >> "$PID_FILE"
