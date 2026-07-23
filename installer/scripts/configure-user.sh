#!/usr/bin/env bash
# installer/scripts/configure-user.sh — Create default user account on installed target rootfs
#
# Usage:
#   bash configure-user.sh <target-rootfs> <username> <password>
#
set -euo pipefail

if [ $# -lt 3 ]; then
  echo "Usage: configure-user.sh <target-rootfs> <username> <password>" >&2
  exit 1
fi

TARGET="$1"
USER="$2"
PASSWORD="$3"

if [ -z "$USER" ]; then
  exit 0
fi

# Ensure /home directory exists
mkdir -p "${TARGET}/home/${USER}"

# Add user entry to /etc/passwd if not present
if ! grep -q "^${USER}:" "${TARGET}/etc/passwd" 2>/dev/null; then
  echo "${USER}:x:1000:1000:${USER}:/home/${USER}:/bin/bash" >> "${TARGET}/etc/passwd"
  echo "${USER}:x:1000:" >> "${TARGET}/etc/group"
fi

# Set user password in shadow
ENCRYPTED_PASS=$(echo "$PASSWORD" | mkpasswd -m sha-512 -S "$(head -c 16 /dev/urandom | base64 | head -c 16)" 2>/dev/null || echo "$PASSWORD")
if grep -q "^${USER}:" "${TARGET}/etc/shadow" 2>/dev/null; then
  sed -i "s|^${USER}:[^:]*:|${USER}:${ENCRYPTED_PASS}:|" "${TARGET}/etc/shadow"
else
  echo "${USER}:${ENCRYPTED_PASS}:19000:0:99999:7:::" >> "${TARGET}/etc/shadow"
fi

echo "Configured user account ${USER} on ${TARGET}"
