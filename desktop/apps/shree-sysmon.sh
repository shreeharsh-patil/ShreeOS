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
    
    local KEY=""
    read -r -t 3 -n 1 KEY || true
    if [ "$KEY" = "q" ] || [ "$KEY" = "Q" ]; then
      break
    elif [ "$KEY" = "k" ] || [ "$KEY" = "K" ]; then
      local TARGET_PID=""
      read -r -p "  Enter PID to terminate: " TARGET_PID
      if ! [[ "$TARGET_PID" =~ ^[0-9]+$ ]] || [ "$TARGET_PID" -le 1 ] || [ "$TARGET_PID" -eq "$$" ]; then
        echo "  Invalid or protected PID: ${TARGET_PID:-<empty>}"
        sleep 1
        continue
      fi
      if [ ! -d "/proc/$TARGET_PID" ]; then
        echo "  PID ${TARGET_PID} no longer exists"
        sleep 1
        continue
      fi

      local target_name
      target_name=$(ps -p "$TARGET_PID" -o comm= 2>/dev/null | head -n1 || true)
      local confirm=""
      read -r -p "  Terminate PID ${TARGET_PID} (${target_name:-unknown})? [y/N]: " confirm
      if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
        continue
      fi

      if kill -15 "$TARGET_PID" 2>/dev/null; then
        echo "  Sent SIGTERM to PID ${TARGET_PID}"
      else
        echo "  Failed to terminate PID ${TARGET_PID}"
      fi
      sleep 1
    fi
  done
}

if [ -t 0 ]; then
  run_monitor
else
  st -g 85x24 -t "System Monitor" -e "$0" &
fi
