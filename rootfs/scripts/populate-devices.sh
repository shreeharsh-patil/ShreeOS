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

# Create essential static character device nodes if running with mknod privileges
if command -v mknod &>/dev/null; then
  [ -e "${DEVDIR}/console" ] || mknod -m 622 "${DEVDIR}/console" c 5 1 2>/dev/null || true
  [ -e "${DEVDIR}/null" ]    || mknod -m 666 "${DEVDIR}/null"    c 1 3 2>/dev/null || true
  [ -e "${DEVDIR}/zero" ]    || mknod -m 666 "${DEVDIR}/zero"    c 1 5 2>/dev/null || true
  [ -e "${DEVDIR}/tty" ]     || mknod -m 666 "${DEVDIR}/tty"     c 5 0 2>/dev/null || true
  [ -e "${DEVDIR}/random" ]  || mknod -m 666 "${DEVDIR}/random"  c 1 8 2>/dev/null || true
  [ -e "${DEVDIR}/urandom" ] || mknod -m 666 "${DEVDIR}/urandom" c 1 9 2>/dev/null || true
fi

echo "Populated device nodes in ${DEVDIR}"
