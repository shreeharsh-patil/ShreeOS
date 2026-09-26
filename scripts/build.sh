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

# The graphical desktop edition is the primary ShreeOS product. Minimal and
# server remain explicit profiles for rescue, CI diagnostics, and headless use.
profile="${1:-desktop}"
case "$profile" in
  desktop|minimal|server) ;;
  *)
    echo "Usage: $0 [desktop|minimal|server]" >&2
    exit 2
    ;;
esac

printf '==> ShreeOS reliable build: PROFILE=%s\n' "$profile"
bash scripts/doctor.sh --strict

for component in toolchain kernel base-system; do
  bash scripts/verify-sources.sh --fetch --component="$component"
done

if [ "$profile" = "desktop" ]; then
  bash scripts/verify-sources.sh --fetch --component=desktop
  bash desktop/graphics/verify-sources.sh
  make PROFILE="$profile" toolchain
  make PROFILE="$profile" base-system
fi

make PROFILE="$profile" iso
make PROFILE="$profile" verify-iso

if [ "$profile" = "desktop" ]; then
  PROFILE=desktop bash scripts/graphics-readiness.sh --strict
fi
