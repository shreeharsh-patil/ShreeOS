#!/usr/bin/env bash
# installer/scripts/install-to-disk.sh — Install ShreeOS to a target disk
#
# Partitions (BIOS Boot + EFI ESP + Root ext4), formats, copies rootfs,
# installs GRUB (UEFI & BIOS), and configures first boot.
#
# Usage:
#   bash install-to-disk.sh /dev/sda              # interactive
#   bash install-to-disk.sh /dev/sda --yes         # non-interactive
#   bash install-to-disk.sh /dev/sda --yes \
#     --hostname=shreeos --root-password=changeme
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SHREEOS_ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$SHREEOS_ROOT_DIR/build.conf" 2>/dev/null || true
source "$SHREEOS_ROOT_DIR/scripts/common.sh" 2>/dev/null || {
  shreeos_step() { echo "==> $1"; }
  shreeos_log() { echo "  -> $1"; }
  shreeos_ok() { echo "  [OK] $1"; }
  shreeos_warn() { echo "  [WARN] $1"; }
  shreeos_die() { echo "  [ERROR] $1" >&2; exit 1; }
  shreeos_require_cmd() { for c in "$@"; do command -v "$c" >/dev/null 2>&1 || { echo "Missing $c" >&2; exit 1; }; done; }
  lumen_die() { shreeos_die "$@"; }
  lumen_require_cmd() { shreeos_require_cmd "$@"; }
}

if [ $# -lt 1 ]; then
  shreeos_die "Usage: install-to-disk.sh <disk-device> [--yes] [--hostname=...] [--root-password=...]"
fi

DISK="$1"
shift

ASSUME_YES=false
HOSTNAME="${DISTRO_CODENAME:-shreeos}"
ROOT_PASSWORD="shreeos"
USERNAME=""
USER_PASSWORD=""

for arg in "$@"; do
  case "$arg" in
    --yes) ASSUME_YES=true ;;
    --hostname=*) HOSTNAME="${arg#*=}" ;;
    --root-password=*) ROOT_PASSWORD="${arg#*=}" ;;
    --username=*) USERNAME="${arg#*=}" ;;
    --user-password=*) USER_PASSWORD="${arg#*=}" ;;
    --help|-h) echo "Usage: install-to-disk.sh <disk> [--yes] [--hostname=...] [--root-password=...] [--username=...] [--user-password=...]"; exit 0 ;;
  esac
done

shreeos_require_cmd sfdisk mkfs.ext4 grub-install

if [ ! -b "$DISK" ] && [ ! -f "$DISK" ]; then
  shreeos_die "${DISK} is not a valid block device or disk image."
fi

shreeos_step "Installing ${DISTRO_NAME:-ShreeOS} to ${DISK}"

# 1. Partition disk with safety checks and GPT scheme (BIOS + ESP + Root)
shreeos_log "Partitioning ${DISK}"
PARTITION_ARGS=()
if [ "$ASSUME_YES" = true ]; then
  PARTITION_ARGS+=("--yes")
fi
bash "${SCRIPT_DIR}/partition-disk.sh" "$DISK" "${PARTITION_ARGS[@]}"

# Wait for kernel / udev to settle partition table
sleep 1

# Detect partition devices (handle nvme/loop vs sdX)
if [ -b "${DISK}p3" ] || [ -f "${DISK}p3" ]; then
  PART_BIOS="${DISK}p1"
  PART_ESP="${DISK}p2"
  PART_ROOT="${DISK}p3"
elif [ -b "${DISK}3" ] || [ -f "${DISK}3" ]; then
  PART_BIOS="${DISK}1"
  PART_ESP="${DISK}2"
  PART_ROOT="${DISK}3"
else
  # Loop device / kpartx fallback
  PART_BIOS="${DISK}1"
  PART_ESP="${DISK}2"
  PART_ROOT="${DISK}3"
fi

# 2. Format ESP (FAT32) and Root (ext4)
shreeos_log "Formatting EFI System Partition (${PART_ESP})"
if command -v mkfs.vfat >/dev/null 2>&1; then
  mkfs.vfat -F32 -n "EFI" "$PART_ESP"
elif command -v mkfs.fat >/dev/null 2>&1; then
  mkfs.fat -F32 -n "EFI" "$PART_ESP"
else
  shreeos_warn "mkfs.vfat not found, skipping explicit ESP formatting"
fi

shreeos_log "Formatting root partition (${PART_ROOT})"
mkfs.ext4 -F -L "${DISTRO_ID:-shreeos}-root" "$PART_ROOT"

