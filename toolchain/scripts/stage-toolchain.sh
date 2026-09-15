#!/usr/bin/env bash
# stage-toolchain.sh — Strip, manifest, and verify the completed toolchain
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

lumen_step "Staging toolchain — stripping debug symbols and generating manifest"

MANIFEST="${LUMEN_TOOLS}/MANIFEST.txt"

# Strip debug symbols from toolchain binaries
find "${LUMEN_TOOLS}" -type f -executable 2>/dev/null | while read -r f; do
  strip --strip-unneeded "$f" 2>/dev/null || true
done

# Populate sysroot with target runtime libraries (libstdc++, libgcc_s, libatomic)
mkdir -p "${LUMEN_SYSROOT}/usr/lib64" "${LUMEN_SYSROOT}/usr/lib"
for libdir in "${LUMEN_TOOLS}/${LUMEN_TARGET_TRIPLET}/lib64" "${LUMEN_TOOLS}/${LUMEN_TARGET_TRIPLET}/lib"; do
  if [ -d "$libdir" ]; then
    cp -d -p "$libdir"/libstdc++* "${LUMEN_SYSROOT}/usr/lib64/" 2>/dev/null || true
    cp -d -p "$libdir"/libgcc_s* "${LUMEN_SYSROOT}/usr/lib64/" 2>/dev/null || true
    cp -d -p "$libdir"/libatomic* "${LUMEN_SYSROOT}/usr/lib64/" 2>/dev/null || true
    cp -d -p "$libdir"/libstdc++* "${LUMEN_SYSROOT}/usr/lib/" 2>/dev/null || true
    cp -d -p "$libdir"/libgcc_s* "${LUMEN_SYSROOT}/usr/lib/" 2>/dev/null || true
    cp -d -p "$libdir"/libatomic* "${LUMEN_SYSROOT}/usr/lib/" 2>/dev/null || true
  fi
done

# Generate manifest
{
  echo "ShreeOS Cross-Compilation Toolchain Manifest"
  echo "Generated: $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
  echo "Target:    ${LUMEN_TARGET_TRIPLET}"
  echo "Binutils:  ${VER_BINUTILS}"
  echo "GCC:       ${VER_GCC}"
  echo "glibc:     ${VER_GLIBC}"
  echo "Kernel:    ${VER_LINUX_KERNEL}"
  echo ""
  echo "=== File Listing ==="
  find "${LUMEN_TOOLS}" -type f | sort
} > "$MANIFEST"

echo ""
echo "Toolchain installed at: ${LUMEN_TOOLS}"
echo "Manifest:              ${MANIFEST}"
echo "Key binaries:"
ls -lh "${LUMEN_TOOLS}/bin/" 2>/dev/null | head -20

lumen_ok "Toolchain staged successfully"
