#!/usr/bin/env bash
# 35-kmod.sh — Build kmod (modprobe, lsmod, insmod, rmmod, depmod)
#
# The build explicitly excludes libcrypto/zstd compression of module indexes
# so the dependency chain stays small; depmod then writes plain indexes which
# the kernel and modprobe read without extra libraries.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

PKG_NAME="kmod"
PKG_VER="$(pkg_version "$PKG_NAME")"
ARCHIVE="$(pkg_archive "$PKG_NAME")"
SRCDIR="$(base_pkg_extract "$PKG_NAME")"
BUILDDIR="$(pkg_builddir "$PKG_NAME")"

lumen_step "Building ${PKG_NAME}-${PKG_VER}"

mkdir -p "$BUILDDIR" && cd "$BUILDDIR"

"${SRCDIR}/configure" \
  --prefix=/usr \
  --build="$(gcc -dumpmachine)" \
  --host="${LUMEN_TARGET_TRIPLET}" \
  --target="${LUMEN_TARGET_TRIPLET}" \
  --sysconfdir=/etc \
  --with-bashcompletiondir=/usr/share/bash-completion/completions \
  --disable-debug \
  --without-xz \
  --without-zstd \
  --without-zlib

make -j"${LUMEN_MAKE_JOBS}"
make DESTDIR="${LUMEN_STAGE_ROOT}" install

base_sync_sysroot

# kmod installs only the multi-call binary plus libkmod; the traditional
# tool names are symlinks that modprobe and friends are invoked through.
[ -e "${LUMEN_STAGE_ROOT}/usr/bin/kmod" ] || \
  lumen_die "Target kmod multi-call binary was not staged"
for tool in modprobe depmod insmod lsmod rmmod modinfo; do
  ln -sfn kmod "${LUMEN_STAGE_ROOT}/usr/bin/${tool}"
done
mkdir -p "${LUMEN_STAGE_ROOT}/sbin"
ln -sfn ../usr/bin/kmod "${LUMEN_STAGE_ROOT}/sbin/modprobe"
ln -sfn ../usr/bin/kmod "${LUMEN_STAGE_ROOT}/sbin/depmod"

lumen_ok "${PKG_NAME}-${PKG_VER} built successfully"
