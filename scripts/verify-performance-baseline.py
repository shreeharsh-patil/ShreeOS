#!/usr/bin/env python3
"""Verify that a committed performance baseline came from a successful exact workflow run."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path


BASELINE_SOURCE_COMMIT = "9313ebb042cf71bb148441037940b130d49920d1"
WORKFLOW_PATH = ".github/workflows/performance-baseline.yml"
BASELINE_NAME = "performance-baseline.tsv"
SAMPLE_NAMES = tuple(f"performance-sample-{index}.tsv" for index in range(1, 4))
REUSABLE_ARTIFACT_STEP = "Upload the reusable measured baseline and raw sample TSVs"
CHECKSUM_MANIFEST_NAME = "performance-baseline.sha256"
ATTESTATION_BUNDLE_NAME = "performance-baseline.attestation.json"
RESOURCE_COUNTERS = (
    "cgroup_cpu_stat_nr_periods_delta",
    "cgroup_cpu_stat_nr_throttled_delta",
    "cgroup_cpu_stat_throttled_usec_delta",
    "cgroup_cpu_stat_throttled_usec_local_delta",
    "cgroup_capture_elapsed_usec",
    "cgroup_memory_events_low_visible_max_delta",
    "cgroup_memory_events_high_visible_max_delta",
    "cgroup_memory_events_max_visible_max_delta",
    "cgroup_memory_events_oom_visible_max_delta",
    "cgroup_memory_events_oom_kill_visible_max_delta",
    "cgroup_memory_events_oom_group_kill_visible_max_delta",
)
PRODUCT_METRICS = (
    "mem_used_mib", "cpu_busy_pct", "boot_total_ms", "graphical_reached_ms",
    "desktop_ready", "pss_available", "units_failed",
    "storage_write_mib_s", "storage_read_mib_s",
)


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def metadata(path: Path) -> dict[str, str]:
    result: dict[str, str] = {}
    for number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        if not line.startswith("# "):
            continue
        key, separator, value = line[2:].partition("=")
        if separator:
            if key in result:
                raise ValueError(f"duplicate metadata field {key!r} in {path}:{number}")
            result[key] = value
    return result


def decode_json(raw: str, label: str) -> dict:
    try:
        value = json.loads(raw)
    except json.JSONDecodeError as error:
        raise ValueError(f"GitHub returned invalid JSON for {label}: {error}") from error
    if not isinstance(value, dict):
        raise ValueError(f"GitHub returned an unexpected response for {label}")
    return value


def github_json(endpoint: str) -> dict:
    result = subprocess.run(
        ["gh", "api", endpoint], check=True, capture_output=True, text=True,
        env=os.environ.copy(),
    )
    return decode_json(result.stdout, endpoint)


def checksum_manifest_text(bundle: Path) -> str:
    rows = []
    for path in sorted(bundle.rglob("*")):
        if path.is_symlink():
            raise ValueError(f"baseline bundle contains a symlink: {path}")
        if not path.is_file() or path.name in {CHECKSUM_MANIFEST_NAME, ATTESTATION_BUNDLE_NAME}:
            continue
        relative = path.relative_to(bundle).as_posix()
        rows.append(f"{sha256(path)}  {relative}\n")
    return "".join(rows)


def serial_metrics_text(serial: str) -> str:
    rows = set()
    marker = "SHREEOS_PERF "
    for line in serial.splitlines():
        position = line.find(marker)
        if position < 0:
            continue
        payload = line[position + len(marker):]
        key, separator, value = payload.partition("=")
        if separator and key:
            rows.add(f"{key}\t{value}")
    return "" if not rows else "".join(f"{row}\n" for row in sorted(rows))


def parse_metric_tsv(path: Path) -> dict[str, str]:
    result = {}
    for number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        key, separator, value = line.partition("\t")
        if not separator or not key or key in result:
            raise ValueError(f"invalid or duplicate metric row in {path}:{number}")
        result[key] = value
    return result


def string_values(value: object):
    if isinstance(value, str):
        yield value
    elif isinstance(value, dict):
        for child in value.values():
            yield from string_values(child)
    elif isinstance(value, list):
        for child in value:
            yield from string_values(child)


def verify_attestation(
    bundle: Path, repository: str, run_id: str, run_attempt: str, harness_commit: str,
) -> None:
    manifest = bundle / CHECKSUM_MANIFEST_NAME
    attestation = bundle / ATTESTATION_BUNDLE_NAME
    if not manifest.is_file() or not attestation.is_file() or not attestation.stat().st_size:
        raise ValueError("durable baseline evidence has no signed checksum manifest")
    result = subprocess.run(
        [
            "gh", "attestation", "verify", str(manifest),
            "--repo", repository,
            "--signer-workflow", f"{repository}/{WORKFLOW_PATH}",
            "--source-digest", harness_commit,
            "--bundle", str(attestation),
            "--format", "json",
        ],
        check=True,
        capture_output=True,
        text=True,
        env=os.environ.copy(),
    )
    try:
        verified = json.loads(result.stdout)
    except json.JSONDecodeError as error:
        raise ValueError("GitHub CLI returned invalid attestation verification JSON") from error
    if not isinstance(verified, list):
        raise ValueError("GitHub CLI returned an unexpected attestation verification result")
    expected_invocation = (
        f"https://github.com/{repository}/actions/runs/{run_id}/attempts/{run_attempt}"
    )
    exact_run = False
    for item in verified:
        if not isinstance(item, dict):
            continue
        verification = item.get("verificationResult") or {}
        signature = verification.get("signature") or {}
        certificate = signature.get("certificate") or {}
        certificate_values = set(string_values(certificate))
        if expected_invocation in certificate_values and harness_commit in certificate_values:
            exact_run = True
            break
    if not exact_run:
        raise ValueError("signed baseline manifest was not attested by the recorded workflow run attempt")


def validate_run(repository: str, provenance: dict) -> bool:
    run_id = provenance["run_id"]
    endpoint = f"repos/{repository}/actions/runs/{run_id}"
    run_attempt = int(provenance["run_attempt"])
    run = github_json(f"{endpoint}/attempts/{run_attempt}")
    repository_info = github_json(f"repos/{repository}")
    default_branch = repository_info.get("default_branch")
    if not isinstance(default_branch, str) or not default_branch:
        raise ValueError("GitHub did not return the repository default branch")
    expected_path = provenance["workflow_path"]
    actual_path = str(run.get("path", "")).split("@", 1)[0]
    if run.get("id") != int(run_id):
        raise ValueError("GitHub run ID does not match baseline provenance")
    if run.get("status") != "completed" or run.get("conclusion") != "success":
        raise ValueError("the recorded baseline workflow run did not complete successfully")
    if run.get("event") != "workflow_dispatch":
        raise ValueError("the recorded baseline must come from a manual workflow dispatch")
    if run.get("run_attempt") != run_attempt:
        raise ValueError("GitHub returned a different baseline workflow attempt")
    if actual_path != expected_path:
        raise ValueError(f"workflow run used {actual_path!r}, expected {expected_path!r}")
    if run.get("head_sha") != provenance["harness_commit"]:
        raise ValueError("baseline workflow run head SHA differs from the recorded harness commit")
    if run.get("head_branch") != default_branch:
        raise ValueError("baseline workflow must run from the repository default branch")
    run_repository = (run.get("repository") or {}).get("full_name")
    if run_repository != repository:
        raise ValueError("baseline workflow run belongs to a different repository")
    head_repository = (run.get("head_repository") or {}).get("full_name")
    if head_repository != repository:
        raise ValueError("baseline workflow run was dispatched from a different repository")

    jobs_response = github_json(f"{endpoint}/attempts/{run_attempt}/jobs?per_page=100")
    jobs = jobs_response.get("jobs")
    if not isinstance(jobs, list):
        raise ValueError("GitHub did not return the baseline workflow attempt jobs")
    artifact_steps = [
        step
        for job in jobs
        for step in job.get("steps", [])
        if step.get("name") == REUSABLE_ARTIFACT_STEP
    ]
    if len(artifact_steps) != 1 or artifact_steps[0].get("conclusion") != "success":
        raise ValueError("the exact baseline attempt did not successfully upload its reusable artifact")

    artifact_response = github_json(f"{endpoint}/artifacts?per_page=100")
    artifacts = artifact_response.get("artifacts")
    if not isinstance(artifacts, list):
        raise ValueError("GitHub did not return the baseline workflow artifacts")
    matches = [item for item in artifacts if item.get("name") == provenance["artifact_name"]]
    if not matches:
        # The committed samples and raw logs are the durable evidence copy.
        # GitHub can remove artifact metadata after its configured retention period.
        return False
    if len(matches) != 1:
        raise ValueError("the recorded run contains multiple matching baseline artifacts")
    artifact = matches[0]
    if (artifact.get("workflow_run") or {}).get("id") != int(run_id):
        raise ValueError("the reusable baseline artifact is attached to a different workflow run")
    expired = artifact.get("expired")
    if not isinstance(expired, bool):
        return False
    return not expired


def validate_bundle(
    bundle: Path,
    tracked_baseline: Path,
    tracked_provenance: Path,
    repository: str,
) -> dict:
    payload_provenance_path = bundle / "provenance.json"
    payload_baseline = bundle / BASELINE_NAME
    expected_files = {BASELINE_NAME, *SAMPLE_NAMES}
    provenance = json.loads(payload_provenance_path.read_text(encoding="utf-8"))
    if provenance != json.loads(tracked_provenance.read_text(encoding="utf-8")):
        raise ValueError("committed provenance does not match the reusable workflow artifact")
    if tracked_provenance.read_bytes() != payload_provenance_path.read_bytes():
        raise ValueError("committed provenance bytes differ from the reusable workflow artifact")
    if provenance.get("schema_version") != 2:
        raise ValueError("unsupported performance provenance schema")
    if provenance.get("repository") != repository:
        raise ValueError("baseline provenance repository does not match this checkout")
    if provenance.get("workflow_path") != WORKFLOW_PATH:
        raise ValueError("baseline provenance does not identify the authoritative workflow")
    if provenance.get("baseline_source_commit") != BASELINE_SOURCE_COMMIT:
        raise ValueError("baseline provenance does not identify the pinned untouched source")
    if not re.fullmatch(r"[0-9a-f]{40}", str(provenance.get("harness_commit", ""))):
        raise ValueError("baseline provenance has no full harness commit SHA")
    if not str(provenance.get("run_id", "")).isdigit() or not str(provenance.get("run_attempt", "")).isdigit():
        raise ValueError("baseline provenance has an invalid workflow run identity")
    expected_artifact = (
        f"shreeos-performance-baseline-{provenance['run_id']}-{provenance['run_attempt']}"
    )
    if provenance.get("artifact_name") != expected_artifact:
        raise ValueError("baseline provenance artifact name does not bind its run ID and attempt")
    if not re.fullmatch(r"[0-9a-f]{64}", str(provenance.get("measurement_protocol_sha256", ""))):
        raise ValueError("baseline provenance has an invalid measurement protocol digest")
    if not re.fullmatch(r"[0-9a-f]{64}", str(provenance.get("iso_sha256", ""))):
        raise ValueError("baseline provenance has an invalid ISO digest")
    if provenance.get("sample_count") != 3:
        raise ValueError("baseline provenance must identify exactly three samples")

    file_hashes = provenance.get("files")
    if not isinstance(file_hashes, dict) or set(file_hashes) != expected_files:
        raise ValueError("baseline provenance file list is incomplete or unexpected")
    for name in sorted(expected_files):
        path = bundle / name
        if not path.is_file() or sha256(path) != file_hashes[name]:
            raise ValueError(f"reusable baseline file is missing or has the wrong digest: {name}")
    raw_hashes = provenance.get("raw_evidence_files")
    if not isinstance(raw_hashes, dict) or not raw_hashes:
        raise ValueError("baseline provenance does not bind retained raw QEMU evidence")
    if any(not name.startswith("raw-evidence/") or ".." in Path(name).parts for name in raw_hashes):
        raise ValueError("baseline provenance contains an unsafe raw evidence path")
    expected_files.update(raw_hashes)
    manifest_path = bundle / CHECKSUM_MANIFEST_NAME
    attestation_path = bundle / ATTESTATION_BUNDLE_NAME
    if not manifest_path.is_file() or not attestation_path.is_file() or not attestation_path.stat().st_size:
        raise ValueError("baseline bundle is missing its attested checksum manifest")
    actual_files = {
        path.relative_to(bundle).as_posix()
        for path in bundle.rglob("*")
        if path.is_file() and not path.is_symlink()
    }
    actual_files.discard("provenance.json")
    actual_files.discard(CHECKSUM_MANIFEST_NAME)
    actual_files.discard(ATTESTATION_BUNDLE_NAME)
    if actual_files != expected_files:
        raise ValueError("baseline bundle contains missing or unexpected files")
    for name, digest in sorted(raw_hashes.items()):
        path = bundle / Path(name)
        if not path.is_file() or path.is_symlink() or sha256(path) != digest:
            raise ValueError(f"raw evidence file is missing or has the wrong digest: {name}")
    for index, sample_name in enumerate(SAMPLE_NAMES, 1):
        prefix = f"raw-evidence/run-{index}/"
        required = {
            f"{prefix}qemu.log", f"{prefix}serial.log", f"{prefix}metrics.tsv",
            f"{prefix}environment-deltas.txt", f"{prefix}performance-candidate.tsv",
        }
        if not required.issubset(raw_hashes):
            raise ValueError(f"raw evidence for run {index} is incomplete")
        sample_path = bundle / sample_name
        raw_candidate = bundle / prefix / "performance-candidate.tsv"
        if raw_candidate.read_bytes() != sample_path.read_bytes():
            raise ValueError(f"raw performance sample differs from {sample_name}")
        serial = (bundle / prefix / "serial.log").read_text(encoding="utf-8", errors="replace")
        if "SHREEOS_PERF_END" not in serial:
            raise ValueError(f"run {index} serial log has no completed performance probe marker")
        metrics_path = bundle / prefix / "metrics.tsv"
        if metrics_path.read_text(encoding="utf-8") != serial_metrics_text(serial):
            raise ValueError(f"run {index} parsed metrics do not match its raw serial log")
        raw_metrics = parse_metric_tsv(metrics_path)
        sample_metrics = {}
        for line in sample_path.read_text(encoding="utf-8").splitlines():
            if not line or line.startswith("# "):
                continue
            fields = line.split("\t")
            if len(fields) == 2:
                sample_metrics[fields[0]] = fields[1]
        if any(raw_metrics.get(key) != sample_metrics.get(key) for key in PRODUCT_METRICS):
            raise ValueError(f"run {index} product metrics do not match its raw performance sample")
        deltas = {}
        for line in (bundle / prefix / "environment-deltas.txt").read_text(
            encoding="utf-8", errors="replace",
        ).splitlines():
            if line.startswith("# "):
                key, separator, value = line[2:].partition("=")
                if separator:
                    deltas[key] = value
        for counter in RESOURCE_COUNTERS:
            if counter not in sample_metrics or deltas.get(counter) != sample_metrics[counter]:
                raise ValueError(f"run {index} raw cgroup delta does not match sample field {counter}")
    expected_manifest_files = expected_files | {"provenance.json"}
    manifest_lines = manifest_path.read_text(encoding="utf-8").splitlines()
    manifest_files = set()
    for line in manifest_lines:
        digest, separator, name = line.partition("  ")
        if not separator or not re.fullmatch(r"[0-9a-f]{64}", digest) or not name:
            raise ValueError("attested checksum manifest contains an invalid row")
        manifest_files.add(name)
    if manifest_files != expected_manifest_files:
        raise ValueError("attested checksum manifest contains an incomplete or unexpected file list")
    if manifest_path.read_text(encoding="utf-8") != checksum_manifest_text(bundle):
        raise ValueError("attested checksum manifest does not match durable baseline evidence")
    if tracked_baseline.read_bytes() != payload_baseline.read_bytes():
        raise ValueError("committed baseline TSV differs from the successful workflow artifact")

    measured = metadata(payload_baseline)
    for key, expected in (
        ("source_commit", BASELINE_SOURCE_COMMIT),
        ("sample_count", "3"),
        ("iso_sha256", provenance.get("iso_sha256")),
        ("conditions", provenance.get("conditions")),
        ("measurement_protocol_sha256", provenance.get("measurement_protocol_sha256")),
    ):
        if measured.get(key) != expected:
            raise ValueError(f"baseline TSV metadata {key!r} differs from its provenance record")

    with tempfile.TemporaryDirectory(prefix="shreeos-baseline-reaggregate-") as directory:
        output = Path(directory) / BASELINE_NAME
        report = Path(directory) / "summary.md"
        sample_paths = [bundle / name for name in SAMPLE_NAMES]
        aggregator = Path(__file__).with_name("aggregate-performance-runs.py")
        subprocess.run(
            [sys.executable, str(aggregator), "--output", str(output),
             "--report-output", str(report), *(str(path) for path in sample_paths)],
            check=True,
        )
        if output.read_bytes() != payload_baseline.read_bytes():
            raise ValueError("baseline TSV does not reaggregate from the three retained raw samples")
    return provenance


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repository", required=True)
    parser.add_argument("--baseline", required=True, type=Path)
    parser.add_argument("--provenance", required=True, type=Path)
    parser.add_argument("--evidence-dir", required=True, type=Path,
                        help="durable checked-in sample TSVs and raw-evidence directory")
    parser.add_argument("--download-dir", required=True, type=Path)
    args = parser.parse_args(argv[1:])
    try:
        tracked_provenance = json.loads(args.provenance.read_text(encoding="utf-8"))
        artifact_available = validate_run(args.repository, tracked_provenance)
        if (args.evidence_dir.is_symlink() or not args.evidence_dir.is_dir()
                or any(path.is_symlink() for path in args.evidence_dir.rglob("*"))):
            raise ValueError("durable baseline evidence directory is unavailable")
        with tempfile.TemporaryDirectory(prefix="shreeos-baseline-durable-") as directory:
            durable_bundle = Path(directory)
            shutil.copyfile(args.baseline, durable_bundle / BASELINE_NAME)
            shutil.copyfile(args.provenance, durable_bundle / "provenance.json")
            for name in SAMPLE_NAMES:
                shutil.copyfile(args.evidence_dir / name, durable_bundle / name)
            shutil.copytree(args.evidence_dir / "raw-evidence", durable_bundle / "raw-evidence")
            shutil.copyfile(
                args.evidence_dir / CHECKSUM_MANIFEST_NAME,
                durable_bundle / CHECKSUM_MANIFEST_NAME,
            )
            shutil.copyfile(
                args.evidence_dir / ATTESTATION_BUNDLE_NAME,
                durable_bundle / ATTESTATION_BUNDLE_NAME,
            )
            provenance = validate_bundle(
                durable_bundle, args.baseline, args.provenance, args.repository,
            )
            verify_attestation(
                durable_bundle, args.repository,
                str(tracked_provenance["run_id"]), str(tracked_provenance["run_attempt"]),
                str(tracked_provenance["harness_commit"]),
            )
            durable_trust_files = {
                name: (durable_bundle / name).read_bytes()
                for name in (CHECKSUM_MANIFEST_NAME, ATTESTATION_BUNDLE_NAME)
            }
        if artifact_available:
            if args.download_dir.exists() and any(args.download_dir.iterdir()):
                raise ValueError("baseline artifact download directory must be empty")
            args.download_dir.mkdir(parents=True, exist_ok=True)
            subprocess.run(
                ["gh", "run", "download", str(tracked_provenance["run_id"]),
                 "--repo", args.repository, "--name", tracked_provenance["artifact_name"],
                 "--dir", str(args.download_dir)],
                check=True,
                env=os.environ.copy(),
            )
            validate_bundle(
                args.download_dir, args.baseline, args.provenance, args.repository,
            )
            for name in (CHECKSUM_MANIFEST_NAME, ATTESTATION_BUNDLE_NAME):
                if (args.download_dir / name).read_bytes() != durable_trust_files[name]:
                    raise ValueError(f"uploaded workflow artifact differs from committed {name}")
    except (KeyError, OSError, UnicodeError, ValueError, subprocess.CalledProcessError, json.JSONDecodeError) as error:
        print(f"Performance baseline provenance verification failed: {error}", file=sys.stderr)
        return 1
    artifact_note = "live workflow artifact matched" if artifact_available else "expired workflow artifact; signed durable evidence verified"
    print(
        "Verified measured baseline from workflow run "
        f"{provenance['run_id']} attempt {provenance['run_attempt']} "
        f"({provenance['artifact_name']}; {artifact_note})"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
