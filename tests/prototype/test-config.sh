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
grep -Fq -- '--apt-options "--yes -o Acquire::Retries=5 -o Acquire::Check-Valid-Until=false"' \
  "$REPO_ROOT/scripts/build-debian-prototype.sh"
grep -Fq 'shreeos-live-boot-check' \
  "$CONFIG_DIR/config/includes.chroot/etc/systemd/system/shreeos-boot-check.service"
lock_hook="$CONFIG_DIR/config/includes.chroot/lib/live/config-hooks/2000-lock-live-user"
boot_check="$CONFIG_DIR/config/includes.chroot/usr/local/sbin/shreeos-live-boot-check"
test -f "$lock_hook"
test -x "$lock_hook"
test -f "$boot_check"
test -x "$CONFIG_DIR/profiles/desktop/includes.chroot/usr/local/lib/shreeos/first_run.py"
grep -Fq 'passwd --lock shree' "$lock_hook"
grep -Fq 'live-config.hooks=filesystem' \
  "$REPO_ROOT/scripts/build-debian-prototype.sh"
grep -Fq 'LIVE_APPEND_COMPONENTS=hostname,user-setup,locales,tzdata,keyboard-configuration,hooks' \
  "$REPO_ROOT/scripts/build-debian-prototype.sh"
grep -Fq 'LIVE_APPEND_COMPONENTS=hostname,user-setup,locales,tzdata,keyboard-configuration,lightdm,hooks' \
  "$REPO_ROOT/scripts/build-debian-prototype.sh"
grep -Fq 'passwd --status shree' "$boot_check"
grep -Fq 'live account password is locked' "$boot_check"
grep -Fq 'SHREEOS_LIVE_BOOT_OK' "$boot_check"
grep -Fq 'SHREEOS_BOOT_CHECK: %s' "$boot_check"
grep -Fq 'StandardOutput=journal+console' \
  "$CONFIG_DIR/config/includes.chroot/etc/systemd/system/shreeos-boot-check.service"
grub_config="$CONFIG_DIR/config/bootloaders/grub-pc"
test -s "$grub_config/splash.svg"
test -s "$grub_config/live-theme/theme.txt"
grep -Fq 'title-text: "ShreeOS"' "$grub_config/live-theme/theme.txt"
grep -Fq 'desktop-image: "../splash.png"' "$grub_config/live-theme/theme.txt"
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
for required in arc-theme bluez blueman brightness-udev brightnessctl dconf-cli firefox-esr fonts-inter plank \
  firmware-linux-free papirus-icon-theme pipewire-audio \
  python3-gi \
  lightdm-gtk-greeter network-manager-applet task-xfce-desktop xfce4-screenshooter \
  wmctrl xfce4-notifyd xfce4-pulseaudio-plugin xdg-user-dirs; do
  grep -Fxq "$required" "$desktop_packages" || {
    echo "Desktop profile is missing: $required" >&2
    exit 1
  }
done
grep -Fq 'shreeos-calm-light.png' \
  "$CONFIG_DIR/profiles/desktop/includes.chroot/etc/skel/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-desktop.xml"
grep -Fq 'image-show" type="bool" value="true"' \
  "$CONFIG_DIR/profiles/desktop/includes.chroot/etc/skel/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-desktop.xml"
grep -Fq 'image-show' \
  "$CONFIG_DIR/profiles/desktop/includes.chroot/usr/local/bin/shreeos-session-setup"
grep -Fq 'xfdesktop --reload' \
  "$CONFIG_DIR/profiles/desktop/includes.chroot/usr/local/bin/shreeos-session-setup"
grep -Fq 'sleep 3' \
  "$CONFIG_DIR/profiles/desktop/includes.chroot/usr/local/bin/shreeos-session-setup"
grep -Fq 'Exec=/usr/local/bin/shreeos-dock-session' \
  "$CONFIG_DIR/profiles/desktop/includes.chroot/etc/xdg/autostart/shreeos-dock.desktop"
