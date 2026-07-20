#!/usr/bin/env bash
# tests/smoke/run-all.sh — fast, no-build sanity checks.
# Run from anywhere: bash tests/smoke/run-all.sh

set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${REPO_ROOT}"

pass=0
fail=0

check() {
  local desc="$1"; shift
  if "$@" >/dev/null 2>&1; then
    printf '  [ok]   %s\n' "${desc}"
    pass=$((pass + 1))
  else
    printf '  [FAIL] %s\n' "${desc}"
    fail=$((fail + 1))
  fi
}

echo "== Milestone 1 smoke tests: repository scaffold =="

check "build.conf is valid bash"           bash -n build.conf
check "scripts/common.sh is valid bash"    bash -n scripts/common.sh
check "build.conf sources cleanly"         bash -c "source build.conf"

for d in toolchain base-system kernel rootfs init bootloader \
         pkgmanager repo-tools installer iso-builder desktop \
         branding update tests docs; do
  check "README.md exists in ${d}/"        test -f "${d}/README.md"
done

check "LICENSE exists"                     test -f LICENSE
check "ROADMAP.md exists"                  test -f docs/ROADMAP.md
check "ARCHITECTURE.md exists"             test -f docs/ARCHITECTURE.md

echo
echo "== Results: ${pass} passed, ${fail} failed =="
[[ "${fail}" -eq 0 ]]
