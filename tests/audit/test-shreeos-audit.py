#!/usr/bin/env python3
"""Self-tests for tools/shreeos-audit.py.

The audit report is only as trustworthy as the tool that produces it, so these
tests exercise the parsers against synthetic images built in a temp directory
rather than trusting a single real-world sample. Each test asserts a specific
measured value, so a parser regression fails loudly instead of silently
producing plausible-looking numbers.

Run with:  python3 tests/audit/test-shreeos-audit.py
"""
import gzip
import importlib.util
import io
import os
import struct
import tempfile
import unittest

REPO_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
TOOL_PATH = os.path.join(REPO_ROOT, "tools", "shreeos-audit.py")

_spec = importlib.util.spec_from_file_location("shreeos_audit", TOOL_PATH)
audit = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(audit)


def build_cpio(entries):
    """Build a newc cpio archive from (name, data, mode) tuples."""
    out = bytearray()
    ino = 1
    for name, data, mode in entries:
        encoded = name.encode() + b"\0"
        out += b"070701"
        for value in (ino, mode, 0, 0, 1, 0, len(data), 0, 0, 0, 0,
                      len(encoded), 0):
            out += ("%08X" % value).encode()
        out += encoded
        out += b"\0" * ((-len(out)) % 4)
        out += data
        out += b"\0" * ((-len(out)) % 4)
        ino += 1
    trailer = b"TRAILER!!!\0"
    out += b"070701"
    for value in (0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, len(trailer), 0):
        out += ("%08X" % value).encode()
    out += trailer
    out += b"\0" * ((-len(out)) % 4)
    return bytes(out)


def build_squashfs(payload_bytes=1 << 20, compression=4, inode_count=42):
    """Build a minimal but structurally valid SquashFS 4.0 superblock."""
    data = bytearray(96)
    data[0:4] = b"hsqs"
    struct.pack_into("<10I", data, 8,
                     inode_count, 1700000000, 131072, 0, compression,
                     17, 0, 3, 4, 0)
    struct.pack_into("<2Q", data, 48, inode_count, payload_bytes)
    return bytes(data)


class BuildConfParseTest(unittest.TestCase):
    """build.conf is parsed as text, never sourced."""

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)

    def write(self, text):
        path = os.path.join(self.tmp.name, "build.conf")
        with open(path, "w", encoding="utf-8") as handle:
            handle.write(text)
        return path

    def test_parses_quoted_unquoted_and_commented_values(self):
        path = self.write(
            'export A="quoted"\n'
            'export B=unquoted        # trailing comment\n'
            "# export C=\"commented out\"\n"
            'D="inline # not a comment"\n'
        )
        values = audit.parse_build_conf(path)
        self.assertEqual(values["A"], "quoted")
        self.assertEqual(values["B"], "unquoted")
        self.assertEqual(values["D"], "inline # not a comment")
        self.assertNotIn("C", values)

    def test_resolves_parameter_expansion(self):
        path = self.write(
            'export DISTRO_VERSION="0.2.2-dev"\n'
            'export DISTRO_VERSION_ID="${DISTRO_VERSION%%-*}"\n'
            'export CHAIN="${DISTRO_VERSION_ID}-final"\n'
        )
        values = audit.parse_build_conf(path)
        self.assertEqual(values["DISTRO_VERSION_ID"], "0.2.2")
        self.assertEqual(values["CHAIN"], "0.2.2-final")

    def test_self_reference_terminates(self):
        path = self.write('export A="${A}loop"\n')
        values = audit.parse_build_conf(path)   # must not hang
        self.assertIn("A", values)


