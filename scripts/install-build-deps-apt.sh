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

# The unified image entry point (scripts/build-shreeos.sh) requires live-build,
# debootstrap, squashfs-tools, dpkg-dev, librsvg2-bin and debian-archive-keyring
# in addition to the source-build toolchain. They are installed here so a host
# prepared by this script can actually build the release artifact instead of
# failing the environment validation with an empty tool list.
"${APT[@]}" update
"${APT[@]}" install -y --no-install-recommends \
  git ca-certificates python3 python3-venv python3-mako python3-yaml python3-xcbgen perl \
  build-essential gcc g++ make autoconf automake libtool libtool-bin \
  meson ninja-build bison flex gawk texinfo gperf \
  curl wget patch file rsync xsltproc libxml2-utils \
  bzip2 gzip xz-utils tar cpio bc fakeroot \
  pkg-config gettext gettext-base autopoint x11-xkb-utils xutils-dev \
  libgmp-dev libmpfr-dev libmpc-dev \
  libssl-dev libelf-dev libcrypt-dev openssl \
  xorriso mtools dosfstools fdisk util-linux e2fsprogs kmod \
  grub-pc-bin grub-efi-amd64-bin grub-common grub2-common \
  qemu-system-x86 ovmf \
  shellcheck \
  live-build debootstrap squashfs-tools dpkg-dev librsvg2-bin \
  debian-archive-keyring rsync

# scripts/build-shreeos.sh only accepts the live-build version pinned in
# prototype/debian-live/versions.conf. Report drift here, where the fix (add the
# matching suite snapshot or install the pinned version) is obvious, instead of
# letting the image build refuse to start.
# shellcheck source=../prototype/debian-live/versions.conf
. "$(dirname "${BASH_SOURCE[0]}")/../prototype/debian-live/versions.conf"
installed_live_build="$(dpkg-query -W -f='${Version}' live-build 2>/dev/null || true)"
if [ "$installed_live_build" != "$LIVE_BUILD_VERSION" ]; then
  printf '[warn] live-build %s is installed but the image contract pins %s; scripts/build-shreeos.sh will refuse to build until they match.\n' \
    "${installed_live_build:-none}" "$LIVE_BUILD_VERSION" >&2
fi

# libxcb's source generator runs on the build host even though libxcb itself is
# cross-compiled for ShreeOS. Check that the module can be located without
# importing xcbgen.state directly: that module is designed to run inside
# libxcb's c_client.py context and expects generator globals in __main__.
python3 -c 'import importlib.util; assert importlib.util.find_spec("xcbgen.state") is not None' >/dev/null

echo "[ok] ShreeOS host build dependencies installed."
