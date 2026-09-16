#!/usr/bin/env bash
# installer/scripts/shree-recovery.sh — ShreeOS Emergency Recovery Environment
#
# Terminal-based disaster recovery suite accessible via GRUB Single-User / Recovery mode.

set -euo pipefail

clear
echo "┌────────────────────────────────────────────────────────────────────────────┐"
echo "│                      ShreeOS Emergency Recovery Console                    │"
echo "│                                                                            │"
echo "│             Hardware & System Repair Utilities for ShreeOS                 │"
echo "└────────────────────────────────────────────────────────────────────────────┘"
echo ""

while true; do
  echo "  Select a recovery action:"
  echo "  ──────────────────────────────────────────────────────────────────────────"
  echo "    [1] Continue Normal System Boot"
  echo "    [2] Verify & Repair Package Database (lpm verify)"
  echo "    [3] Check & Repair Root Filesystem (fsck)"
  echo "    [4] Rollback Recent System Package Update"
  echo "    [5] Reset Network Interfaces & Resolvers"
  echo "    [6] Drop to Root Maintenance Shell"
  echo "    [7] Reboot Computer"
  echo "    [8] Power Off"
  echo "  ──────────────────────────────────────────────────────────────────────────"
  echo ""
  read -r -p "  Enter choice [1-8]: " CHOICE

  case "$CHOICE" in
    1)
      echo "Resuming system startup..."
      exec /sbin/init || exit 0
      ;;
    2)
      echo "Running lpm package integrity checks..."
      if [ -d /var/lib/lpm/installed ]; then
        for pkg in /var/lib/lpm/installed/*; do
          [ -d "$pkg" ] || continue
          lpm verify "$(basename "$pkg")" || true
        done
      fi
      read -r -p "Press Enter to return..." _
      ;;
    3)
      echo "Checking root filesystem..."
      fsck -y / 2>/dev/null || echo "Root is mounted rw; unmount or reboot into ro mode for fsck"
      read -r -p "Press Enter to return..." _
      ;;
    4)
      shreectl snapshots list
      read -r -p "Enter snapshot ID to restore: " SNAP_ID
      if [ -n "$SNAP_ID" ]; then
        shreectl snapshots rollback "$SNAP_ID"
      fi
      read -r -p "Press Enter to return..." _
      ;;
    5)
      echo "Resetting network interfaces..."
      ip link set lo up 2>/dev/null || true
      echo "nameserver 1.1.1.1" > /etc/resolv.conf 2>/dev/null || true
      echo "Network and DNS reset to defaults."
      read -r -p "Press Enter to return..." _
      ;;
    6)
      echo "Spawning root maintenance shell (type 'exit' to return to recovery menu)..."
      /bin/bash --login || /bin/sh
      ;;
    7)
      initctl reboot || reboot
      ;;
    8)
      initctl poweroff || poweroff
      ;;
  esac
  clear
done
