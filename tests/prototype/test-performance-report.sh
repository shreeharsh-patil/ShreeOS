#!/usr/bin/env bash
# Stage E: measure the unified ShreeOS image in a controlled virtual machine and
# compare it against the release targets and, once one is recorded, a measured
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
#   QEMU_LOG_DIR  directory to copy the report, metrics, serial log and QEMU log into
#   RESUME        "1" to compare against tests/prototype/performance-baseline.tsv
#   REQUIRE_BASELINE "1" to fail if no untouched-build baseline is recorded
#   CAPTURE_ONLY  "1" to validate and retain one sample but defer target gates
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

for tool in realpath xorriso unsquashfs qemu-system-x86_64 qemu-img xvfb-run timeout setsid sha256sum python3 dpkg-query; do
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
MONITOR_LOG="$TEST_DIR/monitor.log"
SCREEN="$TEST_DIR/performance-screen.ppm"
MENU_SCREEN="$TEST_DIR/performance-menu.ppm"
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
TIMER_SOURCE="$REPO_ROOT/prototype/debian-live/config/includes.chroot/etc/systemd/system/shreeos-perf-probe.timer"
TIME_HELPER_SOURCE="$REPO_ROOT/prototype/debian-live/config/includes.chroot/usr/local/lib/shreeos/performance-time.sh"
unsquashfs -q -cat "$SQUASHFS" etc/systemd/system/shreeos-perf-probe.service >"$TEST_DIR/probe.service" 2>/dev/null || true
cmp -s "$SERVICE_SOURCE" "$TEST_DIR/probe.service" || {
  echo 'Image uses a different performance probe unit than the measurement harness; baseline and candidate would not be comparable.' >&2
  exit 1
}
unsquashfs -q -cat "$SQUASHFS" etc/systemd/system/shreeos-perf-probe.timer >"$TEST_DIR/probe.timer" 2>/dev/null || true
cmp -s "$TIMER_SOURCE" "$TEST_DIR/probe.timer" || {
  echo 'Image uses a different performance probe timer than the measurement harness; baseline and candidate would not be comparable.' >&2
  exit 1
}
unsquashfs -q -cat "$SQUASHFS" usr/local/lib/shreeos/performance-time.sh >"$TEST_DIR/performance-time.sh" 2>/dev/null || true
cmp -s "$TIME_HELPER_SOURCE" "$TEST_DIR/performance-time.sh" || {
  echo 'Image uses a different boot-time parser than the measurement harness; baseline and candidate would not be comparable.' >&2
  exit 1
}
probe_sha256="$(sha256sum "$PROBE_SOURCE" | awk '{print $1}')"
probe_service_sha256="$(sha256sum "$SERVICE_SOURCE" | awk '{print $1}')"
probe_timer_sha256="$(sha256sum "$TIMER_SOURCE" | awk '{print $1}')"
probe_time_helper_sha256="$(sha256sum "$TIME_HELPER_SOURCE" | awk '{print $1}')"
measurement_protocol_sha256="$(
  cd "$REPO_ROOT"
  sha256sum \
    .github/workflows/performance-baseline.yml \
    .github/workflows/shreeos-release.yml \
    prototype/debian-live/performance-targets.tsv \
    scripts/aggregate-performance-runs.py \
    scripts/compare-performance-runs.py \
    scripts/verify-performance-manifest.py \
    tests/prototype/test-performance-report.sh | sha256sum | awk '{print $1}'
)"
qemu_version="$(qemu-system-x86_64 --version | head -n 1 | tr -d '\r')"
qemu_package_version="$(dpkg-query -W -f='${Version}' qemu-system-x86)"
seabios_package_version="$(dpkg-query -W -f='${Version}' seabios)"
BIOS_ROM=/usr/share/seabios/bios-256k.bin
[ -r "$BIOS_ROM" ] || { echo "Missing pinned SeaBIOS ROM: $BIOS_ROM" >&2; exit 2; }
bios_rom_sha256="$(sha256sum "$BIOS_ROM" | awk '{print $1}')"
host_kernel="$(uname -sr)"
host_cpu_model="$(awk -F: '/^model name[[:space:]]*:/ { sub(/^[[:space:]]+/, "", $2); print $2; exit }' /proc/cpuinfo)"
host_mem_total_kib="$(awk '$1 == "MemTotal:" { print $2; exit }' /proc/meminfo)"
firmware="SeaBIOS:$BIOS_ROM:sha256=$bios_rom_sha256"
qemu_profile='q35;4096MiB;2-vCPU;virtio-graphics;no-network;fresh-2GiB-virtio-raw-disk;cache=none;explicit-SeaBIOS;CD-ROM-first;1280x800'

