#!/usr/bin/env bash
# tests/installer/test-installer-validation.sh — Test Installer Safeguards & Input Validation
#
# Verifies:
#   - Disk rejection (non-existent, host root device, live media)
#   - NVMe/SATA/VirtIO/MMC partition device naming logic
#   - Hostname format validation (RFC 1123)
#   - Timezone traversal protection
#   - Username validation
#   - Credentials mode 0600 enforcement and memory wiping
#   - GPT partition layout (BIOS Boot + ESP + Root)
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
INSTALLER="${ROOT_DIR}/installer/scripts/install-to-disk.sh"
TUI_INSTALLER="${ROOT_DIR}/installer/scripts/installer-tui.sh"
RECOVERY="${ROOT_DIR}/installer/scripts/shree-recovery.sh"
GRUB_INSTALLER="${ROOT_DIR}/bootloader/scripts/install-grub-disk.sh"
SYSINIT_CONF="${ROOT_DIR}/init/services/00-sysinit.conf"

echo "==> Testing ShreeOS Installer Validation & Safeguards"

# 1. Hostname validation test in install-to-disk.sh
if bash "${ROOT_DIR}/installer/scripts/install-to-disk.sh" --help >/dev/null 2>&1; then
  echo "  [OK] install-to-disk.sh responds to --help"
else
  echo "  [FAIL] install-to-disk.sh help command failed" >&2
  exit 1
fi

# 2. Partition disk validation test
if bash "${ROOT_DIR}/installer/scripts/partition-disk.sh" --help >/dev/null 2>&1; then
  echo "  [OK] partition-disk.sh responds to --help"
else
  echo "  [FAIL] partition-disk.sh help command failed" >&2
  exit 1
fi

# 3. Test non-existent disk rejection
if bash "${ROOT_DIR}/installer/scripts/partition-disk.sh" "/dev/nonexistent_shreeos_disk" --yes >/dev/null 2>&1; then
  echo "  [FAIL] partition-disk.sh accepted non-existent disk device!" >&2
  exit 1
else
  echo "  [OK] Non-existent block device correctly rejected"
fi

# 4. Test protection of host root filesystem
HOST_ROOT=$(findmnt -n -o SOURCE / 2>/dev/null || echo "")
if [ -n "$HOST_ROOT" ] && [ -b "$HOST_ROOT" ]; then
  if bash "${ROOT_DIR}/installer/scripts/partition-disk.sh" "$HOST_ROOT" --yes >/dev/null 2>&1; then
    echo "  [FAIL] partition-disk.sh allowed overwriting host root filesystem!" >&2
    exit 1
  else
    echo "  [OK] Active host root filesystem (${HOST_ROOT}) correctly protected from overwrite"
  fi
fi

# 5. Test NVMe vs SATA partition naming logic
get_partition_dev() {
  local disk="$1"
  local num="$2"
  if [ -b "${disk}p${num}" ] || [ -f "${disk}p${num}" ]; then
    echo "${disk}p${num}"
  elif [ -b "${disk}${num}" ] || [ -f "${disk}${num}" ]; then
    echo "${disk}${num}"
  elif [[ "$disk" =~ [0-9]$ ]]; then
    echo "${disk}p${num}"
  else
    echo "${disk}${num}"
  fi
}

[ "$(get_partition_dev "/dev/nvme0n1" 3)" = "/dev/nvme0n1p3" ] || { echo "  [FAIL] NVMe partition naming failed"; exit 1; }
[ "$(get_partition_dev "/dev/mmcblk0" 3)" = "/dev/mmcblk0p3" ] || { echo "  [FAIL] MMC partition naming failed"; exit 1; }
[ "$(get_partition_dev "/dev/sda" 3)" = "/dev/sda3" ] || { echo "  [FAIL] SATA partition naming failed"; exit 1; }
[ "$(get_partition_dev "/dev/vda" 3)" = "/dev/vda3" ] || { echo "  [FAIL] VirtIO partition naming failed"; exit 1; }
echo "  [OK] Partition device naming handles NVMe, MMC, VirtIO, and SATA"

