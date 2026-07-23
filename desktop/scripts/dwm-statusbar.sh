#!/bin/sh
# desktop/scripts/dwm-statusbar.sh — Statusbar metric updates for dwm
#
# Updates X11 root window name with CPU, memory, clock, and battery stats.
#

get_memory() {
  if [ -f /proc/meminfo ]; then
    total=$(awk '/MemTotal:/ {print $2}' /proc/meminfo)
    free=$(awk '/MemAvailable:/ {print $2}' /proc/meminfo)
    used=$(( (total - free) / 1024 ))
    echo "${used}MB"
  else
    echo "N/A"
  fi
}

get_cpu() {
  if [ -f /proc/loadavg ]; then
    awk '{print $1}' /proc/loadavg
  else
    echo "N/A"
  fi
}

get_battery() {
  if [ -d /sys/class/power_supply/BAT0 ]; then
    capacity=$(cat /sys/class/power_supply/BAT0/capacity 2>/dev/null || echo "100")
    status=$(cat /sys/class/power_supply/BAT0/status 2>/dev/null || echo "Discharging")
    echo "${capacity}% (${status})"
  else
    echo "AC"
  fi
}

get_time() {
  date +"%Y-%m-%d %H:%M:%S"
}

while true; do
  MEM=$(get_memory)
  CPU=$(get_cpu)
  BAT=$(get_battery)
  TIME=$(get_time)

  STATUS="RAM: ${MEM} | CPU: ${CPU} | BAT: ${BAT} | ${TIME}"

  if command -v xsetroot >/dev/null 2>&1; then
    xsetroot -name "${STATUS}"
  else
    echo "${STATUS}"
  fi

  sleep 2
done
