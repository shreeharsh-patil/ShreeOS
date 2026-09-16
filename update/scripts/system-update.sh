#!/usr/bin/env bash
# update/scripts/system-update.sh — System update & package upgrade script for ShreeOS
#
# Syncs repository index, compares installed versions using semver ordering,
# and upgrades out-of-date packages atomically.
#
# Usage:
#   bash system-update.sh              # Check & apply updates
#   bash system-update.sh --check-only # List updates without installing
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SHREEOS_ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$SHREEOS_ROOT_DIR/build.conf" 2>/dev/null || true
source "$SHREEOS_ROOT_DIR/scripts/common.sh" 2>/dev/null || {
  shreeos_step() { echo "==> $1"; }
  shreeos_log() { echo "  -> $1"; }
  shreeos_ok() { echo "  [OK] $1"; }
  shreeos_warn() { echo "  [WARN] $1"; }
  shreeos_die() { echo "  [ERROR] $1" >&2; exit 1; }
  lumen_die() { shreeos_die "$@"; }
}

CHECK_ONLY=false
for arg in "$@"; do
  case "$arg" in
    --check-only) CHECK_ONLY=true ;;
    --help|-h) echo "Usage: system-update.sh [--check-only]"; exit 0 ;;
  esac
done

LPM_BIN="lpm"
if command -v lpm >/dev/null 2>&1; then
  LPM_BIN="lpm"
elif [ -f "${SHREEOS_ROOT_DIR}/pkgmanager/src/lpm" ]; then
  LPM_BIN="${SHREEOS_ROOT_DIR}/pkgmanager/src/lpm"
fi

shreeos_step "Synchronizing repository package index"
"${LPM_BIN}" update || shreeos_warn "Repository index update failed or server unreachable"

REPO_JSON="/var/lib/lpm/repo.json"
INSTALLED_DIR="/var/lib/lpm/installed"

if [ ! -f "$REPO_JSON" ]; then
  shreeos_die "No repository index found at ${REPO_JSON}"
fi

if [ ! -d "$INSTALLED_DIR" ]; then
  shreeos_ok "No packages currently installed"
  exit 0
fi

if [ "$CHECK_ONLY" = true ]; then
  shreeos_step "Checking for available package updates (dry run)"
  UPDATES_COUNT=0
  for pkg_dir in "$INSTALLED_DIR"/*/; do
    [ -d "$pkg_dir" ] || continue
    PKG_NAME=$(basename "$pkg_dir")
    [ -f "${pkg_dir}/manifest.json" ] || continue

    CUR_VER=$(grep -oP '"version"\s*:\s*"\K[^"]+' "${pkg_dir}/manifest.json" 2>/dev/null || echo "0.0")
    REPO_VER=$(grep -A 5 "\"${PKG_NAME}\"" "$REPO_JSON" 2>/dev/null | grep -oP '"version"\s*:\s*"\K[^"]+' || echo "")

    if [ -n "$REPO_VER" ] && [ "$REPO_VER" != "$CUR_VER" ]; then
      # Check if REPO_VER is strictly newer
      if [ "$(printf '%s\n%s' "$CUR_VER" "$REPO_VER" | sort -V | tail -n1)" = "$REPO_VER" ] && [ "$CUR_VER" != "$REPO_VER" ]; then
        shreeos_log "Update available for ${PKG_NAME}: ${CUR_VER} -> ${REPO_VER}"
        UPDATES_COUNT=$((UPDATES_COUNT + 1))
      fi
    fi
  done
  shreeos_ok "Found ${UPDATES_COUNT} update(s) available"
else
  shreeos_step "Applying package upgrades atomically via lpm upgrade"
  "${LPM_BIN}" upgrade
  shreeos_ok "System update process completed"
fi
