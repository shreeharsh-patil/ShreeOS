#!/usr/bin/env python3
"""Regression tests for unified ISO bundle verification before cache reuse."""

from __future__ import annotations

import hashlib
import importlib.util
import json
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location(
    "verify_unified_artifact", ROOT / "scripts" / "verify-unified-artifact.py"
)
assert SPEC is not None and SPEC.loader is not None
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class UnifiedArtifactCacheTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.directory = Path(self.temporary.name)
        self.iso = self.directory / "shreeos(0.4.0).iso"
        self.checksum = self.directory / f"{self.iso.name}.sha256"
        self.packages = self.directory / "shreeos(0.4.0)-packages.txt"
        self.build_info = self.directory / "shreeos(0.4.0)-build-info.txt"
        self.manifest = self.directory / "shreeos(0.4.0)-manifest.json"
        self.version = "0.4.0"
        self.profile = "plasma"
        self.architecture = "x86_64"
        self.suite = "trixie"
        self.snapshot = "20260929T000000Z"
        self.live_build = "1:20250505+deb13u1"
        self.commit = "a" * 40
        self.package_versions = {
            "linux-image-amd64": "6.12.69-1",
            "plasma-workspace": "4:6.3.6-2",
            "kwin-x11": "4:6.3.6-1",
            "sddm": "0.21.0-1",
            "shreeos-tools": "0.4.0",
        }
        self._write_valid_bundle()

    def tearDown(self) -> None:
        self.temporary.cleanup()

    def _write_valid_bundle(self) -> None:
        self.iso.write_bytes(b"synthetic ISO bytes for metadata verification")
        digest = hashlib.sha256(self.iso.read_bytes()).hexdigest()
        size = self.iso.stat().st_size
        self.checksum.write_text(f"{digest}  {self.iso.name}\n", encoding="ascii")
        self.packages.write_text(
            "".join(f"{name} {version}\n" for name, version in self.package_versions.items()),
            encoding="utf-8",
        )
        components = {
            "kernel": self.package_versions["linux-image-amd64"],
            "plasma": self.package_versions["plasma-workspace"],
            "kwin": self.package_versions["kwin-x11"],
            "sddm": self.package_versions["sddm"],
            "shreeos_tools": self.package_versions["shreeos-tools"],
        }
        build_info_values = {
            "version": self.version,
            "artifact": self.iso.name,
            "profile": self.profile,
            "architecture": self.architecture,
            "debian_suite": self.suite,
            "debian_snapshot": self.snapshot,
            "live_build": self.live_build,
            "git_commit": self.commit,
            "git_dirty": "0",
            "built_at": "2026-10-16T00:00:00Z",
            "sha256": digest,
            "size_bytes": str(size),
            **components,
        }
        self.build_info.write_text(
            "".join(f"{key}={value}\n" for key, value in build_info_values.items()),
            encoding="utf-8",
        )
        manifest = {
            "name": "ShreeOS",
            "version": self.version,
            "profile": self.profile,
            "architecture": self.architecture,
            "base_distribution": self.suite,
            "base_snapshot": self.snapshot,
            "live_build": self.live_build,
            "commit": self.commit,
            "git_dirty": False,
            "iso": self.iso.name,
            "sha256": digest,
            "size_bytes": size,
            "components": components,
        }
        self.manifest.write_text(json.dumps(manifest), encoding="utf-8")

    def _verify(self) -> None:
        MODULE.verify_bundle(
            self.iso,
            self.checksum,
            self.packages,
            self.build_info,
            self.manifest,
            version=self.version,
            profile=self.profile,
            architecture=self.architecture,
            suite=self.suite,
            snapshot=self.snapshot,
            live_build=self.live_build,
        )

    def test_accepts_matching_complete_bundle(self) -> None:
        self._verify()

    def test_rejects_missing_build_metadata(self) -> None:
        self.build_info.unlink()
        with self.assertRaisesRegex(ValueError, "missing or empty artifact input"):
            self._verify()

    def test_rejects_checksum_that_does_not_match_iso(self) -> None:
        self.checksum.write_text(f"{'0' * 64}  {self.iso.name}\n", encoding="ascii")
        with self.assertRaisesRegex(ValueError, "checksum sidecar"):
            self._verify()

    def test_rejects_manifest_that_disagrees_with_build_info(self) -> None:
        manifest = json.loads(self.manifest.read_text(encoding="utf-8"))
        manifest["base_snapshot"] = "20250101T000000Z"
        self.manifest.write_text(json.dumps(manifest), encoding="utf-8")
        with self.assertRaisesRegex(ValueError, "base_snapshot"):
            self._verify()

    def test_rejects_missing_required_package_sidecar_entry(self) -> None:
        self.packages.write_text("sddm 0.21.0-1\n", encoding="utf-8")
        with self.assertRaisesRegex(ValueError, "missing required package"):
            self._verify()

    def test_build_cache_fast_path_uses_complete_bundle_verifier(self) -> None:
        source = (ROOT / "scripts" / "build-shreeos.sh").read_text(encoding="utf-8")
        start = source.index("verify_existing_artifact() {")
        end = source.index("\n}", start)
        cache_check = source[start:end]
        for sidecar in ("CHECKSUM_PATH", "PACKAGES_PATH", "BUILD_INFO_PATH", "MANIFEST_PATH"):
            self.assertIn(f'[ -s "${sidecar}" ]', cache_check)
        self.assertIn("scripts/verify-unified-artifact.py", cache_check)


if __name__ == "__main__":
    unittest.main()
