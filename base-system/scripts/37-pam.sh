#!/usr/bin/env bash
# 37-pam.sh — Build Linux-PAM (pluggable authentication modules)
#
# Linux-PAM 1.7 builds with meson; the configure-looking helper in the tarball
# is a wrapper. Cross compilation goes through meson with a target cross file
# generated from the toolchain variables common.sh exports.
#
# The option names below are taken verbatim from the v1.7.0 meson_options.txt.
# They are easy to get wrong (`pamlocking`, not `pam locking`; `docs`, not
# `doc`; and there is no `tests` option at all), and meson rejects an unknown
# option outright, so they are spelled out here rather than abbreviated.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

lumen_require_cmd meson

PKG_NAME="pam"
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
  --sysconfdir=/etc \
  --localstatedir=/var \
  -Dexamples=false \
  -Dxtests=false \
  -Ddocs=disabled \
  -Di18n=disabled \
  -Dpamlocking=false \
  -Dselinux=disabled \
  -Deconf=disabled \
  -Dnis=disabled \
  -Ddb=disabled \
  -Dopenssl=disabled \
  -Daudit=disabled \
  -Dlogind=disabled \
  -Dsconfigdir=/etc/security \
  -Dmailspool=/var/mail \
  -Drandomdev=/dev/urandom

meson compile -C "$BUILDDIR/build" -j"${LUMEN_MAKE_JOBS}"
DESTDIR="${LUMEN_STAGE_ROOT}" meson install -C "$BUILDDIR/build"

base_sync_sysroot

compgen -G "${LUMEN_STAGE_ROOT}/usr/lib/libpam.so*" >/dev/null || \
  lumen_die "Target libpam shared library was not staged"
[ -f "${LUMEN_STAGE_ROOT}/etc/pam.d/other" ] || \
  lumen_die "Linux-PAM default policy (/etc/pam.d/other) was not staged"

lumen_ok "${PKG_NAME}-${PKG_VER} built successfully"
