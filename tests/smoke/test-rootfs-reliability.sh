#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
TEST_ROOT="$(mktemp -d)"
trap 'rm -rf "$TEST_ROOT"' EXIT

fail() {
  echo "  [FAIL] $*" >&2
  exit 1
}

assert_mode() {
  local path="$1" expected="$2" actual
  actual="$(stat -c '%a' -- "$path")"
  [ "$actual" = "$expected" ] || fail "expected mode $expected at $path, got $actual"
}

make_executable() {
  local path="$1"
  mkdir -p "$(dirname "$path")"
  printf '#!/bin/sh\nexit 0\n' > "$path"
  chmod 755 "$path"
}

export SHREEOS_BUILD_DIR="$TEST_ROOT/build"
export SHREEOS_STAGE_ROOT="$TEST_ROOT/stage"
export SHREEOS_SYSROOT="$TEST_ROOT/sysroot"
export SHREEOS_TOOLS="$TEST_ROOT/tools"
export SHREEOS_OUT="$TEST_ROOT/out"
export SHREEOS_SOURCES="$TEST_ROOT/sources"
export MKNOD_LOG="$TEST_ROOT/mknod.log"
export PATH="$TEST_ROOT/bin:$PATH"

mkdir -p "$TEST_ROOT/bin"
cat > "$TEST_ROOT/bin/mknod" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
while [ "$#" -gt 0 ]; do
  case "$1" in
    -m)
      mode="$2"
      shift 2
      ;;
    *)
      break
      ;;
  esac
done
: > "$1"
printf '%s %s\n' "$mode" "$1" >> "$MKNOD_LOG"
EOF
chmod 755 "$TEST_ROOT/bin/mknod"

bash "$PROJECT_ROOT/base-system/scripts/setup-rootfs.sh" >/dev/null
assert_mode "$SHREEOS_STAGE_ROOT/root" 700
assert_mode "$SHREEOS_STAGE_ROOT/etc/shadow" 600

bash "$PROJECT_ROOT/rootfs/scripts/populate-devices.sh" "$SHREEOS_STAGE_ROOT" >/dev/null
assert_mode "$SHREEOS_STAGE_ROOT/dev/console" 600
grep -Fxq "600 $SHREEOS_STAGE_ROOT/dev/console" "$MKNOD_LOG" || \
  fail "console was not created with mode 0600"
echo "  [OK] Rootfs security modes are enforced"

for path in \
  usr/bin/bash usr/bin/ls usr/bin/mount bin/bash bin/sh \
  sbin/init sbin/initctl usr/bin/initctl \
  sbin/shree-auth usr/bin/shree-auth \
  bin/lpm usr/bin/lpm usr/sbin/shreed usr/bin/shreedctl; do
  make_executable "$SHREEOS_STAGE_ROOT/$path"
done
for service in 00-sysinit.conf 10-hostname.conf 20-network.conf 30-shreed.conf 90-console.conf; do
  mkdir -p "$SHREEOS_STAGE_ROOT/etc/services.d"
  cp "$PROJECT_ROOT/init/services/$service" "$SHREEOS_STAGE_ROOT/etc/services.d/$service"
done
mkdir -p "$SHREEOS_SYSROOT/usr/lib" "$SHREEOS_STAGE_ROOT/usr/share"
printf 'fixture-libc\n' > "$SHREEOS_SYSROOT/usr/lib/libc.so.6"
printf 'fixture-loader\n' > "$SHREEOS_SYSROOT/usr/lib/ld-linux-x86-64.so.2"
for index in $(seq 1 4096); do
  printf 'rootfs-determinism-fixture-%08d\n' "$index"
done > "$SHREEOS_STAGE_ROOT/usr/share/rootfs-determinism-fixture"

NO_COLOR=1 bash "$PROJECT_ROOT/rootfs/scripts/make-rootfs.sh" --skip-init \
  > "$TEST_ROOT/rootfs.log" 2>&1
ARCHIVE="$SHREEOS_BUILD_DIR/initramfs.cpio.gz"
gzip -t -- "$ARCHIVE"
[ "$(stat -c '%s' -- "$ARCHIVE")" -ge 1024 ]
gzip -dc -- "$ARCHIVE" | cpio --list --quiet > "$TEST_ROOT/archive.list"
for entry in \
  init sbin/init sbin/initctl usr/bin/initctl \
  sbin/shree-auth usr/bin/shree-auth bin/lpm usr/bin/lpm \
  usr/sbin/shreed usr/bin/shreedctl \
  etc/services.d/00-sysinit.conf etc/services.d/10-hostname.conf \
  etc/services.d/20-network.conf etc/services.d/30-shreed.conf \
  etc/services.d/90-console.conf; do
  if ! grep -Fxq "$entry" "$TEST_ROOT/archive.list" && \
     ! grep -Fxq "./$entry" "$TEST_ROOT/archive.list" && \
     ! grep -Fxq "/$entry" "$TEST_ROOT/archive.list"; then
    fail "archive is missing /$entry"
  fi
done
echo "  [OK] Initramfs passes gzip, size, and required-entry checks"

for path in \
  sbin/initctl usr/bin/initctl sbin/shree-auth usr/bin/shree-auth \
  bin/lpm usr/bin/lpm usr/sbin/shreed usr/bin/shreedctl; do
  rm -f "$SHREEOS_STAGE_ROOT/$path"
  if NO_COLOR=1 bash "$PROJECT_ROOT/rootfs/scripts/make-rootfs.sh" --skip-init \
      > "$TEST_ROOT/missing.log" 2>&1; then
    fail "missing required executable /$path did not fail"
  fi
  grep -Fq "Missing required rootfs executable output: /$path" "$TEST_ROOT/missing.log" || \
    fail "missing /$path did not produce the required diagnostic"
  make_executable "$SHREEOS_STAGE_ROOT/$path"
done
for service in 00-sysinit.conf 10-hostname.conf 20-network.conf 30-shreed.conf 90-console.conf; do
  rm -f "$SHREEOS_STAGE_ROOT/etc/services.d/$service"
  if NO_COLOR=1 bash "$PROJECT_ROOT/rootfs/scripts/make-rootfs.sh" --skip-init \
      > "$TEST_ROOT/missing.log" 2>&1; then
    fail "missing required service $service did not fail"
  fi
  grep -Fq "Missing required rootfs service output: /etc/services.d/$service" "$TEST_ROOT/missing.log" || \
    fail "missing service $service did not produce the required diagnostic"
  cp "$PROJECT_ROOT/init/services/$service" "$SHREEOS_STAGE_ROOT/etc/services.d/$service"
done
echo "  [OK] Required executables and service definitions fail closed"
echo "==> Rootfs reliability test passed"
