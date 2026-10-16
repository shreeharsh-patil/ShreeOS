#!/usr/bin/env bash
# Download a ShreeOS image bundle produced by an earlier job in this run.
#
# Usage: scripts/fetch-release-assets.sh ARTIFACT_ID [DESTINATION_DIR]
#
# The artifact is addressed by ID rather than by name so that a rerun cannot
# silently pick up a bundle from a different attempt. Requires GH_TOKEN, GH_REPO
# and a downloaded-artifact-capable token (actions: read).
set -Eeuo pipefail

if [ "$#" -lt 1 ] || [ "$#" -gt 2 ]; then
  echo "Usage: $0 ARTIFACT_ID [DESTINATION_DIR]" >&2
  exit 2
fi

artifact_id="$1"
destination="${2:-out}"

[[ "$artifact_id" =~ ^[0-9]+$ ]] || {
  echo "Artifact id must be numeric, got '$artifact_id'" >&2
  exit 2
}
[ -n "${GH_TOKEN:-}" ] || { echo 'GH_TOKEN is required' >&2; exit 2; }
[ -n "${GH_REPO:-}" ] || { echo 'GH_REPO is required' >&2; exit 2; }
for tool in gh unzip; do
  command -v "$tool" >/dev/null 2>&1 || { echo "Missing tool: $tool" >&2; exit 2; }
done

mkdir -p "$destination"
# Remove only prior image payloads, never the destination directory itself.
find "$destination" -maxdepth 1 -type f \
  \( -name '*.iso' -o -name '*.iso.sha256' -o -name '*.iso.part-*' \
  -o -name 'SHA256SUMS' -o -name '*-packages.txt' -o -name '*-build-info.txt' \
  -o -name '*-manifest.json' -o -name 'assemble-shreeos-iso.*' \
  -o -name 'REASSEMBLE-ISO.md' \) -delete

bundle="$(mktemp)"
trap 'rm -f -- "$bundle"' EXIT
gh api "/repos/$GH_REPO/actions/artifacts/$artifact_id/zip" >"$bundle"
[ -s "$bundle" ] || { echo "Artifact $artifact_id downloaded empty" >&2; exit 1; }
unzip -q -o "$bundle" -d "$destination"

[ -s "$destination/SHA256SUMS" ] || { echo 'Bundle is missing SHA256SUMS' >&2; exit 1; }

# Verify the part files themselves first, so a truncated upload cannot pass.
(
  cd "$destination"
  sha256sum --check --ignore-missing SHA256SUMS
)

# The bundle is split whenever the ISO exceeds GitHub's per-asset limit. Every
# consumer needs the real image, so reassemble it here, once, and prove the
# reconstruction against the original checksum rather than trusting the parts.
mapfile -t images < <(find "$destination" -maxdepth 1 -type f -name '*.iso' -print)
if [ "${#images[@]}" -gt 0 ]; then
  printf 'Recovered %s\n' "$(basename -- "${images[0]}")"
  exit 0
fi

mapfile -t parts < <(find "$destination" -maxdepth 1 -type f -name '*.iso.part-*' -print | sort)
[ "${#parts[@]}" -ge 2 ] || { echo 'Bundle contains no ISO and no ISO parts' >&2; exit 1; }
printf 'Reassembling %s ISO parts\n' "${#parts[@]}"

# The original name is everything before the first ".part-".
iso_name="$(basename -- "${parts[0]}")"
iso_name="${iso_name%%.part-*}"
[[ "$iso_name" =~ ^shreeos\([0-9A-Za-z._-]+\)\.iso$ ]] || {
  echo "Refusing to reassemble an unrecognised image name: $iso_name" >&2
  exit 1
}

checksum_file="$destination/$iso_name.sha256"
[ -s "$checksum_file" ] || { echo "Bundle is missing $iso_name.sha256" >&2; exit 1; }
expected="$(awk 'NR == 1 {print $1}' "$checksum_file")"
[[ "$expected" =~ ^[[:xdigit:]]{64}$ ]] || { echo "Invalid checksum file: $checksum_file" >&2; exit 1; }

# Concatenation is intentional: hash the reconstructed image byte-for-byte.
# shellcheck disable=SC2002
actual="$(cat -- "${parts[@]}" | sha256sum | awk '{print $1}')"
[ "$actual" = "$expected" ] || {
  echo 'Reassembled image does not match its recorded SHA-256' >&2
  exit 1
}
cat -- "${parts[@]}" >"$destination/$iso_name"
[ "$(sha256sum "$destination/$iso_name" | awk '{print $1}')" = "$expected" ] || {
  echo 'Written image does not match its recorded SHA-256' >&2
  exit 1
}
printf 'Reassembled and verified %s\n' "$iso_name"

