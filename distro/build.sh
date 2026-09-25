#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="${SCRIPT_DIR}/.build"
OUT_DIR="${SCRIPT_DIR}/out"
VERSION="${SHREEOS_VERSION:-0.1-dev}"

if [[ ${EUID} -ne 0 ]]; then
  echo "error: ShreeOS ISO builds require root (live-build mounts chroots)." >&2
  exit 1
fi

for command in lb xorriso mksquashfs rsync; do
  command -v "${command}" >/dev/null 2>&1 || {
    echo "error: missing build dependency: ${command}" >&2
    exit 1
  }
done

rm -rf "${BUILD_DIR}"
mkdir -p "${BUILD_DIR}" "${OUT_DIR}"
rsync -a "${SCRIPT_DIR}/auto" "${SCRIPT_DIR}/config" "${BUILD_DIR}/"

cleanup() {
  if [[ -d "${BUILD_DIR}" ]]; then
    (cd "${BUILD_DIR}" && lb clean >/dev/null 2>&1 || true)
  fi
}
trap cleanup EXIT

cd "${BUILD_DIR}"
lb config
lb build

ISO_SOURCE="$(find . -maxdepth 1 -type f \( -name '*.hybrid.iso' -o -name '*.iso' \) -print -quit)"
if [[ -z "${ISO_SOURCE}" ]]; then
  echo "error: live-build completed without producing an ISO" >&2
  exit 1
fi

ISO_NAME="ShreeOS-${VERSION}-amd64.iso"
rm -f "${OUT_DIR}"/*.iso "${OUT_DIR}"/*.sha256
cp -f "${ISO_SOURCE}" "${OUT_DIR}/${ISO_NAME}"
(
  cd "${OUT_DIR}"
  sha256sum "${ISO_NAME}" > "${ISO_NAME}.sha256"
)

echo "Built ${OUT_DIR}/${ISO_NAME}"
