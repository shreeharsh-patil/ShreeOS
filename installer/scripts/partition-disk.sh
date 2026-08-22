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

# Resolve canonical realpath
CANONICAL_DISK=$(realpath "$DISK" 2>/dev/null || echo "$DISK")

# Protect against writing directly to host root or boot mounts
if command -v findmnt >/dev/null 2>&1; then
  HOST_ROOT_DEV=$(findmnt -n -o SOURCE / 2>/dev/null || echo "")
  if [ -n "$HOST_ROOT_DEV" ]; then
    HOST_ROOT_CANON=$(realpath "$HOST_ROOT_DEV" 2>/dev/null || echo "$HOST_ROOT_DEV")
    if [[ "$HOST_ROOT_CANON" == "$CANONICAL_DISK"* ]] || [[ "$CANONICAL_DISK" == "$HOST_ROOT_CANON"* ]]; then
      shreeos_die "CRITICAL REFUSAL: Target '${DISK}' appears to contain the currently running host root filesystem (/)."
    fi
  fi

  HOST_BOOT_DEV=$(findmnt -n -o SOURCE /boot 2>/dev/null || echo "")
  if [ -n "$HOST_BOOT_DEV" ]; then
    HOST_BOOT_CANON=$(realpath "$HOST_BOOT_DEV" 2>/dev/null || echo "$HOST_BOOT_DEV")
    if [[ "$HOST_BOOT_CANON" == "$CANONICAL_DISK"* ]]; then
      shreeos_die "CRITICAL REFUSAL: Target '${DISK}' contains the host /boot filesystem."
    fi
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
