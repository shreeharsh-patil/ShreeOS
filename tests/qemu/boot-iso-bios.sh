#!/usr/bin/env bash
# QEMU BIOS boot validation for a ShreeOS ISO.
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$PROJECT_ROOT/build.conf"
source "$PROJECT_ROOT/scripts/common.sh"

QEMU_BIN="${QEMU_BIN:-qemu-system-x86_64}"
ISO="${ISO:-${PROJECT_ROOT}/out/${DISTRO_ID}-${DISTRO_VERSION}.iso}"
MARKER_STRING="${MARKER_STRING:-ShreeOS init: critical services ready}"
TIMEOUT="${TIMEOUT:-${BIOS_TIMEOUT:-180}}"
MEMORY="${MEMORY:-1024M}"
REQUIRE_ARTIFACTS="${REQUIRE_ARTIFACTS:-0}"
NO_CLEANUP="${NO_CLEANUP:-false}"
source "$SCRIPT_DIR/qemu-common.sh"

while [ $# -gt 0 ]; do
  case "$1" in
    --iso=*) ISO="${1#*=}"; shift ;;
    --iso) [ $# -ge 2 ] || shreeos_die "--iso requires a path"; ISO="$2"; shift 2 ;;
    --memory=*) MEMORY="${1#*=}"; shift ;;
    --memory) [ $# -ge 2 ] || shreeos_die "--memory requires a value"; MEMORY="$2"; shift 2 ;;
    --timeout=*) TIMEOUT="${1#*=}"; shift ;;
    --timeout) [ $# -ge 2 ] || shreeos_die "--timeout requires a value"; TIMEOUT="$2"; shift 2 ;;
    --no-cleanup) NO_CLEANUP=true; shift ;;
    --help|-h) echo "Usage: boot-iso-bios.sh [--iso=<path>|--iso <path>] [--memory=SIZE] [--timeout=SECONDS] [--no-cleanup]"; exit 0 ;;
    *) shreeos_die "Unknown option: $1" ;;
  esac
done

case "${NO_CLEANUP,,}" in
  1|true|yes|on) NO_CLEANUP=true ;;
  0|false|no|off) NO_CLEANUP=false ;;
  *) shreeos_die "Invalid NO_CLEANUP value: $NO_CLEANUP" ;;
esac

shreeos_step "QEMU BIOS ISO boot test"

if ! command -v "$QEMU_BIN" >/dev/null 2>&1; then
  if [ "$REQUIRE_ARTIFACTS" = "1" ]; then shreeos_die "QEMU not found: $QEMU_BIN"; fi
  shreeos_warn "QEMU not found: $QEMU_BIN"
  exit 77
fi
if [ ! -s "$ISO" ]; then
  if [ "$REQUIRE_ARTIFACTS" = "1" ]; then shreeos_die "ISO not found or empty: $ISO"; fi
  shreeos_warn "ISO not found or empty: $ISO"
  exit 77
fi

shreeos_ok "ISO: $ISO"
LOG_DIR="${LOG_DIR:-${PROJECT_ROOT}/build/logs}"
mkdir -p "$LOG_DIR" || shreeos_die "Unable to create QEMU log directory: $LOG_DIR"
LOG_FILE="$(mktemp "${LOG_DIR}/qemu-iso-bios.XXXXXX.log")"
QEMU_PID=""

cleanup_qemu() {
  qemu_stop "${QEMU_PID:-}"
  QEMU_PID=""
}
trap cleanup_qemu EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

qemu_start "$LOG_FILE" -cdrom "$ISO" -boot d
if qemu_wait_for_marker "$LOG_FILE" "$QEMU_PID" "$TIMEOUT" "BIOS ISO"; then
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
