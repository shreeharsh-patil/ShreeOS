#!/usr/bin/env bash
# tests/build/test-source-fetch.sh — source cache integrity regression tests
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$ROOT_DIR/scripts/common.sh"

TEST_DIR="$(mktemp -d)"
trap 'rm -rf "$TEST_DIR"' EXIT

SOURCE="$TEST_DIR/upstream.tar"
DEST="$TEST_DIR/cache/source.tar"
mkdir -p "$(dirname "$DEST")"
printf 'shreeos-source-fixture\n' > "$SOURCE"
SHA="$(sha256sum "$SOURCE" | awk '{print $1}')"
URL="file://$SOURCE"

shreeos_fetch "$URL" "$DEST" "$SHA"
cmp -s "$SOURCE" "$DEST" || {
  echo "  [FAIL] Initial verified fetch did not reproduce the source" >&2
  exit 1
}
echo "  [OK] Initial source fetch verified before caching"

printf 'corrupt-cache\n' > "$DEST"
shreeos_fetch "$URL" "$DEST" "$SHA"
cmp -s "$SOURCE" "$DEST" || {
  echo "  [FAIL] Invalid cached source was not repaired" >&2
  exit 1
}
echo "  [OK] Corrupted cached source was discarded and recovered"

rm -f "$DEST"
BAD_SHA="$(printf '%064d' 0)"
if (shreeos_fetch "$URL" "$DEST" "$BAD_SHA" >/dev/null 2>&1); then
  echo "  [FAIL] Fetch accepted an incorrect SHA-256 pin" >&2
  exit 1
fi
[ ! -e "$DEST" ] || {
  echo "  [FAIL] Failed verification left an invalid cache entry behind" >&2
  exit 1
}
if compgen -G "$DEST.part.*" >/dev/null; then
  echo "  [FAIL] Failed verification left a partial download behind" >&2
  exit 1
fi
echo "  [OK] Checksum mismatch fails closed without poisoning the cache"
