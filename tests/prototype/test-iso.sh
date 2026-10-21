#!/usr/bin/env bash
set -Eeuo pipefail

if [ "$#" -lt 1 ] || [ "$#" -gt 2 ] || [ ! -s "$1" ]; then
  echo "Usage: test-iso.sh PATH_TO_SHREEOS_ISO [base|desktop|plasma]" >&2
  echo "  The unified release image is out/shreeos(VERSION).iso (profile: plasma)." >&2
  exit 2
fi
ISO="$(realpath "$1")"
PROFILE="${2:-base}"
case "$PROFILE" in
  base|desktop|plasma) ;;
  *) echo "Unknown profile: $PROFILE" >&2; exit 2 ;;
esac
for tool in xorriso unsquashfs qemu-system-x86_64 qemu-img timeout sha256sum xvfb-run; do
  command -v "$tool" >/dev/null 2>&1 || {
    echo "Missing ISO test dependency: $tool" >&2
    exit 2
  }
done

TEST_DIR="$(mktemp -d)"
trap 'rm -rf -- "$TEST_DIR"' EXIT
QEMU_LOG_DIR="${QEMU_LOG_DIR:-}"
if [ -n "$QEMU_LOG_DIR" ]; then mkdir -p "$QEMU_LOG_DIR"; fi
SQUASHFS="$TEST_DIR/filesystem.squashfs"
TARGET_DISK="$TEST_DIR/target.raw"
qemu-img create -q -f raw "$TARGET_DISK" 2G
xorriso -osirrox on -indev "$ISO" -extract /live/filesystem.squashfs "$SQUASHFS" >/dev/null
unsquashfs -s "$SQUASHFS" >/dev/null
xorriso -osirrox on -indev "$ISO" -extract /live/filesystem.packages "$TEST_DIR/packages.txt" >/dev/null
for package in apt live-boot live-config-systemd user-setup network-manager systemd-sysv; do
  grep -Eq "^${package}(:[^[:space:]]+)?([[:space:]]|$)" "$TEST_DIR/packages.txt" || {
    echo "ISO package manifest is missing required package: $package" >&2
    exit 1
  }
done
shared_contents="$(unsquashfs -ll "$SQUASHFS")"
for asset in etc/apt/apt.conf.d/99-shreeos-security etc/shreeos/firmware-policy \
  usr/local/bin/shreeos-software usr/share/shreeos/toolsets/security.list.chroot \
  usr/share/shreeos/toolsets/developer.list.chroot usr/share/shreeos/toolsets/creative.list.chroot; do
  grep -Fq "squashfs-root/$asset" <<<"$shared_contents" || {
    echo "ISO is missing system feature: $asset" >&2; exit 1;
  }
done
firmware_policy="$(unsquashfs -cat "$SQUASHFS" etc/shreeos/firmware-policy)"
if [ "$firmware_policy" = standard ]; then
  for package in firmware-iwlwifi firmware-realtek firmware-amd-graphics intel-microcode amd64-microcode; do
    grep -Eq "^${package}(:[^[:space:]]+)?([[:space:]]|$)" "$TEST_DIR/packages.txt" || {
      echo "Standard firmware ISO is missing: $package" >&2; exit 1;
    }
  done
elif [ "$firmware_policy" != free ]; then
  echo "Unknown ISO firmware policy: $firmware_policy" >&2; exit 1
fi
if [ "$PROFILE" = desktop ]; then
  for package in arc-theme bluez blueman brightness-udev brightnessctl dconf-cli firefox-esr fonts-inter lightdm \
    papirus-icon-theme pipewire-audio \
    python3-gi wmctrl lightdm-gtk-greeter network-manager-applet task-xfce-desktop \
    xfce4-appfinder xfce4-notifyd xfce4-power-manager \
    xfce4-pulseaudio-plugin xfce4-screenshooter mousepad synaptic parole \
    xfce4-screensaver libnotify-bin plank \
    libreoffice-writer atril ristretto galculator xarchiver xdg-user-dirs \
    calamares calamares-settings-debian pkexec onboard orca \
    speech-dispatcher-espeak-ng librsvg2-common plymouth plymouth-themes; do
    grep -Eq "^${package}(:[^[:space:]]+)?([[:space:]]|$)" "$TEST_DIR/packages.txt" || {
      echo "Desktop ISO package manifest is missing: $package" >&2
      exit 1
    }
  done
  image_contents="$(unsquashfs -ll "$SQUASHFS")"
  for desktop_asset in \
    etc/xdg/autostart/shreeos-dock.desktop \
    etc/xdg/autostart/shreeos-session-setup.desktop \
    usr/local/bin/shreeos-dock-session \
    usr/share/backgrounds/shreeos/shreeos-calm-dark.png \
    usr/share/icons/hicolor/scalable/apps/shreeos.svg \
    usr/share/shreeos/branding/shreeos-logo-black.svg \
    usr/share/shreeos/branding/shreeos-logo-white.svg \
    usr/share/shreeos/branding/shreeos-logo-adaptive.svg; do
    if ! grep -Fq "squashfs-root/$desktop_asset" <<<"$image_contents"; then
      echo "Desktop ISO is missing ShreeOS desktop asset: $desktop_asset" >&2
      exit 1
    fi
  done
