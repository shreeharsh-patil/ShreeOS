#!/usr/bin/env python3
"""Regression tests for Debian package evidence archive inspection."""

from __future__ import annotations

import hashlib
import importlib.util
import io
import tarfile
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch


ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location(
    "capture_native_package_evidence",
    ROOT / "scripts" / "capture-native-package-evidence.py",
)
assert SPEC is not None and SPEC.loader is not None
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


def make_tar(*entries: tuple[str, bytes, bytes, str]) -> bytes:
    buffer = io.BytesIO()
    with tarfile.open(fileobj=buffer, mode="w") as archive:
        for name, entry_type, payload, linkname in entries:
            member = tarfile.TarInfo(name)
            member.type = entry_type
            member.mode = 0o755
            member.uid = 0
            member.gid = 0
            member.linkname = linkname
            if entry_type == tarfile.REGTYPE:
                member.size = len(payload)
                archive.addfile(member, io.BytesIO(payload))
            else:
                archive.addfile(member)
    return buffer.getvalue()


def make_empty_tar() -> bytes:
    buffer = io.BytesIO()
    with tarfile.open(fileobj=buffer, mode="w"):
        pass
    return buffer.getvalue()


class NativePackageEvidenceTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.directory = Path(self.temporary.name)
        self.package = self.directory / "shreeos-tools_0.4.0_all.deb"
        self.package.write_bytes(b"synthetic deb")
        self.output = self.directory / "evidence"
        self.output.mkdir()
        self.expected = {
            "name": "shreeos-tools",
            "architecture": "all",
            "dependencies": ["apt"],
            "executables": {"usr/bin/shreeinfo": "0755"},
        }
        self.control = (
            b"Package: shreeos-tools\n"
            b"Version: 0.4.0\n"
            b"Architecture: all\n"
            b"Depends: apt\n"
        )

    def tearDown(self) -> None:
        self.temporary.cleanup()

    def _run_with_payload(self, payload_tar: bytes, control_tar: bytes | None = None):
        control_archive = control_tar if control_tar is not None else make_empty_tar()

        def fake_run(arguments: list[str]) -> bytes:
            if "--field" in arguments:
                return self.control
            if "--fsys-tarfile" in arguments:
                return payload_tar
            if "--ctrl-tarfile" in arguments:
                return control_archive
            if "--info" in arguments or "--contents" in arguments:
                return b"synthetic dpkg-deb output\n"
            raise AssertionError(f"unexpected command: {arguments!r}")

        return patch.object(MODULE, "run", side_effect=fake_run)

    def test_rejects_fifo_disguised_as_expected_executable(self) -> None:
        fifo_tar = make_tar(("usr/bin/shreeinfo", tarfile.FIFOTYPE, b"", ""))
        with self._run_with_payload(fifo_tar):
            with self.assertRaisesRegex(ValueError, "unsupported archive entry type"):
                MODULE.inspect_package(
                    self.package, self.output, self.expected, version="0.4.0"
                )

    def test_accepts_regular_executable_and_records_its_hash(self) -> None:
        payload = b"#!/bin/sh\n"
        with self._run_with_payload(
            make_tar(("usr/bin/shreeinfo", tarfile.REGTYPE, payload, ""))
        ):
            result = MODULE.inspect_package(
                self.package, self.output, self.expected, version="0.4.0"
            )
        entry = result["payload"][0]
        self.assertEqual(entry["type"], "file")
        self.assertEqual(entry["sha256"], hashlib.sha256(payload).hexdigest())

    def test_records_valid_hardlink_without_calling_it_a_regular_file(self) -> None:
        payload = b"#!/bin/sh\n"
        with self._run_with_payload(
            make_tar(
                ("usr/bin/shreeinfo", tarfile.REGTYPE, payload, ""),
                ("usr/share/shreeinfo-copy", tarfile.LNKTYPE, b"", "usr/bin/shreeinfo"),
            )
        ):
            result = MODULE.inspect_package(
                self.package, self.output, self.expected, version="0.4.0"
            )
        hardlink = result["payload"][1]
        self.assertEqual(hardlink["type"], "hardlink")
        self.assertEqual(hardlink["target"], "usr/bin/shreeinfo")
        self.assertNotIn("sha256", hardlink)

    def test_rejects_symlink_as_maintainer_script(self) -> None:
        self.expected["maintainer_scripts"] = {"postinst": "0755"}
        control_tar = make_tar(("postinst", tarfile.SYMTYPE, b"", "target"))
        with self._run_with_payload(
            make_tar(("usr/bin/shreeinfo", tarfile.REGTYPE, b"payload", "")),
            control_tar,
        ):
            with self.assertRaisesRegex(ValueError, "missing maintainer script postinst"):
                MODULE.inspect_package(
                    self.package, self.output, self.expected, version="0.4.0"
                )

    def test_accepts_regular_hashed_maintainer_script(self) -> None:
        self.expected["maintainer_scripts"] = {"postinst": "0755"}
        script = b"#!/bin/sh\nexit 0\n"
        control_tar = make_tar(("postinst", tarfile.REGTYPE, script, ""))
        with self._run_with_payload(
            make_tar(("usr/bin/shreeinfo", tarfile.REGTYPE, b"payload", "")),
            control_tar,
        ):
            result = MODULE.inspect_package(
                self.package, self.output, self.expected, version="0.4.0"
            )
        entry = result["control_archive"][0]
        self.assertEqual(entry["type"], "file")
        self.assertEqual(entry["sha256"], hashlib.sha256(script).hexdigest())


if __name__ == "__main__":
    unittest.main()
