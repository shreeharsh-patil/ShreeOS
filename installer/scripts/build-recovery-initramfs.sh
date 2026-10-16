#!/usr/bin/env bash
# Build a replacement native ShreeOS initramfs without copying user data.
set -Eeuo pipefail

usage() {
  echo "Usage: build-recovery-initramfs.sh ROOT_DIR OUTPUT_CPIO_GZ" >&2
  exit 2
}

[ "$#" -eq 2 ] || usage
root_dir="$1"
output="$2"
[ -d "$root_dir" ] || { echo "Root filesystem is missing: $root_dir" >&2; exit 1; }
output_dir="$(dirname -- "$output")"
[ -d "$output_dir" ] && [ -w "$output_dir" ] || {
  echo "Output directory is missing or not writable: $output_dir" >&2
  exit 1
}

tmp="$(mktemp "${output}.tmp.XXXXXX")"
list_tmp="$(mktemp "${output}.list.XXXXXX")"
cleanup() { rm -f -- "$tmp" "$list_tmp"; }
trap cleanup EXIT

# Keep the mount-point directories themselves, but never pack their contents.
# /home and /root are excluded so this recovery action cannot copy personal
# files or SSH keys into /boot. -xdev also prevents traversing mounted volumes.
(
  cd -- "$root_dir"
  find . -xdev -mindepth 1 \
    \( -path './proc/*' -o -path './sys/*' -o -path './dev/*' \
       -o -path './run/*' -o -path './tmp/*' -o -path './boot/*' \
       -o -path './mnt/*' -o -path './media/*' \
       -o -path './home/*' -o -path './root/*' \) -prune -o -print0 |
    cpio --null -H newc -o --owner=0:0 --quiet |
    gzip -9 -c
) > "$tmp"

gzip -t -- "$tmp"
gzip -dc -- "$tmp" | cpio --list --quiet > "$list_tmp"
grep -Eq '^\./init$|^init$' "$list_tmp" || {
  echo "Rebuilt initramfs does not contain /init; existing archive was preserved." >&2
  exit 1
}

# The archive contains the installed system configuration. Keep it readable
# only by root on the installed machine, as the original archive is.
chmod 0600 -- "$tmp"
mv -f -- "$tmp" "$output"
trap - EXIT
rm -f -- "$list_tmp"
printf 'Wrote protected initramfs: %s (%s bytes)\n' "$output" "$(stat -c '%s' -- "$output")"
