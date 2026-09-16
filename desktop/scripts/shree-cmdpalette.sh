#!/usr/bin/env bash
# desktop/scripts/shree-cmdpalette.sh — ShreeOS Global Command Palette
#
# Shortcut: Super + K
# Fast, reusable system-wide command palette for direct OS operations.

set -euo pipefail

COMMANDS="\
Toggle Dark / Light Appearance
Toggle Night Light (Warm Display)
Toggle Do Not Disturb
Take Screenshot (Interactive)
Take Fullscreen Screenshot
Open Clipboard History (Super + V)
Run System Diagnostics (shree-doctor)
Check for Software Updates
Restart Network & Wi-Fi
Clean Package Cache
Empty Trash
Open Terminal in Home
Open Downloads Folder
Lock Screen (Secure Session)
Reboot System Cleanly
Power Off Computer"

SELECTED=$(echo "$COMMANDS" | dmenu -p "Command Palette (Super+K)" -l 10 -c)
[ -z "$SELECTED" ] && exit 0

case "$SELECTED" in
  "Toggle Dark / Light Appearance")
    shree-theme toggle
    ;;
  "Toggle Night Light"*)
    shree-nightlight toggle
    ;;
  "Toggle Do Not Disturb")
    shree-dnd toggle
    ;;
  "Take Screenshot (Interactive)")
    shree-screenshot select &
    ;;
  "Take Fullscreen Screenshot")
    shree-screenshot full &
    ;;
  "Open Clipboard History"*)
    shree-clipboard &
    ;;
  "Run System Diagnostics"*)
    st -g 85x24 -t "ShreeOS System Diagnostics" -e shree-doctor &
    ;;
  "Check for Software Updates")
    st -g 80x20 -t "ShreeOS Software Updates" -e system-update.sh &
    ;;
  "Restart Network & Wi-Fi")
    shree-net restart
    ;;
  "Clean Package Cache")
    shree-storage clean-cache
    ;;
  "Empty Trash")
    shree-storage empty-trash
    ;;
  "Open Terminal in Home")
    st &
    ;;
  "Open Downloads Folder")
    shree-files "${HOME}/Downloads" &
    ;;
  "Lock Screen"*)
    shree-lock &
    ;;
  "Reboot System Cleanly")
    initctl reboot
    ;;
  "Power Off Computer")
    initctl poweroff
    ;;
esac
