#!/usr/bin/env bash
# Stage E: measure the unified ShreeOS image in a controlled virtual machine and
# compare it against the release targets and, once one exists, a recorded
# baseline.
#
# Controlled conditions, identical for baseline and candidate:
#   2 vCPU, 4096 MiB RAM, virtio graphics, 1280x800, fixed window, no network.
#
# The image writes SHREEOS_PERF lines to its console from
# /usr/local/sbin/shreeos-perf-probe, which runs once on live media only. This
# script reads those lines from the serial log, which is why no guest agent is
# needed.
#
# Usage: tests/prototype/test-performance-report.sh PATH_TO_ISO
#
# Environment:
#   QEMU_LOG_DIR  directory to copy the report, serial log and screenshots into
#   RESUME        "1" to compare against tests/prototype/performance-baseline.tsv
set -Eeuo pipefail

if [ "$#" -ne 1 ] || [ ! -s "$1" ]; then
  echo "Usage: $0 PATH_TO_SHREEOS_ISO" >&2
  exit 2
fi

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
ISO="$(realpath "$1")"
TARGETS="$REPO_ROOT/prototype/debian-live/performance-targets.tsv"
BASELINE="$REPO_ROOT/tests/prototype/performance-baseline.tsv"
REGRESSION_TOLERANCE_PCT="${REGRESSION_TOLERANCE_PCT:-20}"

for tool in xorriso qemu-system-x86_64 qemu-img timeout python3; do
  command -v "$tool" >/dev/null 2>&1 || {
    echo "Missing performance test dependency: $tool" >&2
    exit 2
  }
done

TEST_DIR="$(mktemp -d)"
trap 'rm -rf -- "$TEST_DIR"' EXIT
QEMU_LOG_DIR="${QEMU_LOG_DIR:-}"
[ -z "$QEMU_LOG_DIR" ] || mkdir -p "$QEMU_LOG_DIR"

SERIAL="$TEST_DIR/serial.log"
MONITOR="$TEST_DIR/monitor.sock"
SQUASHFS="$TEST_DIR/filesystem.squashfs"
TARGET_DISK="$TEST_DIR/target.raw"

# Extract the probe so the contract between image and report can be checked
# statically as well as observed at runtime.
xorriso -osirrox on -indev "$ISO" -extract /live/filesystem.squashfs "$SQUASHFS" >/dev/null
unsquashfs -q -cat "$SQUASHFS" usr/local/sbin/shreeos-perf-probe >"$TEST_DIR/probe" 2>/dev/null || true
if [ ! -s "$TEST_DIR/probe" ]; then
  echo 'The image does not ship usr/local/sbin/shreeos-perf-probe; cannot measure it.' >&2
  exit 1
fi

qemu-img create -q -f raw "$TARGET_DISK" 2G

# The window is 30 s of measurement plus boot; 15 minutes is a generous ceiling.
deadline=$((SECONDS + 900))
xvfb-run -a -s "-screen 0 1280x800x24" timeout --signal=TERM 900s qemu-system-x86_64 \
  -machine q35 -m 4096 -smp 2 -vga virtio -nic none \
  -drive "file=$TARGET_DISK,format=raw,if=virtio" \
  -cdrom "$ISO" -boot order=d \
  -display gtk -monitor "unix:$MONITOR,server,nowait" \
  -serial "file:$SERIAL" -no-reboot >"$TEST_DIR/qemu.log" 2>&1 &
emulator_pid=$!

while ! grep -Fq 'SHREEOS_PERF_END' "$SERIAL" 2>/dev/null; do
  if ! kill -0 "$emulator_pid" 2>/dev/null || (( SECONDS >= deadline )); then
    break
  fi
  sleep 2
done

if grep -Fq 'SHREEOS_PERF_END' "$SERIAL" 2>/dev/null; then
  # Give the guest a clean shutdown signal through the monitor.
  python3 - "$MONITOR" <<'PY' || true
import socket
import sys
import time

client = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
client.settimeout(3)
for _ in range(5):
    try:
        client.connect(sys.argv[1])
        break
    except OSError:
        time.sleep(1)
else:
    raise SystemExit(0)
client.recv(4096)
client.sendall(b"quit\n")
client.close()
PY
fi
wait "$emulator_pid" || true

if ! grep -Fq 'SHREEOS_PERF_END' "$SERIAL" 2>/dev/null; then
  echo 'The image never completed its performance probe.' >&2
  tail -n 60 "$SERIAL" >&2 || true
  [ -z "$QEMU_LOG_DIR" ] || cp -f "$SERIAL" "$QEMU_LOG_DIR/serial.log"
  exit 1
fi

# Metrics are stored as key<TAB>value. Several values (top RSS, top CPU, the
# systemd blame list) legitimately contain spaces, so a space-delimited parse
# would truncate them and silently weaken the report.
grep 'SHREEOS_PERF ' "$SERIAL" | sed 's/^.*SHREEOS_PERF //' |
  awk 'index($0, "=") { key = substr($0, 1, index($0, "=") - 1);
                        value = substr($0, index($0, "=") + 1);
                        print key "\t" value }' |
  sort -u >"$TEST_DIR/metrics.tsv"
[ -s "$TEST_DIR/metrics.tsv" ] || { echo 'No SHREEOS_PERF metrics were captured.' >&2; exit 1; }

# Persist the raw evidence before interpreting it.
[ -z "$QEMU_LOG_DIR" ] || cp -f "$SERIAL" "$QEMU_LOG_DIR/serial.log"

