#!/usr/bin/env bash
# Verify build-stage postconditions so stale marker files cannot mask missing outputs.
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$ROOT_DIR/build.conf"
source "$ROOT_DIR/scripts/common.sh"

stage="${1:-}"
profile="${PROFILE:-desktop}"

require_file() {
  local path="$1" desc="$2"
  [ -s "$path" ] || shreeos_die "$stage cache is invalid: missing/empty $desc ($path)"
}

require_exec() {
  local path="$1" desc="$2"
  [ -x "$path" ] || shreeos_die "$stage cache is invalid: missing/non-executable $desc ($path)"
}

require_dir() {
  local path="$1" desc="$2"
  [ -d "$path" ] || shreeos_die "$stage cache is invalid: missing $desc ($path)"
}

require_glob() {
  local pattern="$1" desc="$2"
  compgen -G "$pattern" >/dev/null ||
    shreeos_die "$stage cache is invalid: missing $desc ($pattern)"
}

case "$stage" in
  toolchain)
    require_exec "$SHREEOS_TOOLS/bin/$SHREEOS_TARGET_TRIPLET-gcc" "cross compiler"
    require_file "$SHREEOS_SYSROOT/usr/include/stdio.h" "target libc headers"
    ;;
  base-system)
    require_exec "$SHREEOS_STAGE_ROOT/usr/bin/bash" "/usr/bin/bash"
    require_exec "$SHREEOS_STAGE_ROOT/bin/bash" "/bin/bash compatibility link"
    require_exec "$SHREEOS_STAGE_ROOT/usr/bin/ls" "/usr/bin/ls"
    require_exec "$SHREEOS_STAGE_ROOT/usr/bin/mount" "/usr/bin/mount"
    require_exec "$SHREEOS_STAGE_ROOT/usr/sbin/wpa_supplicant" "wpa_supplicant"
    require_glob "$SHREEOS_STAGE_ROOT/usr/lib/libcrypto.so*" "target libcrypto"
    require_glob "$SHREEOS_STAGE_ROOT/usr/lib/libssl.so*" "target libssl"
    require_glob "$SHREEOS_STAGE_ROOT/usr/lib/libnl-3.so*" "target libnl"
    require_glob "$SHREEOS_STAGE_ROOT/usr/lib/libnl-genl-3.so*" "target libnl-genl"
    require_glob "$SHREEOS_STAGE_ROOT/usr/lib/libpanel.so*" "ncurses panel compatibility library"
    require_exec "$SHREEOS_STAGE_ROOT/usr/bin/amixer" "ALSA mixer utility"
    ;;
  kernel)
    require_file "$SHREEOS_BUILD_DIR/build-kernel/arch/x86/boot/bzImage" "kernel bzImage"
    require_dir "$SHREEOS_STAGE_ROOT/lib/modules" "installed kernel modules"
    ;;
  packages)
    require_exec "$ROOT_DIR/pkgmanager/src/lpm" "lpm"
    require_exec "$ROOT_DIR/init/src/init" "PID 1 init"
    require_exec "$ROOT_DIR/hardware/shreed" "hardware daemon"
    ;;
  desktop)
    if [ "$profile" = "desktop" ]; then
      status="$SHREEOS_STAGE_ROOT/etc/shreeos/desktop-native.status"
      require_file "$status" "desktop status"
      state="$(tr -d '\r\n' < "$status")"
      case "$state" in
        ready)
          bash "$ROOT_DIR/scripts/graphics-readiness.sh" --strict
          ;;
        deferred)
          if [ "${ALLOW_DEFERRED_GRAPHICS:-0}" != "1" ]; then
            shreeos_die "desktop cache is deferred; set ALLOW_DEFERRED_GRAPHICS=1 only for explicit development boot testing"
          fi
          ;;
        *) shreeos_die "desktop cache has invalid state: $state" ;;
      esac
    fi
    ;;
  rootfs)
    require_exec "$SHREEOS_STAGE_ROOT/sbin/init" "rootfs PID 1"
    require_file "$SHREEOS_BUILD_DIR/initramfs.cpio.gz" "rootfs initramfs"
    ;;
  iso)
    iso="$SHREEOS_OUT/$DISTRO_ID-$DISTRO_VERSION.iso"
    require_file "$iso" "ISO image"
    require_file "$iso.sha256" "ISO checksum"
    ;;
  *)
    shreeos_die "Usage: verify-stage.sh <toolchain|base-system|kernel|packages|desktop|rootfs|iso>"
    ;;
esac

shreeos_ok "Stage postconditions verified: $stage"
