#!/usr/bin/env bash
# base-system/scripts/common.sh — shared helpers for base system build scripts
set -euo pipefail

BASE_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_ROOT_DIR="$(cd "$BASE_SCRIPT_DIR/../.." && pwd)"

if [ -f "$BASE_ROOT_DIR/build.conf" ]; then
  source "$BASE_ROOT_DIR/build.conf"
fi
if [ -f "$BASE_ROOT_DIR/scripts/common.sh" ]; then
  source "$BASE_ROOT_DIR/scripts/common.sh"
fi

# Base-system-specific directories
BASE_SOURCES="${LUMEN_BUILD_DIR}/sources"
BASE_BUILDDIR="${LUMEN_BUILD_DIR}/base-system"

export PATH="${LUMEN_TOOLS}/bin:${PATH}"
export CC="${LUMEN_TARGET_TRIPLET}-gcc"
export CXX="${LUMEN_TARGET_TRIPLET}-g++"
export AR="${LUMEN_TARGET_TRIPLET}-ar"
export AS="${LUMEN_TARGET_TRIPLET}-as"
export RANLIB="${LUMEN_TARGET_TRIPLET}-ranlib"
export LD="${LUMEN_TARGET_TRIPLET}-ld"
export PKG_CONFIG_SYSROOT_DIR="${LUMEN_SYSROOT}"
export PKG_CONFIG_LIBDIR="${LUMEN_SYSROOT}/usr/lib/pkgconfig:${LUMEN_SYSROOT}/usr/share/pkgconfig"
export PKG_CONFIG_PATH=""
export CPPFLAGS="--sysroot=${LUMEN_SYSROOT}"
export LDFLAGS="--sysroot=${LUMEN_SYSROOT}"
export STRIP="${LUMEN_TARGET_TRIPLET}-strip"

mkdir -p "$BASE_SOURCES" "$BASE_BUILDDIR"

# Look up package info from packages.list
# Usage: pkg_info <name> <field>  where field is 1=name, 2=version, 3=url, 4=sha256
pkg_info() {
  local name="$1"
  local field="$2"
  awk -v n="$name" -v f="$field" \
    '$1 == n { print $f; exit }' \
    "${BASE_ROOT_DIR}/base-system/packages.list"
}

pkg_url()    { pkg_info "$1" 3; }
pkg_sha256() { pkg_info "$1" 4; }
pkg_version(){ pkg_info "$1" 2; }

pkg_archive() {
  local name="$1"
  local url
  url=$(pkg_url "$name")
  basename "$url"
}

pkg_srcdir() {
  local name="$1"
  local ver
  ver=$(pkg_version "$name")
  echo "${BASE_SOURCES}/${name}-${ver}"
}

pkg_builddir() {
  local name="$1"
  echo "${BASE_BUILDDIR}/build-${name}"
}

# Upstream tarballs do not agree on their top-level directory name: GNU
# projects use "<name>-<version>", GitHub tag archives use "<repo>-<tag>"
# (e.g. systemd-258/ or popt-popt-1.19-release/), and a few use neither.
# Every build script needs the same thing from that directory, so resolve it
# in exactly one place instead of letting each script guess.
#
# Usage: srcdir="$(base_pkg_extract <package-name>)"
#
# The returned directory is always normalised to "${BASE_SOURCES}/<name>-<ver>"
# so pkg_srcdir() and the extracted tree agree for the rest of the build.
base_pkg_extract() {
  local name="$1"
  local url ver archive dest
  url="$(pkg_url "$name")"
  ver="$(pkg_version "$name")"
  archive="$(pkg_archive "$name")"
  dest="${BASE_SOURCES}/${archive}"

  if [ -z "$url" ] || [ -z "$ver" ]; then
    lumen_die "No packages.list entry for '${name}'"
  fi

  # stdout is this function's return value; force every byte to stderr.
  # lumen_fetch routes all of its own output to stderr, so the diagnostics
  # below cannot leak into the captured stdout either.
  lumen_fetch "$url" "$dest" "$(pkg_sha256 "$name")" >&2

  local target="${BASE_SOURCES}/${name}-${ver}"
  if [ -d "$target" ]; then
    printf '%s\n' "$target"
    return 0
  fi

  # Snapshot the directory listing so the newly created tree can be
  # identified without depending on the archive's internal path names.
  local before after created=""
  before="$(mktemp)"
  after="$(mktemp)"
  ls -1A "${BASE_SOURCES}" > "$before"

  local -a xflags=(-x -f)
  case "$archive" in
    *.tar.xz)  xflags=(-x -J -f) ;;
    *.tar.bz2) xflags=(-x -j -f) ;;
    *.tar.zst) xflags=(--zstd -x -f) ;;
  esac
  tar "${xflags[@]}" "$dest" -C "${BASE_SOURCES}"

  ls -1A "${BASE_SOURCES}" > "$after"
  while IFS= read -r entry; do
    [ -n "$entry" ] || continue
    if ! grep -Fxq -- "$entry" "$before" && [ -d "${BASE_SOURCES}/${entry}" ]; then
      if [ -n "$created" ]; then
        rm -f "$before" "$after"
        lumen_die "Archive ${archive} unpacked more than one top-level directory (${created} and ${entry})"
      fi
      created="$entry"
    fi
  done < "$after"
  rm -f "$before" "$after"

  if [ -z "$created" ]; then
    lumen_die "Archive ${archive} did not create a top-level source directory"
  fi
  if [ "$created" != "${name}-${ver}" ]; then
    # NOTE: this function's stdout *is* its return value (callers use
    # srcdir="$(base_pkg_extract <pkg>)"). Every diagnostic must therefore go
    # to stderr, or the message is captured into ${srcdir} and the build
    # directory becomes a log string. shreeos_log/shreeos_ok print to stdout,
    # so redirect explicitly -- do not "simplify" this away.
    shreeos_log "Normalizing source directory ${created} -> ${name}-${ver}" >&2
    mv -f "${BASE_SOURCES}/${created}" "$target"
  fi
  [ -d "$target" ] || lumen_die "Source directory missing after extraction: $target"
  printf '%s\n' "$target"
}

