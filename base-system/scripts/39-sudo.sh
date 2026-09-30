#!/usr/bin/env bash
# 39-sudo.sh — Build sudo (privileged command execution)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

PKG_NAME="sudo"
PKG_VER="$(pkg_version "$PKG_NAME")"
ARCHIVE="$(pkg_archive "$PKG_NAME")"
SRCDIR="$(base_pkg_extract "$PKG_NAME")"
BUILDDIR="$(pkg_builddir "$PKG_NAME")"

lumen_step "Building ${PKG_NAME}-${PKG_VER}"

mkdir -p "$BUILDDIR" && cd "$BUILDDIR"

"${SRCDIR}/configure" \
  --prefix=/usr \
  --build="$(gcc -dumpmachine)" \
  --host="${LUMEN_TARGET_TRIPLET}" \
  --target="${LUMEN_TARGET_TRIPLET}" \
  --sysconfdir=/etc \
  --with-pam \
  --without-kerb5 \
  --without-sssd \
  --disable-nls \
  --disable-static-sudoers \
  --enable-zlib

make -j"${LUMEN_MAKE_JOBS}"
# Every sudo Makefile.in hardcodes install_uid=0/install_gid=0 and passes
# them through INSTALL_OWNER="-o 0 -g 0" to its install-sh, which runs chown
# on every staged file. The base build is unprivileged (CI and dev machines
# alike), so that chown aborts the install -- the 2026-09-29 CI failure at
# 39/51. There is no configure knob (configure.ac only exposes
# --with-sudoers-uid/-gid for the sudoers file, not the install owner), so
# the make variables are overridden on the command line instead. Ownership
# is not lost: make-rootfs.sh packs the whole stage with
# `cpio --owner=0:0`, so the shipped image is root-owned regardless, which is
# the same contract every other unprivileged recipe relies on.
make DESTDIR="${LUMEN_STAGE_ROOT}" install install_uid=0 install_gid=0 INSTALL_OWNER=

base_sync_sysroot

[ -e "${LUMEN_STAGE_ROOT}/usr/bin/sudo" ] || \
  lumen_die "Target sudo binary was not staged"
# sudo must carry its setuid bit to work for desktop users.
mode="$(stat -c '%a' "${LUMEN_STAGE_ROOT}/usr/bin/sudo")"
[ "$mode" = "4755" ] || \
  lumen_die "sudo was installed without mode 4755 (got $mode); privilege escalation would be broken"
# The sudoers policy plugin is dlopen(3)ed by sudo, not executed, so it only
# has to exist: libtool installs it with mode 0644 and no exec bit, and the
# kernel maps it PROT_EXEC on read permission alone. Gating this check on -x
# aborted an otherwise healthy install (the 2026-09-29 CI failure at 39/51:
# "sudoers policy plugin was not staged") even though the plugin was staged
# correctly; the setuid check above cannot catch a missing or unreadable
# plugin, so the existence gate stays as the fail-closed signal.
[ -e "${LUMEN_STAGE_ROOT}/usr/libexec/sudo/sudoers.so" ] || \
  [ -e "${LUMEN_STAGE_ROOT}/usr/lib/sudo/sudoers.so" ] || \
  lumen_die "sudoers policy plugin was not staged; sudo could not evaluate policy"

lumen_ok "${PKG_NAME}-${PKG_VER} built successfully"
