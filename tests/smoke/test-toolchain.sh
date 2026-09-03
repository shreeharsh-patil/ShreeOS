#!/usr/bin/env bash
# test-toolchain.sh — Smoke test for the cross-compilation toolchain
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$PROJECT_ROOT/build.conf"
source "$PROJECT_ROOT/scripts/common.sh"

lumen_step "Smoke testing cross-compilation toolchain"

CC="${LUMEN_TOOLS}/bin/${LUMEN_TARGET_TRIPLET}-gcc"
TESTDIR=$(mktemp -d)
trap 'rm -rf "$TESTDIR"' EXIT

# 1. Verify cross-compiler exists
if [ ! -x "$CC" ]; then
  lumen_die "Cross-compiler not found at ${CC}"
fi
lumen_ok "Cross-compiler found: ${CC}"

# 2. Check compiler version
CC_VERSION=$("$CC" --version 2>&1 | head -1)
lumen_ok "Compiler version: ${CC_VERSION}"

# 3. Compile static hello-world
cat > "${TESTDIR}/hello.c" << 'EOF'
#include <stdio.h>
int main(void) {
  printf("ShreeOS toolchain OK\n");
  return 0;
}
EOF

"$CC" -static "${TESTDIR}/hello.c" -o "${TESTDIR}/hello"
lumen_ok "Static hello-world compiled"

# 4. Verify binary format
BINARY_FORMAT=$(file "${TESTDIR}/hello")
echo "  Binary format: ${BINARY_FORMAT}"

if ! echo "$BINARY_FORMAT" | grep -qE "ELF.*(x86-64|80386)"; then
  lumen_die "Binary format not recognized as ELF x86_64: ${BINARY_FORMAT}"
fi
lumen_ok "Binary format verified: ELF x86_64"

# 5. Check static linking
if ldd "${TESTDIR}/hello" 2>&1 | grep -q "not a dynamic executable"; then
  lumen_ok "Binary is statically linked (no dynamic dependencies)"
else
  lumen_warn "Binary is dynamically linked (unexpected for -static flag)"
fi

# 6. Execute the binary
if file "${TESTDIR}/hello" | grep -q "x86-64"; then
  OUTPUT=$("${TESTDIR}/hello")
  echo "  Output: ${OUTPUT}"
  if [ "$OUTPUT" = "ShreeOS toolchain OK" ]; then
    lumen_ok "Binary executed and produced correct output"
  else
    lumen_die "Unexpected output: ${OUTPUT}"
  fi
else
  lumen_warn "Cannot execute non-x86_64 binary natively (cross-compilation target differs from host)"
  echo "  Skipping runtime test — use QEMU user mode on CI"
fi

echo ""
lumen_ok "=== TOOLCHAIN SMOKE TEST PASSED ==="
echo "  Compiler: ${CC}"
echo "  Version:  ${CC_VERSION}"
echo "  Binary:   ${TESTDIR}/hello"
