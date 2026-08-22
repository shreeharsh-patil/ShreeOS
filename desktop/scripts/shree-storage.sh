#!/usr/bin/env bash
# desktop/scripts/shree-storage.sh — ShreeOS Storage & Cache Manager
#
# Provides disk usage breakdown, package cache cleaning, and trash emptying.

set -euo pipefail

clean_cache() {
  local cache_dir="/var/cache/lpm/pkg"
  if [ -d "$cache_dir" ]; then
    local count
    count=$(ls -1 "$cache_dir" 2>/dev/null | wc -l || echo 0)
    rm -rf "${cache_dir:?}"/*
    if command -v shree-notify >/dev/null 2>&1; then
      shree-notify "Storage" "Cleaned ${count} cached package archive(s)" --app="Storage"
    fi
  else
    if command -v shree-notify >/dev/null 2>&1; then
      shree-notify "Storage" "Package cache is already empty" --app="Storage"
    fi
  fi
}

empty_trash() {
  local trash_dir="${HOME}/.local/share/Trash/files"
  if [ -d "$trash_dir" ]; then
    local count
    count=$(ls -1 "$trash_dir" 2>/dev/null | wc -l || echo 0)
    rm -rf "${trash_dir:?}"/*
    if command -v shree-notify >/dev/null 2>&1; then
      shree-notify "Trash Emptied" "Removed ${count} item(s) from Trash" --app="Files"
    fi
  fi
}

show_storage() {
  clear
  echo "┌────────────────────────────────────────────────────────────────────────────┐"
  echo "│                     ShreeOS Storage & Disk Overview                        │"
  echo "└────────────────────────────────────────────────────────────────────────────┘"
  echo ""
  df -h / /tmp /home 2>/dev/null || df -h /
  echo ""
  echo "  [Actions]"
  echo "    [1] Clean Package Cache (/var/cache/lpm/pkg)"
  echo "    [2] Empty User Trash (~/.local/share/Trash)"
  echo "    [q] Exit"
  echo ""
  read -r -p "  Enter choice [1, 2, q]: " CHOICE
  case "$CHOICE" in
    1) clean_cache ;;
    2) empty_trash ;;
  esac
}

case "${1:-show}" in
  clean-cache) clean_cache ;;
  empty-trash) empty_trash ;;
  show|*)
    if [ -t 0 ]; then show_storage; else st -g 75x20 -t "Storage Manager" -e "$0" show & fi
    ;;
esac
