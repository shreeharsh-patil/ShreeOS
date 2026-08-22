#!/usr/bin/env bash
# desktop/apps/shree-files.sh — ShreeOS Native File Manager
#
# Clean, lightweight desktop file manager with sidebar shortcuts,
# file operations (Rename, Trash, Delete, Copy Path, New Folder),
# search, and Quick Look integration.

set -euo pipefail

CURRENT_DIR="${1:-${HOME}}"
[ ! -d "$CURRENT_DIR" ] && CURRENT_DIR="$HOME"
cd "$CURRENT_DIR"

TRASH_DIR="${HOME}/.local/share/Trash/files"
mkdir -p "$TRASH_DIR"

handle_file_action() {
  local target="$1"
  local actions="Open / Quick Look\nRename\nMove to Trash\nDelete Permanently\nCopy File Path\nCancel"
  local act
  act=$(echo -e "$actions" | dmenu -p "Action: $(basename "$target")" -l 6 -c)
  [ -z "$act" ] && return

  case "$act" in
    "Open / Quick Look")
      shree-quicklook "$target" || xdg-open "$target" 2>/dev/null || shree-edit "$target" &
      ;;
    "Rename")
      local new_name
      new_name=$(echo "" | dmenu -p "New name for $(basename "$target"):" -c)
      if [ -n "$new_name" ]; then
        mv "$target" "$(dirname "$target")/$new_name"
        shree-notify "Files" "Renamed to ${new_name}" --app="Files"
      fi
      ;;
    "Move to Trash")
      mv "$target" "$TRASH_DIR/"
      shree-notify "Files" "Moved $(basename "$target") to Trash" --app="Files"
      ;;
    "Delete Permanently")
      local confirm
      confirm=$(printf "Cancel\nConfirm Permanent Deletion" | dmenu -p "Permanently delete $(basename "$target")?" -l 2 -c)
      if [ "$confirm" = "Confirm Permanent Deletion" ]; then
        rm -rf "$target"
        shree-notify "Files" "Permanently deleted $(basename "$target")" --app="Files"
      fi
      ;;
    "Copy File Path")
      if command -v xclip >/dev/null 2>&1; then
        echo -n "$(realpath "$target")" | xclip -selection clipboard -i
        shree-notify "Files" "Copied path to clipboard" --app="Files"
      fi
      ;;
  esac
}

browse_directory() {
  while true; do
    clear
    echo "┌────────────────────────────────────────────────────────────────────────────┐"
    echo "│  ShreeOS Files  │  Path: $(pwd)"
    echo "├────────────────────────────────────────────────────────────────────────────┤"
    echo "│  [SIDEBAR] ~:Home  Desktop  Documents  Downloads  Pictures  Trash  Root     │"
    echo "├────────────────────────────────────────────────────────────────────────────┤"
    
    local items=()
    # Utility actions first
    items+=(".. (Parent Directory)")
    items+=("➕ [Create New Folder]")
    items+=("🔍 [Search Files in Directory]")
    items+=("💻 [Open Terminal Here]")
    items+=("📌 [Jump to Home Directory]")
    items+=("📌 [Jump to Downloads]")
    items+=("📌 [Jump to Trash]")

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

    local idx=1
    for item in "${items[@]}"; do
      if [ $idx -le 16 ]; then
        printf "  %-3s %s\n" "[$idx]" "$item"
      fi
      idx=$((idx + 1))
    done

    echo "├────────────────────────────────────────────────────────────────────────────┤"
    echo "│ [Navigation] Select item to open or manage file actions                    │"
    echo "└────────────────────────────────────────────────────────────────────────────┘"
    echo ""

    local choice
    choice=$(printf "%s\n" "${items[@]}" | dmenu -p "Files: $(basename "$(pwd)")" -l 10 -c || true)
    
    [ -z "$choice" ] && break

    case "$choice" in
      ".. (Parent Directory)")
        cd ..
        ;;
      "➕ [Create New Folder]")
        local new_dir
        new_dir=$(echo "" | dmenu -p "Enter new folder name:" -c)
        if [ -n "$new_dir" ]; then
          mkdir -p "$new_dir"
          shree-notify "Files" "Created folder '${new_dir}'" --app="Files"
        fi
        ;;
      "🔍 [Search Files in Directory]")
        local q
        q=$(echo "" | dmenu -p "Search file name in $(basename "$(pwd)"):" -c)
        if [ -n "$q" ]; then
          local res
          res=$(find . -iname "*${q}*" 2>/dev/null | head -n 10 || true)
          local sel
          sel=$(echo -e "$res" | dmenu -p "Search Results:" -l 6 -c)
          [ -n "$sel" ] && handle_file_action "$sel"
        fi
        ;;
      "💻 [Open Terminal Here]")
        st &
        ;;
      "📌 [Jump to Home Directory]")
        cd "$HOME"
        ;;
      "📌 [Jump to Downloads]")
        mkdir -p "${HOME}/Downloads"
        cd "${HOME}/Downloads"
        ;;
      "📌 [Jump to Trash]")
        cd "$TRASH_DIR"
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
          handle_file_action "$filename"
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
