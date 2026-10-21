#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)"
CONFIG_SOURCE="$REPO_ROOT/prototype/debian-live"
# The directive (relative to the repository root, which is where the linter is
# invoked) lets it follow the file, so versions.conf's version derivation is
# actually checked instead of being skipped as unresolvable.
# shellcheck source=prototype/debian-live/versions.conf
source "$CONFIG_SOURCE/versions.conf"
LIVE_PROFILE="${SHREEOS_LIVE_PROFILE:-base}"
SHREEOS_UNIFIED="${SHREEOS_UNIFIED:-0}"
case "$SHREEOS_UNIFIED" in 0|1) ;; *) echo "SHREEOS_UNIFIED must be 0 or 1" >&2; exit 2 ;; esac
if [ "$SHREEOS_UNIFIED" = 1 ] && [ "$LIVE_PROFILE" != plasma ]; then
  echo "Unified ShreeOS requires SHREEOS_LIVE_PROFILE=plasma" >&2
  exit 2
fi

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
      developer|security|creative|office|multimedia) ;;
      *) echo "Unknown software bundle: $bundle" >&2; exit 2 ;;
    esac
  done
fi

if [ "$(id -u)" -ne 0 ]; then
  echo "The Debian Live prototype must be built as root; use Debian 13 or CI." >&2
  exit 2
fi
for tool in lb debootstrap xorriso unsquashfs grub-mkrescue sha256sum dpkg-query dpkg-deb; do
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
# The output directory is the SHREEOS_OUT knob that build.conf publishes for
# final artifacts. The canonical builder honours it, so this script has to
# honour it too or the two disagree about where the image was written.
OUT_DIR="${SHREEOS_OUT:-$REPO_ROOT/out}"
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
# etc/os-release is generated from the version source of truth, so the shipped
# image can never advertise a version that disagrees with VERSION.
os_release_template="$CONFIG_SOURCE/config/includes.chroot/etc/os-release"
[ -s "$os_release_template" ] || { echo "Missing os-release template: $os_release_template" >&2; exit 2; }
grep -Fq '@VERSION@' "$os_release_template" || { echo 'os-release template lost @VERSION@' >&2; exit 2; }
sed -e '/^# This file is a build-time template/,$d' \
  -e "s|@VERSION@|$PROTOTYPE_VERSION|g" \
  -e "s|@VERSION_ID@|${PROTOTYPE_VERSION%%-*}|g" \
  "$os_release_template" > "$BUILD_DIR/config/includes.chroot/etc/os-release"
grep -Fxq "VERSION=\"$PROTOTYPE_VERSION\"" "$BUILD_DIR/config/includes.chroot/etc/os-release" || {
  echo 'Generated os-release does not carry the ShreeOS version' >&2; exit 2;
}
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
cp "$REPO_ROOT/branding/theme/tokens.conf" \
  "$BUILD_DIR/config/includes.chroot/etc/shreeos/tokens.conf"
cp "$REPO_ROOT/branding/theme/tokens.css" \
  "$BUILD_DIR/config/includes.chroot/etc/shreeos/tokens.css"

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
  mkdir -p "$BUILD_DIR/config/packages.chroot"
  bash "$REPO_ROOT/scripts/build-shreeos-tools-package.sh" \
    "$BUILD_DIR/config/packages.chroot"
  cp -a "$PROFILE_SOURCE/includes.chroot/." \
    "$BUILD_DIR/config/includes.chroot/"
  mkdir -p "$BUILD_DIR/config/includes.chroot/etc/calamares"
  cp -a "$CONFIG_SOURCE/profiles/desktop/includes.chroot/etc/calamares/." \
    "$BUILD_DIR/config/includes.chroot/etc/calamares/"
  calamares_branding="$BUILD_DIR/config/includes.chroot/etc/calamares/branding/shreeos/branding.desc"
  [ -s "$calamares_branding" ] || {
    echo "Missing ShreeOS Calamares branding: $calamares_branding" >&2; exit 2;
  }
  grep -Fq '@VERSION@' "$calamares_branding" || {
    echo 'Calamares branding lost its version placeholder.' >&2; exit 2;
  }
  sed -i "s|@VERSION@|$PROTOTYPE_VERSION|g" "$calamares_branding"
  grep -Fq "version: $PROTOTYPE_VERSION" "$calamares_branding" || {
    echo 'Generated Calamares branding has the wrong ShreeOS version.' >&2; exit 2;
  }
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
  install -Dm0755 \
    "$CONFIG_SOURCE/profiles/desktop/includes.chroot/usr/local/libexec/shreeos-install-bios-grub" \
    "$BUILD_DIR/config/includes.chroot/usr/local/libexec/shreeos-install-bios-grub"
  install -Dm0644 \
    "$CONFIG_SOURCE/profiles/desktop/includes.chroot/usr/local/libexec/shreeos-installer-storage-checks.sh" \
    "$BUILD_DIR/config/includes.chroot/usr/local/libexec/shreeos-installer-storage-checks.sh"
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
  cp -a "$REPO_ROOT/themes/plasma/shreeos-glass-clear" \
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

