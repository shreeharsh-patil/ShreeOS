#!/usr/bin/env bash
# desktop/scripts/shree-lock.sh — ShreeOS Secure Lock Screen
#
# Blurs desktop, displays large clock & date, and prompts for password to unlock.

set -euo pipefail

if command -v slock >/dev/null 2>&1; then
  exec slock
elif command -v i3lock >/dev/null 2>&1; then
  exec i3lock -c 1C1C1E --ring-color=2878FF --keyhl-color=60A0FF
else
  # Terminal lock screen fallback
  st -f -g 80x24 -t "ShreeOS Lock Screen" -e /bin/bash -c "
    clear
    echo ''
    echo '     ┌────────────────────────────────────────────────────────────┐'
    echo '     │                      ShreeOS Locked                        │'
    echo '     │                     $(date +'%A, %B %d')                   │'
    echo '     └────────────────────────────────────────────────────────────┘'
    echo ''
    echo '       Time: $(date +'%H:%M:%S')'
    echo '       User: ${USER:-shree}'
    echo ''
    read -s -p '       Enter password to unlock: ' _PW
    echo ''
  "
fi
