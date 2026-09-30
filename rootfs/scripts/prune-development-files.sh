#!/usr/bin/env bash
# Remove build-only inputs after all target packages have been assembled.
set -Eeuo pipefail

if [ "$#" -ne 1 ] || [ ! -d "$1" ]; then
  echo "Usage: prune-development-files.sh ROOTFS_DIRECTORY" >&2
  exit 2
fi

root="$(cd "$1" && pwd -P)"
if [ "$root" = "/" ] || [ "$root" = "$(pwd -P)" ]; then
  echo "Refusing to prune an unsafe rootfs path: $root" >&2
  exit 2
fi

# Static archives and libtool metadata are used while compiling, not when
# running programs. Drop them only from the final staged system, after the
# package and desktop builds have completed.
find "$root" -type f \( -name '*.a' -o -name '*.la' \) -delete
find "$root" -type l \( -name '*.a' -o -name '*.la' \) -delete

# Development headers and build-system metadata have no runtime role. Keep
# shared libraries, runtime data, fonts, locales and manual pages intact.
for rel in \
  include \
  usr/include \
  usr/local/include \
  usr/share/aclocal \
  usr/share/pkgconfig \
  usr/lib/pkgconfig \
  usr/lib64/pkgconfig \
  usr/lib/cmake \
  usr/lib64/cmake \
  usr/share/doc \
  usr/share/info
do
  path="$root/$rel"
  if [ -d "$path" ] && [ ! -L "$path" ]; then
    rm -rf -- "$path"
  fi
done

required='usr/bin/bash'
[ -e "$root/$required" ] || {
  echo "Runtime content missing after development-file pruning: /$required" >&2
  exit 1
}

echo "Removed build-only headers, archives and metadata from $root"
