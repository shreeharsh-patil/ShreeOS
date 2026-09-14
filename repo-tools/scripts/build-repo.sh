#!/usr/bin/env bash
# Build a signed-capable ShreeOS package repository from staged package trees.
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$ROOT_DIR/build.conf"
source "$ROOT_DIR/scripts/common.sh"

if [ $# -lt 2 ]; then
  shreeos_die "Usage: build-repo.sh <staging-dir> <output-dir>"
fi

STAGING="$1"
OUTDIR="$2"
shreeos_require_cmd tar gzip sha256sum python3

[ -d "$STAGING" ] || shreeos_die "Staging directory not found: $STAGING"
mkdir -p "$OUTDIR/pool"

REPO_JSON="$OUTDIR/repo.json"
TMP_ENTRIES="$(mktemp)"
cleanup() { rm -f "$TMP_ENTRIES"; }
trap cleanup EXIT INT TERM

for pkg_dir in "$STAGING"/*/; do
  [ -d "$pkg_dir" ] || continue
  PKG_NAME="$(basename "$pkg_dir")"
  MANIFEST="${pkg_dir}/manifest.json"

  if [ ! -f "$MANIFEST" ]; then
    shreeos_warn "Skipping $PKG_NAME: no manifest.json"
    continue
  fi

  # Package names become archive names and repository keys: keep them simple,
  # deterministic and path-safe.
  if ! [[ "$PKG_NAME" =~ ^[A-Za-z0-9][A-Za-z0-9._+-]*$ ]]; then
    shreeos_die "Unsafe package directory name: $PKG_NAME"
  fi

  manifest_values="$(python3 - "$MANIFEST" "$PKG_NAME" <<'PY'
import json, re, sys
path, dirname = sys.argv[1], sys.argv[2]
try:
    with open(path, "r", encoding="utf-8") as fh:
        m = json.load(fh)
except (OSError, json.JSONDecodeError) as exc:
    raise SystemExit(f"invalid manifest {path}: {exc}")
name = m.get("name", dirname)
version = m.get("version")
description = m.get("description", "")
if not isinstance(name, str) or name != dirname:
    raise SystemExit(f"manifest name must match package directory: {dirname}")
if not isinstance(version, str) or not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._+-]*", version):
    raise SystemExit(f"invalid package version for {dirname}: {version!r}")
if not isinstance(description, str):
    raise SystemExit(f"description must be a string for {dirname}")
print(version)
print(json.dumps(description, ensure_ascii=False))
PY
)" || shreeos_die "Manifest validation failed: $MANIFEST"

  VER="$(printf '%s\n' "$manifest_values" | sed -n '1p')"
  DESC_JSON="$(printf '%s\n' "$manifest_values" | sed -n '2p')"
  [ -n "$VER" ] || shreeos_die "Manifest version missing: $MANIFEST"
  [ -n "$DESC_JSON" ] || DESC_JSON='""'

  LPKG_FILE="${PKG_NAME}-${VER}.lpkg"
  LPKG_PATH="$OUTDIR/pool/$LPKG_FILE"

  shreeos_step "Packaging ${PKG_NAME}-${VER}"
  (
    cd "$pkg_dir"
    tar -czf "$LPKG_PATH" --transform='s|^\./||' --sort=name .
  )

  LPKG_SHA="$(sha256sum "$LPKG_PATH" | awk '{print $1}')"
  printf '%s\t%s\t%s\t%s\n' "$PKG_NAME" "$VER" "pool/$LPKG_FILE" "$LPKG_SHA" >> "$TMP_ENTRIES"
  printf '%s\n' "$DESC_JSON" >> "$TMP_ENTRIES"
  shreeos_ok "Packaged $LPKG_FILE ($LPKG_SHA)"
done

# Generate JSON through a JSON library rather than hand-concatenating user
# metadata. Entries are stored as two lines: TSV metadata + JSON description.
python3 - "$TMP_ENTRIES" "$REPO_JSON" "${DISTRO_ID:-shreeos}-main" <<'PY'
import json, sys
entries_path, out_path, repo_name = sys.argv[1:4]
packages = {}
with open(entries_path, "r", encoding="utf-8") as fh:
    lines = iter(fh)
    for meta in lines:
        meta = meta.rstrip("\n")
        if not meta:
            continue
        try:
            desc_line = next(lines).rstrip("\n")
        except StopIteration:
            raise SystemExit("repository metadata is truncated")
        name, version, filename, sha = meta.split("\t")
        description = json.loads(desc_line)
        packages[name] = {
            "version": version,
            "filename": filename,
            "sha256": sha,
            "description": description,
        }
with open(out_path, "w", encoding="utf-8") as fh:
    json.dump({"name": repo_name, "packages": packages}, fh, ensure_ascii=False, indent=2)
    fh.write("\n")
PY

shreeos_ok "Repository index: $REPO_JSON"

REPO_KEY="${SHREEOS_REPO_KEY:-}"
if [ -n "$REPO_KEY" ]; then
  [ -f "$REPO_KEY" ] || shreeos_die "Signing key not found: $REPO_KEY"
  shreeos_require_cmd openssl
  shreeos_step "Signing repository index"
  openssl dgst -sha256 -sign "$REPO_KEY" -out "$REPO_JSON.sig" "$REPO_JSON"
  shreeos_ok "Repository index signed: $REPO_JSON.sig"
else
  shreeos_warn "Repository is unsigned (set SHREEOS_REPO_KEY to sign it)"
fi

shreeos_ok "Repository ready at $OUTDIR"
