#!/usr/bin/env bash
# desktop/scripts/shree-clipboard.sh — ShreeOS Clipboard History Manager
#
# Shortcut: Super + V
# Records, searches, and pastes from recent clipboard history buffer.

set -euo pipefail

HIST_FILE="${HOME}/.local/share/shreeos/clipboard.hist"
mkdir -p "$(dirname "$HIST_FILE")"

# Record current clipboard content if new
if command -v xclip >/dev/null 2>&1; then
  CURRENT=$(xclip -selection clipboard -o 2>/dev/null || true)
  if [ -n "$CURRENT" ] && ! grep -Fxq "$CURRENT" "$HIST_FILE" 2>/dev/null; then
    echo "$CURRENT" >> "$HIST_FILE"
    tail -n 30 "$HIST_FILE" > "${HIST_FILE}.tmp" 2>/dev/null && mv "${HIST_FILE}.tmp" "$HIST_FILE" 2>/dev/null || true
  fi
fi

if [ ! -f "$HIST_FILE" ] || [ ! -s "$HIST_FILE" ]; then
  shree-notify "Clipboard" "Clipboard history is empty" --app="System"
  exit 0
fi

MENU="[Clear Clipboard History]\n$(tac "$HIST_FILE")"
SELECTED=$(echo -e "$MENU" | dmenu -p "Clipboard History (Super+V)" -l 8 -c)

[ -z "$SELECTED" ] && exit 0

if [ "$SELECTED" = "[Clear Clipboard History]" ]; then
  > "$HIST_FILE"
  shree-notify "Clipboard" "Clipboard history cleared" --app="System"
else
  if command -v xclip >/dev/null 2>&1; then
    echo -n "$SELECTED" | xclip -selection clipboard -i
    shree-notify "Clipboard" "Copied item to active clipboard" --app="System"
  fi
fi
