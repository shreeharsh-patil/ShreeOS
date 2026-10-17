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
from types import SimpleNamespace
from unittest.mock import patch

import yaml


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
            "cgroup_cpu_stat_nr_throttled_delta": 1,
            "cgroup_cpu_stat_throttled_usec_delta": 50,
            "cgroup_cpu_stat_throttled_usec_local_delta": 100,
            "cgroup_capture_elapsed_usec": 1_000_000,
            "cgroup_memory_events_low_visible_max_delta": 0,
            "cgroup_memory_events_high_visible_max_delta": 0,
            "cgroup_memory_events_max_visible_max_delta": 0,
            "cgroup_memory_events_oom_visible_max_delta": 0,
            "cgroup_memory_events_oom_kill_visible_max_delta": 0,
            "cgroup_memory_events_oom_group_kill_visible_max_delta": 0,
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
        self.raw_evidence = self.bundle / "raw-evidence"
        for index in range(1, 4):
            run = self.raw_evidence / f"run-{index}"
            run.mkdir(parents=True)
            (run / "qemu.log").write_text(f"QEMU diagnostic output for run {index}\n", encoding="utf-8")
            sample_values = {
                key: value
                for line in self.samples[index - 1].read_text(encoding="utf-8").splitlines()
                if line and not line.startswith("# ")
                for key, value in [line.split("\t", 1)]
            }
            product_metrics = {key: sample_values[key] for key in AGGREGATOR.METRICS}
            serial_lines = [f"SHREEOS_PERF {key}={value}" for key, value in product_metrics.items()]
            serial_lines.append(f"SHREEOS_PERF_END run={index}")
            (run / "serial.log").write_text("\n".join(serial_lines) + "\n", encoding="utf-8")
            (run / "monitor.log").write_text(f"QEMU monitor output for run {index}\n", encoding="utf-8")
            metric_rows = sorted(f"{key}\t{value}" for key, value in product_metrics.items())
            (run / "metrics.tsv").write_text("".join(f"{row}\n" for row in metric_rows), encoding="utf-8")
            delta_lines = [
                f"# {key}={value}"
                for key, value in self.metrics.items()
                if key in AGGREGATOR.RESOURCE_COUNTERS
            ]
            (run / "environment-deltas.txt").write_text("\n".join(delta_lines) + "\n", encoding="utf-8")
            shutil.copyfile(self.samples[index - 1], run / "performance-candidate.tsv")
        self.baseline = self.bundle / VERIFIER.BASELINE_NAME
        AGGREGATOR.write_summary(
            self.baseline,
            self.root / "summary.md",
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
            raw_evidence=self.raw_evidence,
        ))
        (self.bundle / VERIFIER.ATTESTATION_BUNDLE_NAME).write_text(
            '{"signed":"test fixture"}\n', encoding="utf-8",
        )
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

    def test_verifies_raw_qemu_logs_and_detects_tampering(self):
        verified = VERIFIER.validate_bundle(
            self.bundle, self.tracked_baseline, self.tracked_provenance, "owner/repo",
        )
        self.assertEqual(len(verified["raw_evidence_files"]), 18)
        with (self.raw_evidence / "run-2" / "serial.log").open("a", encoding="utf-8") as stream:
            stream.write("tampered\n")
        with self.assertRaisesRegex(ValueError, "raw evidence file is missing or has the wrong digest"):
            VERIFIER.validate_bundle(
                self.bundle, self.tracked_baseline, self.tracked_provenance, "owner/repo",
            )

    def test_recomputes_parsed_metrics_from_the_serial_log(self):
        metrics_path = self.raw_evidence / "run-2" / "metrics.tsv"
        metrics_path.write_text(metrics_path.read_text(encoding="utf-8") + "boot_total_ms\t99999\n", encoding="utf-8")
        WRITER.write_provenance(argparse.Namespace(
            output=self.provenance,
            baseline=self.baseline,
            sample=self.samples,
            repository="owner/repo",
            run_id="12345",
            run_attempt="1",
            harness_commit="a" * 40,
            artifact_name="shreeos-performance-baseline-12345-1",
            raw_evidence=self.raw_evidence,
        ))
        shutil.copyfile(self.provenance, self.tracked_provenance)
        with self.assertRaisesRegex(ValueError, "parsed metrics do not match its raw serial log"):
            VERIFIER.validate_bundle(
                self.bundle, self.tracked_baseline, self.tracked_provenance, "owner/repo",
            )

    def test_attested_manifest_digest_is_bound_to_its_contents(self):
        manifest = self.bundle / VERIFIER.CHECKSUM_MANIFEST_NAME
        value = manifest.read_text(encoding="utf-8")
        manifest.write_text("0" + value[1:], encoding="utf-8")
        with self.assertRaisesRegex(ValueError, "attested checksum manifest does not match"):
            VERIFIER.validate_bundle(
                self.bundle, self.tracked_baseline, self.tracked_provenance, "owner/repo",
            )

    def test_attestation_verification_pins_repository_and_workflow_identity(self):
        expected_invocation = "https://github.com/owner/repo/actions/runs/12345/attempts/1"
        response = [{"verificationResult": {"signature": {"certificate": {
            "runnerInvocationUri": expected_invocation,
            "sourceRepositoryDigest": "a" * 40,
        }}}}]
        with patch.object(
            VERIFIER.subprocess, "run", return_value=SimpleNamespace(stdout=json.dumps(response)),
        ) as run:
            VERIFIER.verify_attestation(self.bundle, "owner/repo", "12345", "1", "a" * 40)
        command = run.call_args.args[0]
        self.assertEqual(command[:3], ["gh", "attestation", "verify"])
        self.assertIn("--repo", command)
        self.assertIn("owner/repo", command)
        self.assertIn("--signer-workflow", command)
        self.assertIn("owner/repo/.github/workflows/performance-baseline.yml", command)
        self.assertIn("--source-digest", command)
        self.assertIn("a" * 40, command)
        self.assertIn("--bundle", command)
        with patch.object(
            VERIFIER.subprocess, "run", return_value=SimpleNamespace(stdout=json.dumps([{
                "verificationResult": {"signature": {"certificate": {
                    "runnerInvocationUri": "https://github.com/owner/repo/actions/runs/other/attempts/1",
                    "sourceRepositoryDigest": "a" * 40,
                }}}
            }])),
        ):
            with self.assertRaisesRegex(ValueError, "recorded workflow run attempt"):
                VERIFIER.verify_attestation(self.bundle, "owner/repo", "12345", "1", "a" * 40)

    def test_run_must_be_successful_and_match_the_recorded_head_and_workflow(self):
        run = {
            "id": 12345,
            "status": "completed",
            "conclusion": "success",
            "event": "workflow_dispatch",
            "run_attempt": 1,
            "path": ".github/workflows/performance-baseline.yml",
            "head_sha": "a" * 40,
            "head_branch": "main",
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
        jobs = {"jobs": [{"steps": [{
            "name": VERIFIER.REUSABLE_ARTIFACT_STEP,
            "conclusion": "success",
        }]}]}
        repository = {"default_branch": "main"}
        with patch.object(VERIFIER, "github_json", side_effect=[run, repository, jobs, artifacts]):
            self.assertTrue(VERIFIER.validate_run("owner/repo", json.loads(self.provenance.read_text())))
        run["conclusion"] = "failure"
        with patch.object(VERIFIER, "github_json", side_effect=[run, repository]):
            with self.assertRaisesRegex(ValueError, "did not complete successfully"):
                VERIFIER.validate_run("owner/repo", json.loads(self.provenance.read_text()))

    def test_baseline_run_must_come_from_the_reviewed_default_branch(self):
        run = {
            "id": 12345,
            "status": "completed",
            "conclusion": "success",
            "event": "workflow_dispatch",
            "run_attempt": 1,
            "path": ".github/workflows/performance-baseline.yml",
            "head_sha": "a" * 40,
            "head_branch": "feature/unreviewed",
            "repository": {"full_name": "owner/repo"},
            "head_repository": {"full_name": "owner/repo"},
        }
        with patch.object(VERIFIER, "github_json", side_effect=[run, {"default_branch": "main"}]):
            with self.assertRaisesRegex(ValueError, "repository default branch"):
                VERIFIER.validate_run("owner/repo", json.loads(self.provenance.read_text()))

    def test_durable_evidence_artifact_contains_verifier_sample_layout(self):
        workflow = yaml.safe_load((ROOT / ".github/workflows/performance-baseline.yml").read_text())
        steps = workflow["jobs"]["measure-baseline"]["steps"]
        prepare = next(step for step in steps if step.get("name") == "Prepare run-bound reusable baseline artifact")
        run = prepare["run"]
        self.assertIn('"baseline-evidence/performance-sample-$sample.tsv"', run)
        self.assertIn('cp -a "$bundle/raw-evidence" baseline-evidence/raw-evidence', run)

    def test_expired_artifact_is_reported_but_durable_evidence_remains_usable(self):
        run = {
            "id": 12345,
            "status": "completed",
            "conclusion": "success",
            "event": "workflow_dispatch",
            "run_attempt": 1,
            "path": ".github/workflows/performance-baseline.yml",
            "head_sha": "a" * 40,
            "head_branch": "main",
            "repository": {"full_name": "owner/repo"},
            "head_repository": {"full_name": "owner/repo"},
        }
        artifacts = {
            "artifacts": [{
                "name": "shreeos-performance-baseline-12345-1",
                "expired": True,
                "workflow_run": {"id": 12345},
            }]
        }
        jobs = {"jobs": [{"steps": [{
            "name": VERIFIER.REUSABLE_ARTIFACT_STEP,
            "conclusion": "success",
        }]}]}
        repository = {"default_branch": "main"}
        with patch.object(VERIFIER, "github_json", side_effect=[run, repository, jobs, artifacts]):
            self.assertFalse(VERIFIER.validate_run("owner/repo", json.loads(self.provenance.read_text())))

        with patch.object(VERIFIER, "github_json", side_effect=[run, repository, jobs, artifacts]), \
                patch.object(VERIFIER, "verify_attestation"):
            result = VERIFIER.main([
                "verify-performance-baseline.py",
                "--repository", "owner/repo",
                "--baseline", str(self.tracked_baseline),
                "--provenance", str(self.tracked_provenance),
                "--evidence-dir", str(self.bundle),
                "--download-dir", str(self.root / "unused-download"),
            ])
        self.assertEqual(result, 0)


if __name__ == "__main__":
    unittest.main()
