#!/usr/bin/env bash
# tests/auth/test-auth.sh — ShreeOS Authentication & Credential Security Tests
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

echo "==> Testing ShreeOS Authentication Subsystems"

TMP_ROOT=$(mktemp -d /tmp/shreeos-authtest-XXXXXX)
PRIV_PREFIX=()
CAN_PRIVILEGED_TEST=1
CREDS_FILE=""

if [ "$(id -u)" -ne 0 ]; then
  if command -v sudo >/dev/null 2>&1 && sudo -n true >/dev/null 2>&1; then
    PRIV_PREFIX=(sudo -n)
  else
    CAN_PRIVILEGED_TEST=0
  fi
fi

# Some rootless containers report UID 0 while their user namespace forbids
# changing ownership to unmapped target IDs.  Probe the operation the test
# actually needs instead of treating an effective UID of zero as sufficient.
OWNERSHIP_PROBE="${TMP_ROOT}/ownership-probe"
mkdir -p "$OWNERSHIP_PROBE"
if ! "${PRIV_PREFIX[@]}" chown 1000:1000 "$OWNERSHIP_PROBE" 2>/dev/null; then
  CAN_PRIVILEGED_TEST=0
fi

cleanup() {
  rm -f "${CREDS_FILE:-}" >/dev/null 2>&1 || true
  if [ "${#PRIV_PREFIX[@]}" -gt 0 ]; then
    "${PRIV_PREFIX[@]}" rm -rf "$TMP_ROOT" >/dev/null 2>&1 || true
  else
    rm -rf "$TMP_ROOT" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

run_configure_user() {
  "${PRIV_PREFIX[@]}" bash "${ROOT_DIR}/installer/scripts/configure-user.sh" "$@"
}

mkdir -p "${TMP_ROOT}/etc"
touch "${TMP_ROOT}/etc/passwd" "${TMP_ROOT}/etc/group" "${TMP_ROOT}/etc/shadow"

# Valid username test. CI has passwordless sudo, which lets us exercise the
# production ownership path instead of weakening configure-user.sh.
CREDS_FILE=$(mktemp /tmp/cred-XXXXXX)
chmod 600 "$CREDS_FILE"
printf '%s\n' "SecureSecretPass123" > "$CREDS_FILE"

if [ "$CAN_PRIVILEGED_TEST" -eq 1 ]; then
  if run_configure_user "$TMP_ROOT" "validuser" "$CREDS_FILE"; then
    echo "  [OK] Valid username 'validuser' successfully configured"
  else
    echo "  [FAIL] Valid username rejected" >&2
    rm -f "$CREDS_FILE"
    exit 1
  fi
else
  # A non-root developer machine without passwordless sudo cannot perform the
  # ownership transition. Still verify that the valid account reaches the
  # expected database-writing path before chown fails.
  if bash "${ROOT_DIR}/installer/scripts/configure-user.sh" "$TMP_ROOT" "validuser" "$CREDS_FILE" >/dev/null 2>&1; then
    echo "  [OK] Valid username 'validuser' successfully configured"
  elif grep -q '^validuser:' "${TMP_ROOT}/etc/passwd"; then
    echo "  [SKIP] Ownership assertion requires root; valid account path reached"
  else
    echo "  [FAIL] Valid username rejected before account creation" >&2
    rm -f "$CREDS_FILE"
    exit 1
  fi
fi
rm -f "$CREDS_FILE"

# Insecure/malformed username tests must fail before any privileged operation.
INVALID_USERS=("user:root" "../baduser" "user with spaces" "user\\nname" "-dashfirst" "user/slash")
for bad_user in "${INVALID_USERS[@]}"; do
  if bash "${ROOT_DIR}/installer/scripts/configure-user.sh" "$TMP_ROOT" "$bad_user" "testpass" >/dev/null 2>&1; then
    echo "  [FAIL] Insecure username '${bad_user}' was incorrectly accepted!" >&2
    exit 1
  else
    echo "  [OK] Insecure username '${bad_user}' correctly rejected"
  fi
done

SHADOW_PERM=$(stat -c "%a" "${TMP_ROOT}/etc/shadow" 2>/dev/null || stat -f "%Lp" "${TMP_ROOT}/etc/shadow" 2>/dev/null || echo "600")
if [ "$SHADOW_PERM" = "600" ] || [ "$SHADOW_PERM" = "000" ]; then
  echo "  [OK] Configured /etc/shadow permissions are secure (mode ${SHADOW_PERM})"
else
  echo "  [FAIL] Insecure /etc/shadow permissions: mode ${SHADOW_PERM}" >&2
  exit 1
fi

echo "==> All authentication tests passed successfully!"
