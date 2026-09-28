#!/usr/bin/env bash
# update-pins.sh — Recompute the SHA-256 column of a packages.list manifest.
#
# Every ShreeOS source tarball is pinned by SHA-256 so that a compromised or
# corrupted mirror can never silently feed a different tree into the build.
# This tool is the supported way to create or refresh those pins after adding a
# package or bumping a version: it downloads each URL once, prints the digest,
# and rewrites the manifest in place. It never consults the host package
# manager and never installs anything.
#
# Usage:
#   bash base-system/scripts/update-pins.sh                     # all entries
#   bash base-system/scripts/update-pins.sh findutils sudo      # selected
#   bash base-system/scripts/update-pins.sh --check              # verify only
#   bash base-system/scripts/update-pins.sh --list <file>        # other manifest
#
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
# shellcheck source=../../scripts/common.sh
source "$REPO_ROOT/scripts/common.sh"

MODE="write"
CHECK_ONLY=0
MANIFEST="${SHREEOS_MANIFEST:-${REPO_ROOT}/base-system/packages.list}"
SELECTED=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --check)  CHECK_ONLY=1; shift ;;
    --list)   [[ $# -ge 2 ]] || shreeos_die "--list requires a manifest path"
              MANIFEST="$2"; shift 2 ;;
    --help|-h)
      sed -n '2,16p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
      exit 0 ;;
    -*)       shreeos_die "Unknown option: $1" ;;
    *)        SELECTED+=("$1"); shift ;;
  esac
done

[[ -f "$MANIFEST" ]] || shreeos_die "Manifest not found: $MANIFEST"

shreeos_require_cmd curl sha256sum awk

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

shreeos_step "Refreshing SHA-256 pins in $(basename "$MANIFEST")"

failures=0
updated=0
checked=0

# Emit "<line-number>\t<name>\t<url>\t<oldsha>" for one entry.
emit() {
  awk -F'\t' -v want="$1" '
    /^[[:space:]]*#/ { next }
    NF < 4 { next }
    $1 == want { printf "%d\t%s\t%s\t%s\n", NR, $1, $3, $4 }
  ' "$MANIFEST"
}

process() {
  local name="$1" url="$2" want="$3" line="$4" dest sha
  dest="${WORK}/$(basename "$url")"
  shreeos_log "$name <- $url"
  if ! curl --fail --location --silent --show-error --retry 3 --retry-all-errors \
            --connect-timeout 20 --max-time 900 \
            --proto '=https' --proto-redir '=https' \
            --output "$dest" "$url"; then
    shreeos_warn "$name: download failed, pin left unchanged"
    failures=$((failures + 1))
    return 0
  fi
  sha="$(sha256sum "$dest" | awk '{print $1}')"
  if [[ "$CHECK_ONLY" == "1" ]]; then
    if [[ "$sha" == "$want" ]]; then
      shreeos_ok "$name pin matches ($sha)"
    else
      shreeos_warn "$name pin MISMATCH: manifest=$want actual=$sha"
      failures=$((failures + 1))
    fi
    checked=$((checked + 1))
  else
    if [[ "$sha" == "$want" ]]; then
      shreeos_ok "$name already pinned ($sha)"
    else
      shreeos_warn "$name re-pinned: ${want:-<none>} -> $sha"
      updated=$((updated + 1))
    fi
    pin_manifest "$line" "$sha"
  fi
}

# Rewrite exactly one manifest line, preserving its name/version/url columns.
pin_manifest() {
  local lineno="$1" sha="$2"
  awk -v n="$lineno" -v s="$sha" 'NR == n { $4 = s } { print }' "$MANIFEST" > "${MANIFEST}.new"
  mv -f "${MANIFEST}.new" "$MANIFEST"
}

if [[ ${#SELECTED[@]} -gt 0 ]]; then
  for name in "${SELECTED[@]}"; do
    rec="$(emit "$name")"
    [[ -n "$rec" ]] || shreeos_die "No entry named '$name' in $MANIFEST"
    IFS=$'\t' read -r line name url want <<<"$rec"
    process "$name" "$url" "$want" "$line"
  done
else
  while IFS=$'\t' read -r line name url want; do
    process "$name" "$url" "$want" "$line"
  done < <(awk -F'\t' '
    /^[[:space:]]*#/ { next }
    NF < 4 { next }
    { printf "%d\t%s\t%s\t%s\n", NR, $1, $3, $4 }
  ' "$MANIFEST")
fi

shreeos_step "Pin refresh summary"
shreeos_log "  manifest : $MANIFEST"
if [[ "$CHECK_ONLY" == "1" ]]; then
  shreeos_log "  verified : $checked"
else
  shreeos_log "  re-pinned : $updated"
fi
shreeos_log "  failures : $failures"

if [[ $failures -gt 0 ]]; then
  shreeos_die "$failures package(s) could not be pinned/verified"
fi
shreeos_ok "All source pins verified"
