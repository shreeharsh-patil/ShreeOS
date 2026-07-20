#!/usr/bin/env bash
# build-binutils-pass1.sh — Build binutils for the cross-compiler (Pass 1)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

lumen_step "Building binutils (Pass 1) — version ${VER_BINUTILS}"

PKG="binutils-${VER_BINUTILS}"
ARCHIVE="${PKG}.tar.xz"
SRCDIR="${LUMEN_BUILD_DIR}/sources/${PKG}"
BUILDDIR="${LUMEN_BUILD_DIR}/build-binutils-pass1"

lumen_fetch "${BINUTILS_URL}" "${LUMEN_BUILD_DIR}/sources/${ARCHIVE}" "${BINUTILS_SHA256}"

if [ ! -d "$SRCDIR" ]; then
  tar -xJf "${LUMEN_BUILD_DIR}/sources/${ARCHIVE}" -C "${LUMEN_BUILD_DIR}/sources"
fi

mkdir -p "$BUILDDIR"
cd "$BUILDDIR"

"${SRCDIR}/configure" \
  --prefix="${LUMEN_TOOLS}" \
  --with-sysroot="${LUMEN_SYSROOT}" \
  --target="${LUMEN_TARGET_TRIPLET}" \
  --disable-nls \
  --enable-gprofng=no \
  --disable-werror

make -j"${LUMEN_MAKE_JOBS}"
make install

echo "Verifying binutils..."
"${LUMEN_TOOLS}/bin/${LUMEN_TARGET_TRIPLET}-ld" --version

lumen_ok "binutils (Pass 1) built successfully"
