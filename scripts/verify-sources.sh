#!/usr/bin/env bash
# scripts/verify-sources.sh — Verify source definitions, URLs, and downloaded archives
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

if [ -f "$REPO_ROOT/build.conf" ]; then
  source "$REPO_ROOT/build.conf"
fi
if [ -f "$REPO_ROOT/scripts/common.sh" ]; then
  source "$REPO_ROOT/scripts/common.sh"
fi

FETCH_MISSING=false
for arg in "$@"; do
  case "$arg" in
    --fetch|--download) FETCH_MISSING=true ;;
    --help|-h)
      echo "Usage: verify-sources.sh [--fetch|--download]"
      echo "Checks validity of all pinned checksums in *.list files."
      echo "Verifies integrity of existing archives in build/sources."
      echo "With --fetch, also downloads and verifies missing sources."
      exit 0
      ;;
  esac
done

SOURCES_DIR="${SHREEOS_SOURCES:-${REPO_ROOT}/build/sources}"
mkdir -p "$SOURCES_DIR"

TOTAL=0
VALID_DEFINITIONS=0
DOWNLOADED=0
VERIFIED=0
FAILED=0
MISSING=0

echo "========================================================"
echo " ShreeOS Pinned Upstream Sources Verification           "
echo "========================================================"
echo ""

verify_entry() {
  local comp="$1"
  local name="$2"
  local version="$3"
  local url="$4"
  local expected_sha="$5"

  TOTAL=$((TOTAL + 1))

  # 1. Format verification (valid 64-char hex string)
  if ! [[ "$expected_sha" =~ ^[a-fA-F0-9]{64}$ ]]; then
    printf "  \033[1;31m[INVALID]\033[0m [%-11s] %-16s %s (malformed SHA256)\n" "$comp" "$name" "$expected_sha"
    FAILED=$((FAILED + 1))
    return 1
  fi
  VALID_DEFINITIONS=$((VALID_DEFINITIONS + 1))

  local filename
  filename=$(basename "$url")
  local archive_path="${SOURCES_DIR}/${filename}"

  if [ ! -f "$archive_path" ] && [ "$FETCH_MISSING" = true ]; then
    printf "  \033[1;34m[FETCH]\033[0m   [%-11s] Downloading %s...\n" "$comp" "$filename"
    curl -fL --retry 2 -o "${archive_path}.tmp" "$url" && mv "${archive_path}.tmp" "$archive_path" || true
  fi

  if [ -f "$archive_path" ]; then
    DOWNLOADED=$((DOWNLOADED + 1))
    local actual_sha
    actual_sha=$(sha256sum "$archive_path" | awk '{print $1}')
    if [ "$actual_sha" = "$expected_sha" ]; then
      printf "  \033[1;32m[PASS]\033[0m    [%-11s] %-16s %-8s %s\n" "$comp" "$name" "$version" "$filename"
      VERIFIED=$((VERIFIED + 1))
    else
      printf "  \033[1;31m[MISMATCH]\033[0m[%-11s] %-16s %-8s %s\n" "$comp" "$name" "$version" "$filename"
      printf "            expected: %s\n            actual:   %s\n" "$expected_sha" "$actual_sha"
      FAILED=$((FAILED + 1))
    fi
  else
    printf "  \033[1;33m[UNCACHED]\033[0m[%-11s] %-16s %-8s %s (SHA: %.12s...)\n" "$comp" "$name" "$version" "$filename" "$expected_sha"
    MISSING=$((MISSING + 1))
  fi
}

echo "==> Verifying Toolchain Pinned Sources:"
if [ -f "${REPO_ROOT}/toolchain/scripts/sources.list" ]; then
  # Sourced variables
  (
    # shellcheck disable=SC1091
    source "${REPO_ROOT}/toolchain/scripts/sources.list"
    verify_entry "toolchain" "binutils" "${VER_BINUTILS:-2.43.1}" "$BINUTILS_URL" "$BINUTILS_SHA256"
    verify_entry "toolchain" "gcc" "${VER_GCC:-14.2.0}" "$GCC_URL" "$GCC_SHA256"
    verify_entry "toolchain" "glibc" "${VER_GLIBC:-2.40}" "$GLIBC_URL" "$GLIBC_SHA256"
    verify_entry "toolchain" "linux-headers" "${VER_LINUX_KERNEL:-6.18}" "$KERNEL_URL" "$KERNEL_SHA256"
  )
fi

echo ""
echo "==> Verifying Kernel Pinned Sources:"
if [ -f "${REPO_ROOT}/kernel/sources.list" ]; then
  (
    # shellcheck disable=SC1091
    source "${REPO_ROOT}/kernel/sources.list"
    verify_entry "kernel" "linux" "${VER_LINUX_KERNEL:-6.18}" "$KERNEL_URL" "$KERNEL_SHA256"
  )
fi

echo ""
echo "==> Verifying Base System Pinned Sources (packages.list):"
if [ -f "${REPO_ROOT}/base-system/packages.list" ]; then
  while IFS=$'\t' read -r name ver url sha || [ -n "$name" ]; do
    [[ "$name" =~ ^#.*$ ]] && continue
    [ -z "$name" ] && continue
    verify_entry "base-system" "$name" "$ver" "$url" "$sha"
  done < "${REPO_ROOT}/base-system/packages.list"
fi

echo ""
echo "==> Verifying Desktop Suite Pinned Sources:"
if [ -f "${REPO_ROOT}/desktop/wm/sources.list" ]; then
  (
    # shellcheck disable=SC1091
    source "${REPO_ROOT}/desktop/wm/sources.list"
    verify_entry "desktop" "dwm" "6.5" "$DWM_URL" "$DWM_SHA256"
    verify_entry "desktop" "st" "0.9.2" "$ST_URL" "$ST_SHA256"
    verify_entry "desktop" "dmenu" "5.3" "$DMENU_URL" "$DMENU_SHA256"
  )
fi

echo ""
echo "========================================================"
echo " Source Verification Summary:"
echo "   Total definitions checked: $TOTAL"
echo "   Valid hash definitions:   $VALID_DEFINITIONS"
echo "   Locally cached archives:  $DOWNLOADED"
echo "   Checksums verified:       $VERIFIED"
echo "   Uncached archives:        $MISSING"
echo "   Integrity failures:       $FAILED"
echo "========================================================"

if [ "$FAILED" -gt 0 ]; then
  echo " Verification FAILED: $FAILED corrupted or invalid source entries."
  exit 1
else
  echo " Verification SUCCESS: All pinned source definitions are cryptographically valid."
  exit 0
fi