grep -Fq 'OnlyShowIn=XFCE;' \
  "$CONFIG_DIR/profiles/desktop/includes.chroot/etc/xdg/autostart/shreeos-dock.desktop"
grep -Fq 'shreeos-logo.svg' \
  "$CONFIG_DIR/profiles/desktop/includes.chroot/etc/lightdm/lightdm-gtk-greeter.conf.d/50-shreeos.conf"
grep -Fxq desktop \
  "$CONFIG_DIR/profiles/desktop/includes.chroot/etc/shreeos/image-profile"
plasma_packages="$CONFIG_DIR/profiles/plasma/package-lists/shreeos-plasma.list.chroot"
plasma_actual="$(sed -e '/^[[:space:]]*#/d' -e '/^[[:space:]]*$/d' "$plasma_packages" | sort)"
plasma_unique="$(printf '%s\n' "$plasma_actual" | uniq)"
test "$plasma_actual" = "$plasma_unique"
for required in kde-plasma-desktop plasma-desktop plasma-workspace kwin-x11 sddm sddm-theme-breeze \
  breeze-gtk-theme breeze-cursor-theme dolphin konsole ark kde-spectacle \
  plasma-discover plasma-discover-backend-flatpak flatpak packagekit plasma-nm \
  plasma-pa powerdevil bluedevil pipewire-audio network-manager papirus-icon-theme \
  fonts-inter x11-xserver-utils kdialog libnotify-bin plank dconf-cli kate gwenview okular kcalc; do
  grep -Fxq "$required" "$plasma_packages" || {
    echo "Plasma profile is missing: $required" >&2
    exit 1
  }
done
plasma_includes="$CONFIG_DIR/profiles/plasma/includes.chroot"
grep -Fq 'Current=shreeos' "$plasma_includes/etc/sddm.conf.d/10-shreeos.conf"
grep -Fq 'Session=plasmax11.desktop' "$plasma_includes/etc/sddm.conf.d/20-shreeos-live-autologin.conf"
grep -Fq 'User=shree' "$plasma_includes/etc/sddm.conf.d/20-shreeos-live-autologin.conf"
test -s "$plasma_includes/usr/share/sddm/themes/shreeos/Main.qml"
test -s "$plasma_includes/usr/share/sddm/themes/shreeos/theme.conf"
test -x "$plasma_includes/usr/local/sbin/shreeos-sddm-live-autologin"
test -x "$CONFIG_DIR/profiles/plasma/hooks/9001-shreeos-sddm.hook.chroot"
grep -Fq 'sddm.login(userPicker.currentText' \
  "$plasma_includes/usr/share/sddm/themes/shreeos/Main.qml"
grep -Fq 'sddm.canPowerOff' \
  "$plasma_includes/usr/share/sddm/themes/shreeos/Main.qml"
grep -Fq 'width: Screen.width' \
  "$plasma_includes/usr/share/sddm/themes/shreeos/Main.qml"
grep -Fq 'shreeos-logo.png' \
  "$plasma_includes/usr/share/sddm/themes/shreeos/Main.qml"
grep -Fq 'Meta+Space' "$plasma_includes/etc/skel/.config/kglobalshortcutsrc"
grep -Fq 'Exec=/usr/local/bin/shreeos-plasma-first-login' \
  "$plasma_includes/etc/skel/.config/autostart/shreeos-plasma-defaults.desktop"