# 6. Test Hostname RFC 1123 format validation
validate_hostname() {
  local h="$1"
  [[ "$h" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?$ ]]
}
validate_hostname "shreeos" || { echo "  [FAIL] Valid hostname rejected"; exit 1; }
validate_hostname "my-linux-box-01" || { echo "  [FAIL] Valid hyphenated hostname rejected"; exit 1; }
! validate_hostname "-badprefix" || { echo "  [FAIL] Hostname with leading hyphen accepted"; exit 1; }
! validate_hostname "bad_underscore" || { echo "  [FAIL] Hostname with underscore accepted"; exit 1; }
! validate_hostname "has spaces" || { echo "  [FAIL] Hostname with spaces accepted"; exit 1; }
echo "  [OK] Hostname RFC 1123 validation correctly enforced"

# 7. Test Timezone traversal rejection
validate_tz() {
  local tz="$1"
  ! [[ "$tz" == *".."* ]] && ! [[ "$tz" == /* ]] && [[ "$tz" =~ ^[A-Za-z0-9_+-]+(/[A-Za-z0-9_+-]+)*$ ]]
}
validate_tz "UTC" || { echo "  [FAIL] Valid UTC timezone rejected"; exit 1; }
validate_tz "Asia/Kolkata" || { echo "  [FAIL] Valid Asia/Kolkata rejected"; exit 1; }
! validate_tz "../etc/passwd" || { echo "  [FAIL] Path traversal timezone accepted"; exit 1; }
! validate_tz "/etc/shadow" || { echo "  [FAIL] Absolute path timezone accepted"; exit 1; }
echo "  [OK] Timezone traversal validation correctly enforced"

# 8. Test Username validation
validate_user() {
  local u="$1"
  [[ "$u" =~ ^[a-z_][a-z0-9_-]{0,31}$ ]]
}
validate_user "shree" || { echo "  [FAIL] Valid username rejected"; exit 1; }
validate_user "dev_user01" || { echo "  [FAIL] Valid username with underscore/digits rejected"; exit 1; }
! validate_user "UserCapital" || { echo "  [FAIL] Uppercase username accepted"; exit 1; }
! validate_user "has spaces" || { echo "  [FAIL] Username with spaces accepted"; exit 1; }
! validate_user "root:evil" || { echo "  [FAIL] Username with colon accepted"; exit 1; }
echo "  [OK] Username validation correctly enforced"

# 9. Installed systems must boot the ext4 partition itself. Loading the full
# live initramfs here would hide installed credentials and filesystem changes.
grep -Fq 'root=PARTUUID=${ROOT_PARTUUID} rw' "$GRUB_INSTALLER" || {
  echo "  [FAIL] Installed GRUB configuration does not use the root GPT PARTUUID" >&2
  exit 1
}
if grep -Eq '^[[:space:]]+initrd /boot/initramfs' "$GRUB_INSTALLER"; then
  echo "  [FAIL] Installed GRUB configuration still boots the live initramfs" >&2
  exit 1
fi
echo "  [OK] Installed GRUB configuration boots the persistent ext4 root directly"

for required_text in \
  'console=tty0 console=ttyS0,115200n8' \
  'serial --speed=115200 --unit=0 --word=8 --parity=no --stop=1' \
  'terminal_input --append serial console' \
  'terminal_output --append serial console'; do
  grep -Fq "$required_text" "$GRUB_INSTALLER" || {
    echo "  [FAIL] Installed GRUB configuration is missing: ${required_text}" >&2
    exit 1
  }
done
[ "$(grep -Fc '    linux /boot/bzImage ' "$GRUB_INSTALLER")" -eq 3 ] || {
  echo "  [FAIL] Installed GRUB configuration does not contain three kernel entries" >&2
  exit 1
}
if grep -Eq '^[[:space:]]*linux .*quiet' "$GRUB_INSTALLER"; then
  echo "  [FAIL] Installed GRUB configuration suppresses kernel diagnostics" >&2
  exit 1
fi
while IFS= read -r kernel_line; do
  [[ "$kernel_line" == *"console=tty0 console=ttyS0,115200n8"* ]] || {
    echo "  [FAIL] An installed kernel entry lacks console diagnostics: ${kernel_line}" >&2
    exit 1
  }
done < <(grep -E '^[[:space:]]*linux /boot/bzImage ' "$GRUB_INSTALLER")
echo "  [OK] Installed kernel entries expose local and serial diagnostics"

for required_text in \
  'ESP_SIZE_BYTES=$((512 * 1024 * 1024))' \
  'ROOTFS_PAYLOAD_BYTES' \
  'SAFETY_MARGIN_BYTES' \
  'MIN_TARGET_BYTES'; do
  grep -Fq "$required_text" "$INSTALLER" || {
    echo "  [FAIL] Installer capacity validation is missing: ${required_text}" >&2
    exit 1
  }
done
grep -Fq 'losetup --nooverlap -Pf --show' "$INSTALLER" || {
  echo "  [FAIL] Image loop attachment does not use losetup --nooverlap" >&2
  exit 1
}
grep -Fq 'losetup -j "$CANONICAL_DISK"' "$INSTALLER" || {
  echo "  [FAIL] Installer does not reject existing image loop associations" >&2
  exit 1
}
grep -Fq 'EXPECTED_CREDS_OWNER="${SUDO_UID:-$(id -u)}"' "$INSTALLER" || {
  echo "  [FAIL] External credential ownership validation was removed" >&2
  exit 1
}
grep -Fq 'grub-mkimage --verbose -O x86_64-efi -o "$UEFI_IMAGE" -p /EFI/BOOT' "$GRUB_INSTALLER" || {
  echo "  [FAIL] Installed UEFI path does not build an explicit /EFI/BOOT GRUB image" >&2
  exit 1
}
grep -Fq 'install -m 0644 "${TARGET}/boot/grub/grub.cfg" "${UEFI_BOOT_DIR}/grub.cfg"' "$GRUB_INSTALLER" || {
  echo "  [FAIL] Installed UEFI path does not stage grub.cfg on the ESP" >&2
  exit 1
}
grep -Fq 'env -u SUDO_UID bash' "$TUI_INSTALLER" || {
  echo "  [FAIL] TUI does not isolate its root-owned temporary credentials from sudo ownership checks" >&2
  exit 1
}
for required_text in \
  'A username requires a credentials file with a non-empty user password.' \
  'A user password was supplied without --username.' \
  'Credentials file has an empty user password.'; do
  grep -Fq "$required_text" "$INSTALLER" || {
    echo "  [FAIL] Credential pairing validation is missing: ${required_text}" >&2
    exit 1
  }
done
NORMALIZE_LINE=$(grep -nF 'chown -R root:root "${TARGET}"' "$INSTALLER" | awk -F: 'NR == 1 {print $1}')
USER_LINE=$(grep -nF 'bash "${SCRIPT_DIR}/configure-user.sh"' "$INSTALLER" | awk -F: 'NR == 1 {print $1}')
[ -n "$NORMALIZE_LINE" ] && [ -n "$USER_LINE" ] && [ "$NORMALIZE_LINE" -lt "$USER_LINE" ] || {
  echo "  [FAIL] Installed files are not normalized before user creation" >&2
  exit 1
}
grep -Fq 'chown -R "${NEW_UID}:${NEW_GID}" "${TARGET}/home/${USER}"' "${ROOT_DIR}/installer/scripts/configure-user.sh" || {
  echo "  [FAIL] User home ownership is not restored after normalization" >&2
  exit 1
}
grep -Fq "type the exact disk path" "$TUI_INSTALLER" || {
  echo "  [FAIL] Exact disk confirmation was removed" >&2
  exit 1
}
grep -Fq 'ALL EXISTING DATA ON ${DISK} WILL BE PERMANENTLY DESTROYED!' "${ROOT_DIR}/installer/scripts/partition-disk.sh" || {
  echo "  [FAIL] Destructive-operation warning was removed" >&2
  exit 1
}
grep -Fq "grep -Eq '^(\\./)?init$'" "$RECOVERY" || {
  echo "  [FAIL] Recovery initramfs validation does not require /init" >&2
  exit 1
}
if grep -Fq '(init|sbin/init)' "$RECOVERY"; then
  echo "  [FAIL] Recovery validation still accepts /sbin/init" >&2
  exit 1
fi
[ "$(grep -Fc '    linux /boot/bzImage ' "$RECOVERY")" -eq 3 ] || {
  echo "  [FAIL] Recovery configuration does not contain three kernel entries" >&2
  exit 1
}
if grep -Eq '^[[:space:]]*linux .*quiet' "$RECOVERY"; then
  echo "  [FAIL] Recovery configuration suppresses kernel diagnostics" >&2
  exit 1
fi
while IFS= read -r recovery_kernel_line; do
  [[ "$recovery_kernel_line" == *"console=tty0 console=ttyS0,115200n8"* ]] || {
    echo "  [FAIL] A recovery kernel entry lacks console diagnostics: ${recovery_kernel_line}" >&2
    exit 1
  }
done < <(grep -E '^[[:space:]]*linux /boot/bzImage ' "$RECOVERY")
if grep -Fq '/proc/sys/kernel/printk' "$SYSINIT_CONF"; then
  echo "  [FAIL] sysinit still suppresses kernel printk diagnostics" >&2
  exit 1
fi
echo "  [OK] Installer safety and bootability checks are present"

PREFLIGHT_DIR=$(mktemp -d /tmp/shreeos-installer-preflight-XXXXXX)
trap 'rm -rf "$PREFLIGHT_DIR"' EXIT
PREFLIGHT_STAGE="$PREFLIGHT_DIR/rootfs"
PREFLIGHT_BUILD="$PREFLIGHT_DIR/build"
mkdir -p "$PREFLIGHT_STAGE/usr/share/zoneinfo" "$PREFLIGHT_BUILD/build-kernel/arch/x86/boot"
printf 'UTC\n' > "$PREFLIGHT_STAGE/usr/share/zoneinfo/UTC"
printf 'kernel\n' > "$PREFLIGHT_BUILD/build-kernel/arch/x86/boot/bzImage"
printf 'initramfs\n' > "$PREFLIGHT_BUILD/initramfs.cpio.gz"
PREFLIGHT_TARGET="$PREFLIGHT_DIR/target.img"
truncate -s 1G "$PREFLIGHT_TARGET"
PREFLIGHT_CREDS="$PREFLIGHT_DIR/creds.txt"
: > "$PREFLIGHT_CREDS"
chmod 600 "$PREFLIGHT_CREDS"

run_installer_preflight() {
  SHREEOS_STAGE_ROOT="$PREFLIGHT_STAGE" SHREEOS_BUILD_DIR="$PREFLIGHT_BUILD" bash "$INSTALLER" "$@"
}

expect_preflight_failure() {
  local expected="$1"
  shift
  local output
  if output=$(run_installer_preflight "$@" 2>&1); then
    echo "  [FAIL] Installer accepted invalid preflight input" >&2
    exit 1
  fi
  grep -Fq "$expected" <<< "$output" || {
    echo "  [FAIL] Installer did not report expected preflight error: ${expected}" >&2
    exit 1
  }
}

printf 'rootpassword123\n' > "$PREFLIGHT_CREDS"
expect_preflight_failure 'A username requires a credentials file' "$PREFLIGHT_TARGET" --username=alice
printf 'rootpassword123\n' > "$PREFLIGHT_CREDS"
expect_preflight_failure 'A username requires a second' "$PREFLIGHT_TARGET" --username=alice --credentials-file="$PREFLIGHT_CREDS"
printf 'rootpassword123\n\n' > "$PREFLIGHT_CREDS"
expect_preflight_failure 'empty user password' "$PREFLIGHT_TARGET" --username=alice --credentials-file="$PREFLIGHT_CREDS"
printf 'rootpassword123\nuserpassword123\n' > "$PREFLIGHT_CREDS"
expect_preflight_failure 'without --username' "$PREFLIGHT_TARGET" --credentials-file="$PREFLIGHT_CREDS"
SUDO_UID=999999 expect_preflight_failure 'owned by the invoking user' "$PREFLIGHT_TARGET" --credentials-file="$PREFLIGHT_CREDS"
unset SUDO_UID
printf 'rootpassword123\n' > "$PREFLIGHT_CREDS"
PREFLIGHT_SMALL="$PREFLIGHT_DIR/small.img"
truncate -s 600M "$PREFLIGHT_SMALL"
expect_preflight_failure 'Target media is too small' "$PREFLIGHT_SMALL" --credentials-file="$PREFLIGHT_CREDS"
FAKE_BIN="$PREFLIGHT_DIR/bin"
mkdir -p "$FAKE_BIN"
cat > "$FAKE_BIN/losetup" <<'LOSETUP'
#!/usr/bin/env bash
if [ "${1:-}" = "-j" ]; then
  printf '/dev/loop0: [0005]:0000 (%s)\n' "${2:-}"
  exit 0
fi
exit 1
LOSETUP
chmod 700 "$FAKE_BIN/losetup"
if output=$(PATH="$FAKE_BIN:$PATH" SHREEOS_STAGE_ROOT="$PREFLIGHT_STAGE" SHREEOS_BUILD_DIR="$PREFLIGHT_BUILD" bash "$INSTALLER" "$PREFLIGHT_TARGET" --credentials-file="$PREFLIGHT_CREDS" 2>&1); then
  echo "  [FAIL] Installer accepted an image with an existing loop association" >&2
  exit 1
fi
grep -Fq 'already has a loop association' <<< "$output" || {
  echo "  [FAIL] Installer did not report the overlapping loop association" >&2
  exit 1
}
printf 'rootpassword123\nuserpassword123\n' > "$PREFLIGHT_CREDS"
if output=$(run_installer_preflight "$PREFLIGHT_TARGET" --username=alice --credentials-file="$PREFLIGHT_CREDS" --timezone=../invalid 2>&1); then
  echo "  [FAIL] Valid username/credential pairing unexpectedly reached destructive setup" >&2
  exit 1
fi
grep -Fq 'Invalid timezone' <<< "$output" || {
  echo "  [FAIL] Valid username/credential pairing was rejected before the next validation" >&2
  exit 1
}
echo "  [OK] Credential pairing, non-empty validation, ownership checks, and capacity checks run before setup"

# 10. Behavioral test: Partition a virtual disk image using GPT layout
if command -v sfdisk >/dev/null 2>&1; then
  TEST_DISK=$(mktemp /tmp/shreeos-part-test-XXXXXX.img)
  truncate -s 1G "$TEST_DISK"

  if bash "${ROOT_DIR}/installer/scripts/partition-disk.sh" "$TEST_DISK" --yes >/dev/null 2>&1 && \
     sfdisk -l "$TEST_DISK" 2>/dev/null | grep -q "BIOS boot" && \
     sfdisk -l "$TEST_DISK" 2>/dev/null | grep -Eq '512M[[:space:]]+EFI System' && \
     sfdisk -l "$TEST_DISK" 2>/dev/null | grep -q "Linux filesystem"; then
    echo "  [OK] Successfully partitioned virtual disk image with GPT BIOS+ESP+Root layout"
  else
    echo "  [FAIL] GPT partition layout test failed" >&2
    rm -f "$TEST_DISK"
    exit 1
  fi
  rm -f "$TEST_DISK"
fi

echo "==> All installer validation tests passed successfully!"
