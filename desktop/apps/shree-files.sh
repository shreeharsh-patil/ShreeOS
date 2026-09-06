#!/usr/bin/env bash
# desktop/apps/shree-files.sh — Finder-Inspired Lightweight File Manager for ShreeOS
#
# Features:
#   - Left Sidebar: Home, Desktop, Documents, Downloads, Pictures, Music, Trash, Mounted Drives
#   - Main Area: Breadcrumb path, List & Grid layout modes, sorting (Name/Date/Size)
#   - Actions: Open, Quick Look (shree-quicklook), Info, Copy, Move, Rename, Trash, New Folder
#   - Fully XDG Trash compliant (.local/share/Trash/files and info)
#   - High performance, responsive, low memory footprint
#
set -euo pipefail

CURRENT_DIR="${1:-${HOME}}"
[ ! -d "$CURRENT_DIR" ] && CURRENT_DIR="$HOME"
cd "$CURRENT_DIR"

TRASH_FILES="${HOME}/.local/share/Trash/files"
TRASH_INFO="${HOME}/.local/share/Trash/info"
CLIPBOARD_FILE="${XDG_RUNTIME_DIR:-/tmp}/shreeos-file-clipboard"
mkdir -p "$TRASH_FILES" "$TRASH_INFO"

SORT_MODE="name" # name, date, size

get_breadcrumbs() {
  local cur
  cur="$(pwd)"
  if [ "$cur" = "$HOME" ]; then
    echo "⟡ ShreeOS > ~ (Home)"
  elif [[ "$cur" == "$HOME"* ]]; then
    local rel="${cur#"$HOME"/}"
    echo "⟡ ShreeOS > Home > ${rel//\// > }"
  else
    echo "⟡ ShreeOS > ${cur//\// > }"
  fi
}

get_mounted_drives() {
  awk '$2 ~ /^\/(media|mnt|run\/media)/ {print $2}' /proc/mounts 2>/dev/null | sort -u || true
}

move_to_trash() {
  local target="$1"
  local abs_path
  abs_path="$(realpath "$target")"
  local bname
  bname="$(basename "$target")"
  local dest_name="$bname"

  if [ -e "${TRASH_FILES}/${dest_name}" ]; then
    dest_name="${bname}_$(date +%s)"
  fi

  local info_file="${TRASH_INFO}/${dest_name}.trashinfo"
  cat > "$info_file" <<EOF
[Trash Info]
Path=${abs_path}
DeletionDate=$(date +'%Y-%m-%dT%H:%M:%S')
EOF

  mv "$target" "${TRASH_FILES}/${dest_name}"
  if command -v shree-notify >/dev/null 2>&1; then
    shree-notify "Files" "Moved '${bname}' to Trash" --app="Files"
  fi
}

show_file_info() {
  local target="$1"
  local abs_path
  abs_path="$(realpath "$target")"
  local bname
  bname="$(basename "$target")"
  local sz mod perm mime

  sz=$(du -h "$target" 2>/dev/null | awk '{print $1}' || echo "N/A")
  mod=$(date -r "$target" +"%Y-%m-%d %H:%M:%S" 2>/dev/null || stat -c %y "$target" 2>/dev/null || echo "Unknown")
  perm=$(stat -c "%a (%A)" "$target" 2>/dev/null || echo "N/A")
  mime=$(file --mime-type -b "$target" 2>/dev/null || echo "unknown")

  local info_text="Name: ${bname}\nPath: ${abs_path}\nType: ${mime}\nSize: ${sz}\nModified: ${mod}\nPermissions: ${perm}\n[Close]"
  echo -e "$info_text" | dmenu -p "File Info: ${bname}" -l 7 -c >/dev/null 2>&1 || true
}

