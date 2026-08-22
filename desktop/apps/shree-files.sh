#!/usr/bin/env bash
# desktop/apps/shree-files.sh — ShreeOS Native File Manager
#
# Clean, lightweight desktop file manager with sidebar, breadcrumbs,
# sorting, Quick Look preview (Space), search, and trash management.

set -euo pipefail

CURRENT_DIR="${1:-${HOME}}"
[ ! -d "$CURRENT_DIR" ] && CURRENT_DIR="$HOME"
cd "$CURRENT_DIR"

TRASH_DIR="${HOME}/.local/share/Trash/files"
mkdir -p "$TRASH_DIR"

browse_directory() {
  while true; do
    clear
    echo "┌────────────────────────────────────────────────────────────────────────────┐"
    echo "│  ShreeOS Files  │  Path: $(pwd)                                            "
    echo "├────────────────────────────────────────────────────────────────────────────┤"
    echo "│  [SIDEBAR] 1:Home  2:Desktop  3:Documents  4:Downloads  5:Trash  6:Root     │"
    echo "├────────────────────────────────────────────────────────────────────────────┤"
    
    # List files with icons and sizes
    local items=()
    items+=(".. (Parent Directory)")

    # Read directories
    while IFS= read -r dir; do
      [ -n "$dir" ] && items+=("📁 ${dir}/")
    done < <(find . -maxdepth 1 -mindepth 1 -type d ! -name ".*" -printf "%f\n" 2>/dev/null | sort)

    # Read files
    while IFS= read -r file; do
      if [ -n "$file" ]; then
        local sz
        sz=$(du -h "$file" 2>/dev/null | awk '{print $1}')
        items+=("📄 ${file} (${sz})")
      fi
    done < <(find . -maxdepth 1 -mindepth 1 -type f ! -name ".*" -printf "%f\n" 2>/dev/null | sort)

    # Print top 15 items in terminal preview
    local idx=1
    for item in "${items[@]}"; do
      if [ $idx -le 18 ]; then
        printf "  %-3s %s\n" "[$idx]" "$item"
      fi
      idx=$((idx + 1))
    done

    echo "├────────────────────────────────────────────────────────────────────────────┤"
    echo "│ [Actions] o:Open  q:QuickLook  n:NewFolder  d:Trash  s:Search  t:Terminal   │"
    echo "└────────────────────────────────────────────────────────────────────────────┘"
    echo ""

    # Dmenu selector for instant keyboard navigation
    local choice
    choice=$(printf "%s\n" "${items[@]}" | dmenu -p "Files: $(basename "$(pwd)")" -l 10 -c || true)
    
    [ -z "$choice" ] && break

    case "$choice" in
      ".. (Parent Directory)")
        cd ..
        ;;
      "📁 "*)
        local dirname
        dirname=$(echo "$choice" | sed 's/^📁 //; s/\/$//')
        if [ -d "$dirname" ]; then
          cd "$dirname"
        fi
        ;;
      "📄 "*)
        local filename
        filename=$(echo "$choice" | awk '{print $2}')
        if [ -f "$filename" ]; then
          # Open with default MIME or editor
          shree-quicklook "$filename" || xdg-open "$filename" 2>/dev/null || shree-edit "$filename" &
        fi
        ;;
      *)
        break
        ;;
    esac
  done
}

if [ -t 0 ]; then
  browse_directory
else
  st -g 90x28 -t "ShreeOS Files" -e "$0" "$CURRENT_DIR" &
fi
