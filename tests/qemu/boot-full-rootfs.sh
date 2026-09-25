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
TIMEOUT="${TIMEOUT:-180}"
MEMORY="${MEMORY:-1024M}"
REQUIRE_ARTIFACTS="${REQUIRE_ARTIFACTS:-0}"
NO_CLEANUP="${NO_CLEANUP:-false}"
source "$SCRIPT_DIR/qemu-common.sh"

while [ $# -gt 0 ]; do
  case "$1" in
    --kernel=*) KERNEL_IMAGE="${1#*=}"; shift ;;
    --kernel) [ $# -ge 2 ] || shreeos_die "--kernel requires a path"; KERNEL_IMAGE="$2"; shift 2 ;;
    --initrd=*) INITRD="${1#*=}"; shift ;;
    --initrd) [ $# -ge 2 ] || shreeos_die "--initrd requires a path"; INITRD="$2"; shift 2 ;;
    --memory=*) MEMORY="${1#*=}"; shift ;;
    --memory) [ $# -ge 2 ] || shreeos_die "--memory requires a value"; MEMORY="$2"; shift 2 ;;
    --timeout=*) TIMEOUT="${1#*=}"; shift ;;
    --timeout) [ $# -ge 2 ] || shreeos_die "--timeout requires a value"; TIMEOUT="$2"; shift 2 ;;
    --no-cleanup) NO_CLEANUP=true; shift ;;
    --help|-h) echo "Usage: boot-full-rootfs.sh [--kernel=<path>] [--initrd=<path>] [--memory=SIZE] [--timeout=SECONDS] [--no-cleanup]"; exit 0 ;;
    *) shreeos_die "Unknown option: $1" ;;
  esac
done

case "${NO_CLEANUP,,}" in
  1|true|yes|on) NO_CLEANUP=true ;;
  0|false|no|off) NO_CLEANUP=false ;;
  *) shreeos_die "Invalid NO_CLEANUP value: $NO_CLEANUP" ;;
esac

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

LOG_DIR="${LOG_DIR:-${PROJECT_ROOT}/build/logs}"
mkdir -p "$LOG_DIR" || shreeos_die "Unable to create QEMU log directory: $LOG_DIR"
LOG_FILE="$(mktemp "${LOG_DIR}/qemu-full-rootfs.XXXXXX.log")"
QEMU_PID=""
cleanup_qemu() {
  qemu_stop "${QEMU_PID:-}"
  QEMU_PID=""
}
trap cleanup_qemu EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

qemu_start "$LOG_FILE" -kernel "$KERNEL_IMAGE" -initrd "$INITRD" -append "console=tty0 console=ttyS0,115200n8"
if qemu_wait_for_marker "$LOG_FILE" "$QEMU_PID" "$TIMEOUT" "Full rootfs"; then
  cleanup_qemu
  echo "  Complete log: $LOG_FILE"
  if [ "$NO_CLEANUP" = true ]; then
    echo "  NO_CLEANUP enabled; complete log retained"
  fi
  exit 0
fi
cleanup_qemu
echo "  Complete log: $LOG_FILE"
exit 1
