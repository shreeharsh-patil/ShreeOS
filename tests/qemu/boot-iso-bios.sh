#!/usr/bin/env bash
# QEMU BIOS boot validation for a ShreeOS ISO.
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$PROJECT_ROOT/build.conf"
source "$PROJECT_ROOT/scripts/common.sh"

QEMU_BIN="${QEMU_BIN:-qemu-system-x86_64}"
ISO="${ISO:-${PROJECT_ROOT}/out/${DISTRO_ID}-${DISTRO_VERSION}.iso}"
MARKER_STRING="${MARKER_STRING:-ShreeOS init: critical services ready}"
TIMEOUT="${TIMEOUT:-60}"
MEMORY="${MEMORY:-256M}"
REQUIRE_ARTIFACTS="${REQUIRE_ARTIFACTS:-0}"
NO_CLEANUP=false

while [ $# -gt 0 ]; do
  case "$1" in
    --iso=*) ISO="${1#*=}"; shift ;;
    --iso) [ $# -ge 2 ] || shreeos_die "--iso requires a path"; ISO="$2"; shift 2 ;;
    --no-cleanup) NO_CLEANUP=true; shift ;;
    --help|-h) echo "Usage: boot-iso-bios.sh [--iso=<path>|--iso <path>] [--no-cleanup]"; exit 0 ;;
    *) shreeos_die "Unknown option: $1" ;;
  esac
done

shreeos_step "QEMU BIOS ISO boot test"

if ! command -v "$QEMU_BIN" >/dev/null 2>&1; then
  if [ "$REQUIRE_ARTIFACTS" = "1" ]; then shreeos_die "QEMU not found: $QEMU_BIN"; fi
  shreeos_warn "QEMU not found: $QEMU_BIN"
  exit 77
fi
if [ ! -s "$ISO" ]; then
  if [ "$REQUIRE_ARTIFACTS" = "1" ]; then shreeos_die "ISO not found or empty: $ISO"; fi
  shreeos_warn "ISO not found or empty: $ISO"
  exit 77
fi

shreeos_ok "ISO: $ISO"
LOG_FILE="$(mktemp /tmp/shreeos-qemu-bios.XXXXXX)"
QEMU_PID=""

cleanup_qemu() {
  if [ -n "$QEMU_PID" ] && kill -0 "$QEMU_PID" 2>/dev/null; then
    kill "$QEMU_PID" 2>/dev/null || true
    wait "$QEMU_PID" 2>/dev/null || true
  fi
}
trap cleanup_qemu EXIT INT TERM

"$QEMU_BIN"   -cdrom "$ISO"   -boot d   -m "$MEMORY"   -nographic   -no-reboot   > "$LOG_FILE" 2>&1 &
QEMU_PID=$!

WAITED=0
FOUND=false
while [ "$WAITED" -lt "$TIMEOUT" ]; do
  sleep 1
  WAITED=$((WAITED + 1))
  if grep -Fq "$MARKER_STRING" "$LOG_FILE" 2>/dev/null; then
    FOUND=true
    break
  fi
  kill -0 "$QEMU_PID" 2>/dev/null || break
done

cleanup_qemu
QEMU_PID=""

echo
echo "--- QEMU Serial Output (last 30 lines) ---"
tail -30 "$LOG_FILE" || true
echo "--- End of output ---"

if [ "$FOUND" = true ]; then
  shreeos_ok "BIOS ISO boot test PASSED — marker found after ${WAITED}s"
  if [ "$NO_CLEANUP" = false ]; then rm -f "$LOG_FILE"; else echo "  Log: $LOG_FILE"; fi
  exit 0
fi

shreeos_warn "BIOS ISO boot test FAILED — marker not found within ${TIMEOUT}s"
echo "  Expected: $MARKER_STRING"
echo "  Log:      $LOG_FILE"
exit 1
