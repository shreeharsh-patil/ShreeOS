#!/usr/bin/env bash
# installer/tests/test-install.sh — Non-interactive installer test
#
# Creates an isolated raw disk image, installs ShreeOS to a dedicated loop
# device, then boots that disk in QEMU and waits for the init-ready marker.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LUMEN_ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$LUMEN_ROOT_DIR/build.conf"
source "$LUMEN_ROOT_DIR/scripts/common.sh"

QEMU_BIN="${QEMU_BIN:-qemu-system-x86_64}"
DISK_IMAGE="${DISK_IMAGE:-/tmp/shreeos-install-test.img}"
DISK_SIZE="${DISK_SIZE:-4G}"
MARKER_STRING="${MARKER_STRING:-ShreeOS init: critical services ready}"
TIMEOUT="${TIMEOUT:-120}"
KEEP=false

for arg in "$@"; do
  case "$arg" in
    --image=*) DISK_IMAGE="${arg#*=}" ;;
    --keep) KEEP=true ;;
    *) lumen_die "Unknown installer test option: $arg" ;;
  esac
done

lumen_require_cmd qemu-img sfdisk mkfs.ext4 losetup "$QEMU_BIN"
command -v sudo >/dev/null 2>&1 || lumen_die "sudo is required for loop-device installer testing"
if ! command -v mkfs.vfat >/dev/null 2>&1 && ! command -v mkfs.fat >/dev/null 2>&1; then
  lumen_die "mkfs.vfat or mkfs.fat is required for the default UEFI installer path"
fi

LOOP=""
LOG_FILE=""
CREDS_FILE=""
QEMU_PID=""

cleanup() {
  if [ -n "$QEMU_PID" ] && kill -0 "$QEMU_PID" 2>/dev/null; then
    kill "$QEMU_PID" 2>/dev/null || true
    wait "$QEMU_PID" 2>/dev/null || true
  fi
  if [ -n "$LOOP" ]; then
    sudo losetup -d "$LOOP" 2>/dev/null || true
  fi
  [ -n "$CREDS_FILE" ] && rm -f "$CREDS_FILE"
  if [ "$KEEP" = false ]; then
    [ -n "$LOG_FILE" ] && rm -f "$LOG_FILE"
    rm -f "$DISK_IMAGE"
  fi
}
trap cleanup EXIT INT TERM

lumen_step "Installer test: install to isolated virtual disk"

rm -f "$DISK_IMAGE"
qemu-img create -f raw "$DISK_IMAGE" "$DISK_SIZE" >/dev/null
lumen_ok "Disk image created: ${DISK_IMAGE}"

LOOP=$(sudo losetup --find --show --partscan "$DISK_IMAGE")
[ -n "$LOOP" ] || lumen_die "Unable to allocate a loop device for installer test"
lumen_log "Loop device: ${LOOP}"

CREDS_FILE=$(mktemp /tmp/shreeos-install-creds-XXXXXX)
chmod 600 "$CREDS_FILE"
printf '%s\n' "test-root-password" > "$CREDS_FILE"

sudo bash "${LUMEN_ROOT_DIR}/installer/scripts/install-to-disk.sh" "$LOOP" --yes \
  --hostname="shreeos-test" \
  --timezone="UTC" \
  --credentials-file="$CREDS_FILE"

rm -f "$CREDS_FILE"
CREDS_FILE=""

sync
sudo losetup -d "$LOOP"
LOOP=""

lumen_step "Booting installed disk in QEMU"
LOG_FILE=$(mktemp /tmp/shreeos-qemu-install.XXXXXX)

"$QEMU_BIN" \
  -drive file="$DISK_IMAGE",format=raw \
  -m 256M \
  -nographic \
  -no-reboot \
  >"$LOG_FILE" 2>&1 &
QEMU_PID=$!

WAITED=0
FOUND=false
while [ "$WAITED" -lt "$TIMEOUT" ]; do
  sleep 1
  WAITED=$((WAITED + 1))
  if grep -Fq "$MARKER_STRING" "$LOG_FILE" 2>/dev/null; then
    FOUND=true
    break
  fi
  if ! kill -0 "$QEMU_PID" 2>/dev/null; then
    break
  fi
done

if kill -0 "$QEMU_PID" 2>/dev/null; then
  kill "$QEMU_PID" 2>/dev/null || true
fi
wait "$QEMU_PID" 2>/dev/null || true
QEMU_PID=""

echo ""
echo "--- QEMU Serial Output (last 30 lines) ---"
tail -30 "$LOG_FILE"
echo "--- End of output ---"

if [ "$FOUND" = true ]; then
  lumen_ok "Installer test PASSED — booted from disk to init"
  echo "  Time: ${WAITED}s"
  exit 0
fi

lumen_warn "Installer test FAILED — marker not found within ${TIMEOUT}s"
echo "  Log: ${LOG_FILE}"
exit 1
