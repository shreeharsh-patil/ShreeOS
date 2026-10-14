#!/usr/bin/env bash
set -Eeuo pipefail
if [ "$#" -ne 1 ] || [ ! -s "$1" ]; then
  echo "Usage: test-iso-contents.sh ShreeOS-0.4.0-amd64.iso" >&2
  exit 2
fi
iso="$(realpath "$1")"
root="$(cd "$(dirname "$0")/../.." && pwd -P)"
out="$root/out"
test -s "$out/ShreeOS-0.4.0-amd64.iso.sha256"
(cd "$out" && sha256sum -c ShreeOS-0.4.0-amd64.iso.sha256)
grep -Eq '^shreeos-native-tools[[:space:]]' "$out/ShreeOS-0.4.0-packages.txt"
grep -Fxq 'edition=unified' "$out/ShreeOS-0.4.0-build-info.txt"
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
  lib/systemd/system/shreeos-hardware.service \
  usr/bin/shreeos-native-status \
  usr/share/applications/shreeos-native-monitor.desktop \
  usr/share/doc/shreeos-native-tools/lpm/src/main.c \
  usr/share/doc/shreeos-native-tools/lpm/spec/lpkg-format.md; do
  grep -Fq "squashfs-root/$item" <<< "$paths" || {
    echo "Unified ISO missing: $item" >&2
    exit 1
  }
done
unsquashfs -cat "$tmp/root.squashfs" etc/os-release | grep -Fxq 'VERSION_ID="0.4.0"'
unsquashfs -cat "$tmp/root.squashfs" etc/shreeos/unified-image | grep -Fxq 'edition=unified'
if grep -Fq 'squashfs-root/usr/bin/lpm' <<< "$paths"; then
  echo 'LPM must not be installed as an active system package manager' >&2
  exit 1
fi
echo 'Unified ISO contents and checksum validated.'
