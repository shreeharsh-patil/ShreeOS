#!/usr/bin/env bash
# 41-elfutils.sh — Build elfutils (libelf/libdw, required by iproute2 and perf)
#
# Only the libraries are installed on the target; the tools are not needed
# and pull in extra dependencies. libdw's ELF compression support is left off
# because it drags zlib/bz2/lzma into the link for marginal benefit here.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

PKG_NAME="elfutils"
PKG_VER="$(pkg_version "$PKG_NAME")"
ARCHIVE="$(pkg_archive "$PKG_NAME")"
SRCDIR="$(base_pkg_extract "$PKG_NAME")"
BUILDDIR="$(pkg_builddir "$PKG_NAME")"

lumen_step "Building ${PKG_NAME}-${PKG_VER}"

# configure probes for a host bzlib/xz/zstd when cross-compiling; the target
# libraries are staged by now but keeping the feature off keeps the link
# surface minimal and avoids host leakage through libtool.
mkdir -p "$BUILDDIR" && cd "$BUILDDIR"

"${SRCDIR}/configure" \
  --prefix=/usr \
  --build="$(gcc -dumpmachine)" \
  --host="${LUMEN_TARGET_TRIPLET}" \
  --target="${LUMEN_TARGET_TRIPLET}" \
  --disable-debuginfod \
  --enable-libdebuginfod=dummy \
  --disable-demo \
  --disable-progs

# elfutils wires its libraries together through sibling noinst archives, and
# none of those live in the subdirectory being built: libelf.so links
# ../lib/libeu.a, and libdw.so additionally links ../libebl/libebl_pic.a,
# ../backends/libebl_backends_pic.a, ../libcpu/libcpu_pic.a,
# ../libdwelf/libdwelf_pic.a and ../libdwfl/libdwfl_pic.a. A bare
# `make -C libelf` cannot recurse into ../lib and dies with "No rule to make
# target '../lib/libeu.a'" (the 2026-09-30 CI failure at 41/51), and libdw
# would fail the same way one level deeper. Build the directories in the
# dependency order below, mirroring upstream's top-level SUBDIRS order;
# skipping the tool subdirs (src/, libasm/) keeps host-run generators out of
# the cross build. The *_pic.a archives are part of each directory's default
# target, so one pass per directory is enough.
make -j"${LUMEN_MAKE_JOBS}" -C lib
make -j"${LUMEN_MAKE_JOBS}" -C libelf
make -j"${LUMEN_MAKE_JOBS}" -C libebl
make -j"${LUMEN_MAKE_JOBS}" -C backends
make -j"${LUMEN_MAKE_JOBS}" -C libcpu
make -j"${LUMEN_MAKE_JOBS}" -C libdwelf
make -j"${LUMEN_MAKE_JOBS}" -C libdwfl
make -j"${LUMEN_MAKE_JOBS}" -C libdw
make -C libelf install DESTDIR="${LUMEN_STAGE_ROOT}"
make -C libdw install DESTDIR="${LUMEN_STAGE_ROOT}"

# libelf.pc and libdw.pc are generated and installed from config/, not from
# the library directories, and the top-level install is deliberately not used
# here. Stage the two files directly: the 42-iproute2 recipe gates its build
# on `pkg-config --exists libelf`, so this metadata is load-bearing, while
# config/'s full install rule would also copy the debuginfod profile scripts
# into /etc under LIBDEBUGINFOD (which --enable-libdebuginfod=dummy leaves
# defined).
install -d "${LUMEN_STAGE_ROOT}/usr/lib/pkgconfig"
install -m 0644 config/libelf.pc config/libdw.pc \
  "${LUMEN_STAGE_ROOT}/usr/lib/pkgconfig/"

base_sync_sysroot

compgen -G "${LUMEN_STAGE_ROOT}/usr/lib/libelf.so*" >/dev/null || \
  lumen_die "Target libelf shared library was not staged"
compgen -G "${LUMEN_STAGE_ROOT}/usr/lib/libdw.so*" >/dev/null || \
  lumen_die "Target libdw shared library was not staged"

lumen_ok "${PKG_NAME}-${PKG_VER} built successfully"
