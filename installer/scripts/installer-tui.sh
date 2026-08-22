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
echo "│                         Version 0.1.0-dev (x86_64)                       │"
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
echo "Available storage block devices:"
echo "--------------------------------------------------------------------------"
if command -v lsblk >/dev/null 2>&1; then
  lsblk -d -o NAME,SIZE,MODEL,ROTA,TYPE | grep -E "disk|loop" || true
else
  fdisk -l 2>/dev/null | grep "Disk /dev/" || echo "No disks found"
fi
echo "--------------------------------------------------------------------------"
echo ""
read -r -p "Enter target disk path (e.g. /dev/sda or /dev/nvme0n1): " TARGET_DISK

if [[ -z "$TARGET_DISK" || ( ! -b "$TARGET_DISK" && ! -f "$TARGET_DISK" ) ]]; then
  shreeos_die "Invalid target disk '${TARGET_DISK}'. Aborting."
fi

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
