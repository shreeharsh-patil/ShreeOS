#!/usr/bin/env bash
# Verify recovery archives stay private and omit personal and mounted data.
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
BUILDER="$PROJECT_ROOT/installer/scripts/build-recovery-initramfs.sh"
TEST_ROOT="$(mktemp -d)"
trap 'rm -rf -- "$TEST_ROOT"' EXIT

for command in cpio find gzip sha256sum stat; do
  command -v "$command" >/dev/null 2>&1 || {
    echo "Required recovery-test command is missing: $command" >&2
    exit 1
  }
done

ROOT="$TEST_ROOT/root"
OUT="$TEST_ROOT/out"
mkdir -p "$ROOT"/{etc,home/alice/.ssh,root/.ssh,proc/1,sys/kernel,dev,run,boot,mnt,media} "$OUT"
printf 'init\n' > "$ROOT/init"
printf 'system account data\n' > "$ROOT/etc/passwd"
printf 'system auth data\n' > "$ROOT/etc/shadow"
printf 'private user key\n' > "$ROOT/home/alice/.ssh/id_rsa"
printf 'private root key\n' > "$ROOT/root/.ssh/id_rsa"
printf 'mounted process data\n' > "$ROOT/proc/1/cmdline"
printf 'old kernel image\n' > "$ROOT/boot/bzImage"
printf 'mounted data\n' > "$ROOT/mnt/disk-image"

ARCHIVE="$OUT/initramfs.cpio.gz"
bash "$BUILDER" "$ROOT" "$ARCHIVE"
gzip -t -- "$ARCHIVE"
[ "$(stat -c '%a' -- "$ARCHIVE")" = 600 ] || {
  echo "Recovery initramfs permissions must be 0600" >&2
  exit 1
}
gzip -dc -- "$ARCHIVE" | cpio --list --quiet > "$TEST_ROOT/archive.list"

for required in init etc/passwd etc/shadow home root proc boot mnt; do
  grep -Fxq "./$required" "$TEST_ROOT/archive.list" || {
    echo "Recovery initramfs is missing required system entry: $required" >&2
    exit 1
  }
done
for forbidden in home/alice/.ssh/id_rsa root/.ssh/id_rsa proc/1/cmdline boot/bzImage mnt/disk-image; do
  if grep -Fxq "./$forbidden" "$TEST_ROOT/archive.list"; then
    echo "Recovery initramfs contains excluded personal or mounted data: $forbidden" >&2
    exit 1
  fi
done

before="$(sha256sum "$ARCHIVE" | awk '{print $1}')"
rm -f -- "$ROOT/init"
if bash "$BUILDER" "$ROOT" "$ARCHIVE" >/dev/null 2>&1; then
  echo "Recovery builder accepted an archive without /init" >&2
  exit 1
fi
after="$(sha256sum "$ARCHIVE" | awk '{print $1}')"
[ "$before" = "$after" ] || {
  echo "Failed recovery rebuild replaced the existing initramfs" >&2
  exit 1
}

echo "Recovery initramfs confidentiality and atomicity checks passed."
