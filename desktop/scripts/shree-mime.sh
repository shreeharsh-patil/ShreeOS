#!/usr/bin/env bash
# desktop/scripts/shree-mime.sh — ShreeOS Default Application & MIME Association Manager
#
# Manages default associations for text files, images, archives, terminal, and browser.

set -euo pipefail

MIME_DIR="${HOME}/.config"
MIME_FILE="${MIME_DIR}/mimeapps.list"
mkdir -p "$MIME_DIR"

if [ ! -f "$MIME_FILE" ]; then
  cat > "$MIME_FILE" <<'EOF'
[Default Applications]
text/plain=shree-edit.desktop
text/markdown=shree-edit.desktop
application/json=shree-edit.desktop
image/png=shree-view.desktop
image/jpeg=shree-view.desktop
image/svg+xml=shree-view.desktop
application/zip=shree-archive.desktop
application/x-tar=shree-archive.desktop
x-scheme-handler/http=shree-browser.desktop
x-scheme-handler/https=shree-browser.desktop
EOF
fi

get_default() {
  local type="$1"
  grep -oP "^${type}=\\K.*" "$MIME_FILE" 2>/dev/null || echo "default"
}

set_default() {
  local type="$1"
  local app="$2"
  if grep -q "^${type}=" "$MIME_FILE" 2>/dev/null; then
    sed -i "s|^${type}=.*|${type}=${app}|" "$MIME_FILE"
  else
    echo "${type}=${app}" >> "$MIME_FILE"
  fi
  if command -v shree-notify >/dev/null 2>&1; then
    shree-notify "Default Applications" "Updated handler for ${type} to ${app}" --app="Settings"
  fi
}

case "${1:-get}" in
  get) get_default "${2:-text/plain}" ;;
  set) set_default "${2:-text/plain}" "${3:-shree-edit.desktop}" ;;
  *) echo "Usage: shree-mime.sh [get <type> | set <type> <app.desktop>]" ;;
esac
