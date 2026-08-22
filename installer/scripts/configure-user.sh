#!/usr/bin/env bash
# installer/scripts/configure-user.sh — Create default user account on installed target rootfs
#
# Usage:
#   bash configure-user.sh <target-rootfs> <username> <credential-file-or-stdin>
#
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
  echo "Error: Invalid username '${USER}'. Must match ^[a-z_][a-z0-9_-]{0,31}$ (no colons, slashes, or whitespace)." >&2
  exit 1
fi

# 2. Read password securely (from credential file mode 0600 or stdin)
PASSWORD=""
if [ -n "$CRED_FILE" ] && [ -f "$CRED_FILE" ]; then
  PASSWORD=$(cat "$CRED_FILE")
elif [ ! -t 0 ]; then
  PASSWORD=$(cat)
fi

if [ -z "$PASSWORD" ]; then
  echo "Error: Empty password provided for user '${USER}'. Aborting installation." >&2
  exit 1
fi

# 3. Secure password hashing with multiple robust backends
SALT="$(head -c 16 /dev/urandom | base64 | tr -dc 'a-zA-Z0-9' | head -c 16)"
ENCRYPTED_PASS=""

if command -v openssl >/dev/null 2>&1; then
  ENCRYPTED_PASS=$(openssl passwd -6 -salt "$SALT" "$PASSWORD" 2>/dev/null || echo "")
fi

if [ -z "$ENCRYPTED_PASS" ] && command -v mkpasswd >/dev/null 2>&1; then
  ENCRYPTED_PASS=$(echo "$PASSWORD" | mkpasswd -m sha-512 -S "$SALT" 2>/dev/null || echo "")
fi

if [ -z "$ENCRYPTED_PASS" ] && command -v python3 >/dev/null 2>&1; then
  ENCRYPTED_PASS=$(python3 -c "import crypt; print(crypt.crypt('''$PASSWORD''', '\$6\$$SALT\$'))" 2>/dev/null || echo "")
fi

# FAIL CLOSED: Never write plaintext password to /etc/shadow
if [ -z "$ENCRYPTED_PASS" ] || [[ "$ENCRYPTED_PASS" == "$PASSWORD" ]]; then
  echo "CRITICAL SECURITY ERROR: Failed to securely hash password using SHA-512 (openssl, mkpasswd, or python3 crypt required)." >&2
  echo "Failing closed: installation aborted to prevent insecure credentials." >&2
  exit 1
fi

# 4. Ensure /home directory exists with proper permissions
mkdir -p "${TARGET}/home/${USER}"
chmod 700 "${TARGET}/home/${USER}"

# 5. Add user and group entries if not present
mkdir -p "${TARGET}/etc"
touch "${TARGET}/etc/passwd" "${TARGET}/etc/group" "${TARGET}/etc/shadow"

if ! grep -q "^${USER}:" "${TARGET}/etc/passwd" 2>/dev/null; then
  echo "${USER}:x:1000:1000:${USER}:/home/${USER}:/bin/bash" >> "${TARGET}/etc/passwd"
fi

if ! grep -q "^${USER}:" "${TARGET}/etc/group" 2>/dev/null; then
  echo "${USER}:x:1000:" >> "${TARGET}/etc/group"
fi

# Add user to wheel group if wheel exists
if grep -q "^wheel:" "${TARGET}/etc/group" 2>/dev/null; then
  sed -i "s|^wheel:.*|&,${USER}|; s|:,,|:,|" "${TARGET}/etc/group"
fi

# 6. Set user password securely in shadow
if grep -q "^${USER}:" "${TARGET}/etc/shadow" 2>/dev/null; then
  sed -i "s|^${USER}:[^:]*:|${USER}:${ENCRYPTED_PASS}:|" "${TARGET}/etc/shadow"
else
  echo "${USER}:${ENCRYPTED_PASS}:19000:0:99999:7:::" >> "${TARGET}/etc/shadow"
fi

chmod 600 "${TARGET}/etc/shadow"
chmod 644 "${TARGET}/etc/passwd" "${TARGET}/etc/group"

echo "Configured user account '${USER}' on ${TARGET}"
