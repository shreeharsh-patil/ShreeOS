#!/usr/bin/env bash
set -Eeuo pipefail

if [ "$#" -lt 1 ] || [ "$#" -gt 2 ] || [ ! -s "$1" ]; then
  echo "Usage: test-iso.sh PATH_TO_PROTOTYPE_ISO [base|desktop]" >&2
  exit 2
fi
ISO="$(realpath "$1")"
PROFILE="${2:-base}"
case "$PROFILE" in
  base|desktop) ;;
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
for package in apt live-boot live-config-systemd network-manager systemd-sysv; do
  grep -Eq "^${package}(:[^[:space:]]+)?([[:space:]]|$)" "$TEST_DIR/packages.txt" || {
    echo "ISO package manifest is missing required package: $package" >&2
    exit 1
  }
done
if [ "$PROFILE" = desktop ]; then
  for package in arc-theme bluez blueman brightness-udev brightnessctl dconf-cli firefox-esr fonts-inter lightdm \
    papirus-icon-theme pipewire-audio \
    python3-gi wmctrl lightdm-gtk-greeter network-manager-applet task-xfce-desktop \
    xfce4-appfinder xfce4-notifyd xfce4-power-manager \
    xfce4-pulseaudio-plugin xfce4-screenshooter mousepad synaptic parole \
    xfce4-screensaver libnotify-bin \
    libreoffice-writer atril ristretto galculator xarchiver xdg-user-dirs \
    calamares calamares-settings-debian pkexec onboard orca \
    speech-dispatcher-espeak-ng librsvg2-common plymouth plymouth-themes; do
    grep -Eq "^${package}(:[^[:space:]]+)?([[:space:]]|$)" "$TEST_DIR/packages.txt" || {
      echo "Desktop ISO package manifest is missing: $package" >&2
      exit 1
    }
  done
fi

run_boot_test() {
  local mode="$1"
  local firmware_args=() log="$TEST_DIR/${mode}.log"
  local emulator_log="$TEST_DIR/${mode}-qemu.log"
  local monitor_socket="$TEST_DIR/${mode}-monitor.sock"
  local screen_dump="$TEST_DIR/${PROFILE}-${mode}-screen.ppm"
  local menu_dump="$TEST_DIR/${PROFILE}-${mode}-menu.ppm" status=0
  local splash_dump="$TEST_DIR/${PROFILE}-${mode}-splash.ppm"
  local deadline=$((SECONDS + 300))
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

  xvfb-run -a -s "-screen 0 1280x800x24" timeout --signal=TERM 300s qemu-system-x86_64 \
    -machine q35 -m 2048 -smp 2 -vga virtio -nic user,model=virtio-net-pci \
    -drive "file=$TARGET_DISK,format=raw,if=virtio" \
    -cdrom "$ISO" -boot order=d \
    -display gtk -monitor "unix:$monitor_socket,server,nowait" \
    -serial "file:$log" -no-reboot "${firmware_args[@]}" >"$emulator_log" 2>&1 &
  local emulator_pid=$!
  sleep 20
  if ! grep -Fq 'SHREEOS_LIVE_BOOT_OK' "$log" 2>/dev/null; then
    if python3 - "$monitor_socket" "$menu_dump" "$splash_dump" <<'PY'
import socket
import sys
import time

monitor, output, splash = sys.argv[1:]
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
client.recv(4096)
client.sendall(f"screendump {output}\n".encode())
client.recv(4096)
client.sendall(b"sendkey home\n")
client.recv(4096)
client.sendall(b"sendkey ret\n")
client.recv(4096)
time.sleep(3)
client.sendall(f"screendump {splash}\n".encode())
client.recv(4096)
client.close()
PY
    then
      :
    else
      printf 'QEMU screen capture was unavailable.\n' >>"$emulator_log"
    fi
  fi

  while ! grep -Fq 'SHREEOS_LIVE_BOOT_OK' "$log" 2>/dev/null; do
    if ! kill -0 "$emulator_pid" 2>/dev/null || (( SECONDS >= deadline )); then
      break
    fi
    sleep 1
  done
  if grep -Fq 'SHREEOS_LIVE_BOOT_OK' "$log" 2>/dev/null; then
    python3 - "$monitor_socket" "$screen_dump" <<'PY'
import socket
import sys
import time

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
client.recv(4096)
client.sendall(b"sendkey shift\n")
client.recv(4096)
time.sleep(10)
client.sendall(f"screendump {output}\n".encode())
client.recv(4096)
client.sendall(b"quit\n")
client.close()
PY
  fi
  wait "$emulator_pid" || status=$?

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
    if [ -s "$menu_dump" ]; then
      cp -- "$menu_dump" "$QEMU_LOG_DIR/${PROFILE}-${mode}-menu.ppm"
    fi
    if [ -s "$splash_dump" ]; then
      cp -- "$splash_dump" "$QEMU_LOG_DIR/${PROFILE}-${mode}-splash.ppm"
    fi
  fi

  if ! grep -Fq 'SHREEOS_LIVE_BOOT_OK' "$log" 2>/dev/null; then
    echo "${mode} boot did not reach the ShreeOS multi-user marker (qemu exit $status)." >&2
    [ ! -f "$log" ] || cat "$log" >&2
    [ ! -s "$emulator_log" ] || cat "$emulator_log" >&2
    return 1
  fi
  if [ "$PROFILE" = desktop ]; then
    python3 - "$screen_dump" <<'PY'
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
data = path.read_bytes()
if not data.startswith(b"P6"):
    raise SystemExit(f"Desktop screenshot is not a binary PPM: {path}")
parts = data.split(maxsplit=4)
if len(parts) != 5:
    raise SystemExit(f"Desktop screenshot has an invalid PPM header: {path}")
width, height, maximum = map(int, parts[1:4])
pixels = parts[4]
if maximum != 255 or len(pixels) != width * height * 3:
    raise SystemExit(f"Desktop screenshot has invalid pixel data: {path}")
lit_pixels = sum(1 for i in range(0, len(pixels), 3)
                 if max(pixels[i:i + 3]) > 24)
if lit_pixels < width * height // 20:
    raise SystemExit(f"Desktop screenshot is blank or nearly blank: {path}")
desktop_top = 40
desktop_bottom = height - 64
desktop_pixels = pixels[desktop_top * width * 3:desktop_bottom * width * 3]
wallpaper_pixels = sum(1 for i in range(0, len(desktop_pixels), 3)
                       if max(desktop_pixels[i:i + 3]) > 8)
if wallpaper_pixels < width * (desktop_bottom - desktop_top) // 2:
    raise SystemExit(f"ShreeOS wallpaper is missing from the desktop area: {path}")
dock_pixels = pixels[(height - 64) * width * 3:]
visible_dock_pixels = sum(1 for i in range(0, len(dock_pixels), 3)
                          if max(dock_pixels[i:i + 3]) > 50)
if visible_dock_pixels < max(24, width * 64 // 300):
    raise SystemExit(f"ShreeOS dock is missing from the bottom of the desktop: {path}")
print(f"Desktop screenshot contains visible content ({width}x{height}).")
PY
  fi
  echo "${mode} live boot reached multi-user.target."
}

run_boot_test bios
run_boot_test uefi
echo "Prototype ISO validation passed."
