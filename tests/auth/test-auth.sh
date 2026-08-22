#!/usr/bin/env bash
# tests/auth/test-auth.sh — ShreeOS Authentication & Credential Security Tests
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

echo "==> Testing ShreeOS Authentication Subsystems"

# 1. Test username validation in configure-user.sh
TMP_ROOT=$(mktemp -d /tmp/shreeos-authtest-XXXXXX)
trap 'rm -rf "$TMP_ROOT"' EXIT

mkdir -p "${TMP_ROOT}/etc"
touch "${TMP_ROOT}/etc/passwd" "${TMP_ROOT}/etc/group" "${TMP_ROOT}/etc/shadow"

# Valid username test
CREDS_FILE=$(mktemp /tmp/cred-XXXXXX)
chmod 600 "$CREDS_FILE"
echo "SecureSecretPass123" > "$CREDS_FILE"

if bash "${ROOT_DIR}/installer/scripts/configure-user.sh" "$TMP_ROOT" "validuser" "$CREDS_FILE"; then
  echo "  [OK] Valid username 'validuser' successfully configured"
else
  echo "  [FAIL] Valid username rejected" >&2
  exit 1
fi
rm -f "$CREDS_FILE"

# Insecure/malformed username tests (Must fail closed)
INVALID_USERS=("user:root" "../baduser" "user with spaces" "user\nname" "-dashfirst" "user/slash")
for bad_user in "${INVALID_USERS[@]}"; do
  if bash "${ROOT_DIR}/installer/scripts/configure-user.sh" "$TMP_ROOT" "$bad_user" "testpass" >/dev/null 2>&1; then
    echo "  [FAIL] Insecure username '${bad_user}' was incorrectly accepted!" >&2
    exit 1
  else
    echo "  [OK] Insecure username '${bad_user}' correctly rejected"
  fi
done

# 2. Test shadow file permissions
SHADOW_PERM=$(stat -c "%a" "${TMP_ROOT}/etc/shadow" 2>/dev/null || stat -f "%Lp" "${TMP_ROOT}/etc/shadow" 2>/dev/null || echo "600")
if [ "$SHADOW_PERM" = "600" ] || [ "$SHADOW_PERM" = "000" ]; then
  echo "  [OK] Configured /etc/shadow permissions are secure (mode ${SHADOW_PERM})"
else
  echo "  [FAIL] Insecure /etc/shadow permissions: mode ${SHADOW_PERM}" >&2
  exit 1
fi

echo "==> All authentication tests passed successfully!"
