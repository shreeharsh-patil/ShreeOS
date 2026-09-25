#!/usr/bin/env bash
# installer/scripts/shree-recovery.sh — ShreeOS Emergency Recovery Environment
#
# Terminal-based disaster recovery suite accessible via GRUB Single-User / Recovery mode.
# Supports automatic rollback, package verification, initramfs rebuild, boot repair, and diagnostics.

set -euo pipefail

if grep -qw 'shreeos.rollback=1' /proc/cmdline 2>/dev/null; then
  echo "ShreeOS SafeUpdate rollback requested via boot parameters."
  echo "Applying newest valid rollback payload..."
  if LPM_RECOVERY=1 lpm rollback; then
    echo "Rollback applied successfully. Rebooting to verified system state..."
    sleep 2
    initctl reboot 2>/dev/null || reboot
    exit 0
  else
    echo "Rollback payload missing or failed; falling back to interactive Recovery Menu."
    sleep 2
  fi
fi

clear
echo "┌────────────────────────────────────────────────────────────────────────────┐"
echo "│                      ShreeOS Emergency Recovery Console                    │"
echo "│                                                                            │"
echo "│         Hardware, Bootloader & System Repair Utilities for ShreeOS         │"
echo "└────────────────────────────────────────────────────────────────────────────┘"
echo ""

