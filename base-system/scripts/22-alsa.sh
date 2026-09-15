#!/usr/bin/env bash
# ALSA library and amixer backend used by the optional ShreeOS audio module.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

build_alsa() {
  local name="$1"
  local version url sha archive source
  version="$(pkg_version "$name")"
  url="$(pkg_url "$name")"
  sha="$(pkg_sha256 "$name")"
  archive="${LUMEN_BUILD_DIR}/sources/$(pkg_archive "$name")"
  source="${LUMEN_BUILD_DIR}/sources/${name}-${version}"

  lumen_fetch "$url" "$archive" "$sha"
  [ -d "$source" ] || tar -xjf "$archive" -C "${LUMEN_BUILD_DIR}/sources"

  rm -rf "${LUMEN_BUILD_DIR}/build-${name}"
  mkdir -p "${LUMEN_BUILD_DIR}/build-${name}"
  cd "${LUMEN_BUILD_DIR}/build-${name}"

  "$source/configure" --prefix=/usr --host="${LUMEN_TARGET_TRIPLET}" --disable-nls
  make -j"${LUMEN_MAKE_JOBS}"
  make DESTDIR="${LUMEN_STAGE_ROOT}" install
}

build_alsa alsa-lib
base_sync_sysroot
build_alsa alsa-utils
