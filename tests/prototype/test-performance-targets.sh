#!/usr/bin/env bash
set -Eeuo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
# shellcheck source=scripts/performance-targets.sh
source "$REPO_ROOT/scripts/performance-targets.sh"

assert_result() {
  local label="$1" expected="$2" measured="$3" comparison="$4" limit="$5"
  local actual=1
  if performance_target_met "$measured" "$comparison" "$limit"; then
    actual=0
  fi
  if [[ "$actual" -ne "$expected" ]]; then
    printf 'Performance target comparison failed: %s\n' "$label" >&2
    exit 1
  fi
}

assert_result 'maximum boundary is allowed' 0 2 max 2
assert_result 'maximum overrun is rejected' 1 2.01 max 2
assert_result 'minimum boundary is allowed' 0 1 min 1
assert_result 'minimum shortfall is rejected' 1 0.99 min 1
assert_result 'nonnumeric metrics are rejected' 1 invalid max 2
assert_result 'unknown comparisons are rejected' 1 1 median 1

assert_improvement_result() {
  local label="$1" expected="$2" baseline_memory="$3" measured_memory="$4"
  local baseline_cpu="$5" measured_cpu="$6" actual=1
  if performance_improvement_or_efficiency_met \
    "$baseline_memory" "$measured_memory" "$baseline_cpu" "$measured_cpu"; then
    actual=0
  fi
  if [[ "$actual" -ne "$expected" ]]; then
    printf 'Performance improvement comparison failed: %s\n' "$label" >&2
    exit 1
  fi
}

assert_improvement_result '20% memory improvement is accepted' 0 1000 800 3 3
assert_improvement_result '20% CPU improvement is accepted' 0 1000 1000 3 2.4
assert_improvement_result 'smaller gains are insufficient' 1 1000 900 3 2.5
assert_improvement_result 'efficient untouched baseline is documented' 0 850 900 2 3
assert_improvement_result 'zero baseline CPU cannot count as an improvement' 1 1000 1000 0 0
assert_improvement_result 'invalid measurements are rejected' 1 invalid 900 3 2
printf 'Performance target comparison tests passed.\n'
