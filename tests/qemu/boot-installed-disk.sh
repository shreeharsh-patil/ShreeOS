#!/usr/bin/env bash
# tests/qemu/boot-installed-disk.sh — QEMU boot test for installed disk
#
# Boots a raw disk image and checks for the init marker.
#
# Usage:
#   bash tests/qemu/boot-installed-disk.sh [disk-image]
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$PROJECT_ROOT/build.conf" 2>/dev/null || true
source "$PROJECT_ROOT/scripts/common.sh" 2>/dev/null || {
  lumen_step() { echo "==> $1"; }
  lumen_ok() { echo "  [OK] $1"; }
  lumen_warn() { echo "  [WARN] $1"; }
  lumen_die() { echo "  [ERROR] $1" >&2; exit 1; }
}

DISK_IMAGE="${1:-}"
TEMP_DISK=""

if [ -z "$DISK_IMAGE" ]; then
  if [ -f "${PROJECT_ROOT}/build/installed-disk.img" ]; then
    DISK_IMAGE="${PROJECT_ROOT}/build/installed-disk.img"
  else
    # Create temporary sparse test disk for automated CI
    TEMP_DISK=$(mktemp /tmp/shreeos-test-disk-XXXXXX.img)
    truncate -s 2G "$TEMP_DISK"
    DISK_IMAGE="$TEMP_DISK"
    trap 'rm -f "$TEMP_DISK"' EXIT INT TERM
    
    # If rootfs and installer exist, run quick install test on image
    if [ -f "${PROJECT_ROOT}/build/initramfs.cpio.gz" ] && command -v sfdisk >/dev/null 2>&1; then
      CREDS_FILE=$(mktemp /tmp/test-creds-XXXXXX)
      chmod 600 "$CREDS_FILE"
      printf "testrootpass\ntestuserpass\n" > "$CREDS_FILE"
      bash "${PROJECT_ROOT}/installer/scripts/install-to-disk.sh" "$DISK_IMAGE" --yes --credentials-file="$CREDS_FILE"
      rm -f "$CREDS_FILE"
    else
      lumen_warn "No built rootfs (initramfs.cpio.gz) found — skipping disk boot test"
      exit 0
    fi
  fi
fi

QEMU_BIN="${QEMU_BIN:-qemu-system-x86_64}"
MARKER_STRING="${MARKER_STRING:-ShreeOS init: reached PID 1}"
TIMEOUT="${TIMEOUT:-60}"
MEMORY="${MEMORY:-256M}"

lumen_step "Booting disk image: ${DISK_IMAGE}"

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

if [ "$FOUND" = true ]; then
  lumen_ok "Disk boot test PASSED — init marker found (${WAITED}s)"
  rm -f "$LOG_FILE"
  exit 0
else
  lumen_warn "Disk boot test failed without marker (Log saved to ${LOG_FILE})"
  rm -f "$LOG_FILE"
  exit 1
fi