if [ "$SHREEOS_UNIFIED" = 1 ]; then
  # One boot/runtime stack. Native tools are an ordinary Debian package;
  # incompatible native init, LPM executable and libraries remain separate.
  bash "$REPO_ROOT/scripts/package-unified-native.sh" "$BUILD_DIR/config/packages.chroot"
  cat > "$BUILD_DIR/config/includes.chroot/etc/os-release" <<OS_RELEASE
NAME="ShreeOS"
PRETTY_NAME="ShreeOS ${PROTOTYPE_VERSION} (Debian 13 Trixie)"
ID=shreeos
ID_LIKE=debian
VERSION="${PROTOTYPE_VERSION}"
VERSION_ID="${PROTOTYPE_VERSION%%-*}"
VERSION_CODENAME=trixie
HOME_URL="https://github.com/shreeharsh-patil/ShreeOS"
SUPPORT_URL="https://github.com/shreeharsh-patil/ShreeOS/issues"
BUG_REPORT_URL="https://github.com/shreeharsh-patil/ShreeOS/issues/new"
OS_RELEASE
  printf 'edition=unified\nnative_package=shreeos-native-tools\n' \
    > "$BUILD_DIR/config/includes.chroot/etc/shreeos/unified-image"
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
# Start the performance probe a few seconds after the graphical target is
# reached. The timer is a quick target dependency; the long-running probe is
# ordered after graphical.target but is not part of its startup transaction.
if [ "$LIVE_PROFILE" = desktop ] || [ "$LIVE_PROFILE" = plasma ]; then
  ln -sfn ../shreeos-perf-probe.timer \
    "$BUILD_DIR/config/includes.chroot/etc/systemd/system/${LIVE_TARGET}.target.wants/shreeos-perf-probe.timer"
fi

ISO_APPLICATION="ShreeOS Base Prototype"
ISO_VOLUME="SHREEOS_PROTO"
if [ "$SHREEOS_UNIFIED" = 1 ]; then
  ISO_APPLICATION="ShreeOS ${PROTOTYPE_VERSION} Unified Desktop"
  # The volume label carries the release version, so it is derived from the
  # version source of truth instead of being written down here.
  ISO_VOLUME="SHREEOS_$(printf '%s' "$PROTOTYPE_VERSION" | tr -cd '0-9')"
fi
APT_RECOMMENDS=true
if [ "$SHREEOS_UNIFIED" = 1 ]; then APT_RECOMMENDS=false; fi
SNAPSHOT="https://snapshot.debian.org/archive/debian/${DEBIAN_SNAPSHOT}/"
SECURITY_SNAPSHOT="https://snapshot.debian.org/archive/debian-security/${DEBIAN_SNAPSHOT}/"
LIVE_APPEND="boot=live components live-config.components=${LIVE_APPEND_COMPONENTS} live-config.hooks=filesystem live-config.hostname=shreeos live-config.username=shree live-config.user-default-groups=audio,cdrom,dip,floppy,video,plugdev,netdev,powerdev,scanner,bluetooth,shree-hardware live-config.user-fullname=ShreeOS-Live-User live-config.locales=en_US.UTF-8 console=tty0 console=ttyS0,115200n8"
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
    --apt-recommends "$APT_RECOMMENDS" \
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
    --iso-application "$ISO_APPLICATION" \
    --iso-preparer "ShreeOS build pipeline" \
    --iso-publisher "ShreeOS" \
    --iso-volume "$ISO_VOLUME" \
    --bootappend-live "$LIVE_APPEND"
  lb build
)

