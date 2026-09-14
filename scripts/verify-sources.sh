#!/usr/bin/env bash
# Verify source definitions and cached/downloaded archives for ShreeOS.
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$REPO_ROOT/build.conf"
source "$REPO_ROOT/scripts/common.sh"

FETCH_MISSING=false
for arg in "$@"; do
  case "$arg" in
    --fetch|--download) FETCH_MISSING=true ;;
    --help|-h)
      echo "Usage: verify-sources.sh [--fetch|--download]"
      echo "Validates pinned SHA-256 definitions and verifies every cached archive."
      echo "With --fetch, all missing sources are downloaded and verified."
      exit 0
      ;;
    *) shreeos_die "Unknown option: $arg" ;;
  esac
done

SOURCES_DIR="${SHREEOS_SOURCES:-$REPO_ROOT/build/sources}"
mkdir -p "$SOURCES_DIR"

TOTAL=0
VALID_DEFINITIONS=0
DOWNLOADED=0
VERIFIED=0
FAILED=0
MISSING=0

verify_entry() {
  local comp="$1" name="$2" version="$3" url="$4" expected_sha="$5"
  TOTAL=$((TOTAL + 1))

  if [ -z "$url" ] || [[ "$url" != https://* ]]; then
    printf "  [INVALID] [%-11s] %-16s invalid or non-HTTPS URL: %s\n" "$comp" "$name" "$url"
    FAILED=$((FAILED + 1))
    return 0
  fi
  if ! [[ "$expected_sha" =~ ^[a-fA-F0-9]{64}$ ]]; then
    printf "  [INVALID] [%-11s] %-16s malformed SHA256: %s\n" "$comp" "$name" "$expected_sha"
    FAILED=$((FAILED + 1))
    return 0
  fi
  VALID_DEFINITIONS=$((VALID_DEFINITIONS + 1))

  local filename archive_path tmp_path
  filename="$(basename "${url%%\?*}")"
  [ -n "$filename" ] || {
    printf "  [INVALID] [%-11s] %-16s URL has no archive filename\n" "$comp" "$name"
    FAILED=$((FAILED + 1))
    return 0
  }
  archive_path="$SOURCES_DIR/$filename"
  tmp_path="$archive_path.tmp"

  if [ ! -f "$archive_path" ] && [ "$FETCH_MISSING" = true ]; then
    printf "  [FETCH]   [%-11s] %s\n" "$comp" "$filename"
    rm -f "$tmp_path"
    if curl -fL --retry 3 --retry-delay 2 --connect-timeout 20 -o "$tmp_path" "$url"; then
      mv "$tmp_path" "$archive_path"
    else
      rm -f "$tmp_path"
      printf "  [FAILED]  [%-11s] %-16s download failed\n" "$comp" "$name"
      FAILED=$((FAILED + 1))
      return 0
    fi
  fi

  if [ -f "$archive_path" ]; then
    DOWNLOADED=$((DOWNLOADED + 1))
    local actual_sha
    actual_sha="$(sha256sum "$archive_path" | awk '{print $1}')"
    if [ "$actual_sha" = "$expected_sha" ]; then
      printf "  [PASS]    [%-11s] %-16s %-8s %s\n" "$comp" "$name" "$version" "$filename"
      VERIFIED=$((VERIFIED + 1))
    else
      printf "  [MISMATCH][%-11s] %-16s %-8s %s\n" "$comp" "$name" "$version" "$filename"
      printf "            expected: %s\n            actual:   %s\n" "$expected_sha" "$actual_sha"
      FAILED=$((FAILED + 1))
    fi
  elif [ "$FETCH_MISSING" = true ]; then
    printf "  [FAILED]  [%-11s] %-16s missing after fetch\n" "$comp" "$name"
    FAILED=$((FAILED + 1))
  else
    printf "  [UNCACHED][%-11s] %-16s %-8s %s\n" "$comp" "$name" "$version" "$filename"
    MISSING=$((MISSING + 1))
  fi
}

echo "========================================================"
echo " ShreeOS Pinned Upstream Sources Verification"
echo "========================================================"

if [ -f "$REPO_ROOT/toolchain/scripts/sources.list" ]; then
  # shellcheck disable=SC1091
  source "$REPO_ROOT/toolchain/scripts/sources.list"
  verify_entry toolchain binutils "${VER_BINUTILS:-2.43.1}" "$BINUTILS_URL" "$BINUTILS_SHA256"
  verify_entry toolchain gcc "${VER_GCC:-14.2.0}" "$GCC_URL" "$GCC_SHA256"
  verify_entry toolchain glibc "${VER_GLIBC:-2.40}" "$GLIBC_URL" "$GLIBC_SHA256"
  verify_entry toolchain linux-headers "${VER_LINUX_KERNEL:-6.18}" "$KERNEL_URL" "$KERNEL_SHA256"
fi

if [ -f "$REPO_ROOT/kernel/sources.list" ]; then
  # shellcheck disable=SC1091
  source "$REPO_ROOT/kernel/sources.list"
  verify_entry kernel linux "${VER_LINUX_KERNEL:-6.18}" "$KERNEL_URL" "$KERNEL_SHA256"
fi

if [ -f "$REPO_ROOT/base-system/packages.list" ]; then
  while IFS=$'\t' read -r name ver url sha _rest || [ -n "${name:-}" ]; do
    [[ "${name:-}" =~ ^[[:space:]]*# ]] && continue
    [ -z "${name:-}" ] && continue
    verify_entry base-system "$name" "$ver" "$url" "$sha"
  done < "$REPO_ROOT/base-system/packages.list"
fi

if [ -f "$REPO_ROOT/desktop/wm/sources.list" ]; then
  # shellcheck disable=SC1091
  source "$REPO_ROOT/desktop/wm/sources.list"
  verify_entry desktop dwm 6.5 "$DWM_URL" "$DWM_SHA256"
  verify_entry desktop st 0.9.2 "$ST_URL" "$ST_SHA256"
  verify_entry desktop dmenu 5.3 "$DMENU_URL" "$DMENU_SHA256"
fi

echo
echo "========================================================"
echo " Source Verification Summary"
echo "   Definitions checked: $TOTAL"
echo "   Valid definitions:   $VALID_DEFINITIONS"
echo "   Cached/downloaded:   $DOWNLOADED"
echo "   Archives verified:   $VERIFIED"
echo "   Uncached:            $MISSING"
echo "   Failures:            $FAILED"
echo "========================================================"

if [ "$FAILED" -gt 0 ]; then
  shreeos_die "Source verification failed: $FAILED problem(s)"
fi
if [ "$FETCH_MISSING" = true ] && [ "$VERIFIED" -ne "$VALID_DEFINITIONS" ]; then
  shreeos_die "Fetch verification incomplete: verified $VERIFIED of $VALID_DEFINITIONS valid definition(s)"
fi

if [ "$MISSING" -gt 0 ]; then
  shreeos_ok "Pinned definitions are valid and cached archives verified; $MISSING source(s) are not cached."
else
  shreeos_ok "All pinned source archives verified successfully."
fi
