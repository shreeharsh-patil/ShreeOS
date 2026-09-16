#!/usr/bin/env bash
# desktop/apps/shree-apps.sh — ShreeOS App Center (LPM Frontend)
set -euo pipefail

pause_screen() {
  echo ""
  read -r -p "Press Enter to return..." _
}

run_lpm() {
  if lpm "$@"; then
    return 0
  fi
  echo ""
  echo "ERROR: lpm $* failed. Review the message above before retrying." >&2
  return 1
}

app_center_tui() {
  while true; do
    clear
    echo "┌────────────────────────────────────────────────────────────────────────────┐"
    echo "│                           ShreeOS App Center                               │"
    echo "│                     Source-Built Software Repository                       │"
    echo "└────────────────────────────────────────────────────────────────────────────┘"
    echo ""
    echo "    [1] Discover Available Packages"
    echo "    [2] Search Software Catalog"
    echo "    [3] View Installed Applications"
    echo "    [4] Check & Apply Software Updates"
    echo "    [5] Verify Package Security & File Integrity"
    echo "    [q] Exit App Center"
    echo ""
    read -r -p "  Select section [1-5, q]: " CHOICE

    case "$CHOICE" in
      1)
        clear
        echo "==> Synchronizing repository index..."
        if run_lpm update; then
          echo ""
          echo "Available packages in ShreeOS repository:"
          echo "--------------------------------------------------------------------------"
          run_lpm search "" || true
        fi
        pause_screen
        ;;
      2)
        clear
        read -r -p "Enter search query: " QUERY
        if [ -n "$QUERY" ]; then
          echo ""
          run_lpm search "$QUERY" || true
          echo ""
          read -r -p "Install a package from results? Enter exact name (or Enter to skip): " PKG_NAME
          if [ -n "$PKG_NAME" ]; then
            run_lpm install "$PKG_NAME" || true
          fi
        fi
        pause_screen
        ;;
      3)
        clear
        echo "Installed Packages on this System:"
        echo "--------------------------------------------------------------------------"
        run_lpm list || true
        echo "--------------------------------------------------------------------------"
        echo ""
        read -r -p "Enter package name for details / remove (or Enter to skip): " PKG
        if [ -n "$PKG" ] && run_lpm query "$PKG"; then
          echo ""
          read -r -p "Remove this package? [y/N]: " REMOVE_CONFIRM
          if [ "$REMOVE_CONFIRM" = "y" ] || [ "$REMOVE_CONFIRM" = "Y" ]; then
            run_lpm remove "$PKG" || true
          fi
        fi
        pause_screen
        ;;
      4)
        clear
        echo "Checking for software updates..."
        if run_lpm upgrade --dry-run; then
          echo ""
          read -r -p "Apply available updates now? [y/N]: " APPLY
          if [ "$APPLY" = "y" ] || [ "$APPLY" = "Y" ]; then
            run_lpm upgrade || true
          fi
        fi
        pause_screen
        ;;
      5)
        clear
        read -r -p "Enter installed package name to verify: " PKG
        if [ -n "$PKG" ]; then
          run_lpm verify "$PKG" || true
        fi
        pause_screen
        ;;
      q|Q) break ;;
    esac
  done
}

if [ -t 0 ]; then
  app_center_tui
else
  st -g 85x26 -t "ShreeOS App Center" -e "$0" &
fi
