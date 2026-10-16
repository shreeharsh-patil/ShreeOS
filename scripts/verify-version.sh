#!/usr/bin/env bash
# Validate the single-authoritative-version contract.
#
# The repository-root VERSION file is the only place a ShreeOS version may be
# written down. Everything else derives from it, so this script exists to fail
# loudly when a file drifts, when an artifact would be misnamed, or when a
# release tag does not match the image it claims to describe.
#
# Usage:
#   scripts/verify-version.sh                 # repository contract only
#   scripts/verify-version.sh --tag v0.4.0    # also require the tag to match
#   scripts/verify-version.sh --iso PATH      # also require an ISO to be named for the version
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)"

expected_tag=""
iso_path=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --tag)
      [ "$#" -ge 2 ] || { echo 'verify-version.sh: --tag needs a value' >&2; exit 2; }
      expected_tag="$2"
      shift 2
      ;;
    --iso)
      [ "$#" -ge 2 ] || { echo 'verify-version.sh: --iso needs a value' >&2; exit 2; }
      iso_path="$2"
      shift 2
      ;;
    -h | --help)
      sed -n '2,12p' "${BASH_SOURCE[0]}"
      exit 0
      ;;
    *)
      echo "verify-version.sh: unexpected argument '$1'" >&2
      exit 2
      ;;
  esac
done

fail() {
  printf 'VERSION CONTRACT FAILED: %s\n' "$*" >&2
  exit 1
}

# --- The single source ------------------------------------------------------
version_file="$REPO_ROOT/VERSION"
[ -s "$version_file" ] || fail "missing version source: $version_file"
VERSION="$(tr -d '[:space:]' < "$version_file")"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z][0-9A-Za-z.-]*)?$ ]] ||
  fail "VERSION '$VERSION' is not MAJOR.MINOR.PATCH with an optional -suffix"
[ "$(wc -l < "$version_file")" -le 1 ] ||
  fail 'VERSION must contain exactly one line'

# --- Every derived consumer must agree --------------------------------------
# Sourced rather than grepped: these files compute the value at source time, so
# sourcing proves the derivation actually works instead of matching a literal.
build_conf_version="$(
  cd "$REPO_ROOT"
  # shellcheck source=/dev/null
  source ./build.conf >/dev/null
  printf '%s\n' "$DISTRO_VERSION"
)"
[ "$build_conf_version" = "$VERSION" ] ||
  fail "build.conf resolved DISTRO_VERSION='$build_conf_version', expected '$VERSION'"

build_conf_iso_name="$(
  cd "$REPO_ROOT"
  # shellcheck source=/dev/null
  source ./build.conf >/dev/null
  printf '%s\n' "$SHREEOS_ISO_NAME"
)"
[ "$build_conf_iso_name" = "shreeos($VERSION).iso" ] ||
  fail "build.conf resolved SHREEOS_ISO_NAME='$build_conf_iso_name', expected 'shreeos($VERSION).iso'"

prototype_version="$(
  cd "$REPO_ROOT"
  # shellcheck source=/dev/null
  source ./prototype/debian-live/versions.conf >/dev/null
  # PROTOTYPE_VERSION is assigned by the sourced file above. The linter cannot
  # see through that source, so its "may not be assigned" guess is wrong here.
  # Sourcing is deliberate: it proves the derivation works rather than
  # pattern-matching a literal.
  # shellcheck disable=SC2153
  printf '%s\n' "$PROTOTYPE_VERSION"
)"
[ "$prototype_version" = "$VERSION" ] ||
  fail "versions.conf resolved PROTOTYPE_VERSION='$prototype_version', expected '$VERSION'"

