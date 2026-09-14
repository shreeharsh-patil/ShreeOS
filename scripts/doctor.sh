#!/usr/bin/env bash
# scripts/doctor.sh — Comprehensive host/build prerequisite checker for ShreeOS.
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

source "$REPO_ROOT/build.conf"
source "$REPO_ROOT/scripts/common.sh"

ERRORS=0
WARNINGS=0
STRICT=false

for arg in "$@"; do
  case "$arg" in
    --strict) STRICT=true ;;
    --help|-h)
      echo "Usage: doctor.sh [--strict]"
      echo "  --strict  require runtime validation and installer prerequisites"
      exit 0
      ;;
    *) echo "Unknown option: $arg" >&2; exit 2 ;;
  esac
done

ok()   { printf "  \033[1;32m[OK]\033[0m %s\n" "$*"; }
warn() { printf "  \033[1;33m[WARN]\033[0m %s\n" "$*"; WARNINGS=$((WARNINGS + 1)); }
fail() { printf "  \033[1;31m[FAIL]\033[0m %s\n" "$*"; ERRORS=$((ERRORS + 1)); }

check_cmd() {
  local cmd="$1"
  local desc="${2:-$1}"
  local required="${3:-true}"

  if command -v "$cmd" >/dev/null 2>&1; then
    local ver
    ver="$("$cmd" --version 2>&1 | head -n 1 | tr -cd '[:print:]' | cut -c1-64 || true)"
    [ -n "$ver" ] || ver="available"
    ok "$desc ($ver)"
  elif [ "$required" = "true" ]; then
    fail "$desc (NOT FOUND - required)"
  else
    warn "$desc (NOT FOUND - optional)"
  fi
}

echo "========================================================"
echo " ShreeOS Environment & Build Diagnostics"
echo "========================================================"
echo

