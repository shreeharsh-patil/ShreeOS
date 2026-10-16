#!/usr/bin/env bash
# SquashFS and package-manifest verification for a built ShreeOS image.
#
# This is the structural half of image verification: it proves the image really
# contains the required packages, the ShreeOS-owned desktop payload and a
# coherent firmware policy, without booting anything. tests/prototype/test-iso.sh
# covers the boot half.
#
# Usage: tests/prototype/test-iso-squashfs.sh PATH_TO_ISO
set -Eeuo pipefail

if [ "$#" -ne 1 ] || [ ! -s "$1" ]; then
  echo "Usage: $0 PATH_TO_SHREEOS_ISO" >&2
  exit 2
fi

ISO="$(realpath "$1")"
for tool in xorriso unsquashfs sha256sum; do
  command -v "$tool" >/dev/null 2>&1 || {
    echo "Missing ISO verification dependency: $tool" >&2
    exit 2
  }
done

TEST_DIR="$(mktemp -d)"
trap 'rm -rf -- "$TEST_DIR"' EXIT

SQUASHFS="$TEST_DIR/filesystem.squashfs"
xorriso -osirrox on -indev "$ISO" -extract /live/filesystem.squashfs "$SQUASHFS" >/dev/null
unsquashfs -s "$SQUASHFS" >/dev/null
if ! unsquashfs -no-progress -d "$TEST_DIR/extracted" "$SQUASHFS" >/dev/null; then
  echo 'Full SquashFS extraction/integrity check failed' >&2
  exit 1
fi
xorriso -osirrox on -indev "$ISO" -extract /live/filesystem.packages "$TEST_DIR/packages.txt" >/dev/null
[ -s "$TEST_DIR/packages.txt" ] || { echo 'ISO has no live package manifest' >&2; exit 1; }

have_package() {
  grep -Eq "^$1(:[^[:space:]]+)?([[:space:]]|$)" "$TEST_DIR/packages.txt"
}

# --- Base system: never removable -------------------------------------------
for package in apt dpkg systemd systemd-sysv live-boot live-config-systemd \
  linux-image-amd64 network-manager pipewire-audio; do
  have_package "$package" || { echo "ISO is missing base package: $package" >&2; exit 1; }
done

# --- Desktop stack ----------------------------------------------------------
for package in kde-plasma-desktop plasma-desktop plasma-workspace kwin-x11 sddm \
  dolphin konsole ark kde-spectacle plasma-nm plasma-pa powerdevil bluedevil \
  plasma-discover packagekit flatpak pipewire-audio network-manager \
  papirus-icon-theme fonts-inter plank dconf-cli kcalc kate gwenview okular \
  calamares calamares-settings-debian pkexec plymouth plymouth-themes \
  cups print-manager simple-scan orca onboard power-profiles-daemon \
  systemd-zram-generator fwupd shreeos-tools; do
  have_package "$package" || { echo "ISO is missing desktop package: $package" >&2; exit 1; }
done

# --- These must NOT be present ----------------------------------------------
# A second desktop suite would double the session's process tree, and the
# source-built lpm tool must not compete with APT over Debian-managed files.
for package in task-xfce-desktop gnome-shell; do
  if have_package "$package"; then
    echo "ISO unexpectedly contains a second desktop suite: $package" >&2
    exit 1
  fi
done

# --- ShreeOS-owned payload --------------------------------------------------
# Every entry here is required for the unified image; there is no "optional"
# escape hatch, so a silently dropped asset fails the build's own gate.
contents="$(unsquashfs -ll "$SQUASHFS")"
[ -n "$contents" ] || { echo 'Could not list the SquashFS contents' >&2; exit 1; }

for asset in \
  etc/apt/apt.conf.d/99-shreeos-security \
  etc/shreeos/firmware-policy \
  etc/shreeos/image-profile \
  etc/skel/.config/baloofilerc \
  etc/skel/.config/kwinrc \
  usr/local/bin/shreeos-software \
  usr/local/bin/shreeos-power \
  usr/local/bin/shreeos-motion \
  usr/local/bin/shreeos-theme \
  usr/local/bin/shreeos-installer \
  usr/share/applications/shreeos-power.desktop \
  usr/share/plasma/look-and-feel/org.shreeos.desktop/contents/layouts/org.kde.plasma.desktop-layout.js \
  usr/lib/systemd/zram-generator.conf.d/50-shreeos.conf; do
  if ! grep -Fq "squashfs-root/$asset" <<<"$contents"; then
    echo "ISO is missing ShreeOS asset: $asset" >&2
    exit 1
  fi
done

# --- Version agreement inside the image -------------------------------------
image_version="$(unsquashfs -cat "$SQUASHFS" etc/os-release | sed -n 's/^VERSION="\([^"]*\)".*/\1/p')"
expected_version="$(tr -d '[:space:]' < "$(dirname "${BASH_SOURCE[0]}")/../../VERSION")"
[ -n "$image_version" ] || { echo 'Image /etc/os-release has no VERSION' >&2; exit 1; }
[ "$image_version" = "$expected_version" ] || {
  echo "Image advertises version '$image_version' but VERSION is '$expected_version'" >&2
  exit 1
}
grep -Fxq 'ID=shreeos' <(unsquashfs -cat "$SQUASHFS" etc/os-release) || {
  echo 'Image /etc/os-release does not identify ShreeOS' >&2; exit 1
}

# --- Firmware policy --------------------------------------------------------
firmware_policy="$(unsquashfs -cat "$SQUASHFS" etc/shreeos/firmware-policy)"
case "$firmware_policy" in
  standard)
    for package in firmware-amd-graphics firmware-intel-graphics \
      firmware-iwlwifi firmware-realtek firmware-atheros firmware-brcm80211 \
      firmware-sof-signed intel-microcode amd64-microcode; do
      have_package "$package" || { echo "Standard-firmware image is missing: $package" >&2; exit 1; }
    done
    ;;
  free) ;;
  *)
    echo "Unknown firmware policy in the image: $firmware_policy" >&2
    exit 1
    ;;
esac

# --- The archive is a real hybrid image -------------------------------------
# live-build emits a GRUB hybrid image; require the EFI boot image and confirm
# xorriso can read the ISO as a bootable session.
if ! xorriso -indev "$ISO" -find /boot/grub/efi.img >/dev/null 2>&1 &&
  ! xorriso -indev "$ISO" -find /efi.img >/dev/null 2>&1; then
  echo 'ISO has no EFI boot image' >&2
  exit 1
fi
xorriso -indev "$ISO" -toc >/dev/null 2>&1 || {
  echo 'ISO is not a readable optical image' >&2
  exit 1
}

printf 'SquashFS and package verification passed for %s (version %s).\n' \
  "$(basename -- "$ISO")" "$image_version"