ISO_SOURCE="$BUILD_DIR/live-image-amd64.hybrid.iso"
PACKAGES_SOURCE="$BUILD_DIR/binary/live/filesystem.packages"
[ -s "$ISO_SOURCE" ] || { echo "live-build did not produce $ISO_SOURCE" >&2; exit 1; }
[ -s "$PACKAGES_SOURCE" ] || { echo "live-build did not produce its package manifest" >&2; exit 1; }
for package in apt live-boot live-config-systemd user-setup network-manager systemd-sysv; do
  grep -Eq "^${package}(:[^[:space:]]+)?([[:space:]]|$)" "$PACKAGES_SOURCE" || {
    echo "Built image package manifest is missing required package: $package" >&2
    exit 1
  }
done
if [ "$LIVE_PROFILE" = plasma ]; then
  for package in kde-plasma-desktop plasma-desktop plasma-workspace kwin-x11 sddm \
    dolphin konsole ark kde-spectacle plasma-nm plasma-pa powerdevil bluedevil \
    xserver-xorg libgl1-mesa-dri mesa-vulkan-drivers kio-extras systemsettings \
    xdg-desktop-portal xdg-desktop-portal-gtk xdg-desktop-portal-kde \
    desktop-file-utils shared-mime-info hicolor-icon-theme gtk-update-icon-cache \
    cups-pk-helper system-config-printer-common system-config-printer-udev \
    smbclient avahi-daemon colord sane-airscan sane-utils ipp-usb onboard-data \
    sound-icons xbrlapi btrfs-progs squashfs-tools shreeos-tools shreeos-native-tools; do
    grep -Eq "^${package}(:[^[:space:]]+)?([[:space:]]|$)" "$PACKAGES_SOURCE" || {
      echo "Plasma package manifest is missing required package: $package" >&2
      exit 1
    }
  done
  for package in fonts-noto fonts-noto-extra fonts-noto-cjk fonts-noto-cjk-extra \
    fonts-noto-ui-extra ibus-data; do
    if grep -Eq "^${package}(:[^[:space:]]+)?([[:space:]]|$)" "$PACKAGES_SOURCE"; then
      echo "Optimized Plasma image unexpectedly includes omitted recommendation package: $package" >&2
      exit 1
    fi
  done
fi

if [ "$SHREEOS_UNIFIED" = 1 ]; then
  iso_size_bytes="$(stat -c '%s' "$ISO_SOURCE")"
  if (( iso_size_bytes >= 1900000000 )); then
    printf 'Unified ISO is %s bytes; the release cap is strictly below 1900000000 bytes.\n' \
      "$iso_size_bytes" >&2
    exit 1
  fi
fi

# Output naming.
#
# The canonical unified build (scripts/build-shreeos.sh) passes
# SHREEOS_OUTPUT_BASENAME and owns the mandated "shreeos(VERSION).iso" name.
# A direct build of an experimental profile keeps a suffixed name, so an
# experiment can never be mistaken for, or published as, the unified release.
OUTPUT_SUFFIX=""
ISO_SUFFIX="-amd64"
BUILD_KIND="experimental"
if [ "$LIVE_PROFILE" = desktop ]; then OUTPUT_SUFFIX="-desktop"; fi
if [ "$LIVE_PROFILE" = plasma ]; then OUTPUT_SUFFIX="-plasma"; fi
if [ "$SHREEOS_UNIFIED" = 1 ]; then
  grep -Eq "^shreeos-native-tools[[:space:]]" "$PACKAGES_SOURCE" || {
    echo "Unified ISO is missing native tools Debian package" >&2; exit 1;
  }