qemu-img create -q -f raw "$TARGET_DISK" 2G

# The probe window is 30 s plus boot. A 25-minute guest deadline leaves five
# minutes for QEMU to terminate cleanly while keeping three attempts bounded.
deadline=$((SECONDS + 1500))
qemu_timeout=1800
qemu_args=(
  "-machine" "q35" "-m" "4096" "-smp" "2" "-vga" "virtio" "-nic" "none"
  "-bios" "$BIOS_ROM"
  "-drive" "file=$TARGET_DISK,format=raw,if=none,id=perf-disk,cache=none"
  "-device" "virtio-blk-pci,drive=perf-disk,serial=SHREEOSPERF"
  "-cdrom" "$ISO" "-boot" "order=d"
  "-display" "gtk" "-monitor" "unix:$MONITOR,server,nowait"
  "-serial" "stdio" "-no-reboot"
)
qemu_invocation=(
  setsid xvfb-run -a -s "-screen 0 1280x800x24"
  timeout --signal=TERM "${qemu_timeout}s" qemu-system-x86_64
  "${qemu_args[@]}"
)
printf -v qemu_command '%q ' "${qemu_invocation[@]}"
qemu_command="${qemu_command% }"
"${qemu_invocation[@]}" >"$SERIAL" 2>"$TEST_DIR/qemu.log" &
emulator_pid=$!

# Select the normal live entry from the graphical GRUB menu. Without this
# explicit keypress the baseline can remain at the menu indefinitely in QEMU.
sleep 20
if ! grep -Fq 'SHREEOS_PERF_END' "$SERIAL" 2>/dev/null; then
  python3 - "$MONITOR" "$MENU_SCREEN" "$SERIAL" <<'PY' >>"$MONITOR_LOG" 2>&1
import socket
import sys
import time
from pathlib import Path

monitor, screen, serial = sys.argv[1:]
client = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
client.settimeout(3)
for _ in range(10):
    try:
        client.connect(monitor)
        break
    except OSError:
        time.sleep(1)
else:
    raise SystemExit("QEMU monitor socket did not become available for GRUB selection")

def read_prompt():
    response = bytearray()
    deadline = time.monotonic() + 10
    while b"(qemu) " not in response:
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            raise TimeoutError("QEMU monitor did not return a prompt for GRUB selection")
        client.settimeout(remaining)
        chunk = client.recv(4096)
        if not chunk:
            raise ConnectionError("QEMU monitor closed during GRUB selection")
        response.extend(chunk)
    text = response.decode(errors="replace")
    if "Error:" in text or "Could not" in text:
        raise RuntimeError(f"QEMU monitor command failed: {text.strip()}")
    return text

def command(value):
    client.sendall((value + "\n").encode())
    return read_prompt()

def marker_seen():
    try:
        return "SHREEOS_PERF_END" in Path(serial).read_text(encoding="utf-8", errors="replace")
    except OSError:
        return False

try:
    read_prompt()
    command(f"screendump {screen}")
    command("sendkey home")
    # TCG can take longer than the initial menu delay to accept input. Retry
    # Enter a few times, checking the real serial stream between attempts.
    for attempt in range(4):
        if marker_seen():
            break
        command("sendkey ret")
        for _ in range(10):
            if marker_seen():
                break
            time.sleep(1)
finally:
    client.close()
