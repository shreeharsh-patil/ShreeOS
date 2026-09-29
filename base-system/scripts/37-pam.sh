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
#
# `db` is not a feature option: it is a combo with choices db/gdbm/ndbm/auto
# (meson_options.txt:91-92), so passing it "disabled" is not merely ignored --
# meson validates every -D value during setup, before any build logic runs,
# and aborts the whole package (the 2026-09-29 CI failure at 37/51,
#   ERROR: Value "disabled" (of type "string") for option "db" is not one of
#   the choices. Possible choices are (as string): "db", "gdbm", "ndbm", "auto".
# ). pam_userdb is the only consumer of the db backend (meson.build:336-398
# reads get_option('db') solely inside the not-disabled pam_userdb branch), so
# the deterministic contract is: disable pam_userdb explicitly, and leave db
# at auto, which upstream then never consults. Leaving pam_userdb at auto
# would let a host libdb/libgdbm leak into the cross build through meson's
# find_library probe.
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

# Upstream bug: libpam/meson.build:54 lists libintl in the shared_library
# dependencies unconditionally, but meson.build:214-215 only defines the
# variable when i18n is NOT disabled. With -Di18n=disabled -- our
# reproducibility requirement, same as every autoconf recipe here -- setup
# dies with `Unknown variable "libintl"`. Upstream never sees this because
# they always build with i18n enabled. The C side handles a non-NLS build
# correctly (libpam/include/pam_i18n.h falls back to an identity _() macro
# when ENABLE_NLS is undefined), so the source-level fix is dropping the one
# dangling reference. The staged tree under $BUILDDIR is a private copy, so
# editing it does not disturb the cached sources; the pattern is anchored so
# an upstream repair (defining or removing libintl) makes this sed a no-op.
sed -i 's/\(dependencies: \[[^]]*\), libintl\]/\1]/' \
  "${SRCDIR}/libpam/meson.build"
grep -q 'libintl' "${SRCDIR}/libpam/meson.build" && \
  lumen_die "libpam/meson.build still references libintl; the sed anchor no longer matches upstream 1.7.0"

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
  -Dpam_userdb=disabled \
  -Ddb=auto \
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
