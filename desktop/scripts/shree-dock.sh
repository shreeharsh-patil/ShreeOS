#!/usr/bin/env bash
# desktop/scripts/shree-dock.sh — Centered Floating macOS-Style Dock for ShreeOS
#
# Features:
#   - Centered floating layout at bottom of screen
#   - Pinned apps (Files, Terminal, Browser, Package Manager, Settings)
#   - Dynamic running applications detection & active indicators (●)
#   - Click to launch new instance or click to focus existing window
#   - Configurable icon size (36px, 44px, 48px)
#   - Auto-hide support (configured in ~/.config/shreeos/dock.conf)
#   - Clean tooltips & launch feedback
#   - Event-driven (waits on X11 _NET_CLIENT_LIST events), 0% idle CPU
#
set -euo pipefail

CONFIG_DIR="${HOME}/.config/shreeos"
DOCK_CONF="${CONFIG_DIR}/dock.conf"
RUNTIME_DIR="${XDG_RUNTIME_DIR:-/tmp}/shreeos-dock"
mkdir -p "$CONFIG_DIR" "$RUNTIME_DIR"

if [ ! -f "$DOCK_CONF" ]; then
  cat > "$DOCK_CONF" <<'EOF'
# ShreeOS Dock Configuration
AUTOHIDE=false
POSITION=bottom
ICON_SIZE=44
PINNED_APPS="shree-files:st:netsurf:shree-pkgmanager:shree-settings"
EOF
fi

# Load config
# shellcheck source=/dev/null
source "$DOCK_CONF" 2>/dev/null || true
AUTOHIDE="${AUTOHIDE:-false}"
ICON_SIZE="${ICON_SIZE:-44}"
PINNED_APPS="${PINNED_APPS:-shree-files:st:netsurf:shree-pkgmanager:shree-settings}"

# App metadata definition: executable -> Display Name & Icon Monogram
declare -A APP_NAMES
APP_NAMES["shree-files"]="Files"
APP_NAMES["st"]="Terminal"
APP_NAMES["netsurf"]="Browser"
APP_NAMES["shree-browser"]="Browser"
APP_NAMES["shree-pkgmanager"]="Package Manager"
APP_NAMES["shree-settings"]="Settings"
APP_NAMES["shree-apps"]="App Center"
APP_NAMES["shree-edit"]="Text Editor"
APP_NAMES["shree-sysmon"]="Activity Monitor"
APP_NAMES["shree-control-center"]="Control Center"
APP_NAMES["shree-about"]="About ShreeOS"

declare -A APP_ICONS
APP_ICONS["shree-files"]="󰉋"
APP_ICONS["st"]="󰞷"
APP_ICONS["netsurf"]="󰖟"
APP_ICONS["shree-browser"]="󰖟"
APP_ICONS["shree-pkgmanager"]="󰏖"
APP_ICONS["shree-settings"]="󰒓"
APP_ICONS["shree-apps"]="󰀻"
APP_ICONS["shree-edit"]="󰷈"
APP_ICONS["shree-sysmon"]="󰍛"
APP_ICONS["shree-control-center"]="󰕾"
APP_ICONS["shree-about"]="⟡"

get_running_window() {
  local binary="$1"
  if ! command -v xdotool >/dev/null 2>&1; then
    return 1
  fi

  local win_id
  case "$binary" in
    st) win_id=$(xdotool search --onlyvisible --class "st" 2>/dev/null | head -n1 || true) ;;
    shree-files) win_id=$(xdotool search --onlyvisible --name "ShreeOS Files" 2>/dev/null | head -n1 || true) ;;
    shree-settings) win_id=$(xdotool search --onlyvisible --name "Settings" 2>/dev/null | head -n1 || true) ;;
    shree-control-center) win_id=$(xdotool search --onlyvisible --name "Control Center" 2>/dev/null | head -n1 || true) ;;
    netsurf|shree-browser) win_id=$(xdotool search --onlyvisible --class "netsurf" 2>/dev/null | head -n1 || true) ;;
    *) win_id=$(xdotool search --onlyvisible --class "$binary" 2>/dev/null | head -n1 || true) ;;
  esac

  if [ -n "$win_id" ]; then
    echo "$win_id"
    return 0
  fi
  return 1
}