while true; do
  echo "  Select a recovery action:"
  echo "  ──────────────────────────────────────────────────────────────────────────"
  echo "    [1] Continue Normal System Boot"
  echo "    [2] Verify & Repair Package Database (lpm verify & repair)"
  echo "    [3] Rollback Recent System Package Update (SafeUpdate)"
  echo "    [4] Rebuild Initramfs Archive (/boot/initramfs.cpio.gz)"
  echo "    [5] Bootloader Repair (Regenerate GRUB Configuration)"
  echo "    [6] Hardware & System Diagnostics Report"
  echo "    [7] Check Root Filesystem Safely (read-only fsck)"
  echo "    [8] Reset Network Interfaces & Resolvers"
  echo "    [9] Drop to Root Maintenance Shell"
  echo "    [0] Reboot / Power Off"
  echo "  ──────────────────────────────────────────────────────────────────────────"
  echo ""
  read -r -p "  Enter choice [0-9]: " CHOICE

  case "$CHOICE" in
    1)
      echo "Returning control to the PID 1 supervisor..."
      exit 0
      ;;
    2)
      echo "==> Running LPM package verification and repair diagnostics..."
      if [ -d /var/lib/lpm/installed ]; then
        VERIFY_FAILURES=0
        VERIFY_COUNT=0
        for pkg in /var/lib/lpm/installed/*; do
          [ -d "$pkg" ] || continue
          VERIFY_COUNT=$((VERIFY_COUNT + 1))
          if ! lpm verify "$(basename "$pkg")"; then
            VERIFY_FAILURES=$((VERIFY_FAILURES + 1))
          fi
        done

        if [ "$VERIFY_FAILURES" -gt 0 ]; then
          echo "WARNING: ${VERIFY_FAILURES} of ${VERIFY_COUNT} package(s) failed integrity verification."
        else
          echo "Package verification passed for ${VERIFY_COUNT} package(s)."
        fi

        if lpm repair; then
          echo "LPM repair diagnostics completed successfully."
        else
          echo "WARNING: LPM still reports package integrity problems; reinstall the affected packages before normal boot."
        fi
      else
        echo "No installed packages found in /var/lib/lpm/installed."
      fi
      read -r -p "Press Enter to return to menu..." _
      ;;
    3)
      echo "==> SafeUpdate Transaction Rollback:"
      lpm history || true
      echo ""
      read -r -p "Enter transaction snapshot ID to restore (leave empty for newest): " SNAP_ID
      if [ -n "$SNAP_ID" ]; then
        LPM_RECOVERY=1 lpm rollback "$SNAP_ID" || echo "Rollback failed; transaction data remains available."
      else
        LPM_RECOVERY=1 lpm rollback || echo "Rollback failed; transaction data remains available."
      fi
      read -r -p "Press Enter to return to menu..." _
      ;;
    4)
      echo "==> Rebuilding system initramfs archive (/boot/initramfs.cpio.gz)..."
      INITRAMFS_TARGET="/boot/initramfs.cpio.gz"
      if [ ! -d /boot ] || [ ! -w /boot ]; then
        echo "ERROR: /boot is missing or not writable."
        read -r -p "Press Enter to return to menu..." _
        continue
      fi
      for required in find cpio gzip; do
        if ! command -v "$required" >/dev/null 2>&1; then
          echo "ERROR: required recovery command is missing: $required"
          read -r -p "Press Enter to return to menu..." _
          continue 2
        fi
      done

      INITRAMFS_TMP=$(mktemp /boot/.initramfs.cpio.gz.XXXXXX)
      echo "Packaging root filesystem into a temporary initramfs..."
      if (
        cd /
        find . -mindepth 1 \
          -not -path './proc*' \
          -not -path './sys*' \
          -not -path './dev*' \
          -not -path './run*' \
          -not -path './tmp*' \
          -not -path './boot*' \
          -not -path './mnt*' \
          -not -path './media*' \
          -print0 \
          | cpio --null -H newc -o 2>/dev/null \
          | gzip -9 > "$INITRAMFS_TMP"
      ) && gzip -t "$INITRAMFS_TMP" 2>/dev/null; then
        INIT_LIST=$(gzip -dc "$INITRAMFS_TMP" | cpio -t --quiet 2>/dev/null || true)
        if printf '%s\n' "$INIT_LIST" | grep -Eq '^(\./)?init$'; then
          chmod 0644 "$INITRAMFS_TMP"
          mv -f "$INITRAMFS_TMP" "$INITRAMFS_TARGET"
          sync
          echo "Successfully rebuilt ${INITRAMFS_TARGET} ($(du -h "$INITRAMFS_TARGET" | cut -f1))"
        else
          rm -f "$INITRAMFS_TMP"
          echo "ERROR: rebuilt initramfs does not contain an /init entry; existing archive was preserved."
        fi
      else
        rm -f "$INITRAMFS_TMP"
        echo "ERROR: initramfs rebuild failed; existing archive was preserved."
      fi
      read -r -p "Press Enter to return to menu..." _
      ;;
    5)
      echo "==> Running Bootloader Repair:"
      ROOT_DEVICE=$(findmnt -n -o SOURCE / 2>/dev/null || echo '')
      if [ -z "$ROOT_DEVICE" ] || [ ! -b "$ROOT_DEVICE" ]; then
        for candidate in /dev/sda3 /dev/vda3 /dev/nvme0n1p3; do
          if [ -b "$candidate" ]; then ROOT_DEVICE="$candidate"; break; fi
        done
      fi
      ROOT_UUID=$(blkid -s UUID -o value "$ROOT_DEVICE" 2>/dev/null || echo "")
      ROOT_PARTUUID=$(blkid -s PARTUUID -o value "$ROOT_DEVICE" 2>/dev/null || echo "")

      if [ -n "$ROOT_UUID" ] && [ -n "$ROOT_PARTUUID" ] && [ -d /boot/grub ]; then
        echo "Detected Root UUID: ${ROOT_UUID}; PARTUUID: ${ROOT_PARTUUID}"
        cat > /boot/grub/grub.cfg <<GRUBEOF
# GRUB Configuration — Repaired by ShreeOS Emergency Recovery
set default=0
set timeout=5

serial --speed=115200 --unit=0 --word=8 --parity=no --stop=1

insmod all_video
insmod font
insmod gfxterm
set gfxmode=auto
terminal_output gfxterm
terminal_input --append serial console
terminal_output --append serial console

insmod gpt
insmod part_gpt
insmod part_msdos
insmod ext2
insmod fat

menuentry "ShreeOS (Repaired Boot)" {
    search --no-floppy --fs-uuid --set=root ${ROOT_UUID}
    linux /boot/bzImage root=PARTUUID=${ROOT_PARTUUID} rw rootwait console=tty0 console=ttyS0,115200n8
}

menuentry "ShreeOS (Recovery Mode)" {
    search --no-floppy --fs-uuid --set=root ${ROOT_UUID}
    linux /boot/bzImage root=PARTUUID=${ROOT_PARTUUID} rw rootwait console=tty0 console=ttyS0,115200n8 single shreeos.mode=recovery
}

menuentry "ShreeOS Previous Working State (SafeUpdate Rollback)" {
    search --no-floppy --fs-uuid --set=root ${ROOT_UUID}
    linux /boot/bzImage root=PARTUUID=${ROOT_PARTUUID} rw rootwait console=tty0 console=ttyS0,115200n8 single shreeos.rollback=1
}
GRUBEOF
        chmod 0644 /boot/grub/grub.cfg
        echo "Successfully regenerated /boot/grub/grub.cfg with root PARTUUID ${ROOT_PARTUUID}"
      else
        echo "WARNING: Could not detect the root filesystem UUID/PARTUUID. GRUB configuration unchanged."
      fi
      read -r -p "Press Enter to return to menu..." _
      ;;
    6)
      echo "==> Hardware & System Diagnostics Report:"
      echo "--------------------------------------------------------"
      echo "Kernel Version: $(uname -a)"
      echo "System Uptime:  $(cat /proc/uptime 2>/dev/null | awk '{print $1}') seconds"
      echo ""
      echo "Memory Usage:"
      free -m 2>/dev/null || grep -E 'MemTotal|MemFree|MemAvailable' /proc/meminfo 2>/dev/null || true
      echo ""
      echo "Block Devices & Partitions:"
      lsblk 2>/dev/null || cat /proc/partitions
      echo ""
      echo "Mounted Filesystems:"
      mount | grep -E '^/dev/' || df -h
      echo ""
      echo "Network Interfaces:"
      ip link 2>/dev/null || ifconfig -a 2>/dev/null || true
      echo "--------------------------------------------------------"
      read -r -p "Press Enter to return to menu..." _
      ;;
    7)
      echo "Checking root filesystem safely..."
      ROOT_SOURCE=$(findmnt -n -o SOURCE / 2>/dev/null || true)
      if [ -z "$ROOT_SOURCE" ] || [ ! -b "$ROOT_SOURCE" ]; then
        echo "ERROR: Could not identify a block device backing the root filesystem."
      elif ! command -v fsck >/dev/null 2>&1; then
        echo "ERROR: fsck is not available in this recovery environment."
      else
        echo "Root device: $ROOT_SOURCE"
        echo "Running a read-only filesystem check. Repairs are intentionally not attempted while / is mounted."
        if fsck -fn "$ROOT_SOURCE"; then
          echo "Read-only filesystem check completed without reported errors."
        else
          echo "WARNING: Filesystem issues were reported."
          echo "For repair, boot from external/live recovery media so $ROOT_SOURCE is completely unmounted, then run fsck there."
        fi
      fi
      read -r -p "Press Enter to return to menu..." _
      ;;
    8)
      echo "Resetting network interfaces & resolver..."
      NET_FAILURES=0
      if ! command -v ip >/dev/null 2>&1; then
        echo "ERROR: ip command is unavailable."
        NET_FAILURES=$((NET_FAILURES + 1))
      else
        if ! ip link set lo up 2>/dev/null; then
          echo "WARNING: Could not bring loopback interface up."
          NET_FAILURES=$((NET_FAILURES + 1))
        fi
        for iface in /sys/class/net/*; do
          [ -e "$iface" ] || continue
          dev="${iface##*/}"
          [ "$dev" = "lo" ] && continue
          if ! ip link set "$dev" up 2>/dev/null; then
            echo "WARNING: Could not bring interface $dev up."
            NET_FAILURES=$((NET_FAILURES + 1))
          fi
        done
      fi

      if printf '%s\n' "nameserver 1.1.1.1" > /etc/resolv.conf 2>/dev/null; then
        echo "Resolver set to 1.1.1.1 for recovery networking."
      else
        echo "WARNING: Could not update /etc/resolv.conf."
        NET_FAILURES=$((NET_FAILURES + 1))
      fi

      if [ "$NET_FAILURES" -eq 0 ]; then
        echo "Recovery network reset completed successfully."
      else
        echo "Recovery network reset completed with ${NET_FAILURES} warning(s)."
      fi
      read -r -p "Press Enter to return to menu..." _
      ;;
    9)
      echo "Spawning root maintenance shell (type 'exit' to return to recovery menu)..."
      /bin/bash --login 2>/dev/null || /bin/sh
      ;;
    0)
      read -r -p "Enter [r] to Reboot or [p] to Power Off: " SUB
      if [ "$SUB" = "p" ] || [ "$SUB" = "P" ]; then
        initctl poweroff 2>/dev/null || poweroff
      else
        initctl reboot 2>/dev/null || reboot
      fi
      ;;
  esac
  clear
done
