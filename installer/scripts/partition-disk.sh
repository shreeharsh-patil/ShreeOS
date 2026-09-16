#!/usr/bin/env bash
# installer/scripts/partition-disk.sh — Disk partitioning utility for ShreeOS installer
#
# Formats target disk with GPT partition table (BIOS Boot + rootfs ext4).
#
# Usage:
#   bash partition-disk.sh <disk-device> [--yes]
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LUMEN_ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$LUMEN_ROOT_DIR/build.conf" 2>/dev/null || true
source "$LUMEN_ROOT_DIR/scripts/common.sh" 2>/dev/null || {
  lumen_step() { echo "==> $1"; }
  lumen_log() { echo "  -> $1"; }
  lumen_ok() { echo "  [OK] $1"; }
  lumen_warn() { echo "  [WARN] $1"; }
  lumen_die() { echo "  [ERROR] $1" >&2; exit 1; }
}

if [ $# -lt 1 ]; then
  lumen_die "Usage: partition-disk.sh <disk-device> [--yes]"
fi

DISK="$1"
ASSUME_YES=false
if [ "${2:-}" = "--yes" ]; then
  ASSUME_YES=true
fi

lumen_require_cmd sfdisk

if [ "$ASSUME_YES" = false ]; then
  echo ""
  echo "=========================================================="
  echo " WARNING: ALL DATA ON ${DISK} WILL BE PERMANENTLY ERASED! "
  echo "=========================================================="
  read -r -p "Are you sure you want to partition ${DISK}? [y/N] " CONFIRM
  if [ "$CONFIRM" != "y" ] && [ "$CONFIRM" != "Y" ]; then
    lumen_die "Partitioning aborted by user"
  fi
fi

lumen_step "Writing GPT partition table to ${DISK}"

sfdisk "$DISK" <<EOF
label: gpt
size=512M, type=21686148-6449-6E6F-744E-656564454649, name="BIOS"
size=+, type=0FC63DAF-8483-4772-8E79-3D69D8477DE4, name="root"
EOF

sleep 1
lumen_ok "Successfully partitioned ${DISK}"
