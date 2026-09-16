#!/usr/bin/env bash
# desktop/scripts/shree-dock.sh — ShreeOS Bottom Application Dock
#
# Floating, centered translucent application dock with pinned apps,
# running process indicators, fast click-to-launch, and window focus.

CONFIG_DIR="${HOME}/.config/shreeos"
DOCK_CONF="${CONFIG_DIR}/dock.conf"
mkdir -p "$CONFIG_DIR"

if [ ! -f "$DOCK_CONF" ]; then
  cat > "$DOCK_CONF" <<EOF
AUTOHIDE=false
POSITION=bottom
PINNED_APPS="shree-files:st:shree-apps:shree-edit:shree-sysmon:shree-settings"
EOF
fi

# App metadata definition: executable -> label & icon
declare -A APP_NAMES
APP_NAMES["shree-files"]="Files"
APP_NAMES["st"]="Terminal"
APP_NAMES["shree-apps"]="App Center"
APP_NAMES["shree-edit"]="Text Editor"
APP_NAMES["shree-sysmon"]="System Monitor"
APP_NAMES["shree-settings"]="Settings"
APP_NAMES["shree-about"]="About ShreeOS"

get_running_indicator() {
  local binary="$1"
  if pgrep -x "$binary" >/dev/null 2>&1 || pgrep -f "$binary" >/dev/null 2>&1; then
    echo " ●"
  else
    echo ""
  fi
}

launch_or_focus() {
  local binary="$1"
  if command -v xdotool >/dev/null 2>&1; then
    # If window exists, bring to focus
    local win_id
    win_id=$(xdotool search --onlyvisible --class "$binary" 2>/dev/null | head -n1 || true)
    if [ -n "$win_id" ]; then
      xdotool windowactivate "$win_id"
      return 0
    fi
  fi
  # Otherwise spawn
  "$binary" &
}

interactive_menu() {
  PINNED="shree-files:st:shree-apps:shree-edit:shree-sysmon:shree-settings:shree-about"
  
  MENU_ITEMS=""
  IFS=":" read -r -a APPS <<< "$PINNED"
  for app in "${APPS[@]}"; do
    NAME="${APP_NAMES[$app]:-$app}"
    RUNNING=$(get_running_indicator "$app")
    MENU_ITEMS+="${NAME}${RUNNING} -> ${app}\n"
  done

  CHOICE=$(echo -e "$MENU_ITEMS" | dmenu -p "ShreeOS Dock" -l 7 -c)
  if [ -n "$CHOICE" ]; then
    APP_BIN=$(echo "$CHOICE" | awk -F' -> ' '{print $2}')
    if [ -n "$APP_BIN" ]; then
      launch_or_focus "$APP_BIN"
    fi
  fi
}

case "${1:-menu}" in
  menu)
    interactive_menu
    ;;
  launch)
    launch_or_focus "$2"
    ;;
  *)
    interactive_menu
    ;;
esac
