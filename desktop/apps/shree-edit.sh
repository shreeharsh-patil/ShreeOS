#!/usr/bin/env bash
# desktop/apps/shree-edit.sh — ShreeOS lightweight text editor launcher
set -euo pipefail

FILE="${1:-}"
TITLE="Editor: $(basename "${FILE:-Untitled}")"

if ! command -v st >/dev/null 2>&1; then
  echo "shree-edit: terminal emulator 'st' is unavailable" >&2
  exit 1
fi

if command -v nano >/dev/null 2>&1; then
  st -g 85x26 -t "$TITLE" -e nano "$FILE" &
elif command -v vim >/dev/null 2>&1; then
  st -g 85x26 -t "$TITLE" -e vim "$FILE" &
else
  st -g 85x26 -t "$TITLE" -e /bin/bash -c '
    file="$1"
    if [ -n "$file" ] && [ -f "$file" ]; then
      cat -- "$file"
      echo
      read -r -p "Press Enter to close." _
    else
      [ -n "$file" ] || file="${HOME}/shree-note.txt"
      printf "Type content, press Ctrl+D when finished to save to %s\n" "$file"
      cat > "$file"
    fi
  ' _ "$FILE" &
fi
