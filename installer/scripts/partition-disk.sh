#!/usr/bin/env bash
# installer/scripts/partition-disk.sh — Disk partitioning utility for ShreeOS installer
#
# Formats target disk with GPT partition table:
#   1. BIOS Boot Partition (2 MiB)
#   2. EFI System Partition / ESP (512 MiB, FAT32)
#   3. Root filesystem (Remaining space, ext4)
#
# Safety Requirements:
#   - Block device ancestry verification (protects /, /boot, /boot/efi, live media)
#   - Explicit confirmation check
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
    echo "Usage: partition-disk.sh <disk-device> [--yes]"
    exit 0
  fi
done

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
  shreeos_die "Target '${DISK}' is not a valid block device or disk image."
fi

# Resolve canonical path before performing any topology checks.
if ! CANONICAL_DISK="$(realpath -- "$DISK" 2>/dev/null)"; then
  shreeos_die "Unable to resolve target path safely: $DISK"
fi

# For real block devices, prove that the target is a whole disk/loop device
# and that none of its descendants back a mounted filesystem or active swap.
# Any failed topology query aborts the destructive operation.
if [ -b "$CANONICAL_DISK" ]; then
  shreeos_require_cmd lsblk findmnt mountpoint

  if ! TARGET_TYPE="$(lsblk -dnro TYPE -- "$CANONICAL_DISK" 2>/dev/null)"; then
    shreeos_die "Unable to determine block-device type for '$DISK'; refusing to partition."
  fi
  TARGET_TYPE="${TARGET_TYPE%%$'\n'*}"
  case "$TARGET_TYPE" in
    disk|loop) ;;
    *) shreeos_die "Target '$DISK' is not a whole disk or loop device (detected type: ${TARGET_TYPE:-unknown})." ;;
  esac

  if ! TARGET_MAJMINS="$(lsblk -nr -o MAJ:MIN -- "$CANONICAL_DISK" 2>/dev/null)"; then
    shreeos_die "Unable to inspect block-device ancestry for '$DISK'; refusing to partition."
  fi
  [ -n "$TARGET_MAJMINS" ] || shreeos_die "Block-device ancestry for '$DISK' is empty; refusing to partition."

  target_contains_majmin() {
    local majmin="$1"
    [ -n "$majmin" ] || return 1
    grep -Fxq "$majmin" <<< "$TARGET_MAJMINS"
  }

  if ! HOST_ROOT_MM="$(findmnt -n -o MAJ:MIN / 2>/dev/null)"; then
    shreeos_die "Unable to identify the host root filesystem; refusing to partition any disk."
  fi
  if target_contains_majmin "$HOST_ROOT_MM"; then
    shreeos_die "CRITICAL REFUSAL: Target '$DISK' contains the currently running host root filesystem (/)."
  fi

  for protected_mount in /boot /boot/efi /run/initramfs/live /cdrom /mnt/cdrom /run/media; do
    [ -e "$protected_mount" ] || continue
    if mountpoint -q "$protected_mount"; then
      if ! PROTECTED_MM="$(findmnt -n -o MAJ:MIN "$protected_mount" 2>/dev/null)"; then
        shreeos_die "Unable to inspect protected mount $protected_mount; refusing to partition."
      fi
      if target_contains_majmin "$PROTECTED_MM"; then
        shreeos_die "CRITICAL REFUSAL: Target '$DISK' backs protected mount $protected_mount."
      fi
    fi
  done

  if ! MOUNTED_FILESYSTEMS="$(findmnt -r -n -o MAJ:MIN,TARGET 2>/dev/null)"; then
    shreeos_die "Unable to enumerate mounted filesystems; refusing to partition."
  fi
  while read -r mounted_mm mounted_target; do
    [ -n "$mounted_mm" ] || continue
    case "$mounted_mm" in
      0:*) continue ;;
    esac
    if target_contains_majmin "$mounted_mm"; then
      shreeos_die "CRITICAL REFUSAL: Target '$DISK' contains an active filesystem mounted at '$mounted_target'."
    fi
  done <<< "$MOUNTED_FILESYSTEMS"

  if command -v swapon >/dev/null 2>&1; then
    if ! ACTIVE_SWAP="$(swapon --show --noheadings --raw --output MAJ:MIN 2>/dev/null)"; then
      shreeos_die "Unable to enumerate active swap; refusing to partition."
    fi
    while read -r swap_mm; do
      [ -n "$swap_mm" ] || continue
      if target_contains_majmin "$swap_mm"; then
        shreeos_die "CRITICAL REFUSAL: Target '$DISK' contains active swap."
      fi
    done <<< "$ACTIVE_SWAP"
  fi
fi

# 2. Interactive Confirmation (Unless --yes specified)
if [ "$ASSUME_YES" = false ]; then
  echo ""
  echo "=========================================================================="
  echo " WARNING: ALL EXISTING DATA ON ${DISK} WILL BE PERMANENTLY DESTROYED!"
  echo "=========================================================================="
  read -r -p " Type 'YES' in all caps to proceed with partitioning: " CONFIRM
  if [ "$CONFIRM" != "YES" ]; then
    shreeos_die "Partitioning cancelled by user."
  fi
fi

shreeos_step "Partitioning target disk ${DISK} with GPT layout"

# 3. Create GPT partition table with sfdisk
# Partition 1: BIOS Boot (2MB, type 21686148-6449-6E6F-744E-656564454649)
# Partition 2: EFI System Partition (512MB, type C12A7328-F81F-11D2-BA4B-00A0C93EC93B)
# Partition 3: Linux Root Filesystem (Remaining space, type 0FC63DAF-8483-4772-8E79-3D69D8477DE4)

sfdisk --wipe always --label gpt "$DISK" <<EOF
label: gpt
start=2048, size=4096, type=21686148-6449-6E6F-744E-656564454649, name="BIOS-Boot"
size=1048576, type=C12A7328-F81F-11D2-BA4B-00A0C93EC93B, name="EFI-System"
type=0FC63DAF-8483-4772-8E79-3D69D8477DE4, name="ShreeOS-Root"
EOF

shreeos_ok "Successfully created GPT partition table on ${DISK}"
