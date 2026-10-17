#!/usr/bin/env python3
"""Verify that release inputs match the ISO accepted by interactive install."""

import hashlib
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]
VERIFIER = ROOT / "scripts/verify-install-acceptance-artifact.py"
VERSION = "0.4.0"
COMMIT = "a" * 40
REPOSITORY = "shreeharsh-patil/ShreeOS"
RUN_ID = 12345
ARTIFACT_ID = 67890


class AcceptedInstallArtifactTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.output = self.root / "out"
        self.output.mkdir()
        self.iso_name = f"shreeos({VERSION}).iso"
        self.iso_path = self.output / self.iso_name
        self.iso_path.write_bytes(b"test-only accepted image bytes")
        self.digest = hashlib.sha256(self.iso_path.read_bytes()).hexdigest()
        (self.output / f"{self.iso_name}.sha256").write_text(
            f"{self.digest}  {self.iso_name}\n", encoding="utf-8"
        )
        (self.output / "SHA256SUMS").write_text(
            f"{self.digest}  {self.iso_name}\n", encoding="utf-8"
        )
        (self.output / f"shreeos({VERSION})-packages.txt").write_text(
            "linux-image-amd64\n", encoding="utf-8"
        )
        (self.output / f"shreeos({VERSION})-build-info.txt").write_text(
            f"git_commit={COMMIT}\n", encoding="utf-8"
        )
        manifest = {
            "name": "ShreeOS",
            "version": VERSION,
            "iso": self.iso_name,
            "profile": "plasma",
            "commit": COMMIT,
            "base_distribution": "trixie",
            "architecture": "x86_64",
            "products": ["live", "installed"],
            "sha256": self.digest,
            "size_bytes": self.iso_path.stat().st_size,
        }
        self.manifest_path = self.output / f"shreeos({VERSION})-manifest.json"
        self.manifest_path.write_text(json.dumps(manifest), encoding="utf-8")
        self.record_path = self.root / "INSTALL-ACCEPTANCE.md"
        self._write_record()
        self.run_path = self.root / "workflow-run.json"
        self.artifact_path = self.root / "artifact.json"
        self._write_metadata()

    def tearDown(self):
        self.temp.cleanup()

    def _write_record(self, digest=None, run_id=RUN_ID, artifact_id=ARTIFACT_ID):
        digest = self.digest if digest is None else digest
        self.record_path.write_text(
            "\n".join(
                [
                    "# Interactive install acceptance",
                    "",
                    "## Status",
                    "",
                    "```",
                    "VERDICT: ACCEPTED",
                    f"Commit: {COMMIT}",
                    f"Version: {VERSION}",
                    "Date: 2026-10-17",
                    f"ISO SHA256: {digest}",
                    f"Workflow run ID: {run_id}",
                    f"Artifact ID: {artifact_id}",
                    "```",
                    "",
                    "## Accepted build record",
                    "",
                    "VERDICT: ACCEPTED",
                    f"Commit: {COMMIT}",
                    f"Version: {VERSION}",
                    "Date: 2026-10-17",
                    f"ISO SHA256: {digest}",
                    f"Workflow run ID: {run_id}",
                    f"Artifact ID: {artifact_id}",
                    "Firmware: BIOS and UEFI installed-disk boots passed",
                    "Installer: guided and manual runs passed",
                    "Credentials: created account authenticated",
                    "APT: signed repositories updated and upgraded",
                    "Login: created account entered Plasma",
                    "System: failed unit list was empty",
                    "Limitations: none beyond documented known gaps",
                    "",
                ]
            ),
            encoding="utf-8",
        )

    def _write_metadata(self, run_id=RUN_ID, artifact_id=ARTIFACT_ID, head_sha=COMMIT,
                        status="completed", conclusion="success", path=".github/workflows/unified-iso.yml",
                        expired=False, repository=REPOSITORY, head_repository=REPOSITORY):
        (self.run_path).write_text(
            json.dumps(
                {
                    "id": run_id,
                    "status": status,
                    "conclusion": conclusion,
                    "head_sha": head_sha,
                    "head_branch": "master",
                    "event": "workflow_dispatch",
                    "path": path,
                    "name": "Unified ShreeOS development ISO",
                    "repository": {"full_name": repository, "id": 1},
                    "head_repository": {"full_name": head_repository, "id": 1},
                }
            ),
            encoding="utf-8",
        )
        (self.artifact_path).write_text(
            json.dumps(
                {
                    "id": artifact_id,
                    "expired": expired,
                    "name": f"shreeos-unified-development-{COMMIT}",
                    "workflow_run": {
                        "id": run_id,
                        "head_sha": head_sha,
                        "repository_id": 1,
                        "head_repository_id": 1,
                    },
                }
            ),
            encoding="utf-8",
        )

    def _verify(self, extra_args=()):
        return subprocess.run(
            [
                sys.executable,
                str(VERIFIER),
                "--record", str(self.record_path),
                "--version", VERSION,
                "--repository", REPOSITORY,
                "--workflow-run-json", str(self.run_path),
                "--artifact-json", str(self.artifact_path),
                "--output-dir", str(self.output),
                *extra_args,
            ],
            capture_output=True,
            text=True,
            check=False,
        )

    def test_exact_successful_artifact_is_accepted(self):
        result = self._verify()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn(self.digest, result.stdout)

    def test_current_not_accepted_status_rejects_historical_accepted_record(self):
        text = self.record_path.read_text(encoding="utf-8")
        self.record_path.write_text(text.replace("VERDICT: ACCEPTED", "VERDICT: NOT ACCEPTED", 1), encoding="utf-8")
        result = self._verify()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Current install acceptance verdict is NOT", result.stderr)

    def test_current_status_must_match_accepted_artifact_identity(self):
        text = self.record_path.read_text(encoding="utf-8")
        self.record_path.write_text(
            text.replace(f"ISO SHA256: {self.digest}", f"ISO SHA256: {'0' * 64}", 1),
            encoding="utf-8",
        )
        result = self._verify()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("does not match the accepted record fields", result.stderr)

    def test_iso_hash_must_match_acceptance_record(self):
        self._write_record(digest="0" * 64)
        result = self._verify()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("does not match the value recorded", result.stderr)

    def test_artifact_id_and_workflow_run_must_match_record(self):
        self._write_metadata(artifact_id=ARTIFACT_ID + 1)
        result = self._verify()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("recorded artifact ID", result.stderr)

    def test_artifact_source_sha_must_match_acceptance_record(self):
        self._write_metadata(head_sha="b" * 40)
        result = self._verify()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("source SHA differs", result.stderr)

    def test_expired_or_unsuccessful_artifact_is_rejected(self):
        self._write_metadata(expired=True)
        expired = self._verify()
        self.assertNotEqual(expired.returncode, 0)
        self.assertIn("expired", expired.stderr)
        self._write_metadata(status="in_progress")
        incomplete = self._verify()
        self.assertNotEqual(incomplete.returncode, 0)
        self.assertIn("completed successful", incomplete.stderr)

    def test_artifact_from_fork_or_wrong_workflow_is_rejected(self):
        self._write_metadata(head_repository="attacker/fork")
        fork = self._verify()
        self.assertNotEqual(fork.returncode, 0)
        self.assertIn("not a fork", fork.stderr)
        self._write_metadata(path=".github/workflows/other.yml")
        wrong_workflow = self._verify()
        self.assertNotEqual(wrong_workflow.returncode, 0)
        self.assertIn("unified ISO workflow", wrong_workflow.stderr)

    def test_pull_request_artifact_is_not_install_acceptance_source(self):
        self._write_metadata()
        run = json.loads(self.run_path.read_text(encoding="utf-8"))
        run["event"] = "pull_request"
        run["head_branch"] = "feat/test"
        self.run_path.write_text(json.dumps(run), encoding="utf-8")
        result = self._verify()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("master-branch", result.stderr)

    def test_manifest_must_describe_the_accepted_commit_and_bytes(self):
        manifest = json.loads(self.manifest_path.read_text(encoding="utf-8"))
        manifest["commit"] = "b" * 40
        self.manifest_path.write_text(json.dumps(manifest), encoding="utf-8")
        result = self._verify()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("manifest field 'commit'", result.stderr)


if __name__ == "__main__":
    unittest.main()
