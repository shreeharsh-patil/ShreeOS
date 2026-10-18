#!/usr/bin/env bash
# Stage E: measure the unified ShreeOS image in a controlled virtual machine and
# compare it against the release targets and, once one is recorded, a measured
# baseline.
#
# Controlled conditions, identical for baseline and candidate:
#   2 vCPU, 4096 MiB RAM, virtio graphics, 1280x800. A restricted user-mode
#   network supplies DHCP to the live boot check but blocks host/outside access.
#
# The image writes SHREEOS_PERF lines to its console from
# /usr/local/sbin/shreeos-perf-probe, which runs once on live media only. This
# script reads those lines from the serial log, which is why no guest agent is
# needed.
#
# Usage: tests/prototype/test-performance-report.sh PATH_TO_ISO
#
# Environment:
#   QEMU_LOG_DIR  directory to copy the report, metrics, serial log and QEMU log into
#   RESUME        "1" to compare against tests/prototype/performance-baseline.tsv
#   REQUIRE_BASELINE "1" to fail if no untouched-build baseline is recorded
#   MEASURED_SOURCE_COMMIT  source commit used to build the measured ISO
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
UNTOUCHED_BASELINE_COMMIT='9313ebb042cf71bb148441037940b130d49920d1'
MEASURED_SOURCE_COMMIT="${MEASURED_SOURCE_COMMIT:-${GITHUB_SHA:-}}"
# shellcheck source=scripts/performance-targets.sh
source "$REPO_ROOT/scripts/performance-targets.sh"

for tool in realpath xorriso unsquashfs qemu-system-x86_64 qemu-img xvfb-run timeout sha256sum python3; do
  command -v "$tool" >/dev/null 2>&1 || {
    echo "Missing performance test dependency: $tool" >&2
    exit 2
  }
done

manifest="${ISO%.iso}-manifest.json"
[ -s "$manifest" ] || {
  printf 'Missing image provenance manifest: %s\n' "$manifest" >&2
  exit 2
}
candidate_iso_sha256="$(sha256sum "$ISO" | awk '{print $1}')"
provenance_args=()
if [ "${ALLOW_PERFORMANCE_INSTRUMENTATION_OVERLAY:-0}" = 1 ]; then
  [ "${MEASURED_SOURCE_COMMIT:-}" = "$UNTOUCHED_BASELINE_COMMIT" ] || {
    echo 'The instrumentation overlay is allowed only for the pinned untouched baseline.' >&2
    exit 2
  }
  provenance_args+=(--allow-instrumentation-overlay)
fi
manifest_source_commit="$(python3 "$REPO_ROOT/scripts/verify-performance-manifest.py" \
  "$manifest" "$ISO" "${provenance_args[@]}")"
MEASURED_SOURCE_COMMIT="${MEASURED_SOURCE_COMMIT:-$manifest_source_commit}"
[[ "$MEASURED_SOURCE_COMMIT" =~ ^[0-9a-f]{40}$ ]] || {
  echo 'MEASURED_SOURCE_COMMIT must be a full 40-character Git commit.' >&2
  exit 2
}
[[ "$MEASURED_SOURCE_COMMIT" == "$manifest_source_commit" ]] || {
  printf 'Measured source %s does not match ISO manifest source %s.\n' \
    "$MEASURED_SOURCE_COMMIT" "$manifest_source_commit" >&2
  exit 2
}

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
PROBE_SOURCE="$REPO_ROOT/prototype/debian-live/config/includes.chroot/usr/local/sbin/shreeos-perf-probe"
cmp -s "$PROBE_SOURCE" "$TEST_DIR/probe" || {
  echo 'Image uses a different performance probe than the measurement harness; baseline and candidate would not be comparable.' >&2
  exit 1
}
SERVICE_SOURCE="$REPO_ROOT/prototype/debian-live/config/includes.chroot/etc/systemd/system/shreeos-perf-probe.service"
unsquashfs -q -cat "$SQUASHFS" etc/systemd/system/shreeos-perf-probe.service >"$TEST_DIR/probe.service" 2>/dev/null || true
cmp -s "$SERVICE_SOURCE" "$TEST_DIR/probe.service" || {
  echo 'Image uses a different performance probe unit than the measurement harness; baseline and candidate would not be comparable.' >&2
  exit 1
}
probe_sha256="$(sha256sum "$PROBE_SOURCE" | awk '{print $1}')"
probe_service_sha256="$(sha256sum "$SERVICE_SOURCE" | awk '{print $1}')"

