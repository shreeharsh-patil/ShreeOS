#!/usr/bin/env bash
# desktop/scripts/shree-launcher.sh — Spotlight-Style Floating Search Panel
#
# Shortcut: Super + Space
# Features:
#   - Instant centered floating search panel
#   - Fast keyboard navigation: Up/Down arrows, Enter to launch, Esc to close
#   - Search applications, settings panes, cached user files, and terminal commands
#   - Instant inline math calculation (e.g. 1024 * 4, 1500 / 3)
#   - High performance: cached file index (never rescans whole disk on keypress)
#
set -euo pipefail

CACHE_DIR="${XDG_CACHE_HOME:-${HOME}/.cache}/shreeos"
FILE_CACHE="${CACHE_DIR}/spotlight-files.cache"
mkdir -p "$CACHE_DIR"

refresh_file_cache() {
  local tmp_cache="${FILE_CACHE}.tmp"
  : > "$tmp_cache"
  for dir in "${HOME}/Desktop" "${HOME}/Documents" "${HOME}/Downloads" "${HOME}/Pictures" "${HOME}/Music"; do
    [ -d "$dir" ] || continue
    find "$dir" -maxdepth 2 -type f ! -name ".*" 2>/dev/null | head -n 30 | while read -r f; do
      echo "File: $(basename "$f") — ${f}" >> "$tmp_cache"
    done
  done
  mv "$tmp_cache" "$FILE_CACHE" 2>/dev/null || true
}

# Asynchronously refresh cache if older than 300 seconds or missing
if [ ! -f "$FILE_CACHE" ] || [ $(( $(date +%s) - $(stat -c %Y "$FILE_CACHE" 2>/dev/null || stat -f %m "$FILE_CACHE" 2>/dev/null || echo 0) )) -gt 300 ]; then
  (refresh_file_cache) &
fi

calc_eval() {
  local expr="$1"
  if [[ "$expr" =~ ^[0-9\ \+\-\*\/\(\)\.\^\%]+$ ]]; then
    if command -v bc >/dev/null 2>&1; then
      local res
      res=$(echo "scale=4; $expr" | bc -l 2>/dev/null | sed 's/\.0000$//' || true)
      [ -n "$res" ] && echo "= ${res} (Calculator Result)"
    elif command -v awk >/dev/null 2>&1; then
      local res
      res=$(awk "BEGIN {print $expr}" 2>/dev/null || true)
      [ -n "$res" ] && echo "= ${res} (Calculator Result)"
    fi
  fi
}

get_spotlight_entries() {
  cat <<'ENTRIES'
Terminal                  — Fast Command Line Interface (st)
Files                     — Browse Documents, Storage & Disks (shree-files)
Browser                   — Web Browser & Internet Navigation
App Center                — Discover, Install & Update Packages (shree-apps)
Package Manager           — Manage Installed Packages & Repositories (shree-pkgmanager)
Text Editor               — Document & Code Editor (shree-edit)
Image Viewer              — View Photos and Visual Graphics (shree-view)
Activity Monitor          — System Tasks, Memory & Resource Manager (shree-sysmon)
Control Center            — Quick Network, Audio, Brightness & Display Toggles
Settings: Appearance      — Light & Dark Mode, Accent Color, Wallpapers
Settings: Desktop         — Dock Auto-Hide, Position & Icon Dimensions
Settings: Displays        — Screen Resolution, Refresh Rates & Night Light
Settings: Network         — Wi-Fi Discovery, Ethernet & DNS Settings
Settings: Sound           — Master Volume, Audio Devices & Alerts
Settings: Keyboard        — Keyboard Layouts, Repeat Rate & Shortcuts
Settings: Mouse           — Cursor Speed, Scrolling & Acceleration
Settings: Power           — Battery Health, Standby Timeouts & Display DPMS
Settings: Date & Time     — Clock Format, Timezone & NTP Synchronization
Settings: Users           — User Account Administration & Passwords
Settings: Software        — System Package Updates & Restore Points
Settings: About           — Hardware Specifications, Kernel & System Identity
Command Palette           — Super + K Master Action Palette
Take Screenshot           — Screen Capture, Window or Custom Region
Clipboard History         — Super + V Clipboard Manager
Lock Screen               — Secure Current Session
Restart Computer          — Orderly System Reboot
Power Off                 — Clean System Shutdown
ENTRIES

  # Append cached files instantly without disk lag
  if [ -f "$FILE_CACHE" ]; then
    cat "$FILE_CACHE"
  fi
}

