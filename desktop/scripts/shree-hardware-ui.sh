#!/usr/bin/env bash
# Lightweight keyboard-first live pages for the existing dmenu/ST desktop.
set -u
SHREECTL="${SHREECTL:-shreectl}"
SHREEDCTL="${SHREEDCTL:-shreedctl}"
backend() { "$@" 2>&1 || printf '%s\n' 'Not available (shreed unavailable or restarting)'; }
show_live() { local title="$1" command="$2" key; while :; do clear; printf '=== %s ===\n\n' "$title"; eval "$command"; printf '\nAutomatically refreshing while shreed events or state changes arrive. [r] Refresh [q] Close\n'; key=""; read -r -t 2 -n 1 key || true; [ "$key" = q ] && exit 0; done; }
case "${1:-hardware}" in
 wifi) show_live 'Wi-Fi' 'backend "$SHREECTL" wifi status --json; printf "\nNearby networks:\n"; backend "$SHREECTL" wifi list --json' ;;
 ethernet) show_live 'Ethernet' 'backend "$SHREEDCTL" ethernet --json' ;;
 bluetooth) show_live 'Bluetooth' 'backend "$SHREECTL" bluetooth status --json; backend "$SHREECTL" bluetooth devices --json' ;;
 audio) show_live 'Audio' 'backend "$SHREECTL" audio status --json; backend "$SHREECTL" audio devices --json' ;;
 battery) show_live 'Battery and Power' 'backend "$SHREECTL" battery --json; backend "$SHREECTL" power --json' ;;
 brightness) show_live 'Brightness' 'backend "$SHREECTL" brightness --json' ;;
 storage) show_live 'Storage' 'backend "$SHREEDCTL" disks --json' ;;
 hardware) show_live 'Hardware' 'backend "$SHREEDCTL" hardware --json' ;;
 drivers) show_live 'Drivers and Firmware' 'backend "$SHREEDCTL" drivers --json; backend "$SHREEDCTL" drivers_missing --json; backend "$SHREEDCTL" firmware --json' ;;
 diagnose) show_live 'Hardware Diagnostics (read-only)' 'backend "$SHREEDCTL" diagnose --json' ;;
 wifi-connect) read -r -p 'SSID: ' ssid; [ -n "$ssid" ] && exec "$SHREECTL" wifi connect "$ssid" ;;
 volume) read -r -p 'Volume (0-100): ' value; [[ "$value" =~ ^([0-9]|[1-9][0-9]|100)$ ]] && exec "$SHREECTL" audio volume "$value" ;;
 brightness-set) read -r -p 'Brightness (0-100): ' value; [[ "$value" =~ ^([0-9]|[1-9][0-9]|100)$ ]] && exec "$SHREECTL" brightness "$value" ;;
 *) printf 'Not available\n'; exit 2 ;;
esac
