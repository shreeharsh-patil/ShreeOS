#!/usr/bin/env bash
# tests/qemu/boot-full-rootfs.sh — QEMU boot test for ShreeOS full rootfs
#
# Boots the kernel + assembled rootfs under QEMU and checks
# for the custom init marker string in serial output.
#
# Prerequisites:
#   - Built kernel:   build/build-kernel/arch/x86/boot/bzImage
#   - Built initramfs: build/initramfs.cpio.gz  (from rootfs/scripts/make-rootfs.sh)
#   - qemu-system-x86_64 installed
#
# Usage:
#   bash tests/qemu/boot-full-rootfs.sh                    # run test
#   bash tests/qemu/boot-full-rootfs.sh --kernel <path>    # custom kernel
#   bash tests/qemu/boot-full-rootfs.sh --initrd <path>    # custom initrd
#   bash tests/qemu/boot-full-rootfs.sh --no-cleanup       # keep QEMU logs
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$PROJECT_ROOT/build.conf"
source "$PROJECT_ROOT/scripts/common.sh"

QEMU_BIN="${QEMU_BIN:-qemu-system-x86_64}"
KERNEL_IMAGE="${KERNEL_IMAGE:-${PROJECT_ROOT}/build/build-kernel/arch/x86/boot/bzImage}"
INITRD="${INITRD:-${PROJECT_ROOT}/build/initramfs.cpio.gz}"
MARKER_STRING="${MARKER_STRING:-ShreeOS init: reached PID 1}"
TIMEOUT="${TIMEOUT:-60}"
MEMORY="${MEMORY:-256M}"
NO_CLEANUP=false

for arg in "$@"; do
  case "$arg" in
    --kernel=*)   KERNEL_IMAGE="${arg#*=}" ;;
    --initrd=*)   INITRD="${arg#*=}" ;;
    --no-cleanup) NO_CLEANUP=true ;;
    --help|-h)
      echo "Usage: boot-full-rootfs.sh [--kernel=<path>] [--initrd=<path>] [--no-cleanup]"
      exit 0
      ;;
  esac
done

lumen_step "QEMU full rootfs boot test"

if ! command -v "$QEMU_BIN" &>/dev/null; then
  lumen_die "QEMU not found: ${QEMU_BIN}"
fi
lumen_ok "QEMU found: $($QEMU_BIN --version | head -1)"

if [ ! -f "$KERNEL_IMAGE" ] || [ ! -f "$INITRD" ]; then
  lumen_warn "Kernel (${KERNEL_IMAGE}) or initrd (${INITRD}) not built yet — skipping rootfs boot test."
  exit 0
fi
lumen_ok "Kernel: ${KERNEL_IMAGE}"
lumen_ok "Initrd: ${INITRD}"

LOG_FILE=$(mktemp /tmp/shreeos-qemu-rootfs.XXXXXX)
echo "  Log: ${LOG_FILE}"
echo "  Timeout: ${TIMEOUT}s"

"$QEMU_BIN" \
  -kernel "$KERNEL_IMAGE" \
  -initrd "$INITRD" \
  -nographic \
  -append "console=ttyS0" \
  -m "$MEMORY" \
  -no-reboot \
  2>&1 | head -c 131072 > "$LOG_FILE" &
QEMU_PID=$!

WAITED=0
FOUND=false
while [ $WAITED -lt "$TIMEOUT" ]; do
  sleep 1
  WAITED=$((WAITED + 1))
  if grep -q "$MARKER_STRING" "$LOG_FILE" 2>/dev/null; then
    FOUND=true
    break
  fi
  if ! kill -0 "$QEMU_PID" 2>/dev/null; then
    break
  fi
done

kill "$QEMU_PID" 2>/dev/null || true
wait "$QEMU_PID" 2>/dev/null || true

echo ""
echo "--- QEMU Serial Output (last 30 lines) ---"
tail -30 "$LOG_FILE"
echo "--- End of output ---"

if [ "$FOUND" = true ]; then
  lumen_ok "Full rootfs boot test PASSED — init marker found"
  echo "  Marker: '${MARKER_STRING}'"
  echo "  Time:   ${WAITED}s"
  if [ "$NO_CLEANUP" = false ]; then
    rm -f "$LOG_FILE"
  fi
  exit 0
else
  lumen_warn "Full rootfs boot test FAILED — marker not found within ${TIMEOUT}s"
  echo "  Expected: '${MARKER_STRING}'"
  echo "  Log:      ${LOG_FILE}"
  exit 1
fi