# Run dmenu in centered Spotlight mode (10 lines, centered)
INPUT=$(get_spotlight_entries | dmenu -p "Spotlight Search" -l 10 -c || true)

[ -z "$INPUT" ] && exit 0

# 1. Evaluate instant calculator expression if present
CALC_RES=$(calc_eval "$INPUT" || true)
if [ -n "$CALC_RES" ] && [[ "$INPUT" =~ [0-9] ]]; then
  if command -v shree-notify >/dev/null 2>&1; then
    shree-notify "Calculator" "$INPUT $CALC_RES" --app="Calculator"
  fi
  exit 0
fi

# 2. Dispatch selection
case "$INPUT" in
  Terminal*)                  st & ;;
  Files*)                     shree-files & ;;
  Browser*)
    if command -v netsurf >/dev/null 2>&1; then netsurf &
    elif command -v shree-browser >/dev/null 2>&1; then shree-browser &
    else shree-notify "Browser" "No web browser currently installed" --app="Spotlight"; fi
    ;;
  "App Center"*)              shree-apps & ;;
  "Package Manager"*)         shree-pkgmanager & ;;
  "Text Editor"*)             shree-edit & ;;
  "Image Viewer"*)            shree-view & ;;
  "Activity Monitor"*)        shree-sysmon & ;;
  "Control Center"*)          shree-control-center & ;;
  "Settings: Appearance"*)    shree-settings appearance & ;;
  "Settings: Desktop"*)       shree-settings desktop & ;;
  "Settings: Displays"*)      shree-settings displays & ;;
  "Settings: Network"*)       shree-settings network & ;;
  "Settings: Sound"*)         shree-settings sound & ;;
  "Settings: Keyboard"*)      shree-settings keyboard & ;;
  "Settings: Mouse"*)         shree-settings mouse & ;;
  "Settings: Power"*)         shree-settings power & ;;
  "Settings: Date & Time"*)   shree-settings datetime & ;;
  "Settings: Users"*)         shree-settings users & ;;
  "Settings: Software"*)      shree-settings updates & ;;
  "Settings: About"*)         shree-settings about & ;;
  "Command Palette"*)         shree-cmdpalette & ;;
  "Take Screenshot"*)         shree-screenshot & ;;
  "Clipboard History"*)       shree-clipboard & ;;
  "Lock Screen"*)             shree-lock & ;;
  "Restart Computer"*)        initctl reboot ;;
  "Power Off"*)               initctl poweroff ;;
  "File: "*)
    FILEPATH=$(echo "$INPUT" | awk -F' — ' '{print $2}')
    if [ -e "$FILEPATH" ]; then
      if command -v shree-quicklook >/dev/null 2>&1; then
        shree-quicklook "$FILEPATH" &
      elif command -v xdg-open >/dev/null 2>&1; then
        xdg-open "$FILEPATH" 2>/dev/null || true &
      elif [ -f "$FILEPATH" ]; then
        shree-edit "$FILEPATH" 2>/dev/null || st -e nano "$FILEPATH" &
      fi
    fi
    ;;
  *)
    # Direct command execution from PATH or LPM package search
    if command -v "$INPUT" >/dev/null 2>&1; then
      $INPUT &
    elif [[ "$INPUT" =~ ^install\ (.*) ]]; then
      PKG="${BASH_REMATCH[1]}"
      st -e lpm install "$PKG" &
    else
      SEARCH_RES=$(lpm search "$INPUT" 2>/dev/null | head -n1 || true)
      if [ -n "$SEARCH_RES" ]; then
        if command -v shree-notify >/dev/null 2>&1; then
          shree-notify "LPM Package Search" "Found: ${SEARCH_RES}" --app="Spotlight"
        fi
      fi
    fi
    ;;
esac
