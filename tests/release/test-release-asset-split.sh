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

echo "Release ISO packaging tests passed."
