#!/usr/bin/env bash
# Ensure the cached ISO postcondition rejects stale or corrupted provenance.
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
TEST_ROOT="$(mktemp -d)"
trap 'rm -rf -- "$TEST_ROOT"' EXIT

OUT="$TEST_ROOT/out"
mkdir -p "$OUT"
ISO_NAME='shreeos-0.4.0.iso'
ISO="$OUT/$ISO_NAME"
MANIFEST="$OUT/shreeos-0.4.0-manifest.json"
printf 'synthetic ISO bytes for cache verification\n' > "$ISO"
(cd "$OUT" && sha256sum "$ISO_NAME" > "$ISO_NAME.sha256")
ISO_PATH="$ISO" MANIFEST_PATH="$MANIFEST" python3 - <<'PY'
import hashlib
import json
import os
from pathlib import Path

iso = Path(os.environ["ISO_PATH"])
with iso.open("rb") as stream:
    digest = hashlib.file_digest(stream, "sha256").hexdigest()
manifest = {
    "profile": "minimal",
    "commit": "1" * 40,
    "iso": iso.name,
    "sha256": digest,
    "size_bytes": iso.stat().st_size,
}
Path(os.environ["MANIFEST_PATH"]).write_text(json.dumps(manifest) + "\n", encoding="utf-8")
PY

verify() {
  SHREEOS_OUT="$OUT" PROFILE=minimal bash "$PROJECT_ROOT/scripts/verify-stage.sh" iso
}

verify
printf 'corruption\n' >> "$ISO"
if output="$(verify 2>&1)"; then
  echo "ISO stage verification accepted bytes that disagree with its sidecar and manifest" >&2
  exit 1
fi
grep -Fq 'ISO SHA-256 does not match the sidecar and manifest' <<< "$output" || {
  printf 'Unexpected corruption diagnostic:\n%s\n' "$output" >&2
  exit 1
}

echo "ISO stage checksum and manifest regression checks passed."