qemu-img create -q -f raw "$TARGET_DISK" 2G

# The window is 30 s of measurement plus boot; 15 minutes is a generous ceiling.
# Keep QEMU alive briefly past the probe deadline so the monitor can capture the
# last screen and state before the guest is stopped for diagnostics.
deadline=$((SECONDS + 900))
qemu_timeout=1020
xvfb-run -a -s "-screen 0 1280x800x24" timeout --signal=TERM "${qemu_timeout}s" qemu-system-x86_64 \
  -machine q35 -m 4096 -smp 2 -vga virtio \
  -drive "file=$TARGET_DISK,format=raw,if=virtio" \
  -nic user,model=virtio-net-pci,restrict=on \
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
else
  # A blank serial log cannot distinguish a guest boot hang from a console
  # routing problem. Preserve the visible screen and QEMU monitor state before
  # stopping the emulator, so a timeout has actionable evidence.
  python3 - "$MONITOR" "$TEST_DIR/screen.ppm" "$TEST_DIR/monitor.log" <<'PY' || true
import socket
import sys
import time

monitor, screenshot, output = sys.argv[1:]
client = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
client.settimeout(1)
for _ in range(5):
    try:
        client.connect(monitor)
        break
    except OSError:
        time.sleep(1)
else:
    raise SystemExit(0)

def receive():
    chunks = []
    while True:
        try:
            chunk = client.recv(4096)
        except TimeoutError:
            break
        if not chunk:
            break
        chunks.append(chunk)
    return b"".join(chunks).decode(errors="replace")

greeting = receive()
results = [greeting]
for command in ("info status", f"screendump {screenshot}"):
    client.sendall((command + "\n").encode())
    results.append(receive())
client.sendall(b"quit\n")
client.close()
with open(output, "w", encoding="utf-8") as stream:
    stream.write("\n".join(results))
PY
fi
wait "$emulator_pid" || true

if ! grep -Fq 'SHREEOS_PERF_END' "$SERIAL" 2>/dev/null; then
  echo 'The image never completed its performance probe.' >&2
  tail -n 60 "$SERIAL" >&2 || true
  if [ -n "$QEMU_LOG_DIR" ]; then
    cp -f "$SERIAL" "$QEMU_LOG_DIR/serial.log"
    [ ! -s "$TEST_DIR/qemu.log" ] || cp -f "$TEST_DIR/qemu.log" "$QEMU_LOG_DIR/qemu.log"
    [ ! -s "$TEST_DIR/monitor.log" ] || cp -f "$TEST_DIR/monitor.log" "$QEMU_LOG_DIR/monitor.log"
    [ ! -s "$TEST_DIR/screen.ppm" ] || cp -f "$TEST_DIR/screen.ppm" "$QEMU_LOG_DIR/screen.ppm"
  fi
  tail -n 60 "$TEST_DIR/qemu.log" >&2 || true
  tail -n 60 "$TEST_DIR/monitor.log" >&2 || true
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

{
  printf '# source_commit=%s\n' "$MEASURED_SOURCE_COMMIT"
  printf '# iso_sha256=%s\n' "$candidate_iso_sha256"
  printf '# conditions=2-vCPU,4096MiB,virtio,1280x800,restricted-user-network\n'
  printf '# probe_sha256=%s\n' "$probe_sha256"
  printf '# probe_service_sha256=%s\n' "$probe_service_sha256"
  awk -F'\t' '$1 ~ /^(mem_used_mib|cpu_busy_pct|boot_total_ms|graphical_reached_ms)$/ {
    print $1 "\t" $2
  }' "$TEST_DIR/metrics.tsv"
} >"$TEST_DIR/performance-candidate.tsv"

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
  printf 'Conditions: 2 vCPU, 4096 MiB RAM, virtio graphics, 1280x800, restricted user-mode network (DHCP only; no access to the host or outside network)\n\n'
  printf '| Metric | Measured |\n| --- | --- |\n'
  while IFS=$'\t' read -r key value; do
    [ -n "$key" ] || continue
    printf '| %s | %s |\n' "$key" "${value:-}"
  done <"$TEST_DIR/metrics.tsv"
  printf '\n'
} >"$REPORT"

