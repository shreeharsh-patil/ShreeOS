#!/usr/bin/env bash
# desktop/scripts/shree-topbar.sh — macOS-Style Menu Bar Status Feed for ShreeOS
#
# Height: 28px (configured via dwm user_bh=28)
# Left:
#   - ShreeOS logo (⟡)
#   - Dynamic active application name (event-driven via X11 _NET_ACTIVE_WINDOW)
#   - Contextual application actions (File, Edit, View, Window, Help)
# Right:
#   - Wi-Fi state
#   - Audio volume
#   - Battery capacity & status
#   - Clean formatted clock (e.g., Wed Sep 3  12:30 PM)
#   - Control Center shortcut indicator
#
# Avoids expensive polling: uses event-driven window spy + 15s metric cache.
#
set -euo pipefail

# Cache files to avoid subshell overhead
CACHE_DIR="${XDG_RUNTIME_DIR:-/tmp}/shreeos-topbar"
mkdir -p "$CACHE_DIR"
METRICS_CACHE="${CACHE_DIR}/metrics.txt"
ACTIVE_APP_CACHE="${CACHE_DIR}/active_app.txt"

echo "Desktop" > "$ACTIVE_APP_CACHE"

get_active_app() {
  if ! command -v xdotool >/dev/null 2>&1 || ! command -v xprop >/dev/null 2>&1; then
    echo "ShreeOS"
    return
  fi

  local win_id
  win_id=$(xprop -root _NET_ACTIVE_WINDOW 2>/dev/null | awk '{print $NF}' || echo "")

  if [ -z "$win_id" ] || [ "$win_id" = "0x0" ] || [ "$win_id" = "0" ]; then
    echo "Desktop"
    return
  fi

  # Query window class first (more stable application name)
  local win_class
  win_class=$(xprop -id "$win_id" WM_CLASS 2>/dev/null | awk -F'"' '{print $(NF-1)}' || echo "")

  case "$win_class" in
    st|st-256color)       echo "Terminal" ;;
    shree-files|ShreeFiles) echo "Files" ;;
    shree-apps|ShreeApps) echo "App Center" ;;
    shree-edit|ShreeEdit) echo "Editor" ;;
    shree-view|ShreeView) echo "Image Viewer" ;;
    shree-sysmon|ShreeSysmon) echo "Activity Monitor" ;;
    shree-settings|ShreeSettings) echo "Settings" ;;
    shree-control-center|ShreeControl) echo "Control Center" ;;
    shree-about|ShreeAbout) echo "About ShreeOS" ;;
    netsurf|Netsurf)      echo "Browser" ;;
    "")
      local win_name
      win_name=$(xdotool getwindowname "$win_id" 2>/dev/null | cut -c1-24 || echo "")
      [ -n "$win_name" ] && echo "$win_name" || echo "ShreeOS"
      ;;
    *)
      # Capitalize class name
      echo "${win_class^}"
      ;;
  esac
}

get_context_actions() {
  local app="$1"
  case "$app" in
    Terminal) echo "Shell  Edit  View  Window  Help" ;;
    Files)    echo "File  Edit  View  Go  Window  Help" ;;
    Editor)   echo "File  Edit  Selection  View  Help" ;;
    Browser)  echo "File  Edit  View  History  Bookmarks  Help" ;;
    *)        echo "File  Edit  View  Window  Help" ;;
  esac
}

collect_metrics() {
  # 1. Wi-Fi / Network
  local net_str="Offline"
  local def_route
  def_route=$(ip route show default 2>/dev/null | awk '{print $5}' | head -n1 || echo "")
  if [ -n "$def_route" ]; then
    case "$def_route" in
      wl*|wifi*)
        local ssid=""
        if command -v iwgetid >/dev/null 2>&1; then
          ssid=$(iwgetid -r 2>/dev/null || echo "")
        fi
        [ -n "$ssid" ] && net_str="Wi-Fi: ${ssid}" || net_str="Wi-Fi"
        ;;
      eth*|en*|vd*)
        net_str="Ethernet"
        ;;
      *)
        net_str="Online"
        ;;
    esac
  fi

  # 2. Audio Volume
  local vol_str=""
  if command -v amixer >/dev/null 2>&1; then
    local master_info
    master_info=$(amixer sget Master 2>/dev/null || true)
    if [ -n "$master_info" ]; then
      if echo "$master_info" | grep -q '\[off\]'; then
        vol_str="Mute"
      else
        local pct
        pct=$(echo "$master_info" | grep -oP '\[\K[0-9]+(?=%\])' | head -n1 || echo "")
        [ -n "$pct" ] && vol_str="Vol: ${pct}%"
      fi
    fi
  fi
  if [ -z "$vol_str" ]; then
    if [ -S /run/shreed.sock ] && command -v shreedctl >/dev/null 2>&1; then
      vol_str="Audio"
    fi
  fi
  [ -z "$vol_str" ] && vol_str="Vol: 80%"

  # 3. Battery
  local bat_str="AC"
  for bat in /sys/class/power_supply/BAT* /sys/class/power_supply/*; do
    [ -d "$bat" ] || continue
    local btype
    btype=$(cat "${bat}/type" 2>/dev/null || echo "")
    if [ "$btype" = "Battery" ]; then
      local cap stat
      cap=$(cat "${bat}/capacity" 2>/dev/null || echo "100")
      stat=$(cat "${bat}/status" 2>/dev/null || echo "Discharging")
      if [ "$stat" = "Charging" ]; then
        bat_str="⚡${cap}%"
      else
        bat_str="${cap}%"
      fi
      break
    fi
  done

  # 4. macOS formatted Date & Time (e.g. Wed Sep 3  12:30 PM)
  local datetime
  datetime=$(date +"%a %b %-d   %-I:%M %p" 2>/dev/null || date +"%a %b %d   %H:%M")

  # Write right side metrics
  echo "  ${net_str}  │  ${vol_str}  │  ${bat_str}  │  ${datetime}  │  ⚙ " > "$METRICS_CACHE"
}

render_bar() {
  local app
  app=$(cat "$ACTIVE_APP_CACHE" 2>/dev/null || echo "Desktop")
  local actions
  actions=$(get_context_actions "$app")
  local right_metrics
  right_metrics=$(cat "$METRICS_CACHE" 2>/dev/null || echo "  ShreeOS  ")

  # Format full bar string: Left actions + right hardware & clock metrics
  local full_status="⟡  ${app}   ${actions}   ${right_metrics}"

  if command -v xsetroot >/dev/null 2>&1; then
    xsetroot -name "${full_status}"
  else
    echo "${full_status}"
  fi
}

# Initial calculation
collect_metrics
echo "$(get_active_app)" > "$ACTIVE_APP_CACHE"
render_bar

if [ "${1:-}" = "--once" ]; then
  exit 0
fi

# Run background event spy for X11 window focus updates (0% CPU event-driven)
if command -v xprop >/dev/null 2>&1 && [ -n "${DISPLAY:-}" ]; then
  (
    xprop -root -spy _NET_ACTIVE_WINDOW 2>/dev/null | while read -r _; do
      NEW_APP=$(get_active_app)
      echo "$NEW_APP" > "$ACTIVE_APP_CACHE"
      render_bar
    done
  ) &
  SPY_PID=$!
  trap 'kill "$SPY_PID" 2>/dev/null || true; rm -rf "$CACHE_DIR"' EXIT INT TERM
fi

# Periodic metric updates for clock, battery, network (every 10s)
while true; do
  sleep 10
  collect_metrics
  render_bar
done
