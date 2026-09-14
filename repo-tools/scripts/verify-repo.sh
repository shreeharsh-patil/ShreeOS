#!/usr/bin/env bash
# Cryptographically verify a ShreeOS package repository and every indexed archive.
set -Eeuo pipefail

if [ $# -lt 1 ] || [ $# -gt 2 ]; then
  echo "Usage: $0 <repo-dir> [public-key]" >&2
  exit 2
fi

REPO_DIR="$1"
PUB_KEY="${2:-/etc/lpm/keys/shreeos-repo.pub}"
REPO_JSON="$REPO_DIR/repo.json"
REPO_SIG="$REPO_DIR/repo.json.sig"

for cmd in python3 sha256sum; do
  command -v "$cmd" >/dev/null 2>&1 || {
    echo "ERROR: required command not found: $cmd" >&2
    exit 1
  }
done

[ -f "$REPO_JSON" ] || {
  echo "ERROR: Repository metadata not found at $REPO_JSON" >&2
  exit 1
}

echo "=========================================================="
echo " Verifying ShreeOS Package Repository: $REPO_DIR"
echo "=========================================================="

if [ -f "$REPO_SIG" ]; then
  command -v openssl >/dev/null 2>&1 || {
    echo "ERROR: openssl is required to verify $REPO_SIG" >&2
    exit 1
  }
  [ -f "$PUB_KEY" ] || {
    echo "ERROR: Repository is signed but public key is missing: $PUB_KEY" >&2
    exit 1
  }
  if openssl dgst -sha256 -verify "$PUB_KEY" -signature "$REPO_SIG" "$REPO_JSON" >/dev/null 2>&1; then
    echo "  [PASS] Repository index signature verified"
  else
    echo "  [FAIL] Repository index signature verification failed" >&2
    exit 1
  fi
else
  echo "  [WARN] Repository index is unsigned"
fi

entries_file="$(mktemp)"
cleanup() { rm -f "$entries_file"; }
trap cleanup EXIT INT TERM

# Parse the index with a real JSON parser and reject paths that could escape
# the repository or cause ambiguous checksum verification.
python3 - "$REPO_JSON" >"$entries_file" <<'PY'
import json, posixpath, re, sys
path = sys.argv[1]
try:
    with open(path, "r", encoding="utf-8") as fh:
        doc = json.load(fh)
except (OSError, json.JSONDecodeError) as exc:
    raise SystemExit(f"invalid repository JSON: {exc}")
packages = doc.get("packages")
if not isinstance(packages, dict):
    raise SystemExit("repository JSON must contain an object named 'packages'")
for name, meta in packages.items():
    if not isinstance(name, str) or not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._+-]*", name):
        raise SystemExit(f"invalid package name: {name!r}")
    if not isinstance(meta, dict):
        raise SystemExit(f"metadata for {name} must be an object")
    filename = meta.get("filename")
    sha = meta.get("sha256")
    if not isinstance(filename, str):
        raise SystemExit(f"missing filename for {name}")
    if (
        filename.startswith("/")
        or not filename.startswith("pool/")
        or posixpath.normpath(filename) != filename
        or ".." in filename.split("/")
    ):
        raise SystemExit(f"unsafe package path for {name}: {filename!r}")
    if not isinstance(sha, str) or not re.fullmatch(r"[0-9a-fA-F]{64}", sha):
        raise SystemExit(f"invalid sha256 for {name}")
    print(f"{filename}\t{sha.lower()}")
PY

TOTAL_PKGS=0
VALID_PKGS=0
FAILED_PKGS=0

echo
echo "==> Verifying package archive checksums:"
while IFS=$'\t' read -r rel_path expected_sha; do
  [ -n "$rel_path" ] || continue
  TOTAL_PKGS=$((TOTAL_PKGS + 1))
  pkg_file="$REPO_DIR/$rel_path"

  if [ ! -f "$pkg_file" ]; then
    echo "  [MISSING] $rel_path"
    FAILED_PKGS=$((FAILED_PKGS + 1))
    continue
  fi

  actual_sha="$(sha256sum "$pkg_file" | awk '{print $1}')"
  if [ "$actual_sha" = "$expected_sha" ]; then
    printf "  [PASS] %-32s (SHA: %.12s...)\n" "$(basename "$rel_path")" "$actual_sha"
    VALID_PKGS=$((VALID_PKGS + 1))
  else
    printf "  [FAIL] %-32s checksum mismatch\n" "$(basename "$rel_path")"
    echo "         Expected: $expected_sha"
    echo "         Actual:   $actual_sha"
    FAILED_PKGS=$((FAILED_PKGS + 1))
  fi
done < "$entries_file"

echo
echo "=========================================================="
echo " Repository Verification Results:"
echo "   Total packages checked: $TOTAL_PKGS"
echo "   Verified valid:         $VALID_PKGS"
echo "   Failed:                 $FAILED_PKGS"
echo "=========================================================="

if [ "$FAILED_PKGS" -gt 0 ]; then
  exit 1
fi
echo "Repository verification passed."