# 3. Mount target filesystems
shreeos_log "Mounting target filesystems"
TARGET=$(mktemp -d /tmp/shreeos-target-XXXXXX)
mount "$PART_ROOT" "$TARGET"

mkdir -p "${TARGET}/boot/efi"
if [ -b "$PART_ESP" ]; then
  mount "$PART_ESP" "${TARGET}/boot/efi" || true
fi

cleanup() {
  shreeos_log "Unmounting target filesystems..."
  umount "${TARGET}/boot/efi" 2>/dev/null || true
  umount "$TARGET" 2>/dev/null || true
  rmdir "$TARGET" 2>/dev/null || true
}
trap cleanup EXIT

# 4. Copy rootfs payload
shreeos_log "Copying root filesystem contents..."
STAGE_ROOT="${SHREEOS_STAGE_ROOT:-${SHREEOS_ROOT_DIR}/build/rootfs}"
ROOTFS_CPIO="${SHREEOS_BUILD_DIR:-${SHREEOS_ROOT_DIR}/build}/rootfs.cpio.gz"

if [ -d "${STAGE_ROOT}" ] && [ "$(ls -A "${STAGE_ROOT}" 2>/dev/null)" ]; then
  if command -v rsync >/dev/null 2>&1; then
    rsync -aHAX "${STAGE_ROOT}/" "$TARGET/"
  else
    cp -a "${STAGE_ROOT}/." "$TARGET/"
  fi
elif [ -f "${ROOTFS_CPIO}" ]; then
  gunzip -c "${ROOTFS_CPIO}" | (cd "$TARGET" && cpio -idm)
else
  shreeos_die "No rootfs found at ${STAGE_ROOT} or ${ROOTFS_CPIO}"
fi

# 5. Configure first-boot
shreeos_log "Configuring system identity and credentials..."
mkdir -p "${TARGET}/etc"
echo "${HOSTNAME}" > "${TARGET}/etc/hostname"

if [ -f "${TARGET}/etc/shadow" ] && command -v mkpasswd >/dev/null 2>&1; then
  SALT="$(head -c 16 /dev/urandom | base64 | head -c 16)"
  HASHED_PW="$(echo "$ROOT_PASSWORD" | mkpasswd -m sha-512 -S "$SALT" 2>/dev/null || echo "")"
  if [ -n "$HASHED_PW" ]; then
    sed -i "s|^root:[^:]*:|root:${HASHED_PW}:|" "${TARGET}/etc/shadow"
  fi
fi

if [ -n "${USERNAME}" ] && [ -f "${SCRIPT_DIR}/configure-user.sh" ]; then
  bash "${SCRIPT_DIR}/configure-user.sh" "$TARGET" "$USERNAME" "${USER_PASSWORD:-$ROOT_PASSWORD}"
fi

# 6. Install Bootloader (UEFI + BIOS)
shreeos_log "Installing GRUB bootloader to ${DISK}"
bash "${SHREEOS_ROOT_DIR}/bootloader/scripts/install-grub-disk.sh" "$TARGET" "$DISK"

# 7. Generate fstab with UUIDs
ROOT_UUID=$(blkid -s UUID -o value "$PART_ROOT" 2>/dev/null || echo "")
ESP_UUID=$(blkid -s UUID -o value "$PART_ESP" 2>/dev/null || echo "")

cat > "${TARGET}/etc/fstab" <<FSTAB
# /etc/fstab — Static file system information
$( [ -n "$ROOT_UUID" ] && echo "UUID=${ROOT_UUID} / ext4 defaults 0 1" || echo "${PART_ROOT} / ext4 defaults 0 1" )
$( [ -n "$ESP_UUID" ] && echo "UUID=${ESP_UUID} /boot/efi vfat umask=0077 0 2" || echo "# ${PART_ESP} /boot/efi vfat umask=0077 0 2" )
proc /proc proc defaults 0 0
sysfs /sys sysfs defaults 0 0
devtmpfs /dev devtmpfs defaults 0 0
devpts /dev/pts devpts gid=5,mode=620 0 0
tmpfs /tmp tmpfs defaults,nosuid,nodev 0 0
FSTAB

sync
shreeos_ok "${DISTRO_NAME:-ShreeOS} successfully installed to ${DISK}"
echo ""
echo "Installation complete. Boot in QEMU with:"
echo "  qemu-system-x86_64 -drive file=${DISK},format=raw -m 512M"
echo ""
