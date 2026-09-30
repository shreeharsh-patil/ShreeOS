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
  linux-image-amd64 network-manager sudo systemd-sysv; do
  grep -Fxq "$required" "$packages" || {
    echo "Prototype package list is missing: $required" >&2
    exit 1
  }
done

grep -Fq 'ID=shreeos' "$CONFIG_DIR/config/includes.chroot/etc/os-release"
grep -Fq 'ID_LIKE=debian' "$CONFIG_DIR/config/includes.chroot/etc/os-release"
grep -Fq 'SHREEOS_LIVE_BOOT_OK' \
  "$CONFIG_DIR/config/includes.chroot/etc/systemd/system/shreeos-boot-check.service"
printf 'Debian prototype configuration contract passed.\n'
