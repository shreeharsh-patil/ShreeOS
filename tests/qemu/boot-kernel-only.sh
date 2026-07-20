#!/usr/bin/env bash
# tests/qemu/boot-kernel-only.sh — QEMU boot test for the ShreeOS kernel
#
# Boots the cross-compiled kernel with embedded initramfs under QEMU
# and checks the serial output for the expected marker string.
#
# Prerequisites:
#   - Built kernel: build/build-kernel/arch/x86/boot/bzImage
#   - qemu-system-x86_64 installed
#   - Initramfs: kernel/initramfs/initramfs.cpio.gz
#
# Usage:
#   bash tests/qemu/boot-kernel-only.sh                   # run test
#   bash tests/qemu/boot-kernel-only.sh --kernel <path>   # custom kernel path
#   bash tests/qemu/boot-kernel-only.sh --no-cleanup      # keep QEMU logs
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$PROJECT_ROOT/build.conf"
source "$PROJECT_ROOT/scripts/common.sh"

# --- Configuration ---
QEMU_BIN="${QEMU_BIN:-qemu-system-x86_64}"
KERNEL_IMAGE="${KERNEL_IMAGE:-${PROJECT_ROOT}/build/build-kernel/arch/x86/boot/bzImage}"
INITRAMFS="${INITRAMFS:-${PROJECT_ROOT}/kernel/initramfs/initramfs.cpio.gz}"
MARKER_STRING="${MARKER_STRING:-ShreeOS kernel boot OK}"
TIMEOUT="${TIMEOUT:-30}"       # seconds before we declare failure
MEMORY="${MEMORY:-256M}"

NO_CLEANUP=false

for arg in "$@"; do
  case "$arg" in
    --kernel=*) KERNEL_IMAGE="${arg#*=}" ;;
    --initramfs=*) INITRAMFS="${arg#*=}" ;;
    --no-cleanup) NO_CLEANUP=true ;;
    --help|-h)
      echo "Usage: boot-kernel-only.sh [--kernel=<path>] [--initramfs=<path>] [--no-cleanup]"
      exit 0
      ;;
  esac
done

# --- Pre-flight checks ---
lumen_step "QEMU kernel boot test"

if ! command -v "$QEMU_BIN" &>/dev/null; then
  lumen_die "QEMU not found: ${QEMU_BIN}. Install with: sudo apt install qemu-system-x86"
fi
lumen_ok "QEMU found: $($QEMU_BIN --version | head -1)"

if [ ! -f "$KERNEL_IMAGE" ]; then
  lumen_die "Kernel image not found: ${KERNEL_IMAGE}. Run kernel/scripts/build-kernel.sh first."
fi
lumen_ok "Kernel image: ${KERNEL_IMAGE} ($(stat -c%s "$KERNEL_IMAGE" 2>/dev/null || stat -f%z "$KERNEL_IMAGE" 2>/dev/null || echo '?') bytes)"

if [ ! -f "$INITRAMFS" ]; then
  lumen_die "Initramfs not found: ${INITRAMFS}. Run kernel/scripts/build-kernel.sh first."
fi
lumen_ok "Initramfs: ${INITRAMFS}"

# --- Run QEMU ---
LOG_FILE=$(mktemp /tmp/shreeos-qemu-boot.XXXXXX)
echo "  Log: ${LOG_FILE}"
echo "  QEMU PID: $$ (will time out after ${TIMEOUT}s)"

lumen_step "Booting kernel in QEMU..."

# Run QEMU in background, capture serial output to log file
"$QEMU_BIN" \
  -kernel "$KERNEL_IMAGE" \
  -initrd "$INITRAMFS" \
  -nographic \
  -append "console=ttyS0" \
  -m "$MEMORY" \
  -no-reboot \
  2>&1 | head -c 65536 > "$LOG_FILE" &
QEMU_PID=$!

# Wait for marker or timeout
WAITED=0
FOUND=false
while [ $WAITED -lt $TIMEOUT ]; do
  sleep 1
  WAITED=$((WAITED + 1))
  if grep -q "$MARKER_STRING" "$LOG_FILE" 2>/dev/null; then
    FOUND=true
    break
  fi
  # If QEMU exited, stop waiting
  if ! kill -0 "$QEMU_PID" 2>/dev/null; then
    break
  fi
done

# Kill QEMU if still running
kill "$QEMU_PID" 2>/dev/null || true
wait "$QEMU_PID" 2>/dev/null || true

# --- Results ---
echo ""
echo "--- QEMU Serial Output (last 30 lines) ---"
tail -30 "$LOG_FILE"
echo "--- End of output ---"

if [ "$FOUND" = true ]; then
  lumen_ok "Kernel boot test PASSED — marker string found in serial output"
  echo "  Marker: '${MARKER_STRING}'"
  echo "  Time:   ${WAITED}s"
  if [ "$NO_CLEANUP" = false ]; then
    rm -f "$LOG_FILE"
  else
    echo "  Log:    ${LOG_FILE} (kept)"
  fi
  exit 0
else
  lumen_warn "Kernel boot test FAILED — marker string not found within ${TIMEOUT}s"
  echo "  Expected: '${MARKER_STRING}'"
  echo "  Log:      ${LOG_FILE}"
  exit 1
fi