test -x "$plasma_includes/usr/local/bin/shreeos-plasma-first-login"
test -x "$plasma_includes/usr/local/bin/shreeos-open-downloads"
test -x "$plasma_includes/usr/local/bin/shreeos-open-trash"
test -x "$plasma_includes/usr/local/bin/shreeos-theme"
test -f "$REPO_ROOT/desktop/plasma/layout.js"
test -s "$REPO_ROOT/themes/plasma/colors/ShreeOS-Light.colors"
test -s "$REPO_ROOT/themes/plasma/colors/ShreeOS-Dark.colors"
grep -Fq 'plasma-apply-wallpaperimage' "$plasma_includes/usr/local/bin/shreeos-plasma-first-login"
grep -Fq 'ShreeOS Light' "$plasma_includes/usr/share/plasma/look-and-feel/org.shreeos.desktop/contents/defaults"
grep -Fq 'shreeos-trash.desktop' "$plasma_includes/etc/skel/.config/plank/dock1/launchers/trash.dockitem"
grep -Fq 'shreeos-installer.desktop' "$plasma_includes/etc/skel/.config/plank/dock1/launchers/installer.dockitem"
grep -Fq 'org.kde.plasma.appmenu' "$REPO_ROOT/desktop/plasma/layout.js"
test -s "$plasma_includes/usr/local/bin/shreeos-plasma-dock"
grep -Fq 'org.kde.discover.desktop' "$plasma_includes/etc/skel/.config/plank/dock1/launchers/software.dockitem"
grep -Fq 'org.kde.plasma.kickoff' "$plasma_includes/usr/local/bin/shreeos-plasma-first-login"
grep -Fq 'org.kde.plasma.digitalclock' "$plasma_includes/usr/local/bin/shreeos-plasma-first-login"
test -s "$plasma_includes/usr/share/applications/shreeos-appearance.desktop"
test -s "$plasma_includes/usr/share/applications/shreeos-downloads.desktop"
test -s "$plasma_includes/usr/share/applications/shreeos-trash.desktop"
grep -Fq 'profiles/desktop/includes.chroot/usr/local/bin/shreeos-installer' \
  "$REPO_ROOT/scripts/build-debian-prototype.sh"
grep -Fq 'profiles/desktop/includes.chroot/usr/local/libexec/shreeos-installer-privileged' \
  "$REPO_ROOT/scripts/build-debian-prototype.sh"
test -s "$CONFIG_DIR/profiles/desktop/includes.chroot/etc/calamares/branding/shreeos/branding.desc"
grep -Fq 'etc/calamares/branding/shreeos' "$REPO_ROOT/scripts/build-debian-prototype.sh"
grep -Fq 'branding/logo/shreeos-logo.svg' "$REPO_ROOT/scripts/build-debian-prototype.sh"
test -s "$CONFIG_DIR/profiles/desktop/includes.chroot/usr/share/polkit-1/actions/org.shreeos.installer.policy"
test -s "$plasma_includes/etc/systemd/system/shreeos-sddm-live-autologin.service"
grep -Fq '20-shreeos-live-autologin.conf' \
  "$plasma_includes/usr/local/sbin/shreeos-sddm-live-autologin"
grep -Fq '/run/live/medium' \
  "$plasma_includes/usr/local/sbin/shreeos-sddm-live-autologin"
grep -Fq 'systemctl enable shreeos-sddm-live-autologin.service' \
  "$CONFIG_DIR/profiles/plasma/hooks/9001-shreeos-sddm.hook.chroot"
grep -Fq 'file:///usr/share/backgrounds/shreeos/shreeos-alpenglow.png' \
  "$plasma_includes/usr/share/sddm/themes/shreeos/Main.qml"
test -s "$plasma_includes/etc/skel/.local/share/konsole/ShreeOS.profile"
grep -Fq 'DefaultProfile=ShreeOS.profile' "$plasma_includes/etc/skel/.config/konsolerc"
test -s "$plasma_includes/etc/skel/.config/gtk-4.0/settings.ini"
test -s "$plasma_includes/usr/share/konsole/ShreeOS Dark.colorscheme"
test -s "$plasma_includes/usr/share/konsole/ShreeOS Light.colorscheme"
grep -Fq 'Url=https://dl.flathub.org/repo/' \
  "$plasma_includes/usr/share/flatpak/remotes.d/flathub.flatpakrepo"
