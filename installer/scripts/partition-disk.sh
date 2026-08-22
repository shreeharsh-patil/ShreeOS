#!/usr/bin/env bash
# installer/scripts/partition-disk.sh — Disk partitioning utility for ShreeOS installer
#
# Formats target disk with GPT partition table:
#   1. BIOS Boot Partition (2 MiB)
#   2. EFI System Partition / ESP (512 MiB, FAT32)
#   3. Root filesystem (Remaining space, ext4)
#
# Usage:
#   bash partition-disk.sh <disk-device> [--yes]
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
  shreeos_die "Usage: partition-disk.sh <disk-device> [--yes]"
fi

DISK="$1"
ASSUME_YES=false

for arg in "${@:2}"; do
  if [ "$arg" = "--yes" ]; then
    ASSUME_YES=true
  fi
done

shreeos_require_cmd sfdisk

# 1. Safety Checks: Target Device Validation
if [ ! -b "$DISK" ] && [ ! -f "$DISK" ]; then
  shreeos_die "Target ${DISK} is neither a block device nor a regular disk image file."
fi

# Check if target disk or any of its partitions are mounted
if command -v findmnt >/dev/null 2>&1; then
  MOUNTED_PARTS=$(findmnt -ln -o SOURCE,TARGET | awk -v d="$DISK" '$1 ~ "^"d {print $1" -> "$2}')
  if [ -n "$MOUNTED_PARTS" ]; then
    shreeos_warn "Active mounts detected on ${DISK}:"
    echo "$MOUNTED_PARTS"
    shreeos_die "Cannot partition ${DISK} while partitions are mounted. Unmount all partitions first."
  fi

  # Check if target is the currently booted root device
  ROOT_DEV=$(findmnt -n -o SOURCE / 2>/dev/null || echo "")
  if [ -n "$ROOT_DEV" ] && [[ "$ROOT_DEV" == "$DISK"* ]]; then
    shreeos_die "FATAL: ${DISK} contains the active host/live root filesystem (${ROOT_DEV}). Refusing to self-destruct."
  fi
fi

# Check removable status if available in sysfs
SYS_NAME="$(basename "$DISK")"
if [ -f "/sys/block/${SYS_NAME}/removable" ]; then
  IS_REMOVABLE=$(cat "/sys/block/${SYS_NAME}/removable")
  if [ "$IS_REMOVABLE" = "0" ] && [ "$ASSUME_YES" = false ]; then
    shreeos_warn "${DISK} is reported as a NON-REMOVABLE internal fixed drive."
  fi
fi

# 2. Interactive explicit confirmation (requiring typing the exact device name)
if [ "$ASSUME_YES" = false ]; then
  echo ""
  echo "================================================================="
  echo "  DANGER: ALL EXISTING DATA ON ${DISK} WILL BE ERASED!"
  echo "================================================================="
  echo "  Device: ${DISK}"
  if command -v lsblk >/dev/null 2>&1 && [ -b "$DISK" ]; then
    lsblk -o NAME,SIZE,TYPE,FSTYPE,MODEL "$DISK" || true
  fi
  echo "================================================================="
  echo "  To confirm partitioning, type the exact device path '${DISK}':"
  read -r -p "> " CONFIRM_NAME
  if [ "$CONFIRM_NAME" != "$DISK" ]; then
    shreeos_die "Device confirmation failed ('$CONFIRM_NAME' != '$DISK'). Partitioning aborted."
  fi
fi

shreeos_step "Writing GPT partition table (BIOS Boot + EFI ESP + Root) to ${DISK}"

# Layout:
# 1. BIOS boot partition: 2 MiB (GUID: 21686148-6449-6E6F-744E-656564454649)
# 2. EFI System Partition (ESP): 512 MiB (GUID: C12A7328-F81F-11D2-BA4B-00A0C93EC93B)
# 3. Linux root filesystem: remainder (GUID: 0FC63DAF-8483-4772-8E79-3D69D8477DE4)
sfdisk "$DISK" <<EOF
label: gpt
size=2M,   type=21686148-6449-6E6F-744E-656564454649, name="BIOS"
size=512M, type=C12A7328-F81F-11D2-BA4B-00A0C93EC93B, name="EFI"
size=+,    type=0FC63DAF-8483-4772-8E79-3D69D8477DE4, name="root"
EOF

sleep 1
if command -v partx >/dev/null 2>&1 && [ -b "$DISK" ]; then
  partx -u "$DISK" 2>/dev/null || true
fi

shreeos_ok "Successfully partitioned ${DISK} (Part 1: BIOS Boot, Part 2: ESP FAT32, Part 3: Root ext4)"
