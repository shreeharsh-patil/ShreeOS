#!/usr/bin/env bash
# build-gcc-pass2.sh — Build full GCC cross-compiler (Pass 2, C/C++ with libc)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

lumen_step "Building GCC (Pass 2) — version ${VER_GCC} with C/C++ and glibc ${VER_GLIBC}"

PKG="gcc-${VER_GCC}"
SRCDIR="${LUMEN_BUILD_DIR}/sources/${PKG}"
BUILDDIR="${LUMEN_BUILD_DIR}/build-gcc-pass2"

if [ ! -d "$SRCDIR" ]; then
  lumen_die "GCC source not found at ${SRCDIR} — run build-gcc-pass1.sh first"
fi

# Ensure pass 1 tools are in PATH for build-time tools
export PATH="${LUMEN_TOOLS}/bin:${LUMEN_TOOLS}/${LUMEN_TARGET_TRIPLET}/bin:${PATH}"

mkdir -p "$BUILDDIR"
cd "$BUILDDIR"

"${SRCDIR}/configure" \
  --prefix="${LUMEN_TOOLS}" \
  --target="${LUMEN_TARGET_TRIPLET}" \
  --with-sysroot="${LUMEN_SYSROOT}" \
  --with-glibc-version="${VER_GLIBC}" \
  --enable-languages=c,c++ \
  --enable-default-pie \
  --enable-default-ssp \
  --disable-nls \
  --disable-multilib \
  --with-gcc="${LUMEN_TOOLS}/bin/${LUMEN_TARGET_TRIPLET}-gcc" \
  --with-gxx="${LUMEN_TOOLS}/bin/${LUMEN_TARGET_TRIPLET}-g++" \
  --with-build-time-tools="${LUMEN_TOOLS}/${LUMEN_TARGET_TRIPLET}/bin"

make -j"${LUMEN_MAKE_JOBS}"
make install

echo "Verifying GCC (Pass 2)..."
"${LUMEN_TOOLS}/bin/${LUMEN_TARGET_TRIPLET}-gcc" --version
"${LUMEN_TOOLS}/bin/${LUMEN_TARGET_TRIPLET}-g++" --version

lumen_ok "GCC (Pass 2) built successfully — full C/C++ cross-compiler ready"
