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
            "cpu_stat_local": {"throttled_usec": 10},
            "memory_events_local": {
                "level_0": {"oom": 0, "low": 0, "high": 2},
                "level_1": {"oom": 0, "low": 0, "high": 1},
            },
            "captured_monotonic_ns": 1_000_000_000,
        }
        after = {
            "cpu_stat": {"nr_periods": 10, "nr_throttled": 3, "throttled_usec": 90},
            "cpu_stat_local": {"throttled_usec": 50},
            "memory_events_local": {
                "level_0": {"oom": 0, "low": 0, "high": 2},
                "level_1": {"oom": 0, "low": 1, "high": 3},
            },
            "captured_monotonic_ns": 2_000_000_000,
        }
        with tempfile.TemporaryDirectory() as temporary:
            snapshot = Path(temporary) / "before.json"
            snapshot.write_text(json.dumps(before), encoding="utf-8")
            output = StringIO()
            with patch.object(MODULE, "collect_counters", return_value=after), redirect_stdout(output):
                MODULE.emit_counter_delta(snapshot)
        self.assertIn("# cgroup_cpu_stat_nr_throttled_delta=2", output.getvalue())
        self.assertIn("# cgroup_cpu_stat_throttled_usec_local_delta=40", output.getvalue())
        self.assertIn("# cgroup_memory_events_high_visible_max_delta=2", output.getvalue())
        self.assertIn("# cgroup_memory_events_low_visible_max_delta=1", output.getvalue())
        self.assertIn("# cgroup_memory_events_oom_visible_max_delta=0", output.getvalue())
        self.assertIn("# cgroup_capture_elapsed_usec=1000000", output.getvalue())

    def test_process_metadata_can_be_read_from_the_live_qemu_pid(self):
        status = {
            "CapEff": "00000000a00425fb",
            "CapBnd": "00000000a00425fb",
            "NoNewPrivs": "0",
            "Seccomp": "2",
            "Seccomp_filters": "1",
        }
        with patch.object(MODULE, "verify_qemu_pid") as verify_qemu_pid, \
                patch.object(MODULE, "verify_same_cgroup") as verify_same_cgroup, \
                patch.object(MODULE, "process_status", return_value=status) as process_status:
            rows = dict(MODULE.collect_process(4242))
        verify_qemu_pid.assert_called_once_with(4242)
        verify_same_cgroup.assert_called_once_with(4242)
        process_status.assert_called_once_with(4242)
        self.assertEqual(set(rows), {
            "qemu_process_capeff", "qemu_process_capbnd", "qemu_process_nonewprivs",
            "qemu_process_seccomp", "qemu_process_seccomp_filters",
        })
        with self.assertRaisesRegex(ValueError, "must be positive"):
            MODULE.collect_process(0)

    def test_qemu_pid_must_resolve_to_the_expected_executable(self):
        with patch.object(MODULE.Path, "resolve", return_value=Path("/usr/bin/qemu-system-x86_64")):
            MODULE.verify_qemu_pid(42)
        with patch.object(MODULE.Path, "resolve", return_value=Path("/usr/bin/python3")):
            with self.assertRaisesRegex(ValueError, "not the expected qemu"):
                MODULE.verify_qemu_pid(42)

    def test_qemu_must_share_the_sampled_cgroup(self):
        with patch.object(MODULE, "cgroup_directory", side_effect=[(Path("/sys/fs/cgroup/a"), Path("/sys/fs/cgroup")), (Path("/sys/fs/cgroup/a/b"), Path("/sys/fs/cgroup"))]):
            with self.assertRaisesRegex(ValueError, "not in the cgroup"):
                MODULE.verify_same_cgroup(42)

    def test_every_visible_ancestor_must_expose_local_memory_events(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            leaf = root / "leaf"
            leaf.mkdir()
            (leaf / "cpu.stat").write_text("nr_periods 0\nnr_throttled 0\nthrottled_usec 0\n", encoding="ascii")
            (leaf / "cpu.stat.local").write_text("throttled_usec 0\n", encoding="ascii")
            (leaf / "memory.events.local").write_text(
                "low 0\nhigh 0\nmax 0\noom 0\noom_kill 0\noom_group_kill 0\n",
                encoding="ascii",
            )
            with patch.object(MODULE, "cgroup_directory", return_value=(leaf, root)), \
                    patch.object(MODULE, "ancestors", return_value=[leaf, root]):
                with self.assertRaisesRegex(ValueError, "unavailable at visible cgroup level 1"):
                    MODULE.collect_counters()

    def test_cgroup_path_metadata_does_not_claim_to_identify_hidden_ancestors(self):
        with patch.object(MODULE, "process_cgroup_path", return_value=Path("/")):
            self.assertEqual(MODULE.cgroup_reported_path_shape(), "root")
        with patch.object(MODULE, "cgroup_mount", return_value=(Path("/tenant/job"), Path("/sys/fs/cgroup"))):
            self.assertEqual(MODULE.cgroup_mount_root_path_shape(), "subpath")


if __name__ == "__main__":
    unittest.main()
