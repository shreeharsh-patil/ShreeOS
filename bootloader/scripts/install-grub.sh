#!/usr/bin/env bash
# bootloader/scripts/install-grub.sh — Unified GRUB2 installer dispatcher
#
# Delegates to install-grub-iso.sh for ISO staging directories,
# or install-grub-disk.sh when target disk is provided.
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec bash "${SCRIPT_DIR}/install-grub-iso.sh" "$@"