# Synchronize target development headers/libraries into the compiler sysroot.
# Base packages are installed into the target rootfs via DESTDIR, while later
# packages must link against those same target libraries through the sysroot.
base_sync_sysroot() {
  local subdir src dst libdir
  for subdir in include lib lib64; do
    src="${LUMEN_STAGE_ROOT}/usr/${subdir}"
    [ -d "$src" ] || continue
    dst="${LUMEN_SYSROOT}/usr/${subdir}"
    mkdir -p "$dst"
    cp -a "$src/." "$dst/"
  done

  # Libtool archives installed through DESTDIR retain absolute /usr/lib
  # dependency paths.  Reusing them from the cross sysroot can therefore make
  # later target packages search the host filesystem (alsa-utils is one such
  # consumer).  Shared objects and pkg-config files are the supported target
  # link metadata, so remove the non-runtime .la files from both copies.
  for libdir in \
    "${LUMEN_STAGE_ROOT}/usr/lib" "${LUMEN_STAGE_ROOT}/usr/lib64" \
    "${LUMEN_SYSROOT}/usr/lib" "${LUMEN_SYSROOT}/usr/lib64"; do
    [ -d "$libdir" ] || continue
    find "$libdir" -type f -name '*.la' -delete
  done
}

# Verify cross-compiler exists
base_verify_toolchain() {
  if ! command -v "$CC" &>/dev/null; then
    lumen_die "Cross-compiler not found: ${CC}. Build Phase 1 toolchain first."
  fi
  lumen_ok "Cross-compiler found: $(${CC} --version | head -1)"
}

# Assert that a dependency this package needs for cross-compilation is really
# present in the compiler sysroot, before configure is allowed to run.
#
# Why this exists rather than a plain `pkg-config --exists <name>`:
#
#   * Host `pkg-config` searches host paths only. The target metadata lives in
#     ${LUMEN_SYSROOT}, so an unqualified lookup reports "missing" even when the
#     dependency built correctly -- that is a false negative, and acting on it
#     would block a healthy build order.
#
#   * Not every consumer uses pkg-config. acl, for example, locates libattr with
#     AC_CHECK_LIB/AC_CHECK_HEADERS, so its real requirement is the shared
#     object and the header, not a .pc file. A pkg-config-only guard would
#     describe a requirement the build does not have.
#
# Therefore the check asserts on the artifacts a cross compiler actually
# consumes -- headers under usr/include and linkable objects under usr/lib --
# and is deliberately independent of the host's .pc database.
#
# Usage: base_require_sysroot_dependency <package-name> [path ...]
#
# Each path is relative to the sysroot. A caller that passes no paths is
# asserting the dependency provides at least one of them and the build should
# fail closed rather than pass vacuously.
base_require_sysroot_dependency() {
  local pkg="${1:-}" ; shift || true
  [ -n "$pkg" ] || lumen_die "base_require_sysroot_dependency called without a package name"

  if [ "$#" -eq 0 ]; then
    lumen_die "base_require_sysroot_dependency ${pkg}: no sysroot paths given; refusing to pass vacuously"
  fi

  local rel path
  for rel in "$@"; do
    # Accept "usr/include/attr/xattr.h" and "/usr/include/attr/xattr.h" alike so
    # callers do not have to agree on a leading-slash convention.
    rel="${rel#/}"
    path="${LUMEN_SYSROOT}/${rel}"
    if [ -e "$path" ]; then
      lumen_ok "Dependency ${pkg}: found ${rel} in the ShreeOS sysroot"
      return 0
    fi
  done

  lumen_die "Dependency ${pkg} is not in the ShreeOS sysroot. Looked for: $* (under ${LUMEN_SYSROOT}). Build it earlier, or correct the path list."
}

