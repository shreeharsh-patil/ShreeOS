#!/usr/bin/env bash
# scripts/common.sh — shared helpers sourced by every build script in the repo.
#
# Usage from any stage script:
#   REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
#   source "${REPO_ROOT}/build.conf"
#   source "${REPO_ROOT}/scripts/common.sh"

set -euo pipefail

shreeos_log()  { printf '\033[1;34m[shreeos]\033[0m %s\n' "$*"; }
shreeos_ok()   { printf '\033[1;32m[  ok   ]\033[0m %s\n' "$*"; }
shreeos_warn() { printf '\033[1;33m[ warn  ]\033[0m %s\n' "$*" >&2; }
shreeos_die()  { printf '\033[1;31m[ fail  ]\033[0m %s\n' "$*" >&2; exit 1; }

# Legacy aliases
lumen_log()  { shreeos_log "$@"; }
lumen_ok()   { shreeos_ok "$@"; }
lumen_warn() { shreeos_warn "$@"; }
lumen_die()  { shreeos_die "$@"; }

# shreeos_fetch <url> <dest-file> <sha256>
# Downloads a source tarball and verifies it before publishing it into the
# shared source cache. Invalid cached/downloaded files are never retained.
shreeos_fetch() {
  local url="$1" dest="$2" expected_sha="$3"
  local actual_sha tmp attempt

  if [[ ! "${expected_sha}" =~ ^[0-9a-fA-F]{64}$ ]]; then
    shreeos_die "Invalid SHA-256 pin for $(basename "${dest}"): ${expected_sha}"
  fi

  if [[ -f "${dest}" ]]; then
    actual_sha="$(sha256sum "${dest}" | awk '{print $1}')"
    if [[ "${actual_sha}" == "${expected_sha}" ]]; then
      shreeos_log "Using verified cached source: $(basename "${dest}")"
      shreeos_ok "Verified checksum for $(basename "${dest}")"
      return 0
    fi

    shreeos_warn "Discarding invalid cached source $(basename "${dest}"): expected ${expected_sha}, got ${actual_sha}"
    rm -f -- "${dest}"
  fi

  tmp="${dest}.part.${BASHPID}"
  rm -f -- "${tmp}"

  for attempt in 1 2; do
    shreeos_log "Fetching $(basename "${dest}") (attempt ${attempt}/2) ..."
    if ! curl -fL --retry 3 --retry-all-errors --connect-timeout 20 -o "${tmp}" "${url}"; then
      rm -f -- "${tmp}"
      if (( attempt < 2 )); then
        shreeos_warn "Download failed; retrying source fetch from ${url}"
        continue
      fi
      shreeos_die "Failed to download ${url}"
    fi

    actual_sha="$(sha256sum "${tmp}" | awk '{print $1}')"
    if [[ "${actual_sha}" == "${expected_sha}" ]]; then
      mv -f -- "${tmp}" "${dest}"
      shreeos_ok "Verified checksum for $(basename "${dest}")"
      return 0
    fi

    rm -f -- "${tmp}"
    if (( attempt < 2 )); then
      shreeos_warn "Downloaded checksum mismatch for $(basename "${dest}"); retrying"
    fi
  done

  shreeos_die "Checksum mismatch for ${dest}: expected ${expected_sha}, got ${actual_sha}"
}
lumen_fetch() { shreeos_fetch "$@"; }

# shreeos_step <description> -- runs and logs a labeled build step
shreeos_step() {
  shreeos_log "==> $*"
}
lumen_step() { shreeos_step "$@"; }

# shreeos_require_cmd <cmd> [<cmd> ...] — fail fast with a clear message
shreeos_require_cmd() {
  local missing=()
  for c in "$@"; do
    command -v "${c}" >/dev/null 2>&1 || missing+=("${c}")
  done
  if (( ${#missing[@]} > 0 )); then
    shreeos_die "Missing required commands: ${missing[*]}"
  fi
}
lumen_require_cmd() { shreeos_require_cmd "$@"; }

