#!/usr/bin/env bash
# scripts/doctor.sh — Comprehensive environment and prerequisite checker for ShreeOS
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

if [ -f "$REPO_ROOT/build.conf" ]; then
  source "$REPO_ROOT/build.conf"
fi
if [ -f "$REPO_ROOT/scripts/common.sh" ]; then
  source "$REPO_ROOT/scripts/common.sh"
fi

ERRORS=0
WARNINGS=0

check_cmd() {
  local cmd="$1"
  local desc="${2:-$1}"
  local required="${3:-true}"

  if command -v "$cmd" >/dev/null 2>&1; then
    local ver
    ver=$("$cmd" --version 2>&1 | head -n 1 | tr -cd '[:print:]' | cut -c1-60 || echo "available")
    printf "  \033[1;32m[OK]\033[0m %-22s (%s)\n" "$desc" "$ver"
  else
    if [ "$required" = "true" ]; then
      printf "  \033[1;31m[FAIL]\033[0m %-20s (NOT FOUND - required)\n" "$desc"
      ERRORS=$((ERRORS + 1))
    else
      printf "  \033[1;33m[WARN]\033[0m %-20s (NOT FOUND - optional)\n" "$desc"
      WARNINGS=$((WARNINGS + 1))
    fi
  fi
}

echo "========================================================"
echo " ShreeOS Environment & Toolchain Diagnostics (Doctor)   "
echo "========================================================"
echo ""

echo "==> Checking Core Host Build Tools:"
check_cmd "bash" "GNU Bash" true
check_cmd "make" "GNU Make" true
check_cmd "gcc" "C Compiler (gcc)" true
check_cmd "g++" "C++ Compiler (g++)" true
check_cmd "ld" "Linker (ld)" true
check_cmd "bison" "Parser (bison)" true
check_cmd "flex" "Lexer (flex)" true
check_cmd "awk" "Pattern processor (awk)" true
check_cmd "sed" "Stream editor (sed)" true
check_cmd "diff" "Diff utility" true
check_cmd "patch" "Patch utility" true
check_cmd "tar" "Archive tool (tar)" true
check_cmd "gzip" "Gzip compression" true
check_cmd "bzip2" "Bzip2 compression" true
check_cmd "xz" "XZ compression" true
check_cmd "cpio" "CPIO archive tool" true
check_cmd "curl" "Download tool (curl)" true
check_cmd "sha256sum" "Checksum tool (sha256sum)" true
check_cmd "bc" "Calculator (bc)" true
check_cmd "openssl" "OpenSSL CLI" true
check_cmd "gpg" "GnuPG" false

echo ""
echo "==> Checking Packaging, Boot & ISO Generation Tools:"
check_cmd "xorriso" "ISO creation (xorriso)" true
check_cmd "mcopy" "FAT manipulation (mtools)" true
check_cmd "grub-install" "GRUB bootloader installer" false
check_cmd "sfdisk" "GPT partitioning tool" false
check_cmd "losetup" "Loop device manager" false

echo ""
echo "==> Checking Emulation & Testing Environment:"
check_cmd "qemu-system-x86_64" "QEMU x86_64 emulator" false
check_cmd "shellcheck" "Shell script linter" false

echo ""
echo "==> Checking System Resources & Disk Space:"
FREE_KB=$(df -k "$REPO_ROOT" | awk 'NR==2 {print $4}')
FREE_GB=$((FREE_KB / 1024 / 1024))
if [ "$FREE_GB" -ge 10 ]; then
  printf "  \033[1;32m[OK]\033[0m Free disk space: %d GB available (minimum 10 GB recommended)\n" "$FREE_GB"
elif [ "$FREE_GB" -ge 4 ]; then
  printf "  \033[1;33m[WARN]\033[0m Free disk space: %d GB available (tight; full toolchain build may need >10 GB)\n" "$FREE_GB"
  WARNINGS=$((WARNINGS + 1))
else
  printf "  \033[1;31m[FAIL]\033[0m Free disk space: %d GB available (insufficient; need at least 4 GB)\n" "$FREE_GB"
  ERRORS=$((ERRORS + 1))
fi

TOTAL_MEM_KB=$(grep MemTotal /proc/meminfo 2>/dev/null | awk '{print $2}' || echo 0)
TOTAL_MEM_MB=$((TOTAL_MEM_KB / 1024))
if [ "$TOTAL_MEM_MB" -ge 2048 ]; then
  printf "  \033[1;32m[OK]\033[0m System RAM: %d MB available\n" "$TOTAL_MEM_MB"
elif [ "$TOTAL_MEM_MB" -gt 0 ]; then
  printf "  \033[1;33m[WARN]\033[0m System RAM: %d MB (builds with high -j may run low on memory)\n" "$TOTAL_MEM_MB"
  WARNINGS=$((WARNINGS + 1))
fi

echo ""
echo "==> Checking ShreeOS Build Pipeline Artifacts:"
check_artifact() {
  local path="$1"
  local desc="$2"
  if [ -e "$path" ]; then
    printf "  \033[1;32m[READY]\033[0m %-25s (%s)\n" "$desc" "$path"
  else
    printf "  \033[1;34m[PENDING]\033[0m %-23s (not built yet)\n" "$desc"
  fi
}

check_artifact "${REPO_ROOT}/build/tools/bin/x86_64-shreeos-linux-gnu-gcc" "Cross-Toolchain GCC"
check_artifact "${REPO_ROOT}/build/sysroot/usr/include/stdio.h" "Target Sysroot (glibc)"
check_artifact "${REPO_ROOT}/build/build-kernel/arch/x86/boot/bzImage" "Linux Kernel bzImage"
check_artifact "${REPO_ROOT}/pkgmanager/src/lpm" "LPM Package Manager"
check_artifact "${REPO_ROOT}/init/src/init" "Init Supervisor (PID 1)"
check_artifact "${REPO_ROOT}/hardware/shreed" "Hardware Daemon (shreed)"
check_artifact "${REPO_ROOT}/build/rootfs" "Root Filesystem Staging"
check_artifact "${REPO_ROOT}/out" "Output Directory"

echo ""
echo "========================================================"
if [ "$ERRORS" -eq 0 ]; then
  echo " Doctor Status: PASS ($ERRORS errors, $WARNINGS warnings)"
  echo " Your environment is ready to build ShreeOS components."
  exit 0
else
  echo " Doctor Status: FAILED ($ERRORS required tools/checks failed)"
  echo " Please install missing dependencies and re-run 'make doctor'."
  exit 1
fi