fi
# These are the packages shipped by the default Plasma profile. Office and
# multimedia suites are opt-in toolsets and are checked separately.
if [ "$PROFILE" = plasma ]; then
  for package in kde-plasma-desktop plasma-desktop plasma-workspace kwin-x11 sddm \
    sddm-theme-breeze breeze-gtk-theme breeze-cursor-theme dolphin konsole ark kde-spectacle \
    plasma-discover plasma-discover-backend-flatpak flatpak packagekit \
    plasma-nm plasma-pa powerdevil bluedevil pipewire-audio network-manager papirus-icon-theme \
    fonts-inter x11-xserver-utils kdialog libnotify-bin plymouth plymouth-themes calamares calamares-settings-debian \
    plank dconf-cli kate gwenview okular kcalc \
    cups print-manager simple-scan orca speech-dispatcher-espeak-ng onboard \
    power-profiles-daemon systemd-zram-generator fwupd plasma-discover-backend-fwupd; do
    grep -Eq "^${package}(:[^[:space:]]+)?([[:space:]]|$)" "$TEST_DIR/packages.txt" || {
      echo "Plasma ISO package manifest is missing: $package" >&2
      exit 1
    }
  done
  image_contents="$(unsquashfs -ll "$SQUASHFS")"
  for image_path in \
    etc/shreeos/image-profile \
    etc/sddm.conf.d/10-shreeos.conf \
    etc/sddm.conf.d/20-shreeos-live-autologin.conf \
    etc/systemd/system/shreeos-sddm-live-autologin.service \
    etc/skel/.config/autostart/shreeos-plasma-defaults.desktop \
    etc/skel/.config/autostart/shreeos-plasma-dock.desktop \
    etc/skel/.config/autostart/calamares-desktop-icon.desktop \
    etc/skel/.config/baloofilerc \
    etc/skel/.config/kwinrc \
    usr/local/bin/shreeos-power \
    usr/share/applications/shreeos-power.desktop \
    etc/skel/.config/plank/dock1/launchers/files.dockitem \
    usr/share/plasma/look-and-feel/org.shreeos.desktop/contents/layouts/org.kde.plasma.desktop-layout.js \
    usr/local/bin/shreeos-plasma-first-login \
    usr/local/bin/shreeos-plasma-dock \
    usr/share/shreeos/defaults/plasma-plank.dconf \
    usr/share/plank/themes/ShreeOS-Glass/dock.theme \
    usr/share/plank/themes/ShreeOS-Glass-Dark/dock.theme \
    usr/share/plasma/desktoptheme/shreeos-glass/metadata.json \
    usr/share/plasma/desktoptheme/shreeos-glass/widgets/panel-background.svg \
    usr/share/plasma/desktoptheme/shreeos-glass/opaque/widgets/panel-background.svg \
    usr/share/backgrounds/shreeos/shreeos-ember-flow.png \
    usr/share/backgrounds/shreeos/shreeos-alpenglow.png \
    usr/local/bin/shreeos-open-downloads \
    usr/local/bin/shreeos-open-trash \
    usr/local/bin/shreeos-theme \
    usr/local/bin/shreeos-motion \
    usr/share/applications/shreeos-motion.desktop \
    usr/lib/systemd/zram-generator.conf.d/50-shreeos.conf \
    usr/lib/calamares/modules/shreeos-sources/module.desc \
    usr/lib/calamares/modules/shreeos-sources/main.py \
    usr/local/bin/shreeos-installer \
    usr/local/libexec/shreeos-installer-privileged \
    usr/share/applications/shreeos-installer.desktop \
    usr/share/applications/shreeos-search.desktop \
    usr/share/applications/shreeos-appearance.desktop \
    usr/share/applications/shreeos-downloads.desktop \
    usr/share/applications/shreeos-trash.desktop \
    usr/share/applications/org.kde.dolphin.desktop \
    usr/share/applications/firefox-esr.desktop \
    usr/share/applications/org.kde.kate.desktop \
    usr/share/applications/org.kde.gwenview.desktop \
    usr/share/applications/org.kde.okular.desktop \
    usr/share/applications/org.kde.kcalc.desktop \
    usr/share/applications/org.kde.konsole.desktop \
    usr/share/applications/org.kde.discover.desktop \
    usr/share/applications/systemsettings.desktop \
    usr/share/icons/hicolor/scalable/apps/shreeos-installer.svg \
    usr/share/polkit-1/actions/org.shreeos.installer.policy \
    etc/calamares/settings.conf \
    etc/calamares/branding/shreeos/branding.desc \
    etc/calamares/branding/shreeos/shreeos-logo.svg \
    etc/calamares/branding/shreeos/shreeos-app.svg \
    usr/share/sddm/themes/shreeos/Main.qml \
    usr/share/sddm/themes/shreeos/theme.conf \
    usr/local/sbin/shreeos-sddm-live-autologin \
    "usr/share/color-schemes/ShreeOS Dark.colors" \
    "usr/share/color-schemes/ShreeOS Light.colors" \
    "usr/share/konsole/ShreeOS Dark.colorscheme" \
    "usr/share/konsole/ShreeOS Light.colorscheme" \
    usr/share/flatpak/remotes.d/flathub.flatpakrepo \
    usr/share/pixmaps/shreeos-logo.png \
    usr/share/icons/hicolor/scalable/apps/shreeos.svg \
    usr/share/shreeos/branding/shreeos-logo-black.svg \
    usr/share/shreeos/branding/shreeos-logo-white.svg \
    usr/share/shreeos/branding/shreeos-logo-adaptive.svg; do
    if ! grep -Fq "squashfs-root/$image_path" <<<"$image_contents"; then
      echo "Plasma ISO is missing ShreeOS desktop asset: $image_path" >&2
      exit 1
    fi
  done
