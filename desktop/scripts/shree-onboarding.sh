#!/usr/bin/env bash
# desktop/scripts/shree-onboarding.sh — ShreeOS First-Run Desktop Onboarding
#
# Runs once on initial user desktop login to configure theme, introduce key shortcuts,
# and initialize desktop directories.

set -euo pipefail

ONBOARDING_MARKER="${HOME}/.config/shreeos/.onboarding_complete"
mkdir -p "$(dirname "$ONBOARDING_MARKER")"

# If already completed, exit cleanly
[ -f "$ONBOARDING_MARKER" ] && exit 0

# Create standard user directories
mkdir -p "${HOME}/Desktop" "${HOME}/Documents" "${HOME}/Downloads" "${HOME}/Pictures/Screenshots" "${HOME}/Music" "${HOME}/Videos"

show_welcome() {
  clear
  echo "┌────────────────────────────────────────────────────────────────────────────┐"
  echo "│                            Welcome to ShreeOS                              │"
  echo "│                 Calm, Minimal, High-Performance Desktop                    │"
  echo "└────────────────────────────────────────────────────────────────────────────┘"
  echo ""
  echo "  ShreeOS is ready for daily use. Here are your essential shortcuts:"
  echo ""
  echo "    • Super + Space        Universal Spotlight Search & Calculator"
  echo "    • Super + K            Global Command Palette (Fast OS Actions)"
  echo "    • Super + Return       Open Terminal (st)"
  echo "    • Super + V            Clipboard History"
  echo "    • Super + Q            Close Window"
  echo "    • Super + 1 .. 4       Switch Workspaces"
  echo "    • PrintScreen          Take Screenshot"
  echo ""
  echo "  ──────────────────────────────────────────────────────────────────────────"
  echo "  [1] Select Dark Appearance (Default)"
  echo "  [2] Select Light Appearance"
  echo "  [3] Get Started"
  echo ""
  read -r -p "  Enter choice [1-3, default: 3]: " CHOICE

  case "$CHOICE" in
    1) shree-theme dark ;;
    2) shree-theme light ;;
  esac

  touch "$ONBOARDING_MARKER"
  echo ""
  echo "  Setup complete! Enjoy ShreeOS."
  sleep 1
}

if [ -t 0 ]; then
  show_welcome
else
  st -g 82x24 -t "Welcome to ShreeOS" -e "$0" &
fi
