#!/usr/bin/env bash
# desktop/scripts/shree-theme.sh — ShreeOS Dynamic Appearance Manager
set -euo pipefail

CONFIG_DIR="${HOME}/.config/shreeos"
THEME_FILE="${CONFIG_DIR}/theme.conf"
TOKENS_FILE="/etc/shreeos/tokens.conf"
mkdir -p "$CONFIG_DIR"

if [ -r "$TOKENS_FILE" ]; then
  # shellcheck source=/dev/null
  source "$TOKENS_FILE"
fi

: "${SHREE_DARK_DESKTOP_BG:=#1C1C1E}"
: "${SHREE_DARK_SURFACE_PRIMARY:=#2C2C2E}"
: "${SHREE_DARK_SURFACE_SECONDARY:=#1C1C1E}"
: "${SHREE_DARK_SURFACE_ELEVATED:=rgba(44,44,46,0.88)}"
: "${SHREE_DARK_TEXT_PRIMARY:=#F5F5F7}"
: "${SHREE_DARK_TEXT_SECONDARY:=#A1A1A6}"
: "${SHREE_DARK_TEXT_MUTED:=#86868B}"
: "${SHREE_DARK_BORDER_HEX:=#38383A}"
: "${SHREE_LIGHT_DESKTOP_BG:=#F5F5F7}"
: "${SHREE_LIGHT_SURFACE_PRIMARY:=#FFFFFF}"
: "${SHREE_LIGHT_SURFACE_SECONDARY:=#F5F5F7}"
: "${SHREE_LIGHT_SURFACE_ELEVATED:=rgba(255,255,255,0.85)}"
: "${SHREE_LIGHT_TEXT_PRIMARY:=#1D1D1F}"
: "${SHREE_LIGHT_TEXT_SECONDARY:=#6E6E73}"
: "${SHREE_LIGHT_TEXT_MUTED:=#86868B}"
: "${SHREE_LIGHT_BORDER_HEX:=#E5E5EA}"
: "${SHREE_ACCENT:=#2878FF}"
: "${SHREE_ACCENT_HOVER:=#1A62E8}"
: "${SHREE_SUCCESS:=#30A46C}"
: "${SHREE_WARNING:=#F7B955}"
: "${SHREE_ERROR:=#E54D2E}"

read_state() {
  local key="$1"
  sed -n "s/^${key}=//p" "$THEME_FILE" 2>/dev/null | head -n1
}

get_current_theme() {
  local value
  value=$(read_state THEME)
  case "$value" in dark|light) printf '%s\n' "$value" ;; *) printf 'dark\n' ;; esac
}

get_mode() {
  local value
  value=$(read_state MODE)
  if [ -z "$value" ]; then value=$(get_current_theme); fi
  case "$value" in dark|light|auto) printf '%s\n' "$value" ;; *) printf 'dark\n' ;; esac
}

