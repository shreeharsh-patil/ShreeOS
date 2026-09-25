#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
network_config="$root/init/services/20-network.conf"
mdev_config="$root/init/services/05-mdev.conf"

[ -s "$mdev_config" ]
grep -q '^critical=true$' "$mdev_config"
grep -q '/sbin/mdev' "$mdev_config"
grep -q 'udhcpc -n -q -T 3 -t 3' "$network_config"
grep -q 'udhcpc.*|| echo' "$network_config"
grep -q 'type.*= 1' "$network_config"
grep -q 'wireless' "$network_config"
grep -q 'phy80211' "$network_config"
grep -q '^after=hostname,mdev$' "$network_config"
if grep -Eq '(^|[[:space:]])(eth0|en0)[[:space:]"]' "$network_config"; then
  echo 'FAIL: network startup hardcodes an interface name' >&2
  exit 1
fi
echo 'PASS: mdev, dynamic Ethernet discovery, and non-fatal DHCP are configured'
