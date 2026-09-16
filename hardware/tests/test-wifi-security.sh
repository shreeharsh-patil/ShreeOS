#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
backend="$root/scripts/shree-wifi"
grep -q '^umask 077' "$backend"
grep -q 'chmod 600' "$backend"
grep -q '#psk=' "$backend"
grep -q 'validate_ssid' "$backend"
grep -q 'scan_ssid=1' "$backend"
grep -q 'Wi-Fi: Not available' "$backend"
wpa_build_script="$(find "$root/base-system/scripts" -maxdepth 1 -type f -name '*-wpa-supplicant.sh' -print -quit)"
[ -n "$wpa_build_script" ]
grep -q 'wpa_supplicant' "$wpa_build_script"
echo 'PASS: Wi-Fi credentials and unavailable adapters are handled safely'
