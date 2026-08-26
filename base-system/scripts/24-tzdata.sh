#!/usr/bin/env bash
# Build and install the IANA timezone database.  zic is a build-time tool;
# the installed result is architecture-independent TZif data.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

VERSION=2025b
ARCHIVE="${LUMEN_SOURCES}/tzdata${VERSION}.tar.gz"
SOURCE="${LUMEN_SOURCES}/tzdata${VERSION}"
SHA256="11810413345fc7805017e27ea9fa4885fd74cd61b2911711ad038f5d28d71474"

lumen_fetch "https://data.iana.org/time-zones/releases/tzdata${VERSION}.tar.gz" "$ARCHIVE" "$SHA256"
rm -rf "$SOURCE"
mkdir -p "$SOURCE"
tar -xzf "$ARCHIVE" -C "$SOURCE"

# tzdata's zic is intentionally built for the build host to compile data; no
# host library is copied into the target rootfs.
make -C "$SOURCE" zic
install -d "${LUMEN_STAGE_ROOT}/usr/share/zoneinfo"
"${SOURCE}/zic" -b fat -d "${LUMEN_STAGE_ROOT}/usr/share/zoneinfo" \
  "${SOURCE}/africa" "${SOURCE}/antarctica" "${SOURCE}/asia" \
  "${SOURCE}/australasia" "${SOURCE}/europe" "${SOURCE}/northamerica" \
  "${SOURCE}/southamerica" "${SOURCE}/etcetera" "${SOURCE}/backward"

for zone in UTC Asia/Kolkata America/New_York America/Argentina/Buenos_Aires Europe/London; do
  [ -f "${LUMEN_STAGE_ROOT}/usr/share/zoneinfo/${zone}" ] || lumen_die "tzdata did not produce ${zone}"
done
