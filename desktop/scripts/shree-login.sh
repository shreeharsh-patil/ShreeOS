#!/usr/bin/env bash
# desktop/scripts/shree-login.sh — ShreeOS Graphical Login & Display Session Manager
#
# Presents a clean, calm user selection and authentication screen,
# initializing user environment and launching the desktop session.

set -euo pipefail

get_users() {
  awk -F':' '$3 >= 1000 && $3 < 65000 {print $1}' /etc/passwd 2>/dev/null || echo "${USER:-shree}"
}

run_login_screen() {
  clear
  echo "┌────────────────────────────────────────────────────────────────────────────┐"
  echo "│                                                                            │"
  echo "│                                  ShreeOS                                   │"
  echo "│                                                                            │"
  echo "└────────────────────────────────────────────────────────────────────────────┘"
  echo ""
  echo "  Select User Account to Log In:"
  echo "  ──────────────────────────────────────────────────────────────────────────"
  
  local user_list
  user_list=$(get_users)
  local sel_user
  sel_user=$(echo -e "$user_list\n[Power Off]\n[Reboot]" | dmenu -p "Login to ShreeOS" -l 5 -c || true)

  [ -z "$sel_user" ] && sel_user="${USER:-shree}"

  if [ "$sel_user" = "[Power Off]" ]; then
    initctl poweroff || poweroff
    exit 0
  elif [ "$sel_user" = "[Reboot]" ]; then
    initctl reboot || reboot
    exit 0
  fi

  echo "  Logging into account: ${sel_user}"
  echo ""
  
  # Launch desktop session for selected user
  export USER="$sel_user"
  export HOME="/home/${sel_user}"
  [ ! -d "$HOME" ] && export HOME="/root"

  exec startx
}

run_login_screen