class ManifestParseTest(unittest.TestCase):

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)

    def write(self, text, name="packages.list"):
        path = os.path.join(self.tmp.name, name)
        with open(path, "w", encoding="utf-8") as handle:
            handle.write(text)
        return path

    def test_tsv_flags_placeholder_and_bad_checksums(self):
        good = "a" * 64
        path = self.write(
            "ok\t1.0\thttps://example.org/a.tar.xz\t%s\n" % good +
            "zero\t1.0\thttps://example.org/b.tar.xz\t%s\n" % ("0" * 64) +
            "short\t1.0\thttps://example.org/c.tar.xz\tdeadbeef\n" +
            "insecure\t1.0\thttp://example.org/d.tar.xz\t%s\n" % good
        )
        entries = audit.parse_manifest(path)
        by_name = {e["name"]: e for e in entries}
        self.assertEqual(len(entries), 4)
        self.assertTrue(by_name["ok"]["valid"])
        self.assertIn("placeholder", by_name["zero"]["problem"])
        self.assertIn("64 hex", by_name["short"]["problem"])
        self.assertIn("HTTPS", by_name["insecure"]["problem"])

    def test_shell_assignment_pairs_url_with_sha(self):
        path = self.write(
            'KERNEL_URL=https://cdn.kernel.org/linux-6.18.tar.xz\n'
            'KERNEL_SHA256="%s"\n' % ("b" * 64),
            name="sources.list",
        )
        entries = audit.parse_manifest(path)
        self.assertEqual(len(entries), 1)
        self.assertEqual(entries[0]["name"], "KERNEL")
        self.assertEqual(entries[0]["sha256"], "b" * 64)
        self.assertTrue(entries[0]["valid"])

    def test_shell_assignment_without_sha_is_invalid(self):
        path = self.write(
            "DWM_URL=https://dl.suckless.org/dwm/dwm-6.5.tar.gz\n",
            name="sources.list")
        entries = audit.parse_manifest(path)
        self.assertEqual(len(entries), 1)
        self.assertFalse(entries[0]["valid"])
        self.assertIn("DWM_SHA256", entries[0]["problem"])


class CpioParseTest(unittest.TestCase):

    def test_round_trip_counts_and_classifies(self):
        payload = b"binary-contents" * 10
        entries = [
            ("bin", payload, 0o100755),
            ("lib", b"\x7fELF" + b"\0" * 50, 0o100644),
            ("dev", b"", 0o040755),
            ("link", b"", 0o120777),
        ]
        parsed = audit.parse_newc(build_cpio(entries))
        self.assertEqual([e["name"] for e in parsed],
                         ["bin", "lib", "dev", "link", "TRAILER!!!"])
        self.assertEqual(parsed[0]["size"], len(payload))
        summary = audit.summarize_entries(parsed)
        self.assertEqual(summary["regular_files"], 2)
        self.assertEqual(summary["directories"], 1)
        self.assertEqual(summary["symlinks"], 1)
        self.assertEqual(summary["executables"], 1)
        # Ancestor directories of regular files must resolve for directory probes.
        self.assertIn("/bin", summary["present"])

    def test_gzip_round_trip(self):
        raw = build_cpio([("a", b"x" * 1000, 0o100644)])
        blob = gzip.compress(raw)
        restored = gzip.GzipFile(fileobj=io.BytesIO(blob)).read()
        self.assertEqual(restored, raw)


class SquashfsParseTest(unittest.TestCase):

    def test_reads_superblock_fields(self):
        data = build_squashfs(payload_bytes=12345678, compression=4)
        info = audit.parse_squashfs(data)
        self.assertEqual(info["version"], "4.0")
        self.assertEqual(info["compression"], "xz")
        self.assertEqual(info["inode_count"], 42)
        self.assertEqual(info["bytes_used"], 12345678)

    def test_rejects_non_squashfs(self):
        with self.assertRaises(ValueError):
            audit.parse_squashfs(b"not a squashfs image at all" * 10)

    def test_known_compression_ids(self):
        for comp_id, name in ((1, "gzip"), (4, "xz"), (6, "zstd")):
            info = audit.parse_squashfs(build_squashfs(compression=comp_id))
            self.assertEqual(info["compression"], name)


class HumanSizeTest(unittest.TestCase):

    def test_formats(self):
        self.assertEqual(audit.human(512), "512 B")
        self.assertEqual(audit.human(1024), "1.00 KiB")
        self.assertEqual(audit.human(1024 * 1024), "1.00 MiB")
        self.assertEqual(audit.human(3 * 1024 ** 3), "3.00 GiB")
        self.assertEqual(audit.human(None), "unknown")


