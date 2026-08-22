#!/usr/bin/env bash
# desktop/apps/shree-quicklook.sh — ShreeOS Quick Look Preview
#
# Modular preview generator for images, text files, archives, and directories.

set -euo pipefail

TARGET="${1:-}"
[ -z "$TARGET" ] && exit 0

if [ -d "$TARGET" ]; then
  COUNT=$(find "$TARGET" -maxdepth 1 | wc -l)
  SIZE=$(du -sh "$TARGET" 2>/dev/null | awk '{print $1}')
  shree-notify "Quick Look: Directory" "Folder: $(basename "$TARGET")\nContains: ${COUNT} item(s)\nSize on disk: ${SIZE}" --app="Files"
  exit 0
fi

MIME_TYPE=$(file --mime-type -b "$TARGET" 2>/dev/null || echo "text/plain")

case "$MIME_TYPE" in
  image/*)
    if command -v feh >/dev/null 2>&1; then
      feh --scale-down --geometry 640x480 "$TARGET" &
    elif command -v shree-view >/dev/null 2>&1; then
      shree-view "$TARGET" &
    else
      DIM=$(file "$TARGET" | awk -F', ' '{print $2}')
      shree-notify "Quick Look: Image" "$(basename "$TARGET")\n${DIM}" --app="Preview"
    fi
    ;;
  text/*|application/json|application/xml|application/x-sh)
    st -g 75x20 -t "Quick Look: $(basename "$TARGET")" -e /bin/bash -c "
      head -n 30 '$TARGET'
      echo ''
      echo '─── End of preview (Press Enter to close) ───'
      read -r
    " &
    ;;
  application/zip|application/x-tar|application/gzip|application/x-xz)
    st -g 75x20 -t "Quick Look: Archive" -e /bin/bash -c "
      echo 'Contents of $(basename "$TARGET"):'
      tar -tf '$TARGET' 2>/dev/null || unzip -l '$TARGET' 2>/dev/null || echo 'Archive preview unavailable'
      echo ''
      echo '─── Press Enter to close ───'
      read -r
    " &
    ;;
  *)
    SZ=$(du -h "$TARGET" 2>/dev/null | awk '{print $1}')
    shree-notify "Quick Look" "$(basename "$TARGET")\nType: ${MIME_TYPE}\nSize: ${SZ}" --app="Files"
    ;;
esac