fi

run_boot_test() {
  local mode="$1"
  local firmware_args=() log="$TEST_DIR/${mode}.log"
  local emulator_log="$TEST_DIR/${mode}-qemu.log"
  local monitor_socket="$TEST_DIR/${mode}-monitor.sock"
  local screen_dump="$TEST_DIR/${PROFILE}-${mode}-screen.ppm"
  local screen_before_dock_dump="$TEST_DIR/${PROFILE}-${mode}-screen-before-dock.ppm"
  local menu_dump="$TEST_DIR/${PROFILE}-${mode}-menu.ppm" status=0
  local splash_dump="$TEST_DIR/${PROFILE}-${mode}-splash.ppm"
  local screenshot_captured=0 cleanup_signal_sent=0 boot_check_failed=0
  local qemu_timeout=420
  if [ "$PROFILE" = plasma ]; then qemu_timeout=1800; fi
  local deadline=$((SECONDS + qemu_timeout))
  local memory=2048
  if [ "$PROFILE" = plasma ]; then memory=4096; fi
  if [ "$mode" = uefi ]; then
    local firmware="${OVMF_CODE:-}" firmware_vars="${OVMF_VARS:-}"
    if [ -z "$firmware" ]; then
      for candidate in \
        /usr/share/OVMF/OVMF_CODE_4M.fd \
        /usr/share/OVMF/OVMF_CODE.fd \
        /usr/share/ovmf/OVMF.fd \
        /usr/share/qemu/OVMF.fd
      do
        if [ -s "$candidate" ]; then firmware="$candidate"; break; fi
      done
    fi
    if [ -z "$firmware_vars" ]; then
      for candidate in \
        /usr/share/OVMF/OVMF_VARS_4M.fd \
        /usr/share/OVMF/OVMF_VARS.fd \
        /usr/share/ovmf/OVMF_VARS.fd \
        /usr/share/qemu/OVMF_VARS.fd
      do
        if [ -s "$candidate" ]; then firmware_vars="$candidate"; break; fi
      done
    fi
    [ -s "$firmware" ] || { echo "UEFI firmware not found: $firmware" >&2; return 1; }
    [ -s "$firmware_vars" ] || { echo "UEFI variable store not found: $firmware_vars" >&2; return 1; }
    local vars_copy="$TEST_DIR/${mode}-OVMF_VARS.fd"
    cp -- "$firmware_vars" "$vars_copy"
    firmware_args=(
      -drive "if=pflash,format=raw,readonly=on,file=$firmware"
      -drive "if=pflash,format=raw,file=$vars_copy"
    )
  fi

  setsid xvfb-run -a -s "-screen 0 1280x800x24" timeout --signal=TERM "${qemu_timeout}s" qemu-system-x86_64 \
    -machine q35 -m "$memory" -smp 2 -vga virtio -nic user,model=virtio-net-pci \
    -drive "file=$TARGET_DISK,format=raw,if=virtio" \
    -cdrom "$ISO" -boot order=d \
    -display gtk -monitor "unix:$monitor_socket,server,nowait" \
    -serial stdio -no-reboot "${firmware_args[@]}" >"$log" 2>"$emulator_log" &
  local emulator_pid=$!
  sleep 20
  if ! grep -Fq 'SHREEOS_LIVE_BOOT_OK' "$log" 2>/dev/null; then
    if python3 - "$monitor_socket" "$menu_dump" "$splash_dump" "$log" >>"$emulator_log" 2>&1 <<'PY'
import socket
import sys
import time
import os
from pathlib import Path

monitor, output, splash, serial = sys.argv[1:]
client = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
client.settimeout(3)
for _ in range(10):
    try:
        client.connect(monitor)
        break
    except OSError:
        time.sleep(1)
else:
    raise SystemExit("QEMU monitor socket did not become available")
def read_prompt():
    response = bytearray()
    deadline = time.monotonic() + 10
    while b"(qemu) " not in response:
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            raise TimeoutError(f"QEMU monitor prompt timed out: {response.decode(errors='replace')}")
        client.settimeout(remaining)
        chunk = client.recv(4096)
        if not chunk:
            raise ConnectionError("QEMU monitor closed before returning a prompt")
        response.extend(chunk)
    text = response.decode(errors="replace")
    lowered = text.lower()
    if "error:" in lowered or "could not" in lowered or "unknown command" in lowered:
        raise RuntimeError(f"QEMU monitor command failed: {text.strip()}")

def command(value):
    client.sendall((value + "\n").encode())
    read_prompt()

def boot_marker_seen():
    try:
        contents = Path(serial).read_text(encoding="utf-8", errors="replace")
    except OSError:
        return False
    return "SHREEOS_LIVE_BOOT_OK" in contents or "SHREEOS_BOOT_CHECK: FAIL:" in contents

try:
    read_prompt()
    command(f"screendump {output}")
    command("sendkey home")
    # Retry Enter while TCG catches up. Check the serial marker so the final
    # keypress does not continue after boot validation has finished.
    for attempt in range(4):
        if boot_marker_seen():
            break
        command("sendkey ret")
        for _ in range(10):
            if boot_marker_seen():
                break
            time.sleep(1)
    command(f"screendump {splash}")
    for path in (output, splash):
        if not os.path.isfile(path) or os.path.getsize(path) == 0:
            raise RuntimeError(f"QEMU did not create screenshot: {path}")
finally:
    client.close()
PY
    then
      :
    else
      printf 'QEMU screen capture was unavailable.\n' >>"$emulator_log"
    fi
  fi

  while ! grep -Fq 'SHREEOS_LIVE_BOOT_OK' "$log" 2>/dev/null; do
    if grep -Fq 'SHREEOS_BOOT_CHECK: FAIL:' "$log" 2>/dev/null; then
      printf 'The live boot service reported a validation failure; stopping QEMU.\n' >>"$emulator_log"
      boot_check_failed=1
      kill -TERM -- "-$emulator_pid" 2>/dev/null || true
      cleanup_signal_sent=1
      break
    fi
    if ! kill -0 "$emulator_pid" 2>/dev/null || (( SECONDS >= deadline )); then
      break
    fi
    sleep 1
  done
  if grep -Fq 'SHREEOS_LIVE_BOOT_OK' "$log" 2>/dev/null; then
    if python3 - "$monitor_socket" "$screen_dump" >>"$emulator_log" 2>&1 <<'PY'
import socket
import sys
import time
import os

monitor, output = sys.argv[1:]
client = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
client.settimeout(3)
for _ in range(10):
    try:
        client.connect(monitor)
        break
    except OSError:
        time.sleep(1)
else:
    raise SystemExit("QEMU monitor socket did not become available to stop the guest")
def read_prompt():
    response = bytearray()
    deadline = time.monotonic() + 10
    while b"(qemu) " not in response:
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            raise TimeoutError(f"QEMU monitor prompt timed out: {response.decode(errors='replace')}")
        client.settimeout(remaining)
        chunk = client.recv(4096)
        if not chunk:
            raise ConnectionError("QEMU monitor closed before returning a prompt")
        response.extend(chunk)
    text = response.decode(errors="replace")
    if "Error:" in text or "Could not" in text:
        raise RuntimeError(f"QEMU monitor command failed: {text.strip()}")

def command(value):
    client.sendall((value + "\n").encode())
    read_prompt()

try:
    read_prompt()
    command("sendkey shift")
    # Give Plasma or XFCE time to finish rendering after the live-boot marker.
    time.sleep(30)
    # Both ShreeOS profiles run Plank with hiding disabled, so the dock must be
    # rendered from the start. Capture a frame before and after moving the guest
    # pointer to the bottom edge so the artifact records that the dock does not
    # depend on a pointer reveal.
    before_dock = output.replace("-screen.ppm", "-screen-before-dock.ppm")
    command(f"screendump {before_dock}")
    command("mouse_move 0 10000")
    time.sleep(2)
    command(f"screendump {output}")
    for path in (before_dock, output):
        if not os.path.isfile(path) or os.path.getsize(path) == 0:
            raise RuntimeError(f"QEMU did not create desktop screenshot: {path}")
    client.sendall(b"quit\n")
except Exception:
    # Avoid leaving QEMU alive until its long safety timeout after a capture error.
    try:
        client.sendall(b"quit\n")
    except OSError:
        pass
    raise
finally:
    client.close()
PY
    then
      screenshot_captured=1
    else
      printf 'QEMU desktop screenshot capture failed; stopping the guest.\n' >>"$emulator_log"
      kill -TERM -- "-$emulator_pid" 2>/dev/null || true
    fi
  fi
  # A live desktop has no reason to exit by itself. Stop the disposable QEMU
  # guest after a successful capture so the long safety timeout does not turn a
  # valid boot into a failed CI job. Only normalize the status for this explicit
  # harness shutdown; timeouts and other QEMU failures still fail the test.
  if (( screenshot_captured )) && kill -0 -- "-$emulator_pid" 2>/dev/null; then
    kill -TERM -- "-$emulator_pid" 2>/dev/null || true
    cleanup_signal_sent=1
  fi
  wait "$emulator_pid" || status=$?
  if (( cleanup_signal_sent )) && [[ "$status" -eq 143 ]]; then status=0; fi
  if (( boot_check_failed )); then status=1; fi

  if [ -n "$QEMU_LOG_DIR" ]; then
    if [ -f "$log" ]; then
      cp -- "$log" "$QEMU_LOG_DIR/${PROFILE}-${mode}-serial.log"
    fi
    if [ -f "$emulator_log" ]; then
      cp -- "$emulator_log" "$QEMU_LOG_DIR/${PROFILE}-${mode}-qemu.log"
    fi
    if [ -s "$screen_dump" ]; then
      cp -- "$screen_dump" "$QEMU_LOG_DIR/${PROFILE}-${mode}-screen.ppm"
    fi
    if [ -s "$screen_before_dock_dump" ]; then
      cp -- "$screen_before_dock_dump" "$QEMU_LOG_DIR/${PROFILE}-${mode}-screen-before-dock.ppm"
    fi
    if [ -s "$menu_dump" ]; then
      cp -- "$menu_dump" "$QEMU_LOG_DIR/${PROFILE}-${mode}-menu.ppm"
    fi
    if [ -s "$splash_dump" ]; then
      cp -- "$splash_dump" "$QEMU_LOG_DIR/${PROFILE}-${mode}-splash.ppm"
    fi
  fi

  if [ "$status" -ne 0 ]; then
    echo "${mode} QEMU exited with status $status before validation completed." >&2
    [ ! -s "$log" ] || cat "$log" >&2
    [ ! -s "$emulator_log" ] || cat "$emulator_log" >&2
    return 1
  fi

  if ! grep -Fq 'SHREEOS_LIVE_BOOT_OK' "$log" 2>/dev/null; then
    echo "${mode} boot did not reach the ShreeOS multi-user marker (qemu exit $status)." >&2
    [ ! -f "$log" ] || cat "$log" >&2
    [ ! -s "$emulator_log" ] || cat "$emulator_log" >&2
    return 1
  fi
  if [ "$PROFILE" = desktop ] || [ "$PROFILE" = plasma ]; then
    if [ ! -s "$screen_dump" ] || [ ! -s "$screen_before_dock_dump" ]; then
      echo "${mode} boot reached the health marker, but QEMU did not create a desktop screenshot." >&2
      [ ! -s "$emulator_log" ] || cat "$emulator_log" >&2
      return 1
    fi
    python3 - "$screen_dump" "$PROFILE" "$screen_before_dock_dump" <<'PY'
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
profile = sys.argv[2]
before_path = pathlib.Path(sys.argv[3])

def read_ppm(image_path):
    data = image_path.read_bytes()
    if not data.startswith(b"P6"):
        raise SystemExit(f"{profile} screenshot is not a binary PPM: {image_path}")
    # The header is "P6", width, height and maxval separated by whitespace and
    # followed by exactly one whitespace byte before the raster. Splitting the
    # whole file on whitespace would also swallow leading pixel values that
    # happen to be whitespace bytes, so the header is located explicitly.
    fields = []
    index = 2
    while len(fields) < 3:
        while index < len(data) and data[index:index + 1].isspace():
            index += 1
        if data[index:index + 1] == b"#":
            while index < len(data) and data[index:index + 1] not in (b"\n", b"\r"):
                index += 1
            continue
        start = index
        while index < len(data) and not data[index:index + 1].isspace():
            index += 1
        try:
            fields.append(int(data[start:index]))
        except ValueError:
            raise SystemExit(
                f"{profile} screenshot has an invalid PPM header: {image_path}"
            ) from None
    image_width, image_height, maximum = fields
    # Exactly one whitespace byte separates the header from the raster.
    index += 1
    if data[index:index + 2] == b"\r\n":
        index += 1
    image_pixels = data[index:]
    if maximum != 255 or len(image_pixels) != image_width * image_height * 3:
        raise SystemExit(f"{profile} screenshot has invalid pixel data: {image_path}")
    return image_width, image_height, image_pixels

width, height, pixels = read_ppm(path)
lit_pixels = sum(1 for i in range(0, len(pixels), 3)
                 if max(pixels[i:i + 3]) > 24)
if lit_pixels < width * height // 20:
    raise SystemExit(f"Desktop screenshot is blank or nearly blank: {path}")
desktop_top = 40
desktop_bottom = height - 64
desktop_pixels = pixels[desktop_top * width * 3:desktop_bottom * width * 3]
wallpaper_pixels = sum(1 for i in range(0, len(desktop_pixels), 3)
                       if max(desktop_pixels[i:i + 3]) > 8)
if profile in ("desktop", "plasma") and wallpaper_pixels < width * (desktop_bottom - desktop_top) // 2:
    raise SystemExit(f"ShreeOS wallpaper is missing from the desktop area: {path}")
if profile in ("desktop", "plasma"):
    before_width, before_height, before_pixels = read_ppm(before_path)
    if (before_width, before_height) != (width, height):
        raise SystemExit(f"Before/after desktop screenshots have different sizes: {path}")
    # Plank ships with hiding disabled in both profiles, so the dock has to be
    # drawn in the bottom band of every screenshot instead of being revealed by
    # the pointer moving to the edge. The frame captured before the pointer
    # moved therefore has to show the dock as well; checking both frames is
    # what proves the dock does not depend on a pointer reveal.
    band_start = (height - min(64, height)) * width * 3
    minimum_dock_pixels = max(24, width * 64 // 300)
    for label, frame in (("before", before_pixels), ("after", pixels)):
        dock_band = frame[band_start:]
        visible_dock_pixels = sum(1 for i in range(0, len(dock_band), 3)
                                  if max(dock_band[i:i + 3]) > 50)
        if visible_dock_pixels < minimum_dock_pixels:
            raise SystemExit(
                f"ShreeOS dock is missing from the bottom of the {label} "
                f"desktop screenshot: {path}"
            )
print(f"{profile} screenshot contains visible content ({width}x{height}).")
PY
  fi
  echo "${mode} live boot reached multi-user.target."
}

run_boot_test bios
run_boot_test uefi
echo "Prototype ISO validation passed."
