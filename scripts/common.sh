#!/usr/bin/env bash
# scripts/common.sh — shared helpers sourced by every build script in the repo.
#
# Usage from any stage script:
#   REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
#   source "${REPO_ROOT}/build.conf"
#   source "${REPO_ROOT}/scripts/common.sh"

set -euo pipefail

lumen_log()  { printf '\033[1;34m[lumen]\033[0m %s\n' "$*"; }
lumen_ok()   { printf '\033[1;32m[ ok ]\033[0m %s\n' "$*"; }
lumen_warn() { printf '\033[1;33m[warn]\033[0m %s\n' "$*" >&2; }
lumen_die()  { printf '\033[1;31m[fail]\033[0m %s\n' "$*" >&2; exit 1; }

# lumen_fetch <url> <dest-file> <sha256>
# Downloads a source tarball and verifies its checksum. Refuses to overwrite
# a file that fails verification.
lumen_fetch() {
  local url="$1" dest="$2" expected_sha="$3"
  if [[ -f "${dest}" ]]; then
    lumen_log "Already downloaded: $(basename "${dest}")"
  else
    lumen_log "Fetching $(basename "${dest}") ..."
    curl -fL --retry 3 -o "${dest}.part" "${url}"
    mv "${dest}.part" "${dest}"
  fi
  local actual_sha
  actual_sha="$(sha256sum "${dest}" | awk '{print $1}')"
  if [[ "${actual_sha}" != "${expected_sha}" ]]; then
    lumen_die "Checksum mismatch for ${dest}: expected ${expected_sha}, got ${actual_sha}"
  fi
  lumen_ok "Verified checksum for $(basename "${dest}")"
}

# lumen_step <description> -- runs and logs a labeled build step
lumen_step() {
  lumen_log "==> $*"
}

# lumen_require_cmd <cmd> [<cmd> ...] — fail fast with a clear message
lumen_require_cmd() {
  local missing=()
  for c in "$@"; do
    command -v "${c}" >/dev/null 2>&1 || missing+=("${c}")
  done
  if (( ${#missing[@]} > 0 )); then
    lumen_die "Missing required commands: ${missing[*]}"
  fi
}
