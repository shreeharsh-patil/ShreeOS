#!/usr/bin/env bash
# installer/scripts/installer-tui.sh — ShreeOS Terminal User Interface (TUI) Installer
#
# Multi-stage installation workflow with secure credential handling:
#   1. Welcome & Hardware Overview
#   2. Target Disk Selection & Safety Safeguards
#   3. Hostname & User Account Configuration (No Default Passwords, Strict Validation)
#   4. Timezone & Locale Setup
#   5. Safety Review & Exact Confirmation
#   6. Automated Partitioning, Copying & Bootloader Setup
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SHREEOS_ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$SHREEOS_ROOT_DIR/build.conf" 2>/dev/null || true
source "$SHREEOS_ROOT_DIR/scripts/common.sh" 2>/dev/null || {
  shreeos_step() { echo "==> $1"; }
  shreeos_ok() { echo "  [OK] $1"; }
  shreeos_warn() { echo "  [WARN] $1"; }
  shreeos_die() { echo "  [ERROR] $1" >&2; exit 1; }
  shreeos_require_cmd() { for c in "$@"; do command -v "$c" >/dev/null 2>&1 || shreeos_die "Missing required command: $c"; done; }
}

if [ "$(id -u)" -ne 0 ]; then
  shreeos_die "The interactive installer requires root privileges. Re-run it with sudo."
fi
shreeos_require_cmd lsblk findmnt realpath stat awk grep

clear

echo "┌──────────────────────────────────────────────────────────────────────────┐"
echo "│                                                                          │"
echo "│                                ShreeOS                                   │"
printf "│                         Version %-12.12s (x86_64)                │\n" "${DISTRO_VERSION:-0.2.0-dev}"
echo "│                                                                          │"
echo "│            Designed for Performance, Safety, and Restraint               │"
echo "│                                                                          │"
echo "└──────────────────────────────────────────────────────────────────────────┘"
echo ""

# Stage 1: Welcome
echo "==> Step 1 of 5: System Overview"
echo "    CPU:    $(awk -F': ' '/model name/ {print $2; exit}' /proc/cpuinfo 2>/dev/null || echo 'x86_64 Processor')"
echo "    Memory: $(awk '/MemTotal:/ {printf "%.1f GB", $2/1024/1024}' /proc/meminfo 2>/dev/null || echo 'N/A')"
echo "    Kernel: Linux $(uname -r 2>/dev/null || echo '6.18')"
echo ""
read -r -p "Press [Enter] to begin installation setup... " _

clear
# Stage 2: Disk Selection
echo "==> Step 2 of 5: Target Disk Selection"
echo "Detecting available storage devices (NVMe, SATA, VirtIO, MMC)..."
echo "--------------------------------------------------------------------------"
printf "  %-16s %-10s %-12s %-24s\n" "DEVICE" "SIZE" "TYPE" "MODEL"
echo "--------------------------------------------------------------------------"

disk_has_active_usage() {
  local disk="$1"
  [ -b "$disk" ] || return 1

  local target_mms mounted swap_mms mm
  if ! target_mms=$(lsblk -nr -o MAJ:MIN -- "$disk" 2>/dev/null); then
    return 0
  fi
  [ -n "$target_mms" ] || return 0

  if ! mounted=$(findmnt -r -n -o MAJ:MIN 2>/dev/null); then
    return 0
  fi
  while IFS= read -r mm; do
    [ -n "$mm" ] || continue
    if grep -Fxq "$mm" <<< "$target_mms"; then
      return 0
    fi
  done <<< "$mounted"

  if command -v swapon >/dev/null 2>&1; then
    if ! swap_mms=$(swapon --show --noheadings --raw --output MAJ:MIN 2>/dev/null); then
      return 0
    fi
    while IFS= read -r mm; do
      [ -n "$mm" ] || continue
      if grep -Fxq "$mm" <<< "$target_mms"; then
        return 0
      fi
    done <<< "$swap_mms"
  fi

  return 1
}

AVAILABLE_DISKS=()
while read -r name size type tran; do
  [ -n "$name" ] || continue
  [ "$type" = "disk" ] || continue
  [[ "$name" == sr* ]] && continue

  DEV_PATH="/dev/${name}"
  [ -b "$DEV_PATH" ] || continue
  disk_has_active_usage "$DEV_PATH" && continue

  MODEL=$(lsblk -dn -o MODEL -- "$DEV_PATH" 2>/dev/null | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' || true)
  TRANSPORT="${tran:-disk}"
  case "$name" in
    nvme*) TRANSPORT="NVMe" ;;
    vd*)   TRANSPORT="VirtIO" ;;
    sd*)   [ "$TRANSPORT" = "disk" ] && TRANSPORT="SATA/SCSI" ;;
    mmc*)  TRANSPORT="MMC/SD" ;;
  esac

  printf "  %-16s %-10s %-12s %-24.24s\n" "$DEV_PATH" "$size" "$TRANSPORT" "${MODEL:-Generic Storage}"
  AVAILABLE_DISKS+=("$DEV_PATH")
