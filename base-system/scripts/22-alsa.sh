#!/usr/bin/env bash
# ALSA library and amixer backend used by the optional ShreeOS audio module.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; source "$SCRIPT_DIR/common.sh"
build_alsa() {
  local name="$1" version="$2" sha="$3" type="$4"
  local url="https://www.alsa-project.org/files/pub/${type}/${name}-${version}.tar.bz2"
  local archive="${LUMEN_BUILD_DIR}/sources/${name}-${version}.tar.bz2" source="${LUMEN_BUILD_DIR}/sources/${name}-${version}"
  lumen_fetch "$url" "$archive" "$sha"; [ -d "$source" ] || tar -xjf "$archive" -C "${LUMEN_BUILD_DIR}/sources"
  mkdir -p "${LUMEN_BUILD_DIR}/build-${name}"; cd "${LUMEN_BUILD_DIR}/build-${name}"
  "$source/configure" --prefix=/usr --host="${LUMEN_TARGET_TRIPLET}" --disable-nls
  make -j"${LUMEN_MAKE_JOBS}"; make DESTDIR="${LUMEN_STAGE_ROOT}" install
}
build_alsa alsa-lib 1.2.14 be9c88a0b3604367dd74167a2b754a35e142f670292ae47a2fdef27a2ee97a32 lib
mkdir -p "${LUMEN_SYSROOT}/usr"
cp -a "${LUMEN_STAGE_ROOT}/usr/include" "${LUMEN_SYSROOT}/usr/"
cp -a "${LUMEN_STAGE_ROOT}/usr/lib" "${LUMEN_SYSROOT}/usr/"
build_alsa alsa-utils 1.2.14 0794c74d33fed943e7c50609c13089e409312b6c403d6ae8984fc429c0960741 utils