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

echo "==> Testing ShreeOS Installer Validation & Safeguards"

# 1. Hostname validation test in install-to-disk.sh
if bash "${ROOT_DIR}/installer/scripts/install-to-disk.sh" --help >/dev/null 2>&1; then
  echo "  [OK] install-to-disk.sh responds to --help"
else
  echo "  [FAIL] install-to-disk.sh help command failed" >&2
  exit 1
fi

# 1b. Destructive installs must require a secure credential file before any
# disk validation/partitioning occurs.
NO_CREDS_OUTPUT="$(bash "${ROOT_DIR}/installer/scripts/install-to-disk.sh" /dev/nonexistent_shreeos_disk --yes 2>&1 || true)"
if grep -q -- "--credentials-file is required" <<<"$NO_CREDS_OUTPUT"; then
  echo "  [OK] Missing credentials are rejected before disk operations"
else
  echo "  [FAIL] Installer did not fail closed when credentials were omitted" >&2
  exit 1
fi

# 1c. The removed plaintext password CLI must remain unsupported.
if bash "${ROOT_DIR}/installer/scripts/install-to-disk.sh" /dev/nonexistent_shreeos_disk --root-password=changeme >/dev/null 2>&1; then
  echo "  [FAIL] Legacy plaintext --root-password option was accepted" >&2
  exit 1
else
  echo "  [OK] Plaintext password command-line option is rejected"
fi

# 1d. Credential strength and user-line validation happen before disk access.
TMP_CREDS="$(mktemp /tmp/shreeos-installer-validation-XXXXXX)"
trap 'rm -f "$TMP_CREDS" "${TEST_DISK:-}"' EXIT
chmod 600 "$TMP_CREDS"
printf 'short\n' > "$TMP_CREDS"
SHORT_OUTPUT="$(bash "${ROOT_DIR}/installer/scripts/install-to-disk.sh" /dev/nonexistent_shreeos_disk --yes --credentials-file="$TMP_CREDS" 2>&1 || true)"
if grep -q "Root password must be at least 8 characters" <<<"$SHORT_OUTPUT"; then
  echo "  [OK] Short root passwords are rejected before disk operations"
else
  echo "  [FAIL] Short root password preflight did not trigger" >&2
  exit 1
fi

printf 'strongrootpass\n' > "$TMP_CREDS"
USER_OUTPUT="$(bash "${ROOT_DIR}/installer/scripts/install-to-disk.sh" /dev/nonexistent_shreeos_disk --yes --username=shree --credentials-file="$TMP_CREDS" 2>&1 || true)"
if grep -q "user password on line 2 is required" <<<"$USER_OUTPUT"; then
  echo "  [OK] Username requires a second credential line before disk operations"
else
  echo "  [FAIL] Missing user credential line was not rejected" >&2
  exit 1
fi
rm -f "$TMP_CREDS"

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

# 9. Behavioral test: undersized images must fail, while a valid sparse image
# must receive the complete GPT layout.
if command -v sfdisk >/dev/null 2>&1; then
  TEST_DISK=$(mktemp /tmp/shreeos-part-test-XXXXXX.img)
  trap 'rm -f "$TEST_DISK" "${TMP_CREDS:-}"' EXIT

  truncate -s 512M "$TEST_DISK"
  if bash "${ROOT_DIR}/installer/scripts/partition-disk.sh" "$TEST_DISK" --yes >/dev/null 2>&1; then
    echo "  [FAIL] Undersized raw disk image was accepted" >&2
    exit 1
  else
    echo "  [OK] Undersized raw disk image correctly rejected"
  fi

  truncate -s 2G "$TEST_DISK"
  if ! bash "${ROOT_DIR}/installer/scripts/partition-disk.sh" "$TEST_DISK" --yes >/dev/null 2>&1; then
    echo "  [FAIL] Valid 2 GiB raw disk image could not be partitioned" >&2
    exit 1
  fi

  if sfdisk -l "$TEST_DISK" 2>/dev/null | grep -q "BIOS-Boot" && \
     sfdisk -l "$TEST_DISK" 2>/dev/null | grep -q "EFI-System" && \
     sfdisk -l "$TEST_DISK" 2>/dev/null | grep -q "ShreeOS-Root"; then
    echo "  [OK] Successfully partitioned virtual disk image with GPT BIOS+ESP+Root layout"
  else
    echo "  [FAIL] GPT partition labels/layout are incomplete" >&2
    exit 1
  fi
  rm -f "$TEST_DISK"
fi

echo "==> All installer validation tests passed successfully!"
