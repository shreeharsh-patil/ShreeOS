#!/bin/sh
set -eu

[ -n "${interface:-}" ] || exit 1
resolv_conf="${resolv_conf:-/etc/resolv.conf}"

case "${1:-}" in
  deconfig)
    /usr/bin/ip address flush dev "$interface"
    /usr/bin/ip link set "$interface" up
    ;;
  bound|renew)
    # BusyBox udhcpc exports these variables only for bound/renew events.
    # shellcheck disable=SC2154
    [ -n "${ip:-}" ] && [ -n "${subnet:-}" ] || exit 1
    /usr/bin/ip address replace "${ip}/${subnet}" dev "$interface"
    for router in ${router:-}; do
      /usr/bin/ip route replace default via "$router" dev "$interface"
    done
    temporary="${resolv_conf}.tmp"
    : > "$temporary"
    for nameserver in ${dns:-}; do
      printf 'nameserver %s\n' "$nameserver" >> "$temporary"
    done
    chmod 0644 "$temporary"
    mv -f "$temporary" "$resolv_conf"
    ;;
  *)
    exit 1
    ;;
esac