done < <(lsblk -d -n -o NAME,SIZE,TYPE,TRAN 2>/dev/null)
if [ ${#AVAILABLE_DISKS[@]} -eq 0 ]; then
  echo "  No unmounted candidate disks automatically detected."
  echo "  You may manually specify a target block device or raw disk image below."
fi
echo "--------------------------------------------------------------------------"
echo ""

while true; do
  read -r -p "Enter target disk path (e.g. /dev/nvme0n1, /dev/vda, /dev/sda): " TARGET_DISK
  if [[ -z "$TARGET_DISK" ]]; then
    echo "Error: Disk path cannot be empty."
    continue
  fi
  if [ ! -b "$TARGET_DISK" ] && [ ! -f "$TARGET_DISK" ]; then
    echo "Error: '${TARGET_DISK}' is not a valid block device or file."
    continue
  fi

  if ! CANON_TGT=$(realpath -- "$TARGET_DISK" 2>/dev/null); then
    echo "Error: Unable to resolve target path safely."
    continue
  fi

  if [ -b "$CANON_TGT" ]; then
    TARGET_TYPE=$(lsblk -dn -o TYPE -- "$CANON_TGT" 2>/dev/null || true)
    if [ "$TARGET_TYPE" != "disk" ] && [ "$TARGET_TYPE" != "loop" ]; then
      echo "Error: Target must be a whole disk/loop device, not a partition or mapped child."
      continue
    fi
    if disk_has_active_usage "$CANON_TGT"; then
      echo "Error: Target '${TARGET_DISK}' or one of its child devices is mounted or active swap. Refusing."
      continue
    fi
  else
    IMAGE_BYTES=$(stat -c '%s' "$CANON_TGT" 2>/dev/null || echo 0)
    if ! [[ "$IMAGE_BYTES" =~ ^[0-9]+$ ]] || [ "$IMAGE_BYTES" -lt 1073741824 ]; then
      echo "Error: Raw disk images must be at least 1 GiB for the ShreeOS partition layout."
      continue
    fi
  fi

  TARGET_DISK="$CANON_TGT"
  break
done

clear
# Stage 3: User & Hostname Configuration
echo "==> Step 3 of 5: Identity & Credentials"
echo ""

while true; do
  read -r -p "System Hostname [default: shreeos]: " USER_HOSTNAME
  USER_HOSTNAME="${USER_HOSTNAME:-shreeos}"
  if [[ "$USER_HOSTNAME" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?$ ]]; then
    break
  else
    echo "Invalid hostname. Must contain alphanumeric characters and hyphens only."
  fi
done

while true; do
  read -r -p "Primary User Account Name: " USERNAME
  if ! [[ "$USERNAME" =~ ^[a-z_][a-z0-9_-]{0,31}$ ]]; then
    echo "Invalid username. Must start with lowercase letter or underscore, 1-32 characters, no colons/slashes/spaces."
    continue
  fi
  case "$USERNAME" in
    root|daemon|bin|nobody)
      echo "Username '$USERNAME' is reserved by the ShreeOS base system."
      continue
      ;;
  esac
  break
done

echo ""
while true; do
  echo -n "Enter Root Administrator Password: "
  read -r -s ROOT_PW
  echo ""
  echo -n "Confirm Root Administrator Password: "
  read -r -s ROOT_PW_CONFIRM
  echo ""
  if [ "${#ROOT_PW}" -lt 8 ]; then
    echo "Error: Root password must be at least 8 characters."
  elif [ "$ROOT_PW" != "$ROOT_PW_CONFIRM" ]; then
    echo "Error: Passwords do not match. Please try again."
  else
    break
  fi
done

echo ""
while true; do
  echo -n "Enter Password for User (${USERNAME}): "
  read -r -s USER_PW
  echo ""
  echo -n "Confirm Password for User (${USERNAME}): "
  read -r -s USER_PW_CONFIRM
  echo ""
  if [ "${#USER_PW}" -lt 8 ]; then
    echo "Error: User password must be at least 8 characters."
  elif [ "$USER_PW" != "$USER_PW_CONFIRM" ]; then
    echo "Error: Passwords do not match. Please try again."
  else
    break
  fi
done

clear
# Stage 4: Timezone Setup
echo "==> Step 4 of 5: System Clock & Timezone"
echo ""
while true; do
  read -r -p "Timezone (e.g. UTC, Asia/Kolkata, America/New_York) [default: UTC]: " USER_TZ
  USER_TZ="${USER_TZ:-UTC}"
  if [[ "$USER_TZ" == *".."* ]] || [[ "$USER_TZ" == /* ]] ||
     ! [[ "$USER_TZ" =~ ^[A-Za-z0-9_+-]+(/[A-Za-z0-9_+-]+)*$ ]]; then
    echo "Invalid timezone format."
    continue
  fi
  # Validate against the target rootfs when it is already built; this avoids
  # accepting a host timezone that cannot be installed into ShreeOS.
  if [ -d "${SHREEOS_STAGE_ROOT:-}/usr/share/zoneinfo" ]; then
    if [ ! -f "${SHREEOS_STAGE_ROOT}/usr/share/zoneinfo/$USER_TZ" ]; then
      echo "Timezone '$USER_TZ' was not found in the built ShreeOS rootfs."
      continue
    fi
  elif [ -d /usr/share/zoneinfo ] && [ ! -f "/usr/share/zoneinfo/$USER_TZ" ]; then
    echo "Timezone '$USER_TZ' was not found on this system."
    continue
  fi
  break
done

clear
# Stage 5: Destructive Confirmation & Review
echo "┌──────────────────────────────────────────────────────────────────────────┐"
echo "│                   INSTALLATION SUMMARY & REVIEW                          │"
echo "└──────────────────────────────────────────────────────────────────────────┘"
echo ""
echo "  Target Disk:      ${TARGET_DISK} (DANGER: ALL DATA ON DISK WILL BE ERASED)"
echo "  Partition Scheme: GPT (2MB BIOS Boot + 512MB ESP FAT32 + Root ext4)"
echo "  Bootloader:       GRUB2 (Unified UEFI x86_64-efi + BIOS i386-pc)"
echo "  Hostname:         ${USER_HOSTNAME}"
echo "  User Account:     ${USERNAME}"
echo "  Timezone:         ${USER_TZ}"
echo ""
echo "=========================================================================="
echo "  To confirm installation, type the exact disk path '${TARGET_DISK}':"
read -r -p "> " CONFIRM_DISK

if [ "$CONFIRM_DISK" != "$TARGET_DISK" ]; then
  shreeos_die "Disk confirmation failed ('$CONFIRM_DISK' != '$TARGET_DISK'). Installation cancelled."
fi

# Create secure temporary credential file mode 0600.
CREDS_FILE=$(mktemp /tmp/shreeos-creds-XXXXXX)
chmod 600 "$CREDS_FILE"
printf "%s\n%s\n" "$ROOT_PW" "$USER_PW" > "$CREDS_FILE"

# install-to-disk.sh verifies that a credential file belongs to the original
# sudo user. mktemp runs as root in this TUI, so transfer only this private
# 0600 file back to that invoking user before handing it to the core installer.
if [ -n "${SUDO_UID:-}" ]; then
  if [ -n "${SUDO_GID:-}" ]; then
    chown "${SUDO_UID}:${SUDO_GID}" "$CREDS_FILE"
  else
    chown "${SUDO_UID}" "$CREDS_FILE"
  fi
fi

ROOT_PW=""; ROOT_PW_CONFIRM=""; USER_PW=""; USER_PW_CONFIRM=""
unset ROOT_PW ROOT_PW_CONFIRM USER_PW USER_PW_CONFIRM

cleanup_credentials() {
  [ -n "${CREDS_FILE:-}" ] && rm -f "$CREDS_FILE"
}
trap cleanup_credentials EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

echo ""
echo "==> Starting installation process..."
bash "${SCRIPT_DIR}/install-to-disk.sh" "$TARGET_DISK" --yes \
  --hostname="$USER_HOSTNAME" \
  --timezone="$USER_TZ" \
  --username="$USERNAME" \
  --credentials-file="$CREDS_FILE"

rm -f "$CREDS_FILE"

echo ""
echo "┌──────────────────────────────────────────────────────────────────────────┐"
echo "│                    INSTALLATION COMPLETED SUCCESSFULLY                   │"
echo "│                                                                          │"
echo "│   You may now reboot your computer into your new ShreeOS system.         │"
echo "└──────────────────────────────────────────────────────────────────────────┘"
echo ""
