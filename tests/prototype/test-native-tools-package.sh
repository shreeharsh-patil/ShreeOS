#!/usr/bin/env bash
set -Eeuo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
TEMP_DIR="$(mktemp -d)"
trap 'rm -rf -- "$TEMP_DIR"' EXIT

bash "$REPO_ROOT/scripts/build-shreeos-tools-package.sh" "$TEMP_DIR"
version="$(tr -d '[:space:]' < "$REPO_ROOT/VERSION")"
package="$TEMP_DIR/shreeos-tools_${version}_all.deb"
test -s "$package"
[[ "$(dpkg-deb -f "$package" Package)" == shreeos-tools ]]
[[ "$(dpkg-deb -f "$package" Version)" == "$version" ]]
[[ "$(dpkg-deb -f "$package" Architecture)" == all ]]
dependencies="$(dpkg-deb -f "$package" Depends)"
for dependency in apt iproute2 systemd util-linux; do
  grep -Eq "(^|, )${dependency}([, ]|$)" <<<"$dependencies"
done

dpkg-deb -x "$package" "$TEMP_DIR/extracted"
for path in \
  usr/bin/shreeinfo \
  usr/bin/shree-doctor \
  usr/bin/shree-netdiag \
  usr/bin/shree-audit \
  usr/share/applications/shreeinfo.desktop \
  usr/share/applications/shree-doctor.desktop \
  usr/share/applications/shree-netdiag.desktop \
  usr/share/applications/shree-audit.desktop; do
  test -s "$TEMP_DIR/extracted/$path"
done
grep -Fq 'Exec=shreeinfo' "$TEMP_DIR/extracted/usr/share/applications/shreeinfo.desktop"
grep -Fq 'Exec=shree-doctor' "$TEMP_DIR/extracted/usr/share/applications/shree-doctor.desktop"
grep -Fq 'Exec=shree-netdiag' "$TEMP_DIR/extracted/usr/share/applications/shree-netdiag.desktop"
grep -Fq 'Exec=shree-audit' "$TEMP_DIR/extracted/usr/share/applications/shree-audit.desktop"
for executable in shreeinfo shree-doctor shree-netdiag shree-audit; do
  [[ "$(stat -c '%a' "$TEMP_DIR/extracted/usr/bin/$executable")" == 755 ]]
done
if grep -R -E 'lpm|/var/lib/lpm|/run/init.sock|wpa_supplicant' \
  "$TEMP_DIR/extracted/usr/bin"; then
  echo 'Debian ShreeOS tools contain a native init or package-manager dependency.' >&2
  exit 1
fi
printf 'Versioned ShreeOS Debian tools package passed.\n'
