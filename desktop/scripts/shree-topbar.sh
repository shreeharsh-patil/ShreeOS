#!/usr/bin/env bash
# desktop/scripts/shree-topbar.sh — compact macOS-inspired ShreeOS menu bar feed
set -euo pipefail

CACHE_DIR="${XDG_RUNTIME_DIR:-/tmp}/shreeos-topbar"
mkdir -p "$CACHE_DIR"
METRICS_CACHE="${CACHE_DIR}/metrics.txt"
ACTIVE_APP_CACHE="${CACHE_DIR}/active_app.txt"
printf 'Desktop\n' > "$ACTIVE_APP_CACHE"

get_active_app() {
  if ! command -v xprop >/dev/null 2>&1 || [ -z "${DISPLAY:-}" ]; then
    echo "ShreeOS"
    return
  fi

  local win_id win_class win_name
  win_id=$(xprop -root _NET_ACTIVE_WINDOW 2>/dev/null | awk '{print $NF}' || true)
  if [ -z "$win_id" ] || [ "$win_id" = "0x0" ] || [ "$win_id" = "0" ]; then
    echo "Desktop"
    return
  fi

  win_class=$(xprop -id "$win_id" WM_CLASS 2>/dev/null | awk -F'"' '{print $(NF-1)}' || true)
  case "$win_class" in
    st|st-256color) echo "Terminal" ;;
    shree-files|ShreeFiles) echo "Files" ;;
    shree-apps|ShreeApps) echo "App Center" ;;
    shree-edit|ShreeEdit) echo "Editor" ;;
    shree-view|ShreeView) echo "Image Viewer" ;;
    shree-sysmon|ShreeSysmon) echo "Activity Monitor" ;;
    shree-settings|ShreeSettings) echo "Settings" ;;
    shree-control-center|ShreeControl) echo "Control Center" ;;
    shree-about|ShreeAbout) echo "About ShreeOS" ;;
    netsurf|Netsurf) echo "Browser" ;;
    "")
      if command -v xdotool >/dev/null 2>&1; then
        win_name=$(xdotool getwindowname "$win_id" 2>/dev/null | cut -c1-24 || true)
      else
        win_name=$(xprop -id "$win_id" _NET_WM_NAME 2>/dev/null | sed -n 's/.*= "//; s/"$//; p' | cut -c1-24)
      fi
      [ -n "$win_name" ] && echo "$win_name" || echo "ShreeOS"
      ;;
    *) printf '%s\n' "${win_class^}" ;;
  esac
}

get_context_actions() {
  case "$1" in
    Terminal) echo "Shell  Edit  View  Window  Help" ;;
    Files)    echo "File  Edit  View  Go  Window  Help" ;;
    Editor)   echo "File  Edit  Selection  View  Help" ;;
    Browser)  echo "File  Edit  View  History  Bookmarks  Help" ;;
    *)        echo "File  Edit  View  Window  Help" ;;
  esac
}

collect_metrics() {
  local net_str="Offline" def_route ssid=""
  def_route=$(ip route show default 2>/dev/null | awk 'NR==1 {print $5}' || true)
  if [ -n "$def_route" ]; then
    case "$def_route" in
      wl*|wifi*)
        if command -v iwgetid >/dev/null 2>&1; then ssid=$(iwgetid -r 2>/dev/null || true); fi
        [ -n "$ssid" ] && net_str="Wi-Fi: ${ssid}" || net_str="Wi-Fi"
        ;;
      eth*|en*|vd*) net_str="Ethernet" ;;
      *) net_str="Online" ;;
    esac
  fi

  local vol_str="Audio: —" master_info pct
  if command -v amixer >/dev/null 2>&1; then
    master_info=$(amixer sget Master 2>/dev/null || true)
    if [ -n "$master_info" ]; then
      if printf '%s\n' "$master_info" | grep -q '\[off\]'; then
        vol_str="Mute"
      else
        pct=$(printf '%s\n' "$master_info" | sed -n 's/.*\[\([0-9][0-9]*\)%\].*/\1/p' | head -n1)
        [ -z "$pct" ] || vol_str="Vol: ${pct}%"
      fi
    fi
  fi

  local bat_str="AC" bat btype cap stat
  for bat in /sys/class/power_supply/BAT* /sys/class/power_supply/*; do
    [ -d "$bat" ] || continue
    btype=$(cat "${bat}/type" 2>/dev/null || true)
    [ "$btype" = "Battery" ] || continue
    cap=$(cat "${bat}/capacity" 2>/dev/null || echo "?")
    stat=$(cat "${bat}/status" 2>/dev/null || echo "Unknown")
    [ "$stat" = "Charging" ] && bat_str="⚡${cap}%" || bat_str="${cap}%"
    break
  done

  local datetime
  datetime=$(date +"%a %b %-d   %-I:%M %p" 2>/dev/null || date +"%a %b %d   %H:%M")
  printf '  %s  │  %s  │  %s  │  %s  │  ⚙ \n' "$net_str" "$vol_str" "$bat_str" "$datetime" > "$METRICS_CACHE"
}

render_bar() {
  local app actions right_metrics
  app=$(cat "$ACTIVE_APP_CACHE" 2>/dev/null || echo "Desktop")
  actions=$(get_context_actions "$app")
  right_metrics=$(cat "$METRICS_CACHE" 2>/dev/null || echo "  ShreeOS  ")
  if command -v xsetroot >/dev/null 2>&1 && [ -n "${DISPLAY:-}" ]; then
    xsetroot -name "⟡  ${app}   ${actions}   ${right_metrics}"
  else
    printf '⟡  %s   %s   %s\n' "$app" "$actions" "$right_metrics"
  fi
}

collect_metrics
get_active_app > "$ACTIVE_APP_CACHE"
render_bar
[ "${1:-}" != "--once" ] || exit 0

SPY_PID=""
if command -v xprop >/dev/null 2>&1 && [ -n "${DISPLAY:-}" ]; then
  (
    xprop -root -spy _NET_ACTIVE_WINDOW 2>/dev/null | while IFS= read -r _; do
      get_active_app > "$ACTIVE_APP_CACHE"
      render_bar
    done
  ) &
  SPY_PID=$!
fi

cleanup() {
  [ -z "$SPY_PID" ] || kill "$SPY_PID" 2>/dev/null || true
  rm -rf "$CACHE_DIR"
}
trap cleanup EXIT INT TERM

while true; do
  sleep 15
  collect_metrics
  render_bar
done
