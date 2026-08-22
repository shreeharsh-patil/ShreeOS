#!/usr/bin/env bash
# desktop/scripts/shree-clipboard.sh — ShreeOS Clipboard History Manager & Daemon
#
# Shortcut: Super + V
# Modes:
#   shree-clipboard          -> Interactive search and paste
#   shree-clipboard --daemon -> Continuous background clipboard history logger

set -euo pipefail

HIST_FILE="${HOME}/.local/share/shreeos/clipboard.hist"
mkdir -p "$(dirname "$HIST_FILE")"
touch "$HIST_FILE"

run_daemon() {
  local last_clip=""
  while true; do
    if command -v xclip >/dev/null 2>&1; then
      local cur_clip
      cur_clip=$(xclip -selection clipboard -o 2>/dev/null || true)
      if [ -n "$cur_clip" ] && [ "$cur_clip" != "$last_clip" ]; then
        # Avoid recording single space or passwords if flagged
        if [ ${#cur_clip} -gt 1 ]; then
          # Prepend or record without duplicate consecutive
          echo "$cur_clip" >> "$HIST_FILE"
          tail -n 50 "$HIST_FILE" > "${HIST_FILE}.tmp" 2>/dev/null && mv "${HIST_FILE}.tmp" "$HIST_FILE" 2>/dev/null || true
          last_clip="$cur_clip"
        fi
      fi
    fi
    sleep 1
  done
}

run_interactive() {
  # Sync current active clipboard first
  if command -v xclip >/dev/null 2>&1; then
    local current
    current=$(xclip -selection clipboard -o 2>/dev/null || true)
    if [ -n "$current" ] && ! grep -Fxq "$current" "$HIST_FILE" 2>/dev/null; then
      echo "$current" >> "$HIST_FILE"
    fi
  fi

  if [ ! -s "$HIST_FILE" ]; then
    shree-notify "Clipboard" "Clipboard history is currently empty" --app="System"
    exit 0
  fi

  local menu="[Clear Clipboard History]\n$(tac "$HIST_FILE")"
  local selected
  selected=$(echo -e "$menu" | dmenu -p "Clipboard History (Super+V)" -l 8 -c)

  [ -z "$selected" ] && exit 0

  if [ "$selected" = "[Clear Clipboard History]" ]; then
    > "$HIST_FILE"
    shree-notify "Clipboard" "Clipboard history cleared" --app="System"
  else
    if command -v xclip >/dev/null 2>&1; then
      echo -n "$selected" | xclip -selection clipboard -i
      shree-notify "Clipboard" "Copied item to active clipboard" --app="System"
    fi
  fi
}

case "${1:-interactive}" in
  --daemon|daemon)
    run_daemon
    ;;
  interactive|*)
    run_interactive
    ;;
esac
