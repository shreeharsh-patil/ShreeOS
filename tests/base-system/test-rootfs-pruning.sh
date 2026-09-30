#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
ROOTFS_SCRIPT="$REPO_ROOT/rootfs/scripts/prune-development-files.sh"
fixture="$(mktemp -d)"
trap 'rm -rf -- "$fixture"' EXIT

mkdir -p "$fixture/usr/bin" "$fixture/usr/lib" \
  "$fixture/usr/include/example" "$fixture/usr/share/doc/example" \
  "$fixture/usr/share/fonts"
: > "$fixture/usr/bin/bash"
chmod 755 "$fixture/usr/bin/bash"
: > "$fixture/usr/lib/libc.so.6"
: > "$fixture/usr/lib/libexample.a"
: > "$fixture/usr/lib/libexample.la"
: > "$fixture/usr/include/example/header.h"
: > "$fixture/usr/share/doc/example/README"
: > "$fixture/usr/share/fonts/example.ttf"

bash "$ROOTFS_SCRIPT" "$fixture"

test -f "$fixture/usr/bin/bash"
test -e "$fixture/usr/lib/libc.so.6"
test -e "$fixture/usr/share/fonts/example.ttf"
test ! -e "$fixture/usr/lib/libexample.a"
test ! -e "$fixture/usr/lib/libexample.la"
test ! -e "$fixture/usr/include"
test ! -e "$fixture/usr/share/doc"
printf 'Rootfs development-file pruning test passed.\n'
