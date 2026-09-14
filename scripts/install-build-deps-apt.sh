#!/usr/bin/env bash
# Install the supported Debian/Ubuntu host dependencies used to build ShreeOS.
set -Eeuo pipefail

if ! command -v apt-get >/dev/null 2>&1; then
  echo "[fail] apt-get was not found. This helper supports Debian/Ubuntu hosts." >&2
  exit 1
fi

if [ "$(id -u)" -eq 0 ]; then
  SUDO=""
elif command -v sudo >/dev/null 2>&1; then
  SUDO="sudo"
else
  echo "[fail] sudo is required when not running as root." >&2
  exit 1
fi

export DEBIAN_FRONTEND=noninteractive

$SUDO apt-get update
$SUDO apt-get install -y --no-install-recommends \
  git ca-certificates build-essential gcc g++ make \
  bison flex gawk texinfo gperf \
  curl wget patch file rsync \
  bzip2 gzip xz-utils tar cpio bc \
  pkg-config gettext-base \
  libgmp-dev libmpfr-dev libmpc-dev \
  libssl-dev libelf-dev libcrypt-dev \
  xorriso mtools dosfstools \
  grub-pc-bin grub-efi-amd64-bin grub-common \
  qemu-system-x86 ovmf \
  libx11-dev libxinerama-dev libxft-dev \
  shellcheck

echo "[ok] ShreeOS host build dependencies installed."
