#!/usr/bin/env bash
# desktop/apps/shree-files.sh — ShreeOS Native File Manager
#
# Clean, lightweight desktop file manager with sidebar shortcuts,
# XDG Trash compliance, robust space handling, basename validation,
# and Quick Look integration.

set -euo pipefail

CURRENT_DIR="${1:-${HOME}}"
[ ! -d "$CURRENT_DIR" ] && CURRENT_DIR="$HOME"
cd "$CURRENT_DIR"

TRASH_FILES="${HOME}/.local/share/Trash/files"
TRASH_INFO="${HOME}/.local/share/Trash/info"
mkdir -p "$TRASH_FILES" "$TRASH_INFO"

move_to_trash() {
  local target="$1"
  local abs_path
  abs_path="$(realpath "$target")"
  local bname
  bname="$(basename "$target")"
  local dest_name="$bname"

  # Handle filename collisions in Trash
  if [ -e "${TRASH_FILES}/${dest_name}" ]; then
    dest_name="${bname}_$(date +%s)"
  fi

  # 1. Create .trashinfo metadata file
  local info_file="${TRASH_INFO}/${dest_name}.trashinfo"
  cat > "$info_file" <<EOF
[Trash Info]
Path=${abs_path}
DeletionDate=$(date +'%Y-%m-%dT%H:%M:%S')
EOF

  # 2. Move file to Trash
  mv "$target" "${TRASH_FILES}/${dest_name}"
  shree-notify "Files" "Moved '${bname}' to Trash" --app="Files"
}

handle_file_action() {
  local target="$1"
  local bname
  bname="$(basename "$target")"
  local actions="Open / Quick Look\nRename\nMove to Trash\nDelete Permanently\nCopy File Path\nCancel"
  local act
  act=$(echo -e "$actions" | dmenu -p "Action: ${bname}" -l 6 -c)
  [ -z "$act" ] && return

  case "$act" in
    "Open / Quick Look")
      shree-quicklook "$target" || xdg-open "$target" 2>/dev/null || true
      ;;
    "Rename")
      local new_name
      new_name=$(echo "" | dmenu -p "New name for ${bname}:" -c)
      new_name="$(basename "$new_name" 2>/dev/null || echo "")"
      if [ -n "$new_name" ] && [ "$new_name" != "." ] && [ "$new_name" != ".." ]; then
        mv "$target" "$(dirname "$target")/$new_name"
        shree-notify "Files" "Renamed to ${new_name}" --app="Files"
      fi
      ;;
    "Move to Trash")
      move_to_trash "$target"
      ;;
    "Delete Permanently")
      local confirm
      confirm=$(printf "Cancel\nConfirm Permanent Deletion" | dmenu -p "Permanently delete ${bname}?" -l 2 -c)
      if [ "$confirm" = "Confirm Permanent Deletion" ]; then
        rm -rf "$target"
        shree-notify "Files" "Permanently deleted ${bname}" --app="Files"
      fi
      ;;
    "Copy File Path")
      if command -v xclip >/dev/null 2>&1; then
        printf "%s" "$(realpath "$target")" | xclip -selection clipboard -i
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
      [ -n "$file" ] && items+=("📄 ${file}")
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
        new_dir="$(basename "$new_dir" 2>/dev/null || echo "")"
        if [ -n "$new_dir" ] && [ "$new_dir" != "." ] && [ "$new_dir" != ".." ]; then
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
        cd "$TRASH_FILES"
        ;;
      "📁 "*)
        local dirname="${choice#📁 }"
        dirname="${dirname%/}"
        if [ -d "$dirname" ]; then
          cd "$dirname"
        fi
        ;;
      "📄 "*)
        local filename="${choice#📄 }"
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
