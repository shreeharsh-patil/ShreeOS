#!/usr/bin/env bash
# repo-tools/scripts/build-repo.sh — Build a ShreeOS package repository
#
# Scans a directory tree of built software, packages each into a .lpkg
# file, and writes a repo.json index.
#
# Usage:
#   bash repo-tools/scripts/build-repo.sh <staging-dir> <output-dir>
#
# Example:
#   bash repo-tools/scripts/build-repo.sh \
#     build/staging/packages \
#     out/repo
#
# The staging directory should contain subdirectories, each with:
#   manifest.json  — required (name, version, files, deps)
#   <files>        — files listed in manifest.json at their install paths
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LUMEN_ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$LUMEN_ROOT_DIR/build.conf"
source "$LUMEN_ROOT_DIR/scripts/common.sh"

if [ $# -lt 2 ]; then
  lumen_die "Usage: build-repo.sh <staging-dir> <output-dir>"
fi

STAGING="$1"
OUTDIR="$2"

lumen_require_cmd tar gzip

if [ ! -d "$STAGING" ]; then
  lumen_die "Staging directory not found: ${STAGING}"
fi

mkdir -p "$OUTDIR/pool"

REPO_JSON="${OUTDIR}/repo.json"
echo "{" > "$REPO_JSON"
echo "  \"name\": \"${DISTRO_ID}-main\"," >> "$REPO_JSON"
echo "  \"packages\": {" >> "$REPO_JSON"

FIRST=true
for pkg_dir in "$STAGING"/*/; do
  [ -d "$pkg_dir" ] || continue
  PKG_NAME=$(basename "$pkg_dir")

  if [ ! -f "${pkg_dir}/manifest.json" ]; then
    lumen_warn "Skipping ${PKG_NAME}: no manifest.json"
    continue
  fi

  # Read version from manifest
  VER=$(grep -oP '"version"\s*:\s*"\K[^"]+' "${pkg_dir}/manifest.json" || echo "0.0")
  DESC=$(grep -oP '"description"\s*:\s*"\K[^"]*' "${pkg_dir}/manifest.json" || echo "")

  LPKG_FILE="${PKG_NAME}-${VER}.lpkg"
  LPKG_PATH="${OUTDIR}/pool/${LPKG_FILE}"

  lumen_step "Packaging ${PKG_NAME}-${VER}"

  # Build .lpkg: tar.gz with manifest.json first, then all files
  (
    cd "$pkg_dir"
    tar -czf "$LPKG_PATH" --transform="s|^\./||" --sort=name .
  )

  # Compute SHA256
  LPKG_SHA=$(sha256sum "$LPKG_PATH" | awk '{print $1}')

  # Append to repo.json
  if [ "$FIRST" = true ]; then
    FIRST=false
  else
    echo "," >> "$REPO_JSON"
  fi

  cat >> "$REPO_JSON" <<REPOENTRY
    "${PKG_NAME}": {
      "version": "${VER}",
      "filename": "pool/${LPKG_FILE}",
      "sha256": "${LPKG_SHA}",
      "description": "${DESC}"
    }
REPOENTRY

  lumen_ok "Packaged ${LPKG_FILE} (${LPKG_SHA})"
done

echo "" >> "$REPO_JSON"
echo "  }" >> "$REPO_JSON"
echo "}" >> "$REPO_JSON"

lumen_ok "Repository index: ${REPO_JSON}"
lumen_ok "Repository ready at ${OUTDIR}"
echo ""
echo "Serve with:"
echo "  python3 -m http.server 8080 -d ${OUTDIR}"
echo ""
echo "Then install on target:"
echo "  lpm install <package.lpkg>"
echo ""
