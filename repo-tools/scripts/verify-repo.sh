#!/usr/bin/env bash
# repo-tools/scripts/verify-repo.sh — Cryptographic repository verification utility
#
# Verifies repository signature and package archive integrity.
#
# Usage:
#   bash repo-tools/scripts/verify-repo.sh <repo-dir> [public-key]
#
set -euo pipefail

if [ $# -lt 1 ]; then
  echo "Usage: $0 <repo-dir> [public-key]" >&2
  exit 1
fi

REPO_DIR="$1"
PUB_KEY="${2:-/etc/lpm/keys/shreeos-repo.pub}"

REPO_JSON="${REPO_DIR}/repo.json"
REPO_SIG="${REPO_DIR}/repo.json.sig"

if [ ! -f "$REPO_JSON" ]; then
  echo "ERROR: Repository metadata not found at ${REPO_JSON}" >&2
  exit 1
fi

echo "=========================================================="
echo " Verifying ShreeOS Package Repository: ${REPO_DIR}"
echo "=========================================================="

# 1. Verify repository signature if signature and public key are present
if [ -f "$REPO_SIG" ] && [ -f "$PUB_KEY" ]; then
  echo "==> Verifying repository cryptographic signature with ${PUB_KEY}:"
  if openssl dgst -sha256 -verify "$PUB_KEY" -signature "$REPO_SIG" "$REPO_JSON" >/dev/null 2>&1; then
    echo "  [PASS] Repository index signature is authentic and verified"
  else
    echo "  [FAIL] Repository index signature verification FAILED!" >&2
    exit 1
  fi
elif [ -f "$REPO_SIG" ]; then
  echo "  [WARN] Signature file present (${REPO_SIG}) but public key not found (${PUB_KEY})"
else
  echo "  [WARN] No signature file found for repository (${REPO_SIG})"
fi

# 2. Verify all packages referenced in repo.json
echo ""
echo "==> Verifying package archive checksums:"
TOTAL_PKGS=0
VALID_PKGS=0
FAILED_PKGS=0

# Extract package entries using grep/sed/awk
PKG_ENTRIES=$(grep -oP '"filename"\s*:\s*"\K[^"]+' "$REPO_JSON" || true)

for rel_path in $PKG_ENTRIES; do
  TOTAL_PKGS=$((TOTAL_PKGS + 1))
  PKG_FILE="${REPO_DIR}/${rel_path}"

  if [ ! -f "$PKG_FILE" ]; then
    echo "  [MISSING] ${rel_path} (file not found in pool)"
    FAILED_PKGS=$((FAILED_PKGS + 1))
    continue
  fi

  # Find expected hash for this file
  EXPECTED_SHA=$(grep -B 2 -A 2 "$rel_path" "$REPO_JSON" | grep -oP '"sha256"\s*:\s*"\K[^"]+' || echo "")
  ACTUAL_SHA=$(sha256sum "$PKG_FILE" | awk '{print $1}')

  if [ "$ACTUAL_SHA" = "$EXPECTED_SHA" ]; then
    printf "  [PASS] %-32s (SHA: %.12s...)\n" "$(basename "$rel_path")" "$ACTUAL_SHA"
    VALID_PKGS=$((VALID_PKGS + 1))
  else
    printf "  [FAIL] %-32s Checksum mismatch!\n" "$(basename "$rel_path")"
    echo "         Expected: $EXPECTED_SHA"
    echo "         Actual:   $ACTUAL_SHA"
    FAILED_PKGS=$((FAILED_PKGS + 1))
  fi
done

echo ""
echo "=========================================================="
echo " Repository Verification Results:"
echo "   Total packages checked: ${TOTAL_PKGS}"
echo "   Verified valid:         ${VALID_PKGS}"
echo "   Failed:                 ${FAILED_PKGS}"
echo "=========================================================="

if [ "$FAILED_PKGS" -gt 0 ]; then
  exit 1
fi
exit 0
