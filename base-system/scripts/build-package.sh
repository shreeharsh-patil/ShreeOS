#!/usr/bin/env bash
# build-package.sh — Build one base-system package from packages.list
# Usage: bash base-system/scripts/build-package.sh <package-name>
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

PACKAGES_LIST="$SCRIPT_DIR/../packages.list"

if [[ $# -lt 1 ]]; then
  lumen_die "Usage: build-package.sh <package-name>" "Packages: ncurses bash coreutils util-linux"
fi

PKG_NAME="$1"
LINE=$(grep -E "^\s*${PKG_NAME}\s+" "$PACKAGES_LIST" | grep -vE '^\s*#' | head -1)

if [[ -z "$LINE" ]]; then
  lumen_die "Package '${PKG_NAME}' not found in ${PACKAGES_LIST}"
fi

read -r _ VER URL SHA256 ARGS <<<"$LINE"

ARCHIVE="${LUMEN_BUILD_DIR}/sources/$(basename "${URL}")"
SRCDIR="${LUMEN_BUILD_DIR}/sources/$(basename "${URL}" .tar.gz)"
SRCDIR="${SRCDIR%.tar.xz}"
BUILDDIR="${LUMEN_BUILD_DIR}/build-${PKG_NAME}"

lumen_step "Building ${PKG_NAME}-${VER}"

lumen_fetch "${URL}" "${ARCHIVE}" "${SHA256}"

if [ ! -d "$SRCDIR" ]; then
  case "${ARCHIVE}" in
    *.tar.xz) tar -xJf "${ARCHIVE}" -C "${LUMEN_BUILD_DIR}/sources" ;;
    *.tar.gz) tar -xzf "${ARCHIVE}" -C "${LUMEN_BUILD_DIR}/sources" ;;
    *)        lumen_die "Unknown archive format: ${ARCHIVE}" ;;
  esac
fi

rm -rf "$BUILDDIR"
mkdir -p "$BUILDDIR"
cd "$BUILDDIR"

# shellcheck disable=SC2086
"${SRCDIR}/configure" \
  --prefix=/usr \
  --build="${MACHTYPE}" \
  --host="${LUMEN_TARGET_TRIPLET}" \
  --target="${LUMEN_TARGET_TRIPLET}" \
  $ARGS

make -j"${LUMEN_MAKE_JOBS}"
make DESTDIR="${LUMEN_STAGE_ROOT}" install

lumen_ok "${PKG_NAME}-${VER} built and installed to ${LUMEN_STAGE_ROOT}"
