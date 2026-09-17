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

if [ -x "${LUMEN_STAGE_ROOT}/bin/sh" ]; then
  lumen_ok "Found: /bin/sh compatibility shell"
  PASSED=$((PASSED + 1))
else
  lumen_warn "Missing: /bin/sh compatibility shell"
  FAILED=$((FAILED + 1))
fi

echo ""
echo "  --- Checking libraries ---"
for library in libncursesw.so libncurses.so libpanel.so libmenu.so libform.so; do
  if [ -e "${LUMEN_STAGE_ROOT}/usr/lib/${library}" ]; then
    lumen_ok "Found: ${library}"
    PASSED=$((PASSED + 1))
  else
    lumen_warn "Missing: ${library}"
    FAILED=$((FAILED + 1))
  fi
done

echo ""
echo "============================================"
echo "  Results: ${PASSED} passed, ${FAILED} failed"
echo "============================================"

if [ $FAILED -gt 0 ]; then
  exit 1
fi

# Do not execute a target binary against the host runtime. Verify that
# the staged shell is the expected target ELF; runtime execution is covered
# later by the rootfs/QEMU tests with the target loader and libraries present.
echo ""
lumen_step "Validating target bash binary"
BASH="${LUMEN_STAGE_ROOT}/usr/bin/bash"
if command -v file >/dev/null 2>&1 && file "$BASH" | grep -q 'ELF 64-bit.*x86-64'; then
  lumen_ok "Target bash ELF validation passed"
  lumen_ok "=== BASE SYSTEM SMOKE TEST PASSED ==="
  exit 0
fi

lumen_warn "Target bash is not a valid x86-64 ELF binary"
exit 1
