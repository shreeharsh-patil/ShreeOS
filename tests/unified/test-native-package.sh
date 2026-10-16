#!/usr/bin/env bash
set -Eeuo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd -P)"
version="$(tr -d '[:space:]' < "$root/VERSION")"
dir="$(mktemp -d)"
trap 'rm -rf -- "$dir"' EXIT
bash -n "$root/scripts/shreeinfo" "$root/scripts/shreeos-native-status" \
  "$root/scripts/package-unified-native.sh" "$root/desktop/apps/shree-sysmon.sh" \
  "$root/scripts/build-debian-prototype.sh"
bash "$root/scripts/package-unified-native.sh" "$dir/out"
deb="$dir/out/shreeos-native-tools_${version}_amd64.deb"
test -s "$deb"
test "$(dpkg-deb --field "$deb" Package)" = shreeos-native-tools
test "$(dpkg-deb --field "$deb" Version)" = "$version"
test "$(dpkg-deb --field "$deb" Architecture)" = amd64
dpkg-deb --field "$deb" Depends | grep -Fq "shreeos-tools (= $version)"
dpkg-deb -x "$deb" "$dir/extracted"
dpkg-deb -e "$deb" "$dir/control"
test ! -e "$dir/extracted/usr/bin/shreeinfo"
test -x "$dir/extracted/usr/bin/shreeos-sysmon"
test -x "$dir/extracted/usr/bin/shreeos-native-status"
test -x "$dir/extracted/usr/bin/shreeos-verify-installed"
test -x "$dir/extracted/usr/bin/shreedctl"
test -x "$dir/extracted/usr/libexec/shreeos/shreed"
test -f "$dir/extracted/usr/lib/systemd/system/shreeos-hardware.service"
test -f "$dir/extracted/usr/lib/systemd/system-preset/60-shreeos-native.preset"
grep -Fq 'addgroup --system --quiet shree-hardware' "$dir/control/postinst"
"$dir/extracted/usr/libexec/shreeos/shreed" --unknown >/dev/null 2>&1 && {
  echo "Native daemon accepted invalid argument" >&2; exit 1;
}
test -f "$dir/extracted/usr/share/doc/shreeos-native-tools/lpm/src/main.c"
test -f "$dir/extracted/usr/share/doc/shreeos-native-tools/lpm/spec/lpkg-format.md"
test -f "$dir/extracted/usr/share/applications/shreeos-native-monitor.desktop"
test ! -e "$dir/extracted/usr/bin/lpm"
test ! -e "$dir/extracted/sbin/init"
test ! -e "$dir/extracted/bin/sh"
if grep -R -l '^Exec=.*lpm' "$dir/extracted/usr/share/applications"; then
  echo 'Native app must not use incompatible LPM package operations' >&2
  exit 1
fi
"$dir/extracted/usr/bin/shreeos-native-status" status | grep -Fq system_package_manager
echo 'Native integration Debian package validation passed.'
