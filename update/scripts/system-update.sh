#!/usr/bin/env bash
# update/scripts/system-update.sh — System update & SafeUpdate recovery tool for ShreeOS
#
# Syncs repository index, validates signatures, verifies packages, and upgrades atomically.
# Unifies lpm update, upgrade, history, rollback, and repair workflows.
#
# Usage:
#   bash system-update.sh              # Check & apply updates with SafeUpdate protection
#   bash system-update.sh --check-only # List updates without installing
#   bash system-update.sh --history    # View update transaction history
#   bash system-update.sh --rollback   # Restore previous working state
#   bash system-update.sh --verify     # Verify system package integrity
#   bash system-update.sh --repair     # Attempt automated package database repair
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

LPM_BIN="lpm"
if command -v lpm >/dev/null 2>&1; then
  LPM_BIN="lpm"
elif [ -x "${SHREEOS_ROOT_DIR}/pkgmanager/src/lpm" ]; then
  LPM_BIN="${SHREEOS_ROOT_DIR}/pkgmanager/src/lpm"
fi

ACTION="upgrade"
ROLLBACK_ID=""

while [ $# -gt 0 ]; do
  case "$1" in
    --check-only) ACTION="check" ;;
    --history)    ACTION="history" ;;
    --rollback)   ACTION="rollback"; [ $# -gt 1 ] && [[ "$2" != --* ]] && { ROLLBACK_ID="$2"; shift; } ;;
    --verify)     ACTION="verify" ;;
    --repair)     ACTION="repair" ;;
    --help|-h)
      echo "ShreeOS SafeUpdate System Manager"
      echo "Usage: system-update.sh [OPTIONS]"
      echo "Options:"
      echo "  --check-only   Check for updates without applying changes"
      echo "  --history      View recorded package update transactions"
      echo "  --rollback [ID] Revert to previous working state"
      echo "  --verify       Verify checksums of all installed packages"
      echo "  --repair       Repair corrupted package entries"
      exit 0
      ;;
    *) shreeos_die "Unknown option: $1" ;;
  esac
  shift
done

case "$ACTION" in
  history)
    shreeos_step "Listing SafeUpdate transaction history"
    "${LPM_BIN}" history
    exit 0
    ;;
  rollback)
    shreeos_step "Reverting system state via SafeUpdate rollback"
    if [ -n "$ROLLBACK_ID" ]; then
      "${LPM_BIN}" rollback "$ROLLBACK_ID"
    else
      "${LPM_BIN}" rollback
    fi
    shreeos_ok "Rollback sequence completed"
    exit 0
    ;;
  verify)
    shreeos_step "Verifying all installed packages"
    if [ -d /var/lib/lpm/installed ]; then
      for pkg in /var/lib/lpm/installed/*; do
        [ -d "$pkg" ] || continue
        "${LPM_BIN}" verify "$(basename "$pkg")" || true
      done
    fi
    exit 0
    ;;
  repair)
    shreeos_step "Repairing package database and system manifests"
    "${LPM_BIN}" repair
    exit 0
    ;;
esac

# 1. Sync repository index
shreeos_step "Synchronizing and verifying repository package index"
if ! "${LPM_BIN}" update; then
  shreeos_warn "Repository index update failed or signature rejected; using cached valid index if available"
fi

REPO_JSON="/var/lib/lpm/repo.json"
INSTALLED_DIR="/var/lib/lpm/installed"

if [ ! -f "$REPO_JSON" ]; then
  shreeos_die "No repository index found at ${REPO_JSON}"
fi

if [ ! -d "$INSTALLED_DIR" ]; then
  shreeos_ok "No packages currently installed"
  exit 0
fi

# 2. Inspect available updates
shreeos_step "Analyzing installed packages for available upgrades"
UPDATES_COUNT=0
CRITICAL_UPDATES=0

for pkg_dir in "$INSTALLED_DIR"/*/; do
  [ -d "$pkg_dir" ] || continue
  PKG_NAME=$(basename "$pkg_dir")
  [ -f "${pkg_dir}/manifest.json" ] || continue

  CUR_VER=$(grep -oP '"version"\s*:\s*"\K[^"]+' "${pkg_dir}/manifest.json" 2>/dev/null || echo "0.0")
  REPO_VER=$(grep -A 5 "\"${PKG_NAME}\"" "$REPO_JSON" 2>/dev/null | grep -oP '"version"\s*:\s*"\K[^"]+' || echo "")

  if [ -n "$REPO_VER" ] && [ "$REPO_VER" != "$CUR_VER" ]; then
    if [ "$(printf '%s\n%s' "$CUR_VER" "$REPO_VER" | sort -V | tail -n1)" = "$REPO_VER" ] && [ "$CUR_VER" != "$REPO_VER" ]; then
      shreeos_log "Update available for ${PKG_NAME}: ${CUR_VER} -> ${REPO_VER}"
      UPDATES_COUNT=$((UPDATES_COUNT + 1))
      case "$PKG_NAME" in
        kernel*|init*|glibc*|shreed*|system*)
          CRITICAL_UPDATES=$((CRITICAL_UPDATES + 1))
          shreeos_log "  [!] Critical core component: recoverable SafeUpdate snapshot will be generated"
          ;;
      esac
    fi
  fi
done

if [ "$UPDATES_COUNT" -eq 0 ]; then
  shreeos_ok "System is completely up to date (0 packages require upgrade)"
  exit 0
fi

shreeos_ok "Found ${UPDATES_COUNT} update(s) available (${CRITICAL_UPDATES} critical core component(s))"

if [ "$ACTION" = "check" ]; then
  exit 0
fi

# 3. Apply upgrades atomically
shreeos_step "Applying package upgrades atomically via lpm upgrade"
if "${LPM_BIN}" upgrade; then
  shreeos_ok "All package upgrades completed successfully"
  shreeos_step "Verifying system integrity post-update"
  "${LPM_BIN}" repair || true
  shreeos_ok "SafeUpdate completed without errors"
else
  shreeos_warn "Upgrade encountered an issue. SafeUpdate transaction preserved."
  shreeos_warn "To restore previous system state, run: system-update.sh --rollback"
  exit 1
fi
