#!/usr/bin/env bash
# desktop/scripts/shree-notify.sh — ShreeOS Notification Engine & Dispatcher
#
# Usage:
#   shree-notify "Title" "Message body" [--app="AppName"] [--icon="Icon"] [--urgent]
#
# Supports:
#   - Do Not Disturb state check
#   - Notification Center logging (~/.local/share/shreeos/notifications.log)
#   - OSD popup banner
#   - Freedesktop / notify-send compatibility

set -euo pipefail

TITLE="${1:-Notification}"
BODY="${2:-}"
APP="System"
ICON="about"
URGENT=false

shift 2 2>/dev/null || true

while [ $# -gt 0 ]; do
  case "$1" in
    --app=*) APP="${1#*=}" ;;
    --icon=*) ICON="${1#*=}" ;;
    --urgent) URGENT=true ;;
  esac
  shift
done

# 1. Check Do Not Disturb state
CONFIG_DIR="${HOME}/.config/shreeos"
DND_FILE="${CONFIG_DIR}/dnd.state"
if [ -f "$DND_FILE" ] && [ "$(cat "$DND_FILE")" = "on" ] && [ "$URGENT" = false ]; then
  # DND active: Log notification to history without popping up
  LOG_DIR="${HOME}/.local/share/shreeos"
  mkdir -p "$LOG_DIR"
  echo "$(date +%s)|${APP}|${TITLE}|${BODY}|silent" >> "${LOG_DIR}/notifications.log"
  exit 0
fi

# 2. Append to Notification History Log
LOG_DIR="${HOME}/.local/share/shreeos"
mkdir -p "$LOG_DIR"
echo "$(date +%s)|${APP}|${TITLE}|${BODY}|displayed" >> "${LOG_DIR}/notifications.log"

# Keep last 50 notifications
tail -n 50 "${LOG_DIR}/notifications.log" > "${LOG_DIR}/notifications.log.tmp" 2>/dev/null && mv "${LOG_DIR}/notifications.log.tmp" "${LOG_DIR}/notifications.log" 2>/dev/null || true

# 3. Display Notification
if command -v notify-send >/dev/null 2>&1; then
  notify-send -a "$APP" "$TITLE" "$BODY"
elif command -v zenity >/dev/null 2>&1; then
  zenity --notification --text="${APP}: ${TITLE}\n${BODY}" 2>/dev/null || true
else
  # Fallback to console / top bar echo
  echo "[Notification] [${APP}] ${TITLE}: ${BODY}"
fi
