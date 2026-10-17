#!/bin/sh

# Verify the FAT subtype from the boot-sector fields, not lsblk's vfat label.
# fsck.fat -b performs a read-only boot-sector check; C locale keeps the
# verbose fields stable for parsing on the live installer.
shreeos_require_fat32() {
  device="$1"
  report=""
  if ! report="$(LC_ALL=C fsck.fat -b -v "$device" 2>&1)"; then
    printf 'Could not inspect FAT filesystem on %s: %s\n' "$device" \
      "${report:-fsck.fat returned no details}" >&2
    return 1
  fi

  if ! printf '%s\n' "$report" | awk '
    /32 bit entries/ { found = 1 }
    END { exit !found }
  '; then
    printf 'FAT filesystem on %s is not FAT32.\n' "$device" >&2
    return 1
  fi

  data_clusters="$(printf '%s\n' "$report" | awk '
    $2 == "data" && $3 == "clusters" && $1 ~ /^[0-9]+$/ { print $1; exit }
  ')"
  case "$data_clusters" in
    ''|*[!0-9]*)
      printf 'Could not read FAT32 data-cluster count for %s.\n' "$device" >&2
      return 1
      ;;
  esac
  if [ "$data_clusters" -lt 65525 ]; then
    printf 'FAT32 filesystem on %s has too few data clusters: %s.\n' \
      "$device" "$data_clusters" >&2
    return 1
  fi
  return 0
}
