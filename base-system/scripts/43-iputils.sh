#!/usr/bin/env bash
# 43-iputils.sh — Build iputils (ping, tracepath)
#
# iputils 20250605 builds with meson. Only the setuid-free, cap-free tools a
# desktop user needs are enabled; ping uses ICMP sockets (ping_group_range)
# instead of raw sockets so it does not need file capabilities.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

lumen_require_cmd meson

PKG_NAME="iputils"
PKG_VER="$(pkg_version "$PKG_NAME")"
ARCHIVE="$(pkg_archive "$PKG_NAME")"
SRCDIR="$(base_pkg_extract "$PKG_NAME")"
BUILDDIR="$(pkg_builddir "$PKG_NAME")"

lumen_step "Building ${PKG_NAME}-${PKG_VER}"

CROSSFILE="${BUILDDIR}/cross.txt"
mkdir -p "$BUILDDIR"
cat > "$CROSSFILE" <<EOF
[binaries]
c = '${CC}'
cpp = '${CXX}'
ar = '${AR}'
strip = '${STRIP}'
pkg-config = 'pkg-config'

[host_machine]
system = 'linux'
cpu_family = 'x86_64'
cpu = 'x86_64'
endian = 'little'
EOF

meson setup "$BUILDDIR/build" "$SRCDIR" \
  --cross-file "$CROSSFILE" \
  --prefix=/usr \
  -DNO_SETCAP_OR_SUID=true \
  -DUSE_ROOTNO=false \
  -DUSE_CAP=false \
  -DUSE_IDN=false \
  -DBUILD_RARPD=false \
  -DBUILD_RDISC=false \
  -DBUILD_NINFOD=false \
  -DBUILD_MANS=false

meson compile -C "$BUILDDIR/build" -j"${LUMEN_MAKE_JOBS}"
DESTDIR="${LUMEN_STAGE_ROOT}" meson install -C "$BUILDDIR/build"

[ -e "${LUMEN_STAGE_ROOT}/usr/bin/ping" ] || \
  lumen_die "Target ping binary was not staged"

lumen_ok "${PKG_NAME}-${PKG_VER} built successfully"
