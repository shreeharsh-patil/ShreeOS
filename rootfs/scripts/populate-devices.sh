#!/usr/bin/env bash
# rootfs/scripts/populate-devices.sh — Populate essential character device nodes in target rootfs /dev
#
# Usage:
#   bash populate-devices.sh <target-rootfs>
#
set -euo pipefail

if [ $# -lt 1 ]; then
  echo "Usage: populate-devices.sh <target-rootfs>" >&2
  exit 1
fi

TARGET="$1"
DEVDIR="${TARGET}/dev"

mkdir -p "$DEVDIR"

if ! command -v mknod &>/dev/null; then
  echo "mknod is required to create the initramfs console device" >&2
  exit 1
fi

ensure_device() {
  local name="$1"
  local major="$2"
  local minor="$3"
  local mode="$4"
  local path="${DEVDIR}/${name}"
  local actual=""

  if [ -c "$path" ]; then
    actual="$(stat -c '%t:%T' -- "$path")"
  fi
  if [ "$actual" != "${major}:${minor}" ]; then
    rm -f -- "$path"
    if ! mknod -m "$mode" "$path" c "$major" "$minor"; then
      echo "Failed to create required character device ${path} (${major}:${minor})" >&2
      exit 1
    fi
  fi
  if [ ! -c "$path" ] || [ "$(stat -c '%t:%T' -- "$path")" != "${major}:${minor}" ]; then
    echo "Required character device was not created correctly: ${path}" >&2
    exit 1
  fi
  chmod "$mode" -- "$path"
}

ensure_device console 5 1 600
ensure_device null 1 3 666
ensure_device zero 1 5 666
ensure_device tty 5 0 666
ensure_device random 1 8 666
ensure_device urandom 1 9 666

echo "Populated device nodes in ${DEVDIR}"
