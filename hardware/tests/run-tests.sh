#!/usr/bin/env bash
# run-tests.sh — Build and run native shreed daemon tests

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
make -C "${SCRIPT_DIR}/.." CROSS_COMPILE= test
