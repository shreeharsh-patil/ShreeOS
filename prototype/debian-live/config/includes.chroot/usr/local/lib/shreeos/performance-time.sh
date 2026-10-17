#!/bin/sh
# Shared systemd duration parsing for the live performance probe.

shreeos_extract_boot_total() {
  printf '%s\n' "$1" | awk '
    index($0, "=") {
      value = substr($0, index($0, "=") + 1)
      sub(/^[[:space:]]+/, "", value)
      if (match(value, /^([0-9]+min([[:space:]]+[0-9]+([.][0-9]+)?s)?|[0-9]+([.][0-9]+)?(ms|s))/)) {
        print substr(value, RSTART, RLENGTH)
      }
    }
  '
}

shreeos_duration_to_ms() {
  awk -v duration="${1:-}" 'BEGIN {
    if (duration ~ /^[0-9]+([.][0-9]+)?ms$/) {
      sub(/ms$/, "", duration)
      milliseconds = duration + 0
    } else if (duration ~ /^[0-9]+([.][0-9]+)?s$/) {
      sub(/s$/, "", duration)
      milliseconds = (duration + 0) * 1000
    } else if (duration ~ /^[0-9]+min([[:space:]]+[0-9]+([.][0-9]+)?s)?$/) {
      split(duration, parts, "min")
      milliseconds = (parts[1] + 0) * 60000
      if (parts[2] != "") {
        sub(/s$/, "", parts[2])
        milliseconds += (parts[2] + 0) * 1000
      }
    } else {
      print 0
      exit
    }
    if (milliseconds <= 0) print 0
    else printf "%.0f\n", milliseconds
  }'
}
