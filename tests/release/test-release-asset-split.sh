#!/usr/bin/env bash
set -Eeuo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
helper="$repo_root/scripts/prepare-release-assets.sh"
tmp="$(mktemp -d)"
trap 'rm -rf -- "$tmp"' EXIT

mkdir -p "$tmp/large" "$tmp/small"
python3 - "$tmp/large/sample.iso" "$tmp/small/small.iso" <<'PY'
import pathlib
import sys

pathlib.Path(sys.argv[1]).write_bytes(bytes(range(256)) * 4096)
pathlib.Path(sys.argv[2]).write_bytes(b"tiny test image\n")
PY

for iso in "$tmp/large/sample.iso" "$tmp/small/small.iso"; do
  (cd -- "$(dirname -- "$iso")" && sha256sum "$(basename -- "$iso")" > "$(basename -- "$iso").sha256")
done

bash "$helper" "$tmp/large" sample.iso 250000
[[ ! -e "$tmp/large/sample.iso" ]]
[[ -s "$tmp/large/sample.iso.parts.sha256" ]]
[[ -s "$tmp/large/assemble-shreeos-iso.ps1" ]]
[[ -x "$tmp/large/assemble-shreeos-iso.sh" ]]
[[ "$(find "$tmp/large" -maxdepth 1 -name 'sample.iso.part-*' -type f | wc -l)" -ge 2 ]]
(
  cd -- "$tmp/large"
  sha256sum -c SHA256SUMS
  bash ./assemble-shreeos-iso.sh
  if command -v pwsh.exe >/dev/null 2>&1; then
    pwsh.exe -NoProfile -ExecutionPolicy Bypass -File ./assemble-shreeos-iso.ps1
  fi
  sha256sum -c sample.iso.sha256
)

bash "$helper" "$tmp/small" small.iso
[[ -s "$tmp/small/small.iso" ]]
[[ ! -e "$tmp/small/small.iso.part-00" ]]
(cd -- "$tmp/small" && sha256sum -c SHA256SUMS && sha256sum -c small.iso.sha256)

# The mandated release name contains parentheses, and a large image carrying it
# must split, reassemble and verify exactly like any other name.
mkdir -p "$tmp/mandated"
python3 - "$tmp/mandated/shreeos(0.4.0).iso" <<'PY'
import pathlib
import sys

pathlib.Path(sys.argv[1]).write_bytes(bytes(range(256)) * 4096)
PY
(
  cd -- "$tmp/mandated"
  sha256sum "shreeos(0.4.0).iso" > "shreeos(0.4.0).iso.sha256"
)
bash "$helper" "$tmp/mandated" 'shreeos(0.4.0).iso' 250000
[[ ! -e "$tmp/mandated/shreeos(0.4.0).iso" ]]
[[ -s "$tmp/mandated/shreeos(0.4.0).iso.parts.sha256" ]]
[[ -s "$tmp/mandated/SHA256SUMS" ]]
[[ "$(find "$tmp/mandated" -maxdepth 1 -name 'shreeos(0.4.0).iso.part-*' -type f | wc -l)" -ge 2 ]]
(
  cd -- "$tmp/mandated"
  sha256sum -c SHA256SUMS
  bash ./assemble-shreeos-iso.sh
  sha256sum -c "shreeos(0.4.0).iso.sha256"
)

# A filename that tries to escape the asset directory must still be refused.
for bad in '../escape.iso' 'shreeos*.iso' 'shreeos(0.4.0).iso/../x.iso'; do
  if bash "$helper" "$tmp/small" "$bad" >/dev/null 2>&1; then
    echo "Release helper accepted an unsafe filename: $bad" >&2
    exit 1
  fi
done

echo "Release ISO packaging tests passed."
