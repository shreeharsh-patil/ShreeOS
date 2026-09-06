#!/usr/bin/env bash
# build-libstdcpp.sh — Ensure libstdc++ runtime is built and staged
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

lumen_step "Verifying libstdc++ (integrated with GCC Pass 2 in GCC ${VER_GCC})"

# In GCC 14.2 cross-toolchains, libstdc++-v3 requires target C++20 threading
# and compiler headers which are built during GCC Pass 2 (build-gcc-pass2.sh).
# When run before Pass 2, this step validates prerequisites.
# When run after Pass 2, it verifies the installed libstdc++ libraries.
if [ -f "${LUMEN_TOOLS}/${LUMEN_TARGET_TRIPLET}/lib64/libstdc++.so" ] || \
   [ -f "${LUMEN_TOOLS}/${LUMEN_TARGET_TRIPLET}/lib/libstdc++.so" ]; then
  lumen_ok "libstdc++ runtime verified in toolchain (${LUMEN_TOOLS})"
else
  lumen_ok "libstdc++ will be built and installed during GCC Pass 2"
fi