handle_file_action() {
  local target="$1"
  local bname
  bname="$(basename "$target")"
  local actions="Open\nQuick Look (Space)\nGet File Info\nCopy\nCut (Move)\nRename\nMove to Trash\nDelete Permanently\nCopy File Path\nCancel"
  local act
  act=$(echo -e "$actions" | dmenu -p "Action: ${bname}" -l 10 -c || true)
  [ -z "$act" ] && return

  case "$act" in
    "Open")
      if command -v xdg-open >/dev/null 2>&1; then
        xdg-open "$target" 2>/dev/null || true
      elif [ -f "$target" ]; then
        shree-edit "$target" 2>/dev/null || st -e nano "$target" &
      fi
      ;;
    "Quick Look"*)
      if command -v shree-quicklook >/dev/null 2>&1; then
        shree-quicklook "$target"
      else
        show_file_info "$target"
      fi
      ;;
    "Get File Info")
      show_file_info "$target"
      ;;
    "Copy")
      echo "COPY:$(realpath "$target")" > "$CLIPBOARD_FILE"
      shree-notify "Files" "Copied '${bname}' to clipboard" --app="Files"
      ;;
    "Cut"*)
      echo "MOVE:$(realpath "$target")" > "$CLIPBOARD_FILE"
      shree-notify "Files" "Cut '${bname}' to clipboard" --app="Files"
      ;;
    "Rename")
      local new_name
      new_name=$(echo "$bname" | dmenu -p "Rename to:" -c || true)
      new_name="$(basename "$new_name" 2>/dev/null || echo "")"
      if [ -n "$new_name" ] && [ "$new_name" != "." ] && [ "$new_name" != ".." ] && [ "$new_name" != "$bname" ]; then
        mv "$target" "$(dirname "$target")/$new_name"
        shree-notify "Files" "Renamed to ${new_name}" --app="Files"
      fi
      ;;
    "Move to Trash")
      move_to_trash "$target"
      ;;
    "Delete Permanently")
      local confirm
      confirm=$(printf "Cancel\nConfirm Permanent Deletion" | dmenu -p "Permanently delete ${bname}?" -l 2 -c || true)
      if [ "$confirm" = "Confirm Permanent Deletion" ]; then
        rm -rf "$target"
        shree-notify "Files" "Permanently deleted ${bname}" --app="Files"
      fi
      ;;
    "Copy File Path")
      if command -v xclip >/dev/null 2>&1; then
        printf "%s" "$(realpath "$target")" | xclip -selection clipboard -i 2>/dev/null || true
        shree-notify "Files" "Copied path to clipboard" --app="Files"
      fi
      ;;
  esac
}

