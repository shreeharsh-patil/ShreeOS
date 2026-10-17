#!/usr/bin/env bash
# ShreeOS unified desktop image — canonical build entry point.
#
# This is the ONE user-facing build for the ShreeOS desktop operating system. It
# assembles a single Debian 13 (Trixie) + KDE Plasma root filesystem that boots
# as a live desktop and installs through Calamares to the same image, and it
# emits exactly one primary artifact:
#
#     out/shreeos(VERSION).iso
#
# Every other file it writes is metadata for that image. It never produces
# "-plasma", "-native", "-desktop", "-prototype" or "-amd64" release ISOs.
#
# Usage:
#   scripts/build-shreeos.sh                 # build the unified image
#   scripts/build-shreeos.sh --force         # ignore the reusable-input cache
#   scripts/build-shreeos.sh --check         # validate environment, build nothing
#   scripts/build-shreeos.sh --verify-only   # re-verify an existing image
#
# Requirements: Debian 13 / Trixie (or CI), root, live-build pinned by
# prototype/debian-live/versions.conf.
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)"
cd "$REPO_ROOT"

force=0
check_only=0
verify_only=0
while [ "$#" -gt 0 ]; do
  case "$1" in
    --force) force=1; shift ;;
    --check) check_only=1; shift ;;
    --verify-only) verify_only=1; shift ;;
    -h | --help)
      sed -n '2,22p' "${BASH_SOURCE[0]}"
      exit 0
      ;;
    *)
      echo "build-shreeos.sh: unexpected argument '$1'" >&2
      exit 2
      ;;
  esac
done

# shellcheck source=/dev/null
source "$REPO_ROOT/build.conf"
# shellcheck source=/dev/null
source "$REPO_ROOT/prototype/debian-live/versions.conf"

VERSION="$DISTRO_VERSION"
[ "$VERSION" = "$PROTOTYPE_VERSION" ] || {
  echo "Version drift: build.conf=$VERSION versions.conf=$PROTOTYPE_VERSION" >&2
  exit 1
}

OUT_DIR="${SHREEOS_OUT:-$REPO_ROOT/out}"
ISO_NAME="shreeos(${VERSION}).iso"
ISO_PATH="$OUT_DIR/$ISO_NAME"
CHECKSUM_PATH="$ISO_PATH.sha256"
PACKAGES_PATH="$OUT_DIR/shreeos(${VERSION})-packages.txt"
BUILD_INFO_PATH="$OUT_DIR/shreeos(${VERSION})-build-info.txt"
MANIFEST_PATH="$OUT_DIR/shreeos(${VERSION})-manifest.json"
INPUT_MARKER="$REPO_ROOT/build/.markers/shreeos-iso-inputs.sha256"
# The unified desktop image is the Debian Live Plasma profile. The base and
# XFCE desktop profiles remain buildable as experiments, but they are not
# release artifacts and are never published.
UNIFIED_PROFILE=plasma

log() { printf '==> %s\n' "$*"; }
die() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

# --------------------------------------------------------------------------
# 1. Validate the environment before doing any work. Never start a build that
#    cannot finish, and never silently skip a missing dependency.
# --------------------------------------------------------------------------
required_tools=(lb debootstrap xorriso unsquashfs grub-mkrescue sha256sum dpkg-query rsvg-convert mksquashfs)
missing_tools=()
for tool in "${required_tools[@]}"; do
  command -v "$tool" >/dev/null 2>&1 || missing_tools+=("$tool")
done

environment_ok=1
if [ "${#missing_tools[@]}" -gt 0 ]; then
  printf 'Missing build dependencies: %s\n' "${missing_tools[*]}" >&2
  environment_ok=0
fi

if [ "$(id -u)" -ne 0 ]; then
  echo 'The unified ShreeOS image must be built as root (live-build mounts and chroots).' >&2
  environment_ok=0
fi

