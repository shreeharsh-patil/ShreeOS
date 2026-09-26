#!/usr/bin/env bash
# Install pinned host-side build tools that are newer than Ubuntu's archive versions.
set -Eeuo pipefail

MESON_VERSION="${MESON_VERSION:-1.6.1}"
HOST_TOOLS_DIR="${SHREEOS_HOST_TOOLS_DIR:-${HOME}/.local/share/shreeos/host-tools}"
LOCAL_BIN="${HOME}/.local/bin"

if ! command -v python3 >/dev/null 2>&1; then
  echo "[fail] python3 is required to bootstrap ShreeOS host tools." >&2
  exit 1
fi

python3 -m venv "${HOST_TOOLS_DIR}"
"${HOST_TOOLS_DIR}/bin/python" -m pip install --disable-pip-version-check --upgrade pip
"${HOST_TOOLS_DIR}/bin/python" -m pip install --disable-pip-version-check "meson==${MESON_VERSION}"

mkdir -p "${LOCAL_BIN}"
ln -sfn "${HOST_TOOLS_DIR}/bin/meson" "${LOCAL_BIN}/meson"

export PATH="${LOCAL_BIN}:${PATH}"
actual_version="$(meson --version)"
if [[ "${actual_version}" != "${MESON_VERSION}" ]]; then
  echo "[fail] Expected Meson ${MESON_VERSION}, got ${actual_version}." >&2
  exit 1
fi

echo "[ok] Meson ${actual_version} installed at ${LOCAL_BIN}/meson"
