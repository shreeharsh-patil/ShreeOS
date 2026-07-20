#!/usr/bin/env bash
# tests/qemu/qemu-common.sh — Shared helpers for QEMU boot tests
#
# Source this from QEMU test scripts:
#   source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/qemu-common.sh"
#
set -euo pipefail

QEMU_BIN="${QEMU_BIN:-qemu-system-x86_64}"
MARKER_STRING="${MARKER_STRING:-ShreeOS init: reached PID 1}"
MEMORY="${MEMORY:-256M}"

qemu_find() {
  if ! command -v "$QEMU_BIN" &>/dev/null; then
    lumen_die "QEMU not found: ${QEMU_BIN}. Install: sudo apt install qemu-system-x86"
  fi
  lumen_ok "QEMU: $($QEMU_BIN --version | head -1)"
}

qemu_run() {
  local log_file="$1"
  shift
  "$QEMU_BIN" \
    -m "$MEMORY" \
    -nographic \
    -no-reboot \
    "$@" \
    2>&1 | head -c 131072 > "$log_file" &
  echo "$!"
}

qemu_wait_for_marker() {
  local log_file="$1" qemu_pid="$2" timeout="${3:-60}"
  local waited=0 found=false
  while [ $waited -lt $timeout ]; do
    sleep 1
    waited=$((waited + 1))
    if grep -q "$MARKER_STRING" "$log_file" 2>/dev/null; then
      found=true
      break
    fi
    if ! kill -0 "$qemu_pid" 2>/dev/null; then
      break
    fi
  done
  kill "$qemu_pid" 2>/dev/null || true
  wait "$qemu_pid" 2>/dev/null || true
  echo ""
  echo "--- QEMU Serial Output (last 30 lines) ---"
  tail -30 "$log_file"
  echo "--- End of output ---"
  if [ "$found" = true ]; then
    lumen_ok "Boot test PASSED (${waited}s)"
    return 0
  else
    lumen_warn "Boot test FAILED — marker not found within ${timeout}s"
    echo "  Log: ${log_file}"
    return 1
  fi
}
