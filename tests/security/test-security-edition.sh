#!/usr/bin/env bash
# Validate the ShreeOS security edition source and, when built, staged payload.
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
SOURCE_ONLY=0
[ "${1:-}" = "--source-only" ] && SOURCE_ONLY=1

fail() { echo "[FAIL] $*" >&2; exit 1; }
ok() { echo "[OK] $*"; }

for file in \
  "$ROOT_DIR/base-system/profiles/security.list" \
  "$ROOT_DIR/security/scripts/shree-audit" \
  "$ROOT_DIR/security/scripts/shree-netdiag" \
  "$ROOT_DIR/security/README.md"; do
  [ -s "$file" ] || fail "missing security-edition source: ${file#$ROOT_DIR/}"
done

bash -n "$ROOT_DIR/security/scripts/shree-audit"
bash -n "$ROOT_DIR/security/scripts/shree-netdiag"
grep -Fq '@desktop' "$ROOT_DIR/base-system/profiles/security.list" || fail "security profile must inherit desktop"
grep -Fq 'security' "$ROOT_DIR/Makefile" || fail "central build does not advertise the security profile"
ok "Security edition sources and shell syntax are valid"

if [ "$SOURCE_ONLY" = "1" ]; then
  exit 0
fi

source "$ROOT_DIR/build.conf"
for exe in usr/bin/shree-audit usr/bin/shree-netdiag; do
  [ -x "$SHREEOS_STAGE_ROOT/$exe" ] || fail "security rootfs command missing: /$exe"
done
[ -s "$SHREEOS_STAGE_ROOT/etc/shreeos/security-edition" ] || fail "security edition marker missing"
grep -Fxq 'security' "$SHREEOS_STAGE_ROOT/etc/shreeos/security-edition" || fail "security edition marker has unexpected content"
[ -x "$SHREEOS_STAGE_ROOT/usr/bin/install-shreeos" ] || fail "graphical installer launcher missing"
ok "Security rootfs contains diagnostics and installer launcher"