echo "==> Host environment"
if grep -qi microsoft /proc/version 2>/dev/null || grep -qi microsoft <<<"$(uname -r)"; then
  if grep -qiE 'wsl2|microsoft-standard' <<<"$(uname -r)"; then
    ok "WSL2 detected"
  else
    fail "WSL detected but WSL2 was not confirmed; WSL1 is unsupported"
  fi

  case "$REPO_ROOT" in
    /mnt/[a-zA-Z]/*)
      if [ "${SHREEOS_ALLOW_WINDOWS_FS:-0}" = "1" ]; then
        warn "Repository is under /mnt; Windows filesystem builds can be slower and less reliable"
      else
        fail "Repository is under /mnt. Clone ShreeOS to ~/ShreeOS (or set SHREEOS_ALLOW_WINDOWS_FS=1 to override)"
      fi
      ;;
    *) ok "Repository is on the WSL Linux filesystem" ;;
  esac
else
  ok "Native Linux host detected"
fi

echo
echo "==> Core host build tools"
check_cmd bash "GNU Bash" true
check_cmd git "Git" true
check_cmd python3 "Python 3" true
check_cmd make "GNU Make" true
check_cmd gcc "C Compiler (gcc)" true
check_cmd g++ "C++ Compiler (g++)" true
check_cmd ld "Linker (ld)" true
check_cmd bison "Parser (bison)" true
check_cmd flex "Lexer (flex)" true
check_cmd gawk "GNU awk" true
check_cmd sed "Stream editor (sed)" true
check_cmd patch "Patch utility" true
check_cmd tar "Archive tool (tar)" true
check_cmd gzip "Gzip compression" true
check_cmd bzip2 "Bzip2 compression" true
check_cmd xz "XZ compression" true
check_cmd cpio "CPIO archive tool" true
check_cmd curl "Download tool (curl)" true
check_cmd sha256sum "Checksum tool" true
check_cmd bc "Calculator (bc)" true
check_cmd gperf "Perfect hash generator" true
check_cmd pkg-config "pkg-config" true
check_cmd openssl "OpenSSL CLI" true
check_cmd rsync "rsync" true
check_cmd shellcheck "ShellCheck" false

echo
echo "==> Packaging, boot and ISO tools"
check_cmd xorriso "ISO creation (xorriso)" true
check_cmd mcopy "FAT copy (mtools)" true
check_cmd mformat "FAT formatter (mtools)" true
check_cmd mmd "FAT directory tool (mtools)" true
check_cmd grub-mkimage "GRUB image builder" true
check_cmd envsubst "Template substitution (gettext-base)" true
check_cmd sfdisk "Disk partitioning (sfdisk)" "$STRICT"
check_cmd losetup "Loop device manager" "$STRICT"
check_cmd mkfs.ext4 "ext4 formatter" "$STRICT"
check_cmd mkfs.vfat "FAT formatter" "$STRICT"
check_cmd mount "Filesystem mount tool" "$STRICT"
check_cmd umount "Filesystem unmount tool" "$STRICT"
check_cmd blkid "Filesystem ID tool" "$STRICT"
check_cmd grub-install "GRUB disk installer" "$STRICT"
check_cmd qemu-system-x86_64 "QEMU x86_64 emulator" "$STRICT"

if [ "$(id -u)" -ne 0 ]; then
  check_cmd sudo "Privilege elevation (sudo)" "$STRICT"
fi

if [ -f /usr/share/ovmf/OVMF.fd ] || [ -f /usr/share/qemu/OVMF.fd ] || [ -f /usr/share/OVMF/OVMF_CODE.fd ] || [ -f /usr/share/OVMF/OVMF_CODE_4M.fd ]; then
  ok "OVMF UEFI firmware"
elif [ "$STRICT" = true ]; then
  fail "OVMF UEFI firmware not found; strict UEFI boot validation cannot run"
else
  warn "OVMF UEFI firmware not found; UEFI QEMU validation will not work"
fi

echo
echo "==> System resources"
FREE_KB="$(df -Pk "$REPO_ROOT" | awk 'NR==2 {print $4}')"
FREE_GB=$((FREE_KB / 1024 / 1024))
if [ "$FREE_GB" -ge 30 ]; then
  ok "Free disk space: ${FREE_GB} GB (30+ GB recommended)"
elif [ "$FREE_GB" -ge 15 ]; then
  warn "Free disk space: ${FREE_GB} GB; 30-50 GB is recommended for full builds"
else
  fail "Free disk space: ${FREE_GB} GB; at least 15 GB is required"
fi

TOTAL_MEM_KB="$(awk '/MemTotal/ {print $2; exit}' /proc/meminfo 2>/dev/null || echo 0)"
TOTAL_MEM_MB=$((TOTAL_MEM_KB / 1024))
if [ "$TOTAL_MEM_MB" -ge 8192 ]; then
  ok "System RAM: ${TOTAL_MEM_MB} MB"
elif [ "$TOTAL_MEM_MB" -ge 4096 ]; then
  warn "System RAM: ${TOTAL_MEM_MB} MB; 8 GB is recommended"
elif [ "$TOTAL_MEM_MB" -gt 0 ]; then
  warn "System RAM: ${TOTAL_MEM_MB} MB; builds may be unstable under memory pressure"
fi

CPU_COUNT="$(nproc 2>/dev/null || echo 1)"
if [ "$CPU_COUNT" -ge 4 ]; then
  ok "CPU threads available: $CPU_COUNT"
else
  warn "CPU threads available: $CPU_COUNT; 4+ recommended"
fi

echo
echo "==> Build pipeline artifacts"
check_artifact() {
  local path="$1"
  local desc="$2"
  if [ -e "$path" ]; then
    printf "  \033[1;32m[READY]\033[0m %s\n" "$desc"
  else
    printf "  \033[1;34m[PENDING]\033[0m %s\n" "$desc"
  fi
}

check_artifact "$SHREEOS_TOOLS/bin/$SHREEOS_TARGET_TRIPLET-gcc" "Cross-toolchain GCC"
check_artifact "$SHREEOS_SYSROOT/usr/include/stdio.h" "Target sysroot (glibc)"
check_artifact "$SHREEOS_BUILD_DIR/build-kernel/arch/x86/boot/bzImage" "Linux kernel bzImage"
check_artifact "$REPO_ROOT/pkgmanager/src/lpm" "LPM package manager"
check_artifact "$REPO_ROOT/init/src/init" "Init supervisor"
check_artifact "$REPO_ROOT/hardware/shreed" "Hardware daemon"
check_artifact "$SHREEOS_STAGE_ROOT" "Root filesystem staging"
check_artifact "$SHREEOS_OUT" "Output directory"

echo
echo "==> Target desktop graphics readiness"
if bash "$SCRIPT_DIR/graphics-readiness.sh"; then
  :
else
  warn "Unable to determine target graphical SDK readiness"
fi

echo
echo "========================================================"
if [ "$ERRORS" -eq 0 ]; then
  echo " Doctor Status: PASS ($ERRORS errors, $WARNINGS warnings)"
  echo " Host environment is ready for supported ShreeOS build stages."
  exit 0
fi

echo " Doctor Status: FAILED ($ERRORS errors, $WARNINGS warnings)"
echo " Fix required host checks and re-run 'make doctor'."
exit 1
