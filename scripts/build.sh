#!/usr/bin/env bash
# Legacy source-built ISO pipeline retained for the original desktop experiment.
# The canonical Debian-based ShreeOS image is built by scripts/build-shreeos.sh.
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

if [ -z "${SHREEOS_MAKE_JOBS:-}" ]; then
  jobs="$(nproc 2>/dev/null || echo 4)"
  if [ "$jobs" -gt 8 ]; then
    jobs=8
  fi
  export SHREEOS_MAKE_JOBS="$jobs"
fi

# This legacy pipeline can build desktop/security/minimal/server profiles, but
# its source-built ISO is not the canonical ShreeOS release image.
profile="${1:-desktop}"
case "$profile" in
  desktop|security|minimal|server) ;;
  *)
    echo "Usage: $0 [desktop|security|minimal|server]" >&2
    exit 2
    ;;
esac

printf '==> ShreeOS legacy source-built ISO: PROFILE=%s\n' "$profile"
bash scripts/doctor.sh --strict

for component in toolchain kernel base-system; do
  bash scripts/verify-sources.sh --fetch --component="$component"
done

case "$profile" in
  desktop|security)
    bash scripts/verify-sources.sh --fetch --component=desktop
    bash desktop/graphics/verify-sources.sh
    make PROFILE="$profile" toolchain
    make PROFILE="$profile" base-system
    ;;
esac

make PROFILE="$profile" iso
make PROFILE="$profile" verify-iso

case "$profile" in
  desktop|security)
    PROFILE="$profile" bash scripts/graphics-readiness.sh --strict
    ;;
esac
