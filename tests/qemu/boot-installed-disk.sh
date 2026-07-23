#!/usr/bin/env bash
# tests/qemu/boot-installed-disk.sh — QEMU boot test for installed disk
#
# Boots a raw disk image and checks for the init marker.
#
# Usage:
#   bash tests/qemu/boot-installed-disk.sh <disk-image>
#   bash tests/qemu/boot-installed-disk.sh --image <path> [--timeout 60]
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$PROJECT_ROOT/build.conf"
source "$PROJECT_ROOT/scripts/common.sh"

if [ $# -lt 1 ]; then
  lumen_die "Usage: boot-installed-disk.sh <disk-image>"
fi

DISK_IMAGE="$1"
shift

QEMU_BIN="${QEMU_BIN:-qemu-system-x86_64}"
MARKER_STRING="${MARKER_STRING:-ShreeOS init: reached PID 1}"
TIMEOUT="${TIMEOUT:-120}"
MEMORY="${MEMORY:-256M}"

lumen_step "Booting installed disk: ${DISK_IMAGE}"

if [ ! -f "$DISK_IMAGE" ]; then
  lumen_die "Disk image not found: ${DISK_IMAGE}"
fi

LOG_FILE=$(mktemp /tmp/shreeos-qemu-disk.XXXXXX)

"$QEMU_BIN" \
  -drive file="$DISK_IMAGE",format=raw \
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
  lumen_ok "Disk boot test PASSED — init marker found (${WAITED}s)"
  rm -f "$LOG_FILE"
  exit 0
else
  lumen_warn "Disk boot test FAILED — marker not found within ${TIMEOUT}s"
  echo "  Log: ${LOG_FILE}"
  exit 1
fi
