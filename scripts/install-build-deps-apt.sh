#!/usr/bin/env bash
# Install the supported Debian/Ubuntu host dependencies used to build ShreeOS.
set -Eeuo pipefail

if ! command -v apt-get >/dev/null 2>&1; then
  echo "[fail] apt-get was not found. This helper supports Debian/Ubuntu hosts." >&2
  exit 1
fi

if [ "$(id -u)" -eq 0 ]; then
  APT=(apt-get)
elif command -v sudo >/dev/null 2>&1; then
  APT=(sudo apt-get)
else
  echo "[fail] sudo is required when not running as root." >&2
  exit 1
fi

export DEBIAN_FRONTEND=noninteractive

"${APT[@]}" update
"${APT[@]}" install -y --no-install-recommends \
  git ca-certificates python3 python3-venv python3-mako python3-yaml perl \
  build-essential gcc g++ make autoconf automake libtool libtool-bin \
  meson ninja-build bison flex gawk texinfo gperf \
  curl wget patch file rsync xsltproc libxml2-utils \
  bzip2 gzip xz-utils tar cpio bc fakeroot \
  pkg-config gettext gettext-base x11-xkb-utils xutils-dev \
  libgmp-dev libmpfr-dev libmpc-dev \
  libssl-dev libelf-dev libcrypt-dev \
  xorriso mtools dosfstools fdisk util-linux e2fsprogs kmod \
  grub-pc-bin grub-efi-amd64-bin grub-common grub2-common \
  qemu-system-x86 ovmf \
  shellcheck

echo "[ok] ShreeOS host build dependencies installed."
