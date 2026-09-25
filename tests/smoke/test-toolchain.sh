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
if (ldd "${TESTDIR}/hello" 2>&1 || true) | grep -q "not a dynamic executable"; then
  lumen_ok "Binary is statically linked (no dynamic dependencies)"
else
  lumen_die "Binary is not statically linked (unexpected for -static flag)"
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

# 7. Verify C++ cross-compiler and libstdc++
CXX="${LUMEN_TOOLS}/bin/${LUMEN_TARGET_TRIPLET}-g++"
if [ ! -x "$CXX" ]; then
  lumen_die "C++ cross-compiler not found at ${CXX}"
fi
lumen_ok "C++ cross-compiler found: ${CXX}"

cat > "${TESTDIR}/hello.cpp" << 'EOF'
#include <iostream>

int main() {
  std::cout << "ShreeOS C++ toolchain OK\n";
  return 0;
}
EOF

"$CXX" -static "${TESTDIR}/hello.cpp" -o "${TESTDIR}/hello_cpp"
lumen_ok "Static C++ hello-world compiled"

if file "${TESTDIR}/hello_cpp" | grep -q "x86-64"; then
  OUTPUT_CPP=$("${TESTDIR}/hello_cpp")
  echo "  C++ Output: ${OUTPUT_CPP}"
  if [ "$OUTPUT_CPP" = "ShreeOS C++ toolchain OK" ]; then
    lumen_ok "C++ binary executed and produced correct output"
  else
    lumen_die "Unexpected C++ output: ${OUTPUT_CPP}"
  fi
fi

# 8. Verify dynamic C linking
"$CC" "${TESTDIR}/hello.c" -o "${TESTDIR}/hello_dyn"
if ! readelf -d "${TESTDIR}/hello_dyn" | grep -q "libc\.so"; then
  lumen_die "Dynamic C binary does not link against libc.so"
fi
lumen_ok "Dynamic C binary compiled and verified against sysroot libc"

# 9. Verify dynamic C++ linking
"$CXX" "${TESTDIR}/hello.cpp" -o "${TESTDIR}/hello_cpp_dyn"
if ! readelf -d "${TESTDIR}/hello_cpp_dyn" | grep -q "libstdc++\.so"; then
  lumen_die "Dynamic C++ binary does not link against libstdc++.so"
fi
lumen_ok "Dynamic C++ binary compiled and verified against libstdc++.so"

echo ""
lumen_ok "=== TOOLCHAIN SMOKE TEST PASSED ==="
echo "  C Compiler:   ${CC}"
echo "  C++ Compiler: ${CXX}"
echo "  Version:      ${CC_VERSION}"

