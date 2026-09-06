#!/usr/bin/env bash
# desktop/apps/shree-sysmon.sh — ShreeOS Native System Monitor
#
# Lightweight, native process and hardware resource monitor.

set -euo pipefail

run_monitor() {
  while true; do
    clear
    echo "┌────────────────────────────────────────────────────────────────────────────┐"
    echo "│                           ShreeOS System Monitor                           │"
    echo "└────────────────────────────────────────────────────────────────────────────┘"
    
    # 1. CPU & Memory Overview
    local load
    load=$(awk '{print $1", "$2", "$3}' /proc/loadavg 2>/dev/null || echo "0.0")
    local mem_total
    mem_total=$(awk '/MemTotal:/ {printf "%.1f GB", $2/1024/1024}' /proc/meminfo 2>/dev/null || echo "4.0 GB")
    local mem_avail
    mem_avail=$(awk '/MemAvailable:/ {printf "%.1f GB", $2/1024/1024}' /proc/meminfo 2>/dev/null || echo "2.0 GB")
    
    echo "  Load Average (1m, 5m, 15m): ${load}"
    echo "  Memory: ${mem_avail} available / ${mem_total} total"
    echo ""
    echo "  [Top Active Processes by CPU / Memory]"
    echo "  ──────────────────────────────────────────────────────────────────────────"
    printf "  %-8s %-10s %-8s %-8s %s\n" "PID" "USER" "%CPU" "%MEM" "COMMAND"
    echo "  ──────────────────────────────────────────────────────────────────────────"
    
    ps -eo pid,user,%cpu,%mem,comm --sort=-%cpu 2>/dev/null | head -n 12 | tail -n +2 | while read -r line; do
      printf "  %s\n" "$line"
    done

    echo "  ──────────────────────────────────────────────────────────────────────────"
    echo "  [k] Kill Process   [r] Refresh Now   [q] Exit"
    echo ""
    
    read -r -t 3 -n 1 KEY || true
    if [ "$KEY" = "q" ] || [ "$KEY" = "Q" ]; then
      break
    elif [ "$KEY" = "k" ] || [ "$KEY" = "K" ]; then
      read -r -p "  Enter PID to terminate: " TARGET_PID
      if [ -n "$TARGET_PID" ] && kill -15 "$TARGET_PID" 2>/dev/null; then
        echo "  Sent SIGTERM to PID ${TARGET_PID}"
        sleep 1
      else
        echo "  Failed to terminate PID ${TARGET_PID}"
        sleep 1
      fi
    fi
  done
}

if [ -t 0 ]; then
  run_monitor
else
  st -g 85x24 -t "System Monitor" -e "$0" &
fi