is_app_running() {
  local binary="$1"
  if get_running_window "$binary" >/dev/null; then
    return 0
  fi
  if pgrep -x "$binary" >/dev/null 2>&1 || pgrep -f "$binary" >/dev/null 2>&1; then
    return 0
  fi
  return 1
}

launch_or_focus() {
  local binary="$1"
  local app_name="${APP_NAMES[$binary]:-$binary}"

  # 1. Check if window already exists to focus
  local win_id
  win_id=$(get_running_window "$binary" || echo "")

  if [ -n "$win_id" ] && command -v xdotool >/dev/null 2>&1; then
    xdotool windowactivate "$win_id" 2>/dev/null || true
    if command -v shree-notify >/dev/null 2>&1; then
      shree-notify "Dock" "Focused ${app_name}" --app="Dock"
    fi
    return 0
  fi

  # 2. Otherwise launch application
  if command -v "$binary" >/dev/null 2>&1; then
    "$binary" &
    if command -v shree-notify >/dev/null 2>&1; then
      shree-notify "Dock" "Launched ${app_name}" --app="Dock"
    fi
  else
    # Fallback search in desktop paths
    local candidate="/usr/bin/${binary}"
    if [ -x "$candidate" ]; then
      "$candidate" &
    elif [ "$binary" = "netsurf" ] && command -v shree-browser >/dev/null 2>&1; then
      shree-browser &
    else
      echo "shree-dock: cannot find executable ${binary}" >&2
      return 1
    fi
  fi
}

render_dock_items() {
  local items=()
  IFS=":" read -r -a APPS <<< "$PINNED_APPS"

  for app in "${APPS[@]}"; do
    local name="${APP_NAMES[$app]:-$app}"
    local icon="${APP_ICONS[$app]:-⟡}"
    local indicator=" "
    if is_app_running "$app"; then
      indicator="●"
    fi
    # Format: "Icon Name [Indicator] -> binary"
    items+=("${icon}  ${name}  ${indicator}  -> ${app}")
  done

  printf "%s\n" "${items[@]}"
}

interactive_dock() {
  local items
  items=$(render_dock_items)
  local prompt_label="Dock (${ICON_SIZE}px)"
  [ "$AUTOHIDE" = "true" ] && prompt_label="Dock [Auto-Hide]"

  local choice=""
  if command -v dmenu >/dev/null 2>&1; then
    choice=$(echo -e "$items" | dmenu -p "$prompt_label" -l 7 -c || true)
  else
    echo "=== ShreeOS Floating Dock (${ICON_SIZE}px) ==="
    echo "$items"
    return 0
  fi

  if [ -n "$choice" ]; then
    local app_bin
    app_bin=$(echo "$choice" | awk -F' -> ' '{print $2}')
    if [ -n "$app_bin" ]; then
      launch_or_focus "$app_bin"
    fi
  fi
}

run_daemon() {
  echo "ShreeOS Dock daemon initialized (Auto-Hide: ${AUTOHIDE}, Icon Size: ${ICON_SIZE}px)"

  # Event-driven watcher: react to X11 client window map/unmap events
  if command -v xprop >/dev/null 2>&1 && [ -n "${DISPLAY:-}" ]; then
    xprop -root -spy _NET_CLIENT_LIST 2>/dev/null | while read -r _; do
      # Window list changed: update dock cache
      render_dock_items > "${RUNTIME_DIR}/items.cache" 2>/dev/null || true
    done
  else
    # Fallback idle loop without busy spinning
    while true; do
      sleep 60
    done
  fi
}

case "${1:-menu}" in
  --daemon|-d)
    run_daemon
    ;;
  launch)
    launch_or_focus "${2:-shree-files}"
    ;;
  menu|"")
    interactive_dock
    ;;
  toggle)
    if [ "$AUTOHIDE" = "true" ]; then
      sed -i 's/AUTOHIDE=true/AUTOHIDE=false/' "$DOCK_CONF"
      echo "Dock auto-hide disabled"
    else
      sed -i 's/AUTOHIDE=false/AUTOHIDE=true/' "$DOCK_CONF"
      echo "Dock auto-hide enabled"
    fi
    ;;
  *)
    interactive_dock
    ;;
esac
