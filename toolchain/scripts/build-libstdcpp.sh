#!/usr/bin/env bash
# build-libstdcpp.sh — Build libstdc++ (from GCC source, after glibc)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

lumen_step "Building libstdc++ — from GCC ${VER_GCC}"

PKG="gcc-${VER_GCC}"
SRCDIR="${LUMEN_BUILD_DIR}/sources/${PKG}"
BUILDDIR="${LUMEN_BUILD_DIR}/build-libstdcpp"

if [ ! -d "$SRCDIR" ]; then
  lumen_die "GCC source not found at ${SRCDIR} — run build-gcc-pass1.sh first"
fi

mkdir -p "$BUILDDIR"
cd "$BUILDDIR"

"${SRCDIR}/libstdc++-v3/configure" \
  --prefix="${LUMEN_TOOLS}" \
  --host="${LUMEN_TARGET_TRIPLET}" \
  --build="$(gcc -dumpmachine)" \
  --target="${LUMEN_TARGET_TRIPLET}" \
  --with-gxx-include-dir="${LUMEN_TOOLS}/${LUMEN_TARGET_TRIPLET}/include/c++/${VER_GCC}" \
  --disable-multilib \
  --disable-nls \
  --disable-libstdcxx-pch \
  --with-gcc="${LUMEN_TOOLS}/bin/${LUMEN_TARGET_TRIPLET}-gcc" \
  --with-gxx="${LUMEN_TOOLS}/bin/${LUMEN_TARGET_TRIPLET}-g++"

make -j"${LUMEN_MAKE_JOBS}"
make install

lumen_ok "libstdc++ built successfully"
