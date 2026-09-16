#!/usr/bin/env bash
# QEMU full rootfs boot test for ShreeOS.
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$PROJECT_ROOT/build.conf"
source "$PROJECT_ROOT/scripts/common.sh"

QEMU_BIN="${QEMU_BIN:-qemu-system-x86_64}"
KERNEL_IMAGE="${KERNEL_IMAGE:-${PROJECT_ROOT}/build/build-kernel/arch/x86/boot/bzImage}"
INITRD="${INITRD:-${PROJECT_ROOT}/build/initramfs.cpio.gz}"
MARKER_STRING="${MARKER_STRING:-ShreeOS init: critical services ready}"
TIMEOUT="${TIMEOUT:-60}"
MEMORY="${MEMORY:-256M}"
REQUIRE_ARTIFACTS="${REQUIRE_ARTIFACTS:-0}"
NO_CLEANUP=false

while [ $# -gt 0 ]; do
  case "$1" in
    --kernel=*) KERNEL_IMAGE="${1#*=}"; shift ;;
    --kernel) [ $# -ge 2 ] || shreeos_die "--kernel requires a path"; KERNEL_IMAGE="$2"; shift 2 ;;
    --initrd=*) INITRD="${1#*=}"; shift ;;
    --initrd) [ $# -ge 2 ] || shreeos_die "--initrd requires a path"; INITRD="$2"; shift 2 ;;
    --no-cleanup) NO_CLEANUP=true; shift ;;
    --help|-h) echo "Usage: boot-full-rootfs.sh [--kernel=<path>] [--initrd=<path>] [--no-cleanup]"; exit 0 ;;
    *) shreeos_die "Unknown option: $1" ;;
  esac
done

shreeos_step "QEMU full rootfs boot test"
if ! command -v "$QEMU_BIN" >/dev/null 2>&1; then
  if [ "$REQUIRE_ARTIFACTS" = "1" ]; then shreeos_die "QEMU not found: $QEMU_BIN"; fi
  shreeos_warn "QEMU not found: $QEMU_BIN"; exit 77
fi
for artifact in "$KERNEL_IMAGE" "$INITRD"; do
  if [ ! -s "$artifact" ]; then
    if [ "$REQUIRE_ARTIFACTS" = "1" ]; then shreeos_die "Required boot artifact missing or empty: $artifact"; fi
    shreeos_warn "Boot artifact missing or empty: $artifact"; exit 77
  fi
done

LOG_FILE="$(mktemp /tmp/shreeos-qemu-rootfs.XXXXXX)"
QEMU_PID=""
cleanup_qemu() {
  if [ -n "$QEMU_PID" ] && kill -0 "$QEMU_PID" 2>/dev/null; then
    kill "$QEMU_PID" 2>/dev/null || true
    wait "$QEMU_PID" 2>/dev/null || true
  fi
}
trap cleanup_qemu EXIT INT TERM

"$QEMU_BIN"   -kernel "$KERNEL_IMAGE"   -initrd "$INITRD"   -nographic   -append "console=ttyS0"   -m "$MEMORY"   -no-reboot   > "$LOG_FILE" 2>&1 &
QEMU_PID=$!

WAITED=0
FOUND=false
while [ "$WAITED" -lt "$TIMEOUT" ]; do
  sleep 1
  WAITED=$((WAITED + 1))
  if grep -Fq "$MARKER_STRING" "$LOG_FILE" 2>/dev/null; then FOUND=true; break; fi
  kill -0 "$QEMU_PID" 2>/dev/null || break
done
cleanup_qemu
QEMU_PID=""

tail -30 "$LOG_FILE" || true
if [ "$FOUND" = true ]; then
  shreeos_ok "Full rootfs boot test PASSED — marker found after ${WAITED}s"
  if [ "$NO_CLEANUP" = false ]; then rm -f "$LOG_FILE"; else echo "Log: $LOG_FILE"; fi
  exit 0
fi
shreeos_warn "Full rootfs boot test FAILED — marker not found within ${TIMEOUT}s"
echo "Log: $LOG_FILE"
exit 1
