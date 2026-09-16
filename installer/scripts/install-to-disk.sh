#!/usr/bin/env bash
# installer/scripts/install-to-disk.sh — Install ShreeOS to a target disk
#
# Partitions, formats, copies rootfs, installs GRUB, configures first boot.
#
# Usage:
#   bash install-to-disk.sh /dev/sda              # interactive
#   bash install-to-disk.sh /dev/sda --yes         # non-interactive
#   bash install-to-disk.sh /dev/sda --yes \
#     --hostname=shreeos --root-password=changeme
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LUMEN_ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$LUMEN_ROOT_DIR/build.conf"
source "$LUMEN_ROOT_DIR/scripts/common.sh"

if [ $# -lt 1 ]; then
  lumen_die "Usage: install-to-disk.sh <disk-device> [--yes] [--hostname=...] [--root-password=...]"
fi

DISK="$1"
shift

ASSUME_YES=false
HOSTNAME="${DISTRO_CODENAME}"
ROOT_PASSWORD="shreeos"

for arg in "$@"; do
  case "$arg" in
    --yes) ASSUME_YES=true ;;
    --hostname=*) HOSTNAME="${arg#*=}" ;;
    --root-password=*) ROOT_PASSWORD="${arg#*=}" ;;
    --help|-h) echo "Usage: install-to-disk.sh <disk> [--yes] [--hostname=...] [--root-password=...]"; exit 0 ;;
  esac
done

lumen_require_cmd sfdisk mkfs.ext4 grub-install

if [ ! -b "$DISK" ] && [ "$ASSUME_YES" = false ]; then
  lumen_warn "${DISK} is not a block device. Are you sure?"
  read -r -p "Continue? [y/N] " REPLY
  if [ "$REPLY" != "y" ] && [ "$REPLY" != "Y" ]; then
    lumen_die "Aborted by user"
  fi
fi

lumen_step "Installing ${DISTRO_NAME} to ${DISK}"

# 1. Partition: single ext4 root partition
lumen_log "Partitioning ${DISK}"
sfdisk "$DISK" <<EOF
label: gpt
size=512M, type=21686148-6449-6E6F-744E-656564454649, name="BIOS"
size=+, type=0FC63DAF-8483-4772-8E79-3D69D8477DE4, name="root"
EOF

# Wait for kernel to re-read partition table
sleep 1
PART_ROOT="${DISK}2"
[ -b "${DISK}p2" ] && PART_ROOT="${DISK}p2"

# 2. Format
lumen_log "Formatting ${PART_ROOT}"
mkfs.ext4 -F -L "${DISTRO_ID}-root" "$PART_ROOT"

# 3. Mount and copy rootfs
lumen_log "Copying root filesystem"
TARGET=$(mktemp -d)
mount "$PART_ROOT" "$TARGET"

if [ -d "${LUMEN_STAGE_ROOT}" ]; then
  rsync -aHAX "${LUMEN_STAGE_ROOT}/" "$TARGET/"
elif [ -f "${LUMEN_BUILD_DIR}/rootfs.cpio.gz" ]; then
  gunzip -c "${LUMEN_BUILD_DIR}/rootfs.cpio.gz" | cpio -idm -D "$TARGET"
else
  lumen_die "No rootfs found at ${LUMEN_STAGE_ROOT} or ${LUMEN_BUILD_DIR}/rootfs.cpio.gz"
fi

# 4. Configure first-boot
echo "${HOSTNAME}" > "${TARGET}/etc/hostname"
sed -i "s/root:[^:]*:/root:$(echo "$ROOT_PASSWORD" | mkpasswd -m sha-512 -S "$(head -c 16 /dev/urandom | base64 | head -c 16)"):/" "${TARGET}/etc/shadow" 2>/dev/null || true

# 5. Install GRUB
lumen_log "Installing GRUB"
bash "${LUMEN_ROOT_DIR}/bootloader/scripts/install-grub.sh" "$TARGET"

# 6. Generate fstab
ROOT_UUID=$(blkid -s UUID -o value "$PART_ROOT" 2>/dev/null || echo "")
cat > "${TARGET}/etc/fstab" <<FSTAB
# /etc/fstab
UUID=${ROOT_UUID} / ext4 defaults 0 1
proc /proc proc defaults 0 0
sysfs /sys sysfs defaults 0 0
devtmpfs /dev devtmpfs defaults 0 0
FSTAB

# 7. Cleanup
sync
umount "$TARGET"
rmdir "$TARGET"

lumen_ok "${DISTRO_NAME} installed to ${DISK}"
echo ""
echo "You can now boot the target device:"
echo "  qemu-system-x86_64 -drive file=${DISK},format=raw -m 256M -nographic"
echo ""
