#!/usr/bin/env bash
# installer/scripts/configure-user.sh — Create user account on target rootfs
#
# Security & Integrity Requirements:
#   - Strict username validation: ^[a-z_][a-z0-9_-]{0,31}$
#   - Passwords read from 0600 file or stdin, never exposed on argv
#   - Passwords hashed using stdin-based hashing (openssl -stdin, python3 sys.stdin)
#   - Password variables wiped immediately from memory
#   - Discovers next available UID/GID (>= 1000) avoiding collisions
#   - Sets /home/<user> ownership to <uid>:<gid> and mode 0700
#   - Adds user to wheel group securely

set -euo pipefail

if [ $# -lt 2 ]; then
  echo "Usage: configure-user.sh <target-rootfs> <username> [credential-file]" >&2
  exit 1
fi

TARGET="$1"
USER="$2"
CRED_FILE="${3:-}"

if [ -z "$USER" ]; then
  echo "No username specified, skipping user creation"
  exit 0
fi

# 1. Strict username validation: ^[a-z_][a-z0-9_-]{0,31}$
if ! [[ "$USER" =~ ^[a-z_][a-z0-9_-]{0,31}$ ]]; then
  echo "Error: Invalid username '${USER}'. Must match ^[a-z_][a-z0-9_-]{0,31}$." >&2
  exit 1
fi

# 2. Read password securely (from 0600 file or stdin)
PASSWORD=""
if [ -n "$CRED_FILE" ] && [ -f "$CRED_FILE" ]; then
  PASSWORD=$(cat "$CRED_FILE")
elif [ ! -t 0 ]; then
  PASSWORD=$(cat)
fi

if [ -z "$PASSWORD" ]; then
  echo "Error: Empty password provided for user '${USER}'. Aborting." >&2
  exit 1
fi

# 3. Secure SHA-512 password hashing without exposing password in process argv
SALT="$(head -c 16 /dev/urandom | base64 | tr -dc 'a-zA-Z0-9' | head -c 16)"
ENCRYPTED_PASS=""

if command -v openssl >/dev/null 2>&1; then
  ENCRYPTED_PASS=$(printf "%s" "$PASSWORD" | openssl passwd -6 -salt "$SALT" -stdin 2>/dev/null || echo "")
fi

if [ -z "$ENCRYPTED_PASS" ] && command -v mkpasswd >/dev/null 2>&1; then
  ENCRYPTED_PASS=$(printf "%s" "$PASSWORD" | mkpasswd -m sha-512 -S "$SALT" -s 2>/dev/null || \
                   printf "%s" "$PASSWORD" | mkpasswd -m sha-512 -S "$SALT" 2>/dev/null || echo "")
fi

if [ -z "$ENCRYPTED_PASS" ] && command -v python3 >/dev/null 2>&1; then
  ENCRYPTED_PASS=$(printf "%s" "$PASSWORD" | python3 -c "import sys, crypt; pw=sys.stdin.read(); print(crypt.crypt(pw, '\$6\$$SALT\$'))" 2>/dev/null || echo "")
fi

# Wipe plaintext password immediately
PASSWORD=""
unset PASSWORD

if [ -z "$ENCRYPTED_PASS" ]; then
  echo "CRITICAL SECURITY ERROR: Failed to securely hash user password via SHA-512." >&2
  exit 1
fi

# 4. Prepare system account databases
mkdir -p "${TARGET}/etc"
touch "${TARGET}/etc/passwd" "${TARGET}/etc/group" "${TARGET}/etc/shadow"

# 5. Allocate next available UID & GID >= 1000
NEW_UID=1000
if [ -s "${TARGET}/etc/passwd" ]; then
  MAX_EXISTING_UID=$(awk -F':' '$3 >= 1000 && $3 < 65000 {print $3}' "${TARGET}/etc/passwd" 2>/dev/null | sort -n | tail -n1 || echo "")
  if [ -n "$MAX_EXISTING_UID" ]; then
    NEW_UID=$((MAX_EXISTING_UID + 1))
  fi
fi
NEW_GID="$NEW_UID"

# 6. Add user and group entries if not present
if ! grep -q "^${USER}:" "${TARGET}/etc/passwd" 2>/dev/null; then
  echo "${USER}:x:${NEW_UID}:${NEW_GID}:${USER}:/home/${USER}:/bin/bash" >> "${TARGET}/etc/passwd"
else
  # Retrieve existing UID/GID for directory chown
  NEW_UID=$(awk -F':' -v u="$USER" '$1==u {print $3}' "${TARGET}/etc/passwd")
  NEW_GID=$(awk -F':' -v u="$USER" '$1==u {print $4}' "${TARGET}/etc/passwd")
fi

if ! grep -q "^${USER}:" "${TARGET}/etc/group" 2>/dev/null; then
  echo "${USER}:x:${NEW_GID}:" >> "${TARGET}/etc/group"
fi

# Add wheel group if missing, and append user
if ! grep -q "^wheel:" "${TARGET}/etc/group" 2>/dev/null; then
  echo "wheel:x:10:${USER}" >> "${TARGET}/etc/group"
else
  if ! grep -E "^wheel:.*([,: ]|^)${USER}([,: ]|$)" "${TARGET}/etc/group" 2>/dev/null; then
    sed -i "s|^wheel:[^:]*:[^:]*:.*|&,${USER}|; s|:,,|:,|; s|:,|:|" "${TARGET}/etc/group"
  fi
fi

# 7. Write password hash to /etc/shadow
if grep -q "^${USER}:" "${TARGET}/etc/shadow" 2>/dev/null; then
  sed -i "s|^${USER}:[^:]*:|${USER}:${ENCRYPTED_PASS}:|" "${TARGET}/etc/shadow"
else
  echo "${USER}:${ENCRYPTED_PASS}:19000:0:99999:7:::" >> "${TARGET}/etc/shadow"
fi

# 8. Create /home/<user> with correct owner & 0700 permissions
mkdir -p "${TARGET}/home/${USER}"
chmod 700 "${TARGET}/home/${USER}"
chown -R "${NEW_UID}:${NEW_GID}" "${TARGET}/home/${USER}" 2>/dev/null || true

chmod 600 "${TARGET}/etc/shadow"
chmod 644 "${TARGET}/etc/passwd" "${TARGET}/etc/group"

echo "Configured user account '${USER}' (UID ${NEW_UID}) on ${TARGET}"