PY
fi

while ! grep -Fq 'SHREEOS_PERF_END' "$SERIAL" 2>/dev/null; do
  if ! kill -0 "$emulator_pid" 2>/dev/null || (( SECONDS >= deadline )); then
    break
  fi
  sleep 2
done

if grep -Fq 'SHREEOS_PERF_END' "$SERIAL" 2>/dev/null; then
  # Give the guest a clean shutdown signal through the monitor.
  if ! python3 - "$MONITOR" <<'PY' >>"$MONITOR_LOG" 2>&1
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
    raise SystemExit("QEMU monitor socket did not become available to stop the guest")
client.settimeout(10)
response = bytearray()
while b"(qemu) " not in response:
    chunk = client.recv(4096)
    if not chunk:
        raise SystemExit("QEMU monitor closed before returning a prompt")
    response.extend(chunk)
client.sendall(b"quit\n")
client.close()
PY
  then
    kill -TERM -- "-$emulator_pid" 2>/dev/null || true
  fi
else
  # Snapshot the guest before stopping it so a missing probe marker can be
  # distinguished from a guest that never reached the desktop.
  python3 - "$MONITOR" "$SCREEN" <<'PY' >>"$MONITOR_LOG" 2>&1 || true
import os
import socket
import sys
import time

monitor, output = sys.argv[1:]
client = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
for _ in range(10):
    try:
        client.connect(monitor)
        break
    except OSError:
        time.sleep(1)
else:
    raise SystemExit("QEMU monitor socket did not become available for timeout diagnostics")

def read_prompt():
    response = bytearray()
    deadline = time.monotonic() + 10
    while b"(qemu) " not in response:
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            raise TimeoutError(f"QEMU monitor timed out: {response.decode(errors='replace')}")
        client.settimeout(remaining)
        chunk = client.recv(4096)
        if not chunk:
            raise ConnectionError("QEMU monitor closed before returning a prompt")
        response.extend(chunk)
    text = response.decode(errors="replace")
    print(text, end="", flush=True)
    return text

def command(value):
    client.sendall((value + "\n").encode())
    return read_prompt()

try:
    client.settimeout(10)
    read_prompt()
    command("info status")
    command(f"screendump {output}")
    if not os.path.isfile(output) or os.path.getsize(output) == 0:
        raise RuntimeError(f"QEMU did not create diagnostic screenshot: {output}")
    client.sendall(b"quit\n")
except Exception:
    try:
        client.sendall(b"quit\n")
    except OSError:
        pass
    raise
finally:
    client.close()
PY
  kill -TERM -- "-$emulator_pid" 2>/dev/null || true
fi
status=0
wait "$emulator_pid" || status=$?

if ! grep -Fq 'SHREEOS_PERF_END' "$SERIAL" 2>/dev/null; then
  echo 'The image never completed its performance probe.' >&2
  tail -n 60 "$SERIAL" >&2 || true
  if [ -n "$QEMU_LOG_DIR" ]; then
    cp -f "$SERIAL" "$QEMU_LOG_DIR/serial.log"
    if [ -s "$TEST_DIR/qemu.log" ]; then
      cp -f "$TEST_DIR/qemu.log" "$QEMU_LOG_DIR/qemu.log"
    fi
    if [ -s "$MONITOR_LOG" ]; then
      cp -f "$MONITOR_LOG" "$QEMU_LOG_DIR/monitor.log"
    fi
    if [ -s "$SCREEN" ]; then
      cp -f "$SCREEN" "$QEMU_LOG_DIR/performance-screen.ppm"
    fi
    if [ -s "$MENU_SCREEN" ]; then
      cp -f "$MENU_SCREEN" "$QEMU_LOG_DIR/performance-menu.ppm"
    fi
  fi
  tail -n 60 "$TEST_DIR/qemu.log" >&2 || true
  tail -n 60 "$MONITOR_LOG" >&2 || true
  exit 1
fi

