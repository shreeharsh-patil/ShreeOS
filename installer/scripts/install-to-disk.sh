#!/usr/bin/env bash
# installer/scripts/install-to-disk.sh — Install ShreeOS to a target disk
#
# Supports real block devices and disk images via losetup -Pf.
# Partitions (BIOS Boot + EFI ESP + Root ext4), formats, copies rootfs,
# installs GRUB (UEFI & BIOS), and configures first boot with secure credentials.
#
# Usage:
#   bash install-to-disk.sh /dev/sda --yes --hostname=shreeos --timezone=UTC --credentials-file=/tmp/creds.txt
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

for arg in "$@"; do
  if [ "$arg" = "--help" ] || [ "$arg" = "-h" ]; then
    echo "Usage: install-to-disk.sh <disk-device> [--yes] [--hostname=...] [--timezone=...] [--credentials-file=...] [--username=...] [--boot-mode=both|uefi|bios]"
    exit 0
  fi
done

if [ $# -lt 1 ]; then
  shreeos_die "Usage: install-to-disk.sh <disk-device> [--yes] [--hostname=...] [--timezone=...] [--credentials-file=...] [--username=...]"
fi

DISK="$1"
shift

ASSUME_YES=false
HOSTNAME="${DISTRO_CODENAME:-shreeos}"
TIMEZONE="UTC"
CREDS_FILE=""
CREDS_FILE_OWNED=false
USERNAME=""
BOOT_MODE="both"
HASHED_ROOT_PW=""
HASHED_USER_PW=""

for arg in "$@"; do
  case "$arg" in
    --yes) ASSUME_YES=true ;;
    --hostname=*) HOSTNAME="${arg#*=}" ;;
    --timezone=*) TIMEZONE="${arg#*=}" ;;
    --credentials-file=*) CREDS_FILE="${arg#*=}" ;;
    --username=*) USERNAME="${arg#*=}" ;;
    --boot-mode=*) BOOT_MODE="${arg#*=}" ;;
    --help|-h) echo "Usage: install-to-disk.sh <disk> [--yes] [--hostname=...] [--timezone=...] [--credentials-file=...] [--username=...]"; exit 0 ;;
    *) shreeos_die "Unknown installer option: ${arg}" ;;
  esac
done

TARGET=""
ESP_MOUNT=""
LOOP_DEV=""
USER_TMP_CRED=""

cleanup() {
  if [ -n "$TARGET" ] && [ -d "$TARGET" ]; then
    shreeos_log "Unmounting target filesystems..."
    umount "$TARGET" 2>/dev/null || true
    rmdir "$TARGET" 2>/dev/null || true
  fi
  if [ -n "$ESP_MOUNT" ] && [ -d "$ESP_MOUNT" ]; then
    umount "$ESP_MOUNT" 2>/dev/null || true
    rmdir "$ESP_MOUNT" 2>/dev/null || true
  fi
  if [ -n "$LOOP_DEV" ]; then
    shreeos_log "Detaching loop device ${LOOP_DEV}..."
    losetup -d "$LOOP_DEV" 2>/dev/null || true
  fi
  if [ -n "${USER_TMP_CRED:-}" ] && [ -f "${USER_TMP_CRED}" ]; then
    rm -f "${USER_TMP_CRED}"
  fi
  if [ "${CREDS_FILE_OWNED:-false}" = true ] && [ -n "${CREDS_FILE:-}" ] && [ -f "${CREDS_FILE}" ]; then
    rm -f "${CREDS_FILE}"
  fi
}
trap cleanup EXIT INT TERM

# Validate hostname strictly: ^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?$
if ! [[ "$HOSTNAME" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?$ ]]; then
  shreeos_die "Invalid hostname '${HOSTNAME}'. Must match RFC 1123 format."
fi

case "$BOOT_MODE" in
  bios|uefi|both) ;;
  *) shreeos_die "Invalid --boot-mode '${BOOT_MODE}'; expected bios, uefi, or both." ;;
esac

