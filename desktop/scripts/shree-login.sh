#!/usr/bin/env bash
# desktop/scripts/shree-login.sh — ShreeOS Display Session & Login Manager
#
# Presents clean graphical user selection, authenticates credentials securely
# using shree-auth, drops root privileges, and executes the user session.

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

  echo "  Authenticating account: ${sel_user}"
  echo ""

  # Delegate to audited shree-auth binary which verifies /etc/shadow,
  # switches UID/GID, sets up groups, sanitizes environment, and execs startx
  if [ -x /usr/bin/shree-auth ]; then
    exec /usr/bin/shree-auth "$sel_user" --session /usr/bin/startx
  elif [ -x /sbin/shree-auth ]; then
    exec /sbin/shree-auth "$sel_user" --session /usr/bin/startx
  elif command -v su >/dev/null 2>&1; then
    exec su - "$sel_user" -c "/usr/bin/startx"
  else
    echo "CRITICAL ERROR: No secure authentication backend found (/usr/bin/shree-auth or su)." >&2
    exit 1
  fi
}

run_login_screen
