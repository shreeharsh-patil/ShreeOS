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

# Flex 2.6.4 is old enough that its Autoconf allocation probes cannot be run
# while cross-compiling.  When those probes are left unresolved, configure
# pessimistically maps malloc/realloc to rpl_malloc/rpl_realloc.  The generated
# scanner then sees only implicit declarations; modern GCC treats that as a
# hard error (and older GCC can produce a pointer-truncating stage1flex).
#
# ShreeOS targets glibc, whose malloc(0)/realloc(0) behaviour is compatible
# with the assumptions Flex needs here, so seed those two cache answers.
# HELP2MAN is also intentionally disabled for the target build.
ac_cv_func_malloc_0_nonnull=yes \
ac_cv_func_realloc_0_nonnull=yes \
HELP2MAN=/bin/true \
"${SRCDIR}/configure" \
  --prefix=/usr \
  --build="$(gcc -dumpmachine)" \
  --host="${LUMEN_TARGET_TRIPLET}" \
  --target="${LUMEN_TARGET_TRIPLET}" \
  --disable-bootstrap \
  --docdir="/usr/share/doc/flex-${PKG_VER}"

make -j"${LUMEN_MAKE_JOBS}"
make DESTDIR="${LUMEN_STAGE_ROOT}" install

# Create lex symlink
ln -sf flex "${LUMEN_STAGE_ROOT}/usr/bin/lex" 2>/dev/null || true

lumen_ok "${PKG_NAME}-${PKG_VER} built successfully"
