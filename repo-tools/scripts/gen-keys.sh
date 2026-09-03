#!/usr/bin/env bash
# repo-tools/scripts/gen-keys.sh — Generate repository signing keypair for ShreeOS
#
# Generates a 4096-bit RSA keypair.
# The private key must be kept secure outside the public git repository.
#
# Usage:
#   bash repo-tools/scripts/gen-keys.sh [output-dir]
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

KEY_DIR="${1:-${REPO_ROOT}/build/keys}"
mkdir -p "$KEY_DIR"
chmod 0700 "$KEY_DIR"

PRIV_KEY="${KEY_DIR}/shreeos-repo.key"
PUB_KEY="${KEY_DIR}/shreeos-repo.pub"

echo "==> Generating ShreeOS Package Repository Signing Keypair"
if [ -f "$PRIV_KEY" ]; then
  echo "  [WARN] Keypair already exists at ${PRIV_KEY}"
  echo "         Preserving existing keypair to prevent invalidating existing signatures."
  exit 0
fi

# Generate 4096-bit private key
openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:4096 -out "$PRIV_KEY" 2>/dev/null
chmod 0600 "$PRIV_KEY"

# Extract public key
openssl rsa -pubout -in "$PRIV_KEY" -out "$PUB_KEY" 2>/dev/null
chmod 0644 "$PUB_KEY"

echo "  [OK] Private key generated: ${PRIV_KEY} (mode 0600 - KEEP SECURE)"
echo "  [OK] Public key generated:  ${PUB_KEY} (mode 0644 - install to /etc/lpm/keys/)"
echo ""
echo "To sign repositories automatically, export:"
echo "  export SHREEOS_REPO_KEY=\"${PRIV_KEY}\""
