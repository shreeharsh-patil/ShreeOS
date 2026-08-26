#!/usr/bin/env bash
# base-system/scripts/common.sh — shared helpers for base system build scripts
set -euo pipefail

BASE_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_ROOT_DIR="$(cd "$BASE_SCRIPT_DIR/../.." && pwd)"

if [ -f "$BASE_ROOT_DIR/build.conf" ]; then
  source "$BASE_ROOT_DIR/build.conf"
fi
if [ -f "$BASE_ROOT_DIR/scripts/common.sh" ]; then
  source "$BASE_ROOT_DIR/scripts/common.sh"
fi

# Base-system-specific directories
BASE_SOURCES="${LUMEN_BUILD_DIR}/sources"
BASE_BUILDDIR="${LUMEN_BUILD_DIR}/base-system"

export PATH="${LUMEN_TOOLS}/bin:${PATH}"
export CC="${LUMEN_TARGET_TRIPLET}-gcc"
export CXX="${LUMEN_TARGET_TRIPLET}-g++"
export AR="${LUMEN_TARGET_TRIPLET}-ar"
export AS="${LUMEN_TARGET_TRIPLET}-as"
export RANLIB="${LUMEN_TARGET_TRIPLET}-ranlib"
export LD="${LUMEN_TARGET_TRIPLET}-ld"
export PKG_CONFIG_SYSROOT_DIR="${LUMEN_SYSROOT}"
export PKG_CONFIG_LIBDIR="${LUMEN_SYSROOT}/usr/lib/pkgconfig:${LUMEN_SYSROOT}/usr/share/pkgconfig"
export PKG_CONFIG_PATH=""
export CPPFLAGS="--sysroot=${LUMEN_SYSROOT}"
export LDFLAGS="--sysroot=${LUMEN_SYSROOT}"
export STRIP="${LUMEN_TARGET_TRIPLET}-strip"

mkdir -p "$BASE_SOURCES" "$BASE_BUILDDIR"

# Look up package info from packages.list
# Usage: pkg_info <name> <field>  where field is 1=name, 2=version, 3=url, 4=sha256
pkg_info() {
  local name="$1"
  local field="$2"
  awk -v n="$name" -v f="$field" \
    '$1 == n { print $f; exit }' \
    "${BASE_ROOT_DIR}/base-system/packages.list"
}

pkg_url()    { pkg_info "$1" 3; }
pkg_sha256() { pkg_info "$1" 4; }
pkg_version(){ pkg_info "$1" 2; }

pkg_archive() {
  local name="$1"
  local url
  url=$(pkg_url "$name")
  basename "$url"
}

pkg_srcdir() {
  local name="$1"
  local ver
  ver=$(pkg_version "$name")
  echo "${BASE_SOURCES}/${name}-${ver}"
}

pkg_builddir() {
  local name="$1"
  echo "${BASE_BUILDDIR}/build-${name}"
}

# Verify cross-compiler exists
base_verify_toolchain() {
  if ! command -v "$CC" &>/dev/null; then
    lumen_die "Cross-compiler not found: ${CC}. Build Phase 1 toolchain first."
  fi
  lumen_ok "Cross-compiler found: $(${CC} --version | head -1)"
}
