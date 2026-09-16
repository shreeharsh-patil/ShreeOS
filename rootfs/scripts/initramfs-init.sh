#!/bin/sh
# ShreeOS initramfs PID 1 shim.
#
# Live ISO boots have no root= argument and continue with the in-initramfs
# ShreeOS supervisor. Installed boots pass root=UUID=... from GRUB; in that
# case this shim mounts the real root and hands PID 1 to /sbin/init there.
set -eu

PATH=/usr/sbin:/usr/bin:/sbin:/bin
export PATH

log() {
  printf '%s\n' "ShreeOS initramfs: $*"
}

emergency_shell() {
  log "ERROR: $*"
  log "Dropping to emergency shell."
  exec /bin/sh
}

mkdir -p /proc /sys /dev /run /newroot

# Device discovery and UUID resolution need these filesystems before the real
# ShreeOS supervisor starts. Its own mount routine treats EBUSY as success.
mount -t proc proc /proc 2>/dev/null || true
mount -t sysfs sysfs /sys 2>/dev/null || true
mount -t devtmpfs devtmpfs /dev 2>/dev/null || true
mount -t tmpfs -o mode=0755 tmpfs /run 2>/dev/null || true

CMDLINE="$(cat /proc/cmdline 2>/dev/null || true)"
ROOT_SPEC=""
# Kernel command lines are space-delimited by definition. Disable pathname
# expansion while intentionally splitting the command line into arguments.
set -f
# shellcheck disable=SC2086
for arg in $CMDLINE; do
  case "$arg" in
    root=*)
      ROOT_SPEC="${arg#root=}"
      ;;
  esac
done
set +f

# The live ISO intentionally has no root= device; its cpio archive is the
# complete runtime, so continue directly with the ShreeOS supervisor.
if [ -z "$ROOT_SPEC" ]; then
  exec /sbin/init
fi

command -v blkid >/dev/null 2>&1 ||
  emergency_shell "blkid is unavailable; cannot resolve installed root '$ROOT_SPEC'."
command -v switch_root >/dev/null 2>&1 ||
  emergency_shell "switch_root is unavailable; cannot leave initramfs."

resolve_root() {
  case "$ROOT_SPEC" in
    UUID=*)
      blkid -U "${ROOT_SPEC#UUID=}" 2>/dev/null || true
      ;;
    LABEL=*)
      blkid -L "${ROOT_SPEC#LABEL=}" 2>/dev/null || true
      ;;
    PARTUUID=*)
      blkid -t "PARTUUID=${ROOT_SPEC#PARTUUID=}" -o device 2>/dev/null | head -n 1 || true
      ;;
    /dev/*)
      printf '%s\n' "$ROOT_SPEC"
      ;;
    *)
      return 1
      ;;
  esac
}

ROOT_DEV=""
attempt=0
while [ "$attempt" -lt 100 ]; do
  ROOT_DEV="$(resolve_root || true)"
  if [ -n "$ROOT_DEV" ] && [ -b "$ROOT_DEV" ]; then
    break
  fi
  ROOT_DEV=""
  attempt=$((attempt + 1))
  sleep 0.1
done

[ -n "$ROOT_DEV" ] ||
  emergency_shell "installed root '$ROOT_SPEC' did not become available."

# ShreeOS currently has no later remount-rw stage in /sbin/init, so mount the
# installed filesystem read-write here. GRUB's 'ro' flag still prevents the
# kernel from making an unsafe direct mount before this initramfs handoff.
if ! mount -o rw "$ROOT_DEV" /newroot; then
  emergency_shell "failed to mount installed root '$ROOT_DEV'."
fi

if [ ! -x /newroot/sbin/init ]; then
  umount /newroot 2>/dev/null || true
  emergency_shell "installed root has no executable /sbin/init."
fi

if [ ! -f /newroot/etc/os-release ] ||
   ! grep -Eq '^ID="?shreeos"?
  umount /newroot 2>/dev/null || true
  emergency_shell "target does not look like a ShreeOS root filesystem."
fi

log "switching to installed root $ROOT_DEV ($ROOT_SPEC)"
exec switch_root /newroot /sbin/init
 /newroot/etc/os-release 2>/dev/null; then
  umount /newroot 2>/dev/null || true
  emergency_shell "target does not look like a ShreeOS root filesystem."
fi

log "switching to installed root $ROOT_DEV ($ROOT_SPEC)"
exec switch_root /newroot /sbin/init
