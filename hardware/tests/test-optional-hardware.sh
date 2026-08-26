#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
for helper in shree-bluetooth shree-audio shree-powerctl; do bash -n "$root/scripts/$helper"; done
grep -q '/sys/class/power_supply' "$root/scripts/shree-powerctl"
grep -q '/sys/class/backlight' "$root/scripts/shree-powerctl"
grep -q 'bluetoothctl' "$root/scripts/shree-bluetooth"
grep -q 'amixer' "$root/scripts/shree-audio"
grep -q '0-100' "$root/scripts/shree-audio"
echo 'PASS: optional Bluetooth, audio, battery, and brightness modules are guarded'
