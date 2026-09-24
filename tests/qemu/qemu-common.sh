#!/usr/bin/env bash
# tests/qemu/qemu-common.sh — Shared helpers for QEMU boot tests.
set -Eeuo pipefail

QEMU_BIN="${QEMU_BIN:-qemu-system-x86_64}"
MARKER_STRING="${MARKER_STRING:-ShreeOS init: critical services ready}"
# Live ShreeOS boot paths carry the assembled rootfs as the initramfs, which
# needs roughly 1 GB of guest RAM once unpacked.
MEMORY="${MEMORY:-2048M}"

qemu_find() {
  if ! command -v "$QEMU_BIN" >/dev/null 2>&1; then
    lumen_die "QEMU not found: ${QEMU_BIN}. Install: sudo apt install qemu-system-x86"
  fi
  lumen_ok "QEMU: $("$QEMU_BIN" --version | head -n 1)"
}

qemu_run() {
  local log_file="$1"
  shift

  # Redirect QEMU directly rather than putting it in a pipeline. This makes $!
  # the actual emulator PID, so timeout/cleanup logic cannot leave QEMU behind.
  "$QEMU_BIN"     -m "$MEMORY"     -nographic     -no-reboot     "$@"     >"$log_file" 2>&1 &
  printf '%s\n' "$!"
}

qemu_wait_for_marker() {
  local log_file="$1"
  local qemu_pid="$2"
  local timeout="${3:-60}"
  local waited=0
  local found=false

  while [ "$waited" -lt "$timeout" ]; do
    sleep 1
    waited=$((waited + 1))

    if grep -Fq "$MARKER_STRING" "$log_file" 2>/dev/null; then
      found=true
      break
    fi

    if ! kill -0 "$qemu_pid" 2>/dev/null; then
      break
    fi
  done

  if kill -0 "$qemu_pid" 2>/dev/null; then
    kill "$qemu_pid" 2>/dev/null || true
  fi
  wait "$qemu_pid" 2>/dev/null || true

  echo
  echo "--- QEMU Serial Output (last 30 lines) ---"
  tail -30 "$log_file" || true
  echo "--- End of output ---"

  if [ "$found" = true ]; then
    lumen_ok "Boot test PASSED (${waited}s)"
    return 0
  fi

  lumen_warn "Boot test FAILED — marker not found within ${timeout}s"
  echo "  Log: ${log_file}"
  return 1
}
