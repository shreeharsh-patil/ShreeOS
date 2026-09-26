#!/usr/bin/env bash
# Verify and optionally populate the pinned native desktop graphics source cache.
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$REPO_ROOT/build.conf"
source "$REPO_ROOT/scripts/common.sh"

PACKAGES_FILE="$SCRIPT_DIR/packages.list"
[[ -s "$PACKAGES_FILE" ]] || shreeos_die "Missing desktop graphics package manifest: $PACKAGES_FILE"

count=0
while IFS=$'\t' read -r name version url sha build_kind extra; do
  [[ -n "$name" ]] || continue
  [[ "$name" == \#* ]] && continue
  [[ -z "${extra:-}" ]] || shreeos_die "Malformed desktop graphics manifest row for $name"
  [[ -n "$version" && -n "$url" && -n "$sha" && -n "$build_kind" ]] || \
    shreeos_die "Incomplete desktop graphics manifest row for $name"
  [[ "$url" == https://* ]] || shreeos_die "Desktop source must use HTTPS: $url"
  [[ "$sha" =~ ^[0-9a-fA-F]{64}$ ]] || shreeos_die "Invalid SHA-256 for desktop package $name"
  case "$build_kind" in
    autotools|meson|data) ;;
    *) shreeos_die "Unsupported desktop build kind '$build_kind' for $name" ;;
  esac

  archive="$(basename "$url")"
  shreeos_fetch "$url" "$SHREEOS_SOURCES/$archive" "$sha"
  count=$((count + 1))
done < "$PACKAGES_FILE"

[[ "$count" -ge 1 ]] || shreeos_die "Desktop graphics manifest contains no packages"
shreeos_ok "Verified $count pinned native desktop graphics sources"
