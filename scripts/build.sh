#!/usr/bin/env bash
# Reliable ShreeOS build entry point shared by WSL/local development.
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

profile="${1:-desktop}"
case "$profile" in
  desktop|minimal|server) ;;
  *)
    echo "Usage: $0 [desktop|minimal|server]" >&2
    exit 2
    ;;
esac

echo "==> ShreeOS reliable build: PROFILE=$profile"
bash scripts/doctor.sh --strict
bash scripts/verify-sources.sh --fetch

if [ "$profile" = "desktop" ]; then
  # Fail before spending time assembling an ISO known to lack its native target SDK.
  make toolchain
  make base-system
  if [ "${ALLOW_DEFERRED_GRAPHICS:-0}" = "1" ]; then
    # Explicit opt-in used by CI release builds and headless integration runs:
    # stage the desktop assets while the native graphics stack is still
    # incomplete, exactly like the ISO workflow does for its boot-compatible
    # build. The staged /etc/shreeos/desktop-native.status keeps reporting
    # "deferred" so no consumer mistakes this ISO for desktop-certified.
    bash scripts/graphics-readiness.sh || true
  else
    bash scripts/graphics-readiness.sh --strict
  fi
fi

make PROFILE="$profile" iso
make PROFILE="$profile" verify-iso
