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

# 4. Verify system CLI tools execution
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
