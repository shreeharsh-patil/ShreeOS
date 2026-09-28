#!/usr/bin/env bash
# 42-iproute2.sh — Build iproute2 (ip, ss, tc, bridge)
#
# iproute2 has no configure; its Makefile is driven by environment variables
# and pkg-config probes for libmnl and libelf, both staged by now.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

PKG_NAME="iproute2"
PKG_VER="$(pkg_version "$PKG_NAME")"
ARCHIVE="$(pkg_archive "$PKG_NAME")"
SRCDIR="$(base_pkg_extract "$PKG_NAME")"
BUILDDIR="$(pkg_builddir "$PKG_NAME")"

lumen_step "Building ${PKG_NAME}-${PKG_VER}"

for lib in libmnl libelf; do
  pkg-config --exists "$lib" || \
    lumen_die "Target ${lib} pkg-config metadata is missing from the ShreeOS sysroot"
done

rm -rf "$BUILDDIR"
cp -a "$SRCDIR" "$BUILDDIR"
cd "$BUILDDIR"

# Keep the feature set to what a desktop and the installer need and avoid
# optional libraries that would silently link from the host.
cat > Config <<'EOF'
TC_CONFIG_XT=n
TC_CONFIG_ATM=n
TC_CONFIG_IPSET=n
IP_CONFIG_SETNS=y
HAVE_MNL=y
HAVE_ELF=y
HAVE_LIBBPF=n
HAVE_LIBBFD=n
HAVE_CAP=n
EOF

make -j"${LUMEN_MAKE_JOBS}" \
  CC="${CC}" \
  HOSTCC=gcc \
  AR="${AR}" \
  LD="${LD}"

make DESTDIR="${LUMEN_STAGE_ROOT}" \
  PREFIX=/usr \
  SBINDIR=/usr/sbin \
  CONF_USR_DIR=/usr/share/iproute2 \
  install

for tool in ip ss tc bridge; do
  [ -e "${LUMEN_STAGE_ROOT}/usr/sbin/${tool}" ] || \
    [ -e "${LUMEN_STAGE_ROOT}/usr/bin/${tool}" ] || \
    lumen_die "iproute2 tool missing after install: ${tool}"
done

lumen_ok "${PKG_NAME}-${PKG_VER} built successfully"
