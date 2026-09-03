#!/usr/bin/env bash
# build-all.sh — Build the complete cross-compilation toolchain for ShreeOS
# Executes all build stages in the correct LFS 2-pass order.
#
# Usage:
#   bash toolchain/scripts/build-all.sh              # full build
#   bash toolchain/scripts/build-all.sh --resume N    # resume from step N
#   bash toolchain/scripts/build-all.sh --skip-tests  # skip final verification
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

RESUME_FROM=1
SKIP_TESTS=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --resume)
      if [[ -z "${2:-}" ]]; then
        lumen_die "--resume requires a step number (1-7)"
      fi
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
    --help|-h)
      echo "Usage: build-all.sh [--resume N] [--skip-tests]"
      exit 0
      ;;
    *)
      lumen_die "Unknown option: $1" "Usage: build-all.sh [--resume N] [--skip-tests]"
      ;;
  esac
done

# Validate resume step is in range 1-7
if [[ ! "$RESUME_FROM" =~ ^[1-7]$ ]]; then
  lumen_die "Invalid resume step: ${RESUME_FROM}. Must be 1-7."
fi

lumen_verify_toolchain

# Record disk space before starting
BUILD_START=$(date +%s)
SPACE_BEFORE=$(df -h "$LUMEN_BUILD_DIR" 2>/dev/null | tail -1 | awk '{print $4}' || echo "unknown")

mkdir -p "$LUMEN_BUILD_DIR" "$LUMEN_TOOLS" "$LUMEN_SYSROOT"

run_step() {
  local step_num=$1
  local step_name=$2
  local step_script=$3
  if [ "$step_num" -ge "$RESUME_FROM" ]; then
    lumen_step "${step_num}/7: ${step_name}"
    if [ ! -f "$step_script" ]; then
      lumen_die "Script not found: ${step_script}"
    fi
    bash "$step_script"
  else
    lumen_log "Skipping step ${step_num} (resuming from step ${RESUME_FROM})"
  fi
}

run_step 1 "Building binutils (Pass 1)"     "${SCRIPT_DIR}/build-binutils-pass1.sh"
run_step 2 "Building GCC (Pass 1)"           "${SCRIPT_DIR}/build-gcc-pass1.sh"
run_step 3 "Installing Linux kernel headers"  "${SCRIPT_DIR}/install-kernel-headers.sh"
run_step 4 "Building glibc"                  "${SCRIPT_DIR}/build-glibc.sh"
run_step 5 "Building libstdc++"              "${SCRIPT_DIR}/build-libstdcpp.sh"
run_step 6 "Building GCC (Pass 2)"           "${SCRIPT_DIR}/build-gcc-pass2.sh"
run_step 7 "Staging toolchain"               "${SCRIPT_DIR}/stage-toolchain.sh"

BUILD_END=$(date +%s)
BUILD_DURATION=$((BUILD_END - BUILD_START))

# Verify cross-compiler
if [ "$SKIP_TESTS" = false ]; then
  lumen_step "Verifying toolchain with smoke test"
  SMOKE_SCRIPT="${LUMEN_ROOT_DIR}/tests/smoke/test-toolchain.sh"
  if [ -f "$SMOKE_SCRIPT" ]; then
    bash "$SMOKE_SCRIPT"
  else
    lumen_warn "Smoke test script not found at ${SMOKE_SCRIPT}"
  fi
fi

SPACE_AFTER=$(df -h "$LUMEN_BUILD_DIR" 2>/dev/null | tail -1 | awk '{print $4}' || echo "unknown")

echo ""
echo "============================================"
lumen_ok "Cross-compilation toolchain build COMPLETE"
echo "============================================"
echo "  Target:       ${LUMEN_TARGET_TRIPLET}"
echo "  Install:      ${LUMEN_TOOLS}"
echo "  Sysroot:      ${LUMEN_SYSROOT}"
echo "  Binutils:     ${VER_BINUTILS}"
echo "  GCC:          ${VER_GCC}"
echo "  glibc:        ${VER_GLIBC}"
echo "  Kernel:       ${VER_LINUX_KERNEL}"
echo "  Duration:     ${BUILD_DURATION}s"
echo "  Space (before): ${SPACE_BEFORE}"
echo "  Space (after):  ${SPACE_AFTER}"
echo "============================================"
echo "Key binaries:"
ls -lh "${LUMEN_TOOLS}/bin/${LUMEN_TARGET_TRIPLET}-gcc" 2>/dev/null || echo "  (compiler not found)"
ls -lh "${LUMEN_TOOLS}/bin/${LUMEN_TARGET_TRIPLET}-g++" 2>/dev/null || echo "  (C++ compiler not found)"
ls -lh "${LUMEN_TOOLS}/bin/${LUMEN_TARGET_TRIPLET}-ld" 2>/dev/null || echo "  (linker not found)"
echo ""
echo "Next steps:"
echo "  1. bash tests/smoke/test-toolchain.sh  (verify cross-compiler)"
echo "  2. cd base-system && ...               (proceed to Phase 2)"
