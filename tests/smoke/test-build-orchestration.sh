#!/usr/bin/env bash
# Guard the boundary between GNU Make expansion and the package-stage shell.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

echo "==> Testing ShreeOS build orchestration"

TEST_ROOT="$(mktemp -d /tmp/shreeos-build-test.XXXXXX)"
trap 'rm -rf "$TEST_ROOT"' EXIT

# MAKE=true keeps recursive-make commands harmless while still expanding the
# exact shell recipe that the real package stage executes.
DRY_RUN="$(make -C "$PROJECT_ROOT" -n -B MAKE=true PROFILE=minimal packages)"

grep -Fq 'export PATH="$SHREEOS_TOOLS/bin:$PATH"' <<<"$DRY_RUN" || {
  echo "  [FAIL] Package-stage PATH was corrupted by Make expansion" >&2
  exit 1
}
grep -Fq 'export CROSS_COMPILE="$SHREEOS_TARGET_TRIPLET-"' <<<"$DRY_RUN" || {
  echo "  [FAIL] Package-stage cross-compiler prefix was corrupted by Make expansion" >&2
  exit 1
}
grep -Fq 'CROSS_COMPILE="$CROSS_COMPILE"' <<<"$DRY_RUN" || {
  echo "  [FAIL] Recursive package builds did not receive CROSS_COMPILE" >&2
  exit 1
}

if grep -Eq 'PATH="HREEOS_TOOLS|:ATH"|CROSS_COMPILE="(HREEOS_TARGET_TRIPLET|ROSS_COMPILE)' <<<"$DRY_RUN"; then
  echo "  [FAIL] Dry-run contains a Make-stripped shell variable" >&2
  exit 1
fi

echo "  [OK] Package-stage shell variables survive GNU Make expansion"

# DESTDIR-generated Libtool archives contain absolute target paths and must
# never be copied into the cross sysroot.  Verify that synchronization keeps
# the real shared library while removing stale .la metadata from both trees.
(
  export SHREEOS_BUILD_DIR="$TEST_ROOT/build"
  export SHREEOS_STAGE_ROOT="$TEST_ROOT/stage"
  export SHREEOS_SYSROOT="$TEST_ROOT/sysroot"
  # shellcheck source=/dev/null
  source "$PROJECT_ROOT/base-system/scripts/common.sh"
  mkdir -p "$SHREEOS_STAGE_ROOT/usr/lib"
  printf 'dependency_libs=/usr/lib/libdependency.la\n' > "$SHREEOS_STAGE_ROOT/usr/lib/libexample.la"
  printf 'target shared object\n' > "$SHREEOS_STAGE_ROOT/usr/lib/libexample.so"
  base_sync_sysroot
  [ ! -e "$SHREEOS_STAGE_ROOT/usr/lib/libexample.la" ]
  [ ! -e "$SHREEOS_SYSROOT/usr/lib/libexample.la" ]
  [ -s "$SHREEOS_SYSROOT/usr/lib/libexample.so" ]
) || {
  echo "  [FAIL] Sysroot synchronization retained unsafe Libtool metadata" >&2
  exit 1
}

echo "  [OK] Sysroot synchronization discards unsafe Libtool archives"
echo "==> Build orchestration test passed"
