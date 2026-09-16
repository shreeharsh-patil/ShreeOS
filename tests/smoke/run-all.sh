#!/usr/bin/env bash
# run-all.sh — Run all smoke tests for ShreeOS
#
# Discovers and executes every *.sh file in this directory (except itself)
# in sequence. Each test must exit 0 on success and non-zero on failure.
#
# Usage:
#   bash tests/smoke/run-all.sh              # run all tests
#   bash tests/smoke/run-all.sh --verbose    # run with extra output
#   bash tests/smoke/run-all.sh --list       # list tests without running
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
      echo "Runs all smoke test scripts in tests/smoke/"
      exit 0
      ;;
  esac
done

source "${PROJECT_ROOT}/scripts/common.sh" 2>/dev/null || true

echo "============================================"
lumen_step "ShreeOS Smoke Test Suite"
echo "  Date:    $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
echo "  Root:    ${PROJECT_ROOT}"
echo "  Tests:   ${SCRIPT_DIR}"
echo "============================================"

for test in "${SCRIPT_DIR}"/*.sh; do
  TEST_NAME="$(basename "$test")"
  [ "$TEST_NAME" = "$(basename "${BASH_SOURCE[0]}")" ] && continue

  if [ "$LIST_ONLY" = true ]; then
    TEST_DESC=$(head -3 "$test" | grep -E '^#' | head -1 | sed 's/^# //' || echo "")
    printf "  %-30s %s\n" "$TEST_NAME" "$TEST_DESC"
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
    OUTPUT=$(bash "$test" 2>&1) && {
      DURATION=$(( $(date +%s) - START ))
      printf "  [       OK ] %s (%ds)\n" "$TEST_NAME" "$DURATION"
      PASSED=$((PASSED + 1))
    } || {
      DURATION=$(( $(date +%s) - START ))
      printf "  [  FAILED  ] %s (%ds)\n--- output ---\n%s\n---\n" "$TEST_NAME" "$DURATION" "$OUTPUT"
      FAILED=$((FAILED + 1))
      EXIT_CODE=1
    }
  fi
done

echo ""
echo "============================================"
echo "  Results: ${PASSED} passed, ${FAILED} failed"
echo "============================================"
exit "$EXIT_CODE"