if [ -r /etc/os-release ]; then
  # Keep the host's generic VERSION field out of this shell. On Debian it is
  # "13 (trixie)", and sourcing os-release here would replace ShreeOS's 0.4.0
  # value before the ISO name is passed to the prototype builder.
  host_metadata="$(
    # shellcheck source=/dev/null
    . /etc/os-release
    printf '%s\n%s\n' "${ID:-}" "${VERSION_CODENAME:-}"
  )"
  host_id="${host_metadata%%$'\n'*}"
  host_version_codename="${host_metadata#*$'\n'}"
  if [ "$host_id" != debian ]; then
    printf 'Unsupported build host: %s %s. Build the unified image on Debian 13 (Trixie).\n' \
      "${host_id:-unknown}" "${host_version_codename:-unknown}" >&2
    environment_ok=0
  elif [ "$host_version_codename" != trixie ]; then
    printf 'Warning: building on Debian %s, but the pinned snapshot is Trixie; the build may not resolve.\n' \
      "${host_version_codename:-unknown}" >&2
  fi
fi

if command -v dpkg-query >/dev/null 2>&1; then
  installed_lb="$(dpkg-query -W -f='${Version}' live-build 2>/dev/null || true)"
  if [ "$installed_lb" != "$LIVE_BUILD_VERSION" ]; then
    printf 'live-build %s is required; found %s\n' "$LIVE_BUILD_VERSION" "${installed_lb:-none}" >&2
    environment_ok=0
  fi
fi

bash scripts/verify-version.sh || environment_ok=0

if [ "$environment_ok" -ne 1 ]; then
  die 'build environment validation failed; nothing was built'
fi
log "Environment validated (ShreeOS $VERSION, Debian $DEBIAN_SUITE @ $DEBIAN_SNAPSHOT)"

if [ "$check_only" -eq 1 ]; then
  log "Check complete. Would build: $ISO_PATH"
  exit 0
fi

# --------------------------------------------------------------------------
# 2. Reusable input cache. Only a cache that also re-verifies the artifact it
#    claims to describe may short-circuit the build, so a stale ISO can never
#    be reported as current.
# --------------------------------------------------------------------------
inputs_hash() {
  (
    cd "$REPO_ROOT"
    {
      printf 'version=%s\n' "$VERSION"
      printf 'suite=%s\nsnapshot=%s\nlb=%s\n' "$DEBIAN_SUITE" "$DEBIAN_SNAPSHOT" "$LIVE_BUILD_VERSION"
      printf 'profile=%s\n' "$UNIFIED_PROFILE"
      printf 'firmware=%s\n' "${SHREEOS_FIRMWARE:-standard}"
      printf 'toolsets=%s\n' "${SHREEOS_TOOLSETS:-}"
      printf 'architecture=%s\n' "$SHREEOS_ARCH"
      sha256sum build.conf
      find prototype/debian-live desktop hardware pkgmanager themes/plasma branding scripts \
        docs/UNIFIED-IMAGE.md LICENSE -type f -print0 |
        sort -z | xargs -0 sha256sum
    } | sha256sum | awk '{print $1}'
  )
}

verify_existing_artifact() {
  [ -s "$ISO_PATH" ] || return 1
  [ -s "$CHECKSUM_PATH" ] || return 1
  [ -s "$PACKAGES_PATH" ] || return 1
  [ -s "$BUILD_INFO_PATH" ] || return 1
  [ -s "$MANIFEST_PATH" ] || return 1
  (cd "$OUT_DIR" && sha256sum --check --status "$ISO_NAME.sha256") || return 1
  local expected_source_commit="${GITHUB_SHA:-}"
  if git -C "$REPO_ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    expected_source_commit="$(git -C "$REPO_ROOT" rev-parse HEAD)"
  fi
  [[ "$expected_source_commit" =~ ^[0-9a-f]{40}$ ]] || return 1
  python3 "$REPO_ROOT/scripts/verify-unified-artifact.py" \
    "$ISO_PATH" "$CHECKSUM_PATH" "$PACKAGES_PATH" "$BUILD_INFO_PATH" \
    "$MANIFEST_PATH" "$VERSION" "$UNIFIED_PROFILE" "$SHREEOS_ARCH" \
    "$DEBIAN_SUITE" "$DEBIAN_SNAPSHOT" "$LIVE_BUILD_VERSION" \
    "$expected_source_commit" || return 1
  # A file that is not a bootable hybrid image is not a valid cached artifact.
  xorriso -indev "$ISO_PATH" -toc >/dev/null 2>&1 || return 1
  xorriso -osirrox on -indev "$ISO_PATH" -extract /live/filesystem.squashfs /dev/null >/dev/null 2>&1 || return 1
  return 0
}