class IsoNameNormalisationTest(unittest.TestCase):
    """Regression: ISO 9660 uppercases names and appends a version suffix.

    An earlier version matched on ``BZIMAGE;1`` literally, so a real image
    written without a version (``BZIMAGE.``) was reported as having no kernel.
    """

    class FakeImage:
        """Minimal stand-in that reuses the real IsoImage.find implementation."""

        find = audit.IsoImage.find

        def __init__(self, files):
            self.files = files

    def setUp(self):
        self.image = self.FakeImage([
            ("BOOT/", 0, 0, True),
            ("BOOT/BZIMAGE.;1", 100, 0, False),
            ("BOOT/INITRAMFS_CPIO.GZ;1", 200, 0, False),
            ("LIVE/FILESYSTEM.SQUASHFS;1", 300, 0, False),
            ("EFI/BOOTX64.EFI;1", 50, 0, False),
        ])

    def test_matches_unversioned_and_versioned_names(self):
        self.assertIsNotNone(self.image.find("bzImage", "vmlinuz"))
        self.assertEqual(self.image.find("bzImage", "vmlinuz")[1], 100)

    def test_finds_squashfs_case_insensitively(self):
        found = self.image.find("filesystem.squashfs")
        self.assertIsNotNone(found)
        self.assertEqual(found[1], 300)

    def test_absent_file_returns_none(self):
        self.assertIsNone(self.image.find("nonexistent.img"))

    def test_directories_are_never_matched(self):
        only_dir = self.FakeImage([("BOOT/", 0, 0, True)])
        self.assertIsNone(only_dir.find("boot"))


class ClassificationTest(unittest.TestCase):
    """Categories must be mutually exclusive and size-ordered as documented."""

    def test_specific_categories_win_over_executables(self):
        cases = [
            ("/usr/lib/libc.a", "static_archives"),
            ("/lib/modules/6.18/virtio.ko", "kernel_modules"),
            ("/usr/lib/libc.so.6", "shared_objects"),
            ("/usr/share/fonts/x.ttf", "fonts"),
            ("/usr/share/applications/x.desktop", "desktop_entries"),
            ("/usr/share/man/man1/ls.1.gz", "man_pages"),
        ]
        for path, expected in cases:
            self.assertEqual(audit.classify_entry(path.lstrip("/"), 10, 0o100644),
                             expected, "wrong category for " + path)

    def test_executable_falls_through(self):
        self.assertEqual(audit.classify_entry("usr/bin/true", 10, 0o100755),
                         "executables")

    def test_desktop_requirements_are_unique_and_suffixed(self):
        seen = set()
        for label, candidates in audit.DESKTOP_REQUIREMENTS:
            self.assertNotIn(label, seen, "duplicate requirement " + label)
            seen.add(label)
            for candidate in candidates:
                self.assertFalse(candidate.startswith("/"),
                                 "candidate must be relative: " + candidate)


class RepoAuditTest(unittest.TestCase):
    """End-to-end audit of the real repository tree."""

    @classmethod
    def setUpClass(cls):
        cls.report = audit.audit_repo(REPO_ROOT)

    def test_distribution_metadata_present(self):
        dist = self.report["distribution"]
        self.assertEqual(dist["id"], "shreeos")
        self.assertTrue(dist["version"])

    def test_toolchain_versions_are_resolved(self):
        tool = self.report["toolchain"]
        self.assertEqual(tool["triplet"], "x86_64-shreeos-linux-gnu")
        self.assertTrue(tool["gcc"] and not tool["gcc"].startswith("${"))
        self.assertTrue(tool["glibc"] and not tool["glibc"].startswith("${"))

    def test_graphics_manifest_is_fully_pinned(self):
        info = self.report["pinned_sources"]["desktop/graphics/packages.list"]
        self.assertEqual(info["invalid"], [],
                         "graphics sources must all be checksum-pinned")

    def test_build_output_excluded_from_layout(self):
        self.assertNotIn("build", self.report["layout"])
        self.assertNotIn("out", self.report["layout"])
        self.assertNotIn(".git", self.report["layout"])

    def test_workflows_detected_without_suppressed_failures(self):
        names = {w["name"] for w in self.report["workflows"]}
        self.assertIn("iso.yml", names)
        for flow in self.report["workflows"]:
            self.assertFalse(flow["continue_on_error"],
                             flow["name"] + " uses continue-on-error")
            self.assertFalse(flow["suppresses_failures"],
                             flow["name"] + " suppresses a failure with '|| true'")

    def test_report_is_json_serialisable(self):
        import json
        json.dumps(self.report, sort_keys=True, default=str)


if __name__ == "__main__":
    unittest.main(verbosity=2)
