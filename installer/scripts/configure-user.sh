#!/usr/bin/env bash
# installer/scripts/configure-user.sh — Create user account on target rootfs
#
# Security & Integrity Requirements:
#   - Strict username validation: ^[a-z_][a-z0-9_-]{0,31}$
#   - Passwords read from 0600 file or stdin, never exposed on argv
#   - Passwords hashed using stdin-based hashing (openssl -stdin, python3 sys.stdin)
#   - Password variables wiped immediately from memory
#   - Discovers next available UID and GID independently (>= 1000)
#   - Sets /home/<user> ownership to <uid>:<gid> and mode 0700 (fails closed on error)
#   - Adds user to wheel and shree-hardware groups securely

set -euo pipefail

if [ $# -lt 2 ]; then
  echo "Usage: configure-user.sh <target-rootfs> <username> [credential-file]" >&2
  exit 1
fi

TARGET="$1"
USER="$2"
CRED_FILE="${3:-}"

if [ ! -d "$TARGET" ]; then
  echo "Error: Target rootfs does not exist or is not a directory: $TARGET" >&2
  exit 1
fi

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
if [ -n "$CRED_FILE" ]; then
  if [ ! -f "$CRED_FILE" ] || [ -L "$CRED_FILE" ]; then
    echo "Error: Credential file must be a regular, non-symlink file." >&2
    exit 1
  fi
  CRED_MODE=$(stat -c '%a' "$CRED_FILE" 2>/dev/null || echo "")
  if [ "$CRED_MODE" != "600" ] && [ "$CRED_MODE" != "400" ]; then
    echo "Error: Credential file must have mode 0600 or 0400." >&2
    exit 1
  fi
  PASSWORD=$(sed -n '1p' "$CRED_FILE")
elif [ ! -t 0 ]; then
  IFS= read -r PASSWORD || true
fi

if [ -z "$PASSWORD" ]; then
  echo "Error: Empty password provided for user '${USER}'. Aborting." >&2
  exit 1
fi

# 3. Secure SHA-512 password hashing without exposing password in process argv
SALT="$(od -An -N8 -tx1 /dev/urandom 2>/dev/null | tr -d ' \n')"
if ! [[ "$SALT" =~ ^[0-9a-fA-F]{16}$ ]]; then
  echo "CRITICAL SECURITY ERROR: Failed to generate password salt." >&2
  exit 1
fi
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
# Establish safe modes before any later operation can fail.  In particular,
# a restricted user namespace may reject the home-directory chown; the
# partially configured target must never be left with a world-readable shadow
# database in that case.
chmod 644 "${TARGET}/etc/passwd" "${TARGET}/etc/group"
chmod 600 "${TARGET}/etc/shadow"

# 5. Allocate the first available UID & GID independently (1000-64999).
# Reusing holes scales better on long-lived installations than max+1 allocation.
next_free_id() {
  local file="$1" start="$2" end="$3"
  awk -F: -v start="$start" -v end="$end" '
    $3 ~ /^[0-9]+$/ && $3 >= start && $3 <= end { used[$3] = 1 }
    END {
      for (id = start; id <= end; id++) {
        if (!used[id]) { print id; exit }
      }
    }
  ' "$file"
}

NEW_UID=$(next_free_id "${TARGET}/etc/passwd" 1000 64999)
NEW_GID=$(next_free_id "${TARGET}/etc/group" 1000 64999)
if ! [[ "$NEW_UID" =~ ^[0-9]+$ ]] || ! [[ "$NEW_GID" =~ ^[0-9]+$ ]]; then
  echo "Error: No free UID/GID remains in the supported 1000-64999 range." >&2
  exit 1
fi

# 6. Add user and group entries if not present
if ! grep -q "^${USER}:" "${TARGET}/etc/passwd" 2>/dev/null; then
  echo "${USER}:x:${NEW_UID}:${NEW_GID}:${USER}:/home/${USER}:/bin/bash" >> "${TARGET}/etc/passwd"
else
  # Retrieve existing UID/GID for directory chown
  NEW_UID=$(awk -F':' -v u="$USER" '$1==u {print $3; exit}' "${TARGET}/etc/passwd")
  NEW_GID=$(awk -F':' -v u="$USER" '$1==u {print $4; exit}' "${TARGET}/etc/passwd")
  if ! [[ "$NEW_UID" =~ ^[0-9]+$ ]] || ! [[ "$NEW_GID" =~ ^[0-9]+$ ]]; then
    echo "Error: Existing account '$USER' has invalid UID/GID metadata." >&2
    exit 1
  fi
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

# shreed exposes the hardware socket to this dedicated group.  Allocate an
# unused group ID when creating a rootfs that does not already contain it.
if ! grep -q "^shree-hardware:" "${TARGET}/etc/group" 2>/dev/null; then
  HARDWARE_GID=$(next_free_id "${TARGET}/etc/group" 986 999)
  if [ -z "$HARDWARE_GID" ]; then
    HARDWARE_GID=$(next_free_id "${TARGET}/etc/group" 1000 64999)
  fi
  if ! [[ "$HARDWARE_GID" =~ ^[0-9]+$ ]]; then
    echo "Error: No free GID is available for shree-hardware." >&2
    exit 1
  fi
  echo "shree-hardware:x:${HARDWARE_GID}:${USER}" >> "${TARGET}/etc/group"
elif ! awk -F: -v user="$USER" '$1 == "shree-hardware" { n=split($4, members, ","); for (i=1; i<=n; i++) if (members[i] == user) exit 0; exit 1 }' "${TARGET}/etc/group"; then
  sed -i "/^shree-hardware:/ s/$/,${USER}/" "${TARGET}/etc/group"
fi

# 7. Write password hash to /etc/shadow using today's epoch-day value.
SHADOW_DAY=$(( $(date +%s) / 86400 ))
if grep -q "^${USER}:" "${TARGET}/etc/shadow" 2>/dev/null; then
  awk -F: -v OFS=: -v user="$USER" -v hash="$ENCRYPTED_PASS" -v day="$SHADOW_DAY" '
    $1 == user { $2 = hash; $3 = day }
    { print }
  ' "${TARGET}/etc/shadow" > "${TARGET}/etc/shadow.tmp"
  chmod 600 "${TARGET}/etc/shadow.tmp"
  mv -f "${TARGET}/etc/shadow.tmp" "${TARGET}/etc/shadow"
else
  echo "${USER}:${ENCRYPTED_PASS}:${SHADOW_DAY}:0:99999:7:::" >> "${TARGET}/etc/shadow"
fi

# 8. Create /home/<user> with correct owner & 0700 permissions
mkdir -p "${TARGET}/home/${USER}"
chmod 700 "${TARGET}/home/${USER}"
chown -R "${NEW_UID}:${NEW_GID}" "${TARGET}/home/${USER}"

chmod 600 "${TARGET}/etc/shadow"
chmod 644 "${TARGET}/etc/passwd" "${TARGET}/etc/group"

echo "Configured user account '${USER}' (UID ${NEW_UID}, GID ${NEW_GID}) on ${TARGET}"
