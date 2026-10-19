#!/usr/bin/env bash
# ShreeOS dmenu launcher: apply the active appearance and UI font from Xresources.
set -euo pipefail

if ! command -v dmenu >/dev/null 2>&1; then
  printf 'shree-dmenu: dmenu is not installed\n' >&2
  exit 127
fi

resource() {
  local name="$1"
  xrdb -query 2>/dev/null | awk -v key="${name}:" '
    index($0, key) == 1 {
      sub(/^[^:]*:[[:space:]]*/, "")
      print
      exit
    }
  ' || true
}

config_value() {
  local name="$1" config="${XDG_CONFIG_HOME:-${HOME}/.config}/shreeos/theme-vars.sh"
  [ -r "$config" ] || return 0
  awk -v key="$name" '$1 == "export" && index($2, key "=") == 1 { sub(/^export [^=]+="/, ""); sub(/"$/, ""); print; exit }' "$config"
}

normal_bg=$(resource dmenu.normbg)
normal_fg=$(resource dmenu.normfg)
selected_bg=$(resource dmenu.selbg)
selected_fg=$(resource dmenu.selfg)
font=$(resource dmenu.font)

normal_bg="${normal_bg:-$(config_value SHREE_SURFACE_SEC)}"
normal_fg="${normal_fg:-$(config_value SHREE_TEXT)}"
selected_bg="${selected_bg:-$(config_value SHREE_ACCENT)}"
selected_fg="${selected_fg:-#FFFFFF}"
font="${font:-$(config_value SHREE_FONT_UI)}"
font_size=$(config_value SHREE_FONT_SIZE_UI)
if [[ "$font" != *:size=* ]]; then
  font="${font:-Inter}:size=${font_size:-13}:weight=medium:antialias=true:autohint=true"
fi

normal_bg="${normal_bg:-#1E1E20}"
normal_fg="${normal_fg:-#F5F5F7}"
selected_bg="${selected_bg:-#2878FF}"
selected_fg="${selected_fg:-#FFFFFF}"
font="${font:-Inter:size=13:weight=medium:antialias=true:autohint=true}"

exec dmenu -nb "$normal_bg" -nf "$normal_fg" -sb "$selected_bg" -sf "$selected_fg" -fn "$font" "$@"
