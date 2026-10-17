#!/usr/bin/env python3
"""Tests run identity and raw-sample verification for the measured baseline."""

from __future__ import annotations

import argparse
import importlib.util
import json
import shutil
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch


ROOT = Path(__file__).resolve().parents[2]


def load(name: str, path: Path):
    spec = importlib.util.spec_from_file_location(name, path)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


AGGREGATOR = load("aggregate_performance_runs", ROOT / "scripts/aggregate-performance-runs.py")
WRITER = load("write_performance_provenance", ROOT / "scripts/write-performance-provenance.py")
VERIFIER = load("verify_performance_baseline", ROOT / "scripts/verify-performance-baseline.py")


class PerformanceBaselineProvenanceTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)
        self.bundle = self.root / "bundle"
        self.bundle.mkdir()
        self.samples = [self.bundle / f"performance-sample-{index}.tsv" for index in range(1, 4)]
        self.metadata = {
            "source_commit": WRITER.BASELINE_SOURCE_COMMIT,
            "iso_sha256": "b" * 64,
            "conditions": "2-vCPU,4096MiB,virtio,1280x800,isolated-user-network,BIOS,SHREEOSPERF-64MiB-rw,host-cache-bypassed",
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
            "cgroup_version": "2",
            "cgroup_cpuset_cpus_effective": "0-3",
            "cgroup_cpuset_cpu_count": "4",
            "cgroup_cpu_quota_cores": "4",
            "cgroup_memory_max_bytes": "max",
            "cgroup_memory_high_bytes": "max",
            "cgroup_memory_swap_max_bytes": "max",
            "cgroup_pids_max": "max",
            "process_capeff": "00000000a00425fb",
            "process_capbnd": "00000000a00425fb",
            "process_nonewprivs": "0",
            "process_seccomp": "2",
            "process_seccomp_filters": "1",
            "firmware": "SeaBIOS:/usr/share/seabios/bios-256k.bin:sha256=" + "f" * 64,
            "qemu_profile": "q35;4096MiB;2-vCPU;cache=none;explicit-SeaBIOS",
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
        }
        for index, path in enumerate(self.samples, 1):
            metadata = {**self.metadata, "qemu_command": f"qemu-system-x86_64 -machine q35 -run {index}"}
            metrics = {
                key: value + index if key in {
                    "mem_used_mib", "cpu_busy_pct", "boot_total_ms",
                    "graphical_reached_ms", "storage_write_mib_s", "storage_read_mib_s",
                } else value
                for key, value in self.metrics.items()
            }
            path.write_text(
                "\n".join([*(f"# {key}={value}" for key, value in metadata.items()),
                           *(f"{key}\t{value}" for key, value in metrics.items())]) + "\n",
                encoding="utf-8",
            )
        self.baseline = self.bundle / VERIFIER.BASELINE_NAME
        AGGREGATOR.write_summary(
            self.baseline,
            self.bundle / "summary.md",
            self.samples,
        )
        self.provenance = self.bundle / "provenance.json"
        WRITER.write_provenance(argparse.Namespace(
            output=self.provenance,
            baseline=self.baseline,
            sample=self.samples,
            repository="owner/repo",
            run_id="12345",
            run_attempt="1",
            harness_commit="a" * 40,
            artifact_name="shreeos-performance-baseline-12345-1",
        ))
        self.tracked_baseline = self.root / "tracked-baseline.tsv"
        self.tracked_provenance = self.root / "tracked-provenance.json"
        shutil.copyfile(self.baseline, self.tracked_baseline)
        shutil.copyfile(self.provenance, self.tracked_provenance)

    def tearDown(self) -> None:
        self.temporary.cleanup()

    def test_reaggregates_raw_samples_and_matches_committed_files(self):
        verified = VERIFIER.validate_bundle(
            self.bundle, self.tracked_baseline, self.tracked_provenance, "owner/repo",
        )
        self.assertEqual(verified["run_id"], "12345")
        self.assertEqual(verified["sample_count"], 3)

    def test_detects_a_tampered_raw_sample(self):
        with self.samples[1].open("a", encoding="utf-8") as stream:
            stream.write("# altered=true\n")
        with self.assertRaisesRegex(ValueError, "wrong digest"):
            VERIFIER.validate_bundle(
                self.bundle, self.tracked_baseline, self.tracked_provenance, "owner/repo",
            )

    def test_run_must_be_successful_and_match_the_recorded_head_and_workflow(self):
        run = {
            "id": 12345,
            "status": "completed",
            "conclusion": "success",
            "event": "workflow_dispatch",
            "run_attempt": 1,
            "path": ".github/workflows/performance-baseline.yml",
            "head_sha": "a" * 40,
            "repository": {"full_name": "owner/repo"},
            "head_repository": {"full_name": "owner/repo"},
        }
        artifacts = {
            "artifacts": [{
                "name": "shreeos-performance-baseline-12345-1",
                "expired": False,
                "workflow_run": {"id": 12345},
            }]
        }
        with patch.object(VERIFIER, "github_json", side_effect=[run, artifacts]):
            VERIFIER.validate_run("owner/repo", json.loads(self.provenance.read_text()))
        run["conclusion"] = "failure"
        with patch.object(VERIFIER, "github_json", side_effect=[run]):
            with self.assertRaisesRegex(ValueError, "did not complete successfully"):
                VERIFIER.validate_run("owner/repo", json.loads(self.provenance.read_text()))


if __name__ == "__main__":
    unittest.main()
