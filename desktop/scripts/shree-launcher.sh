#!/usr/bin/env bash
# desktop/scripts/shree-launcher.sh — ShreeOS Universal Spotlight Launcher
#
# Shortcut: Super + Space
# Features:
#   - Instant application launching
#   - Settings & preference navigation
#   - Local file search (Documents, Downloads, Desktop)
#   - Real-time arithmetic evaluation (calculator expressions)
#   - Package discovery via LPM
#   - Direct system power actions

set -euo pipefail

calc_eval() {
  local expr="$1"
  if [[ "$expr" =~ ^[0-9\ \+\-\*\/\(\)\.\^\%]+$ ]]; then
    if command -v bc >/dev/null 2>&1; then
      local res
      res=$(echo "scale=4; $expr" | bc -l 2>/dev/null | sed 's/\.0000$//' || true)
      if [ -n "$res" ]; then
        echo "= ${res} (Calculator Expression)"
      fi
    elif command -v awk >/dev/null 2>&1; then
      local res
      res=$(awk "BEGIN {print $expr}" 2>/dev/null || true)
      if [ -n "$res" ]; then
        echo "= ${res} (Calculator Expression)"
      fi
    fi
  fi
}

get_launcher_entries() {
  cat <<'ENTRIES'
Terminal                  — Fast Command Line Interface (st)
Files                     — Browse Documents and Storage (shree-files)
App Center                — Discover, Install & Update Software (shree-apps)
Text Editor               — Lightweight Document Editor (shree-edit)
Image Viewer              — View Photos and Graphics (shree-view)
System Monitor            — Task and Resource Manager (shree-sysmon)
Control Center            — Quick Network, Audio & Display Toggles
Settings: Appearance      — Light / Dark Theme & Accent Colors
Settings: Displays        — Screen Resolution & Night Light
Settings: Network         — Wi-Fi & Ethernet Configuration
Settings: Storage         — Disk Usage, Cache & Cleanup
Settings: Updates         — System Package Upgrades
Command Palette           — Super + K Action Menu
Take Screenshot           — Capture Screen, Window or Region
Clipboard History         — Super + V Clipboard Manager
About ShreeOS             — System Hardware & OS Details
Lock Screen               — Secure Current Session
Restart Computer          — Orderly System Reboot
Power Off                 — Clean System Shutdown
ENTRIES

  # Index common user directories if they exist
  for dir in "${HOME}/Desktop" "${HOME}/Documents" "${HOME}/Downloads"; do
    if [ -d "$dir" ]; then
      find "$dir" -maxdepth 2 -type f 2>/dev/null | head -n 12 | while read -r filepath; do
        echo "File: $(basename "$filepath") — ${filepath}"
      done
    fi
  done
}

# Run dmenu with prompt
INPUT=$(get_launcher_entries | dmenu -p "Search ShreeOS" -l 10 -c || true)

[ -z "$INPUT" ] && exit 0

# 1. Check if input was a calculator query
CALC_RES=$(calc_eval "$INPUT" || true)
if [ -n "$CALC_RES" ] && [[ "$INPUT" =~ [0-9] ]]; then
  if command -v shree-notify >/dev/null 2>&1; then
    shree-notify "Calculator" "$INPUT $CALC_RES" --app="Calculator"
  fi
  exit 0
fi

# 2. Match selection
case "$INPUT" in
  Terminal*)                  st & ;;
  Files*)                     shree-files & ;;
  "App Center"*)              shree-apps & ;;
  "Text Editor"*)             shree-edit & ;;
  "Image Viewer"*)            shree-view & ;;
  "System Monitor"*)          shree-sysmon & ;;
  "Control Center"*)          shree-control-center & ;;
  "Settings: Appearance"*)    shree-settings appearance & ;;
  "Settings: Displays"*)      shree-settings displays & ;;
  "Settings: Network"*)       shree-settings network & ;;
  "Settings: Storage"*)       shree-settings storage & ;;
  "Settings: Updates"*)       shree-settings updates & ;;
  "Command Palette"*)         shree-cmdpalette & ;;
  "Take Screenshot"*)         shree-screenshot & ;;
  "Clipboard History"*)       shree-clipboard & ;;
  "About ShreeOS"*)           shree-about & ;;
  "Lock Screen"*)             shree-lock & ;;
  "Restart Computer"*)        initctl reboot ;;
  "Power Off"*)               initctl poweroff ;;
  "File: "*)
    FILEPATH=$(echo "$INPUT" | awk -F' — ' '{print $2}')
    if [ -f "$FILEPATH" ]; then
      xdg-open "$FILEPATH" 2>/dev/null || shree-edit "$FILEPATH" 2>/dev/null || st -e nano "$FILEPATH" &
    fi
    ;;
  *)
    # If not a standard entry, try running as direct command or search LPM
    if command -v "$INPUT" >/dev/null 2>&1; then
      $INPUT &
    elif [[ "$INPUT" =~ ^install\ (.*) ]]; then
      PKG="${BASH_REMATCH[1]}"
      st -e lpm install "$PKG" &
    else
      # Try LPM search
      SEARCH_RES=$(lpm search "$INPUT" 2>/dev/null | head -n1 || true)
      if [ -n "$SEARCH_RES" ]; then
        if command -v shree-notify >/dev/null 2>&1; then
          shree-notify "LPM Package Search" "Found: $SEARCH_RES. Run 'lpm install <pkg>' to install." --app="App Center"
        fi
      fi
    fi
    ;;
esac
