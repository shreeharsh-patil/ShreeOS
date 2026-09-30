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
for tool in xorriso unsquashfs qemu-system-x86_64 qemu-img timeout sha256sum; do
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
  grep -Eq "^${package}([[:space:]]|$)" "$TEST_DIR/packages.txt" || {
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
    libreoffice-writer atril ristretto galculator xarchiver xdg-user-dirs; do
    grep -Eq "^${package}([[:space:]]|$)" "$TEST_DIR/packages.txt" || {
      echo "Desktop ISO package manifest is missing: $package" >&2
      exit 1
    }
  done
fi

run_boot_test() {
  local mode="$1"
  local bios_arg=() log="$TEST_DIR/${mode}.log"
  local emulator_log="$TEST_DIR/${mode}-qemu.log"
  local monitor_socket="$TEST_DIR/${mode}-monitor.sock"
  local screen_dump="$TEST_DIR/${PROFILE}-${mode}-screen.ppm" status=0
  if [ "$mode" = uefi ]; then
    local firmware="${OVMF_CODE:-}"
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
    [ -s "$firmware" ] || { echo "UEFI firmware not found: $firmware" >&2; return 1; }
    bios_arg=(-bios "$firmware")
  fi

  timeout --signal=TERM 180s qemu-system-x86_64 \
    -machine q35 -m 2048 -smp 2 -nic user,model=virtio-net-pci \
    -drive "file=$TARGET_DISK,format=raw,if=virtio" \
    -cdrom "$ISO" -boot order=d \
    -display none -monitor "unix:$monitor_socket,server,nowait" \
    -serial "file:$log" -no-reboot "${bios_arg[@]}" >"$emulator_log" 2>&1 &
  local emulator_pid=$!
  sleep 20
  if ! grep -Fq 'SHREEOS_LIVE_BOOT_OK' "$log" 2>/dev/null; then
    if python3 - "$monitor_socket" "$screen_dump" <<'PY'
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
    raise SystemExit("QEMU monitor socket did not become available")
client.recv(4096)
client.sendall(f"screendump {output}\n".encode())
client.recv(4096)
client.sendall(b"sendkey home\n")
client.recv(4096)
client.sendall(b"sendkey ret\n")
client.recv(4096)
client.close()
PY
    then
      :
    else
      printf 'QEMU screen capture was unavailable.\n' >>"$emulator_log"
    fi
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
  fi

  if ! grep -Fq 'SHREEOS_LIVE_BOOT_OK' "$log" 2>/dev/null; then
    echo "${mode} boot did not reach the ShreeOS multi-user marker (qemu exit $status)." >&2
    [ ! -f "$log" ] || cat "$log" >&2
    [ ! -s "$emulator_log" ] || cat "$emulator_log" >&2
    return 1
  fi
  echo "${mode} live boot reached multi-user.target."
}

run_boot_test bios
run_boot_test uefi
echo "Prototype ISO validation passed."
