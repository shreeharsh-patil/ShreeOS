#!/usr/bin/env bash
# desktop/scripts/shree-wallpaper.sh — ShreeOS Wallpaper Engine
#
# Manages wallpaper selection, scaling modes (fill, fit, center),
# theme-aware light/dark switching, and persistent user configuration.
#
# Usage:
#   shree-wallpaper set <filepath> [fill|fit|center]
#   shree-wallpaper mode <fill|fit|center>
#   shree-wallpaper auto
#   shree-wallpaper list
#
set -euo pipefail

CONFIG_DIR="${HOME}/.config/shreeos"
WALLPAPER_CONF="${CONFIG_DIR}/wallpaper.conf"
mkdir -p "$CONFIG_DIR"

WALLPAPER_DIRS=(
  "/usr/share/wallpapers"
  "${HOME}/Pictures/Wallpapers"
  "${HOME}/Pictures"
  "${HOME}/Desktop"
  "$(cd "$(dirname "${BASH_SOURCE[0]}")/../../branding/wallpapers" 2>/dev/null && pwd || true)"
)

get_current_wallpaper() {
  if [ -f "$WALLPAPER_CONF" ]; then
    grep -oP '^WALLPAPER=\K.*' "$WALLPAPER_CONF" 2>/dev/null || echo ""
  else
    echo ""
  fi
}

get_current_mode() {
  if [ -f "$WALLPAPER_CONF" ]; then
    grep -oP '^MODE=\K.*' "$WALLPAPER_CONF" 2>/dev/null || echo "fill"
  else
    echo "fill"
  fi
}

apply_wallpaper() {
  local file="$1"
  local mode="${2:-$(get_current_mode)}"

  [ -f "$file" ] || { echo "shree-wallpaper: File not found: ${file}" >&2; return 1; }

  local xwal_flag="--zoom"
  local feh_flag="--bg-fill"

  case "$mode" in
    fit)
      xwal_flag="--maximize"
      feh_flag="--bg-max"
      ;;
    center)
      xwal_flag="--center"
      feh_flag="--bg-center"
      ;;
    fill|*)
      xwal_flag="--zoom"
      feh_flag="--bg-fill"
      mode="fill"
      ;;
  esac

  if command -v xwallpaper >/dev/null 2>&1; then
    xwallpaper "$xwal_flag" "$file"
  elif command -v feh >/dev/null 2>&1; then
    feh "$feh_flag" "$file"
  else
    echo "shree-wallpaper: Neither xwallpaper nor feh is installed." >&2
    return 1
  fi

  cat > "$WALLPAPER_CONF" <<EOF
WALLPAPER=${file}
MODE=${mode}
EOF

  if command -v shree-notify >/dev/null 2>&1; then
    shree-notify "Wallpaper" "Applied $(basename "$file") (${mode})" --app="Desktop"
  fi
}

cmd_auto() {
  local theme="dark"
  if [ -f "${CONFIG_DIR}/theme.conf" ]; then
    theme=$(grep -oP '^THEME=\K.*' "${CONFIG_DIR}/theme.conf" 2>/dev/null || echo "dark")
  fi

  local target="/usr/share/wallpapers/shreeos-calm-${theme}.svg"
  if [ ! -f "$target" ]; then
    target="/usr/share/wallpapers/shreeos-wallpaper.svg"
  fi

  if [ -f "$target" ]; then
    apply_wallpaper "$target" "fill"
  fi
}

cmd_list() {
  echo "Available Wallpapers:"
  for dir in "${WALLPAPER_DIRS[@]}"; do
    [ -d "$dir" ] || continue
    find "$dir" -maxdepth 2 -type f \( -name "*.svg" -o -name "*.png" -o -name "*.jpg" \) 2>/dev/null | while read -r wp; do
      echo "  $(basename "$wp") -> ${wp}"
    done
  done
}

ACTION="${1:-auto}"
shift || true

case "$ACTION" in
  set)
    if [ $# -lt 1 ]; then
      echo "Usage: shree-wallpaper set <filepath> [fill|fit|center]" >&2
      exit 1
    fi
    apply_wallpaper "$1" "${2:-fill}"
    ;;
  mode)
    CUR_WP=$(get_current_wallpaper)
    if [ -n "$CUR_WP" ] && [ -f "$CUR_WP" ]; then
      apply_wallpaper "$CUR_WP" "${1:-fill}"
    else
      cmd_auto
    fi
    ;;
  auto)
    cmd_auto
    ;;
  list)
    cmd_list
    ;;
  current)
    echo "Wallpaper: $(get_current_wallpaper)"
    echo "Mode:      $(get_current_mode)"
    ;;
  *)
    echo "Usage: shree-wallpaper <set <file> [mode] | mode <mode> | auto | list | current>"
    exit 1
    ;;
esac
