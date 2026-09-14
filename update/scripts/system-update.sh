#!/usr/bin/env bash
# update/scripts/system-update.sh — System update & SafeUpdate recovery tool for ShreeOS
#
# Syncs the repository index, verifies installed packages, and delegates
# transactional upgrades/rollback to LPM.
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
}

LPM_BIN="lpm"
if command -v lpm >/dev/null 2>&1; then
  LPM_BIN="lpm"
elif [ -x "${SHREEOS_ROOT_DIR}/pkgmanager/src/lpm" ]; then
  LPM_BIN="${SHREEOS_ROOT_DIR}/pkgmanager/src/lpm"
else
  shreeos_die "LPM package manager is not available"
fi

ACTION="upgrade"
ROLLBACK_ID=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    --check-only) ACTION="check" ;;
    --history) ACTION="history" ;;
    --rollback)
      ACTION="rollback"
      if [ "$#" -gt 1 ] && [[ "$2" != --* ]]; then
        ROLLBACK_ID="$2"
        shift
      fi
      ;;
    --verify) ACTION="verify" ;;
    --repair) ACTION="repair" ;;
    --help|-h)
      cat <<'EOF'
ShreeOS SafeUpdate System Manager
Usage: system-update.sh [OPTIONS]
  --check-only     Check for upgrades without changing the system
  --history        View recorded package update transactions
  --rollback [ID]  Revert to a previous working state
  --verify         Verify all installed package files and checksums
  --repair         Run LPM package database/integrity repair
EOF
      exit 0
      ;;
    *) shreeos_die "Unknown option: $1" ;;
  esac
  shift
done

case "$ACTION" in
  history)
    shreeos_step "Listing SafeUpdate transaction history"
    "$LPM_BIN" history
    exit 0
    ;;
  rollback)
    shreeos_step "Reverting system state via SafeUpdate rollback"
    if [ -n "$ROLLBACK_ID" ]; then
      "$LPM_BIN" rollback "$ROLLBACK_ID"
    else
      "$LPM_BIN" rollback
    fi
    shreeos_ok "Rollback sequence completed"
    exit 0
    ;;
  verify)
    shreeos_step "Verifying all installed packages"
    failures=0
    checked=0
    if [ -d /var/lib/lpm/installed ]; then
      for pkg in /var/lib/lpm/installed/*; do
        [ -d "$pkg" ] || continue
        checked=$((checked + 1))
        if ! "$LPM_BIN" verify "$(basename "$pkg")"; then
          failures=$((failures + 1))
        fi
      done
    fi

    if [ "$failures" -gt 0 ]; then
      shreeos_die "Package verification failed for ${failures} of ${checked} package(s)"
    fi
    shreeos_ok "Package verification passed for ${checked} package(s)"
    exit 0
    ;;
  repair)
    shreeos_step "Repairing package database and system manifests"
    "$LPM_BIN" repair
    shreeos_ok "Package repair completed successfully"
    exit 0
    ;;
esac

shreeos_step "Synchronizing and verifying repository package index"
if ! "$LPM_BIN" update; then
  if [ -f /var/lib/lpm/repo.json ]; then
    shreeos_warn "Repository refresh failed; retaining the last valid cached index"
  else
    shreeos_die "Repository refresh failed and no cached index is available"
  fi
fi

if [ "$ACTION" = "check" ]; then
  shreeos_step "Checking for package upgrades"
  "$LPM_BIN" upgrade --dry-run
  exit 0
fi

shreeos_step "Applying package upgrades transactionally"
if ! "$LPM_BIN" upgrade; then
  shreeos_warn "One or more upgrades failed. LPM preserved per-package transaction data."
  shreeos_warn "Inspect 'lpm history' and use SafeUpdate rollback if recovery is required."
  exit 1
fi

shreeos_step "Verifying system integrity after upgrade"
if ! "$LPM_BIN" repair; then
  shreeos_warn "Upgrades completed, but post-update integrity verification failed."
  shreeos_warn "Run 'system-update.sh --verify' and inspect 'lpm history' before rebooting."
  exit 1
fi

shreeos_ok "SafeUpdate completed successfully"
