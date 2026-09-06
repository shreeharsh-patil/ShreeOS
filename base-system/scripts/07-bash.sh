#!/usr/bin/env bash
# 07-bash.sh — Build bash (Bourne-Again SHell)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

PKG_NAME="bash"
PKG_VER="$(pkg_version "$PKG_NAME")"
PKG_URL="$(pkg_url "$PKG_NAME")"
PKG_SHA256="$(pkg_sha256 "$PKG_NAME")"
ARCHIVE="$(pkg_archive "$PKG_NAME")"
SRCDIR="$(pkg_srcdir "$PKG_NAME")"
BUILDDIR="$(pkg_builddir "$PKG_NAME")"

lumen_step "Building ${PKG_NAME}-${PKG_VER}"

lumen_fetch "$PKG_URL" "${BASE_SOURCES}/${ARCHIVE}" "$PKG_SHA256"

if [ ! -d "$SRCDIR" ]; then
  tar -xf "${BASE_SOURCES}/${ARCHIVE}" -C "${BASE_SOURCES}"
fi

mkdir -p "$BUILDDIR" && cd "$BUILDDIR"

"${SRCDIR}/configure" \
  --prefix="${LUMEN_STAGE_ROOT}/usr" \
  --build="$(gcc -dumpmachine)" \
  --host="${LUMEN_TARGET_TRIPLET}" \
  --target="${LUMEN_TARGET_TRIPLET}" \
  --without-bash-malloc \
  --with-installed-readline \
  --docdir="${LUMEN_STAGE_ROOT}/usr/share/doc/bash-${PKG_VER}"

make -j"${LUMEN_MAKE_JOBS}"
make install

# Create /bin/sh symlink for POSIX compat
mkdir -p "${LUMEN_STAGE_ROOT}/bin"
ln -sf ../usr/bin/bash "${LUMEN_STAGE_ROOT}/bin/bash"
ln -sf bash "${LUMEN_STAGE_ROOT}/bin/sh"

lumen_ok "${PKG_NAME}-${PKG_VER} built successfully"