if [ "$status" -ne 0 ]; then
  echo "QEMU exited with status $status after completing the performance probe." >&2
  [ -z "$QEMU_LOG_DIR" ] || cp -f "$SERIAL" "$QEMU_LOG_DIR/serial.log"
  [ -z "$QEMU_LOG_DIR" ] || cp -f "$TEST_DIR/qemu.log" "$QEMU_LOG_DIR/qemu.log"
  [ -z "$QEMU_LOG_DIR" ] || { [ ! -s "$MONITOR_LOG" ] || cp -f "$MONITOR_LOG" "$QEMU_LOG_DIR/monitor.log"; }
  [ -z "$QEMU_LOG_DIR" ] || { [ ! -s "$MENU_SCREEN" ] || cp -f "$MENU_SCREEN" "$QEMU_LOG_DIR/performance-menu.ppm"; }
  exit 1
fi

# Metrics are stored as key<TAB>value. Several values (top RSS, top CPU, the
# systemd blame list) legitimately contain spaces, so a space-delimited parse
# would truncate them and silently weaken the report.
awk 'index($0, "SHREEOS_PERF ") {
       line = substr($0, index($0, "SHREEOS_PERF ") + length("SHREEOS_PERF "))
       separator = index(line, "=")
       if (separator > 1) print substr(line, 1, separator - 1) "\t" substr(line, separator + 1)
     }' "$SERIAL" | sort -u >"$TEST_DIR/metrics.tsv"

{
  printf '# source_commit=%s\n' "$MEASURED_SOURCE_COMMIT"
  printf '# iso_sha256=%s\n' "$candidate_iso_sha256"
  printf '# conditions=2-vCPU,4096MiB,virtio,1280x800,no-network,BIOS,SHREEOSPERF-64MiB-rw,host-cache-bypassed\n'
  printf '# probe_sha256=%s\n' "$probe_sha256"
  printf '# probe_service_sha256=%s\n' "$probe_service_sha256"
  printf '# probe_timer_sha256=%s\n' "$probe_timer_sha256"
  printf '# probe_time_helper_sha256=%s\n' "$probe_time_helper_sha256"
  printf '# measurement_protocol_sha256=%s\n' "$measurement_protocol_sha256"
  printf '# qemu_version=%s\n' "$qemu_version"
  printf '# qemu_package_version=%s\n' "$qemu_package_version"
  printf '# seabios_package_version=%s\n' "$seabios_package_version"
  printf '# bios_rom_sha256=%s\n' "$bios_rom_sha256"
  printf '# host_kernel=%s\n' "$host_kernel"
  printf '# host_cpu_model=%s\n' "$host_cpu_model"
  printf '# host_mem_total_kib=%s\n' "$host_mem_total_kib"
  printf '# firmware=%s\n' "$firmware"
  printf '# qemu_profile=%s\n' "$qemu_profile"
  printf '# qemu_command=%s\n' "$qemu_command"
  awk -F'\t' '$1 ~ /^(mem_used_mib|cpu_busy_pct|boot_total_ms|graphical_reached_ms|desktop_ready|pss_available|units_failed|storage_write_mib_s|storage_read_mib_s)$/ {
    print $1 "\t" $2
  }' "$TEST_DIR/metrics.tsv"
} >"$TEST_DIR/performance-candidate.tsv"

# Persist raw and parsed evidence before interpreting or rejecting any metric.
[ -z "$QEMU_LOG_DIR" ] || cp -f "$SERIAL" "$QEMU_LOG_DIR/serial.log"
[ -z "$QEMU_LOG_DIR" ] || cp -f "$TEST_DIR/qemu.log" "$QEMU_LOG_DIR/qemu.log"
[ -z "$QEMU_LOG_DIR" ] || { [ ! -s "$MONITOR_LOG" ] || cp -f "$MONITOR_LOG" "$QEMU_LOG_DIR/monitor.log"; }
[ -z "$QEMU_LOG_DIR" ] || { [ ! -s "$MENU_SCREEN" ] || cp -f "$MENU_SCREEN" "$QEMU_LOG_DIR/grub-menu.ppm"; }
[ -z "$QEMU_LOG_DIR" ] || cp -f "$TEST_DIR/metrics.tsv" "$QEMU_LOG_DIR/metrics.tsv"
[ -z "$QEMU_LOG_DIR" ] || cp -f "$TEST_DIR/performance-candidate.tsv" "$QEMU_LOG_DIR/performance-candidate.tsv"
[ -s "$TEST_DIR/metrics.tsv" ] || { echo 'No SHREEOS_PERF metrics were captured; logs and empty metrics were retained.' >&2; exit 1; }

