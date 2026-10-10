#!/usr/bin/env bash
set -Eeuo pipefail

if (($# < 2 || $# > 3)); then
  echo "Usage: $0 ASSET_DIRECTORY ISO_NAME [PART_SIZE_BYTES]" >&2
  exit 2
fi

asset_dir="$(cd -- "$1" && pwd)"
iso_name="$2"
part_size="${3:-1900000000}"

[[ "$iso_name" =~ ^[A-Za-z0-9._-]+\.iso$ ]] || {
  echo "Invalid ISO filename: $iso_name" >&2
  exit 2
}
[[ "$part_size" =~ ^[0-9]+$ ]] && ((part_size > 0 && part_size < 2147483648)) || {
  echo "Part size must be a positive byte count below GitHub's 2 GiB asset limit." >&2
  exit 2
}

iso_path="$asset_dir/$iso_name"
checksum_path="$iso_path.sha256"
[[ -s "$iso_path" && -s "$checksum_path" ]] || {
  echo "ISO and its checksum must exist in the asset directory." >&2
  exit 1
}

original_hash="$(awk 'NR == 1 {print $1}' "$checksum_path")"
[[ "$original_hash" =~ ^[[:xdigit:]]{64}$ ]] || {
  echo "Invalid SHA-256 file: $checksum_path" >&2
  exit 1
}
actual_hash="$(sha256sum "$iso_path" | awk '{print $1}')"
[[ "$actual_hash" == "$original_hash" ]] || {
  echo "ISO does not match its recorded SHA-256." >&2
  exit 1
}

iso_size="$(stat -c '%s' "$iso_path")"
if ((iso_size <= part_size)); then
  (cd -- "$asset_dir" && sha256sum -- "$iso_name" > SHA256SUMS)
  exit 0
fi

part_prefix="$iso_path.part-"
rm -f -- "$part_prefix"*
split --bytes="$part_size" --numeric-suffixes=0 --suffix-length=2 \
  -- "$iso_path" "$part_prefix"

shopt -s nullglob
parts=("$part_prefix"*)
(( ${#parts[@]} >= 2 )) || {
  echo "Large ISO was not divided into multiple release assets." >&2
  exit 1
}

for part in "${parts[@]}"; do
  part_size_actual="$(stat -c '%s' "$part")"
  ((part_size_actual < 2147483648)) || {
    echo "Release part exceeds GitHub's 2 GiB asset limit: $part" >&2
    exit 1
  }
done

parts_manifest="$iso_path.parts.sha256"
(
  cd -- "$asset_dir"
  sha256sum -- "${parts[@]##*/}" > "$parts_manifest"
  cp -- "$parts_manifest" SHA256SUMS
)

# Concatenation is intentional: hash the reconstructed image byte-for-byte.
# shellcheck disable=SC2002
joined_hash="$(cat -- "${parts[@]}" | sha256sum | awk '{print $1}')"
[[ "$joined_hash" == "$original_hash" ]] || {
  echo "Split parts do not reconstruct the tested ISO checksum." >&2
  exit 1
}

cat > "$asset_dir/REASSEMBLE-ISO.md" <<EOF
# Reassemble the ShreeOS ISO

GitHub limits each release asset to 2 GiB. The tested ISO is supplied as numbered parts.
Download every numbered $iso_name.part-* file into this directory, then run one of:

- Windows: powershell -ExecutionPolicy Bypass -File .\\assemble-shreeos-iso.ps1
- Linux: bash ./assemble-shreeos-iso.sh

The scripts join the parts and verify the original image against $iso_name.sha256.
The SHA256SUMS file verifies each downloaded part.
Do not write individual part files to USB media.
EOF

cat > "$asset_dir/assemble-shreeos-iso.sh" <<EOF
#!/usr/bin/env bash
set -Eeuo pipefail
cd -- "\$(dirname -- "\$0")"
iso_name="$iso_name"
shopt -s nullglob
parts=("\$iso_name".part-*)
(( \${#parts[@]} >= 2 )) || { echo "Download all numbered ISO parts first." >&2; exit 1; }
sha256sum -c SHA256SUMS
cat -- "\${parts[@]}" > "\$iso_name"
sha256sum -c "\$iso_name.sha256"
EOF
chmod 755 "$asset_dir/assemble-shreeos-iso.sh"

cat > "$asset_dir/assemble-shreeos-iso.ps1" <<EOF
\$ErrorActionPreference = 'Stop'
\$isoName = '$iso_name'
\$root = \$PSScriptRoot
\$parts = @(Get-ChildItem -LiteralPath \$root -File -Filter "\$isoName.part-*" | Sort-Object Name)
if (\$parts.Count -lt 2) { throw 'Download all numbered ISO parts into this directory first.' }
foreach (\$line in Get-Content -LiteralPath (Join-Path \$root 'SHA256SUMS')) {
    \$fields = \$line -split '\s+', 2
    \$partName = \$fields[1].TrimStart('*')
    \$partPath = Join-Path \$root \$partName
    if ((Get-FileHash -Algorithm SHA256 -LiteralPath \$partPath).Hash.ToLowerInvariant() -ne \$fields[0].ToLowerInvariant()) {
        throw "Part checksum mismatch: \$partPath"
    }
}
\$outputPath = Join-Path \$root \$isoName
\$output = [System.IO.File]::Open(\$outputPath, [System.IO.FileMode]::Create, [System.IO.FileAccess]::Write)
try {
    foreach (\$part in \$parts) {
        \$input = [System.IO.File]::OpenRead(\$part.FullName)
        try { \$input.CopyTo(\$output, 1048576) } finally { \$input.Dispose() }
    }
} finally { \$output.Dispose() }
\$checksumPath = Join-Path \$root "\$isoName.sha256"
\$expected = ((Get-Content -Raw -LiteralPath \$checksumPath).Trim() -split '\s+')[0]
\$actual = (Get-FileHash -Algorithm SHA256 -LiteralPath \$outputPath).Hash.ToLowerInvariant()
if (\$actual -ne \$expected.ToLowerInvariant()) { Remove-Item -LiteralPath \$outputPath; throw 'Reassembled ISO checksum mismatch.' }
Write-Host "Reassembled and verified \$isoName"
EOF

rm -- "$iso_path"
