#!/usr/bin/env bash
# update/scripts/system-update.sh — System update & package upgrade script for ShreeOS
#
# Syncs repository index, compares installed versions with repo index,
# and upgrades out-of-date packages atomically.
#
# Usage:
#   bash system-update.sh              # Check & apply updates
#   bash system-update.sh --check-only # List updates without installing
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LUMEN_ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$LUMEN_ROOT_DIR/build.conf" 2>/dev/null || true
source "$LUMEN_ROOT_DIR/scripts/common.sh" 2>/dev/null || {
  lumen_step() { echo "==> $1"; }
  lumen_log() { echo "  -> $1"; }
  lumen_ok() { echo "  [OK] $1"; }
  lumen_warn() { echo "  [WARN] $1"; }
  lumen_die() { echo "  [ERROR] $1" >&2; exit 1; }
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
elif [ -f "${LUMEN_ROOT_DIR}/pkgmanager/src/lpm" ]; then
  LPM_BIN="${LUMEN_ROOT_DIR}/pkgmanager/src/lpm"
fi

lumen_step "Updating repository index"
"${LPM_BIN}" update || lumen_warn "Repository update failed or repository offline"

REPO_JSON="/var/lib/lpm/repo.json"
INSTALLED_DIR="/var/lib/lpm/installed"

if [ ! -f "$REPO_JSON" ]; then
  lumen_die "No repository index found at ${REPO_JSON}"
fi

if [ ! -d "$INSTALLED_DIR" ]; then
  lumen_ok "No packages currently installed"
  exit 0
fi

lumen_step "Checking for available package updates"

UPDATES_COUNT=0
for pkg_dir in "$INSTALLED_DIR"/*/; do
  [ -d "$pkg_dir" ] || continue
  PKG_NAME=$(basename "$pkg_dir")
  
  if [ ! -f "${pkg_dir}/manifest.json" ]; then
    continue
  fi

  CUR_VER=$(grep -oP '"version"\s*:\s*"\K[^"]+' "${pkg_dir}/manifest.json" 2>/dev/null || echo "0.0")
  REPO_VER=$(grep -A 5 "\"${PKG_NAME}\"" "$REPO_JSON" 2>/dev/null | grep -oP '"version"\s*:\s*"\K[^"]+' || echo "")

  if [ -n "$REPO_VER" ] && [ "$REPO_VER" != "$CUR_VER" ]; then
    lumen_log "Update available for ${PKG_NAME}: ${CUR_VER} -> ${REPO_VER}"
    UPDATES_COUNT=$((UPDATES_COUNT + 1))

    if [ "$CHECK_ONLY" = false ]; then
      lumen_log "Upgrading ${PKG_NAME}..."
      "${LPM_BIN}" install "${PKG_NAME}" || lumen_warn "Failed to upgrade ${PKG_NAME}"
    fi
  fi
done

if [ "$UPDATES_COUNT" -eq 0 ]; then
  lumen_ok "All system packages are up to date"
else
  lumen_ok "Processed ${UPDATES_COUNT} package update(s)"
fi
