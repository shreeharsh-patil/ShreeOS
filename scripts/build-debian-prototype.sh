#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)"
CONFIG_SOURCE="$REPO_ROOT/prototype/debian-live"
source "$CONFIG_SOURCE/versions.conf"
LIVE_PROFILE="${SHREEOS_LIVE_PROFILE:-base}"

case "$LIVE_PROFILE" in
  base|desktop|plasma) ;;
  *) echo "Unsupported live profile '$LIVE_PROFILE' (expected base, desktop, or plasma)." >&2; exit 2 ;;
esac

# Select firmware deliberately. Graphical images target ordinary PCs; the
# console base retains its main-only default. A free-only image remains an
# explicit choice. All dependencies use the same pinned Debian snapshot.
if [ "$LIVE_PROFILE" = base ]; then DEFAULT_FIRMWARE=free; else DEFAULT_FIRMWARE=standard; fi
FIRMWARE="${SHREEOS_FIRMWARE:-$DEFAULT_FIRMWARE}"
ARCHIVE_AREAS=main
case "$FIRMWARE" in
  free) ;;
  standard) ARCHIVE_AREAS='main non-free-firmware' ;;
  *) echo 'SHREEOS_FIRMWARE must be free or standard.' >&2; exit 2 ;;
esac
TOOLSETS="${SHREEOS_TOOLSETS:-}"
selected_toolsets=()
if [ -n "$TOOLSETS" ]; then
  case "$TOOLSETS" in ,*|*,|*,,*) echo 'SHREEOS_TOOLSETS contains an empty bundle.' >&2; exit 2 ;; esac
  IFS=, read -r -a selected_toolsets <<< "$TOOLSETS"
  for bundle in "${selected_toolsets[@]}"; do
    case "$bundle" in
      developer|security|creative) ;;
      *) echo "Unknown software bundle: $bundle" >&2; exit 2 ;;
    esac
  done
fi

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
if [ "$LIVE_PROFILE" = desktop ] || [ "$LIVE_PROFILE" = plasma ]; then
  command -v rsvg-convert >/dev/null 2>&1 || {
    echo "Missing desktop image asset tool: rsvg-convert (install librsvg2-bin)." >&2
    exit 2
  }
fi
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

# Reject links before deleting the disposable build tree. Lexical path checks
# alone cannot protect a build/ symlink that resolves outside this checkout.
if [ -L "$BUILD_ROOT" ] || [ -L "$BUILD_DIR" ]; then
  echo 'Refusing to clean a symlinked prototype build directory.' >&2
  exit 2
fi
mkdir -p "$BUILD_ROOT"
[ "$(realpath "$BUILD_ROOT")" = "$REPO_ROOT/build" ] || {
  echo 'Prototype build directory resolves outside the checkout.' >&2; exit 2;
}
rm -rf -- "$BUILD_DIR"
mkdir -p "$BUILD_DIR" "$OUT_DIR"
cp -a "$CONFIG_SOURCE/config" "$BUILD_DIR/config"
cp -a "$CONFIG_SOURCE/features/includes.chroot/." "$BUILD_DIR/config/includes.chroot/"
mkdir -p "$BUILD_DIR/config/includes.chroot/usr/share/shreeos/toolsets"
cp "$CONFIG_SOURCE/features/toolsets/"*.list.chroot \
  "$BUILD_DIR/config/includes.chroot/usr/share/shreeos/toolsets/"
chmod 0755 "$BUILD_DIR/config/includes.chroot/usr/local/bin/shreeos-software"
if [ "$FIRMWARE" = standard ]; then
  cp "$CONFIG_SOURCE/features/package-lists/shreeos-hardware.list.chroot" \
    "$BUILD_DIR/config/package-lists/"
fi
for bundle in "${selected_toolsets[@]}"; do
  cp "$CONFIG_SOURCE/features/toolsets/$bundle.list.chroot" \
    "$BUILD_DIR/config/package-lists/shreeos-$bundle.list.chroot"
done
mkdir -p "$BUILD_DIR/config/includes.chroot/etc/shreeos"
printf '%s\n' "$FIRMWARE" > "$BUILD_DIR/config/includes.chroot/etc/shreeos/firmware-policy"

