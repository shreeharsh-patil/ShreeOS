#!/usr/bin/env bash

# Return success only when MEASURED satisfies the configured COMPARISON LIMIT.
performance_target_met() {
  if [[ "$#" -ne 3 ]]; then
    return 2
  fi

  local measured="$1"
  local comparison="$2"
  local limit="$3"

  [[ "$measured" =~ ^[0-9]+([.][0-9]+)?$ ]] || return 2
  [[ "$limit" =~ ^[0-9]+([.][0-9]+)?$ ]] || return 2

  case "$comparison" in
    max)
      awk -v measured="$measured" -v limit="$limit" \
        'BEGIN { exit (measured <= limit) ? 0 : 1 }'
      ;;
    min)
      awk -v measured="$measured" -v limit="$limit" \
        'BEGIN { exit (measured >= limit) ? 0 : 1 }'
      ;;
    *) return 2 ;;
  esac
}

# Require a 20% memory or CPU reduction unless the untouched build already met
# both idle limits. Absolute targets are enforced separately.
performance_improvement_or_efficiency_met() {
  if [[ "$#" -ne 4 ]]; then
    return 2
  fi

  local baseline_memory="$1"
  local measured_memory="$2"
  local baseline_cpu="$3"
  local measured_cpu="$4"
  local value

  for value in "$baseline_memory" "$measured_memory" "$baseline_cpu" "$measured_cpu"; do
    [[ "$value" =~ ^[0-9]+([.][0-9]+)?$ ]] || return 2
  done

  awk -v baseline_memory="$baseline_memory" -v measured_memory="$measured_memory" \
    -v baseline_cpu="$baseline_cpu" -v measured_cpu="$measured_cpu" \
    'BEGIN {
      if (baseline_memory <= 850 && baseline_cpu <= 2) exit 0
      memory_improved = baseline_memory > 0 && measured_memory <= baseline_memory * 0.8
      cpu_improved = baseline_cpu > 0 && measured_cpu <= baseline_cpu * 0.8
      exit (memory_improved || cpu_improved) ? 0 : 1
    }'
}
