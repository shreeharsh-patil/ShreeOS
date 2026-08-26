#!/usr/bin/env bash
# toolchain/scripts/common.sh — shared helpers for toolchain build scripts
set -euo pipefail

LUMEN_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LUMEN_ROOT_DIR="$(cd "$LUMEN_SCRIPT_DIR/../.." && pwd)"

if [ -f "$LUMEN_ROOT_DIR/build.conf" ]; then
  source "$LUMEN_ROOT_DIR/build.conf"
fi
if [ -f "$LUMEN_ROOT_DIR/scripts/common.sh" ]; then
  source "$LUMEN_ROOT_DIR/scripts/common.sh"
fi
if [ -f "$LUMEN_SCRIPT_DIR/sources.list" ]; then
  source "$LUMEN_SCRIPT_DIR/sources.list"
fi

export PATH="$LUMEN_TOOLS/bin:${PATH}"
export PKG_CONFIG_SYSROOT_DIR="$LUMEN_SYSROOT"
export PKG_CONFIG_LIBDIR="$LUMEN_SYSROOT/usr/lib/pkgconfig:$LUMEN_SYSROOT/usr/share/pkgconfig"
export PKG_CONFIG_PATH=""

mkdir -p "$LUMEN_BUILD_DIR/sources"
mkdir -p "$LUMEN_TOOLS/bin"
mkdir -p "$LUMEN_SYSROOT/usr"

lumen_verify_toolchain() {
  local missing=()
  for cmd in gcc g++ make bison flex gawk curl patch bzip2 xz gperf; do
    if ! command -v "$cmd" &>/dev/null; then
      missing+=("$cmd")
    fi
  done
  if ! command -v makeinfo &>/dev/null && ! command -v texi2any &>/dev/null; then
    missing+=("makeinfo")
  fi
  if [ ${#missing[@]} -gt 0 ]; then
    lumen_die "Missing host build tools: ${missing[*]}"
  fi
  lumen_ok "All required host build tools found"
  if command -v dpkg >/dev/null 2>&1; then
    for package in libgmp-dev libmpfr-dev libmpc-dev; do
      dpkg -s "$package" >/dev/null 2>&1 || lumen_die "Missing host GCC prerequisite: $package"
    done
  fi
}
