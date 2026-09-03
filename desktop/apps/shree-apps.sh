#!/usr/bin/env bash
# desktop/apps/shree-apps.sh — ShreeOS App Center (LPM Frontend)
#
# Graphical / TUI frontend for lpm package management:
# Discover, Search, Installed Packages, and Software Updates.

set -euo pipefail

app_center_tui() {
  while true; do
    clear
    echo "┌────────────────────────────────────────────────────────────────────────────┐"
    echo "│                           ShreeOS App Center                               │"
    echo "│                     Source-Built Software Repository                       │"
    echo "└────────────────────────────────────────────────────────────────────────────┘"
    echo ""
    echo "  Sections:"
    echo "  ──────────────────────────────────────────────────────────────────────────"
    echo "    [1] Discover Available Packages (Repository Index)"
    echo "    [2] Search Software Catalog"
    echo "    [3] View Installed Applications"
    echo "    [4] Check & Apply Software Updates"
    echo "    [5] Verify Package Security & File Integrity"
    echo "    [q] Exit App Center"
    echo "  ──────────────────────────────────────────────────────────────────────────"
    echo ""
    read -r -p "  Select section [1-5, q]: " CHOICE

    case "$CHOICE" in
      1)
        clear
        echo "==> Synchronizing repository index..."
        lpm update || true
        echo ""
        echo "Available packages in ShreeOS repository:"
        echo "--------------------------------------------------------------------------"
        lpm search "" 2>/dev/null || echo "No packages in repository"
        echo "--------------------------------------------------------------------------"
        echo ""
        read -r -p "Press Enter to return..." _
        ;;
      2)
        clear
        read -r -p "Enter search query: " QUERY
        if [ -n "$QUERY" ]; then
          echo ""
          echo "Search results for '${QUERY}':"
          echo "--------------------------------------------------------------------------"
          lpm search "$QUERY" || echo "No matching packages found."
          echo "--------------------------------------------------------------------------"
          echo ""
          read -r -p "Install a package from results? Enter name (or press Enter to skip): " PKG_NAME
          if [ -n "$PKG_NAME" ]; then
            lpm install "$PKG_NAME" || true
          fi
        fi
        ;;
      3)
        clear
        echo "Installed Packages on this System:"
        echo "--------------------------------------------------------------------------"
        lpm list || echo "No packages installed"
        echo "--------------------------------------------------------------------------"
        echo ""
        read -r -p "Enter package name for details / remove (or Enter to skip): " PKG
        if [ -n "$PKG" ]; then
          lpm query "$PKG" || true
          echo ""
          read -r -p "Remove this package? [y/N]: " REMOVE_CONFIRM
          if [ "$REMOVE_CONFIRM" = "y" ] || [ "$REMOVE_CONFIRM" = "Y" ]; then
            lpm remove "$PKG" || true
          fi
        fi
        ;;
      4)
        clear
        echo "Checking for software updates..."
        lpm upgrade || true
        echo ""
        read -r -p "Press Enter to return..." _
        ;;
      5)
        clear
        read -r -p "Enter installed package name to verify: " PKG
        if [ -n "$PKG" ]; then
          echo ""
          lpm verify "$PKG" || true
        fi
        echo ""
        read -r -p "Press Enter to return..." _
        ;;
      q|Q)
        break
        ;;
    esac
  done
}

if [ -t 0 ]; then
  app_center_tui
else
  st -g 85x26 -t "ShreeOS App Center" -e "$0" &
fi