# Validate timezone: reject .. and traversal
if [[ "$TIMEZONE" == *".."* ]] || [[ "$TIMEZONE" == /* ]] || ! [[ "$TIMEZONE" =~ ^[A-Za-z0-9_+-]+(/[A-Za-z0-9_+-]+)*$ ]]; then
  shreeos_die "Invalid timezone specification '${TIMEZONE}'."
fi

if [ -n "$USERNAME" ]; then
  if ! [[ "$USERNAME" =~ ^[a-z_][a-z0-9_-]{0,31}$ ]]; then
    shreeos_die "Invalid username '${USERNAME}'. Must match ^[a-z_][a-z0-9_-]{0,31}\$."
  fi
  case "$USERNAME" in
    root|daemon|bin|sys|sync|games|man|lp|mail|news|uucp|proxy|www-data|backup|list|irc|_apt|nobody|systemd-*|messagebus|sshd|shree-hardware)
      shreeos_die "Reserved system username '${USERNAME}' cannot be used."
      ;;
  esac
  if [ -z "$CREDS_FILE" ]; then
    shreeos_die "A username requires a credentials file with a non-empty user password."
  fi
fi

hash_password() {
  local password="$1"
  local salt
  salt="$(od -An -N8 -tx1 /dev/urandom | tr -d ' \n')"
  if ! [[ "$salt" =~ ^[a-zA-Z0-9]{16}$ ]]; then
    shreeos_die "Failed to generate a password salt."
  fi
  local hashed
  hashed="$(printf '%s' "$password" | openssl passwd -6 -salt "$salt" -stdin 2>/dev/null || true)"
  password=""
  if ! [[ "$hashed" =~ ^\$6\$[a-zA-Z0-9]{1,16}\$[./A-Za-z0-9]+$ ]]; then
    shreeos_die "Failed to securely hash the supplied password with SHA-512."
  fi
  printf '%s\n' "$hashed"
}

if [ -n "$CREDS_FILE" ]; then
  shreeos_require_cmd openssl
  if [ ! -f "$CREDS_FILE" ] || [ -L "$CREDS_FILE" ]; then
    shreeos_die "Credentials file must be a regular, non-symlink file."
  fi
  CREDS_OWNER="$(stat -c '%u' "$CREDS_FILE")"
  EXPECTED_CREDS_OWNER="${SUDO_UID:-$(id -u)}"
  if [ "$CREDS_OWNER" != "$EXPECTED_CREDS_OWNER" ] || [ "$(stat -c '%a' "$CREDS_FILE")" != "600" ]; then
    shreeos_die "Credentials file must be owned by the invoking user (including the original sudo user) and have mode exactly 0600."
  fi
  CREDS_LINE_COUNT=$(awk 'END { print NR }' "$CREDS_FILE")
  if [ "$CREDS_LINE_COUNT" -lt 1 ] || [ "$CREDS_LINE_COUNT" -gt 2 ]; then
    shreeos_die "Credentials file must contain one root password line and one optional user password line."
  fi
  CREDS_ROOT_CHECK=$(sed -n '1p' "$CREDS_FILE")
  if [ -z "$CREDS_ROOT_CHECK" ]; then
    CREDS_ROOT_CHECK=""; unset CREDS_ROOT_CHECK
    shreeos_die "Credentials file has an empty root password."
  fi
  CREDS_ROOT_CHECK=""; unset CREDS_ROOT_CHECK
  if [ "$CREDS_LINE_COUNT" -eq 2 ]; then
    if [ -z "$USERNAME" ]; then
      shreeos_die "A user password was supplied without --username."
    fi
    CREDS_USER_CHECK=$(sed -n '2p' "$CREDS_FILE")
    if [ -z "$CREDS_USER_CHECK" ]; then
      CREDS_USER_CHECK=""; unset CREDS_USER_CHECK
      shreeos_die "Credentials file has an empty user password."
    fi
    CREDS_USER_CHECK=""; unset CREDS_USER_CHECK
  elif [ -n "$USERNAME" ]; then
    shreeos_die "A username requires a second, non-empty user password line."
  fi

  ROOT_PW="$(sed -n '1p' "$CREDS_FILE")"
  HASHED_ROOT_PW="$(hash_password "$ROOT_PW")"
  ROOT_PW=""
  unset ROOT_PW
  if [ -n "$USERNAME" ]; then
    USER_PW="$(sed -n '2p' "$CREDS_FILE")"
    HASHED_USER_PW="$(hash_password "$USER_PW")"
    USER_PW=""
    unset USER_PW
  fi
fi

if [ -n "$USERNAME" ] && [ ! -f "${SCRIPT_DIR}/configure-user.sh" ]; then
  shreeos_die "Username configuration helper is missing: ${SCRIPT_DIR}/configure-user.sh."
fi

# If UEFI requested, require FAT formatting utility
if [ "$BOOT_MODE" = "both" ] || [ "$BOOT_MODE" = "uefi" ]; then
  if ! command -v mkfs.vfat >/dev/null 2>&1 && ! command -v mkfs.fat >/dev/null 2>&1; then
    shreeos_die "FATAL: UEFI installation requested but neither mkfs.vfat nor mkfs.fat is installed."
  fi
fi

if [ ! -b "$DISK" ] && [ ! -f "$DISK" ]; then
  shreeos_die "${DISK} is not a valid block device or disk image."
fi

# Complete every non-destructive preflight before creating a loop device,
# partitioning, formatting, or mounting the requested disk.
STAGE_ROOT="${SHREEOS_STAGE_ROOT:-${SHREEOS_ROOT_DIR}/build/rootfs}"
if [ -n "$USERNAME" ] && [ -f "${STAGE_ROOT}/etc/passwd" ] && grep -q "^${USERNAME}:" "${STAGE_ROOT}/etc/passwd"; then
  shreeos_die "Account '${USERNAME}' already exists in the staged root filesystem."
fi
ROOTFS_CPIO="${SHREEOS_BUILD_DIR:-${SHREEOS_ROOT_DIR}/build}/initramfs.cpio.gz"
BZIMAGE="${SHREEOS_BUILD_DIR:-${SHREEOS_ROOT_DIR}/build}/build-kernel/arch/x86/boot/bzImage"
if [ -d "${STAGE_ROOT}" ] && [ "$(ls -A "${STAGE_ROOT}" 2>/dev/null)" ]; then
  if [ ! -f "${STAGE_ROOT}/usr/share/zoneinfo/${TIMEZONE}" ]; then
    shreeos_die "Timezone '${TIMEZONE}' is not present in the staged root filesystem."
  fi
elif [ ! -s "${ROOTFS_CPIO}" ]; then
  shreeos_die "No usable rootfs found at ${STAGE_ROOT} or ${ROOTFS_CPIO}."
fi
if [ ! -s "${BZIMAGE}" ]; then shreeos_die "Missing kernel artifact: ${BZIMAGE}"; fi
if [ ! -s "${ROOTFS_CPIO}" ]; then shreeos_die "Missing initramfs artifact: ${ROOTFS_CPIO}"; fi
shreeos_require_cmd sfdisk losetup mkfs.ext4 mount umount grub-install blkid cpio gzip chown du lsblk realpath stat
if [ ! -d "${STAGE_ROOT}" ] || [ ! "$(ls -A "${STAGE_ROOT}" 2>/dev/null)" ]; then
  TIMEZONE_ARCHIVE_LIST="$(gzip -dc "${ROOTFS_CPIO}" | cpio -t --quiet)"
  if ! grep -Fxq "./usr/share/zoneinfo/${TIMEZONE}" <<<"$TIMEZONE_ARCHIVE_LIST" && \
     ! grep -Fxq "usr/share/zoneinfo/${TIMEZONE}" <<<"$TIMEZONE_ARCHIVE_LIST"; then
    shreeos_die "Timezone '${TIMEZONE}' is not present in the initramfs."
  fi
  unset TIMEZONE_ARCHIVE_LIST
fi

if ! CANONICAL_DISK="$(realpath -- "$DISK" 2>/dev/null)"; then
  shreeos_die "Unable to resolve target path safely: ${DISK}"
fi
if [ -f "$CANONICAL_DISK" ] && [ ! -b "$CANONICAL_DISK" ]; then
  if ! EXISTING_LOOPS=$(losetup -j "$CANONICAL_DISK" 2>/dev/null); then
    shreeos_die "Unable to inspect existing loop associations for ${DISK}; refusing to attach it."
  fi
  if [ -n "$EXISTING_LOOPS" ]; then
    shreeos_die "Target disk image ${DISK} already has a loop association; refusing to reuse overlapping media."
  fi
elif [ -b "$CANONICAL_DISK" ] && [[ "$CANONICAL_DISK" =~ ^/dev/loop[0-9]+$ ]]; then
  if ! LOOP_BACKING="$(losetup -n -O BACK-FILE -- "$CANONICAL_DISK" 2>/dev/null)"; then
    shreeos_die "Unable to verify whether ${DISK} is an attached loop device."
  fi
  if [ -n "$LOOP_BACKING" ]; then
    shreeos_die "Attached loop device ${DISK} is not accepted; provide its backing disk image instead."
  fi
fi
DISK="$CANONICAL_DISK"

if [ -d "${STAGE_ROOT}" ] && [ "$(ls -A "${STAGE_ROOT}" 2>/dev/null)" ]; then
  if ! ROOTFS_PAYLOAD_KB=$(du -sk -- "${STAGE_ROOT}" | awk '{print $1}'); then
    shreeos_die "Unable to determine the staged rootfs payload size."
  fi
  if ! [[ "$ROOTFS_PAYLOAD_KB" =~ ^[0-9]+$ ]] || [ "$ROOTFS_PAYLOAD_KB" -le 0 ]; then
    shreeos_die "Unable to determine a valid staged rootfs payload size."
  fi
  ROOTFS_PAYLOAD_BYTES=$((ROOTFS_PAYLOAD_KB * 1024))
else
  if ! ROOTFS_PAYLOAD_BYTES=$(gzip -dc "${ROOTFS_CPIO}" | wc -c | tr -d '[:space:]'); then
    shreeos_die "Unable to determine the initramfs payload size."
  fi
fi
if ! [[ "$ROOTFS_PAYLOAD_BYTES" =~ ^[0-9]+$ ]] || [ "$ROOTFS_PAYLOAD_BYTES" -le 0 ]; then
  shreeos_die "Unable to determine a valid rootfs payload size."
fi
BZIMAGE_BYTES=$(stat -c '%s' -- "$BZIMAGE" 2>/dev/null || echo "")
ROOTFS_CPIO_BYTES=$(stat -c '%s' -- "$ROOTFS_CPIO" 2>/dev/null || echo "")
if ! [[ "$BZIMAGE_BYTES" =~ ^[0-9]+$ ]] || ! [[ "$ROOTFS_CPIO_BYTES" =~ ^[0-9]+$ ]]; then
  shreeos_die "Unable to determine the installed boot payload size."
fi
ROOTFS_PAYLOAD_BYTES=$((ROOTFS_PAYLOAD_BYTES + BZIMAGE_BYTES + ROOTFS_CPIO_BYTES))

ESP_SIZE_BYTES=$((512 * 1024 * 1024))
SAFETY_MARGIN_BYTES=$((256 * 1024 * 1024))
LAYOUT_OVERHEAD_BYTES=$((4 * 1024 * 1024))
MIN_TARGET_BYTES=$((ESP_SIZE_BYTES + ROOTFS_PAYLOAD_BYTES + SAFETY_MARGIN_BYTES + LAYOUT_OVERHEAD_BYTES))

if [ -f "$DISK" ]; then
  TARGET_BYTES=$(stat -c '%s' -- "$DISK" 2>/dev/null || echo "")
else
  TARGET_BYTES=""
  if command -v blockdev >/dev/null 2>&1; then
    TARGET_BYTES=$(blockdev --getsize64 "$DISK" 2>/dev/null || echo "")
  fi
  if ! [[ "$TARGET_BYTES" =~ ^[0-9]+$ ]]; then
    TARGET_BYTES=$(lsblk -bndo SIZE -- "$DISK" 2>/dev/null | awk 'NR == 1 {print $1}')
  fi
fi
if ! [[ "$TARGET_BYTES" =~ ^[0-9]+$ ]] || [ "$TARGET_BYTES" -le 0 ]; then
  shreeos_die "Unable to determine the target media size for ${DISK}."
fi
if [ "$TARGET_BYTES" -lt "$MIN_TARGET_BYTES" ]; then
  shreeos_die "Target media is too small: ${TARGET_BYTES} bytes; at least ${MIN_TARGET_BYTES} bytes are required for the 512MiB ESP, rootfs payload, and safety margin."
fi

if [ -z "$CREDS_FILE" ]; then
  shreeos_die "A credentials file is required for installation; use --credentials-file with a 0600 file containing the root password and optional user password."
fi

if [ "$(id -u)" -ne 0 ]; then
  shreeos_die "Installation requires root privileges. Re-run with sudo: sudo bash installer/scripts/install-to-disk.sh ..."
fi

WORKING_DISK="$DISK"

# If disk is regular file, attach loop device with partition scanning
if [ -f "$DISK" ] && [ ! -b "$DISK" ]; then
  shreeos_log "Attaching raw disk image ${DISK} via loop device (with partition scanning)..."
  LOOP_DEV=$(losetup --nooverlap -Pf --show "$CANONICAL_DISK")
  WORKING_DISK="$LOOP_DEV"
fi

shreeos_step "Installing ${DISTRO_NAME:-ShreeOS} to ${WORKING_DISK}"

# 1. Partition disk with safety checks and GPT scheme
shreeos_log "Partitioning ${WORKING_DISK}"
PARTITION_ARGS=()
if [ "$ASSUME_YES" = true ]; then
  PARTITION_ARGS+=("--yes")
fi
bash "${SCRIPT_DIR}/partition-disk.sh" "$WORKING_DISK" "${PARTITION_ARGS[@]}"

# Settle partition table
sleep 1

# Detect partition devices (NVMe, MMC, VirtIO, SATA, Loop)
get_partition_dev() {
  local disk="$1"
  local num="$2"
  if [ -b "${disk}p${num}" ] || [ -f "${disk}p${num}" ]; then
    echo "${disk}p${num}"
  elif [ -b "${disk}${num}" ] || [ -f "${disk}${num}" ]; then
    echo "${disk}${num}"
  elif [[ "$disk" =~ [0-9]$ ]]; then
    echo "${disk}p${num}"
  else
    echo "${disk}${num}"
  fi
}

PART_BIOS=$(get_partition_dev "$WORKING_DISK" 1)
PART_ESP=$(get_partition_dev "$WORKING_DISK" 2)
PART_ROOT=$(get_partition_dev "$WORKING_DISK" 3)

verify_child_partition() {
  local partition="$1"
  local parent
  parent="$(lsblk -ndo PKNAME -- "$partition" 2>/dev/null | awk 'NR == 1 {print $1}')"
  if [ -z "$parent" ] || [ "$parent" != "$(basename -- "$WORKING_DISK")" ]; then
    shreeos_die "Partition ${partition} is not a child of ${WORKING_DISK}."
  fi
}
verify_child_partition "$PART_ROOT"
if [ "$BOOT_MODE" != "bios" ]; then
  verify_child_partition "$PART_ESP"
fi

# Partition nodes can appear asynchronously after sfdisk/loop partition scans.
# Ask the kernel/udev to settle, then fail explicitly instead of racing mkfs.
if command -v partprobe >/dev/null 2>&1; then
  partprobe "$WORKING_DISK" >/dev/null 2>&1 || true
fi
if command -v udevadm >/dev/null 2>&1; then
  udevadm settle --timeout=10 >/dev/null 2>&1 || true
fi
for _attempt in {1..20}; do
  if [ -b "$PART_ROOT" ] && { [ "$BOOT_MODE" = "bios" ] || [ -b "$PART_ESP" ]; }; then
    break
  fi
  sleep 0.25
done

[ -b "$PART_ROOT" ] || shreeos_die "Root partition device did not appear: ${PART_ROOT}"
if [ "$BOOT_MODE" != "bios" ]; then
  [ -b "$PART_ESP" ] || shreeos_die "EFI partition device did not appear: ${PART_ESP}"
fi

shreeos_log "Detected partition devices (BIOS: ${PART_BIOS}, ESP: ${PART_ESP}, Root: ${PART_ROOT})"

# 2. Format ESP (FAT32) and Root (ext4)
if [ "$BOOT_MODE" = "both" ] || [ "$BOOT_MODE" = "uefi" ]; then
  shreeos_log "Formatting EFI System Partition (${PART_ESP})"
  if command -v mkfs.vfat >/dev/null 2>&1; then
    mkfs.vfat -F32 -n "EFI" "$PART_ESP"
  else
    mkfs.fat -F32 -n "EFI" "$PART_ESP"
  fi
fi

shreeos_log "Formatting root partition (${PART_ROOT})"
mkfs.ext4 -F -L "${DISTRO_ID:-shreeos}-root" "$PART_ROOT"

# 3. Mount target filesystems
shreeos_log "Mounting target filesystems"
TARGET=$(mktemp -d /tmp/shreeos-target-XXXXXX)
mount "$PART_ROOT" "$TARGET"
if [ "$BOOT_MODE" != "bios" ]; then
  ESP_MOUNT=$(mktemp -d /tmp/shreeos-esp-XXXXXX)
  mount "$PART_ESP" "$ESP_MOUNT"
fi

# 4. Copy rootfs payload
shreeos_log "Copying root filesystem contents..."
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

# The installed boot configuration is independent of the copied rootfs tree.
# Install the exact validated build artifacts before GRUB is invoked.
[ ! -L "${TARGET}/boot" ] || shreeos_die "Unsafe /boot symlink in staged rootfs."
mkdir -p "${TARGET}/boot"
cp "${BZIMAGE}" "${TARGET}/boot/bzImage"
cp "${ROOTFS_CPIO}" "${TARGET}/boot/initramfs.cpio.gz"
if [ ! -s "${TARGET}/boot/bzImage" ] || [ ! -s "${TARGET}/boot/initramfs.cpio.gz" ]; then
  shreeos_die "Failed to install required kernel or initramfs boot artifact."
fi

chown -R root:root "${TARGET}"
for auth_binary in "${TARGET}/usr/bin/shree-auth" "${TARGET}/sbin/shree-auth"; do
  [ -f "$auth_binary" ] && [ ! -L "$auth_binary" ] || \
    shreeos_die "Installed authentication helper is missing or unsafe: $auth_binary"
  chown 0:0 "$auth_binary"
  chmod 4755 "$auth_binary"
done
if [ -n "$ESP_MOUNT" ]; then
  [ ! -L "${TARGET}/boot" ] || shreeos_die "Unsafe /boot symlink in staged rootfs."
  mkdir -p "${TARGET}/boot/efi"
  [ ! -L "${TARGET}/boot/efi" ] || shreeos_die "Unsafe /boot/efi symlink in staged rootfs."
fi

# 5. Configure system identity, timezone and credentials
shreeos_log "Configuring system identity and credentials..."
mkdir -p "${TARGET}/etc"
echo "${HOSTNAME}" > "${TARGET}/etc/hostname"

echo "${TIMEZONE}" > "${TARGET}/etc/timezone"
if [ ! -f "${TARGET}/usr/share/zoneinfo/${TIMEZONE}" ]; then
  shreeos_die "Timezone '${TIMEZONE}' is not present in the target zoneinfo database."
fi
ln -sf "/usr/share/zoneinfo/${TIMEZONE}" "${TARGET}/etc/localtime"

if [ -n "$HASHED_ROOT_PW" ]; then
  if [ -f "${TARGET}/etc/shadow" ]; then
    sed -i "s|^root:[^:]*:|root:${HASHED_ROOT_PW}:|" "${TARGET}/etc/shadow"
  else
    echo "root:${HASHED_ROOT_PW}:19000:0:99999:7:::" > "${TARGET}/etc/shadow"
  fi
  chmod 600 "${TARGET}/etc/shadow"
fi

if [ -n "${USERNAME}" ]; then
  SHREEOS_PREHASHED_USER_PASSWORD="$HASHED_USER_PW" \
    bash "${SCRIPT_DIR}/configure-user.sh" "$TARGET" "$USERNAME"
fi

HASHED_ROOT_PW=""
HASHED_USER_PW=""
unset HASHED_ROOT_PW HASHED_USER_PW

# 6. Install Bootloader (UEFI & BIOS)
shreeos_log "Installing GRUB bootloader to ${WORKING_DISK}"
GRUB_EFI_ARGS=()
# The ESP is mounted outside the target tree, so point grub-install at the
# real FAT mount; otherwise it would write the UEFI loader into the empty
# ${TARGET}/boot/efi directory on the ext4 root and leave the ESP empty.
if [ -n "$ESP_MOUNT" ]; then
  GRUB_EFI_ARGS+=("--efi-dir=$ESP_MOUNT")
fi
bash "${SHREEOS_ROOT_DIR}/bootloader/scripts/install-grub-disk.sh" "$TARGET" "$WORKING_DISK" --boot-mode="$BOOT_MODE" "${GRUB_EFI_ARGS[@]}"

# 7. Generate fstab with UUIDs
ROOT_UUID=$(blkid -s UUID -o value "$PART_ROOT" 2>/dev/null || echo "")
ROOT_PARTUUID=$(blkid -s PARTUUID -o value "$PART_ROOT" 2>/dev/null || echo "")
ESP_UUID=$(blkid -s UUID -o value "$PART_ESP" 2>/dev/null || echo "")

if [ -z "$ROOT_UUID" ]; then
  shreeos_die "CRITICAL: Could not discover filesystem UUID for root partition (${PART_ROOT})."
fi
if [ -z "$ROOT_PARTUUID" ]; then
  shreeos_die "CRITICAL: Could not discover GPT PARTUUID for root partition (${PART_ROOT})."
fi

cat > "${TARGET}/etc/fstab" <<FSTAB
# /etc/fstab — Static file system information
UUID=${ROOT_UUID} / ext4 defaults 0 1
$( [ "$BOOT_MODE" != "bios" ] && [ -n "$ESP_UUID" ] && echo "UUID=${ESP_UUID} /boot/efi vfat umask=0077 0 2" )
proc /proc proc defaults 0 0
sysfs /sys sysfs defaults 0 0
devtmpfs /dev devtmpfs defaults 0 0
devpts /dev/pts devpts gid=5,mode=620 0 0
tmpfs /tmp tmpfs defaults,nosuid,nodev 0 0
FSTAB

# 8. Post-installation Verification
shreeos_step "Verifying completed installation on ${TARGET}..."
VERIFY_FAILED=false

if [ ! -s "${TARGET}/boot/bzImage" ]; then
  shreeos_warn "Verification failure: /boot/bzImage is missing or empty"
  VERIFY_FAILED=true
fi

if [ ! -s "${TARGET}/boot/initramfs.cpio.gz" ]; then
  shreeos_warn "Verification failure: /boot/initramfs.cpio.gz is missing or empty"
  VERIFY_FAILED=true
fi

if [ ! -s "${TARGET}/boot/grub/grub.cfg" ]; then
  shreeos_warn "Verification failure: /boot/grub/grub.cfg is missing or empty"
  VERIFY_FAILED=true
elif ! grep -q "${ROOT_UUID}" "${TARGET}/boot/grub/grub.cfg"; then
  shreeos_warn "Verification failure: Root UUID ${ROOT_UUID} not present in /boot/grub/grub.cfg"
  VERIFY_FAILED=true
elif ! grep -Fq "root=PARTUUID=${ROOT_PARTUUID} rw" "${TARGET}/boot/grub/grub.cfg"; then
  shreeos_warn "Verification failure: installed GRUB entry does not boot the ext4 root by PARTUUID"
  VERIFY_FAILED=true
elif grep -Eq '^[[:space:]]*initrd[[:space:]]' "${TARGET}/boot/grub/grub.cfg"; then
  shreeos_warn "Verification failure: installed GRUB entry still boots the live rootfs initramfs"
  VERIFY_FAILED=true
fi

if [ ! -s "${TARGET}/etc/fstab" ]; then
  shreeos_warn "Verification failure: /etc/fstab is missing or empty"
  VERIFY_FAILED=true
elif ! grep -q "${ROOT_UUID}" "${TARGET}/etc/fstab"; then
  shreeos_warn "Verification failure: Root UUID ${ROOT_UUID} not present in /etc/fstab"
  VERIFY_FAILED=true
fi

if [ -n "$ESP_MOUNT" ]; then
  for esp_file in "${ESP_MOUNT}/EFI/BOOT/BOOTX64.EFI" "${ESP_MOUNT}/EFI/BOOT/grub.cfg"; do
    if [ ! -s "$esp_file" ] || [ -L "$esp_file" ]; then
      shreeos_warn "Verification failure: required UEFI ESP file is missing or unsafe: ${esp_file}"
      VERIFY_FAILED=true
    fi
  done
fi

for auth_binary in "${TARGET}/usr/bin/shree-auth" "${TARGET}/sbin/shree-auth"; do
  if [ ! -f "$auth_binary" ] || [ -L "$auth_binary" ] || \
     [ "$(stat -c '%u:%g:%a' "$auth_binary" 2>/dev/null || echo '')" != "0:0:4755" ]; then
    shreeos_warn "Verification failure: authentication helper is not root-owned setuid 4755: ${auth_binary}"
    VERIFY_FAILED=true
  fi
done

if [ -f "${TARGET}/etc/shadow" ]; then
  if [ "$(stat -c '%a' "${TARGET}/etc/shadow" 2>/dev/null || echo '0')" != "600" ]; then
    chmod 0600 "${TARGET}/etc/shadow" 2>/dev/null || true
  fi
fi

if [ "$VERIFY_FAILED" = true ]; then
  shreeos_die "CRITICAL: Completed installation verification failed! System may not boot cleanly."
fi

shreeos_ok "Completed installation successfully verified (kernel, direct-root GRUB, fstab, and security credentials OK)"

sync
shreeos_ok "${DISTRO_NAME:-ShreeOS} successfully installed to ${DISK}"
