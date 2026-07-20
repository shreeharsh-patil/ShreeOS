#!/usr/bin/env bash
# installer/tests/test-install.sh — Non-interactive installer test
#
# Creates a blank QEMU virtual disk, runs the installer,
# then boots the installed disk to verify it reaches init.
#
# Usage:
#   bash installer/tests/test-install.sh
#   bash installer/tests/test-install.sh --image <path> --keep
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LUMEN_ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$LUMEN_ROOT_DIR/build.conf"
source "$LUMEN_ROOT_DIR/scripts/common.sh"

QEMU_BIN="${QEMU_BIN:-qemu-system-x86_64}"
DISK_IMAGE="${DISK_IMAGE:-/tmp/shreeos-install-test.img}"
DISK_SIZE="${DISK_SIZE:-4G}"
MARKER_STRING="${MARKER_STRING:-ShreeOS init: reached PID 1}"
TIMEOUT="${TIMEOUT:-120}"
KEEP=false

for arg in "$@"; do
  case "$arg" in
    --image=*) DISK_IMAGE="${arg#*=}" ;;
    --keep)    KEEP=true ;;
  esac
done

lumen_require_cmd qemu-img sfdisk mkfs.ext4

lumen_step "Installer test: install to virtual disk"

# 1. Create blank disk image
qemu-img create -f raw "$DISK_IMAGE" "$DISK_SIZE" 2>&1
lumen_ok "Disk image created: ${DISK_IMAGE}"

# 2. Attach via loopback
sudo losetup -D 2>/dev/null || true
LOOP=$(sudo losetup -f)
sudo losetup -P "$LOOP" "$DISK_IMAGE"
lumen_log "Loop device: ${LOOP}"

# 3. Run installer
sudo bash "${LUMEN_ROOT_DIR}/installer/scripts/install-to-disk.sh" "$LOOP" --yes \
  --hostname="shreeos-test" --root-password="test"

# 4. Detach loop device
sync
sudo losetup -d "$LOOP"

# 5. Boot installed disk in QEMU
lumen_step "Booting installed disk in QEMU"
LOG_FILE=$(mktemp /tmp/shreeos-qemu-install.XXXXXX)

"$QEMU_BIN" \
  -drive file="$DISK_IMAGE",format=raw \
  -m 256M \
  -nographic \
  -no-reboot \
  2>&1 | head -c 131072 > "$LOG_FILE" &
QEMU_PID=$!

WAITED=0
FOUND=false
while [ $WAITED -lt $TIMEOUT ]; do
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
  lumen_ok "Installer test PASSED — booted from disk to init shell"
  echo "  Time: ${WAITED}s"
  [ "$KEEP" = false ] && rm -f "$LOG_FILE" "$DISK_IMAGE"
  exit 0
else
  lumen_warn "Installer test FAILED — marker not found within ${TIMEOUT}s"
  echo "  Log: ${LOG_FILE}"
  [ "$KEEP" = false ] && rm -f "$DISK_IMAGE"
  exit 1
fi
