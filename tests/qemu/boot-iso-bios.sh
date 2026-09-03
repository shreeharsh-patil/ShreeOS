#!/usr/bin/env bash
# tests/qemu/boot-iso-bios.sh — QEMU BIOS boot test for ShreeOS ISO
#
# Prerequisites:
#   - Built ISO: out/shreeos-<version>.iso (from iso-builder/scripts/build-iso.sh)
#   - qemu-system-x86_64 installed
#
# Usage:
#   bash tests/qemu/boot-iso-bios.sh                   # run test
#   bash tests/qemu/boot-iso-bios.sh --iso <path>      # custom ISO path
#   bash tests/qemu/boot-iso-bios.sh --no-cleanup      # keep QEMU logs
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$PROJECT_ROOT/build.conf"
source "$PROJECT_ROOT/scripts/common.sh"

QEMU_BIN="${QEMU_BIN:-qemu-system-x86_64}"
ISO="${ISO:-${PROJECT_ROOT}/out/${DISTRO_ID}-${DISTRO_VERSION}.iso}"
MARKER_STRING="${MARKER_STRING:-ShreeOS init: reached PID 1}"
TIMEOUT="${TIMEOUT:-60}"
MEMORY="${MEMORY:-256M}"
NO_CLEANUP=false

for arg in "$@"; do
  case "$arg" in
    --iso=*)        ISO="${arg#*=}" ;;
    --no-cleanup)   NO_CLEANUP=true ;;
    --help|-h) echo "Usage: boot-iso-bios.sh [--iso=<path>] [--no-cleanup]"; exit 0 ;;
  esac
done

lumen_step "QEMU BIOS ISO boot test"

if ! command -v "$QEMU_BIN" &>/dev/null; then
  lumen_die "QEMU not found: ${QEMU_BIN}"
fi
lumen_ok "QEMU found: $($QEMU_BIN --version | head -1)"

if [ ! -f "$ISO" ]; then
  lumen_warn "ISO not found: ${ISO} — skipping until ISO is built."
  exit 0
fi
lumen_ok "ISO: ${ISO} ($(stat -c%s "$ISO" 2>/dev/null || stat -f%z "$ISO" 2>/dev/null || echo '?') bytes)"

LOG_FILE=$(mktemp /tmp/shreeos-qemu-bios.XXXXXX)
echo "  Log: ${LOG_FILE}"
echo "  Timeout: ${TIMEOUT}s"

"$QEMU_BIN" \
  -cdrom "$ISO" \
  -boot d \
  -m "$MEMORY" \
  -nographic \
  -no-reboot \
  2>&1 | head -c 131072 > "$LOG_FILE" &
QEMU_PID=$!

WAITED=0
FOUND=false
while [ $WAITED -lt "$TIMEOUT" ]; do
  sleep 1
  WAITED=$((WAITED + 1))
  if grep -q "$MARKER_STRING" "$LOG_FILE" 2>/dev/null; then
    FOUND=true
    break
  fi
  if ! kill -0 "$QEMU_PID" 2>/dev/null; then
    break
  fi
done

kill "$QEMU_PID" 2>/dev/null || true
wait "$QEMU_PID" 2>/dev/null || true

echo ""
echo "--- QEMU Serial Output (last 30 lines) ---"
tail -30 "$LOG_FILE"
echo "--- End of output ---"

if [ "$FOUND" = true ]; then
  lumen_ok "BIOS ISO boot test PASSED — marker found"
  echo "  Marker: '${MARKER_STRING}'"
  echo "  Time:   ${WAITED}s"
  if [ "$NO_CLEANUP" = false ]; then
    rm -f "$LOG_FILE"
  fi
  exit 0
else
  lumen_warn "BIOS ISO boot test FAILED — marker not found within ${TIMEOUT}s"
  echo "  Log: ${LOG_FILE}"
  exit 1
fi
