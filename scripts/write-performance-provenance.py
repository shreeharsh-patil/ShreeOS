#!/usr/bin/env python3
"""Write a run-bound provenance record for a measured performance baseline."""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import sys
from pathlib import Path


BASELINE_SOURCE_COMMIT = "9313ebb042cf71bb148441037940b130d49920d1"
WORKFLOW_PATH = ".github/workflows/performance-baseline.yml"
CHECKSUM_MANIFEST_NAME = "performance-baseline.sha256"
ATTESTATION_BUNDLE_NAME = "performance-baseline.attestation.json"


def read_metadata(path: Path) -> dict[str, str]:
    metadata: dict[str, str] = {}
    for number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        if not line.startswith("# "):
            continue
        key, separator, value = line[2:].partition("=")
        if not separator or key in metadata:
            raise ValueError(f"invalid or duplicate metadata in {path}:{number}")
        metadata[key] = value
    return metadata


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def write_checksum_manifest(bundle: Path) -> None:
    rows = []
    for path in sorted(bundle.rglob("*")):
        if path.is_symlink():
            raise ValueError(f"baseline bundle contains a symlink: {path}")
        if not path.is_file() or path.name in {CHECKSUM_MANIFEST_NAME, ATTESTATION_BUNDLE_NAME}:
            continue
        relative = path.relative_to(bundle).as_posix()
        rows.append(f"{sha256(path)}  {relative}\n")
    if not rows:
        raise ValueError("baseline bundle is empty")
    (bundle / CHECKSUM_MANIFEST_NAME).write_text("".join(rows), encoding="utf-8")


def write_provenance(args: argparse.Namespace) -> None:
    if not re.fullmatch(r"[0-9a-f]{40}", args.harness_commit):
        raise ValueError("harness commit must be a full lowercase Git SHA")
    if not args.run_id.isdigit() or not args.run_attempt.isdigit():
        raise ValueError("workflow run ID and attempt must be numeric")
    expected_artifact = f"shreeos-performance-baseline-{args.run_id}-{args.run_attempt}"
    if args.artifact_name != expected_artifact:
        raise ValueError("artifact name must bind the measured run ID and attempt")
    if not args.repository or "/" not in args.repository:
        raise ValueError("repository must have owner/name form")

    baseline = args.baseline.resolve(strict=True)
    samples = [path.resolve(strict=True) for path in args.sample]
    if len(samples) != 3:
        raise ValueError("exactly three raw sample TSVs are required")
    raw_evidence = args.raw_evidence.resolve(strict=True)
    if not raw_evidence.is_dir():
        raise ValueError("raw evidence must be a directory containing per-sample QEMU logs")
    metadata = read_metadata(baseline)
    if metadata.get("source_commit") != BASELINE_SOURCE_COMMIT:
        raise ValueError("aggregate does not identify the pinned untouched source commit")
    if metadata.get("sample_count") != "3":
        raise ValueError("aggregate must report exactly three samples")
    protocol = metadata.get("measurement_protocol_sha256", "")
    if not re.fullmatch(r"[0-9a-f]{64}", protocol):
        raise ValueError("aggregate has no valid measurement protocol SHA-256")
    if not re.fullmatch(r"[0-9a-f]{64}", metadata.get("iso_sha256", "")):
        raise ValueError("aggregate is missing a valid measured ISO SHA-256")

    files = {"performance-baseline.tsv": sha256(baseline)}
    for index, sample in enumerate(samples, 1):
        files[f"performance-sample-{index}.tsv"] = sha256(sample)
    raw_evidence_files: dict[str, str] = {}
    for index in range(1, 4):
        run = raw_evidence / f"run-{index}"
        required_logs = (
            "qemu.log", "serial.log", "metrics.tsv", "environment-deltas.txt",
            "performance-candidate.tsv",
        )
        for name in required_logs:
            if not (run / name).is_file():
                raise ValueError(f"raw evidence is missing run-{index}/{name}")
        sample = samples[index - 1]
        if (run / "performance-candidate.tsv").read_bytes() != sample.read_bytes():
            raise ValueError(f"run-{index} raw performance sample differs from its bundle TSV")
        if "SHREEOS_PERF_END" not in (run / "serial.log").read_text(
            encoding="utf-8", errors="replace",
        ):
            raise ValueError(f"run-{index} serial log has no completed performance probe marker")
        if not (run / "metrics.tsv").stat().st_size or not (run / "environment-deltas.txt").stat().st_size:
            raise ValueError(f"run-{index} is missing parsed metrics or cgroup counter evidence")
    for path in sorted(raw_evidence.rglob("*")):
        if path.is_symlink():
            raise ValueError(f"raw evidence contains a symlink: {path}")
        if not path.is_file():
            continue
        relative = path.relative_to(raw_evidence).as_posix()
        raw_evidence_files[f"raw-evidence/{relative}"] = sha256(path)
    if not raw_evidence_files:
        raise ValueError("raw QEMU evidence is empty")
    record = {
        "schema_version": 2,
        "repository": args.repository,
        "workflow_path": WORKFLOW_PATH,
        "run_id": args.run_id,
        "run_attempt": args.run_attempt,
        "harness_commit": args.harness_commit,
        "artifact_name": args.artifact_name,
        "baseline_source_commit": BASELINE_SOURCE_COMMIT,
        "iso_sha256": metadata["iso_sha256"],
        "measurement_protocol_sha256": protocol,
        "conditions": metadata["conditions"],
        "sample_count": 3,
        "files": files,
        "raw_evidence_files": raw_evidence_files,
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(record, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    write_checksum_manifest(args.output.parent)


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--baseline", required=True, type=Path)
    parser.add_argument("--sample", action="append", required=True, type=Path)
    parser.add_argument("--raw-evidence", required=True, type=Path)
    parser.add_argument("--repository", required=True)
    parser.add_argument("--run-id", required=True)
    parser.add_argument("--run-attempt", required=True)
    parser.add_argument("--harness-commit", required=True)
    parser.add_argument("--artifact-name", required=True)
    args = parser.parse_args(argv[1:])
    try:
        write_provenance(args)
    except (OSError, UnicodeError, ValueError) as error:
        print(f"Could not write performance baseline provenance: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
