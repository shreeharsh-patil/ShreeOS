#!/usr/bin/env bash
# tests/smoke/test-desktop-suite.sh — Smoke test for ShreeOS Desktop Suite & System CLI
#
# Validates syntax, asset integrity, design tokens, and CLI tool functionality.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

echo "==> Testing ShreeOS Desktop Suite & Tools"

# 1. Syntax check all desktop scripts and applications
for f in "${PROJECT_ROOT}/desktop/scripts/"*.sh "${PROJECT_ROOT}/desktop/apps/"*.sh "${PROJECT_ROOT}/scripts/shree"*; do
  [ -f "$f" ] || continue
  bash -n "$f" || { echo "Syntax error in $f"; exit 1; }
done
echo "  [OK] All desktop scripts and system utilities pass syntax validation"

# 2. Verify design tokens and theme configuration
if [ -f "${PROJECT_ROOT}/branding/theme/tokens.conf" ] && [ -f "${PROJECT_ROOT}/branding/theme/tokens.css" ]; then
  echo "  [OK] Design system tokens verified"
else
  echo "  [FAIL] Design tokens missing"; exit 1
fi

# 3. Verify vector icon suite
REQUIRED_ICONS=(files terminal settings pkgmanager browser editor sysmon network about installer)
for icon in "${REQUIRED_ICONS[@]}"; do
  if [ -f "${PROJECT_ROOT}/branding/icons/${icon}.svg" ]; then
    grep -q "<svg" "${PROJECT_ROOT}/branding/icons/${icon}.svg" || { echo "Invalid SVG for $icon"; exit 1; }
  else
    echo "  [FAIL] Missing icon: ${icon}.svg"; exit 1
  fi
done
echo "  [OK] All 10 vector icon suite assets verified"

# 4. Verify system CLI tools execution
if [ -f "${PROJECT_ROOT}/scripts/shreectl" ]; then
  bash "${PROJECT_ROOT}/scripts/shreectl" --help >/dev/null
  echo "  [OK] shreectl responds to --help"
fi

if [ -f "${PROJECT_ROOT}/scripts/shreeinfo" ]; then
  bash "${PROJECT_ROOT}/scripts/shreeinfo" >/dev/null
  echo "  [OK] shreeinfo banner generates successfully"
fi

echo "==> All desktop suite smoke tests passed successfully!"
