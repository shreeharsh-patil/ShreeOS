#!/usr/bin/env bash
set -Eeuo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd -P)"
live="$root/prototype/debian-live/config/includes.chroot/usr/local/sbin/shreeos-live-boot-check"
sddm="$root/prototype/debian-live/profiles/plasma/includes.chroot/usr/local/sbin/shreeos-sddm-live-autologin"
verify="$root/scripts/shreeos-verify-installed"
grep -Fq 'if [ ! -e /run/live/medium ]; then' "$live"
grep -Fq 'rm -f "$override"' "$sddm"
grep -Fq '/boot/grub/grub.cfg' "$verify"
grep -Fq 'SHREEOS_INSTALLED_OK' "$verify"
bash -n "$verify"
sh -n "$live" "$sddm"
echo 'Live-to-installed integration checks passed.'