# --- Enforce the release targets --------------------------------------------
failures=0
if [ "$MEASURED_SOURCE_COMMIT" = "$UNTOUCHED_BASELINE_COMMIT" ]; then
  for required_metric in mem_used_mib cpu_busy_pct boot_total_ms graphical_reached_ms; do
    measured="$(metric "$required_metric")"
    if ! [[ "$measured" =~ ^[0-9]+([.][0-9]+)?$ ]]; then
      printf 'Untouched baseline is missing a numeric %s measurement.\n' \
        "$required_metric" >&2
      failures=$((failures + 1))
    fi
  done
else
  while IFS=$'\t' read -r key limit comparison provenance; do
    case "$key" in '' | '#'*) continue ;; esac
    measured="$(metric "$key")"
    [ -n "$measured" ] || { printf 'missing metric: %s\n' "$key" >&2; failures=$((failures + 1)); continue; }
    if ! performance_target_met "$measured" "$comparison" "$limit"; then
      printf 'TARGET MISSED: %s = %s (limit %s, %s) - %s\n' \
        "$key" "$measured" "$limit" "$comparison" "$provenance" >&2
      failures=$((failures + 1))
    else
      printf 'target met: %s = %s (%s %s)\n' "$key" "$measured" "$comparison" "$limit"
    fi
  done <"$TARGETS"
fi

# --- Comparison against the untouched build ----------------------------------
if [ "$MEASURED_SOURCE_COMMIT" = "$UNTOUCHED_BASELINE_COMMIT" ]; then
  {
    printf '\n## Untouched-build baseline capture\n\n'
    printf 'This run measured the designated pre-optimization source. The candidate release targets are evaluated in the release build.\n'
  } >>"$REPORT"
elif [ "${RESUME:-0}" = 1 ] && [ -s "$BASELINE" ]; then
  printf '\n## Regression against the recorded baseline (>%s%%)\n\n' "$REGRESSION_TOLERANCE_PCT" >>"$REPORT"
  printf '| Metric | Baseline | Measured | Delta |\n| --- | --- | --- | --- |\n' >>"$REPORT"
  baseline_valid=1
  baseline_source_commit="$(awk -F= '$1 == "# source_commit" { print $2; exit }' "$BASELINE")"
  baseline_iso_sha256="$(awk -F= '$1 == "# iso_sha256" { print $2; exit }' "$BASELINE")"
  baseline_conditions="$(awk -F= '$1 == "# conditions" { print $2; exit }' "$BASELINE")"
  baseline_probe_sha256="$(awk -F= '$1 == "# probe_sha256" { print $2; exit }' "$BASELINE")"
  baseline_probe_service_sha256="$(awk -F= '$1 == "# probe_service_sha256" { print $2; exit }' "$BASELINE")"
  if [ "$baseline_source_commit" != "$UNTOUCHED_BASELINE_COMMIT" ]; then
    printf 'Baseline provenance must name untouched source %s.\n' \
      "$UNTOUCHED_BASELINE_COMMIT" >&2
    baseline_valid=0
    failures=$((failures + 1))
  fi
  if ! [[ "$baseline_iso_sha256" =~ ^[0-9a-f]{64}$ ]]; then
    printf 'Baseline provenance must include the tested ISO SHA256.\n' >&2
    baseline_valid=0
    failures=$((failures + 1))
  fi
  if [ "$baseline_conditions" != '2-vCPU,4096MiB,virtio,1280x800,restricted-user-network' ]; then
    printf 'Baseline was not measured under the controlled release conditions.\n' >&2
    baseline_valid=0
    failures=$((failures + 1))
  fi
  if ! [[ "$baseline_probe_sha256" =~ ^[0-9a-f]{64}$ ]] ||
    [ "$baseline_probe_sha256" != "$probe_sha256" ]; then
    printf 'Baseline performance probe hash does not match this candidate.\n' >&2
    baseline_valid=0
    failures=$((failures + 1))
  fi
  if ! [[ "$baseline_probe_service_sha256" =~ ^[0-9a-f]{64}$ ]] ||
    [ "$baseline_probe_service_sha256" != "$probe_service_sha256" ]; then
    printf 'Baseline performance probe service hash does not match this candidate.\n' >&2
    baseline_valid=0
    failures=$((failures + 1))
  fi
  for required_metric in mem_used_mib cpu_busy_pct boot_total_ms graphical_reached_ms; do
    baseline_value="$(awk -F'\t' -v key="$required_metric" \
      '$1 == key { print $2; exit }' "$BASELINE")"
    if ! [[ "$baseline_value" =~ ^[0-9]+([.][0-9]+)?$ ]]; then
      printf 'Baseline is missing a numeric %s measurement.\n' "$required_metric" >&2
      baseline_valid=0
      failures=$((failures + 1))
    fi
  done
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
  baseline_memory="$(awk -F'\t' '$1 == "mem_used_mib" { print $2; exit }' "$BASELINE")"
  baseline_cpu="$(awk -F'\t' '$1 == "cpu_busy_pct" { print $2; exit }' "$BASELINE")"
  measured_memory="$(metric mem_used_mib)"
  measured_cpu="$(metric cpu_busy_pct)"
  if [ "$baseline_valid" -ne 1 ]; then
    printf 'PERFORMANCE ACCEPTANCE FAILED: baseline provenance or required measurements are invalid.\n' >&2
    printf '\nImprovement requirement: FAILED (baseline provenance or metrics are invalid).\n' >>"$REPORT"
  elif ! performance_improvement_or_efficiency_met \
      "$baseline_memory" "$measured_memory" "$baseline_cpu" "$measured_cpu"; then
    printf 'PERFORMANCE ACCEPTANCE FAILED: need at least 20%% idle memory or CPU improvement, or an untouched baseline already within both limits (850 MiB, 2%%).\n' >&2
    printf '\nImprovement requirement: FAILED (baseline memory=%s MiB, measured=%s MiB; baseline CPU=%s%%, measured=%s%%).\n' \
      "$baseline_memory" "$measured_memory" "$baseline_cpu" "$measured_cpu" >>"$REPORT"
    failures=$((failures + 1))
  else
    printf 'Performance improvement or efficient baseline requirement passed.\n'
    printf '\nImprovement requirement: passed (baseline memory=%s MiB, measured=%s MiB; baseline CPU=%s%%, measured=%s%%).\n' \
      "$baseline_memory" "$measured_memory" "$baseline_cpu" "$measured_cpu" >>"$REPORT"
  fi