# The image's own os-release is a build-time template: the builder substitutes
# the version while the image is assembled, so the shipped /etc/os-release can
# never drift from VERSION. The template must therefore carry placeholders and
# must NOT carry a literal version.
os_release="$REPO_ROOT/prototype/debian-live/config/includes.chroot/etc/os-release"
if [ -s "$os_release" ]; then
  grep -Fq '@VERSION@' "$os_release" ||
    fail 'etc/os-release template lost its @VERSION@ placeholder'
  grep -Fq '@VERSION_ID@' "$os_release" ||
    fail 'etc/os-release template lost its @VERSION_ID@ placeholder'
  if grep -Eq '^VERSION(_ID)?="?[0-9]' "$os_release"; then
    fail 'etc/os-release hardcodes a version; it must keep the @VERSION@ placeholders'
  fi
fi

calamares_branding="$REPO_ROOT/prototype/debian-live/profiles/desktop/includes.chroot/etc/calamares/branding/shreeos/branding.desc"
if [ -s "$calamares_branding" ]; then
  grep -Fq 'version: @VERSION@' "$calamares_branding" ||
    fail 'Calamares branding must derive version from the @VERSION@ placeholder'
  grep -Fq 'shortVersion: @VERSION@' "$calamares_branding" ||
    fail 'Calamares short version must derive from the @VERSION@ placeholder'
  grep -Fq 'versionedName: ShreeOS @VERSION@' "$calamares_branding" ||
    fail 'Calamares versioned product name must derive from the @VERSION@ placeholder'
  grep -Fq 'shortVersionedName: ShreeOS @VERSION@' "$calamares_branding" ||
    fail 'Calamares short product name must derive from the @VERSION@ placeholder'
  if grep -Eq '^[[:space:]]*(version|shortVersion):[[:space:]]*[0-9]' "$calamares_branding"; then
    fail 'Calamares branding hardcodes a version instead of using @VERSION@'
  fi
fi

# --- No second version literal may reappear ---------------------------------
# A hardcoded *previous* version anywhere in the tree is exactly the drift this
# contract exists to prevent, so the scan covers the whole repository rather
# than a hand-maintained list of paths -- a list is what let stale literals
# survive in the legacy native userland.
#
# Deliberately excluded, with reasons:
#   .git, build/, out/            not source
#   __pycache__, *.pyc            generated bytecode
#   CHANGELOG.md, docs/audit/**   historical records of what past releases were
#   tests/audit/**                synthetic fixtures in its own temporary tree
#   tests/release/test-version-contract.sh
#                                 plants a stale literal on purpose, to prove
#                                 this very check fails when it should
stale="$(
  cd "$REPO_ROOT"
  grep -rnIE '(0\.3\.0-prototype|4\.0\.0-dev|0\.2\.2-dev)' \
    --exclude-dir=.git --exclude-dir=build --exclude-dir=out \
    --exclude-dir=__pycache__ --exclude-dir=.freebuff --exclude-dir=.probe \
    --exclude='*.pyc' --exclude='CHANGELOG.md' \
    . 2>/dev/null |
    grep -vE '^\./(tests/audit/|tests/release/test-version-contract\.sh|docs/audit/)' ||
    true
)"
if [ -n "$stale" ]; then
  printf 'VERSION CONTRACT FAILED: hardcoded version literals remain in live files:\n%s\n' "$stale" >&2
  exit 1
fi

# --- Optional: release tag ---------------------------------------------------
if [ -n "$expected_tag" ]; then
  case "$expected_tag" in
    "v$VERSION" | "v$VERSION-build."* | "v$VERSION+build."*) ;;
    *) fail "release tag '$expected_tag' does not describe ShreeOS $VERSION" ;;
  esac
fi

# --- Optional: artifact name -------------------------------------------------
if [ -n "$iso_path" ]; then
  iso_name="$(basename -- "$iso_path")"
  [ "$iso_name" = "shreeos($VERSION).iso" ] ||
    fail "release ISO is named '$iso_name'; the mandated name is 'shreeos($VERSION).iso'"
  case "$iso_name" in
    *-plasma* | *-native* | *-desktop* | *-prototype* | *-amd64* | *-base*)
      fail "release ISO '$iso_name' carries a forbidden suffix"
      ;;
  esac
fi

printf 'Version contract OK: %s -> %s + shreeos(%s).iso\n' \
  'VERSION' "$VERSION" "$VERSION"
