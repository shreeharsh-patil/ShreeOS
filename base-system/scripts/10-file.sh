#!/usr/bin/env bash
# 10-file.sh — Build file (file type detection utility)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

PKG_NAME="file"
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

# file uses its own executable while generating the target magic database.
# A cross-compiled binary cannot run on the build host, and the host's distro
# file may be a different version. Build a matching native helper first.
HOST_BUILDDIR="${BASE_BUILDDIR}/build-file-host"
rm -rf "$HOST_BUILDDIR"
mkdir -p "$HOST_BUILDDIR"
(
  unset CC CXX AR AS RANLIB LD STRIP CPPFLAGS LDFLAGS \
        PKG_CONFIG_SYSROOT_DIR PKG_CONFIG_LIBDIR PKG_CONFIG_PATH
  cd "$HOST_BUILDDIR"
  "${SRCDIR}/configure" \
    --disable-bzlib \
    --disable-libseccomp \
    --disable-xzlib \
    --disable-zlib
  make -j"${LUMEN_MAKE_JOBS}"
)

HOST_FILE="${HOST_BUILDDIR}/src/file"
[ -x "$HOST_FILE" ] || lumen_die "Native file helper was not built: $HOST_FILE"

mkdir -p "$BUILDDIR" && cd "$BUILDDIR"

"${SRCDIR}/configure" \
  --prefix=/usr \
  --build="$(gcc -dumpmachine)" \
  --host="${LUMEN_TARGET_TRIPLET}" \
  --target="${LUMEN_TARGET_TRIPLET}"

make FILE_COMPILE="$HOST_FILE" -j"${LUMEN_MAKE_JOBS}"
make DESTDIR="${LUMEN_STAGE_ROOT}" FILE_COMPILE="$HOST_FILE" install

lumen_ok "${PKG_NAME}-${PKG_VER} built successfully"
