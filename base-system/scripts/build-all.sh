#!/usr/bin/env bash
# build-all.sh — Build the complete base system for ShreeOS
# Executes all package build scripts in dependency order.
#
# Usage:
#   bash base-system/scripts/build-all.sh                      # full build
#   bash base-system/scripts/build-all.sh --resume N            # resume from package N
#   bash base-system/scripts/build-all.sh --skip-tests          # skip final verification
#   bash base-system/scripts/build-all.sh --list                # list packages
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

RESUME_FROM=1
SKIP_TESTS=false

# Build order (dependency order: dependencies before dependents)
PACKAGES=(
  "01-m4"
  "02-ncurses"
  "03-zlib"
  "04-bison"
  "05-flex"
  "06-readline"
  "07-bash"
  "08-coreutils"
  "09-diffutils"
  "10-file"
  "11-gawk"
  "12-grep"
  "13-gzip"
  "14-make"
  "15-patch"
  "16-sed"
  "17-tar"
  "18-xz"
  "19-util-linux"
  "20-libxcrypt"
  "21-wpa-supplicant"
  "22-alsa"
  "23-bluez"
  "24-tzdata"
)

while [[ $# -gt 0 ]]; do
  case "$1" in
    --resume)
      RESUME_FROM="$2"
      shift 2
      ;;
    --resume=*)
      RESUME_FROM="${1#*=}"
      shift
      ;;
    --skip-tests)
      SKIP_TESTS=true
      shift
      ;;
    --list)
      echo "Base system packages (build order):"
      for i in "${!PACKAGES[@]}"; do
        PKG_FILE="${PACKAGES[$i]}"
        PKG_NAME="${PKG_FILE#*-}"
        PKG_NUM="${PKG_FILE%%-*}"
        printf "  %s. %s\n" "$PKG_NUM" "$PKG_NAME"
      done
      exit 0
      ;;
    --help|-h)
      echo "Usage: build-all.sh [--resume N] [--skip-tests] [--list]"
      exit 0
      ;;
    *)
      lumen_die "Unknown option: $1" "Usage: build-all.sh [--resume N] [--skip-tests] [--list]"
      ;;
  esac
done

# Validate resume step
if [[ ! "$RESUME_FROM" =~ ^[0-9]+$ ]] || [ "$RESUME_FROM" -lt 1 ] || [ "$RESUME_FROM" -gt "${#PACKAGES[@]}" ]; then
  lumen_die "Invalid resume step: ${RESUME_FROM}. Must be 1-${#PACKAGES[@]}."
fi

base_verify_toolchain

BUILD_START=$(date +%s)

for PKG_FILE in "${PACKAGES[@]}"; do
  PKG_NUM="${PKG_FILE%%-*}"
  PKG_NAME="${PKG_FILE#*-}"
  PKG_SCRIPT="${SCRIPT_DIR}/${PKG_FILE}.sh"

  if [ "$((10#$PKG_NUM))" -lt "$((10#$RESUME_FROM))" ]; then
    lumen_log "Skipping package ${PKG_NUM}/${#PACKAGES[@]}: ${PKG_NAME} (resumed from ${RESUME_FROM})"
    continue
  fi

  lumen_step "[${PKG_NUM}/${#PACKAGES[@]}] Building ${PKG_NAME}"

  if [ ! -f "$PKG_SCRIPT" ]; then
    lumen_die "Build script not found: ${PKG_SCRIPT}"
  fi

  bash "$PKG_SCRIPT"
  lumen_ok "[${PKG_NUM}/${#PACKAGES[@]}] ${PKG_NAME} built"
done

BUILD_END=$(date +%s)
BUILD_DURATION=$((BUILD_END - BUILD_START))

# Verify with smoke test
if [ "$SKIP_TESTS" = false ]; then
  lumen_step "Verifying base system with smoke test"
  SMOKE_SCRIPT="${LUMEN_ROOT_DIR}/tests/smoke/test-base-system.sh"
  if [ -f "$SMOKE_SCRIPT" ]; then
    bash "$SMOKE_SCRIPT"
  else
    lumen_warn "Smoke test script not found at ${SMOKE_SCRIPT}"
  fi
fi

echo ""
echo "============================================"
lumen_ok "Base system build COMPLETE"
echo "============================================"
echo "  Packages: ${#PACKAGES[@]}"
echo "  Install:  ${LUMEN_STAGE_ROOT}"
echo "  Duration: ${BUILD_DURATION}s"
echo "============================================"
echo ""
echo "Next steps:"
echo "  1. bash tests/smoke/test-base-system.sh  (verify chroot)"
echo "  2. Proceed to Phase 3 (Kernel) or Phase 4 (Rootfs)"
echo ""
