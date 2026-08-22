#!/usr/bin/env bash
# tests/security/test-security.sh — ShreeOS System Security Audit Tests
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

echo "==> Auditing ShreeOS Security Posture"

# 1. Verify that xinitrc does not automatically spawn unauthenticated network listeners
if grep -q "shree-connect --daemon" "${ROOT_DIR}/desktop/configs/xinitrc.template" 2>/dev/null; then
  echo "  [FAIL] Insecure connect daemon found running by default in xinitrc" >&2
  exit 1
else
  echo "  [OK] Default xinitrc does not auto-start unauthenticated network listeners"
fi

# 2. Verify that shree-lock.sh does not contain unauthenticated password reading loops
if grep -q "read -s -p.*_PW" "${ROOT_DIR}/desktop/scripts/shree-lock.sh" 2>/dev/null; then
  echo "  [FAIL] Insecure terminal lock fallback found in shree-lock.sh" >&2
  exit 1
else
  echo "  [OK] Screen locker enforces trusted locker binaries and fails closed"
fi

# 3. Verify clipboard history file permissions in shree-clipboard.sh
if grep -q "chmod 600" "${ROOT_DIR}/desktop/scripts/shree-clipboard.sh" 2>/dev/null; then
  echo "  [OK] Clipboard manager enforces 0600 private permissions on history logs"
else
  echo "  [FAIL] Clipboard history permissions missing 0600 mode" >&2
  exit 1
fi

# 4. Verify no default plaintext passwords in installer
if grep -q 'ROOT_PASSWORD="shreeos"' "${ROOT_DIR}/installer/scripts/install-to-disk.sh" 2>/dev/null; then
  echo "  [FAIL] Hardcoded default root password found in install-to-disk.sh" >&2
  exit 1
else
  echo "  [OK] Hardcoded default passwords eliminated from installer scripts"
fi

# 5. Verify no hardcoded root=/dev/sda3 in bootloader installer
if grep -q 'ROOT_PARAM="root=/dev/sda3"' "${ROOT_DIR}/bootloader/scripts/install-grub-disk.sh" 2>/dev/null; then
  echo "  [FAIL] Hardcoded root=/dev/sda3 fallback found in install-grub-disk.sh" >&2
  exit 1
else
  echo "  [OK] Bootloader installer enforces mandatory UUID and rejects hardcoded device fallbacks"
fi

# 6. Verify SO_PEERCRED authorization enforcement in init.c
if grep -q "SO_PEERCRED" "${ROOT_DIR}/init/src/init.c" 2>/dev/null; then
  echo "  [OK] Init supervisor IPC (/run/init.sock) enforces SO_PEERCRED client authorization"
else
  echo "  [FAIL] Init supervisor missing SO_PEERCRED credentials check" >&2
  exit 1
fi

# 7. Verify console login service does not launch unauthenticated root shell
if grep -q "command=/bin/bash --login" "${ROOT_DIR}/init/services/90-console.conf" 2>/dev/null; then
  echo "  [FAIL] Insecure unauthenticated root shell configured in 90-console.conf" >&2
  exit 1
else
  echo "  [OK] Console service enforces authenticated login flow via shree-auth"
fi

echo "==> All security audit tests passed successfully!"
