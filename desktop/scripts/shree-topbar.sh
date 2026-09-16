#!/bin/sh
# desktop/scripts/shree-topbar.sh — Persistent top menu bar metric feed for ShreeOS
#
# Formats system metrics cleanly into the X11 root window name for the top bar.

get_mem() {
  if [ -f /proc/meminfo ]; then
    total=$(awk '/MemTotal:/ {print $2}' /proc/meminfo)
    avail=$(awk '/MemAvailable:/ {print $2}' /proc/meminfo)
    used_mb=$(( (total - avail) / 1024 ))
    echo "${used_mb}M"
  else
    echo "—"
  fi
}

get_cpu() {
  if [ -f /proc/loadavg ]; then
    awk '{print $1}' /proc/loadavg
  else
    echo "—"
  fi
}

get_battery() {
  if [ -d /sys/class/power_supply/BAT0 ]; then
    cap=$(cat /sys/class/power_supply/BAT0/capacity 2>/dev/null || echo "100")
    stat=$(cat /sys/class/power_supply/BAT0/status 2>/dev/null || echo "AC")
    if [ "$stat" = "Charging" ]; then
      echo "⚡${cap}%"
    else
      echo "${cap}%"
    fi
  else
    echo "AC"
  fi
}

get_net() {
  dev=$(ip route show default 2>/dev/null | awk '{print $5}' | head -n1 || echo "")
  if [ -n "$dev" ]; then
    case "$dev" in
      wl*|wifi*) echo "Wi-Fi" ;;
      eth*|en*)  echo "Ethernet" ;;
      *)         echo "Online" ;;
    esac
  else
    echo "Offline"
  fi
}

get_datetime() {
  date +"%a %b %d   %H:%M"
}

while true; do
  MEM=$(get_mem)
  CPU=$(get_cpu)
  BAT=$(get_battery)
  NET=$(get_net)
  DATETIME=$(get_datetime)

  STATUS="  Mem: ${MEM}  │  Load: ${CPU}  │  ${NET}  │  ${BAT}  │  ${DATETIME}  "

  if command -v xsetroot >/dev/null 2>&1; then
    xsetroot -name "${STATUS}"
  else
    echo "${STATUS}"
  fi

  sleep 2
done
