#!/usr/bin/env bash
# Run the ShreeOS QEMU boot suite.
# Default mode permits unavailable build artifacts to be skipped for local development.
# --strict is used by make test-qemu/CI and requires QEMU plus every prerequisite.
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$ROOT_DIR/build.conf"
source "$ROOT_DIR/scripts/common.sh"

# Leave TIMEOUT empty by default so every boot test applies its own budget. The
# live ISO path boots a rootfs-sized initramfs and needs a much larger window
# than the kernel-only or installed-disk tests, so a single global default here
# would either waste minutes or fail the slow paths.
TIMEOUT=""
STRICT=false
for arg in "$@"; do
  case "$arg" in
    --timeout=*) TIMEOUT="${arg#*=}" ;;
    --strict) STRICT=true ;;
    --help|-h)
      echo "Usage: run-all-qemu-tests.sh [--timeout=N] [--strict]"
      exit 0
      ;;
    *) shreeos_die "Unknown option: $arg" ;;
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

for t in "${TESTS[@]}"; do
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
  set +e
  if [ -n "$TIMEOUT" ]; then
    REQUIRE_ARTIFACTS="$([ "$STRICT" = true ] && echo 1 || echo 0)" TIMEOUT="$TIMEOUT" bash "$test_path"
  else
    REQUIRE_ARTIFACTS="$([ "$STRICT" = true ] && echo 1 || echo 0)" bash "$test_path"
  fi
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
