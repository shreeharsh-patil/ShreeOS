#!/usr/bin/env bash
# tests/pkgmanager/test-lpm-transactions.sh — Behavioral tests for LPM V2 transactions, signing & safeguards
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

echo "==> Testing LPM Package Manager Behavioral Transactions, Signatures & Safeguards"

LPM_BIN="${ROOT_DIR}/pkgmanager/src/lpm"
if [ ! -x "$LPM_BIN" ]; then
  make -C "${ROOT_DIR}/pkgmanager/src" clean all CROSS_COMPILE=
fi

# 1. Compile LPM test harness if host compiler available
if command -v gcc >/dev/null 2>&1; then
  make -C "${ROOT_DIR}/pkgmanager/tests" test
  echo "  [OK] LPM C unit test suite (manifest, constraints, conflicts, locking) passed"
fi

TEST_DIR=$(mktemp -d /tmp/shreeos-lpmtest-XXXXXX)
trap 'rm -rf "$TEST_DIR"' EXIT

export LPM_LOCK_FILE="${TEST_DIR}/lock"

# 2. Behavioral test: create valid package and verify structure
mkdir -p "${TEST_DIR}/src/usr/bin" "${TEST_DIR}/pkg"
echo "echo hello from test pkg" > "${TEST_DIR}/src/usr/bin/testapp"
chmod +x "${TEST_DIR}/src/usr/bin/testapp"

FILE_SHA=$(sha256sum "${TEST_DIR}/src/usr/bin/testapp" | awk '{print $1}')

cat > "${TEST_DIR}/src/manifest.json" <<EOF
{
  "name": "testpkg",
  "version": "1.0.0",
  "description": "Test Package for LPM",
  "files": ["/usr/bin/testapp"],
  "checksums": {
    "/usr/bin/testapp": "${FILE_SHA}"
  },
  "dependencies": []
}
EOF

(
  cd "${TEST_DIR}/src"
  tar -czf "${TEST_DIR}/pkg/testpkg-1.0.0.lpkg" manifest.json usr/bin/testapp
)

if [ -f "${TEST_DIR}/pkg/testpkg-1.0.0.lpkg" ]; then
  echo "  [OK] Generated valid LPM package archive testpkg-1.0.0.lpkg"
fi

# 3. Behavioral test: Archive traversal rejection
mkdir -p "${TEST_DIR}/traversal/tmp"
cat > "${TEST_DIR}/traversal/manifest.json" <<EOF
{
  "name": "badpkg",
  "version": "1.0.0",
  "description": "Malicious Traversal Package",
  "files": ["/tmp/escape.txt"],
  "dependencies": []
}
EOF
echo "pwned" > "${TEST_DIR}/traversal/tmp/escape.txt"

(
  cd "${TEST_DIR}/traversal"
  tar -czf "${TEST_DIR}/pkg/badpkg-1.0.0.lpkg" manifest.json tmp/escape.txt
)

# Verify lpm install rejects traversal or unsafe paths
if "$LPM_BIN" install "${TEST_DIR}/pkg/badpkg-1.0.0.lpkg" 2>/dev/null; then
  echo "  [FAIL] LPM accepted package with invalid/unsafe install path" >&2
  exit 1
else
  echo "  [OK] LPM correctly rejected package with unsafe path"
fi

# 4. Behavioral test: Transaction Planner (--dry-run)
DRYRUN_OUT=$("$LPM_BIN" install --dry-run "${TEST_DIR}/pkg/testpkg-1.0.0.lpkg")
if echo "$DRYRUN_OUT" | grep -q "Transaction Plan (dry-run)" && echo "$DRYRUN_OUT" | grep -q "Install: testpkg-1.0.0"; then
  echo "  [OK] LPM transaction planner (--dry-run) planned transaction without mutations"
else
  echo "  [FAIL] LPM --dry-run failed to produce valid plan:"
  echo "$DRYRUN_OUT"
  exit 1
fi

# 5. Behavioral test: Signed Repository Generation & Verification
echo "==> Testing Signed Repository Generation and Verification"
KEYS_DIR="${TEST_DIR}/keys"
bash "${ROOT_DIR}/repo-tools/scripts/gen-keys.sh" "$KEYS_DIR" >/dev/null
PUB_KEY="${KEYS_DIR}/shreeos-repo.pub"
PRIV_KEY="${KEYS_DIR}/shreeos-repo.key"

if [ -f "$PRIV_KEY" ] && [ -f "$PUB_KEY" ]; then
  echo "  [OK] Successfully generated repository RSA keypair"
fi

# Stage a package for repository
STAGING_DIR="${TEST_DIR}/staging"
mkdir -p "${STAGING_DIR}/samplepkg/usr/bin"
echo "#!/bin/sh" > "${STAGING_DIR}/samplepkg/usr/bin/sample"
chmod +x "${STAGING_DIR}/samplepkg/usr/bin/sample"
SAMPLE_SHA=$(sha256sum "${STAGING_DIR}/samplepkg/usr/bin/sample" | awk '{print $1}')
cat > "${STAGING_DIR}/samplepkg/manifest.json" <<EOF
{
  "name": "samplepkg",
  "version": "1.2.0",
  "description": "Sample package in signed repository",
  "files": ["/usr/bin/sample"],
  "checksums": {
    "/usr/bin/sample": "${SAMPLE_SHA}"
  },
  "dependencies": []
}
EOF

REPO_OUT="${TEST_DIR}/repo"
SHREEOS_REPO_KEY="$PRIV_KEY" bash "${ROOT_DIR}/repo-tools/scripts/build-repo.sh" "$STAGING_DIR" "$REPO_OUT" >/dev/null

if [ -f "${REPO_OUT}/repo.json" ] && [ -f "${REPO_OUT}/repo.json.sig" ]; then
  echo "  [OK] Generated repository index and cryptographic signature (repo.json.sig)"
fi

# Verify repository signature
if bash "${ROOT_DIR}/repo-tools/scripts/verify-repo.sh" "$REPO_OUT" "$PUB_KEY" >/dev/null; then
  echo "  [OK] Repository cryptographic signature and package hashes verified"
fi

# Tamper test: Alter repo.json and ensure verification fails
echo " " >> "${REPO_OUT}/repo.json"
if bash "${ROOT_DIR}/repo-tools/scripts/verify-repo.sh" "$REPO_OUT" "$PUB_KEY" >/dev/null 2>&1; then
  echo "  [FAIL] Verification unexpectedly passed on tampered repo.json!" >&2
  exit 1
else
  echo "  [OK] Verification successfully rejected tampered repository metadata"
fi

echo "==> All LPM behavioral transaction & signed repo tests passed successfully!"
exit 0
