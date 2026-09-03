#!/usr/bin/env bash
# tests/smoke/test-base-system.sh — Smoke test for the base system
#
# Verifies that the base system is installed to $LUMEN_STAGE_ROOT
# and that key utilities are present.
#
# Usage:
#   bash tests/smoke/test-base-system.sh
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$PROJECT_ROOT/build.conf"
source "$PROJECT_ROOT/scripts/common.sh"

PASSED=0
FAILED=0

check_bin() {
  local bin="$1"
  local path="${LUMEN_STAGE_ROOT}/usr/bin/${bin}"
  if [ -x "$path" ]; then
    lumen_ok "Found: ${bin}"
    PASSED=$((PASSED + 1))
  else
    lumen_warn "Missing: ${bin} (expected at ${path})"
    FAILED=$((FAILED + 1))
  fi
}

lumen_step "Smoke testing base system at ${LUMEN_STAGE_ROOT}"

if [ ! -d "$LUMEN_STAGE_ROOT" ]; then
  lumen_die "Stage root not found: ${LUMEN_STAGE_ROOT}. Build base system first."
fi

echo ""
echo "  --- Checking essential binaries ---"
check_bin bash
check_bin sh
check_bin ls
check_bin cat
check_bin cp
check_bin mv
check_bin rm
check_bin mkdir
check_bin grep
check_bin sed
check_bin gawk
check_bin tar
check_bin gzip
check_bin make
check_bin patch
check_bin m4
check_bin bison
check_bin diff

echo ""
echo "  --- Checking libraries ---"
if [ -f "${LUMEN_STAGE_ROOT}/usr/lib/libncursesw.so" ]; then
  lumen_ok "Found: libncursesw.so"
  PASSED=$((PASSED + 1))
else
  lumen_warn "Missing: libncursesw.so"
  FAILED=$((FAILED + 1))
fi

echo ""
echo "============================================"
echo "  Results: ${PASSED} passed, ${FAILED} failed"
echo "============================================"

if [ $FAILED -gt 0 ]; then
  exit 1
fi

# Verify bash can execute code
echo ""
lumen_step "Testing bash execution"
BASH="${LUMEN_STAGE_ROOT}/usr/bin/bash"
if [ -x "$BASH" ]; then
  OUTPUT=$("$BASH" -c 'echo "ShreeOS base system OK"')
  if [ "$OUTPUT" = "ShreeOS base system OK" ]; then
    lumen_ok "Bash execution test passed"
    lumen_ok "=== BASE SYSTEM SMOKE TEST PASSED ==="
    exit 0
  fi
fi

exit 1
