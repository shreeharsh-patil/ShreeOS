#!/usr/bin/env bash
# build-glibc.sh — Build glibc for the cross-compiler
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

lumen_step "Building glibc — version ${VER_GLIBC}"

PKG="glibc-${VER_GLIBC}"
ARCHIVE="${PKG}.tar.xz"
SRCDIR="${LUMEN_BUILD_DIR}/sources/${PKG}"
BUILDDIR="${LUMEN_BUILD_DIR}/build-glibc"

lumen_fetch "${GLIBC_URL}" "${LUMEN_BUILD_DIR}/sources/${ARCHIVE}" "${GLIBC_SHA256}"

if [ ! -d "$SRCDIR" ]; then
  tar -xJf "${LUMEN_BUILD_DIR}/sources/${ARCHIVE}" -C "${LUMEN_BUILD_DIR}/sources"
fi

mkdir -p "$BUILDDIR"
cd "$BUILDDIR"

"${SRCDIR}/configure" \
  --prefix="${LUMEN_TOOLS}/${LUMEN_TARGET_TRIPLET}" \
  --build="$(gcc -dumpmachine)" \
  --host="${LUMEN_TARGET_TRIPLET}" \
  --target="${LUMEN_TARGET_TRIPLET}" \
  --with-headers="${LUMEN_SYSROOT}/usr/include" \
  --disable-nls \
  libc_cv_slibdir="${LUMEN_TOOLS}/${LUMEN_TARGET_TRIPLET}/lib"

make -j"${LUMEN_MAKE_JOBS}"
make install

if [ ! -f "${LUMEN_TOOLS}/${LUMEN_TARGET_TRIPLET}/lib/libc.so" ]; then
  lumen_die "glibc installation failed — libc.so not found"
fi

lumen_ok "glibc built successfully"
