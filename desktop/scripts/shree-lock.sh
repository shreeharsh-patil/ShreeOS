#!/usr/bin/env bash
# desktop/scripts/shree-lock.sh — ShreeOS Secure Screen Locker
#
# Delegates strictly to a trusted X11 screen locker (slock or i3lock).
# Fails closed if no authenticating screen locker binary is present.

set -euo pipefail

if command -v slock >/dev/null 2>&1; then
  exec slock
elif command -v i3lock >/dev/null 2>&1; then
  exec i3lock -c 1C1C1E --ring-color=2878FF --keyhl-color=60A0FF
elif [ -x /usr/bin/shree-auth ] && /usr/bin/shree-auth --check-lock >/dev/null 2>&1; then
  exec /usr/bin/shree-auth --lock
else
  # FAIL CLOSED: Never provide an unauthenticated fake lock screen
  if command -v shree-notify >/dev/null 2>&1; then
    shree-notify "Security Alert" "Cannot lock screen: No trusted screen locker (slock/i3lock) found on system." --app="Security" --urgent
  fi
  echo "Error: No trusted screen locker (slock/i3lock) is installed. Refusing to start an insecure lock screen." >&2
  exit 1
fi
