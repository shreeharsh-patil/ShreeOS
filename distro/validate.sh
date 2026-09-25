#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ISO="${1:-$(find "${SCRIPT_DIR}/out" -maxdepth 1 -type f -name 'ShreeOS-*.iso' -print -quit)}"

[[ -n "${ISO}" && -s "${ISO}" ]] || { echo "error: ShreeOS ISO not found" >&2; exit 1; }
command -v xorriso >/dev/null
command -v unsquashfs >/dev/null

# Reject the tiny/headless-image failure mode: the production desktop image must
# contain a real desktop, firmware and security toolset.
SIZE_BYTES="$(stat -c '%s' "${ISO}")"
if (( SIZE_BYTES < 1073741824 )); then
  echo "error: ISO is unexpectedly small (${SIZE_BYTES} bytes); refusing desktop certification" >&2
  exit 1
fi

REPORT="$(xorriso -indev "${ISO}" -report_el_torito plain 2>&1)"
grep -qi 'El Torito' <<<"${REPORT}" || { echo "error: ISO has no El Torito boot catalog" >&2; exit 1; }

LISTING="$(xorriso -indev "${ISO}" -find / -type f -print 2>/dev/null)"
grep -q '/live/filesystem.squashfs' <<<"${LISTING}" || { echo "error: missing live filesystem" >&2; exit 1; }
grep -Eq '/install\.(amd|386)/|/d-i/' <<<"${LISTING}" || { echo "error: Debian Installer payload not found" >&2; exit 1; }

TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"' EXIT
xorriso -osirrox on -indev "${ISO}" -extract /live/filesystem.squashfs "${TMP}/filesystem.squashfs" >/dev/null 2>&1

assert_file() {
  local path="$1"
  unsquashfs -ll "${TMP}/filesystem.squashfs" "${path#/}" 2>/dev/null | grep -q "${path#/}" || {
    echo "error: live filesystem missing ${path}" >&2
    exit 1
  }
}

OS_RELEASE="$(unsquashfs -cat "${TMP}/filesystem.squashfs" etc/os-release 2>/dev/null)"
grep -q '^NAME="ShreeOS"$' <<<"${OS_RELEASE}" || { echo "error: image identity is not ShreeOS" >&2; exit 1; }
grep -q '^ID=shreeos$' <<<"${OS_RELEASE}" || { echo "error: os-release ID is not shreeos" >&2; exit 1; }

assert_file /usr/share/backgrounds/shreeos/shreeos-wallpaper.svg
assert_file /usr/bin/gnome-shell
assert_file /usr/bin/firefox-esr
assert_file /usr/bin/nmap
assert_file /usr/bin/aircrack-ng
assert_file /usr/sbin/debian-installer-launcher

SHA_FILE="${ISO}.sha256"
if [[ -f "${SHA_FILE}" ]]; then
  (cd "$(dirname "${ISO}")" && sha256sum -c "$(basename "${SHA_FILE}")")
fi

echo "ShreeOS desktop ISO validation passed: ${ISO}"
