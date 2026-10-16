#!/usr/bin/env bash
# Release-side regression test for the version and filename contract.
#
# scripts/verify-version.sh enforces the contract for the real tree. This test
# proves the enforcement actually works, including the failure modes, using a
# synthetic copy so it never has to mutate the checkout.
set -Eeuo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
verifier="$REPO_ROOT/scripts/verify-version.sh"
[ -x "$verifier" ] || { echo "Missing verifier: $verifier" >&2; exit 1; }

TMP="$(mktemp -d)"
trap 'rm -rf -- "$TMP"' EXIT

pass() { printf '  ok: %s\n' "$1"; }
fail() {
  printf 'Version contract test FAILED: %s\n' "$1" >&2
  exit 1
}

# A synthetic tree that satisfies the contract.
build_fixture() {
  local root="$1" version="$2"
  mkdir -p "$root/scripts" "$root/prototype/debian-live/config/includes.chroot/etc"
  cp "$verifier" "$root/scripts/verify-version.sh"
  chmod 755 "$root/scripts/verify-version.sh"
  printf '%s\n' "$version" >"$root/VERSION"
  cat >"$root/build.conf" <<'EOF'
export DISTRO_VERSION="$(tr -d '[:space:]' < "$(dirname "${BASH_SOURCE[0]}")/VERSION")"
export DISTRO_ID="shreeos"
export SHREEOS_ISO_NAME="${DISTRO_ID}(${DISTRO_VERSION}).iso"
EOF
  cat >"$root/prototype/debian-live/versions.conf" <<'EOF'
PROTOTYPE_VERSION="$(tr -d '[:space:]' < "$(dirname "${BASH_SOURCE[0]}")/../../VERSION")"
EOF
  cat >"$root/prototype/debian-live/config/includes.chroot/etc/os-release" <<'EOF'
ID=shreeos
VERSION="@VERSION@"
VERSION_ID="@VERSION_ID@"
EOF
}

# --- The real tree satisfies the contract -----------------------------------
bash "$verifier" || fail 'the checked-out tree violates its own version contract'
pass 'repository satisfies the version contract'

version="$(tr -d '[:space:]' < "$REPO_ROOT/VERSION")"
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z][0-9A-Za-z.-]*)?$ ]] ||
  fail "VERSION '$version' is not a release version"
pass "VERSION is $version"

# --- The mandate: exactly shreeos(VERSION).iso ------------------------------
expected="shreeos($version).iso"
resolved="$(
  cd "$REPO_ROOT"
  # shellcheck source=/dev/null
  source ./build.conf >/dev/null
  printf '%s\n' "$SHREEOS_ISO_NAME"
)"
[ "$resolved" = "$expected" ] ||
  fail "build.conf resolves the release image to '$resolved', expected '$expected'"
pass "release artifact name is $expected"

for forbidden in -plasma -native -desktop -prototype -amd64 -base; do
  case "$resolved" in
    *"$forbidden"*) fail "release artifact name carries the forbidden suffix '$forbidden'" ;;
  esac
done
pass 'release artifact name carries no profile or architecture suffix'

case "$resolved" in
  *VERSION*) fail 'the literal word VERSION leaked into the artifact name' ;;
esac
pass 'the literal word VERSION is not in the artifact name'

# --- Enforcement actually fails when it should ------------------------------
fixture="$TMP/fixture"
build_fixture "$fixture" "$version"
bash "$fixture/scripts/verify-version.sh" >/dev/null ||
  fail 'the verifier rejects a valid synthetic tree'
pass 'verifier accepts a consistent tree'

# A drifting versions.conf must be caught.
printf 'PROTOTYPE_VERSION="9.9.9"\n' >>"$fixture/prototype/debian-live/versions.conf"
if bash "$fixture/scripts/verify-version.sh" >/dev/null 2>&1; then
  fail 'verifier accepted a versions.conf that disagrees with VERSION'
fi
pass 'verifier rejects a drifting image version'
build_fixture "$fixture" "$version"

# A re-hardcoded version must be caught.
printf 'export THING=0.3.0-prototype\n' >>"$fixture/build.conf"
if bash "$fixture/scripts/verify-version.sh" >/dev/null 2>&1; then
  fail 'verifier accepted a hardcoded version literal'
fi
pass 'verifier rejects a hardcoded version literal'
build_fixture "$fixture" "$version"

# A hardcoded os-release must be caught.
sed -i 's/^VERSION="@VERSION@"$/VERSION="0.9.9"/' \
  "$fixture/prototype/debian-live/config/includes.chroot/etc/os-release"
if bash "$fixture/scripts/verify-version.sh" >/dev/null 2>&1; then
  fail 'verifier accepted a hardcoded image os-release'
fi
pass 'verifier rejects a hardcoded image version'
build_fixture "$fixture" "$version"

# --- Tag and artifact arguments ---------------------------------------------
bash "$verifier" --tag "v$version" >/dev/null || fail "verifier rejected the tag v$version"
bash "$verifier" --tag "v$version-build.1234" >/dev/null ||
  fail 'verifier rejected a build-qualified tag'
if bash "$verifier" --tag 'v9.9.9' >/dev/null 2>&1; then
  fail 'verifier accepted a tag that does not describe the image'
fi
pass 'tag validation accepts matching tags and rejects others'

release_workflow="$REPO_ROOT/.github/workflows/shreeos-release.yml"
grep -Fq 'pull_request:' "$release_workflow" ||
  fail 'the unified release checks do not run for pull requests'
grep -Fq 'gh release view "$tag"' "$release_workflow" ||
  fail 'published release verification does not use the selected tag'
grep -Fq 'RELEASE_TAG="$tag"' "$release_workflow" ||
  fail 'published release verification does not check the selected tag'
grep -Fq 'sha256sum build.conf' "$REPO_ROOT/scripts/build-shreeos.sh" ||
  fail 'the unified ISO cache key omits build.conf'
pass 'pull request checks, selected release tags, and build configuration cache inputs are enforced'

iso_dir="$TMP/iso"
mkdir -p "$iso_dir"
: >"$iso_dir/$expected"
bash "$verifier" --iso "$iso_dir/$expected" >/dev/null ||
  fail 'verifier rejected the mandated ISO filename'
pass "verifier accepts $expected"

for wrong in "shreeos-${version}-plasma-amd64.iso" "shreeos-${version}-amd64.iso" \
  "shreeos-${version}-prototype.iso"; do
  : >"$iso_dir/$wrong"
  if bash "$verifier" --iso "$iso_dir/$wrong" >/dev/null 2>&1; then
    fail "verifier accepted the misnamed artifact $wrong"
  fi
done
pass 'verifier rejects suffixed release filenames'

printf 'Release version contract tests passed.\n'
