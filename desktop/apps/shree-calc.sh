#!/usr/bin/env bash
# desktop/apps/shree-calc.sh — ShreeOS Native Calculator
#
# Minimalist, keyboard-first desktop calculator for arithmetic, powers, and percentages.

set -euo pipefail

run_calc() {
  while true; do
    EXPR=$(echo "" | dmenu -p "Calculator (e.g. 128 * 4 + 32):" -c)
    [ -z "$EXPR" ] && break

    if command -v bc >/dev/null 2>&1; then
      RES=$(echo "scale=4; $EXPR" | bc -l 2>/dev/null || echo "Error")
    else
      RES=$(awk "BEGIN {print $EXPR}" 2>/dev/null || echo "Error")
    fi

    shree-notify "Calculator" "${EXPR} = ${RES}" --app="Calculator"
  done
}

run_calc
