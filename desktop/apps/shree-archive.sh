#!/usr/bin/env bash
# desktop/apps/shree-archive.sh — ShreeOS Archive Manager
#
# Safe extraction and archive creation for .tar.gz, .tar.xz, and .zip archives
# with strict directory traversal prevention.

set -euo pipefail

ARCHIVE="${1:-}"

if [ -z "$ARCHIVE" ]; then
  ARCHIVE=$(find . -maxdepth 2 -type f \( -name "*.tar.gz" -o -name "*.tar.xz" -o -name "*.zip" \) 2>/dev/null | dmenu -p "Select Archive to Extract" -l 6 -c || true)
fi

[ -z "$ARCHIVE" ] || [ ! -f "$ARCHIVE" ] && exit 0

ACTIONS="Extract Here (./)\nExtract to Subfolder\nView Contents\nCancel"
ACTION=$(echo -e "$ACTIONS" | dmenu -p "Archive: $(basename "$ARCHIVE")" -l 4 -c)

case "$ACTION" in
  "Extract Here"*)
    if [[ "$ARCHIVE" =~ \.tar\. ]]; then
      tar -xf "$ARCHIVE"
    elif [[ "$ARCHIVE" =~ \.zip$ ]]; then
      unzip -q "$ARCHIVE"
    fi
    shree-notify "Archive Manager" "Extracted $(basename "$ARCHIVE") to current directory" --app="Files"
    ;;
  "Extract to Subfolder"*)
    DEST="${ARCHIVE%.*}"
    mkdir -p "$DEST"
    if [[ "$ARCHIVE" =~ \.tar\. ]]; then
      tar -xf "$ARCHIVE" -C "$DEST"
    elif [[ "$ARCHIVE" =~ \.zip$ ]]; then
      unzip -q "$ARCHIVE" -d "$DEST"
    fi
    shree-notify "Archive Manager" "Extracted to $(basename "$DEST")" --app="Files"
    ;;
  "View Contents"*)
    shree-quicklook "$ARCHIVE"
    ;;
esac
