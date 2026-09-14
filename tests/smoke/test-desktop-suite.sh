#!/usr/bin/env bash
# tests/smoke/test-desktop-suite.sh — Smoke test for ShreeOS Desktop Suite & System CLI
#
# Validates syntax, asset integrity, design tokens, and CLI tool functionality.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

echo "==> Testing ShreeOS Desktop Suite & System Tools"

# 1. Syntax check all desktop scripts, applications, installer, and CLI tools
for dir in "${PROJECT_ROOT}/desktop/scripts" "${PROJECT_ROOT}/desktop/apps" "${PROJECT_ROOT}/installer/scripts" "${PROJECT_ROOT}/scripts"; do
  [ -d "$dir" ] || continue
  for f in "$dir"/*; do
    [ -f "$f" ] || continue
    # If it is a shell script (has shebang or .sh)
    if head -n 1 "$f" 2>/dev/null | grep -qE '^#!/(bin|usr)'; then
      bash -n "$f" || { echo "Syntax error in $f"; exit 1; }
    fi
  done
done
echo "  [OK] All desktop scripts, installer scripts, and system utilities pass syntax validation"

# 2. Verify design tokens and theme configuration
if [ -f "${PROJECT_ROOT}/branding/theme/tokens.conf" ] && [ -f "${PROJECT_ROOT}/branding/theme/tokens.css" ]; then
  echo "  [OK] Design system tokens verified"
else
  echo "  [FAIL] Design tokens missing"; exit 1
fi

# 3. Verify vector icon suite and original wallpapers
REQUIRED_ICONS=(files terminal settings pkgmanager browser editor sysmon network about installer)
for icon in "${REQUIRED_ICONS[@]}"; do
  if [ -f "${PROJECT_ROOT}/branding/icons/${icon}.svg" ]; then
    grep -q "<svg" "${PROJECT_ROOT}/branding/icons/${icon}.svg" || { echo "Invalid SVG for $icon"; exit 1; }
  else
    echo "  [FAIL] Missing icon: ${icon}.svg"; exit 1
  fi
done
echo "  [OK] All 10 vector icon suite assets verified"

# Verify original wallpapers
for wp in "shreeos-calm-dark.svg" "shreeos-calm-light.svg" "shreeos-wallpaper.svg"; do
  if [ -f "${PROJECT_ROOT}/branding/wallpapers/${wp}" ]; then
    grep -q "<svg" "${PROJECT_ROOT}/branding/wallpapers/${wp}" || { echo "Invalid SVG for $wp"; exit 1; }
  else
    echo "  [FAIL] Missing wallpaper: ${wp}"; exit 1
  fi
done
echo "  [OK] Original ShreeOS abstract wallpapers verified"

# 4. Verify the macOS-style desktop configuration is actually wired into builds
grep -q 'cp "$distro_config" config.h' "${PROJECT_ROOT}/desktop/wm/build-wm.sh" || {
  echo "  [FAIL] ShreeOS WM config headers are not wired into the native build"; exit 1;
}
[ -f "${PROJECT_ROOT}/desktop/wm/patches/dwm-bar-height.patch" ] || {
  echo "  [FAIL] dwm menu-bar height patch missing"; exit 1;
}
[ -f "${PROJECT_ROOT}/desktop/wm/patches/dmenu-center.patch" ] || {
  echo "  [FAIL] centered Spotlight patch missing"; exit 1;
}
[ -f "${PROJECT_ROOT}/desktop/wm/shree-dock.c" ] || {
  echo "  [FAIL] persistent dock source missing"; exit 1;
}

if grep -R -n --include='*.sh' --include='shree-*' 'grep -oP'     "${PROJECT_ROOT}/desktop/scripts" "${PROJECT_ROOT}/desktop/apps"; then
  echo "  [FAIL] Desktop contains GNU-PCRE-only grep parsing"; exit 1
fi

if command -v cc >/dev/null 2>&1 &&
   printf '#include <X11/Xlib.h>\n' | cc -E -x c - >/dev/null 2>&1; then
  cc -std=c99 -Wall -Wextra -fsyntax-only "${PROJECT_ROOT}/desktop/wm/shree-dock.c"
  echo "  [OK] Persistent dock source passes C syntax validation"
fi

echo "  [OK] Native desktop configuration and compatibility patches verified"

# 5. Verify system CLI tools execution
if [ -f "${PROJECT_ROOT}/scripts/shreectl" ]; then
  bash "${PROJECT_ROOT}/scripts/shreectl" --help >/dev/null
  echo "  [OK] shreectl responds to --help"
fi

if [ -f "${PROJECT_ROOT}/scripts/shreeinfo" ]; then
  bash "${PROJECT_ROOT}/scripts/shreeinfo" >/dev/null
  echo "  [OK] shreeinfo banner generates successfully"
fi

if [ -f "${PROJECT_ROOT}/scripts/shree-doctor" ]; then
  bash "${PROJECT_ROOT}/scripts/shree-doctor" >/dev/null
  echo "  [OK] shree-doctor diagnostic suite executes successfully"
fi

echo "==> All desktop suite smoke tests passed successfully!"
