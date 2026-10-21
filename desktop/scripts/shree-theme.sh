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

: "${SHREE_THEME_MODE:=dark}"
: "${SHREE_DARK_DESKTOP_BG:=#19191B}"
: "${SHREE_DARK_SURFACE_PRIMARY:=#252527}"
: "${SHREE_DARK_SURFACE_SECONDARY:=#1E1E20}"
: "${SHREE_DARK_SURFACE_ELEVATED:=rgba(37,37,39,0.88)}"
: "${SHREE_DARK_TEXT_PRIMARY:=#F5F5F7}"
: "${SHREE_DARK_TEXT_SECONDARY:=#A1A1A6}"
: "${SHREE_DARK_TEXT_MUTED:=#86868B}"
: "${SHREE_DARK_BORDER_HEX:=#38383A}"
: "${SHREE_DARK_BORDER:=rgba(255,255,255,0.12)}"
: "${SHREE_LIGHT_DESKTOP_BG:=#F4EFE9}"
: "${SHREE_LIGHT_SURFACE_PRIMARY:=#FFFDFA}"
: "${SHREE_LIGHT_SURFACE_SECONDARY:=#F6F1EC}"
: "${SHREE_LIGHT_SURFACE_ELEVATED:=rgba(255,253,250,0.88)}"
: "${SHREE_LIGHT_TEXT_PRIMARY:=#1D1D1F}"
: "${SHREE_LIGHT_TEXT_SECONDARY:=#6E6E73}"
: "${SHREE_LIGHT_TEXT_MUTED:=#86868B}"
: "${SHREE_LIGHT_BORDER_HEX:=#E5E5EA}"
: "${SHREE_LIGHT_BORDER:=rgba(45,39,34,0.10)}"
: "${SHREE_ACCENT:=#2878FF}"
: "${SHREE_ACCENT_LIGHT:=#5E9BFF}"
: "${SHREE_ACCENT_HOVER:=#1A62E8}"
: "${SHREE_ACCENT_MUTED:=rgba(40,120,255,0.18)}"
: "${SHREE_SUCCESS:=#30A46C}"
: "${SHREE_WARNING:=#F7B955}"
: "${SHREE_ERROR:=#E54D2E}"
: "${SHREE_GLASS_OPACITY_CLEAR:=0.54}"
: "${SHREE_GLASS_OPACITY_TINTED:=0.88}"
: "${SHREE_GLASS_OPACITY:=0.88}"
: "${SHREE_GLASS_BLUR:=22}"
: "${SHREE_GLASS_SATURATION:=1.45}"
: "${SHREE_RADIUS_WINDOW:=12}"
: "${SHREE_RADIUS_CONTROL:=9}"
: "${SHREE_RADIUS_DOCK:=16}"
: "${SHREE_RADIUS_MENU:=12}"
: "${SHREE_RADIUS_AVATAR:=9999}"
: "${SHREE_SPACE_XS:=4}"
: "${SHREE_SPACE_SM:=8}"
: "${SHREE_SPACE_MD:=12}"
: "${SHREE_SPACE_LG:=16}"
: "${SHREE_SPACE_XL:=24}"
: "${SHREE_SPACE_2XL:=32}"
: "${SHREE_FONT_UI:=Inter}"
: "${SHREE_FONT_MONO:=JetBrains Mono}"
: "${SHREE_FONT_SIZE_TITLE:=20}"
: "${SHREE_FONT_SIZE_SECTION:=16}"
: "${SHREE_FONT_SIZE_UI:=13}"
: "${SHREE_FONT_SIZE_SM:=11}"
: "${SHREE_DOCK_HEIGHT:=64}"
: "${SHREE_DOCK_ICON_SIZE:=50}"
: "${SHREE_TOPBAR_HEIGHT:=28}"
: "${SHREE_ANIM_FAST:=120ms}"
: "${SHREE_ANIM_NORMAL:=180ms}"
: "${SHREE_ANIM_SLOW:=240ms}"
: "${SHREE_ANIM_CURVE:=cubic-bezier(0.16, 1, 0.3, 1)}"

read_state() {
  local key="$1"
  sed -n "s/^${key}=//p" "$THEME_FILE" 2>/dev/null | head -n1
}

