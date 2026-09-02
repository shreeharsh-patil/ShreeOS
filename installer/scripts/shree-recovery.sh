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
  echo "    [7] Check & Repair Root Filesystem (fsck)"
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
      echo "==> Running LPM package verification and repair..."
      if [ -d /var/lib/lpm/installed ]; then
        for pkg in /var/lib/lpm/installed/*; do
          [ -d "$pkg" ] || continue
          lpm verify "$(basename "$pkg")" || true
        done
        lpm repair || true
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
      INITRAMFS_TMP="/boot/initramfs.cpio.gz.tmp.$$"
      if [ -d /boot ]; then
        echo "Packaging root filesystem into new initramfs..."
        (
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
            | cpio -H newc -o 2>/dev/null | gzip -9 > "$INITRAMFS_TMP"
        )
        mv "$INITRAMFS_TMP" "$INITRAMFS_TARGET"
        chmod 0644 "$INITRAMFS_TARGET"
        echo "Successfully rebuilt ${INITRAMFS_TARGET} ($(du -h "$INITRAMFS_TARGET" | cut -f1))"
      else
        echo "ERROR: /boot directory not found."
      fi
      read -r -p "Press Enter to return to menu..." _
      ;;
    5)
      echo "==> Running Bootloader Repair:"
      ROOT_UUID=$(blkid -s UUID -o value "$(findmnt -n -o SOURCE / 2>/dev/null || echo '')" 2>/dev/null || echo "")
      if [ -z "$ROOT_UUID" ]; then
        ROOT_UUID=$(blkid -s UUID -o value /dev/sda3 2>/dev/null || blkid -s UUID -o value /dev/vda3 2>/dev/null || blkid -s UUID -o value /dev/nvme0n1p3 2>/dev/null || echo "")
      fi

      if [ -n "$ROOT_UUID" ] && [ -d /boot/grub ]; then
        echo "Detected Root UUID: ${ROOT_UUID}"
        cat > /boot/grub/grub.cfg <<GRUBEOF
# GRUB Configuration — Repaired by ShreeOS Emergency Recovery
set default=0
set timeout=5

insmod all_video
insmod font
insmod gfxterm
set gfxmode=auto
terminal_output gfxterm

insmod gpt
insmod part_gpt
insmod part_msdos
insmod ext2
insmod fat

menuentry "ShreeOS (Repaired Boot)" {
    search --no-floppy --fs-uuid --set=root ${ROOT_UUID}
    linux /boot/bzImage root=UUID=${ROOT_UUID} ro quiet
    initrd /boot/initramfs.cpio.gz
}

menuentry "ShreeOS (Recovery Mode)" {
    search --no-floppy --fs-uuid --set=root ${ROOT_UUID}
    linux /boot/bzImage root=UUID=${ROOT_UUID} ro single shreeos.mode=recovery
    initrd /boot/initramfs.cpio.gz
}

menuentry "ShreeOS Previous Working State (SafeUpdate Rollback)" {
    search --no-floppy --fs-uuid --set=root ${ROOT_UUID}
    linux /boot/bzImage root=UUID=${ROOT_UUID} ro single shreeos.rollback=1
    initrd /boot/initramfs.cpio.gz
}
GRUBEOF
        chmod 0644 /boot/grub/grub.cfg
        echo "Successfully regenerated /boot/grub/grub.cfg with Root UUID ${ROOT_UUID}"
      else
        echo "WARNING: Could not automatically detect Root UUID. GRUB configuration unchanged."
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
      echo "Checking root filesystem..."
      fsck -y / 2>/dev/null || echo "Root is mounted rw; reboot with 'ro single' for active root fsck."
      read -r -p "Press Enter to return to menu..." _
      ;;
    8)
      echo "Resetting network interfaces & DNS..."
      ip link set lo up 2>/dev/null || true
      for iface in /sys/class/net/*; do
        dev="${iface##*/}"
        [ "$dev" = "lo" ] && continue
        ip link set "$dev" up 2>/dev/null || true
      done
      echo "nameserver 1.1.1.1" > /etc/resolv.conf 2>/dev/null || true
      echo "Network interfaces brought UP and DNS set to 1.1.1.1."
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