metric() {
  awk -F'\t' -v key="$1" '$1 == key { print $2; exit }' "$TEST_DIR/metrics.tsv"
}

REPORT="$TEST_DIR/performance-report.md"
{
  printf '# ShreeOS performance report\n\n'
  # Backticks are Markdown code spans in the generated report, not command
  # substitution, so the literal-quote warning does not apply.
  # shellcheck disable=SC2016
  printf 'Image: `%s`\n' "$(basename -- "$ISO")"
  printf 'Measured: %s (UTC)\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  printf 'Conditions: 2 vCPU, 4096 MiB RAM, virtio graphics, 1280x800, no network\n\n'
  printf '| Metric | Measured |\n| --- | --- |\n'
  while IFS=$'\t' read -r key value; do
    [ -n "$key" ] || continue
    printf '| %s | %s |\n' "$key" "${value:-}"
  done <"$TEST_DIR/metrics.tsv"
  printf '\n'
} >"$REPORT"

# --- Enforce the release targets --------------------------------------------
failures=0
while IFS=$'\t' read -r key limit comparison provenance; do
  case "$key" in '' | '#'*) continue ;; esac
  measured="$(metric "$key")"
  [ -n "$measured" ] || { printf 'missing metric: %s\n' "$key" >&2; failures=$((failures + 1)); continue; }
  if ! awk -v m="$measured" -v l="$limit" -v c="$comparison" \
    'BEGIN { exit (c == "max" ? (m > l) : (m < l)) ? 0 : 1 }'; then
    printf 'TARGET MISSED: %s = %s (limit %s, %s) - %s\n' \
      "$key" "$measured" "$limit" "$comparison" "$provenance" >&2
    failures=$((failures + 1))
  else
    printf 'target met: %s = %s (%s %s)\n' "$key" "$measured" "$comparison" "$limit"
  fi
done <"$TARGETS"

# --- Regression against a recorded baseline, when one exists -----------------
{
  printf '\n## Target evaluation\n\n'
  if [ "$failures" -eq 0 ]; then
    printf 'All release targets were met.\n'
  else
    printf '%s release target(s) were missed. See the step log.\n' "$failures"
  fi
} >>"$REPORT"

if [ "${RESUME:-0}" = 1 ] && [ -s "$BASELINE" ]; then
  printf '\n## Regression against the recorded baseline (>%s%%)\n\n' "$REGRESSION_TOLERANCE_PCT" >>"$REPORT"
  printf '| Metric | Baseline | Measured | Delta |\n| --- | --- | --- | --- |\n' >>"$REPORT"
  while IFS=$'\t' read -r key baseline_value; do
    case "$key" in '' | '#'*) continue ;; esac
    measured="$(metric "$key")"
    [ -n "$measured" ] || continue
    verdict="$(awk -v b="$baseline_value" -v m="$measured" -v t="$REGRESSION_TOLERANCE_PCT" \
      'BEGIN {
        if (b <= 0) { print "no-baseline"; exit }
        delta = ((m - b) / b) * 100
        printf "%.1f%% %s", delta, (delta > t ? "REGRESSION" : "ok")
      }')"
    printf '| %s | %s | %s | %s |\n' "$key" "$baseline_value" "$measured" "$verdict" >>"$REPORT"
    case "$verdict" in
      *REGRESSION*)
        printf 'REGRESSION: %s went from %s to %s (>%s%%)\n' \
          "$key" "$baseline_value" "$measured" "$REGRESSION_TOLERANCE_PCT" >&2
        failures=$((failures + 1))
        ;;
    esac
  done <"$BASELINE"
else
  {
    printf '\n## Regression baseline\n\n'
    printf 'No measured baseline is recorded in the repository yet, so this run\n'
    printf 'establishes one. The metrics above are published with this run as\n'
    # Backticks are Markdown code spans here, not command substitution.
    # shellcheck disable=SC2016
    printf '`performance-baseline.tsv`; commit them and set `RESUME=1` to start\n'
    printf 'failing future runs on a genuine regression.\n'
  } >>"$REPORT"
  awk -F'\t' '$1 ~ /^(mem_used_mib|cpu_busy_pct|boot_total_ms|graphical_reached_ms)$/ {
    print $1 "\t" $2
  }' "$TEST_DIR/metrics.tsv" >"$TEST_DIR/performance-baseline.tsv"
fi

if [ -n "$QEMU_LOG_DIR" ]; then
  # The report and the raw metrics are the evidence the gate is based on, so a
  # failure to archive them fails the run instead of being swallowed.
  cp -f "$REPORT" "$QEMU_LOG_DIR/performance-report.md"
  cp -f "$TEST_DIR/metrics.tsv" "$QEMU_LOG_DIR/metrics.tsv"
  if [ -s "$TEST_DIR/performance-baseline.tsv" ]; then
    cp -f "$TEST_DIR/performance-baseline.tsv" "$QEMU_LOG_DIR/performance-baseline.tsv"
  fi
  # The emulator's own log is diagnostic only: a missing one must not hide the
  # performance result, but a present one is always archived.
  if [ -s "$TEST_DIR/qemu.log" ]; then
    cp -f "$TEST_DIR/qemu.log" "$QEMU_LOG_DIR/qemu.log"
  fi
fi

cat "$REPORT"
[ "$failures" -eq 0 ] || {
  printf 'Performance gate failed with %s problem(s).\n' "$failures" >&2
  exit 1
}
printf 'Performance gate passed.\n'
