#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
for file in desktop/apps/shree-settings desktop/apps/shree-control-center desktop/apps/shree-about desktop/scripts/shree-hardware-ui.sh; do bash -n "$root/$file"; done
grep -q 'shreedctl hardware --json' "$root/desktop/apps/shree-about"
grep -q 'shree-hardware-ui' "$root/desktop/apps/shree-settings"
grep -q 'shreectl wifi status --json' "$root/desktop/apps/shree-control-center"
grep -q 'drivers_missing --json' "$root/desktop/scripts/shree-hardware-ui.sh"
echo 'PASS: desktop views use live ShreeOS backend commands'
