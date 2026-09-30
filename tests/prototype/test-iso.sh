#!/usr/bin/env bash
set -Eeuo pipefail

if [ "$#" -ne 1 ] || [ ! -s "$1" ]; then
  echo "Usage: test-iso.sh PATH_TO_PROTOTYPE_ISO" >&2
  exit 2
fi
ISO="$(realpath "$1")"
for tool in xorriso unsquashfs qemu-system-x86_64 timeout sha256sum; do
  command -v "$tool" >/dev/null 2>&1 || {
    echo "Missing ISO test dependency: $tool" >&2
    exit 2
  }
done

TEST_DIR="$(mktemp -d)"
trap 'rm -rf -- "$TEST_DIR"' EXIT
SQUASHFS="$TEST_DIR/filesystem.squashfs"
xorriso -osirrox on -indev "$ISO" -extract /live/filesystem.squashfs "$SQUASHFS" >/dev/null
unsquashfs -s "$SQUASHFS" >/dev/null
xorriso -osirrox on -indev "$ISO" -extract /live/filesystem.packages "$TEST_DIR/packages.txt" >/dev/null
for package in apt live-boot live-config-systemd network-manager systemd-sysv; do
  grep -Eq "^${package}([[:space:]]|$)" "$TEST_DIR/packages.txt" || {
    echo "ISO package manifest is missing required package: $package" >&2
    exit 1
  }
done

run_boot_test() {
  local mode="$1" bios_arg=() log="$TEST_DIR/${mode}.log" status=0
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
    -machine q35 -m 2048 -smp 2 -cdrom "$ISO" -boot order=d \
    -display none -monitor none -serial "file:$log" -no-reboot \
    "${bios_arg[@]}" >/dev/null 2>&1 || status=$?

  if ! grep -Fq 'SHREEOS_LIVE_BOOT_OK' "$log" 2>/dev/null; then
    echo "${mode} boot did not reach the ShreeOS multi-user marker (qemu exit $status)." >&2
    [ ! -f "$log" ] || cat "$log" >&2
    return 1
  fi
  echo "${mode} live boot reached multi-user.target."
}

run_boot_test bios
run_boot_test uefi
echo "Prototype ISO validation passed."
