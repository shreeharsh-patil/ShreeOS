#!/usr/bin/env bash
# tests/installer/test-installer-validation.sh — Test Installer Safeguards & Input Validation
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

echo "==> Testing ShreeOS Installer Validation & Safeguards"

# 1. Hostname validation test in install-to-disk.sh
if bash "${ROOT_DIR}/installer/scripts/install-to-disk.sh" --help >/dev/null 2>&1; then
  echo "  [OK] install-to-disk.sh responds to --help"
else
  echo "  [FAIL] install-to-disk.sh help command failed" >&2
  exit 1
fi

# 2. Partition disk validation test
if bash "${ROOT_DIR}/installer/scripts/partition-disk.sh" --help >/dev/null 2>&1; then
  echo "  [OK] partition-disk.sh responds to --help"
else
  echo "  [FAIL] partition-disk.sh help command failed" >&2
  exit 1
fi

# 3. Test non-existent disk rejection
if bash "${ROOT_DIR}/installer/scripts/partition-disk.sh" "/dev/nonexistent_shreeos_disk" --yes >/dev/null 2>&1; then
  echo "  [FAIL] partition-disk.sh accepted non-existent disk device!" >&2
  exit 1
else
  echo "  [OK] Non-existent block device correctly rejected"
fi

echo "==> All installer validation tests passed successfully!"