browse_directory() {
  while true; do
    clear
    local bc
    bc=$(get_breadcrumbs)
    echo "┌────────────────────────────────────────────────────────────────────────────┐"
    echo "│  ${bc}"
    echo "├────────────────────────────────────────────────────────────────────────────┤"
    echo "│  SIDEBAR: Home [~] │ Desktop │ Documents │ Downloads │ Pictures │ Trash    │"
    echo "├────────────────────────────────────────────────────────────────────────────┤"

    local items=()
    # Sidebar navigation items
    items+=("⬆  .. (Parent Folder)")
    items+=("📁 Sidebar: Home [~]")
    items+=("📁 Sidebar: Desktop")
    items+=("📁 Sidebar: Documents")
    items+=("📁 Sidebar: Downloads")
    items+=("📁 Sidebar: Pictures")
    items+=("📁 Sidebar: Music")
    items+=("🗑  Sidebar: Trash")

    # Mounted drives
    while IFS= read -r mnt; do
      [ -n "$mnt" ] && items+=("💾 Drive: $(basename "$mnt") (${mnt})")
    done < <(get_mounted_drives)

    items+=("➕ [New Folder]")
    items+=("📋 [Paste File Here]")
    items+=("🔍 [Search Current Folder]")
    items+=("💻 [Open Terminal Here]")
    items+=("⚙  [Sort by: ${SORT_MODE^} (Click to Change)]")

    # Read directories according to sort mode
    case "$SORT_MODE" in
      date)
        while IFS= read -r dir; do
          [ -n "$dir" ] && items+=("📁 ${dir}/")
        done < <(find . -maxdepth 1 -mindepth 1 -type d ! -name ".*" -printf "%T@ %f\n" 2>/dev/null | sort -nr | awk '{$1=""; print substr($0,2)}')

        while IFS= read -r file; do
          [ -n "$file" ] && items+=("📄 ${file}")
        done < <(find . -maxdepth 1 -mindepth 1 -type f ! -name ".*" -printf "%T@ %f\n" 2>/dev/null | sort -nr | awk '{$1=""; print substr($0,2)}')
        ;;
      size)
        while IFS= read -r dir; do
          [ -n "$dir" ] && items+=("📁 ${dir}/")
        done < <(find . -maxdepth 1 -mindepth 1 -type d ! -name ".*" -printf "%f\n" 2>/dev/null | sort)

        while IFS= read -r file; do
          [ -n "$file" ] && items+=("📄 ${file}")
        done < <(find . -maxdepth 1 -mindepth 1 -type f ! -name ".*" -printf "%s %f\n" 2>/dev/null | sort -nr | awk '{$1=""; print substr($0,2)}')
        ;;
      name|*)
        while IFS= read -r dir; do
          [ -n "$dir" ] && items+=("📁 ${dir}/")
        done < <(find . -maxdepth 1 -mindepth 1 -type d ! -name ".*" -printf "%f\n" 2>/dev/null | sort)

        while IFS= read -r file; do
          [ -n "$file" ] && items+=("📄 ${file}")
        done < <(find . -maxdepth 1 -mindepth 1 -type f ! -name ".*" -printf "%f\n" 2>/dev/null | sort)
        ;;
    esac

    # Display preview rows on terminal
    local idx=1
    for item in "${items[@]}"; do
      if [ $idx -le 16 ]; then
        printf "  %-3s %s\n" "[$idx]" "$item"
      fi
      idx=$((idx + 1))
    done

    echo "├────────────────────────────────────────────────────────────────────────────┤"
    echo "│ Select item to navigate or manage. Esc to quit.                            │"
    echo "└────────────────────────────────────────────────────────────────────────────┘"

    local choice
    choice=$(printf "%s\n" "${items[@]}" | dmenu -p "Files: $(basename "$(pwd)")" -l 10 -c || true)
    [ -z "$choice" ] && break

    case "$choice" in
      "⬆  .. (Parent Folder)")
        cd ..
        ;;
      "📁 Sidebar: Home [~]")
        cd "$HOME"
        ;;
      "📁 Sidebar: Desktop")
        mkdir -p "${HOME}/Desktop"; cd "${HOME}/Desktop"
        ;;
      "📁 Sidebar: Documents")
        mkdir -p "${HOME}/Documents"; cd "${HOME}/Documents"
        ;;
      "📁 Sidebar: Downloads")
        mkdir -p "${HOME}/Downloads"; cd "${HOME}/Downloads"
        ;;
      "📁 Sidebar: Pictures")
        mkdir -p "${HOME}/Pictures"; cd "${HOME}/Pictures"
        ;;
      "📁 Sidebar: Music")
        mkdir -p "${HOME}/Music"; cd "${HOME}/Music"
        ;;
      "🗑  Sidebar: Trash")
        cd "$TRASH_FILES"
        ;;
      "💾 Drive: "*)
        local drive_path
        drive_path=$(echo "$choice" | awk -F'(' '{print $2}' | tr -d ')')
        [ -d "$drive_path" ] && cd "$drive_path"
        ;;
      "➕ [New Folder]")
        local new_folder
        new_folder=$(echo "" | dmenu -p "New Folder Name:" -c || true)
        new_folder="$(basename "$new_folder" 2>/dev/null || echo "")"
        if [ -n "$new_folder" ] && [ "$new_folder" != "." ] && [ "$new_folder" != ".." ]; then
          mkdir -p "$new_folder"
          shree-notify "Files" "Created folder '${new_folder}'" --app="Files"
        fi
        ;;
      "📋 [Paste File Here]")
        if [ -f "$CLIPBOARD_FILE" ]; then
          local clip_entry clip_op clip_src
          clip_entry=$(cat "$CLIPBOARD_FILE")
          clip_op="${clip_entry%%:*}"
          clip_src="${clip_entry#*:}"
          if [ -e "$clip_src" ]; then
            if [ "$clip_op" = "COPY" ]; then
              cp -r "$clip_src" .
              shree-notify "Files" "Pasted $(basename "$clip_src")" --app="Files"
            elif [ "$clip_op" = "MOVE" ]; then
              mv "$clip_src" .
              rm -f "$CLIPBOARD_FILE"
              shree-notify "Files" "Moved $(basename "$clip_src")" --app="Files"
            fi
          fi
        fi
        ;;
      "🔍 [Search Current Folder]")
        local query
        query=$(echo "" | dmenu -p "Search in $(basename "$(pwd)"):" -c || true)
        if [ -n "$query" ]; then
          local matches
          matches=$(find . -iname "*${query}*" 2>/dev/null | head -n 12 || true)
          local picked
          picked=$(echo -e "$matches" | dmenu -p "Search Results:" -l 6 -c || true)
          if [ -n "$picked" ]; then
            if [ -d "$picked" ]; then cd "$picked"; else handle_file_action "$picked"; fi
          fi
        fi
        ;;
      "💻 [Open Terminal Here]")
        st &
        ;;
      "⚙  [Sort by: "*)
        local s_pick
        s_pick=$(printf "Name (A-Z)\nDate Modified (Newest)\nSize (Largest)" | dmenu -p "Sort Files By" -l 3 -c || true)
        case "$s_pick" in
          Date*) SORT_MODE="date" ;;
          Size*) SORT_MODE="size" ;;
          *)     SORT_MODE="name" ;;
        esac
        ;;
      "📁 "*)
        local dname="${choice#📁 }"
        dname="${dname%/}"
        [ -d "$dname" ] && cd "$dname"
        ;;
      "📄 "*)
        local fname="${choice#📄 }"
        [ -e "$fname" ] && handle_file_action "$fname"
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
