#!/usr/bin/env bash
# desktop/scripts/shree-login.sh — ShreeOS Display Session & Login Manager
#
# Presents graphical user selection in X11 (or prompts on TTY),
# authenticates credentials securely via shree-auth, permanently drops
# root privileges, and executes the user desktop session. Fails closed.

set -euo pipefail

get_users() {
  awk -F':' '$3 >= 1000 && $3 < 65000 {print $1}' /etc/passwd 2>/dev/null || echo "${USER:-shree}"
}

run_login_screen() {
  local auth_bin=""
  if [ -x /usr/bin/shree-auth ]; then
    auth_bin="/usr/bin/shree-auth"
  elif [ -x /sbin/shree-auth ]; then
    auth_bin="/sbin/shree-auth"
  else
    echo "FATAL SECURITY ERROR: /usr/bin/shree-auth authentication binary is not available. Failing closed." >&2
    exit 1
  fi

  # If not in X11 display server, run terminal login loop
  if [ -z "${DISPLAY:-}" ]; then
    exec "$auth_bin" --login-tty
  fi

  local user_list
  user_list=$(get_users)
  local sel_user=""

  if command -v dmenu >/dev/null 2>&1; then
    sel_user=$(echo -e "$user_list\n[Power Off]\n[Reboot]" | dmenu -p "Login to ShreeOS" -l 5 -c || true)
  fi

  [ -z "$sel_user" ] && sel_user="${USER:-shree}"

  if [ "$sel_user" = "[Power Off]" ]; then
    initctl poweroff 2>/dev/null || poweroff
    exit 0
  elif [ "$sel_user" = "[Reboot]" ]; then
    initctl reboot 2>/dev/null || reboot
    exit 0
  fi

  # Authenticate through audited binary and drop privileges
  exec "$auth_bin" "$sel_user" --session /usr/bin/startx
}

run_login_screen
