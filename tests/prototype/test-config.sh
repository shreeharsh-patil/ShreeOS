#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
CONFIG_DIR="$REPO_ROOT/prototype/debian-live"
source "$CONFIG_DIR/versions.conf"

[[ "$DEBIAN_SUITE" =~ ^trixie$ ]]
[[ "$DEBIAN_SNAPSHOT" =~ ^[0-9]{8}T[0-9]{6}Z$ ]]
[[ "$LIVE_BUILD_VERSION" = '1:20250505+deb13u1' ]]

packages="$CONFIG_DIR/config/package-lists/shreeos-base.list.chroot"
actual="$(sed -e '/^[[:space:]]*#/d' -e '/^[[:space:]]*$/d' "$packages" | sort)"
unique="$(printf '%s\n' "$actual" | uniq)"
test "$actual" = "$unique"
for required in apt ca-certificates live-boot live-config-systemd \
  linux-image-amd64 network-manager systemd-sysv passwd; do
  grep -Fxq "$required" "$packages" || {
    echo "Prototype package list is missing: $required" >&2
    exit 1
  }
done

grep -Fq 'ID=shreeos' "$CONFIG_DIR/config/includes.chroot/etc/os-release"
grep -Fq 'ID_LIKE=debian' "$CONFIG_DIR/config/includes.chroot/etc/os-release"
grep -Fq 'shreeos-live-boot-check' \
  "$CONFIG_DIR/config/includes.chroot/etc/systemd/system/shreeos-boot-check.service"
lock_hook="$CONFIG_DIR/config/includes.chroot/lib/live/config/9999-lock-live-user"
boot_check="$CONFIG_DIR/config/includes.chroot/usr/local/sbin/shreeos-live-boot-check"
test -f "$lock_hook"
test -f "$boot_check"
grep -Fq 'passwd --lock shree' "$lock_hook"
grep -Fq 'passwd --status shree' "$boot_check"
grep -Fq 'SHREEOS_LIVE_BOOT_OK' "$boot_check"
grep -Fq 'apt-get check' "$boot_check"
grep -Fq 'lsblk -ndo TYPE' "$boot_check"
grep -Fq 'NetworkManager.service' "$boot_check"
grep -Fq 'nmcli -t -f TYPE,STATE device status' "$boot_check"
grep -Fq 'unexpectedly has sudo access' "$boot_check"
if grep -Eq 'live-config\.components=[^ ]*sudo' \
  "$REPO_ROOT/scripts/build-debian-prototype.sh"; then
  echo 'The console prototype must not grant sudo to its live account.' >&2
  exit 1
fi
grep -Fxq 'passwd' "$packages"
if grep -Fxq 'sudo' "$packages"; then
  echo 'The console prototype does not need the sudo package.' >&2
  exit 1
fi

desktop_packages="$CONFIG_DIR/profiles/desktop/package-lists/shreeos-desktop.list.chroot"
desktop_actual="$(sed -e '/^[[:space:]]*#/d' -e '/^[[:space:]]*$/d' "$desktop_packages" | sort)"
desktop_unique="$(printf '%s\n' "$desktop_actual" | uniq)"
test "$desktop_actual" = "$desktop_unique"
for required in bluez blueman firefox-esr firmware-linux-free pipewire-audio \
  lightdm-gtk-greeter network-manager-applet task-xfce-desktop \
  xfce4-pulseaudio-plugin; do
  grep -Fxq "$required" "$desktop_packages" || {
    echo "Desktop profile is missing: $required" >&2
    exit 1
  }
done
grep -Fq 'shreeos-wallpaper.svg' \
  "$CONFIG_DIR/profiles/desktop/includes.chroot/etc/skel/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-desktop.xml"
grep -Fq 'shreeos-logo.svg' \
  "$CONFIG_DIR/profiles/desktop/includes.chroot/etc/lightdm/lightdm-gtk-greeter.conf.d/50-shreeos.conf"
grep -Fxq desktop \
  "$CONFIG_DIR/profiles/desktop/includes.chroot/etc/shreeos/image-profile"
printf 'Debian prototype configuration contract passed.\n'
