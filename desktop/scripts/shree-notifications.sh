#!/usr/bin/env bash
# desktop/scripts/shree-notifications.sh — ShreeOS Notification Center
#
# Lists recent notifications, timestamps, application sources, and clear options.

LOG_FILE="${HOME}/.local/share/shreeos/notifications.log"

if [ ! -f "$LOG_FILE" ] || [ ! -s "$LOG_FILE" ]; then
  CHOICE=$(printf "No recent notifications\n[Close]" | dmenu -p "Notification Center" -l 2 -c)
  exit 0
fi

ENTRIES="[Clear All Notifications]\n"

while IFS='|' read -r timestamp app title body status; do
  [ -z "$timestamp" ] && continue
  TIME_STR=$(date -d "@${timestamp}" +"%H:%M" 2>/dev/null || date +"%H:%M")
  ENTRIES+="${TIME_STR} [${app}] ${title}: ${body}\n"
done < <(tac "$LOG_FILE" 2>/dev/null || cat "$LOG_FILE")

SELECTED=$(echo -e "$ENTRIES" | dmenu -p "Notification Center" -l 8 -c)

if [ "$SELECTED" = "[Clear All Notifications]" ]; then
  > "$LOG_FILE"
  if command -v shree-notify >/dev/null 2>&1; then
    shree-notify "Notification Center" "All notifications cleared" --app="System"
  fi
fi
