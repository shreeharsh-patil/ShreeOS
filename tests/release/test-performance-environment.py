#!/usr/bin/env python3
"""Tests normalization of cgroup limits used by the performance comparator."""

from __future__ import annotations

import importlib.util
import json
import tempfile
import unittest
from fractions import Fraction
from pathlib import Path
from unittest.mock import patch
from contextlib import redirect_stdout
from io import StringIO


ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location(
    "performance_environment", ROOT / "scripts" / "performance-environment.py"
)
assert SPEC is not None and SPEC.loader is not None
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class PerformanceEnvironmentTests(unittest.TestCase):
    def test_cpu_quota_uses_the_most_restrictive_visible_ancestor(self):
        self.assertEqual(
            MODULE.effective_cpu_quota(["max 100000", "250000 100000", "200000 100000"]),
            "2",
        )
        self.assertEqual(MODULE.effective_cpu_quota(["max 100000", "max 100000"]), "max")
        self.assertEqual(MODULE.parse_cpu_max("50000 100000"), Fraction(1, 2))

    def test_memory_and_process_limits_use_the_most_restrictive_ancestor(self):
        self.assertEqual(MODULE.effective_limit(["max", "9000000", "8000000"], "memory.max"), "8000000")
        self.assertEqual(MODULE.effective_limit(["max", "max"], "pids.max"), "max")

    def test_cpuset_ranges_are_counted_and_invalid_values_fail_closed(self):
        self.assertEqual(MODULE.cpuset_count("0-2,5,8-9"), 6)
        with self.assertRaisesRegex(ValueError, "invalid cpuset"):
            MODULE.cpuset_count("0-2,broken")

    def test_invalid_limits_fail_closed(self):
        with self.assertRaisesRegex(ValueError, "invalid cpu.max"):
            MODULE.parse_cpu_max("100000")
        with self.assertRaisesRegex(ValueError, "invalid memory.max"):
            MODULE.effective_limit(["unlimited"], "memory.max")

    def test_emits_cgroup_throttling_and_memory_event_deltas(self):
        before = {
            "cpu_stat": {"nr_periods": 5, "nr_throttled": 1, "throttled_usec": 50},
            "memory_events": {"oom": 0, "high": 2},
        }
        after = {
            "cpu_stat": {"nr_periods": 10, "nr_throttled": 3, "throttled_usec": 90},
            "memory_events": {"oom": 0, "high": 4},
        }
        with tempfile.TemporaryDirectory() as temporary:
            snapshot = Path(temporary) / "before.json"
            snapshot.write_text(json.dumps(before), encoding="utf-8")
            output = StringIO()
            with patch.object(MODULE, "collect_counters", return_value=after), redirect_stdout(output):
                MODULE.emit_counter_delta(snapshot)
        self.assertIn("# cgroup_cpu_stat_nr_throttled_delta=2", output.getvalue())
        self.assertIn("# cgroup_memory_events_high_delta=2", output.getvalue())
        self.assertIn("# cgroup_memory_events_oom_delta=0", output.getvalue())


if __name__ == "__main__":
    unittest.main()
