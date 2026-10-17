#!/usr/bin/env python3
"""Tests repeated performance sample provenance and median/range reporting."""

from __future__ import annotations

import importlib.util
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location(
    "aggregate_performance_runs", ROOT / "scripts" / "aggregate-performance-runs.py"
)
assert SPEC is not None and SPEC.loader is not None
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class PerformanceAggregationTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.directory = Path(self.temporary.name)
        self.samples = [self.directory / "run-1.tsv", self.directory / "run-2.tsv"]
        self.metadata = {
            "source_commit": "a" * 40,
            "iso_sha256": "b" * 64,
            "conditions": "2-vCPU,4096MiB,virtio,1280x800,no-network,BIOS,SHREEOSPERF-64MiB-rw,host-cache-bypassed",
            "probe_sha256": "c" * 64,
            "probe_service_sha256": "d" * 64,
            "probe_timer_sha256": "0" * 64,
            "probe_time_helper_sha256": "e" * 64,
            "measurement_protocol_sha256": "1" * 64,
            "qemu_version": "QEMU emulator version 10.0.0",
            "qemu_package_version": "1:10.0.13+ds-0+deb13u1",
            "seabios_package_version": "1.16.3-2",
            "bios_rom_sha256": "f" * 64,
            "host_kernel": "Linux 6.8.0",
            "host_cpu_model": "Example CPU",
            "host_mem_total_kib": "8000000",
            "cgroup_limit_scope": "visible-hierarchy-ancestors",
            "cgroup_memory_event_scope": "visible-hierarchy-local-events",
            "cgroup_reported_path_shape": "non-root",
            "cgroup_mount_root_path_shape": "subpath",
            "cgroup_version": "2",
            "cgroup_cpuset_cpus_effective": "0-3",
            "cgroup_cpuset_cpu_count": "4",
            "cgroup_cpu_quota_cores": "4",
            "cgroup_memory_max_bytes": "max",
            "cgroup_memory_high_bytes": "max",
            "cgroup_memory_swap_max_bytes": "max",
            "cgroup_pids_max": "max",
            "collector_capeff": "00000000a00425fb",
            "collector_capbnd": "00000000a00425fb",
            "collector_nonewprivs": "0",
            "collector_seccomp": "2",
            "collector_seccomp_filters": "1",
            "qemu_process_capeff": "00000000a00425fb",
            "qemu_process_capbnd": "00000000a00425fb",
            "qemu_process_nonewprivs": "0",
            "qemu_process_seccomp": "2",
            "qemu_process_seccomp_filters": "1",
            "firmware": "SeaBIOS:/usr/share/seabios/bios-256k.bin:sha256=" + "f" * 64,
            "qemu_profile": "q35;4096MiB;2-vCPU;cache=none;explicit-SeaBIOS",
            "qemu_command": "qemu-system-x86_64 -machine q35",
        }
        self.metrics = {
            "mem_used_mib": 800,
            "cpu_busy_pct": 1,
            "boot_total_ms": 12_000,
            "graphical_reached_ms": 10_000,
            "desktop_ready": 1,
            "pss_available": 1,
            "units_failed": 0,
            "storage_write_mib_s": 100,
            "storage_read_mib_s": 200,
            "cgroup_cpu_stat_nr_periods_delta": 100,
            "cgroup_cpu_stat_nr_throttled_delta": 2,
            "cgroup_cpu_stat_throttled_usec_delta": 250,
            "cgroup_cpu_stat_throttled_usec_local_delta": 1000,
            "cgroup_capture_elapsed_usec": 1_000_000,
            "cgroup_memory_events_low_visible_max_delta": 0,
            "cgroup_memory_events_high_visible_max_delta": 0,
            "cgroup_memory_events_max_visible_max_delta": 0,
            "cgroup_memory_events_oom_visible_max_delta": 0,
            "cgroup_memory_events_oom_kill_visible_max_delta": 0,
            "cgroup_memory_events_oom_group_kill_visible_max_delta": 0,
        }
        self._write_sample(self.samples[0], self.metrics)
        self._write_sample(
            self.samples[1], {
                key: value * 2 if key in {
                    "mem_used_mib", "cpu_busy_pct", "boot_total_ms",
                    "graphical_reached_ms", "storage_write_mib_s", "storage_read_mib_s",
                } else value
                for key, value in self.metrics.items()
            }
        )

    def tearDown(self) -> None:
        self.temporary.cleanup()

    def _write_sample(self, path: Path, metrics: dict[str, float]) -> None:
        lines = [f"# {key}={value}" for key, value in self.metadata.items()]
        lines.extend(f"{key}\t{value}" for key, value in metrics.items())
        path.write_text("\n".join(lines) + "\n", encoding="utf-8")

    def test_writes_median_and_minimum_maximum_variability(self) -> None:
        output = self.directory / "summary.tsv"
        report = self.directory / "summary.md"
        MODULE.write_summary(output, report, self.samples)
        summary = output.read_text(encoding="utf-8")
        self.assertIn("# sample_count=2\n", summary)
        self.assertIn("# sample_1_qemu_command=qemu-system-x86_64 -machine q35\n", summary)
        self.assertIn("# variability_mem_used_mib=min:800,median:1200,max:1600\n", summary)
        self.assertIn("mem_used_mib\t1200\n", summary)
        self.assertIn("cgroup_cpu_stat_nr_throttled_delta\t2\n", summary)
        self.assertIn("cgroup_cpu_throttled_period_pct\t2\n", summary)
        self.assertIn("cgroup_cpu_local_throttled_capacity_estimate_pct\t0.03\n", summary)
        self.assertIn("| mem_used_mib | 800 | 1200 | 1600 |", report.read_text(encoding="utf-8"))

    def test_rejects_samples_with_different_host_or_iso_provenance(self) -> None:
        changed = dict(self.metadata)
        changed["host_cpu_model"] = "Different CPU"
        lines = [f"# {key}={value}" for key, value in changed.items()]
        lines.extend(f"{key}\t{value}" for key, value in self.metrics.items())
        self.samples[1].write_text("\n".join(lines) + "\n", encoding="utf-8")
        with self.assertRaisesRegex(ValueError, "sample environment/provenance differs"):
            MODULE.aggregate(self.samples)

    def test_retains_unique_commands_without_treating_temp_paths_as_environment(self) -> None:
        changed = dict(self.metadata)
        changed["qemu_command"] = "qemu-system-x86_64 -drive file=/tmp/run-2/target.raw"
        lines = [f"# {key}={value}" for key, value in changed.items()]
        lines.extend(f"{key}\t{value}" for key, value in self.metrics.items())
        self.samples[1].write_text("\n".join(lines) + "\n", encoding="utf-8")
        output = self.directory / "summary.tsv"
        report = self.directory / "summary.md"
        MODULE.write_summary(output, report, self.samples)
        summary = output.read_text(encoding="utf-8")
        self.assertIn("# sample_2_qemu_command=qemu-system-x86_64 -drive file=/tmp/run-2/target.raw\n", summary)
        self.assertIn("qemu_profile=q35;4096MiB;2-vCPU;cache=none;explicit-SeaBIOS", summary)

    def test_rejects_non_ready_desktop_and_one_sample(self) -> None:
        values = dict(self.metrics)
        values["desktop_ready"] = 0
        self._write_sample(self.samples[1], values)
        with self.assertRaisesRegex(ValueError, "desktop was not ready"):
            MODULE.aggregate(self.samples)
        with self.assertRaisesRegex(ValueError, "at least two"):
            MODULE.aggregate(self.samples[:1])

    def test_rejects_failed_health_invariants_in_any_sample(self) -> None:
        values = dict(self.metrics)
        values["units_failed"] = 1
        self._write_sample(self.samples[1], values)
        with self.assertRaisesRegex(ValueError, "failed system units"):
            MODULE.aggregate(self.samples)

        values["units_failed"] = 0
        values["pss_available"] = 0
        self._write_sample(self.samples[1], values)
        with self.assertRaisesRegex(ValueError, "PSS was unavailable"):
            MODULE.aggregate(self.samples)

    def test_resource_counter_deltas_are_required_and_memory_pressure_fails_closed(self) -> None:
        values = dict(self.metrics)
        values["cgroup_memory_events_oom_kill_visible_max_delta"] = 1
        self._write_sample(self.samples[1], values)
        with self.assertRaisesRegex(ValueError, "cgroup memory pressure"):
            MODULE.aggregate(self.samples)

        values = dict(self.metrics)
        values["cgroup_memory_events_low_visible_max_delta"] = 1
        self._write_sample(self.samples[1], values)
        with self.assertRaisesRegex(ValueError, "cgroup memory pressure"):
            MODULE.aggregate(self.samples)

        values = dict(self.metrics)
        del values["cgroup_cpu_stat_nr_periods_delta"]
        self._write_sample(self.samples[1], values)
        with self.assertRaisesRegex(ValueError, "or metrics"):
            MODULE.aggregate(self.samples)

        values = dict(self.metrics)
        values["cgroup_cpu_stat_nr_throttled_delta"] = 11
        self._write_sample(self.samples[1], values)
        with self.assertRaisesRegex(ValueError, "CPU throttling exceeded"):
            MODULE.aggregate(self.samples)

        values = dict(self.metrics)
        values["cgroup_cpu_stat_throttled_usec_local_delta"] = 500_000
        self._write_sample(self.samples[1], values)
        with self.assertRaisesRegex(ValueError, "CPU throttling exceeded"):
            MODULE.aggregate(self.samples)

    def test_unlimited_leaf_period_counters_can_be_zero_when_local_throttling_is_clear(self) -> None:
        values = dict(self.metrics)
        values["cgroup_cpu_stat_nr_periods_delta"] = 0
        values["cgroup_cpu_stat_nr_throttled_delta"] = 0
        values["cgroup_cpu_stat_throttled_usec_delta"] = 0
        self._write_sample(self.samples[1], values)
        _, parsed = MODULE.parse_sample(self.samples[1])
        self.assertEqual(parsed["cgroup_cpu_throttled_period_pct"], 0)

        values["cgroup_cpu_stat_nr_throttled_delta"] = 1
        self._write_sample(self.samples[1], values)
        with self.assertRaisesRegex(ValueError, "invalid cgroup CPU throttling"):
            MODULE.parse_sample(self.samples[1])


if __name__ == "__main__":
    unittest.main()