else
  {
    printf '\n## Regression baseline\n\n'
    printf 'No untouched-build baseline is recorded in the repository yet. This run\n'
    printf 'produces a candidate report, but cannot establish the requested relative\n'
    printf 'performance improvement. Review and commit an untouched-build baseline.\n'
    # Backticks are Markdown code spans here, not command substitution.
    # shellcheck disable=SC2016
    printf 'The candidate metrics are published as `performance-candidate.tsv`.\n'
  } >>"$REPORT"
  if [ "${REQUIRE_BASELINE:-0}" = 1 ]; then
    printf 'PERFORMANCE ACCEPTANCE FAILED: untouched-build baseline is missing.\n' >&2
    printf '\nImprovement requirement: FAILED (no untouched-build baseline is committed).\n' >>"$REPORT"
    failures=$((failures + 1))
  fi
fi

{
  printf '\n## Target evaluation\n\n'
  if [ "$MEASURED_SOURCE_COMMIT" = "$UNTOUCHED_BASELINE_COMMIT" ] && [ "$failures" -eq 0 ]; then
    printf 'Untouched-build baseline measurements are complete.\n'
  elif [ "$failures" -eq 0 ]; then
    printf 'All absolute and comparative performance release targets were met.\n'
  else
    printf '%s performance release target(s) were missed. See the step log.\n' "$failures"
  fi
} >>"$REPORT"

if [ -n "$QEMU_LOG_DIR" ]; then
  # The report and the raw metrics are the evidence the gate is based on, so a
  # failure to archive them fails the run instead of being swallowed.
  cp -f "$REPORT" "$QEMU_LOG_DIR/performance-report.md"
  cp -f "$TEST_DIR/metrics.tsv" "$QEMU_LOG_DIR/metrics.tsv"
  cp -f "$TEST_DIR/performance-candidate.tsv" "$QEMU_LOG_DIR/performance-candidate.tsv"
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
