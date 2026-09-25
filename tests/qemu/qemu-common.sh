#!/usr/bin/env bash
# tests/qemu/qemu-common.sh — Shared helpers for QEMU boot tests.
set -Eeuo pipefail

QEMU_BIN="${QEMU_BIN:-qemu-system-x86_64}"
MARKER_STRING="${MARKER_STRING:-ShreeOS init: critical services ready}"
MEMORY="${MEMORY:-256M}"
qemu_find() {
  if ! command -v "$QEMU_BIN" >/dev/null 2>&1; then
    lumen_die "QEMU not found: ${QEMU_BIN}. Install: sudo apt install qemu-system-x86"
  fi
  lumen_ok "QEMU: $("$QEMU_BIN" --version | head -n 1)"
}

qemu_start() {
  local log_file="$1"
  shift

  "$QEMU_BIN" -m "$MEMORY" -nographic -no-reboot -nic none "$@" >"$log_file" 2>&1 &
  QEMU_PID=$!
}

qemu_run() {
  local log_file="$1"
  shift

  qemu_start "$log_file" "$@"
  printf '%s\n' "$QEMU_PID"
}

qemu_process_running() {
  local pid="$1"
  local state

  if ! kill -0 "$pid" 2>/dev/null; then
    return 1
  fi

  if command -v ps >/dev/null 2>&1; then
    if state="$(ps -o stat= -p "$pid" 2>/dev/null)"; then
      state="${state//[[:space:]]/}"
      case "$state" in
        ""|Z*|X*) return 1 ;;
      esac
    fi
  fi

  return 0
}

qemu_stop() {
  local pid="${1:-}"

  [ -n "$pid" ] || return 0
  if qemu_process_running "$pid"; then
    kill "$pid" 2>/dev/null || true
  fi
  wait "$pid" 2>/dev/null || true
}

qemu_failure_reason() {
  local log_file="$1"
  local pattern
  local match
  local patterns=(
    "Kernel panic"
    "panic - not syncing"
    "VFS: Unable to mount root fs"
    "Out of memory"
    "oom-killer"
    "oom_kill"
    "invoked oom-killer"
    "Memory cgroup out of memory"
    "Killed process"
    "Cannot allocate memory"
    "No memory left"
    "No working init found"
    "No init found"
    "Attempted to kill init"
    "requested /init"
    "Failed to execute /init"
    "could not execute /init"
    "/init: not found"
    "initramfs: unpacking failed"
    "initramfs: error"
  )

  for pattern in "${patterns[@]}"; do
    match="$(grep -Fai -m 1 "$pattern" "$log_file" 2>/dev/null || true)"
    if [ -n "$match" ]; then
      printf '%s\n' "$match"
      return 0
    fi
  done

  return 1
}

qemu_log_tail() {
  local log_file="$1"
  local line_count="${2:-60}"

  printf '\n--- QEMU Serial Output (last %s lines) ---\n' "$line_count"
  if [ -s "$log_file" ]; then
    tail -n "$line_count" "$log_file" || true
  else
    printf '%s\n' "(no serial output captured)"
  fi
  printf '%s\n' "--- End of output ---"
}

qemu_wait_for_marker() {
  local log_file="$1"
  local qemu_pid="$2"
  local timeout="${3:-60}"
  local label="${4:-Boot test}"
  local waited=0
  local found=false
  local terminated=false
  local reason=""
  local final_reason=""

  if ! [[ "$timeout" =~ ^[0-9]+$ ]]; then
    reason="invalid timeout: ${timeout}"
  else
    while [ "$waited" -le "$timeout" ]; do
      if [ ! -f "$log_file" ]; then
        reason="QEMU log disappeared: ${log_file}"
        break
      fi

      if grep -Fq "$MARKER_STRING" "$log_file" 2>/dev/null; then
        found=true
        break
      fi

      if reason="$(qemu_failure_reason "$log_file")"; then
        break
      fi

      if ! qemu_process_running "$qemu_pid"; then
        terminated=true
        reason="QEMU terminated before the boot marker"
        break
      fi

      if [ "$waited" -eq "$timeout" ]; then
        reason="boot marker not found within ${timeout}s"
        break
      fi

      sleep 1
      waited=$((waited + 1))
    done
  fi

  qemu_stop "$qemu_pid"
  if grep -Fq "$MARKER_STRING" "$log_file" 2>/dev/null; then
    found=true
    reason=""
  elif [ "$terminated" = true ] && final_reason="$(qemu_failure_reason "$log_file")"; then
    reason="$final_reason"
  fi
  qemu_log_tail "$log_file" 60
  if [ "$found" = true ]; then
    lumen_ok "${label} PASSED — marker found after ${waited}s"
    return 0
  fi

  lumen_warn "${label} FAILED — ${reason}"
  echo "  Expected: ${MARKER_STRING}"
  echo "  Log:      ${log_file}"
  return 1
}