# Assert that staged files are genuine target objects and not host binaries.
#
# A package script that copies a file from the build host into the target root,
# or one whose install step silently falls back to a prebuilt artifact, produces
# an ISO that builds cleanly and then fails at runtime in the live session. That
# is the single most expensive class of bug in this project, because nothing
# notices until a user boots the image. Detecting it at package-build time turns
# a mysterious boot failure into a build failure with a precise message.
#
# Two properties are checked for every path:
#
#   1. Program interpreter. A dynamically linked target object must request
#      ld-linux-x86-64.so.2. A host Ubuntu binary requests the same path, so
#      the interpreter alone is not sufficient evidence; it is checked because a
#      foreign loader (musl, a 32-bit loader, a cross-architecture path) is an
#      unambiguous failure. A static object legitimately has no interpreter.
#
#   2. .note.package. Debian and Ubuntu rebuild every binary with a
#      .note.package section naming the source package and version. Upstream
#      tarballs never contain it, so its presence proves the file came from a
#      distribution package rather than from our cross toolchain.
#
# Usage: base_assert_no_host_binary <path> [path...]
#
# Paths are glob-expanded by the caller or here, and a pattern that matches
# nothing is an error rather than a silent pass. A missing artifact usually
# means the install step did not do what the script assumed, and that is worth
# failing on at build time.
base_assert_no_host_binary() {
  [ "$#" -gt 0 ] || lumen_die "base_assert_no_host_binary called with no arguments"

  # Resolve the inspector up front. Without this guard the function fails OPEN:
  # a missing readelf makes every `readelf -h` fail, which the "not an ELF"
  # branch would treat as "nothing to check", so contaminated binaries would be
  # reported as passing. A check that cannot run must not report success.
  local readelf_bin=""
  local candidate
  for candidate in "${READELF:-}" readelf "${LUMEN_TARGET_TRIPLET}-readelf"; do
    if [ -n "$candidate" ] && command -v "$candidate" >/dev/null 2>&1; then
      readelf_bin="$candidate"
      break
    fi
  done
  [ -n "$readelf_bin" ] || lumen_die \
    "base_assert_no_host_binary requires readelf, but no readelf was found in PATH"

  local pattern path checked=0
  for pattern in "$@"; do
    # Expand globs ourselves so an unexpanded pattern is detectable. The
    # caller's shell may or may not have expanded it, and a literal '*' reaching
    # this function means the caller expected a match that did not happen.
    local -a matches=()
    if [ -e "$pattern" ]; then
      matches=("$pattern")
    else
      # compgen exits non-zero when nothing matches. That is an answer, not an
      # error, so it is captured in a condition rather than aborted.
      local glob_list=""
      if glob_list="$(compgen -G "$pattern")"; then
        :
      else
        glob_list=""
      fi
      while IFS= read -r path; do
        [ -n "$path" ] && matches+=("$path")
      done <<< "$glob_list"
    fi

    if [ "${#matches[@]}" -eq 0 ]; then
      lumen_die "Host-binary check found no file matching '${pattern}'."
    fi

    for path in "${matches[@]}"; do
      [ -f "$path" ] || continue

      # Text files (pkgconfig, .la stubs, version scripts) are legitimately
      # installed beside the binaries and carry no ELF header to inspect.
      # Reading the header rather than matching the magic bytes keeps this
      # working regardless of locale or grep's binary handling of 0x7F.
      if ! "$readelf_bin" -h "$path" >/dev/null 2>&1; then
        continue
      fi

      local interp
      interp="$("$readelf_bin" -l "$path" 2>/dev/null \
        | sed -n 's/.*program interpreter: \(.*\)\]/\1/p' | head -n1)"
      case "$interp" in
        ""|/lib64/ld-linux-x86-64.so.2|/lib/ld-linux-x86-64.so.2)
          ;;
        *)
          lumen_die "Host-binary check failed: ${path} requests a foreign dynamic loader: ${interp}"
          ;;
      esac

      if "$readelf_bin" -S "$path" 2>/dev/null | grep -q 'note\.package'; then
        lumen_die "Host-binary check failed: ${path} carries a distribution .note.package section (host contamination)"
      fi

      checked=$((checked + 1))
    done
  done

  [ "$checked" -gt 0 ] || lumen_die \
    "Host-binary check inspected no ELF objects; refusing to report a pass"

  lumen_ok "Host-binary check passed on ${checked} target object(s)"
}

