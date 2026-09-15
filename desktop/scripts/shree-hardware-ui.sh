#!/usr/bin/env bash
# Lightweight keyboard-first live pages for the existing dmenu/ST desktop.
set -u
SHREECTL="${SHREECTL:-shreectl}"
SHREEDCTL="${SHREEDCTL:-shreedctl}"

backend() {
  "$@" 2>&1 || printf '%s\n' 'Not available (shreed unavailable or restarting)'
}

render_page() {
  case "$1" in
    wifi)
      backend "$SHREECTL" wifi status --json
      printf '\nNearby networks:\n'
      backend "$SHREECTL" wifi list --json
      ;;
    ethernet) backend "$SHREEDCTL" ethernet --json ;;
    bluetooth)
      backend "$SHREECTL" bluetooth status --json
      backend "$SHREECTL" bluetooth devices --json
      ;;
    audio)
      backend "$SHREECTL" audio status --json
      backend "$SHREECTL" audio devices --json
      ;;
    battery)
      backend "$SHREECTL" battery --json
      backend "$SHREECTL" power --json
      ;;
    brightness) backend "$SHREECTL" brightness --json ;;
    storage) backend "$SHREEDCTL" disks --json ;;
    hardware) backend "$SHREEDCTL" hardware --json ;;
    drivers)
      backend "$SHREEDCTL" drivers --json
      backend "$SHREEDCTL" drivers_missing --json
      backend "$SHREEDCTL" firmware --json
      ;;
    diagnose) backend "$SHREEDCTL" diagnose --json ;;
  esac
}

show_live() {
  local title="$1" page="$2" key
  while :; do
    clear
    printf '=== %s ===\n\n' "$title"
    render_page "$page"
    printf '\nAutomatically refreshing while hardware state changes arrive. [r] Refresh [q] Close\n'
    key=""
    read -r -t 2 -n 1 key || true
    [ "$key" = q ] && exit 0
  done
}

case "${1:-hardware}" in
  wifi) show_live 'Wi-Fi' wifi ;;
  ethernet) show_live 'Ethernet' ethernet ;;
  bluetooth) show_live 'Bluetooth' bluetooth ;;
  audio) show_live 'Audio' audio ;;
  battery) show_live 'Battery and Power' battery ;;
  brightness) show_live 'Brightness' brightness ;;
  storage) show_live 'Storage' storage ;;
  hardware) show_live 'Hardware' hardware ;;
  drivers) show_live 'Drivers and Firmware' drivers ;;
  diagnose) show_live 'Hardware Diagnostics (read-only)' diagnose ;;
  wifi-connect)
    read -r -p 'SSID: ' ssid
    [ -n "$ssid" ] && exec "$SHREECTL" wifi connect "$ssid"
    ;;
  volume)
    read -r -p 'Volume (0-100): ' value
    [[ "$value" =~ ^([0-9]|[1-9][0-9]|100)$ ]] && exec "$SHREECTL" audio volume "$value"
    ;;
  brightness-set)
    read -r -p 'Brightness (0-100): ' value
    [[ "$value" =~ ^([0-9]|[1-9][0-9]|100)$ ]] && exec "$SHREECTL" brightness "$value"
    ;;
  *) printf 'Not available\n'; exit 2 ;;
esac