metric() {
  awk -F'\t' -v key="$1" '$1 == key { print $2; exit }' "$TEST_DIR/metrics.tsv"
}

require_positive_metric() {
  key="$1"
  measured="$(metric "$key")"
  if ! awk -v value="$measured" 'BEGIN {
    if (value !~ /^[0-9]+([.][0-9]+)?$/ || value + 0 <= 0) exit 1
  }'; then
    printf 'Missing or non-positive %s measurement: %s\n' "$key" "${measured:-missing}" >&2
    exit 1
  fi
}

for required_positive in boot_total_ms graphical_reached_ms storage_write_mib_s storage_read_mib_s; do
  require_positive_metric "$required_positive"
done
if [ "$(metric desktop_ready)" != 1 ]; then
  printf 'The live desktop did not reach the required ready state: %s\n' \
    "$(metric desktop_ready)" >&2
  exit 1
fi

REPORT="$TEST_DIR/performance-report.md"
{
  printf '# ShreeOS performance report\n\n'
  # Backticks are Markdown code spans in the generated report, not command
  # substitution, so the literal-quote warning does not apply.
  # shellcheck disable=SC2016
  printf 'Image: `%s`\n' "$(basename -- "$ISO")"
  printf 'Measured: %s (UTC)\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  printf 'Conditions: 2 vCPU, 4096 MiB RAM, virtio graphics, 1280x800, QEMU BIOS, no network; serial-tagged QEMU scratch disk, 64 MiB sequential direct write/read\n\n'
  printf '| Metric | Measured |\n| --- | --- |\n'
  while IFS=$'\t' read -r key value; do
    [ -n "$key" ] || continue
    printf '| %s | %s |\n' "$key" "${value:-}"
  done <"$TEST_DIR/metrics.tsv"
  printf '\n'
} >"$REPORT"

