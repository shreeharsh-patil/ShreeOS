#!/usr/bin/env bash
# installer/tests/test-install.sh — Non-interactive installer test
#
# Creates an isolated raw disk image, lets the installer safely allocate its
# own loop device, then boots the installed disk in QEMU.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LUMEN_ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$LUMEN_ROOT_DIR/build.conf"
source "$LUMEN_ROOT_DIR/scripts/common.sh"

QEMU_BIN="${QEMU_BIN:-qemu-system-x86_64}"
DISK_IMAGE="${DISK_IMAGE:-/tmp/shreeos-install-test.img}"
DISK_SIZE="${DISK_SIZE:-4G}"
MARKER_STRING="${MARKER_STRING:-ShreeOS init: critical services ready}"
ROOT_MARKER_STRING="${ROOT_MARKER_STRING:-ShreeOS init: installed ext4 root mounted}"
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
SUDO=()
if [ "$(id -u)" -ne 0 ]; then
  command -v sudo >/dev/null 2>&1 || lumen_die "sudo is required for loop-device installer testing"
  sudo -n true >/dev/null 2>&1 || lumen_die "passwordless sudo is required for non-interactive loop-device installer testing"
  SUDO=(sudo -n)
fi
if ! command -v mkfs.vfat >/dev/null 2>&1 && ! command -v mkfs.fat >/dev/null 2>&1; then
  lumen_die "mkfs.vfat or mkfs.fat is required for the default UEFI installer path"
fi

LOG_FILE=""
CREDS_FILE=""
QEMU_PID=""
TEST_SUCCEEDED=false
DISK_CREATED=false

cleanup() {
  if [ -n "$QEMU_PID" ] && kill -0 "$QEMU_PID" 2>/dev/null; then
    kill "$QEMU_PID" 2>/dev/null || true
    wait "$QEMU_PID" 2>/dev/null || true
  fi
  [ -n "$CREDS_FILE" ] && rm -f "$CREDS_FILE"
  if [ "$KEEP" = false ]; then
    if [ "$TEST_SUCCEEDED" = true ]; then
      [ -n "$LOG_FILE" ] && rm -f "$LOG_FILE"
    fi
    # A failure during preflight must not delete an existing user-supplied image.
    if [ "$DISK_CREATED" = true ]; then
      rm -f -- "$DISK_IMAGE"
    fi
  fi
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

lumen_step "Installer test: install to isolated virtual disk"

# Never erase a pre-existing file supplied via --image (including symlinks).
# This is a test fixture, not permission to overwrite an arbitrary disk image.
if [ -e "$DISK_IMAGE" ] || [ -L "$DISK_IMAGE" ]; then
  lumen_die "Refusing to overwrite existing installer test image: $DISK_IMAGE"
fi
qemu-img create -f raw "$DISK_IMAGE" "$DISK_SIZE" >/dev/null
DISK_CREATED=true
lumen_ok "Disk image created: ${DISK_IMAGE}"

CREDS_FILE=$(mktemp /tmp/shreeos-install-creds-XXXXXX)
chmod 600 "$CREDS_FILE"
printf '%s\n' "test-root-password" > "$CREDS_FILE"

# Passing an already-attached /dev/loopN is forbidden by install-to-disk.sh;
# it owns loop-device allocation for regular disk images and detaches on exit.
"${SUDO[@]}" bash "${LUMEN_ROOT_DIR}/installer/scripts/install-to-disk.sh" "$DISK_IMAGE" --yes \
  --hostname="shreeos-test" \
  --timezone="UTC" \
  --credentials-file="$CREDS_FILE"

rm -f "$CREDS_FILE"
CREDS_FILE=""

sync

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
  if grep -Fq "$MARKER_STRING" "$LOG_FILE" 2>/dev/null &&
     grep -Fq "$ROOT_MARKER_STRING" "$LOG_FILE" 2>/dev/null; then
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
  lumen_ok "Installer test PASSED — booted persistent ext4 root to init"
  echo "  Time: ${WAITED}s"
  TEST_SUCCEEDED=true
  exit 0
fi

lumen_warn "Installer test FAILED — persistent root/init markers missing after ${TIMEOUT}s"
echo "  Log: ${LOG_FILE}"
exit 1