get_current_theme() {
  local value
  value=$(read_state THEME)
  case "$value" in
    dark|light) printf '%s\n' "$value" ;;
    *) case "$SHREE_THEME_MODE" in light) printf 'light\n' ;; *) printf 'dark\n' ;; esac ;;
  esac
}

get_mode() {
  local value
  value=$(read_state MODE)
  if [ -z "$value" ]; then value=$(get_current_theme); fi
  case "$value" in
    dark|light|auto) printf '%s\n' "$value" ;;
    *) case "$SHREE_THEME_MODE" in light|auto) printf '%s\n' "$SHREE_THEME_MODE" ;; *) printf 'dark\n' ;; esac ;;
  esac
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
  local mode="$1" effective="$2"
  local bg surface surface_sec elevated text text_sec muted border border_rgba
  if [ "$effective" = "light" ]; then
    bg="$SHREE_LIGHT_DESKTOP_BG"; surface="$SHREE_LIGHT_SURFACE_PRIMARY"; surface_sec="$SHREE_LIGHT_SURFACE_SECONDARY"
    elevated="$SHREE_LIGHT_SURFACE_ELEVATED"; text="$SHREE_LIGHT_TEXT_PRIMARY"; text_sec="$SHREE_LIGHT_TEXT_SECONDARY"
    muted="$SHREE_LIGHT_TEXT_MUTED"; border="$SHREE_LIGHT_BORDER_HEX"; border_rgba="$SHREE_LIGHT_BORDER"
  else
    bg="$SHREE_DARK_DESKTOP_BG"; surface="$SHREE_DARK_SURFACE_PRIMARY"; surface_sec="$SHREE_DARK_SURFACE_SECONDARY"
    elevated="$SHREE_DARK_SURFACE_ELEVATED"; text="$SHREE_DARK_TEXT_PRIMARY"; text_sec="$SHREE_DARK_TEXT_SECONDARY"
    muted="$SHREE_DARK_TEXT_MUTED"; border="$SHREE_DARK_BORDER_HEX"; border_rgba="$SHREE_DARK_BORDER"
  fi

  cat > "${CONFIG_DIR}/theme-vars.sh" <<EOF
export SHREE_THEME="$effective"
export SHREE_THEME_MODE="$mode"
export SHREE_BG="$bg"
export SHREE_SURFACE="$surface"
export SHREE_SURFACE_SEC="$surface_sec"
export SHREE_SURFACE_ELEVATED="$elevated"
export SHREE_TEXT="$text"
export SHREE_TEXT_SEC="$text_sec"
export SHREE_TEXT_MUTED="$muted"
export SHREE_BORDER="$border"
export SHREE_BORDER_RGBA="$border_rgba"
export SHREE_ACCENT="$SHREE_ACCENT"
export SHREE_ACCENT_LIGHT="$SHREE_ACCENT_LIGHT"
export SHREE_ACCENT_HOVER="$SHREE_ACCENT_HOVER"
export SHREE_ACCENT_MUTED="$SHREE_ACCENT_MUTED"
export SHREE_SUCCESS="$SHREE_SUCCESS"
export SHREE_WARNING="$SHREE_WARNING"
export SHREE_ERROR="$SHREE_ERROR"
export SHREE_GLASS_OPACITY_CLEAR="$SHREE_GLASS_OPACITY_CLEAR"
export SHREE_GLASS_OPACITY_TINTED="$SHREE_GLASS_OPACITY_TINTED"
export SHREE_GLASS_OPACITY="$SHREE_GLASS_OPACITY"
export SHREE_GLASS_BLUR="$SHREE_GLASS_BLUR"
export SHREE_GLASS_SATURATION="$SHREE_GLASS_SATURATION"
export SHREE_RADIUS_WINDOW="$SHREE_RADIUS_WINDOW"
export SHREE_RADIUS_CONTROL="$SHREE_RADIUS_CONTROL"
export SHREE_RADIUS_DOCK="$SHREE_RADIUS_DOCK"
export SHREE_RADIUS_MENU="$SHREE_RADIUS_MENU"
export SHREE_RADIUS_AVATAR="$SHREE_RADIUS_AVATAR"
export SHREE_SPACE_XS="$SHREE_SPACE_XS"
export SHREE_SPACE_SM="$SHREE_SPACE_SM"
export SHREE_SPACE_MD="$SHREE_SPACE_MD"
export SHREE_SPACE_LG="$SHREE_SPACE_LG"
export SHREE_SPACE_XL="$SHREE_SPACE_XL"
export SHREE_SPACE_2XL="$SHREE_SPACE_2XL"
export SHREE_FONT_UI="$SHREE_FONT_UI"
export SHREE_FONT_MONO="$SHREE_FONT_MONO"
export SHREE_FONT_SIZE_TITLE="$SHREE_FONT_SIZE_TITLE"
export SHREE_FONT_SIZE_SECTION="$SHREE_FONT_SIZE_SECTION"
export SHREE_FONT_SIZE_UI="$SHREE_FONT_SIZE_UI"
export SHREE_FONT_SIZE_SM="$SHREE_FONT_SIZE_SM"
export SHREE_DOCK_HEIGHT="$SHREE_DOCK_HEIGHT"
export SHREE_DOCK_ICON_SIZE="$SHREE_DOCK_ICON_SIZE"
export SHREE_TOPBAR_HEIGHT="$SHREE_TOPBAR_HEIGHT"
export SHREE_ANIM_FAST="$SHREE_ANIM_FAST"
export SHREE_ANIM_NORMAL="$SHREE_ANIM_NORMAL"
export SHREE_ANIM_SLOW="$SHREE_ANIM_SLOW"
export SHREE_ANIM_CURVE="$SHREE_ANIM_CURVE"
EOF
  chmod 644 "${CONFIG_DIR}/theme-vars.sh"
}

