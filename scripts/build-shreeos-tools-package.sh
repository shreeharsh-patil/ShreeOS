#!/usr/bin/env bash
set -Eeuo pipefail

if [ "$#" -ne 1 ]; then
  echo "Usage: $0 DIRECTORY_FOR_DEBIAN_PACKAGES" >&2
  exit 2
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)"
SOURCE_DIR="$REPO_ROOT/prototype/debian-live/features/native-tools"
VERSION="$(tr -d '[:space:]' < "$REPO_ROOT/VERSION")"
OUTPUT_DIR="$(mkdir -p "$1" && cd "$1" && pwd -P)"

[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z][0-9A-Za-z.-]*)?$ ]] || {
  echo "Invalid ShreeOS package version: $VERSION" >&2
  exit 1
}
command -v dpkg-deb >/dev/null 2>&1 || {
  echo 'Missing package build dependency: dpkg-deb' >&2
  exit 2
}
for file in control.in shreeinfo shree-doctor shree-netdiag shree-audit \
  shreeinfo.desktop shree-doctor.desktop shree-netdiag.desktop shree-audit.desktop; do
  [ -s "$SOURCE_DIR/$file" ] || { echo "Missing ShreeOS package source: $file" >&2; exit 1; }
done

temporary="$(mktemp -d "${TMPDIR:-/tmp}/shreeos-tools.XXXXXX")"
trap 'rm -rf -- "$temporary"' EXIT
package_root="$temporary/package"
mkdir -p "$package_root/DEBIAN" "$package_root/usr/bin" "$package_root/usr/share/applications"
sed "s/@VERSION@/$VERSION/g" "$SOURCE_DIR/control.in" > "$package_root/DEBIAN/control"
install -m 0755 "$SOURCE_DIR/shreeinfo" "$package_root/usr/bin/shreeinfo"
install -m 0755 "$SOURCE_DIR/shree-doctor" "$package_root/usr/bin/shree-doctor"
install -m 0755 "$SOURCE_DIR/shree-netdiag" "$package_root/usr/bin/shree-netdiag"
install -m 0755 "$SOURCE_DIR/shree-audit" "$package_root/usr/bin/shree-audit"
for app in shreeinfo shree-doctor shree-netdiag shree-audit; do
  install -m 0644 "$SOURCE_DIR/$app.desktop" "$package_root/usr/share/applications/$app.desktop"
done

output="$OUTPUT_DIR/shreeos-tools_${VERSION}_all.deb"
rm -f -- "$output"
dpkg-deb --build --root-owner-group "$package_root" "$output" >/dev/null
dpkg-deb --info "$output" >/dev/null
printf 'Built %s\n' "$output"
