#!/usr/bin/env python3
"""Bind a release run to the exact ISO accepted by interactive installation."""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import sys
from datetime import date
from pathlib import Path
from typing import Any


REQUIRED_EVIDENCE = (
    "Firmware",
    "Installer",
    "Credentials",
    "APT",
    "Login",
    "System",
    "Limitations",
)


def read_accepted_record(path: Path, version: str) -> dict[str, str]:
    text = path.read_text(encoding="utf-8")
    records = re.findall(
        r"^VERDICT:\s*ACCEPTED\s*\n(.*?)(?=^VERDICT:|\Z)",
        text,
        re.MULTILINE | re.DOTALL,
    )
    for record in reversed(records):
        fields = dict(
            re.findall(
                r"^([A-Za-z][A-Za-z 0-9/-]*):\s*(.*?)\s*$",
                record,
                re.MULTILINE,
            )
        )
        if fields.get("Version") == version:
            break
    else:
        raise ValueError(f"No ACCEPTED installer record exists for ShreeOS {version}")

    required = ("Commit", "Version", "Date", "ISO SHA256", "Workflow run ID", "Artifact ID", *REQUIRED_EVIDENCE)
    missing = [field for field in required if not fields.get(field)]
    if missing:
        raise ValueError(f"INSTALL-ACCEPTANCE.md is missing: {', '.join(missing)}")
    if not re.fullmatch(r"[0-9a-f]{40}", fields["Commit"]):
        raise ValueError("The accepted source commit must be a full lowercase 40-character SHA")
    if not re.fullmatch(r"[0-9a-f]{64}", fields["ISO SHA256"]):
        raise ValueError("The acceptance record must contain a full lowercase ISO SHA256")
    for field in ("Workflow run ID", "Artifact ID"):
        if not re.fullmatch(r"[0-9]+", fields[field]):
            raise ValueError(f"{field} must be numeric")
    if not re.fullmatch(r"[0-9]{4}-[0-9]{2}-[0-9]{2}", fields["Date"]):
        raise ValueError("The acceptance date must use YYYY-MM-DD")
    try:
        date.fromisoformat(fields["Date"])
    except ValueError as error:
        raise ValueError("The acceptance date must use YYYY-MM-DD") from error
    return fields


def read_json(path: Path, label: str) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as error:
        raise ValueError(f"{label} is not valid JSON: {error}") from error
    if not isinstance(value, dict):
        raise ValueError(f"{label} must be a JSON object")
    return value