# --- Enforce the release targets --------------------------------------------
failures=0
if [ "${CAPTURE_ONLY:-0}" != 1 ]; then
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
  baseline_probe_timer_sha256="$(awk -F= '$1 == "# probe_timer_sha256" { print $2; exit }' "$BASELINE")"
  baseline_probe_time_helper_sha256="$(awk -F= '$1 == "# probe_time_helper_sha256" { print $2; exit }' "$BASELINE")"
  baseline_measurement_protocol_sha256="$(awk -F= '$1 == "# measurement_protocol_sha256" { print $2; exit }' "$BASELINE")"
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
  if [ "$baseline_conditions" != '2-vCPU,4096MiB,virtio,1280x800,no-network,BIOS,SHREEOSPERF-64MiB-rw,host-cache-bypassed' ]; then
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
  if ! [[ "$baseline_probe_timer_sha256" =~ ^[0-9a-f]{64}$ ]] ||
    [ "$baseline_probe_timer_sha256" != "$probe_timer_sha256" ]; then
    printf 'Baseline performance probe timer hash does not match this candidate.\n' >&2
    baseline_valid=0
    failures=$((failures + 1))
  fi
  if ! [[ "$baseline_probe_time_helper_sha256" =~ ^[0-9a-f]{64}$ ]] ||
    [ "$baseline_probe_time_helper_sha256" != "$probe_time_helper_sha256" ]; then
    printf 'Baseline boot-time parser hash does not match this candidate.\n' >&2
    baseline_valid=0
    failures=$((failures + 1))
  fi
  if ! [[ "$baseline_measurement_protocol_sha256" =~ ^[0-9a-f]{64}$ ]] ||
    [ "$baseline_measurement_protocol_sha256" != "$measurement_protocol_sha256" ]; then
    printf 'Baseline measurement protocol hash does not match this candidate.\n' >&2
    baseline_valid=0
    failures=$((failures + 1))
  fi
  for environment_field in qemu_version qemu_package_version seabios_package_version bios_rom_sha256 host_kernel host_cpu_model host_mem_total_kib firmware qemu_profile; do
    baseline_environment="$(awk -F= -v key="$environment_field" '$1 == "# " key { sub(/^[^=]*=/, ""); print; exit }' "$BASELINE")"
    measured_environment="$(awk -F= -v key="$environment_field" '$1 == "# " key { sub(/^[^=]*=/, ""); print; exit }' "$TEST_DIR/performance-candidate.tsv")"
    if [ -z "$baseline_environment" ] || [ "$baseline_environment" != "$measured_environment" ]; then
      printf 'Baseline %s does not match the candidate measurement environment.\n' "$environment_field" >&2
      baseline_valid=0
      failures=$((failures + 1))
    fi
  done
  for required_metric in mem_used_mib cpu_busy_pct boot_total_ms graphical_reached_ms desktop_ready storage_write_mib_s storage_read_mib_s; do
    baseline_value="$(awk -F'\t' -v key="$required_metric" \
      '$1 == key { print $2; exit }' "$BASELINE")"
    if ! [[ "$baseline_value" =~ ^[0-9]+([.][0-9]+)?$ ]]; then
      printf 'Baseline is missing a numeric %s measurement.\n' "$required_metric" >&2
      baseline_valid=0
      failures=$((failures + 1))
    fi
  done
  for required_positive in boot_total_ms graphical_reached_ms desktop_ready storage_write_mib_s storage_read_mib_s; do
    baseline_value="$(awk -F'\t' -v key="$required_positive" \
      '$1 == key { print $2; exit }' "$BASELINE")"
    if ! awk -v value="$baseline_value" 'BEGIN {
      if (value !~ /^[0-9]+([.][0-9]+)?$/ || value + 0 <= 0) exit 1
    }'; then
      printf 'Baseline is missing a positive %s measurement.\n' "$required_positive" >&2
      baseline_valid=0
      failures=$((failures + 1))
    fi
  done
  while IFS=$'\t' read -r key baseline_value; do
    case "$key" in '' | '#'*) continue ;; esac
    measured="$(metric "$key")"
    [ -n "$measured" ] || continue
    if [[ "$key" == storage_* ]]; then
      printf '| %s | %s | %s | informational only; backing storage varies by runner |\n' \
        "$key" "$baseline_value" "$measured" >>"$REPORT"
      continue
    fi
    regression_delta='((m - b) / b) * 100'
    verdict="$(awk -v b="$baseline_value" -v m="$measured" -v t="$REGRESSION_TOLERANCE_PCT" \
      -v expression="$regression_delta" 'BEGIN {
        if (b <= 0) { print "no-baseline"; exit }
        if (expression == "((b - m) / b) * 100") delta = ((b - m) / b) * 100
        else delta = ((m - b) / b) * 100
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
else
  printf '\n## Aggregate acceptance deferred\n\nThis valid sample was captured without per-run performance gates. The workflow evaluates all three samples after aggregation.\n' >>"$REPORT"
fi

{
  printf '\n## Target evaluation\n\n'
  if [ "${CAPTURE_ONLY:-0}" = 1 ]; then
    printf 'Sample capture and structural validation completed; aggregate target and baseline gates are deferred.\n'
  elif [ "$MEASURED_SOURCE_COMMIT" = "$UNTOUCHED_BASELINE_COMMIT" ] && [ "$failures" -eq 0 ]; then
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
if [ "${CAPTURE_ONLY:-0}" = 1 ]; then
  printf 'Performance sample captured; aggregate acceptance is deferred.\n'
else
  printf 'Performance gate passed.\n'
fi
