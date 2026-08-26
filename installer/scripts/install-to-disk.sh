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
LOOP_DEV=""

cleanup() {
  if [ -n "$TARGET" ] && [ -d "$TARGET" ]; then
    shreeos_log "Unmounting target filesystems..."
    umount "${TARGET}/boot/efi" 2>/dev/null || true
    umount "$TARGET" 2>/dev/null || true
    rmdir "$TARGET" 2>/dev/null || true
  fi
  if [ -n "$LOOP_DEV" ]; then
    shreeos_log "Detaching loop device ${LOOP_DEV}..."
    losetup -d "$LOOP_DEV" 2>/dev/null || true
  fi
  if [ "${CREDS_FILE_OWNED:-false}" = true ] && [ -n "${CREDS_FILE:-}" ] && [ -f "${CREDS_FILE}" ]; then
    rm -f "${CREDS_FILE}"
  fi
}
trap cleanup EXIT INT TERM

shreeos_require_cmd sfdisk mkfs.ext4 grub-install blkid

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

if [ -n "$CREDS_FILE" ]; then
  if [ ! -f "$CREDS_FILE" ] || [ -L "$CREDS_FILE" ]; then
    shreeos_die "Credentials file must be a regular, non-symlink file."
  fi
  if [ "$(stat -c '%u' "$CREDS_FILE")" != "$(id -u)" ] || [ $((8#$(stat -c '%a' "$CREDS_FILE") & 077)) -ne 0 ]; then
    shreeos_die "Credentials file must be owned by the invoking user and have mode 0600."
  fi
  if [ "$(sed -n '$=' "$CREDS_FILE")" -gt 2 ]; then
    shreeos_die "Credentials file must contain only root and optional user password lines."
  fi
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

WORKING_DISK="$DISK"

# If disk is regular file, attach loop device with partition scanning
if [ -f "$DISK" ] && [ ! -b "$DISK" ]; then
  if command -v losetup >/dev/null 2>&1; then
    shreeos_log "Attaching raw disk image ${DISK} via loop device (with partition scanning)..."
    LOOP_DEV=$(losetup -Pf --show "$DISK")
    WORKING_DISK="$LOOP_DEV"
  fi
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

# Detect partition devices
if [ -b "${WORKING_DISK}p3" ] || [ -f "${WORKING_DISK}p3" ]; then
  PART_BIOS="${WORKING_DISK}p1"
  PART_ESP="${WORKING_DISK}p2"
  PART_ROOT="${WORKING_DISK}p3"
elif [ -b "${WORKING_DISK}3" ] || [ -f "${WORKING_DISK}3" ]; then
  PART_BIOS="${WORKING_DISK}1"
  PART_ESP="${WORKING_DISK}2"
  PART_ROOT="${WORKING_DISK}3"
else
  PART_BIOS="${WORKING_DISK}1"
  PART_ESP="${WORKING_DISK}2"
  PART_ROOT="${WORKING_DISK}3"
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

if [ "$BOOT_MODE" = "both" ] || [ "$BOOT_MODE" = "uefi" ]; then
  mkdir -p "${TARGET}/boot/efi"
  if [ -b "$PART_ESP" ]; then
    mount "$PART_ESP" "${TARGET}/boot/efi"
  fi
fi

# 4. Copy rootfs payload
shreeos_log "Copying root filesystem contents..."
STAGE_ROOT="${SHREEOS_STAGE_ROOT:-${SHREEOS_ROOT_DIR}/build/rootfs}"
ROOTFS_CPIO="${SHREEOS_BUILD_DIR:-${SHREEOS_ROOT_DIR}/build}/initramfs.cpio.gz"

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

# 5. Configure system identity, timezone and credentials
shreeos_log "Configuring system identity and credentials..."
mkdir -p "${TARGET}/etc"
echo "${HOSTNAME}" > "${TARGET}/etc/hostname"

echo "${TIMEZONE}" > "${TARGET}/etc/timezone"
if [ ! -f "${TARGET}/usr/share/zoneinfo/${TIMEZONE}" ]; then
  shreeos_die "Timezone '${TIMEZONE}' is not present in the target zoneinfo database."
fi
ln -sf "/usr/share/zoneinfo/${TIMEZONE}" "${TARGET}/etc/localtime"

# Read root & user passwords from secure credential file if provided
if [ -n "$CREDS_FILE" ] && [ -f "$CREDS_FILE" ]; then
  ROOT_PW=$(sed -n '1p' "$CREDS_FILE")
  USER_PW=$(sed -n '2p' "$CREDS_FILE")

  if [ -n "$ROOT_PW" ]; then
    SALT="$(head -c 16 /dev/urandom | base64 | tr -dc 'a-zA-Z0-9' | head -c 16)"
    HASHED_PW=""
    if command -v openssl >/dev/null 2>&1; then
      HASHED_PW=$(printf "%s" "$ROOT_PW" | openssl passwd -6 -salt "$SALT" -stdin 2>/dev/null || echo "")
    elif command -v mkpasswd >/dev/null 2>&1; then
      HASHED_PW=$(printf "%s" "$ROOT_PW" | mkpasswd -m sha-512 -S "$SALT" 2>/dev/null || echo "")
    fi

    # Wipe ROOT_PW immediately
    ROOT_PW=""
    unset ROOT_PW

    if [ -z "$HASHED_PW" ]; then
      shreeos_die "Failed to securely hash root administrator password. Installation aborted."
    fi

    if [ -f "${TARGET}/etc/shadow" ]; then
      sed -i "s|^root:[^:]*:|root:${HASHED_PW}:|" "${TARGET}/etc/shadow"
    else
      echo "root:${HASHED_PW}:19000:0:99999:7:::" > "${TARGET}/etc/shadow"
    fi
    chmod 600 "${TARGET}/etc/shadow"
  fi

  if [ -n "${USERNAME}" ] && [ -f "${SCRIPT_DIR}/configure-user.sh" ]; then
    USER_TMP_CRED=$(mktemp /tmp/user-cred-XXXXXX)
    chmod 600 "$USER_TMP_CRED"
    printf "%s" "$USER_PW" > "$USER_TMP_CRED"
    USER_PW=""
    unset USER_PW

    bash "${SCRIPT_DIR}/configure-user.sh" "$TARGET" "$USERNAME" "$USER_TMP_CRED"
    rm -f "$USER_TMP_CRED"
  fi
fi

# 6. Install Bootloader (UEFI & BIOS)
shreeos_log "Installing GRUB bootloader to ${WORKING_DISK}"
bash "${SHREEOS_ROOT_DIR}/bootloader/scripts/install-grub-disk.sh" "$TARGET" "$WORKING_DISK" --boot-mode="$BOOT_MODE"

# 7. Generate fstab with UUIDs
ROOT_UUID=$(blkid -s UUID -o value "$PART_ROOT" 2>/dev/null || echo "")
ESP_UUID=$(blkid -s UUID -o value "$PART_ESP" 2>/dev/null || echo "")

if [ -z "$ROOT_UUID" ]; then
  shreeos_die "CRITICAL: Could not discover filesystem UUID for root partition (${PART_ROOT})."
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

sync
shreeos_ok "${DISTRO_NAME:-ShreeOS} successfully installed to ${DISK}"