write_xresources() {
  local mode="$1" fg bg surface_sec muted border dmenu_font
  if [ "$mode" = "light" ]; then
    fg="$SHREE_LIGHT_TEXT_PRIMARY"; bg="$SHREE_LIGHT_SURFACE_PRIMARY"; surface_sec="$SHREE_LIGHT_SURFACE_SECONDARY"
    muted="$SHREE_LIGHT_TEXT_SECONDARY"; border="$SHREE_LIGHT_BORDER_HEX"
  else
    fg="$SHREE_DARK_TEXT_PRIMARY"; bg="$SHREE_DARK_DESKTOP_BG"; surface_sec="$SHREE_DARK_SURFACE_SECONDARY"
    muted="$SHREE_DARK_TEXT_SECONDARY"; border="$SHREE_DARK_BORDER_HEX"
  fi
  dmenu_font="${SHREE_FONT_UI}:size=${SHREE_FONT_SIZE_UI}:weight=medium:antialias=true:autohint=true"

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
dmenu.normbg:  $surface_sec
dmenu.normfg:  $fg
dmenu.selbg:   $SHREE_ACCENT
dmenu.selfg:   #FFFFFF
dmenu.font:    $dmenu_font
EOF

  if command -v xrdb >/dev/null 2>&1 && [ -n "${DISPLAY:-}" ]; then
    xrdb -merge "${CONFIG_DIR}/Xresources.theme" 2>/dev/null || true
  fi
}

apply_theme() {
  local effective="$1" notify="${2:-true}" mode="${3:-$1}"
  write_theme_vars "$mode" "$effective"
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
  apply_theme "$effective" true "$mode"
  printf 'ShreeOS theme: %s (mode: %s)\n' "$effective" "$mode"
}

refresh_theme() {
  local mode effective old
  mode=$(get_mode)
  old=$(get_current_theme)
  if [ "$mode" = "auto" ]; then effective=$(resolve_auto_theme); else effective="$mode"; fi
  write_state "$mode" "$effective"
  apply_theme "$effective" "$([ "$old" = "$effective" ] && printf false || printf true)" "$mode"
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
  initial_mode="$SHREE_THEME_MODE"
  case "$initial_mode" in dark|light|auto) ;; *) initial_mode=dark ;; esac
  if [ "$initial_mode" = auto ]; then initial_theme=$(resolve_auto_theme); else initial_theme="$initial_mode"; fi
  write_state "$initial_mode" "$initial_theme"
  apply_theme "$initial_theme" false "$initial_mode"
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