grep -Fq 'GPGKey=' "$plasma_includes/usr/share/flatpak/remotes.d/flathub.flatpakrepo"
grep -Fq 'plasma-apply-colorscheme' "$plasma_includes/usr/local/bin/shreeos-theme"
grep -Fq 'desktop/plasma/layout.js' "$REPO_ROOT/scripts/build-debian-prototype.sh"
grep -Fq 'shreeos-logo.png' "$REPO_ROOT/scripts/build-debian-prototype.sh"
grep -Fxq plasma "$plasma_includes/etc/shreeos/image-profile"
desktop_includes="$CONFIG_DIR/profiles/desktop/includes.chroot"
test -s "$desktop_includes/etc/skel/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-panel.xml"
test -s "$desktop_includes/etc/skel/.config/xfce4/xfconf/xfce-perchannel-xml/xfwm4.xml"
test -s "$desktop_includes/etc/skel/.config/xfce4/xfconf/xfce-perchannel-xml/xsettings.xml"
test -s "$desktop_includes/usr/share/plank/themes/ShreeOS/dock.theme"
test -s "$desktop_includes/usr/share/plank/themes/ShreeOS-Light/dock.theme"
test -x "$desktop_includes/usr/local/bin/shreeos-dock-session"
grep -Fq 'pgrep -x xfwm4' "$desktop_includes/usr/local/bin/shreeos-dock-session"
grep -Fq 'shreeos-dock-session.log' "$desktop_includes/usr/local/bin/shreeos-dock-session"
grep -Fq 'sleep 3' "$desktop_includes/usr/local/bin/shreeos-session-setup"
test -x "$desktop_includes/usr/local/bin/shreeos-control-center"
test -x "$desktop_includes/usr/local/bin/shreeos-search"
test -x "$desktop_includes/usr/local/bin/shreeos-overview"
test -s "$desktop_includes/usr/share/applications/shreeos-control-center.desktop"
test -s "$desktop_includes/usr/share/applications/shreeos-search.desktop"
test -s "$desktop_includes/usr/share/icons/hicolor/scalable/apps/shreeos-control-center.svg"
grep -Fq "theme='ShreeOS-Light'" "$desktop_includes/usr/share/shreeos/defaults/plank.dconf"
grep -Fq 'gtk-theme-name=Arc' \
  "$desktop_includes/etc/skel/.config/gtk-3.0/settings.ini"
grep -Fq 'button_layout' \
  "$desktop_includes/etc/skel/.config/xfce4/xfconf/xfce-perchannel-xml/xfwm4.xml"
test -f "$desktop_includes/etc/skel/.config/plank/dock1/launchers/thunar.dockitem"
test -f "$desktop_includes/etc/skel/.config/plank/dock1/launchers/downloads.dockitem"
test -f "$desktop_includes/etc/skel/.config/plank/dock1/launchers/trash.dockitem"
test -f "$desktop_includes/etc/skel/.config/plank/dock1/launchers/shreeos-search.dockitem"
test -f "$desktop_includes/etc/skel/.config/plank/dock1/launchers/shreeos-overview.dockitem"
test -s "$desktop_includes/etc/skel/.config/gtk-3.0/bookmarks"
test -f "$desktop_includes/etc/skel/.config/autostart/shreeos-dock.desktop"
test -f "$desktop_includes/etc/skel/.config/autostart/shreeos-first-run.desktop"
test ! -e "$desktop_includes/etc/skel/.config/autostart/plank.desktop"
grep -Fq 'shreeos-calm-light.png' \
  "$desktop_includes/etc/skel/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-desktop.xml"
grep -Fq 'rsvg-convert --width=1920' "$REPO_ROOT/scripts/build-debian-prototype.sh"
grep -Fq 'shreeos-alpenglow.png' \
  "$CONFIG_DIR/profiles/plasma/includes.chroot/usr/local/bin/shreeos-plasma-first-login"
printf 'Debian prototype configuration contract passed.\n'
