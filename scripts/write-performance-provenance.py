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
    record = {
        "schema_version": 1,
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
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(record, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--baseline", required=True, type=Path)
    parser.add_argument("--sample", action="append", required=True, type=Path)
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
