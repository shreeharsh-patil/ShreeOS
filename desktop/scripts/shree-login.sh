#!/usr/bin/env bash
# desktop/scripts/shree-login.sh — macOS-Inspired Login Experience for ShreeOS
#
# Clean, centered user session login:
#   - Centered user avatar monogram [ U ]
#   - User account selection & display
#   - Password authentication via audited /usr/bin/shree-auth
#   - Minimal ShreeOS branding (⟡ ShreeOS 0.2.0-dev)
#   - Quick [Shutdown] and [Reboot] controls
#   - Strict security: permanent privilege drop, fails closed
#
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
  local formatted_choices=""

  while IFS= read -r u; do
    [ -z "$u" ] && continue
    local initial="${u:0:1}"
    initial="${initial^^}"
    formatted_choices+="[  ${initial}  ]  ${u}\n"
  done <<< "$user_list"

  formatted_choices+="[ ⏻ ]  Shutdown Computer\n[ ↺ ]  Restart Computer"

  local sel_entry=""
  if command -v dmenu >/dev/null 2>&1; then
    sel_entry=$(echo -e "$formatted_choices" | dmenu -p "⟡ ShreeOS 0.2.0-dev" -l 6 -c || true)
  fi

  [ -z "$sel_entry" ] && sel_entry="[  S  ]  ${USER:-shree}"

  if [[ "$sel_entry" =~ "Shutdown" ]]; then
    initctl poweroff 2>/dev/null || poweroff
    exit 0
  elif [[ "$sel_entry" =~ "Restart" ]]; then
    initctl reboot 2>/dev/null || reboot
    exit 0
  fi

  local sel_user
  sel_user=$(echo "$sel_entry" | awk '{print $NF}')
  [ -z "$sel_user" ] && sel_user="${USER:-shree}"

  # Authenticate through audited binary and drop privileges to start user session
  exec "$auth_bin" "$sel_user" --session /usr/bin/startx
}

run_login_screen
