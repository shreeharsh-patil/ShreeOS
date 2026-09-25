#!/usr/bin/env bash
# QEMU boot test for an installed ShreeOS disk image.
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$PROJECT_ROOT/build.conf"
source "$PROJECT_ROOT/scripts/common.sh"

QEMU_BIN="${QEMU_BIN:-qemu-system-x86_64}"
MARKER_STRING="${MARKER_STRING:-ShreeOS init: critical services ready}"
ROOT_MARKER_STRING="${ROOT_MARKER_STRING:-ShreeOS init: installed ext4 root mounted}"
TIMEOUT="${TIMEOUT:-60}"
MEMORY="${MEMORY:-256M}"
REQUIRE_ARTIFACTS="${REQUIRE_ARTIFACTS:-0}"
DISK_IMAGE="${1:-}"
TEMP_DISK=""
SUDO=()

if ! command -v "$QEMU_BIN" >/dev/null 2>&1; then
  if [ "$REQUIRE_ARTIFACTS" = "1" ]; then shreeos_die "QEMU not found: $QEMU_BIN"; fi
  shreeos_warn "QEMU not found: $QEMU_BIN"; exit 77
fi

if [ -z "$DISK_IMAGE" ]; then
  if [ -s "$PROJECT_ROOT/build/installed-disk.img" ]; then
    DISK_IMAGE="$PROJECT_ROOT/build/installed-disk.img"
  else
    if [ ! -s "$PROJECT_ROOT/build/initramfs.cpio.gz" ] || ! command -v sfdisk >/dev/null 2>&1; then
      if [ "$REQUIRE_ARTIFACTS" = "1" ]; then
        shreeos_die "Cannot create installed-disk test: rootfs or sfdisk is unavailable"
      fi
      shreeos_warn "Installed-disk prerequisites unavailable"
      exit 77
    fi

    TEMP_DISK="$(mktemp /tmp/shreeos-test-disk-XXXXXX.img)"
    truncate -s 4G "$TEMP_DISK"
    DISK_IMAGE="$TEMP_DISK"
    CREDS_FILE="$(mktemp /tmp/shreeos-test-creds-XXXXXX)"
    cleanup_files() { rm -f "$TEMP_DISK" "$CREDS_FILE"; }
    trap cleanup_files EXIT
    trap 'exit 130' INT
    trap 'exit 143' TERM
    chmod 600 "$CREDS_FILE"
    printf 'testrootpass\ntestuserpass\n' > "$CREDS_FILE"
    if [ "$(id -u)" -eq 0 ]; then
      bash "$PROJECT_ROOT/installer/scripts/install-to-disk.sh" "$DISK_IMAGE" --yes --username=shree --credentials-file="$CREDS_FILE"
    elif command -v sudo >/dev/null 2>&1 && sudo -n true >/dev/null 2>&1; then
      SUDO=(sudo -n -E)
      "${SUDO[@]}" bash "$PROJECT_ROOT/installer/scripts/install-to-disk.sh" "$DISK_IMAGE" --yes --username=shree --credentials-file="$CREDS_FILE"
    elif [ "$REQUIRE_ARTIFACTS" = "1" ]; then
      shreeos_die "passwordless sudo/root privileges are required for the installed-disk test"
    else
      shreeos_warn "non-interactive sudo/root privileges unavailable; skipping installed-disk test"
      exit 77
    fi
  fi
fi

[ -s "$DISK_IMAGE" ] || shreeos_die "Disk image not found or empty: $DISK_IMAGE"
shreeos_step "Booting disk image: $DISK_IMAGE"

# Persist serial logs under build/logs so CI artifacts can capture boot failures.
LOG_DIR="${PROJECT_ROOT}/build/logs"
mkdir -p "$LOG_DIR"
LOG_FILE="$(mktemp "${LOG_DIR}/qemu-installed-disk.XXXXXX.log")"
QEMU_PID=""
cleanup_qemu() {
  if [ -n "$QEMU_PID" ] && kill -0 "$QEMU_PID" 2>/dev/null; then
    kill "$QEMU_PID" 2>/dev/null || true
    wait "$QEMU_PID" 2>/dev/null || true
  fi
}
cleanup_all() {
  cleanup_qemu
  [ -n "$TEMP_DISK" ] && rm -f "$TEMP_DISK"
  [ -n "${CREDS_FILE:-}" ] && rm -f "$CREDS_FILE"
}
trap cleanup_all EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

"$QEMU_BIN"   -drive file="$DISK_IMAGE",format=raw   -m "$MEMORY"   -nographic   -no-reboot   > "$LOG_FILE" 2>&1 &
QEMU_PID=$!

WAITED=0
FOUND=false
while [ "$WAITED" -lt "$TIMEOUT" ]; do
  sleep 1
  WAITED=$((WAITED + 1))
  if grep -Fq "$MARKER_STRING" "$LOG_FILE" 2>/dev/null &&
     grep -Fq "$ROOT_MARKER_STRING" "$LOG_FILE" 2>/dev/null; then FOUND=true; break; fi
  kill -0 "$QEMU_PID" 2>/dev/null || break
done
cleanup_qemu
QEMU_PID=""

if [ "$FOUND" = true ]; then
  shreeos_ok "Disk boot test PASSED — installed ext4 root and init markers found after ${WAITED}s"
  rm -f "$LOG_FILE"
  exit 0
fi
shreeos_warn "Disk boot test FAILED — installed ext4 root/init markers not both found"
echo "Log: $LOG_FILE"
exit 1
