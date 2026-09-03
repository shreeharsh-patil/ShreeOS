#!/usr/bin/env bash
# build-gcc-pass1.sh — Build GCC cross-compiler (Pass 1, C only, static)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

lumen_step "Building GCC (Pass 1) — version ${VER_GCC}"

PKG="gcc-${VER_GCC}"
ARCHIVE="${PKG}.tar.xz"
SRCDIR="${LUMEN_BUILD_DIR}/sources/${PKG}"
BUILDDIR="${LUMEN_BUILD_DIR}/build-gcc-pass1"

lumen_fetch "${GCC_URL}" "${LUMEN_BUILD_DIR}/sources/${ARCHIVE}" "${GCC_SHA256}"

if [ ! -d "$SRCDIR" ]; then
  tar -xJf "${LUMEN_BUILD_DIR}/sources/${ARCHIVE}" -C "${LUMEN_BUILD_DIR}/sources"
fi

mkdir -p "$BUILDDIR"
cd "$BUILDDIR"

"${SRCDIR}/configure" \
  --prefix="${LUMEN_TOOLS}" \
  --target="${LUMEN_TARGET_TRIPLET}" \
  --with-sysroot="${LUMEN_SYSROOT}" \
  --disable-nls \
  --enable-languages=c \
  --disable-libatomic \
  --disable-libgomp \
  --disable-libquadmath \
  --disable-libssp \
  --disable-libvtv \
  --disable-libstdcxx \
  --disable-multilib

make -j"${LUMEN_MAKE_JOBS}"
make install

echo "Verifying GCC (Pass 1)..."
"${LUMEN_TOOLS}/bin/${LUMEN_TARGET_TRIPLET}-gcc" --version

lumen_ok "GCC (Pass 1) built successfully"
