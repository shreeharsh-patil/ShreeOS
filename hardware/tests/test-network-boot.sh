#!/usr/bin/env bash
set -euo pipefail

config="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/init/services/20-network.conf"

# The DHCP client is intentionally best-effort: its failure must not make the
# non-critical boot service fail, and only Ethernet interfaces are selected.
grep -q 'dhcpcd -w -t 20' "$config"
grep -q 'udhcpc -n -q -T 3 -t 3' "$config"
grep -q 'udhcpc.*|| true' "$config"
grep -q 'type.*= 1' "$config"
echo 'PASS: DHCP failure is non-fatal and Ethernet-only'
