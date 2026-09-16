#!/usr/bin/env bash
# build-all.sh — Build all base-system packages for ShreeOS
# Usage: bash base-system/scripts/build-all.sh [--resume N]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

PACKAGES_LIST="$SCRIPT_DIR/../packages.list"
RESUME_FROM=1

while [[ $# -gt 0 ]]; do
  case "$1" in
    --resume) RESUME_FROM="$2"; shift 2 ;;
    --help|-h) echo "Usage: build-all.sh [--resume N]"; exit 0 ;;
    *) lumen_die "Unknown option: $1" ;;
  esac
done

BUILD_START=$(date +%s)
SPACE_BEFORE=$(df -h "$LUMEN_BUILD_DIR" 2>/dev/null | tail -1 | awk '{print $4}' || echo "unknown")

mkdir -p "$LUMEN_BUILD_DIR" "$LUMEN_STAGE_ROOT"

STEP=0
while IFS= read -r LINE; do
  [[ -z "$LINE" || "$LINE" =~ ^[[:space:]]*# ]] && continue
  read -r NAME _ <<<"$LINE"
  STEP=$((STEP + 1))
  if [ "$STEP" -ge "$RESUME_FROM" ]; then
    lumen_step "${STEP}: Building ${NAME}"
    bash "$SCRIPT_DIR/build-package.sh" "$NAME"
  else
    lumen_log "Skipping step ${STEP} (resuming from step ${RESUME_FROM})"
  fi
done < <(grep -vE '^\s*(#|$)' "$PACKAGES_LIST")

BUILD_END=$(date +%s)
SPACE_AFTER=$(df -h "$LUMEN_BUILD_DIR" 2>/dev/null | tail -1 | awk '{print $4}' || echo "unknown")

echo ""
echo "============================================"
lumen_ok "Base system build COMPLETE"
echo "============================================"
echo "  Target:       ${LUMEN_TARGET_TRIPLET}"
echo "  Rootfs:       ${LUMEN_STAGE_ROOT}"
echo "  Duration:     $((BUILD_END - BUILD_START))s"
echo "  Space (before): ${SPACE_BEFORE}"
echo "  Space (after):  ${SPACE_AFTER}"
echo "============================================"