def file_sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def verify_artifact(
    fields: dict[str, str],
    workflow_run: dict[str, Any],
    artifact: dict[str, Any],
    output_dir: Path,
    repository: str,
) -> None:
    run_id = int(fields["Workflow run ID"])
    artifact_id = int(fields["Artifact ID"])
    source_commit = fields["Commit"]
    expected_name = f"shreeos-unified-development-{source_commit}"

    if artifact.get("id") != artifact_id:
        raise ValueError("The Actions artifact API response does not match the recorded artifact ID")
    if artifact.get("expired") is not False:
        raise ValueError("The accepted ISO artifact has expired or its expiry state is unknown")
    if artifact.get("name") != expected_name:
        raise ValueError(f"Expected accepted artifact name {expected_name!r}")

    artifact_run = artifact.get("workflow_run")
    if not isinstance(artifact_run, dict):
        raise ValueError("The accepted artifact is missing its workflow-run identity")
    if artifact_run.get("id") != run_id:
        raise ValueError("The accepted artifact belongs to a different workflow run")
    if artifact_run.get("head_sha") != source_commit:
        raise ValueError("The accepted artifact source SHA differs from the acceptance record")

    if workflow_run.get("id") != run_id:
        raise ValueError("The workflow-run API response does not match the recorded run ID")
    if workflow_run.get("status") != "completed" or workflow_run.get("conclusion") != "success":
        raise ValueError("The accepted ISO must come from a completed successful workflow run")
    if workflow_run.get("head_sha") != source_commit:
        raise ValueError("The workflow run source SHA differs from the acceptance record")
    if workflow_run.get("path") != ".github/workflows/unified-iso.yml":
        raise ValueError("The accepted artifact was not produced by the unified ISO workflow")
    if workflow_run.get("name") != "Unified ShreeOS development ISO":
        raise ValueError("The accepted artifact came from an unexpected workflow")
    if workflow_run.get("head_branch") != "master" or workflow_run.get("event") not in {
        "push",
        "workflow_dispatch",
    }:
        raise ValueError("Install acceptance must use a master-branch push or manual ISO build")
    base_repository = workflow_run.get("repository") or {}
    head_repository = workflow_run.get("head_repository") or {}
    if base_repository.get("full_name") != repository or head_repository.get("full_name") != repository:
        raise ValueError("The accepted workflow artifact must come from this repository, not a fork")

    base_id = base_repository.get("id")
    head_id = head_repository.get("id")
    if artifact_run.get("repository_id") != base_id or artifact_run.get("head_repository_id") != head_id:
        raise ValueError("The artifact repository identity does not match the workflow run")

    iso_name = f"shreeos({fields['Version']}).iso"
    iso_path = output_dir / iso_name
    if not iso_path.is_file() or iso_path.stat().st_size <= 0:
        raise ValueError(f"The accepted artifact does not contain {iso_name}")
    image_paths = sorted(output_dir.glob("*.iso"))
    if image_paths != [iso_path]:
        raise ValueError("The accepted artifact must contain exactly the canonical ISO")

    expected_sha = fields["ISO SHA256"]
    actual_sha = file_sha256(iso_path)
    if actual_sha != expected_sha:
        raise ValueError("The ISO SHA256 does not match the value recorded after installation acceptance")

    checksum_path = output_dir / f"{iso_name}.sha256"
    checksum_fields = checksum_path.read_text(encoding="utf-8").split()
    if len(checksum_fields) < 2 or checksum_fields[0] != actual_sha or checksum_fields[1] != iso_name:
        raise ValueError("The ISO sidecar checksum does not match the accepted image")

    sums_path = output_dir / "SHA256SUMS"
    sums = [line.split(maxsplit=1) for line in sums_path.read_text(encoding="utf-8").splitlines() if line.strip()]
    if not any(len(fields) == 2 and fields[0] == actual_sha and fields[1].lstrip("* ") == iso_name for fields in sums):
        raise ValueError("SHA256SUMS does not match the accepted image")

    manifest_path = output_dir / f"shreeos({fields['Version']})-manifest.json"
    manifest = read_json(manifest_path, "accepted ISO manifest")
    expected_manifest = {
        "name": "ShreeOS",
        "version": fields["Version"],
        "iso": iso_name,
        "profile": "plasma",
        "commit": source_commit,
        "base_distribution": "trixie",
        "architecture": "x86_64",
        "sha256": actual_sha,
        "size_bytes": iso_path.stat().st_size,
    }
    for key, expected in expected_manifest.items():
        if manifest.get(key) != expected:
            raise ValueError(f"The accepted ISO manifest field {key!r} does not match {expected!r}")
    if manifest.get("products") != ["live", "installed"]:
        raise ValueError("The accepted ISO manifest does not identify both live and installed products")
    for name in (f"shreeos({fields['Version']})-packages.txt", f"shreeos({fields['Version']})-build-info.txt"):
        if not (output_dir / name).is_file():
            raise ValueError(f"The accepted artifact is missing {name}")


def output_values(fields: dict[str, str]) -> dict[str, str]:
    return {
        "source_commit": fields["Commit"],
        "iso_sha256": fields["ISO SHA256"],
        "workflow_run_id": fields["Workflow run ID"],
        "artifact_id": fields["Artifact ID"],
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--record", type=Path, required=True)
    parser.add_argument("--version", required=True)
    parser.add_argument("--repository", help="owner/name of the repository that built the ISO")
    parser.add_argument("--workflow-run-json", type=Path)
    parser.add_argument("--artifact-json", type=Path)
    parser.add_argument("--output-dir", type=Path)
    parser.add_argument("--github-output", type=Path)
    parser.add_argument("--reference-only", action="store_true")
    args = parser.parse_args()

    try:
        fields = read_accepted_record(args.record, args.version)
        values = output_values(fields)
        if not args.reference_only:
            if not all((args.repository, args.workflow_run_json, args.artifact_json, args.output_dir)):
                raise ValueError("Full verification requires repository, run JSON, artifact JSON and output directory")
            verify_artifact(
                fields,
                read_json(args.workflow_run_json, "workflow run metadata"),
                read_json(args.artifact_json, "artifact metadata"),
                args.output_dir,
                args.repository,
            )
            if args.github_output:
                with args.github_output.open("a", encoding="utf-8") as stream:
                    for key, value in values.items():
                        stream.write(f"{key}={value}\n")
        print(json.dumps(values, sort_keys=True))
    except (OSError, ValueError, KeyError, TypeError) as error:
        print(f"Accepted install artifact verification failed: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
