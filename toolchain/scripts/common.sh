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

export PATH="$LUMEN_TOOLS/bin:${PATH}"

mkdir -p "$LUMEN_BUILD_DIR/sources"
mkdir -p "$LUMEN_TOOLS/bin"
mkdir -p "$LUMEN_SYSROOT/usr"

lumen_verify_toolchain() {
  local missing=()
  for cmd in gcc g++ make bison flex gawk curl patch bzip2 xz; do
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
}