fi
if [ -n "${SHREEOS_OUTPUT_BASENAME:-}" ]; then
  # Parentheses are part of the mandated filename; validate tightly so the value
  # cannot escape the output directory or carry a forbidden release suffix.
  if ! [[ "$SHREEOS_OUTPUT_BASENAME" =~ ^shreeos\([0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?\)$ ]]; then
    echo "Unsafe SHREEOS_OUTPUT_BASENAME: $SHREEOS_OUTPUT_BASENAME" >&2
    exit 2
  fi
  OUTPUT_PREFIX="$OUT_DIR/$SHREEOS_OUTPUT_BASENAME"
  ISO_SUFFIX=""
  BUILD_KIND="unified"
else
  OUTPUT_PREFIX="$OUT_DIR/shreeos-${PROTOTYPE_VERSION}${OUTPUT_SUFFIX}"
fi
ISO_OUT="${OUTPUT_PREFIX}${ISO_SUFFIX}.iso"
cp -- "$ISO_SOURCE" "$ISO_OUT"
cp -- "$PACKAGES_SOURCE" "${OUTPUT_PREFIX}-packages.txt"
(cd "$OUT_DIR" && sha256sum "$(basename "$ISO_OUT")" > "$(basename "$ISO_OUT").sha256")
manifest_version() {
  awk -v pkg="$1" '$1 == pkg { print $2; exit }' "$PACKAGES_SOURCE"
}
printf 'version=%s\nkind=%s\nsuite=%s\nsnapshot=%s\nlive_build=%s\nprofile=%s\napt_recommends=%s\nfirmware=%s\ntoolsets=%s\narchitecture=x86_64\n' \
  "$PROTOTYPE_VERSION" "$BUILD_KIND" "$DEBIAN_SUITE" "$DEBIAN_SNAPSHOT" "$LIVE_BUILD_VERSION" \
  "$LIVE_PROFILE" "$APT_RECOMMENDS" "$FIRMWARE" "$TOOLSETS" \
  > "${OUTPUT_PREFIX}-build-info.txt"
printf 'kernel=%s\nplasma=%s\nkwin=%s\nsddm=%s\n' \
  "$(manifest_version linux-image-amd64)" "$(manifest_version plasma-workspace)" \
  "$(manifest_version kwin-x11)" "$(manifest_version sddm)" \
  >> "${OUTPUT_PREFIX}-build-info.txt"
for package in live-build debootstrap xorriso squashfs-tools \
  grub-pc-bin grub-efi-amd64-bin; do
  dpkg-query -W -f='${Package}=${Version}\n' "$package" \
    >> "${OUTPUT_PREFIX}-build-info.txt"
done
if [ "$SHREEOS_UNIFIED" = 1 ]; then
  printf 'edition=unified\nnative_package=shreeos-native-tools\n' >> "${OUTPUT_PREFIX}-build-info.txt"
  iso_sha256="$(sha256sum "$ISO_OUT" | awk '{print $1}')"
  iso_size_bytes="$(stat -c '%s' "$ISO_OUT")"
  if git -C "$REPO_ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    source_commit="$(git -C "$REPO_ROOT" rev-parse HEAD)"
    git_dirty=0
    if [ -n "$(git -C "$REPO_ROOT" status --porcelain --untracked-files=all)" ]; then
      git_dirty=1
    fi
  else
    source_commit="${GITHUB_SHA:-}"
    if ! [[ "$source_commit" =~ ^[0-9a-f]{40}$ ]]; then
      echo 'Unified build requires Git metadata or a full GITHUB_SHA for provenance.' >&2
      exit 1
    fi
    git_dirty=0
  fi
  printf 'artifact=%s\ndebian_suite=%s\ndebian_snapshot=%s\ngit_commit=%s\ngit_dirty=%s\nbuilt_at=%s\nsha256=%s\nsize_bytes=%s\nshreeos_tools=%s\nshreeos_native_tools=%s\n' \
    "$(basename "$ISO_OUT")" "$DEBIAN_SUITE" "$DEBIAN_SNAPSHOT" \
    "$source_commit" "$git_dirty" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    "$iso_sha256" "$iso_size_bytes" \
    "$(manifest_version shreeos-tools)" "$(manifest_version shreeos-native-tools)" \
    >> "${OUTPUT_PREFIX}-build-info.txt"
  ISO_NAME="$(basename "$ISO_OUT")" ISO_PATH="$ISO_OUT" ISO_SHA256="$iso_sha256" \
    ISO_SIZE="$iso_size_bytes" SOURCE_COMMIT="$source_commit" GIT_DIRTY="$git_dirty" \
    IMAGE_VERSION="$PROTOTYPE_VERSION" IMAGE_PROFILE="$LIVE_PROFILE" \
    DEBIAN_SUITE="$DEBIAN_SUITE" DEBIAN_SNAPSHOT="$DEBIAN_SNAPSHOT" \
    LIVE_BUILD_VERSION="$LIVE_BUILD_VERSION" PACKAGE_MANIFEST="$PACKAGES_SOURCE" \
    python3 - "${OUTPUT_PREFIX}-manifest.json" <<'PY'
import hashlib
import json
import os
import sys
from pathlib import Path

iso = Path(os.environ["ISO_PATH"])
with iso.open("rb") as stream:
    digest = hashlib.file_digest(stream, "sha256").hexdigest()
size_bytes = iso.stat().st_size
if digest != os.environ["ISO_SHA256"]:
    raise SystemExit("unified ISO digest changed while writing provenance")
if size_bytes != int(os.environ["ISO_SIZE"]):
    raise SystemExit("unified ISO size changed while writing provenance")

packages = {}
for raw_line in Path(os.environ["PACKAGE_MANIFEST"]).read_text(encoding="utf-8").splitlines():
    fields = raw_line.split()
    if len(fields) >= 2:
        packages[fields[0]] = fields[1]
components = {
    "kernel": packages.get("linux-image-amd64", ""),
    "plasma": packages.get("plasma-workspace", ""),
    "kwin": packages.get("kwin-x11", ""),
    "sddm": packages.get("sddm", ""),
    "shreeos_tools": packages.get("shreeos-tools", ""),
    "shreeos_native_tools": packages.get("shreeos-native-tools", ""),
}
if any(not value for value in components.values()):
    raise SystemExit("unified package manifest is missing a required component")

manifest = {
    "name": "ShreeOS",
    "version": os.environ["IMAGE_VERSION"],
    "profile": os.environ["IMAGE_PROFILE"],
    "architecture": "x86_64",
    "base_distribution": os.environ["DEBIAN_SUITE"],
    "base_snapshot": os.environ["DEBIAN_SNAPSHOT"],
    "live_build": os.environ["LIVE_BUILD_VERSION"],
    "commit": os.environ["SOURCE_COMMIT"],
    "git_dirty": os.environ["GIT_DIRTY"] == "1",
    "products": ["live", "installed"],
    "iso": os.environ["ISO_NAME"],
    "sha256": digest,
    "size_bytes": size_bytes,
    "components": components,
}
Path(sys.argv[1]).write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n",
                             encoding="utf-8")
PY
  python3 "$REPO_ROOT/scripts/verify-unified-artifact.py" \
    "$ISO_OUT" "${ISO_OUT}.sha256" "${OUTPUT_PREFIX}-packages.txt" \
    "${OUTPUT_PREFIX}-build-info.txt" "${OUTPUT_PREFIX}-manifest.json" \
    "$PROTOTYPE_VERSION" "$LIVE_PROFILE" x86_64 "$DEBIAN_SUITE" \
    "$DEBIAN_SNAPSHOT" "$LIVE_BUILD_VERSION"
fi
printf 'Built %s %s ISO: %s\n' "$LIVE_PROFILE" "$BUILD_KIND" "$ISO_OUT"
