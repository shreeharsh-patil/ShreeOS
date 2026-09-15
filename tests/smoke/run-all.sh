#!/usr/bin/env bash
# run-all.sh — Run all smoke and integration test suites for ShreeOS
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

VERBOSE=false
LIST_ONLY=false
EXIT_CODE=0
PASSED=0
FAILED=0

for arg in "$@"; do
  case "$arg" in
    --verbose|-v) VERBOSE=true ;;
    --list|-l)    LIST_ONLY=true ;;
    --help|-h)
      echo "Usage: run-all.sh [--verbose] [--list]"
      exit 0
      ;;
  esac
done

source "${PROJECT_ROOT}/scripts/common.sh" 2>/dev/null || true

echo "============================================"
if command -v shreeos_step >/dev/null 2>&1; then
  shreeos_step "ShreeOS Comprehensive Test Suite"
else
  echo "==> ShreeOS Comprehensive Test Suite"
fi
echo "  Date:    $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
echo "  Root:    ${PROJECT_ROOT}"
echo "============================================"

# Collect all test scripts across suites
TEST_FILES=(
  "${PROJECT_ROOT}/hardware/tests/run-tests.sh"
  "${PROJECT_ROOT}/init/tests/test-init-v2.sh"
  "${PROJECT_ROOT}/tests/smoke/test-desktop-suite.sh"
  "${PROJECT_ROOT}/tests/security/test-security.sh"
  "${PROJECT_ROOT}/tests/auth/test-auth.sh"
  "${PROJECT_ROOT}/tests/installer/test-installer-validation.sh"
  "${PROJECT_ROOT}/tests/pkgmanager/test-lpm-transactions.sh"
)

for test in "${TEST_FILES[@]}"; do
  [ ! -f "$test" ] && continue
  TEST_NAME="$(basename "$test")"

  if [ "$LIST_ONLY" = true ]; then
    printf "  %-35s %s\n" "$TEST_NAME" "$test"
    continue
  fi

  printf "  [ RUN      ] %s\n" "$TEST_NAME"
  START=$(date +%s)

  if [ "$VERBOSE" = true ]; then
    if bash "$test"; then
      DURATION=$(( $(date +%s) - START ))
      printf "  [       OK ] %s (%ds)\n" "$TEST_NAME" "$DURATION"
      PASSED=$((PASSED + 1))
    else
      DURATION=$(( $(date +%s) - START ))
      printf "  [  FAILED  ] %s (%ds)\n" "$TEST_NAME" "$DURATION"
      FAILED=$((FAILED + 1))
      EXIT_CODE=1
    fi
  else
    if OUTPUT=$(bash "$test" 2>&1); then
      DURATION=$(( $(date +%s) - START ))
      printf "  [       OK ] %s (%ds)\n" "$TEST_NAME" "$DURATION"
      PASSED=$((PASSED + 1))
    else
      DURATION=$(( $(date +%s) - START ))
      printf "  [  FAILED  ] %s (%ds)\n--- output ---\n%s\n---\n" "$TEST_NAME" "$DURATION" "$OUTPUT"
      FAILED=$((FAILED + 1))
      EXIT_CODE=1
    fi
  fi
done

echo ""
echo "============================================"
echo "  Results: ${PASSED} passed, ${FAILED} failed"
echo "============================================"
exit "$EXIT_CODE"
