#!/usr/bin/env bash
# Run the ShreeOS QEMU boot suite.
# Default mode permits unavailable build artifacts to be skipped for local development.
# --strict is used by make test-qemu/CI and requires QEMU plus every prerequisite.
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$ROOT_DIR/build.conf"
source "$ROOT_DIR/scripts/common.sh"

TIMEOUT="${TIMEOUT:-}"
MEMORY="${MEMORY:-}"
STRICT=false
while [ $# -gt 0 ]; do
  case "$1" in
    --timeout=*) TIMEOUT="${1#*=}"; shift ;;
    --timeout) [ $# -ge 2 ] || shreeos_die "--timeout requires a value"; TIMEOUT="$2"; shift 2 ;;
    --memory=*) MEMORY="${1#*=}"; shift ;;
    --memory) [ $# -ge 2 ] || shreeos_die "--memory requires a value"; MEMORY="$2"; shift 2 ;;
    --strict) STRICT=true; shift ;;
    --help|-h)
      echo "Usage: run-all-qemu-tests.sh [--timeout=N] [--memory=SIZE] [--strict]"
      exit 0
      ;;
    *) shreeos_die "Unknown option: $1" ;;
  esac
done

QEMU_BIN="${QEMU_BIN:-qemu-system-x86_64}"
if ! command -v "$QEMU_BIN" >/dev/null 2>&1; then
  if [ "$STRICT" = true ]; then
    shreeos_die "QEMU ($QEMU_BIN) is required for strict boot validation"
  fi
  shreeos_warn "QEMU ($QEMU_BIN) is not installed; skipping QEMU suite"
  exit 0
fi

shreeos_step "Running QEMU Boot Test Suite (timeout: ${TIMEOUT:-per-test default}, strict: ${STRICT})"

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
declare -A SEEN_TESTS=()

for t in "${TESTS[@]}"; do
  if [ -n "${SEEN_TESTS[$t]+present}" ]; then
    shreeos_warn "Skipping duplicate QEMU test: $t"
    continue
  fi
  SEEN_TESTS["$t"]=1

  test_path="$SCRIPT_DIR/$t"
  if [ ! -f "$test_path" ]; then
    if [ "$STRICT" = true ]; then
      shreeos_warn "Missing required QEMU test: $t"
      FAILED=$((FAILED + 1))
    else
      SKIPPED=$((SKIPPED + 1))
    fi
    continue
  fi

  shreeos_step "Executing QEMU test: $t"
  REQUIRE_ARTIFACTS=0
  if [ "$STRICT" = true ]; then
    REQUIRE_ARTIFACTS=1
  fi
  TEST_ENV=(REQUIRE_ARTIFACTS="$REQUIRE_ARTIFACTS")
  if [ -n "$TIMEOUT" ]; then
    TEST_ENV+=(TIMEOUT="$TIMEOUT")
  fi
  if [ -n "$MEMORY" ]; then
    TEST_ENV+=(MEMORY="$MEMORY")
  else
    case "$t" in
      boot-kernel-only.sh) TEST_ENV+=(MEMORY=256M) ;;
      boot-full-rootfs.sh|boot-iso-bios.sh|boot-iso-uefi.sh) TEST_ENV+=(MEMORY=1024M) ;;
    esac
  fi

  set +e
  env "${TEST_ENV[@]}" bash "$test_path"
  rc=$?
  set -e

  case "$rc" in
    0) PASSED=$((PASSED + 1)) ;;
    77)
      if [ "$STRICT" = true ]; then
        FAILED=$((FAILED + 1))
      else
        SKIPPED=$((SKIPPED + 1))
      fi
      ;;
    *) FAILED=$((FAILED + 1)) ;;
  esac
done

echo
echo "=== QEMU Boot Test Summary ==="
echo "  Passed:  $PASSED"
echo "  Failed:  $FAILED"
echo "  Skipped: $SKIPPED"

if [ "$FAILED" -gt 0 ]; then
  exit 1
fi
if [ "$STRICT" = true ] && [ "$SKIPPED" -gt 0 ]; then
  shreeos_die "Strict QEMU validation cannot contain skipped tests"
fi
shreeos_ok "QEMU boot suite completed successfully"
