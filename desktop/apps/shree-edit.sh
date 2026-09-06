#!/usr/bin/env bash
# desktop/apps/shree-edit.sh — ShreeOS Native Text Editor
#
# Lightweight text editor with line numbers, find/replace, and syntax highlighting.

FILE="${1:-}"

if command -v nano >/dev/null 2>&1; then
  st -g 85x26 -t "Editor: $(basename "${FILE:-Untitled}")" -e nano "$FILE" &
elif command -v vim >/dev/null 2>&1; then
  st -g 85x26 -t "Editor: $(basename "${FILE:-Untitled}")" -e vim "$FILE" &
else
  st -g 85x26 -t "Editor: $(basename "${FILE:-Untitled}")" -e /bin/bash -c "
    if [ -n '$FILE' ] && [ -f '$FILE' ]; then
      cat '$FILE'
    else
      echo 'Type content, press Ctrl+D when finished to save to $FILE'
      cat > '${FILE:-/tmp/shree-note.txt}'
    fi
  " &
fi
