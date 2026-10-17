#!/usr/bin/env python3
"""Verify that a committed performance baseline came from a successful exact workflow run."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import subprocess
import sys
import tempfile
from pathlib import Path


BASELINE_SOURCE_COMMIT = "9313ebb042cf71bb148441037940b130d49920d1"
WORKFLOW_PATH = ".github/workflows/performance-baseline.yml"
BASELINE_NAME = "performance-baseline.tsv"
SAMPLE_NAMES = tuple(f"performance-sample-{index}.tsv" for index in range(1, 4))


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


def validate_run(repository: str, provenance: dict) -> None:
    run_id = provenance["run_id"]
    endpoint = f"repos/{repository}/actions/runs/{run_id}"
    run = github_json(endpoint)
    expected_path = provenance["workflow_path"]
    actual_path = str(run.get("path", "")).split("@", 1)[0]
    if run.get("id") != int(run_id):
        raise ValueError("GitHub run ID does not match baseline provenance")
    if run.get("status") != "completed" or run.get("conclusion") != "success":
        raise ValueError("the recorded baseline workflow run did not complete successfully")
    if run.get("event") != "workflow_dispatch":
        raise ValueError("the recorded baseline must come from a manual workflow dispatch")
    if run.get("run_attempt") != int(provenance["run_attempt"]):
        raise ValueError("the recorded baseline workflow attempt is no longer the current attempt")
    if actual_path != expected_path:
        raise ValueError(f"workflow run used {actual_path!r}, expected {expected_path!r}")
    if run.get("head_sha") != provenance["harness_commit"]:
        raise ValueError("baseline workflow run head SHA differs from the recorded harness commit")
    run_repository = (run.get("repository") or {}).get("full_name")
    if run_repository != repository:
        raise ValueError("baseline workflow run belongs to a different repository")
    head_repository = (run.get("head_repository") or {}).get("full_name")
    if head_repository != repository:
        raise ValueError("baseline workflow run was dispatched from a different repository")

    artifact_response = github_json(f"{endpoint}/artifacts?per_page=100")
    artifacts = artifact_response.get("artifacts")
    if not isinstance(artifacts, list):
        raise ValueError("GitHub did not return the baseline workflow artifacts")
    matches = [item for item in artifacts if item.get("name") == provenance["artifact_name"]]
    if len(matches) != 1:
        raise ValueError("the recorded run does not contain exactly one matching baseline artifact")
    artifact = matches[0]
    if artifact.get("expired") is not False:
        raise ValueError("the recorded reusable baseline artifact is expired")
    if (artifact.get("workflow_run") or {}).get("id") != int(run_id):
        raise ValueError("the reusable baseline artifact is attached to a different workflow run")


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
    if provenance.get("schema_version") != 1:
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
    parser.add_argument("--download-dir", required=True, type=Path)
    args = parser.parse_args(argv[1:])
    try:
        tracked_provenance = json.loads(args.provenance.read_text(encoding="utf-8"))
        validate_run(args.repository, tracked_provenance)
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
        provenance = validate_bundle(
            args.download_dir, args.baseline, args.provenance, args.repository,
        )
    except (KeyError, OSError, UnicodeError, ValueError, subprocess.CalledProcessError, json.JSONDecodeError) as error:
        print(f"Performance baseline provenance verification failed: {error}", file=sys.stderr)
        return 1
    print(
        "Verified measured baseline from workflow run "
        f"{provenance['run_id']} attempt {provenance['run_attempt']} "
        f"({provenance['artifact_name']})"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
