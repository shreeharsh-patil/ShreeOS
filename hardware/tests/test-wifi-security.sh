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
grep -q 'wpa_supplicant' "$root/base-system/scripts/21-wpa-supplicant.sh"
echo 'PASS: Wi-Fi credentials and unavailable adapters are handled safely'
