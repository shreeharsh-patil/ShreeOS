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
}

clear

echo "┌──────────────────────────────────────────────────────────────────────────┐"
echo "│                                                                          │"
echo "│                                ShreeOS                                   │"
echo "│                         Version 0.2.0-dev (x86_64)                       │"
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

LIVE_DEV=""
for live_dir in /run/initramfs/live /cdrom /mnt/cdrom /run/media; do
  if [ -d "$live_dir" ]; then
    LIVE_DEV=$(findmnt -n -o SOURCE "$live_dir" 2>/dev/null || echo "")
    [ -n "$LIVE_DEV" ] && break
  fi
done
HOST_ROOT_DEV=$(findmnt -n -o SOURCE / 2>/dev/null || echo "")

AVAILABLE_DISKS=()
if command -v lsblk >/dev/null 2>&1; then
  while read -r name size model _rota type tran; do
    [ -z "$name" ] && continue
    [ "$type" != "disk" ] && [ "$type" != "loop" ] && continue
    # Skip CD/DVD drives
    [[ "$name" == sr* ]] && continue

    DEV_PATH="/dev/${name}"
    CANON_DEV=$(realpath "$DEV_PATH" 2>/dev/null || echo "$DEV_PATH")

    # Skip active live media or active host root
    if [ -n "$LIVE_DEV" ] && [[ "$(realpath "$LIVE_DEV" 2>/dev/null || echo "$LIVE_DEV")" == "$CANON_DEV"* ]]; then
      continue
    fi
    if [ -n "$HOST_ROOT_DEV" ] && [[ "$(realpath "$HOST_ROOT_DEV" 2>/dev/null || echo "$HOST_ROOT_DEV")" == "$CANON_DEV"* ]]; then
      continue
    fi

    TRANSPORT="${tran:-${type}}"
    case "$name" in
      nvme*) TRANSPORT="NVMe" ;;
      vd*)   TRANSPORT="VirtIO" ;;
      sd*)   [ "$TRANSPORT" = "disk" ] && TRANSPORT="SATA/SCSI" ;;
      mmc*)  TRANSPORT="MMC/SD" ;;
    esac

    printf "  %-16s %-10s %-12s %-24s\n" "$DEV_PATH" "$size" "$TRANSPORT" "${model:-Generic Storage}"
    AVAILABLE_DISKS+=("$DEV_PATH")
  done < <(lsblk -d -n -o NAME,SIZE,MODEL,ROTA,TYPE,TRAN 2>/dev/null || true)
fi

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

  CANON_TGT=$(realpath "$TARGET_DISK" 2>/dev/null || echo "$TARGET_DISK")
  if [ -n "$LIVE_DEV" ] && [[ "$(realpath "$LIVE_DEV" 2>/dev/null || echo "$LIVE_DEV")" == "$CANON_TGT"* ]]; then
    echo "Error: Target '${TARGET_DISK}' contains the running live installer media! Refusing."
    continue
  fi
  if [ -n "$HOST_ROOT_DEV" ] && [[ "$(realpath "$HOST_ROOT_DEV" 2>/dev/null || echo "$HOST_ROOT_DEV")" == "$CANON_TGT"* ]]; then
    echo "Error: Target '${TARGET_DISK}' contains the running host root filesystem! Refusing."
    continue
  fi
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
  if [[ "$USERNAME" =~ ^[a-z_][a-z0-9_-]{0,31}$ ]]; then
    break
  else
    echo "Invalid username. Must start with lowercase letter or underscore, 1-32 characters, no colons/slashes/spaces."
  fi
done

echo ""
while true; do
  echo -n "Enter Root Administrator Password: "
  read -r -s ROOT_PW
  echo ""
  echo -n "Confirm Root Administrator Password: "
  read -r -s ROOT_PW_CONFIRM
  echo ""
  if [ -z "$ROOT_PW" ]; then
    echo "Error: Password cannot be empty."
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
  if [ -z "$USER_PW" ]; then
    echo "Error: Password cannot be empty."
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
read -r -p "Timezone (e.g. UTC, Asia/Kolkata, America/New_York) [default: UTC]: " USER_TZ
USER_TZ="${USER_TZ:-UTC}"

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

# Create secure temporary credential file mode 0600
CREDS_FILE=$(mktemp /tmp/shreeos-creds-XXXXXX)
chmod 600 "$CREDS_FILE"
printf "%s\n%s\n" "$ROOT_PW" "$USER_PW" > "$CREDS_FILE"

# Clean credentials on exit
trap 'rm -f "$CREDS_FILE"' EXIT

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
echo "│   You may now reboot your computer into your new ShreeOS desktop.        │"
echo "└──────────────────────────────────────────────────────────────────────────┘"
echo ""
