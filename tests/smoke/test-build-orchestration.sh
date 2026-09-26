#!/usr/bin/env bash
# Guard the boundary between GNU Make expansion and the package-stage shell.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

echo "==> Testing ShreeOS build orchestration"

TEST_ROOT="$(mktemp -d /tmp/shreeos-build-test.XXXXXX)"
trap 'rm -rf "$TEST_ROOT"' EXIT

DEFAULT_HELP="$(make -s -C "$PROJECT_ROOT" help)"
grep -Fq 'Active Profile: desktop' <<<"$DEFAULT_HELP" || {
  echo "  [FAIL] Desktop is not the default build profile" >&2
  exit 1
}
grep -Fq '(default: desktop)' <<<"$DEFAULT_HELP" || {
  echo "  [FAIL] Help does not report the desktop default profile" >&2
  exit 1
}

MINIMAL_DESKTOP_DRY_RUN="$(make -n -B -C "$PROJECT_ROOT" PROFILE=minimal desktop)"
if grep -Fq 'bash desktop/wm/build-all.sh' <<<"$MINIMAL_DESKTOP_DRY_RUN"; then
  echo "  [FAIL] Minimal profile unexpectedly builds the desktop suite" >&2
  exit 1
fi
DESKTOP_DRY_RUN="$(make -n -B -C "$PROJECT_ROOT" PROFILE=desktop desktop)"
grep -Fq 'bash desktop/wm/build-all.sh' <<<"$DESKTOP_DRY_RUN" || {
  echo "  [FAIL] Explicit desktop profile no longer builds the desktop suite" >&2
  exit 1
}
echo "  [OK] Desktop is default and explicit minimal/desktop behavior is preserved"

if grep -Eq 'make -C .* clean all' "$PROJECT_ROOT/rootfs/scripts/make-rootfs.sh"; then
  echo "  [FAIL] Rootfs assembly still force-rebuilds Phase 4 packages" >&2
  exit 1
fi
echo "  [OK] Rootfs assembly reuses incremental Phase 4 artifacts"

cat > "$TEST_ROOT/color-check.sh" <<'EOF'
source "$1"
shreeos_ok ok
shreeos_warn warn
EOF
NONINTERACTIVE_OUTPUT="$(env -u NO_COLOR bash "$TEST_ROOT/color-check.sh" "$PROJECT_ROOT/scripts/common.sh" 2>&1)"
if [[ "$NONINTERACTIVE_OUTPUT" == *$'\033['* ]]; then
  echo "  [FAIL] Noninteractive logging emitted ANSI color" >&2
  exit 1
fi
if command -v script >/dev/null 2>&1; then
  NO_COLOR_OUTPUT="$(env NO_COLOR= script -qefc "bash '$TEST_ROOT/color-check.sh' '$PROJECT_ROOT/scripts/common.sh'" /dev/null 2>&1)"
  if [[ "$NO_COLOR_OUTPUT" == *$'\033['* ]]; then
    echo "  [FAIL] NO_COLOR logging emitted ANSI color on a terminal" >&2
    exit 1
  fi
fi
echo "  [OK] ANSI color honors NO_COLOR and noninteractive output"

# MAKE=true keeps recursive-make commands harmless while still expanding the
# exact shell recipe that the real package stage executes.
DRY_RUN="$(make -C "$PROJECT_ROOT" -n -B MAKE=true PROFILE=minimal packages)"

grep -Fq "export PATH=\"\$SHREEOS_TOOLS/bin:\$PATH\"" <<<"$DRY_RUN" || {
  echo "  [FAIL] Package-stage PATH was corrupted by Make expansion" >&2
  exit 1
}
grep -Fq "export CROSS_COMPILE=\"\$SHREEOS_TARGET_TRIPLET-\"" <<<"$DRY_RUN" || {
  echo "  [FAIL] Package-stage cross-compiler prefix was corrupted by Make expansion" >&2
  exit 1
}
grep -Fq "CROSS_COMPILE=\"\$CROSS_COMPILE\"" <<<"$DRY_RUN" || {
  echo "  [FAIL] Recursive package builds did not receive CROSS_COMPILE" >&2
  exit 1
}
grep -Fq "bash -c 'set -e; source build.conf" <<<"$DRY_RUN" || {
  echo "  [FAIL] Package-stage shell can mask an earlier component failure" >&2
  exit 1
}

if grep -Eq 'PATH="HREEOS_TOOLS|:ATH"|CROSS_COMPILE="(HREEOS_TARGET_TRIPLET|ROSS_COMPILE)' <<<"$DRY_RUN"; then
  echo "  [FAIL] Dry-run contains a Make-stripped shell variable" >&2
  exit 1
fi

echo "  [OK] Package-stage shell variables survive GNU Make expansion"

# DESTDIR-generated Libtool archives contain absolute target paths and must
# never be copied into the cross sysroot. Verify that synchronization keeps
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
