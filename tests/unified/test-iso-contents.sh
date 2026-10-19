#!/usr/bin/env bash
set -Eeuo pipefail
if [ "$#" -ne 1 ] || [ ! -s "$1" ]; then
  echo "Usage: test-iso-contents.sh shreeos(VERSION).iso" >&2
  exit 2
fi
iso="$(realpath "$1")"
root="$(cd "$(dirname "$0")/../.." && pwd -P)"
out="$root/out"
version="$(tr -d '[:space:]' < "$root/VERSION")"
iso_name="shreeos(${version}).iso"
[[ "$(basename "$iso")" == "$iso_name" ]]
test -s "$out/$iso_name.sha256"
(cd "$out" && sha256sum -c "$iso_name.sha256")
test "$(stat -c '%s' "$iso")" -lt 1900000000
grep -Eq '^shreeos-native-tools[[:space:]]' "$out/shreeos(${version})-packages.txt"
grep -Fxq 'edition=unified' "$out/shreeos(${version})-build-info.txt"
tmp="$(mktemp -d)"
trap 'rm -rf -- "$tmp"' EXIT
xorriso -osirrox on -indev "$iso" -extract /live/filesystem.squashfs "$tmp/root.squashfs" >/dev/null
paths="$(unsquashfs -ll "$tmp/root.squashfs")"
for item in \
  etc/shreeos/unified-image \
  usr/bin/shreeinfo \
  usr/bin/shreeos-sysmon \
  usr/bin/shreedctl \
  usr/libexec/shreeos/shreed \
  usr/lib/systemd/system/shreeos-hardware.service \
  etc/calamares/modules/partition.conf \
  etc/calamares/modules/bootloader.conf \
  etc/calamares/modules/shellprocess.conf \
  usr/local/libexec/shreeos-install-bios-grub \
  usr/bin/shreeos-native-status \
  usr/share/applications/shreeos-native-monitor.desktop \
  usr/share/doc/shreeos-native-tools/lpm/src/main.c \
  usr/share/doc/shreeos-native-tools/lpm/spec/lpkg-format.md; do
  grep -Fq "squashfs-root/$item" <<< "$paths" || {
    echo "Unified ISO missing: $item" >&2
    exit 1
  }
done
unsquashfs -cat "$tmp/root.squashfs" etc/os-release | grep -Fxq "VERSION_ID=\"${version%%-*}\""
unsquashfs -cat "$tmp/root.squashfs" etc/shreeos/unified-image | grep -Fxq 'edition=unified'
if grep -Fq 'squashfs-root/usr/bin/lpm' <<< "$paths"; then
  echo 'LPM must not be installed as an active system package manager' >&2
  exit 1
fi
echo 'Unified ISO contents and checksum validated.'
