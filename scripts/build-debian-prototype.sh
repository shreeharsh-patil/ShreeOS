#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)"
CONFIG_SOURCE="$REPO_ROOT/prototype/debian-live"
source "$CONFIG_SOURCE/versions.conf"

if [ "$(id -u)" -ne 0 ]; then
  echo "The Debian Live prototype must be built as root; use Debian 13 or CI." >&2
  exit 2
fi
for tool in lb debootstrap xorriso unsquashfs grub-mkrescue sha256sum dpkg-query; do
  command -v "$tool" >/dev/null 2>&1 || {
    echo "Missing prototype build dependency: $tool" >&2
    exit 2
  }
done
installed_lb_version="$(dpkg-query -W -f='${Version}' live-build)"
if [ "$installed_lb_version" != "$LIVE_BUILD_VERSION" ]; then
  echo "live-build $LIVE_BUILD_VERSION is required; found $installed_lb_version" >&2
  exit 2
fi

BUILD_ROOT="$REPO_ROOT/build"
BUILD_DIR="$BUILD_ROOT/debian-live-prototype"
OUT_DIR="$REPO_ROOT/out"
case "$BUILD_DIR" in
  "$BUILD_ROOT/debian-live-prototype") ;;
  *) echo "Unsafe prototype build path: $BUILD_DIR" >&2; exit 2 ;;
esac

rm -rf -- "$BUILD_DIR"
mkdir -p "$BUILD_DIR" "$OUT_DIR"
cp -a "$CONFIG_SOURCE/config" "$BUILD_DIR/config"

mkdir -p "$BUILD_DIR/config/includes.chroot/etc/systemd/system/multi-user.target.wants"
ln -sfn ../shreeos-boot-check.service \
  "$BUILD_DIR/config/includes.chroot/etc/systemd/system/multi-user.target.wants/shreeos-boot-check.service"

SNAPSHOT="https://snapshot.debian.org/archive/debian/${DEBIAN_SNAPSHOT}/"
SECURITY_SNAPSHOT="https://snapshot.debian.org/archive/debian-security/${DEBIAN_SNAPSHOT}/"
LIVE_APPEND="boot=live components live-config.components=hostname,user-setup,locales,tzdata,keyboard-configuration live-config.hostname=shreeos live-config.username=shree live-config.user-fullname=ShreeOS-Live-User live-config.locales=en_US.UTF-8 console=tty0 console=ttyS0,115200n8"

(
  cd "$BUILD_DIR"
  lb config \
    --mode debian \
    --system live \
    --distribution "$DEBIAN_SUITE" \
    --architecture amd64 \
    --binary-image iso-hybrid \
    --bootloaders "grub-pc grub-efi" \
    --archive-areas main \
    --debian-installer none \
    --apt-recommends true \
    --apt-secure true \
    --apt-options "-o Acquire::Check-Valid-Until=false" \
    --security true \
    --firmware-binary false \
    --firmware-chroot false \
    --checksums sha256 \
    --memtest none \
    --initsystem systemd \
    --initramfs live-boot \
    --mirror-bootstrap "$SNAPSHOT" \
    --mirror-chroot "$SNAPSHOT" \
    --mirror-chroot-security "$SECURITY_SNAPSHOT" \
    --mirror-binary https://deb.debian.org/debian/ \
    --mirror-binary-security https://security.debian.org/debian-security/ \
    --iso-application "ShreeOS Base Prototype" \
    --iso-preparer "ShreeOS build pipeline" \
    --iso-publisher "ShreeOS" \
    --iso-volume "SHREEOS_PROTO" \
    --bootappend-live "$LIVE_APPEND"
  lb build
)

ISO_SOURCE="$BUILD_DIR/live-image-amd64.hybrid.iso"
PACKAGES_SOURCE="$BUILD_DIR/binary/live/filesystem.packages"
[ -s "$ISO_SOURCE" ] || { echo "live-build did not produce $ISO_SOURCE" >&2; exit 1; }
[ -s "$PACKAGES_SOURCE" ] || { echo "live-build did not produce its package manifest" >&2; exit 1; }
for package in apt live-boot live-config-systemd network-manager systemd-sysv; do
  grep -Eq "^${package}([[:space:]]|$)" "$PACKAGES_SOURCE" || {
    echo "Built image package manifest is missing required package: $package" >&2
    exit 1
  }
done

ISO_OUT="$OUT_DIR/shreeos-${PROTOTYPE_VERSION}-amd64.iso"
cp -- "$ISO_SOURCE" "$ISO_OUT"
cp -- "$PACKAGES_SOURCE" "$OUT_DIR/shreeos-${PROTOTYPE_VERSION}-packages.txt"
(cd "$OUT_DIR" && sha256sum "$(basename "$ISO_OUT")" > "$(basename "$ISO_OUT").sha256")
printf 'suite=%s\nsnapshot=%s\nlive_build=%s\n' \
  "$DEBIAN_SUITE" "$DEBIAN_SNAPSHOT" "$LIVE_BUILD_VERSION" \
  > "$OUT_DIR/shreeos-${PROTOTYPE_VERSION}-build-info.txt"
for package in live-build debootstrap xorriso squashfs-tools \
  grub-pc-bin grub-efi-amd64-bin; do
  dpkg-query -W -f='${Package}=${Version}\n' "$package" \
    >> "$OUT_DIR/shreeos-${PROTOTYPE_VERSION}-build-info.txt"
done
printf 'Built prototype ISO: %s\n' "$ISO_OUT"
