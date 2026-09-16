#!/usr/bin/env bash
# Validate that installed-disk boots leave the initramfs and enter the on-disk
# ShreeOS root filesystem.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
INITRAMFS_INIT="$ROOT_DIR/rootfs/scripts/initramfs-init.sh"
ROOTFS_BUILDER="$ROOT_DIR/rootfs/scripts/make-rootfs.sh"
DISK_GRUB="$ROOT_DIR/bootloader/scripts/install-grub-disk.sh"

echo "==> Testing initramfs installed-root handoff"

[ -f "$INITRAMFS_INIT" ] || {
  echo "  [FAIL] Missing initramfs handoff script" >&2
  exit 1
}
sh -n "$INITRAMFS_INIT"
echo "  [OK] initramfs handoff script is shell-syntax valid"

grep -Fq 'root=*)' "$INITRAMFS_INIT" || {
  echo "  [FAIL] /init does not parse root= from the kernel command line" >&2
  exit 1
}
grep -Fq 'blkid -U' "$INITRAMFS_INIT" || {
  echo "  [FAIL] /init does not resolve root=UUID" >&2
  exit 1
}
grep -Fq 'mount -o rw "$ROOT_DEV" /newroot' "$INITRAMFS_INIT" || {
  echo "  [FAIL] /init does not mount the installed root filesystem" >&2
  exit 1
}
grep -Fq 'exec switch_root /newroot /sbin/init' "$INITRAMFS_INIT" || {
  echo "  [FAIL] /init does not switch into the installed root" >&2
  exit 1
}
echo "  [OK] installed root is resolved, mounted, and handed to switch_root"

grep -Fq 'cp "$INITRAMFS_INIT" "${LUMEN_STAGE_ROOT}/init"' "$ROOTFS_BUILDER" || {
  echo "  [FAIL] rootfs builder does not stage the handoff script as /init" >&2
  exit 1
}
if grep -Fq 'ln -sfn sbin/init "${LUMEN_STAGE_ROOT}/init"' "$ROOTFS_BUILDER"; then
  echo "  [FAIL] rootfs builder still bypasses the handoff with /init -> /sbin/init" >&2
  exit 1
fi
echo "  [OK] rootfs build stages the handoff instead of the old symlink"

grep -Fq 'root=UUID=${ROOT_UUID}' "$DISK_GRUB" || {
  echo "  [FAIL] installed GRUB config does not pass root=UUID" >&2
  exit 1
}
grep -Fq 'initrd /boot/initramfs.cpio.gz' "$DISK_GRUB" || {
  echo "  [FAIL] installed GRUB config no longer loads the handoff initramfs" >&2
  exit 1
}
echo "  [OK] installed GRUB and initramfs handoff agree on root=UUID"

echo "==> Initramfs installed-root handoff tests passed"