if [ "$LIVE_PROFILE" = desktop ]; then
  PROFILE_SOURCE="$CONFIG_SOURCE/profiles/desktop"
  cp "$PROFILE_SOURCE/package-lists/shreeos-desktop.list.chroot" \
    "$BUILD_DIR/config/package-lists/"
  cp -a "$PROFILE_SOURCE/includes.chroot/." \
    "$BUILD_DIR/config/includes.chroot/"
  XFCE_DEFAULTS_SOURCE="$BUILD_DIR/config/includes.chroot/etc/skel/.config/xfce4/xfconf/xfce-perchannel-xml"
  XFCE_DEFAULTS_TARGET="$BUILD_DIR/config/includes.chroot/etc/xdg/xfce4/xfconf/xfce-perchannel-xml"
  mkdir -p "$XFCE_DEFAULTS_TARGET"
  cp "$XFCE_DEFAULTS_SOURCE"/*.xml "$XFCE_DEFAULTS_TARGET/"
  mkdir -p \
    "$BUILD_DIR/config/includes.chroot/usr/share/backgrounds/shreeos" \
    "$BUILD_DIR/config/includes.chroot/usr/share/pixmaps" \
    "$BUILD_DIR/config/includes.chroot/usr/share/shreeos/branding" \
    "$BUILD_DIR/config/includes.chroot/usr/share/icons/hicolor/scalable/apps" \
    "$BUILD_DIR/config/includes.chroot/etc/calamares/branding/shreeos"
  cp "$REPO_ROOT"/branding/logo/*.svg \
    "$BUILD_DIR/config/includes.chroot/usr/share/shreeos/branding/"
  cp "$REPO_ROOT"/branding/wallpapers/*.svg \
    "$BUILD_DIR/config/includes.chroot/usr/share/backgrounds/shreeos/"
  cp "$REPO_ROOT/branding/logo/shreeos-logo.svg" \
    "$BUILD_DIR/config/includes.chroot/usr/share/pixmaps/"
  cp "$REPO_ROOT/branding/icons/shreeos-app.svg" \
    "$BUILD_DIR/config/includes.chroot/usr/share/icons/hicolor/scalable/apps/shreeos.svg"
  cp "$REPO_ROOT/branding/icons/shreeos-app.svg" \
    "$BUILD_DIR/config/includes.chroot/etc/calamares/branding/shreeos/shreeos-app.svg"
  cp "$PROFILE_SOURCE/includes.chroot/usr/share/icons/hicolor/scalable/apps/shreeos-control-center.svg" \
    "$BUILD_DIR/config/includes.chroot/usr/share/icons/hicolor/scalable/apps/"
  cp "$REPO_ROOT/branding/icons/installer.svg" \
    "$BUILD_DIR/config/includes.chroot/usr/share/icons/hicolor/scalable/apps/shreeos-installer.svg"
  cp "$REPO_ROOT/branding/logo/shreeos-logo.svg" \
    "$BUILD_DIR/config/includes.chroot/etc/calamares/branding/shreeos/"
  for wallpaper in "$REPO_ROOT"/branding/wallpapers/*.svg; do
    rsvg-convert --width=1920 \
      --output="$BUILD_DIR/config/includes.chroot/usr/share/backgrounds/shreeos/$(basename "${wallpaper%.svg}").png" \
      "$wallpaper"
  done
  # Debian's xfdesktop package may compile a desktop-base fallback path even
  # when desktop-base is not installed. Provide ShreeOS artwork at that path
  # so xfdesktop never starts with a missing-image backdrop.
  mkdir -p "$BUILD_DIR/config/includes.chroot/usr/share/images/desktop-base"
  cp "$BUILD_DIR/config/includes.chroot/usr/share/backgrounds/shreeos/shreeos-calm-light.png" \
    "$BUILD_DIR/config/includes.chroot/usr/share/images/desktop-base/default"
  rsvg-convert --width=256 \
    --output="$BUILD_DIR/config/includes.chroot/usr/share/plymouth/themes/shreeos/logo.png" \
    "$REPO_ROOT/branding/logo/shreeos-logo.svg"
  rsvg-convert \
    --output="$BUILD_DIR/config/includes.chroot/usr/share/plymouth/themes/shreeos/dot.png" \
    "$PROFILE_SOURCE/includes.chroot/usr/share/plymouth/themes/shreeos/dot.svg"
  mkdir -p "$BUILD_DIR/config/hooks/live"
  cp "$PROFILE_SOURCE/hooks/9000-shreeos-plymouth.hook.chroot" \
    "$BUILD_DIR/config/hooks/live/"
  chmod 0755 "$BUILD_DIR/config/hooks/live/9000-shreeos-plymouth.hook.chroot"
fi

if [ "$LIVE_PROFILE" = plasma ]; then
  PROFILE_SOURCE="$CONFIG_SOURCE/profiles/plasma"
  cp "$PROFILE_SOURCE/package-lists/shreeos-plasma.list.chroot" \
    "$BUILD_DIR/config/package-lists/"
  cp -a "$PROFILE_SOURCE/includes.chroot/." \
    "$BUILD_DIR/config/includes.chroot/"
  mkdir -p "$BUILD_DIR/config/includes.chroot/etc/calamares"
  cp -a "$CONFIG_SOURCE/profiles/desktop/includes.chroot/etc/calamares/." \
    "$BUILD_DIR/config/includes.chroot/etc/calamares/"
  mkdir -p \
    "$BUILD_DIR/config/includes.chroot/usr/local/bin" \
    "$BUILD_DIR/config/includes.chroot/usr/local/libexec" \
    "$BUILD_DIR/config/includes.chroot/usr/share/applications" \
    "$BUILD_DIR/config/includes.chroot/usr/share/shreeos/branding" \
    "$BUILD_DIR/config/includes.chroot/usr/share/icons/hicolor/scalable/apps" \
    "$BUILD_DIR/config/includes.chroot/usr/share/polkit-1/actions" \
    "$BUILD_DIR/config/includes.chroot/etc/calamares/branding/shreeos"
  cp "$CONFIG_SOURCE/profiles/desktop/includes.chroot/usr/local/bin/shreeos-installer" \
    "$BUILD_DIR/config/includes.chroot/usr/local/bin/"
  cp "$CONFIG_SOURCE/profiles/desktop/includes.chroot/usr/local/libexec/shreeos-installer-privileged" \
    "$BUILD_DIR/config/includes.chroot/usr/local/libexec/"
  cp "$CONFIG_SOURCE/profiles/desktop/includes.chroot/usr/share/applications/shreeos-installer.desktop" \
    "$BUILD_DIR/config/includes.chroot/usr/share/applications/"
  cp "$REPO_ROOT/branding/icons/installer.svg" \
    "$BUILD_DIR/config/includes.chroot/usr/share/icons/hicolor/scalable/apps/shreeos-installer.svg"
  cp "$CONFIG_SOURCE/profiles/desktop/includes.chroot/usr/share/polkit-1/actions/org.shreeos.installer.policy" \
    "$BUILD_DIR/config/includes.chroot/usr/share/polkit-1/actions/"
  cp "$REPO_ROOT"/branding/logo/*.svg \
    "$BUILD_DIR/config/includes.chroot/usr/share/shreeos/branding/"
  cp "$REPO_ROOT/branding/logo/shreeos-logo.svg" \
    "$BUILD_DIR/config/includes.chroot/etc/calamares/branding/shreeos/"
  cp "$REPO_ROOT/branding/icons/shreeos-app.svg" \
    "$BUILD_DIR/config/includes.chroot/etc/calamares/branding/shreeos/shreeos-app.svg"
  mkdir -p \
    "$BUILD_DIR/config/includes.chroot/usr/share/backgrounds/shreeos" \
    "$BUILD_DIR/config/includes.chroot/usr/share/pixmaps"
  cp "$REPO_ROOT"/branding/wallpapers/*.svg \
    "$BUILD_DIR/config/includes.chroot/usr/share/backgrounds/shreeos/"
  cp "$REPO_ROOT/branding/logo/shreeos-logo.svg" \
    "$BUILD_DIR/config/includes.chroot/usr/share/pixmaps/"
  mkdir -p "$BUILD_DIR/config/includes.chroot/usr/share/icons/hicolor/scalable/apps"
  cp "$REPO_ROOT/branding/icons/shreeos-app.svg" \
    "$BUILD_DIR/config/includes.chroot/usr/share/icons/hicolor/scalable/apps/shreeos.svg"
  rsvg-convert --width=256 --height=256 \
    --output="$BUILD_DIR/config/includes.chroot/usr/share/pixmaps/shreeos-logo.png" \
    "$REPO_ROOT/branding/logo/shreeos-logo.svg"
  mkdir -p "$BUILD_DIR/config/includes.chroot/usr/share/plasma/look-and-feel/org.shreeos.desktop/contents/layouts"
  mkdir -p "$BUILD_DIR/config/includes.chroot/usr/share/color-schemes"
  cp "$REPO_ROOT/themes/plasma/colors/ShreeOS-Dark.colors" \
    "$BUILD_DIR/config/includes.chroot/usr/share/color-schemes/ShreeOS Dark.colors"
  cp "$REPO_ROOT/themes/plasma/colors/ShreeOS-Light.colors" \
    "$BUILD_DIR/config/includes.chroot/usr/share/color-schemes/ShreeOS Light.colors"
  cp "$REPO_ROOT/desktop/plasma/layout.js" \
    "$BUILD_DIR/config/includes.chroot/usr/share/plasma/look-and-feel/org.shreeos.desktop/contents/layouts/org.kde.plasma.desktop-layout.js"
  mkdir -p "$BUILD_DIR/config/includes.chroot/usr/share/plasma/desktoptheme"
  cp -a "$REPO_ROOT/themes/plasma/shreeos-glass" \
    "$BUILD_DIR/config/includes.chroot/usr/share/plasma/desktoptheme/"
  cp "$REPO_ROOT/branding/wallpapers/shreeos-alpenglow.png" \
    "$BUILD_DIR/config/includes.chroot/usr/share/backgrounds/shreeos/"
  chmod 0755 \
    "$BUILD_DIR/config/includes.chroot/usr/local/bin/shreeos-plasma-first-login" \
    "$BUILD_DIR/config/includes.chroot/usr/local/bin/shreeos-plasma-dock" \
    "$BUILD_DIR/config/includes.chroot/usr/local/bin/shreeos-motion" \
    "$BUILD_DIR/config/includes.chroot/usr/local/bin/shreeos-open-downloads" \
    "$BUILD_DIR/config/includes.chroot/usr/local/bin/shreeos-open-trash" \
    "$BUILD_DIR/config/includes.chroot/usr/local/bin/shreeos-theme" \
    "$BUILD_DIR/config/includes.chroot/usr/local/sbin/shreeos-sddm-live-autologin"
  chmod 0755 \
    "$BUILD_DIR/config/includes.chroot/usr/local/bin/shreeos-installer" \
    "$BUILD_DIR/config/includes.chroot/usr/local/libexec/shreeos-installer-privileged"
  for wallpaper in "$REPO_ROOT"/branding/wallpapers/*.svg; do
    rsvg-convert --width=1920 \
      --output="$BUILD_DIR/config/includes.chroot/usr/share/backgrounds/shreeos/$(basename "${wallpaper%.svg}").png" \
      "$wallpaper"
  done
  mkdir -p "$BUILD_DIR/config/includes.chroot/usr/share/plymouth/themes/shreeos"
  cp "$CONFIG_SOURCE/profiles/desktop/includes.chroot/usr/share/plymouth/themes/shreeos/"{shreeos.plymouth,shreeos.script,dot.svg} \
    "$BUILD_DIR/config/includes.chroot/usr/share/plymouth/themes/shreeos/"
  rsvg-convert --width=256 \
    --output="$BUILD_DIR/config/includes.chroot/usr/share/plymouth/themes/shreeos/logo.png" \
    "$REPO_ROOT/branding/logo/shreeos-logo.svg"
  rsvg-convert \
    --output="$BUILD_DIR/config/includes.chroot/usr/share/plymouth/themes/shreeos/dot.png" \
    "$CONFIG_SOURCE/profiles/desktop/includes.chroot/usr/share/plymouth/themes/shreeos/dot.svg"
  mkdir -p "$BUILD_DIR/config/hooks/live"
  cp "$CONFIG_SOURCE/profiles/desktop/hooks/9000-shreeos-plymouth.hook.chroot" \
    "$BUILD_DIR/config/hooks/live/"
  chmod 0755 "$BUILD_DIR/config/hooks/live/9000-shreeos-plymouth.hook.chroot"
  cp "$PROFILE_SOURCE/hooks/9001-shreeos-sddm.hook.chroot" \
    "$BUILD_DIR/config/hooks/live/"
  chmod 0755 "$BUILD_DIR/config/hooks/live/9001-shreeos-sddm.hook.chroot"
fi

if [ "$LIVE_PROFILE" = desktop ]; then
  LIVE_TARGET=graphical
  LIVE_APPEND_COMPONENTS=hostname,user-setup,locales,tzdata,keyboard-configuration,lightdm,hooks
elif [ "$LIVE_PROFILE" = plasma ]; then
  LIVE_TARGET=graphical
  LIVE_APPEND_COMPONENTS=hostname,user-setup,locales,tzdata,keyboard-configuration,hooks
else
  LIVE_TARGET=multi-user
  LIVE_APPEND_COMPONENTS=hostname,user-setup,locales,tzdata,keyboard-configuration,hooks
fi

mkdir -p "$BUILD_DIR/config/includes.chroot/etc/systemd/system/${LIVE_TARGET}.target.wants"
ln -sfn ../shreeos-boot-check.service \
  "$BUILD_DIR/config/includes.chroot/etc/systemd/system/${LIVE_TARGET}.target.wants/shreeos-boot-check.service"

SNAPSHOT="https://snapshot.debian.org/archive/debian/${DEBIAN_SNAPSHOT}/"
SECURITY_SNAPSHOT="https://snapshot.debian.org/archive/debian-security/${DEBIAN_SNAPSHOT}/"
LIVE_APPEND="boot=live components live-config.components=${LIVE_APPEND_COMPONENTS} live-config.hooks=filesystem live-config.hostname=shreeos live-config.username=shree live-config.user-fullname=ShreeOS-Live-User live-config.locales=en_US.UTF-8 console=tty0 console=ttyS0,115200n8"
if [ "$LIVE_PROFILE" = desktop ] || [ "$LIVE_PROFILE" = plasma ]; then LIVE_APPEND="$LIVE_APPEND quiet splash"; fi

(
  cd "$BUILD_DIR"
  lb config \
    --mode debian \
    --system live \
    --distribution "$DEBIAN_SUITE" \
    --architecture amd64 \
    --binary-image iso-hybrid \
    --bootloaders "grub-pc grub-efi" \
    --archive-areas "$ARCHIVE_AREAS" \
    --debian-installer none \
    --apt-recommends true \
    --apt-secure true \
    --apt-options "--yes -o Acquire::Retries=5 -o Acquire::Check-Valid-Until=false" \
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
  grep -Eq "^${package}(:[^[:space:]]+)?([[:space:]]|$)" "$PACKAGES_SOURCE" || {
    echo "Built image package manifest is missing required package: $package" >&2
    exit 1
  }
done
if [ "$LIVE_PROFILE" = plasma ]; then
  for package in kde-plasma-desktop plasma-desktop plasma-workspace kwin-x11 sddm \
    dolphin konsole ark kde-spectacle plasma-nm plasma-pa powerdevil bluedevil; do
    grep -Eq "^${package}(:[^[:space:]]+)?([[:space:]]|$)" "$PACKAGES_SOURCE" || {
      echo "Plasma package manifest is missing required package: $package" >&2
      exit 1
    }
  done
fi

OUTPUT_SUFFIX=""
if [ "$LIVE_PROFILE" = desktop ]; then OUTPUT_SUFFIX="-desktop"; fi
if [ "$LIVE_PROFILE" = plasma ]; then OUTPUT_SUFFIX="-plasma"; fi
OUTPUT_PREFIX="$OUT_DIR/shreeos-${PROTOTYPE_VERSION}${OUTPUT_SUFFIX}"
ISO_OUT="${OUTPUT_PREFIX}-amd64.iso"
cp -- "$ISO_SOURCE" "$ISO_OUT"
cp -- "$PACKAGES_SOURCE" "${OUTPUT_PREFIX}-packages.txt"
(cd "$OUT_DIR" && sha256sum "$(basename "$ISO_OUT")" > "$(basename "$ISO_OUT").sha256")
printf 'suite=%s\nsnapshot=%s\nlive_build=%s\nprofile=%s\nfirmware=%s\ntoolsets=%s\n' \
  "$DEBIAN_SUITE" "$DEBIAN_SNAPSHOT" "$LIVE_BUILD_VERSION" "$LIVE_PROFILE" "$FIRMWARE" "$TOOLSETS" \
  > "${OUTPUT_PREFIX}-build-info.txt"
for package in live-build debootstrap xorriso squashfs-tools \
  grub-pc-bin grub-efi-amd64-bin; do
  dpkg-query -W -f='${Package}=${Version}\n' "$package" \
    >> "${OUTPUT_PREFIX}-build-info.txt"
done
printf 'Built %s prototype ISO: %s\n' "$LIVE_PROFILE" "$ISO_OUT"
