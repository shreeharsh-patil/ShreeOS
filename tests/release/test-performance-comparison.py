#!/usr/bin/env python3
"""Tests aggregate median performance acceptance and provenance checks."""

from __future__ import annotations

import importlib.util
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location(
    "compare_performance_runs", ROOT / "scripts" / "compare-performance-runs.py"
)
assert SPEC is not None and SPEC.loader is not None
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class PerformanceComparisonTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.directory = Path(self.temporary.name)
        self.candidate = self.directory / "candidate.tsv"
        self.baseline = self.directory / "baseline.tsv"
        self.targets = self.directory / "targets.tsv"
        self.metadata = {
            "source_commit": "a" * 40,
            "iso_sha256": "b" * 64,
            "conditions": "2-vCPU,4096MiB,virtio,1280x800,no-network,BIOS,SHREEOSPERF-64MiB-rw,host-cache-bypassed",
            "probe_sha256": "c" * 64,
            "probe_service_sha256": "d" * 64,
            "probe_timer_sha256": "0" * 64,
            "probe_time_helper_sha256": "e" * 64,
            "measurement_protocol_sha256": "1" * 64,
            "qemu_version": "QEMU emulator version 10.0.13",
            "qemu_package_version": "1:10.0.13+ds-0+deb13u1",
            "seabios_package_version": "1.16.3-2",
            "bios_rom_sha256": "f" * 64,
            "host_kernel": "Linux 6.12.0",
            "host_cpu_model": "Example CPU",
            "host_mem_total_kib": "8000000",
            "firmware": "SeaBIOS:/usr/share/seabios/bios-256k.bin:sha256=" + "f" * 64,
            "qemu_profile": "q35;4096MiB;2-vCPU;explicit-SeaBIOS",
            "sample_count": "3",
        }
        self.candidate_metrics = {
            "mem_used_mib": 800,
            "cpu_busy_pct": 1.5,
            "boot_total_ms": 11_000,
            "graphical_reached_ms": 13_000,
            "desktop_ready": 1,
            "pss_available": 1,
            "units_failed": 0,
            "storage_write_mib_s": 50,
            "storage_read_mib_s": 60,
        }
        self.baseline_metrics = {
            **self.candidate_metrics,
            "mem_used_mib": 1_000,
            "cpu_busy_pct": 4,
            "boot_total_ms": 10_000,
            "graphical_reached_ms": 12_000,
            "storage_write_mib_s": 10_000,
            "storage_read_mib_s": 10_000,
        }
        self._write_summary(self.candidate, self.metadata, self.candidate_metrics)
        baseline_metadata = dict(self.metadata)
        baseline_metadata["source_commit"] = MODULE.BASELINE_COMMIT
        baseline_metadata["iso_sha256"] = "9" * 64
        self._write_summary(self.baseline, baseline_metadata, self.baseline_metrics)
        self.targets.write_text(
            "desktop_ready\t1\tmin\tready\n"
            "pss_available\t1\tmin\tPSS\n"
            "mem_used_mib\t850\tmax\tRAM\n"
            "cpu_busy_pct\t2\tmax\tCPU\n"
            "units_failed\t0\tmax\tunits\n",
            encoding="utf-8",
        )

    def tearDown(self) -> None:
        self.temporary.cleanup()

    @staticmethod
    def _write_summary(path: Path, metadata: dict[str, str], metrics: dict[str, float]) -> None:
        lines = [f"# {key}={value}" for key, value in metadata.items()]
        lines.extend(f"{key}\t{value}" for key, value in metrics.items())
        path.write_text("\n".join(lines) + "\n", encoding="utf-8")

    def test_uses_medians_even_when_one_raw_sample_misses_a_target(self) -> None:
        # The aggregate encodes median=800 MiB and max=1000 MiB. The outlier
        # remains visible in variability metadata but does not become a single-run gate.
        with self.candidate.open("a", encoding="utf-8") as stream:
            stream.write("# variability_mem_used_mib=min:800,median:800,max:1000\n")
        failures, details = MODULE.evaluate(self.candidate, self.baseline, self.targets, True)
        self.assertEqual(failures, [])
        self.assertTrue(any("candidate median 800" in line for line in details))
        self.assertTrue(any("Storage throughput is reported for context only" in line for line in details))

    def test_rejects_candidate_median_that_misses_absolute_targets(self) -> None:
        metrics = dict(self.candidate_metrics)
        metrics["mem_used_mib"] = 900
        metrics["cpu_busy_pct"] = 2.5
        self._write_summary(self.candidate, self.metadata, metrics)
        failures, _ = MODULE.evaluate(self.candidate, self.baseline, self.targets, True)
        self.assertTrue(any("missed mem_used_mib" in failure for failure in failures))
        self.assertTrue(any("missed cpu_busy_pct" in failure for failure in failures))

    def test_rejects_qemu_or_firmware_environment_mismatch(self) -> None:
        metadata = dict(self.metadata)
        metadata["bios_rom_sha256"] = "0" * 64
        self._write_summary(self.candidate, metadata, self.candidate_metrics)
        failures, _ = MODULE.evaluate(self.candidate, self.baseline, self.targets, True)
        self.assertTrue(any("bios_rom_sha256" in failure for failure in failures))

    def test_rejects_a_different_measurement_protocol(self) -> None:
        metadata = dict(self.metadata)
        metadata["measurement_protocol_sha256"] = "2" * 64
        self._write_summary(self.candidate, metadata, self.candidate_metrics)
        failures, _ = MODULE.evaluate(self.candidate, self.baseline, self.targets, True)
        self.assertTrue(any("measurement_protocol_sha256" in failure for failure in failures))

    def test_required_baseline_must_exist_and_health_invariants_are_checked(self) -> None:
        failures, _ = MODULE.evaluate(self.candidate, None, self.targets, True)
        self.assertTrue(any("baseline is required" in failure for failure in failures))
        invalid = dict(self.candidate_metrics)
        invalid["units_failed"] = 1
        self._write_summary(self.candidate, self.metadata, invalid)
        with self.assertRaisesRegex(ValueError, "failed system units"):
            MODULE.evaluate(self.candidate, self.baseline, self.targets, True)


if __name__ == "__main__":
    unittest.main()
