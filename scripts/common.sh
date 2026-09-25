#!/usr/bin/env bash
# scripts/common.sh — shared helpers sourced by every build script in the repo.
#
# Usage from any stage script:
#   REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
#   source "${REPO_ROOT}/build.conf"
#   source "${REPO_ROOT}/scripts/common.sh"

set -euo pipefail

SHREEOS_REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [ -z "${SOURCE_DATE_EPOCH:-}" ]; then
  SOURCE_DATE_EPOCH="$(git -C "$SHREEOS_REPO_ROOT" log -1 --format=%ct 2>/dev/null || printf '0')"
fi
if ! [[ "$SOURCE_DATE_EPOCH" =~ ^[0-9]+$ ]]; then
  printf 'SOURCE_DATE_EPOCH must be an integer, got: %s\n' "$SOURCE_DATE_EPOCH" >&2
  exit 1
fi
export SOURCE_DATE_EPOCH
export LC_ALL=C
export TZ=UTC
umask 022

if [[ -z ${NO_COLOR+x} ]] && [[ -t 1 ]] && [[ -t 2 ]]; then
  shreeos_log()  { printf '\033[1;34m[shreeos]\033[0m %s\n' "$*"; }
  shreeos_ok()   { printf '\033[1;32m[  ok   ]\033[0m %s\n' "$*"; }
  shreeos_warn() { printf '\033[1;33m[ warn  ]\033[0m %s\n' "$*" >&2; }
  shreeos_die()  { printf '\033[1;31m[ fail  ]\033[0m %s\n' "$*" >&2; exit 1; }
else
  shreeos_log()  { printf '[shreeos] %s\n' "$*"; }
  shreeos_ok()   { printf '[  ok   ] %s\n' "$*"; }
  shreeos_warn() { printf '[ warn  ] %s\n' "$*" >&2; }
  shreeos_die()  { printf '[ fail  ] %s\n' "$*" >&2; exit 1; }
fi

# Legacy aliases
lumen_log()  { shreeos_log "$@"; }
lumen_ok()   { shreeos_ok "$@"; }
lumen_warn() { shreeos_warn "$@"; }
lumen_die()  { shreeos_die "$@"; }

# shreeos_fetch <url> <dest-file> <sha256>
# Downloads a source tarball and verifies it before publishing it into the
# shared source cache. Invalid cached/downloaded files are never retained.
# GNU sources automatically fall back to independent HTTPS mirrors when the
# canonical ftp.gnu.org endpoint is temporarily unreachable from CI runners.
shreeos_fetch() {
  local url="$1" dest="$2" expected_sha="$3"
  local actual_sha="" tmp attempt candidate rel
  local downloaded=0
  local -a urls=("$url")

  if [[ ! "${expected_sha}" =~ ^[0-9a-fA-F]{64}$ ]]; then
    shreeos_die "Invalid SHA-256 pin for $(basename "${dest}"): ${expected_sha}"
  fi

  if [[ -L "${dest}" ]]; then
    shreeos_warn "Discarding symlink source cache: ${dest}"
    rm -f -- "${dest}"
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

  if [[ "$url" == https://ftp.gnu.org/gnu/* ]]; then
    rel="${url#https://ftp.gnu.org/gnu/}"
    urls+=(
      "https://ftpmirror.gnu.org/${rel}"
      "https://mirrors.kernel.org/gnu/${rel}"
    )
  fi

  tmp="${dest}.part.${BASHPID}"
  rm -f -- "${tmp}"

  for candidate in "${urls[@]}"; do
    for attempt in 1 2; do
      shreeos_log "Fetching $(basename "${dest}") from ${candidate} (attempt ${attempt}/2) ..."
      local -a curl_args=(--fail --location --retry 2 --retry-all-errors --connect-timeout 15 --max-time 600 --output "${tmp}")
      if [[ "${candidate}" == file://* ]]; then
        if [[ "${SHREEOS_ALLOW_FILE_FETCH:-0}" != "1" ]]; then
          rm -f -- "${tmp}"
          shreeos_die "file:// source URLs are allowed only in isolated tests"
        fi
      else
        if [[ "${candidate}" != https://* ]]; then
          rm -f -- "${tmp}"
          shreeos_die "Only HTTPS source URLs are allowed: ${candidate}"
        fi
        curl_args+=(--proto '=https' --proto-redir '=https')
      fi

      if ! curl "${curl_args[@]}" "${candidate}"; then
        rm -f -- "${tmp}"
        if (( attempt < 2 )); then
          shreeos_warn "Download failed; retrying source fetch from ${candidate}"
        else
          shreeos_warn "Source endpoint unavailable: ${candidate}"
        fi
        continue
      fi

      downloaded=1
      actual_sha="$(sha256sum "${tmp}" | awk '{print $1}')"
      if [[ "${actual_sha}" == "${expected_sha}" ]]; then
        mv -f -- "${tmp}" "${dest}"
        shreeos_ok "Verified checksum for $(basename "${dest}")"
        return 0
      fi

      rm -f -- "${tmp}"
      shreeos_warn "Downloaded checksum mismatch for $(basename "${dest}") from ${candidate}; trying another attempt or mirror"
    done
  done

  if (( downloaded == 0 )); then
    shreeos_die "Failed to download ${url} from all configured HTTPS endpoints"
  fi
  shreeos_die "Checksum mismatch for ${dest}: expected ${expected_sha}, got ${actual_sha}"
}

# Most callers want fetch progress on stdout. Native desktop package preparation
# captures a function's stdout to obtain an extracted source path; in that mode
# send fetch/status chatter to stderr so it cannot corrupt the captured path.
lumen_fetch() {
  if [[ "${LUMEN_FETCH_STDERR:-0}" == "1" ]]; then
    shreeos_fetch "$@" >&2
  else
    shreeos_fetch "$@"
  fi
}

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