resolve_auto_theme() {
  local hour
  hour=$(date +%H)
  hour=$((10#$hour))
  if [ "$hour" -ge 7 ] && [ "$hour" -lt 19 ]; then
    printf 'light\n'
  else
    printf 'dark\n'
  fi
}

write_state() {
  local mode="$1" effective="$2" tmp="${THEME_FILE}.tmp"
  printf 'MODE=%s\nTHEME=%s\n' "$mode" "$effective" > "$tmp"
  mv "$tmp" "$THEME_FILE"
}

write_theme_vars() {
  local mode="$1"
  local bg surface surface_sec elevated text text_sec muted border
  if [ "$mode" = "light" ]; then
    bg="$SHREE_LIGHT_DESKTOP_BG"; surface="$SHREE_LIGHT_SURFACE_PRIMARY"; surface_sec="$SHREE_LIGHT_SURFACE_SECONDARY"
    elevated="$SHREE_LIGHT_SURFACE_ELEVATED"; text="$SHREE_LIGHT_TEXT_PRIMARY"; text_sec="$SHREE_LIGHT_TEXT_SECONDARY"
    muted="$SHREE_LIGHT_TEXT_MUTED"; border="$SHREE_LIGHT_BORDER_HEX"
  else
    bg="$SHREE_DARK_DESKTOP_BG"; surface="$SHREE_DARK_SURFACE_PRIMARY"; surface_sec="$SHREE_DARK_SURFACE_SECONDARY"
    elevated="$SHREE_DARK_SURFACE_ELEVATED"; text="$SHREE_DARK_TEXT_PRIMARY"; text_sec="$SHREE_DARK_TEXT_SECONDARY"
    muted="$SHREE_DARK_TEXT_MUTED"; border="$SHREE_DARK_BORDER_HEX"
  fi

  cat > "${CONFIG_DIR}/theme-vars.sh" <<EOF
export SHREE_THEME="$mode"
export SHREE_BG="$bg"
export SHREE_SURFACE="$surface"
export SHREE_SURFACE_SEC="$surface_sec"
export SHREE_SURFACE_ELEVATED="$elevated"
export SHREE_TEXT="$text"
export SHREE_TEXT_SEC="$text_sec"
export SHREE_TEXT_MUTED="$muted"
export SHREE_BORDER="$border"
export SHREE_ACCENT="$SHREE_ACCENT"
export SHREE_ACCENT_HOVER="$SHREE_ACCENT_HOVER"
EOF
  chmod 644 "${CONFIG_DIR}/theme-vars.sh"
}

write_xresources() {
  local mode="$1" fg bg muted border
  if [ "$mode" = "light" ]; then
    fg="$SHREE_LIGHT_TEXT_PRIMARY"; bg="$SHREE_LIGHT_SURFACE_PRIMARY"; muted="$SHREE_LIGHT_TEXT_SECONDARY"; border="$SHREE_LIGHT_BORDER_HEX"
  else
    fg="$SHREE_DARK_TEXT_PRIMARY"; bg="$SHREE_DARK_DESKTOP_BG"; muted="$SHREE_DARK_TEXT_SECONDARY"; border="$SHREE_DARK_BORDER_HEX"
  fi

  cat > "${CONFIG_DIR}/Xresources.theme" <<EOF
*.foreground:  $fg
*.background:  $bg
*.cursorColor: $SHREE_ACCENT
*.color0:      $bg
*.color8:      $border
*.color1:      $SHREE_ERROR
*.color9:      $SHREE_ERROR
*.color2:      $SHREE_SUCCESS
*.color10:     $SHREE_SUCCESS
*.color3:      $SHREE_WARNING
*.color11:     $SHREE_WARNING
*.color4:      $SHREE_ACCENT
*.color12:     #5E9BFF
*.color5:      #8E4EC6
*.color13:     #A56DD8
*.color6:      #12A594
*.color14:     #30C0B0
*.color7:      $muted
*.color15:     $fg
EOF

  if command -v xrdb >/dev/null 2>&1 && [ -n "${DISPLAY:-}" ]; then
    xrdb -merge "${CONFIG_DIR}/Xresources.theme" 2>/dev/null || true
  fi
}

apply_theme() {
  local effective="$1" notify="${2:-true}"
  write_theme_vars "$effective"
  write_xresources "$effective"

  local wp="/usr/share/wallpapers/shreeos-calm-${effective}.svg"
  if [ -f "$wp" ] && [ -n "${DISPLAY:-}" ]; then
    if command -v xwallpaper >/dev/null 2>&1; then
      xwallpaper --zoom "$wp" >/dev/null 2>&1 || true
    elif command -v feh >/dev/null 2>&1; then
      feh --bg-fill "$wp" >/dev/null 2>&1 || true
    fi
  fi

  if command -v xprop >/dev/null 2>&1 && [ -n "${DISPLAY:-}" ]; then
    xprop -root -format _SHREEOS_THEME 8s -set _SHREEOS_THEME "$effective" >/dev/null 2>&1 || true
  fi

  if [ "$notify" = true ] && command -v shree-notify >/dev/null 2>&1; then
    shree-notify "Appearance Changed" "Switched to ${effective^} appearance" --app="Settings"
  fi
}

set_theme() {
  local requested="$1" mode effective current
  current=$(get_current_theme)

  case "$requested" in
    toggle)
      if [ "$current" = "dark" ]; then mode="light"; else mode="dark"; fi
      effective="$mode"
      ;;
    auto)
      mode="auto"
      effective=$(resolve_auto_theme)
      ;;
    dark|light)
      mode="$requested"
      effective="$requested"
      ;;
    *)
      printf 'Invalid theme mode: %s\n' "$requested" >&2
      return 1
      ;;
  esac

  write_state "$mode" "$effective"
  apply_theme "$effective"
  printf 'ShreeOS theme: %s (mode: %s)\n' "$effective" "$mode"
}

refresh_theme() {
  local mode effective old
  mode=$(get_mode)
  old=$(get_current_theme)
  if [ "$mode" = "auto" ]; then effective=$(resolve_auto_theme); else effective="$mode"; fi
  write_state "$mode" "$effective"
  apply_theme "$effective" "$([ "$old" = "$effective" ] && printf false || printf true)"
}

watch_theme() {
  trap 'exit 0' INT TERM
  refresh_theme >/dev/null 2>&1 || true
  while true; do
    sleep 300
    refresh_theme >/dev/null 2>&1 || true
  done
}

if [ ! -f "$THEME_FILE" ]; then
  write_state dark dark
fi

case "${1:-status}" in
  dark|light|auto|toggle) set_theme "$1" ;;
  get|status)             get_current_theme ;;
  mode)                   get_mode ;;
  refresh)                refresh_theme ;;
  watch)                  watch_theme ;;
  *)
    echo "Usage: shree-theme [dark|light|auto|toggle|get|mode|refresh|watch]"
    exit 1
    ;;
esac