current_hash="$(inputs_hash)"
if [ "$verify_only" -eq 1 ]; then
  verify_existing_artifact || die "existing image failed verification: $ISO_PATH"
  log "Existing image verified: $ISO_PATH"
  exit 0
fi

if [ "$force" -eq 0 ] && [ -f "$INPUT_MARKER" ] && [ "$(cat "$INPUT_MARKER")" = "$current_hash" ]; then
  if verify_existing_artifact; then
    log "Inputs unchanged and $ISO_NAME verified; reusing the existing image (use --force to rebuild)"
    exit 0
  fi
  log 'Cached inputs recorded but the artifact no longer verifies; rebuilding'
fi

# --------------------------------------------------------------------------
# 3. Build. Remove only this image's own prior outputs, never the build tree,
#    so a stale ISO can never be mistaken for the one about to be produced.
# --------------------------------------------------------------------------
for stale in "$ISO_PATH" "$CHECKSUM_PATH" "$PACKAGES_PATH" "$BUILD_INFO_PATH" "$MANIFEST_PATH"; do
  [ -e "$stale" ] || continue
  case "$stale" in
    "$OUT_DIR"/*) rm -f -- "$stale" ;;
    *) die "refusing to delete path outside the output directory: $stale" ;;
  esac
done
mkdir -p "$OUT_DIR" "$(dirname "$INPUT_MARKER")"

build_started="$(date +%s)"
log "Building the unified ShreeOS desktop image ($UNIFIED_PROFILE profile)"

SHREEOS_UNIFIED=1 \
SHREEOS_LIVE_PROFILE="$UNIFIED_PROFILE" \
  SHREEOS_OUTPUT_BASENAME="shreeos(${VERSION})" \
  SHREEOS_FIRMWARE="${SHREEOS_FIRMWARE:-standard}" \
  SHREEOS_TOOLSETS="${SHREEOS_TOOLSETS:-}" \
  bash scripts/build-debian-prototype.sh

for required in "$ISO_PATH" "$PACKAGES_PATH" "$BUILD_INFO_PATH"; do
  [ -s "$required" ] || die "the build did not produce $required"
done

iso_mtime="$(stat -c '%Y' "$ISO_PATH")"
[ "$iso_mtime" -ge "$build_started" ] ||
  die "$ISO_NAME is older than this build run; refusing to report a stale artifact"

# --------------------------------------------------------------------------
# 4. Checksums and the build manifest. The manifest is the machine-readable
#    provenance record GitHub Actions asserts against before publishing.
# --------------------------------------------------------------------------
(cd "$OUT_DIR" && sha256sum -- "$ISO_NAME" > "$(basename -- "$CHECKSUM_PATH")")
sha256="$(awk 'NR == 1 {print $1}' "$CHECKSUM_PATH")"
size_bytes="$(stat -c '%s' "$ISO_PATH")"
if git -C "$REPO_ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  commit="$(git -C "$REPO_ROOT" rev-parse HEAD)"
  dirty=0
  if [ -n "$(git -C "$REPO_ROOT" status --porcelain --untracked-files=all)" ]; then
    dirty=1
  fi
else
  # actions/checkout falls back to a clean source archive in minimal Debian
  # build containers that do not contain Git. Preserve its immutable commit
  # identity instead of writing "unknown" into an otherwise verified build.
  commit="${GITHUB_SHA:-unknown}"
  if [[ "$commit" =~ ^[0-9a-f]{40}$ ]]; then dirty=0; else dirty=1; fi
fi

test "$(awk -F= '$1 == "git_commit" { print $2; exit }' "$BUILD_INFO_PATH")" = "$commit"
test "$(awk -F= '$1 == "git_dirty" { print $2; exit }' "$BUILD_INFO_PATH")" = "$dirty"
test "$(awk -F= '$1 == "sha256" { print $2; exit }' "$BUILD_INFO_PATH")" = "$sha256"
test "$(awk -F= '$1 == "size_bytes" { print $2; exit }' "$BUILD_INFO_PATH")" = "$size_bytes"
test -n "$(awk -F= '$1 == "built_at" { print $2; exit }' "$BUILD_INFO_PATH")"

ISO_NAME="$ISO_NAME" ISO_PATH="$ISO_PATH" ISO_SHA256="$sha256" ISO_SIZE="$size_bytes" \
  VERSION="$VERSION" PROFILE="$UNIFIED_PROFILE" ARCH="$SHREEOS_ARCH" \
  SUITE="$DEBIAN_SUITE" SNAPSHOT="$DEBIAN_SNAPSHOT" LIVE_BUILD="$LIVE_BUILD_VERSION" \
  COMMIT="$commit" DIRTY="$dirty" BUILD_INFO="$BUILD_INFO_PATH" \
  python3 - "$MANIFEST_PATH" <<'PY'
import hashlib
import json
import os
import sys
from pathlib import Path

out = {key: os.environ[env] for key, env in (
    ("version", "VERSION"),
    ("profile", "PROFILE"),
    ("architecture", "ARCH"),
    ("base_distribution", "SUITE"),
    ("base_snapshot", "SNAPSHOT"),
    ("live_build", "LIVE_BUILD"),
    ("commit", "COMMIT"),
)}
out["name"] = "ShreeOS"
out["products"] = ["live", "installed"]
out["iso"] = os.environ["ISO_NAME"]
out["sha256"] = os.environ["ISO_SHA256"]
out["size_bytes"] = int(os.environ["ISO_SIZE"])
out["git_dirty"] = os.environ["DIRTY"] == "1"
out["built_at"] = next(
    line.split("=", 1)[1]
    for line in Path(os.environ["BUILD_INFO"]).read_text().splitlines()
    if line.startswith("built_at=")
)
out["components"] = {
    line.split("=", 1)[0]: line.split("=", 1)[1]
    for line in Path(os.environ["BUILD_INFO"]).read_text().splitlines()
    if line.split("=", 1)[0] in {
        "kernel", "plasma", "kwin", "sddm", "shreeos_tools", "shreeos_native_tools"
    }
}
# The manifest must describe the bytes actually on disk.
iso = Path(os.environ["ISO_PATH"])
with iso.open("rb") as stream:
    digest = hashlib.file_digest(stream, "sha256").hexdigest()
if digest != out["sha256"]:
    raise SystemExit("manifest digest does not match the built image")
if iso.stat().st_size != out["size_bytes"]:
    raise SystemExit("manifest size does not match the built image")
Path(sys.argv[1]).write_text(json.dumps(out, indent=2, sort_keys=True) + "\n")
print(f"Manifest written for {out['iso']} ({out['size_bytes']} bytes)")
PY

python3 "$REPO_ROOT/scripts/verify-unified-artifact.py" \
  "$ISO_PATH" "$CHECKSUM_PATH" "$PACKAGES_PATH" "$BUILD_INFO_PATH" \
  "$MANIFEST_PATH" "$VERSION" "$UNIFIED_PROFILE" "$SHREEOS_ARCH" \
  "$DEBIAN_SUITE" "$DEBIAN_SNAPSHOT" "$LIVE_BUILD_VERSION"
bash scripts/verify-version.sh --iso "$ISO_PATH"
printf '%s\n' "$current_hash" >"$INPUT_MARKER"

log "Unified ShreeOS image ready:"
printf '    %s\n    %s\n    %s\n    %s\n    %s\n' \
  "$ISO_PATH" "$CHECKSUM_PATH" "$PACKAGES_PATH" "$BUILD_INFO_PATH" "$MANIFEST_PATH"
