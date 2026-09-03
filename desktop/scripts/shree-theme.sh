#!/usr/bin/env bash
# desktop/scripts/shree-theme.sh — ShreeOS Dynamic Appearance Manager
#
# Manages system theme switching (Light / Dark / Auto Day-Night 07:00-19:00), updates Xresources,
# wallpaper rendering, and notifies running applications.

set -euo pipefail

CONFIG_DIR="${HOME}/.config/shreeos"
THEME_FILE="${CONFIG_DIR}/theme.conf"
mkdir -p "$CONFIG_DIR"

if [ ! -f "$THEME_FILE" ]; then
  echo "THEME=dark" > "$THEME_FILE"
fi

get_current_theme() {
  grep -oP '^THEME=\K.*' "$THEME_FILE" 2>/dev/null || echo "dark"
}

set_theme() {
  local mode="$1"
  if [ "$mode" = "toggle" ]; then
    local cur
    cur=$(get_current_theme)
    if [ "$cur" = "dark" ]; then mode="light"; else mode="dark"; fi
  elif [ "$mode" = "auto" ]; then
    local hour
    hour=$(date +%H)
    if [ "$hour" -ge 7 ] && [ "$hour" -lt 19 ]; then
      mode="light"
    else
      mode="dark"
    fi
  fi

  echo "THEME=${mode}" > "$THEME_FILE"

  # Generate sourced shell tokens file (~/.config/shreeos/theme-vars.sh)
  local vars_file="${CONFIG_DIR}/theme-vars.sh"
  if [ "$mode" = "light" ]; then
    cat > "$vars_file" <<'EOF'
export SHREE_THEME="light"
export SHREE_BG="#F5F5F7"
export SHREE_SURFACE="#FFFFFF"
export SHREE_SURFACE_SEC="#F5F5F7"
export SHREE_SURFACE_ELEVATED="rgba(255,255,255,0.85)"
export SHREE_TEXT="#1D1D1F"
export SHREE_TEXT_SEC="#6E6E73"
export SHREE_TEXT_MUTED="#86868B"
export SHREE_BORDER="#E5E5EA"
export SHREE_BORDER_ALPHA="rgba(0,0,0,0.10)"
export SHREE_ACCENT="#2878FF"
export SHREE_ACCENT_HOVER="#1A62E8"
EOF
  else
    cat > "$vars_file" <<'EOF'
export SHREE_THEME="dark"
export SHREE_BG="#1C1C1E"
export SHREE_SURFACE="#2C2C2E"
export SHREE_SURFACE_SEC="#1C1C1E"
export SHREE_SURFACE_ELEVATED="rgba(44,44,46,0.88)"
export SHREE_TEXT="#F5F5F7"
export SHREE_TEXT_SEC="#A1A1A6"
export SHREE_TEXT_MUTED="#86868B"
export SHREE_BORDER="#38383A"
export SHREE_BORDER_ALPHA="rgba(255,255,255,0.10)"
export SHREE_ACCENT="#2878FF"
export SHREE_ACCENT_HOVER="#1A62E8"
EOF
  fi
  chmod 644 "$vars_file"

  # Update X11 terminal & system resources
  if command -v xrdb >/dev/null 2>&1; then
    local xres="${CONFIG_DIR}/Xresources.theme"
    if [ "$mode" = "light" ]; then
      cat > "$xres" <<'EOF'
*.foreground:  #1D1D1F
*.background:  #FFFFFF
*.cursorColor: #2878FF
*.color0:      #F5F5F7
*.color8:      #E5E5EA
*.color1:      #E54D2E
*.color9:      #EC6D53
*.color2:      #30A46C
*.color10:     #46B880
*.color3:      #F7B955
*.color11:     #F8CA7B
*.color4:      #2878FF
*.color12:     #5E9BFF
*.color5:      #8E4EC6
*.color13:     #A56DD8
*.color6:      #12A594
*.color14:     #30C0B0
*.color7:      #6E6E73
*.color15:     #1D1D1F
EOF
    else
      cat > "$xres" <<'EOF'
*.foreground:  #F5F5F7
*.background:  #1C1C1E
*.cursorColor: #2878FF
*.color0:      #1C1C1E
*.color8:      #38383A
*.color1:      #E54D2E
*.color9:      #EC6D53
*.color2:      #30A46C
*.color10:     #46B880
*.color3:      #F7B955
*.color11:     #F8CA7B
*.color4:      #2878FF
*.color12:     #5E9BFF
*.color5:      #8E4EC6
*.color13:     #A56DD8
*.color6:      #12A594
*.color14:     #30C0B0
*.color7:      #A1A1A6
*.color15:     #F5F5F7
EOF
    fi
    xrdb -merge "$xres" 2>/dev/null || true
  fi

  # Switch wallpaper if theme-coordinated wallpaper exists
  local wp="/usr/share/wallpapers/shreeos-calm-${mode}.svg"
  if [ -f "$wp" ]; then
    if command -v xwallpaper >/dev/null 2>&1; then
      xwallpaper --zoom "$wp" 2>/dev/null || true
    elif command -v feh >/dev/null 2>&1; then
      feh --bg-fill "$wp" 2>/dev/null || true
    fi
  fi

  # Update X11 root properties
  if command -v xprop >/dev/null 2>&1; then
    xprop -root -format _SHREEOS_THEME 8s -set _SHREEOS_THEME "$mode" 2>/dev/null || true
  fi

  # Notify user if notify helper is available
  if command -v shree-notify >/dev/null 2>&1; then
    shree-notify "Appearance Changed" "Switched to ${mode^} appearance" --app="Settings"
  fi

  echo "ShreeOS theme set to: ${mode}"
}

case "${1:-status}" in
  dark|light|auto|toggle)
    set_theme "$1"
    ;;
  get|status)
    get_current_theme
    ;;
  *)
    echo "Usage: shree-theme [dark|light|auto|toggle|get]"
    exit 1
    ;;
esac
