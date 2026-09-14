#!/usr/bin/env bash
# desktop/scripts/shree-launcher.sh — Spotlight-style floating search panel
set -euo pipefail

CACHE_DIR="${XDG_CACHE_HOME:-${HOME}/.cache}/shreeos"
FILE_CACHE="${CACHE_DIR}/spotlight-files.cache"
mkdir -p "$CACHE_DIR"

refresh_file_cache() {
  local tmp_cache="${FILE_CACHE}.tmp"
  local dir f count
  : > "$tmp_cache"

  for dir in "${HOME}/Desktop" "${HOME}/Documents" "${HOME}/Downloads" "${HOME}/Pictures" "${HOME}/Music"; do
    [ -d "$dir" ] || continue
    count=0
    while IFS= read -r f; do
      printf 'File: %s — %s\n' "$(basename "$f")" "$f" >> "$tmp_cache"
      count=$((count + 1))
      [ "$count" -ge 30 ] && break
    done < <(find "$dir" -maxdepth 2 -type f ! -name ".*" -print 2>/dev/null | LC_ALL=C sort)
  done

  mv "$tmp_cache" "$FILE_CACHE"
}

cache_mtime=0
if [ -f "$FILE_CACHE" ]; then
  cache_mtime=$(stat -c %Y "$FILE_CACHE" 2>/dev/null || stat -f %m "$FILE_CACHE" 2>/dev/null || echo 0)
fi
if [ ! -f "$FILE_CACHE" ] || [ $(( $(date +%s) - cache_mtime )) -gt 300 ]; then
  (refresh_file_cache >/dev/null 2>&1 || true) &
fi

calc_eval() {
  local expr="$1"
  if [[ "$expr" =~ ^[0-9\ \+\-\*\/\(\)\.\^\%]+$ ]]; then
    local res=""
    if command -v bc >/dev/null 2>&1; then
      res=$(printf 'scale=4; %s\n' "$expr" | bc -l 2>/dev/null | sed 's/\.0000$//' || true)
    elif command -v awk >/dev/null 2>&1; then
      res=$(awk "BEGIN {print $expr}" 2>/dev/null || true)
    fi
    [ -n "$res" ] && printf '= %s (Calculator Result)\n' "$res"
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
  [ ! -f "$FILE_CACHE" ] || cat "$FILE_CACHE"
}

if ! command -v dmenu >/dev/null 2>&1; then
  printf 'shree-launcher: dmenu is not installed\n' >&2
  exit 1
fi

INPUT=$(get_spotlight_entries | dmenu -p "Spotlight Search" -l 10 -c || true)
[ -n "$INPUT" ] || exit 0

CALC_RES=$(calc_eval "$INPUT" || true)
if [ -n "$CALC_RES" ] && [[ "$INPUT" =~ [0-9] ]]; then
  if command -v shree-notify >/dev/null 2>&1; then
    shree-notify "Calculator" "$INPUT $CALC_RES" --app="Calculator"
  else
    printf '%s %s\n' "$INPUT" "$CALC_RES"
  fi
  exit 0
fi

case "$INPUT" in
  Terminal*)                  st & ;;
  Files*)                     shree-files & ;;
  Browser*)
    if command -v netsurf >/dev/null 2>&1; then netsurf &
    elif command -v shree-browser >/dev/null 2>&1; then shree-browser &
    elif command -v shree-notify >/dev/null 2>&1; then shree-notify "Browser" "No web browser currently installed" --app="Spotlight"
    fi
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
    FILEPATH=$(printf '%s\n' "$INPUT" | awk -F' — ' '{print $2}')
    if [ -e "$FILEPATH" ]; then
      if command -v shree-quicklook >/dev/null 2>&1; then
        shree-quicklook "$FILEPATH" &
      elif command -v xdg-open >/dev/null 2>&1; then
        xdg-open "$FILEPATH" >/dev/null 2>&1 &
      elif [ -f "$FILEPATH" ] && command -v shree-edit >/dev/null 2>&1; then
        shree-edit "$FILEPATH" &
      elif [ -f "$FILEPATH" ] && command -v nano >/dev/null 2>&1; then
        st -e nano "$FILEPATH" &
      fi
    fi
    ;;
  *)
    if command -v "$INPUT" >/dev/null 2>&1; then
      "$INPUT" &
    elif [[ "$INPUT" =~ ^install[[:space:]]+(.+) ]]; then
      PKG="${BASH_REMATCH[1]}"
      st -e lpm install "$PKG" &
    elif command -v lpm >/dev/null 2>&1; then
      SEARCH_RES=$(lpm search "$INPUT" 2>/dev/null | head -n1 || true)
      if [ -n "$SEARCH_RES" ] && command -v shree-notify >/dev/null 2>&1; then
        shree-notify "LPM Package Search" "Found: ${SEARCH_RES}" --app="Spotlight"
      fi
    fi
    ;;
esac
