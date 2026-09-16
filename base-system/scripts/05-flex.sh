#!/usr/bin/env bash
# 05-flex.sh — Build flex (lexer generator)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

PKG_NAME="flex"
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
  --docdir="${LUMEN_STAGE_ROOT}/usr/share/doc/flex-${PKG_VER}"

make -j"${LUMEN_MAKE_JOBS}"
make install

# Create lex symlink
ln -sf flex "${LUMEN_STAGE_ROOT}/usr/bin/lex" 2>/dev/null || true

lumen_ok "${PKG_NAME}-${PKG_VER} built successfully"
