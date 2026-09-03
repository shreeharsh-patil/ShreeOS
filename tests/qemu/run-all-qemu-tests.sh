#!/usr/bin/env bash
# tests/qemu/run-all-qemu-tests.sh — Run all automated QEMU boot tests
#
# Executes kernel, rootfs, ISO (BIOS & UEFI), and disk boot tests sequentially.
#
# Usage:
#   bash tests/qemu/run-all-qemu-tests.sh [--timeout=60]
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LUMEN_ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$LUMEN_ROOT_DIR/build.conf" 2>/dev/null || true
source "$LUMEN_ROOT_DIR/scripts/common.sh" 2>/dev/null || {
  lumen_step() { echo "==> $1"; }
  lumen_ok() { echo "  [OK] $1"; }
  lumen_warn() { echo "  [WARN] $1"; }
}

TIMEOUT=60
for arg in "$@"; do
  case "$arg" in
    --timeout=*) TIMEOUT="${arg#*=}" ;;
    --help|-h) echo "Usage: run-all-qemu-tests.sh [--timeout=N]"; exit 0 ;;
  esac
done

QEMU_BIN="${QEMU_BIN:-qemu-system-x86_64}"
if ! command -v "$QEMU_BIN" &>/dev/null; then
  lumen_warn "QEMU (${QEMU_BIN}) not installed on host — skipping automated hardware boot runs"
  exit 0
fi

lumen_step "Running QEMU Boot Test Suite (Timeout: ${TIMEOUT}s)"

TESTS=(
  "boot-kernel-only.sh"
  "boot-full-rootfs.sh"
  "boot-iso-bios.sh"
  "boot-iso-uefi.sh"
  "boot-installed-disk.sh"
  "test-e2e-install-and-boot.sh"
)

PASSED=0
FAILED=0
SKIPPED=0

for t in "${TESTS[@]}"; do
  TEST_PATH="${SCRIPT_DIR}/${t}"
  if [ ! -f "$TEST_PATH" ]; then
    SKIPPED=$((SKIPPED + 1))
    continue
  fi

  lumen_step "Executing QEMU test: ${t}"
  if TIMEOUT="$TIMEOUT" bash "$TEST_PATH"; then
    PASSED=$((PASSED + 1))
  else
    FAILED=$((FAILED + 1))
  fi
done

echo ""
echo "=== QEMU Boot Test Summary ==="
echo "  Passed:  ${PASSED}"
echo "  Failed:  ${FAILED}"
echo "  Skipped: ${SKIPPED}"

if [ "$FAILED" -gt 0 ]; then
  exit 1
fi
