#!/usr/bin/env bash
set -euo pipefail

LUMEN_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LUMEN_BASE_DIR="$(cd "$LUMEN_SCRIPT_DIR/.." && pwd)"
LUMEN_ROOT_DIR="$(cd "$LUMEN_BASE_DIR/.." && pwd)"

source "$LUMEN_ROOT_DIR/build.conf"
source "$LUMEN_ROOT_DIR/scripts/common.sh"

export PATH="$LUMEN_TOOLS/bin:$LUMEN_STAGE_ROOT/usr/bin:${PATH}"
