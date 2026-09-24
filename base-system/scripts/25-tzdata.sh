#!/usr/bin/env bash
# Build and install the IANA timezone database.  zic is a build-time tool;
# the installed result is architecture-independent TZif data.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

VERSION="$(pkg_version tzdata)"
CODE_ARCHIVE="${LUMEN_SOURCES}/$(pkg_archive tzcode)"
DATA_ARCHIVE="${LUMEN_SOURCES}/$(pkg_archive tzdata)"
CODE_SOURCE="${LUMEN_SOURCES}/tzcode${VERSION}"
DATA_SOURCE="${LUMEN_SOURCES}/tzdata${VERSION}"

lumen_fetch "$(pkg_url tzcode)" "$CODE_ARCHIVE" "$(pkg_sha256 tzcode)"
lumen_fetch "$(pkg_url tzdata)" "$DATA_ARCHIVE" "$(pkg_sha256 tzdata)"
rm -rf "$CODE_SOURCE" "$DATA_SOURCE"
mkdir -p "$CODE_SOURCE" "$DATA_SOURCE"
tar -xzf "$CODE_ARCHIVE" -C "$CODE_SOURCE"
tar -xzf "$DATA_ARCHIVE" -C "$DATA_SOURCE"

# zic is a build-host executable. Do not use the target cross compiler and
# do not install this host binary in the target filesystem.
#
# IANA ships code and data in separate tarballs, but the tzcode Makefile
# generates version.h from the data files (the 'version' target depends on
# africa/asia/...). The data files must therefore be visible inside the
# code tree before building zic. Copy every data file so future zone splits
# cannot reintroduce "No rule to make target 'africa'" failures.
for data_path in "${DATA_SOURCE}/"*; do
  [ -f "$data_path" ] || continue
  cp -f "$data_path" "${CODE_SOURCE}/"
done
env -u CC -u CXX -u AR -u AS -u RANLIB -u LD -u STRIP \
    -u CPPFLAGS -u CFLAGS -u LDFLAGS \
  make -C "$CODE_SOURCE" VERSION="$VERSION" VERSION_DEPS= zic CC="${HOSTCC:-cc}"
install -d "${LUMEN_STAGE_ROOT}/usr/share/zoneinfo"
"${CODE_SOURCE}/zic" -b fat -d "${LUMEN_STAGE_ROOT}/usr/share/zoneinfo" \
  "${DATA_SOURCE}/africa" "${DATA_SOURCE}/antarctica" "${DATA_SOURCE}/asia" \
  "${DATA_SOURCE}/australasia" "${DATA_SOURCE}/europe" "${DATA_SOURCE}/northamerica" \
  "${DATA_SOURCE}/southamerica" "${DATA_SOURCE}/etcetera" "${DATA_SOURCE}/backward"

for zone in UTC Asia/Kolkata America/New_York America/Argentina/Buenos_Aires Europe/London; do
  [ -f "${LUMEN_STAGE_ROOT}/usr/share/zoneinfo/${zone}" ] || lumen_die "tzdata did not produce ${zone}"
done
