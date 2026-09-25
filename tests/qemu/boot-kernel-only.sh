#!/usr/bin/env bash
# QEMU kernel boot test for ShreeOS.
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$PROJECT_ROOT/build.conf"
source "$PROJECT_ROOT/scripts/common.sh"

QEMU_BIN="${QEMU_BIN:-qemu-system-x86_64}"
KERNEL_IMAGE="${KERNEL_IMAGE:-${PROJECT_ROOT}/build/build-kernel/arch/x86/boot/bzImage}"
INITRAMFS="${INITRAMFS:-${PROJECT_ROOT}/kernel/initramfs/initramfs.cpio.gz}"
MARKER_STRING="${MARKER_STRING:-ShreeOS kernel boot OK}"
TIMEOUT="${TIMEOUT:-30}"
MEMORY="${MEMORY:-256M}"
REQUIRE_ARTIFACTS="${REQUIRE_ARTIFACTS:-0}"
NO_CLEANUP=false

while [ $# -gt 0 ]; do
  case "$1" in
    --kernel=*) KERNEL_IMAGE="${1#*=}"; shift ;;
    --kernel) [ $# -ge 2 ] || shreeos_die "--kernel requires a path"; KERNEL_IMAGE="$2"; shift 2 ;;
    --initramfs=*) INITRAMFS="${1#*=}"; shift ;;
    --initramfs) [ $# -ge 2 ] || shreeos_die "--initramfs requires a path"; INITRAMFS="$2"; shift 2 ;;
    --no-cleanup) NO_CLEANUP=true; shift ;;
    --help|-h) echo "Usage: boot-kernel-only.sh [--kernel=<path>] [--initramfs=<path>] [--no-cleanup]"; exit 0 ;;
    *) shreeos_die "Unknown option: $1" ;;
  esac
done

shreeos_step "QEMU kernel boot test"
if ! command -v "$QEMU_BIN" >/dev/null 2>&1; then
  if [ "$REQUIRE_ARTIFACTS" = "1" ]; then shreeos_die "QEMU not found: $QEMU_BIN"; fi
  shreeos_warn "QEMU not found: $QEMU_BIN"; exit 77
fi
if [ ! -s "$KERNEL_IMAGE" ]; then
  if [ "$REQUIRE_ARTIFACTS" = "1" ]; then shreeos_die "Required kernel image missing or empty: $KERNEL_IMAGE"; fi
  shreeos_warn "Kernel image missing or empty: $KERNEL_IMAGE"
  exit 77
fi

# The tiny kernel-test initramfs is deliberately not part of production kernel
# builds. Build the fixture on demand so strict testing does not depend on a
# stale generated file being present in the checkout.
if [ ! -s "$INITRAMFS" ] && [ "$INITRAMFS" = "$PROJECT_ROOT/kernel/initramfs/initramfs.cpio.gz" ]; then
  shreeos_step "Building dedicated kernel-test initramfs fixture"
  make -C "$PROJECT_ROOT/kernel/initramfs" all
fi
if [ ! -s "$INITRAMFS" ]; then
  if [ "$REQUIRE_ARTIFACTS" = "1" ]; then shreeos_die "Required initramfs missing or empty: $INITRAMFS"; fi
  shreeos_warn "Initramfs missing or empty: $INITRAMFS"
  exit 77
fi

# Persist serial logs under build/logs so CI artifacts can capture boot failures.
LOG_DIR="${PROJECT_ROOT}/build/logs"
mkdir -p "$LOG_DIR"
LOG_FILE="$(mktemp "${LOG_DIR}/qemu-kernel-only.XXXXXX.log")"
QEMU_PID=""
cleanup_qemu() {
  if [ -n "$QEMU_PID" ] && kill -0 "$QEMU_PID" 2>/dev/null; then
    kill "$QEMU_PID" 2>/dev/null || true
    wait "$QEMU_PID" 2>/dev/null || true
  fi
}
trap cleanup_qemu EXIT INT TERM

"$QEMU_BIN"   -kernel "$KERNEL_IMAGE"   -initrd "$INITRAMFS"   -nographic   -append "console=ttyS0"   -m "$MEMORY"   -no-reboot   > "$LOG_FILE" 2>&1 &
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
  shreeos_ok "Kernel boot test PASSED — marker found after ${WAITED}s"
  if [ "$NO_CLEANUP" = false ]; then rm -f "$LOG_FILE"; else echo "Log: $LOG_FILE"; fi
  exit 0
fi
shreeos_warn "Kernel boot test FAILED — marker not found within ${TIMEOUT}s"
echo "Log: $LOG_FILE"
exit 1
