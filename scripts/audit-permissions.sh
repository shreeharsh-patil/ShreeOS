#!/usr/bin/env bash
# scripts/audit-permissions.sh — Audit and enforce repository file permissions
#
# Enforces:
#  - 755 (executable) for executable scripts and binaries
#  - 644 (non-executable) for source files, documentation, configs, and assets
#
# Usage:
#   bash scripts/audit-permissions.sh         # check only (fails if violations exist)
#   bash scripts/audit-permissions.sh --fix   # fix violations in git index and working tree

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${REPO_ROOT}"

FIX_MODE=false
if [[ "${1:-}" == "--fix" ]]; then
  FIX_MODE=true
fi

errors=0

while IFS=$'\t' read -r mode_type_hash file; do
  mode=$(echo "$mode_type_hash" | awk '{print $1}')
  
  if [ ! -f "$file" ]; then
    continue
  fi

  ext="${file##*.}"
  basename_file="$(basename "$file")"
  
  is_always_644=false
  case "$basename_file" in
    Makefile|fstab|os-release|resolv.conf|.keep|*.list|build.conf)
      is_always_644=true
      ;;
  esac
  case "$ext" in
    md|c|h|conf|list|json|txt|yml|yaml|patch|keep)
      is_always_644=true
      ;;
  esac

  should_be_exec=false
  if [ "$is_always_644" = false ]; then
    if [[ "$file" == scripts/shree* ]] || [[ "$file" == *.sh ]]; then
      should_be_exec=true
    else
      first_bytes=$(head -c 2 "$file" 2>/dev/null || true)
      if [ "$first_bytes" = "#!" ]; then
        should_be_exec=true
      fi
    fi
  fi

  if [ "$should_be_exec" = true ]; then
    if [ "$mode" != "100755" ]; then
      echo "[PERM ERROR] Expected 755, found $mode: $file"
      errors=$((errors + 1))
      if [ "$FIX_MODE" = true ]; then
        git update-index --chmod=+x "$file"
        chmod 755 "$file" 2>/dev/null || true
        echo "  -> fixed: set 755 for $file"
      fi
    fi
  else
    if [ "$mode" != "100644" ]; then
      echo "[PERM ERROR] Expected 644, found $mode: $file"
      errors=$((errors + 1))
      if [ "$FIX_MODE" = true ]; then
        git update-index --chmod=-x "$file"
        chmod 644 "$file" 2>/dev/null || true
        echo "  -> fixed: set 644 for $file"
      fi
    fi
  fi
done < <(git ls-files --stage)

if [ "$errors" -gt 0 ]; then
  if [ "$FIX_MODE" = true ]; then
    echo "Fixed $errors permission violation(s)."
  else
    echo "Found $errors permission violation(s). Run with --fix to resolve."
    exit 1
  fi
else
  echo "All file permissions are correct."
fi
