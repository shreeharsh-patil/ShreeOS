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
import re
import struct
import subprocess
import sys
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
        """Minimal stand-in that reuses the real IsoImage name-matching logic.

        Built with ``__new__`` so ``find``/``find_prefix`` and their
        ``_mangled`` helper are the production implementations rather than
        reimplementations that could drift from them.
        """

        def __init__(self, files):
            real = audit.IsoImage.__new__(audit.IsoImage)
            real.files = files
            self.files = files
            self.find = real.find
            self.find_prefix = real.find_prefix
            self._mangled = real._mangled

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


class ProfileDetectionTest(unittest.TestCase):
    """The profile is read from the filename; a wrong one mislabels coverage.

    ShreeOS names images `shreeos-<version>-<profile>.iso`, and the minimal
    profile `shreeos-<version>.iso`. Guessing "minimal" for an unrecognised
    name would quietly under-report a desktop image's missing components, so
    the tool must say "unknown" instead.
    """

    def test_recognises_each_profile(self):
        cases = {
            "shreeos-0.2.2-dev-desktop.iso": "desktop",
            "shreeos-0.2.2-dev-server.iso": "server",
            "shreeos-0.2.2-dev-security.iso": "security",
            # The minimal image carries no profile suffix. The version itself
            # contains a dash, so this is the case a naive "last component"
            # parse gets wrong.
            "shreeos-0.2.2-dev.iso": "minimal",
            "shreeos-1.0.iso": "minimal",
            "shreeos-0.2.2-dev-minimal.iso": "minimal",
        }
        for name, expected in cases.items():
            self.assertEqual(audit.detect_profile(name), expected, name)

    def test_unrecognised_name_is_unknown_not_minimal(self):
        # A non-ShreeOS image must not be labelled with a ShreeOS profile.
        self.assertEqual(audit.detect_profile("download.iso"), "unknown")
        self.assertEqual(audit.detect_profile("ubuntu-24.04-desktop.iso"), "unknown")
        self.assertEqual(audit.detect_profile("shreeos.iso"), "unknown")
        self.assertEqual(audit.detect_profile("shreeos-.iso"), "unknown")
        # An unknown trailing component is not a profile either.
        self.assertEqual(audit.detect_profile("shreeos-1.0-workstation.iso"),
                         "minimal")

    def test_version_containing_a_profile_word_is_not_mistaken(self):
        # A hypothetical future version must not be read as a profile.
        self.assertEqual(audit.detect_profile("shreeos-2.0-server.iso"), "server")
        self.assertEqual(audit.detect_profile("shreeos-2.0-desktoprc.iso"),
                         "minimal")

    def test_distro_id_prefix_is_honoured(self):
        self.assertEqual(
            audit.detect_profile("shreeos-1.0-desktop.iso", distro_id="shreeos"),
            "desktop")
        self.assertEqual(
            audit.detect_profile("shreeos-1.0-desktop.iso", distro_id="other"),
            "unknown")

    def test_directory_component_is_ignored(self):
        self.assertEqual(
            audit.detect_profile("/tmp/artifacts/shreeos-1.0-desktop.iso"),
            "desktop")

    def test_audit_iso_accepts_explicit_profile(self):
        self.assertEqual(
            audit.audit_iso.__defaults__, (None,),
            "profile_override must default to None so the filename is used")


class WorkflowSelectionTest(unittest.TestCase):
    """The ISO audit must inspect the newest release, not a stale one.

    `/releases/latest` excludes pre-releases. ShreeOS publishes every ISO as a
    pre-release, so that endpoint returns the *oldest* published image and the
    audit would silently report on stale contents forever.
    """

    WORKFLOW = os.path.join(REPO_ROOT, ".github", "workflows", "audit.yml")

    @classmethod
    def setUpClass(cls):
        with open(cls.WORKFLOW, "r", encoding="utf-8") as handle:
            cls.text = handle.read()

    def test_does_not_use_releases_latest_endpoint(self):
        # Match the endpoint in real use, not inside an explanatory comment.
        self.assertNotRegex(self.text, r"api\.github\.com[^\"']*/releases/latest",
                            "audit must not use /releases/latest; it hides pre-releases")

    def test_lists_releases_including_pre_releases(self):
        self.assertIn("/releases?per_page=", self.text)

    def test_prefers_desktop_profile_iso(self):
        self.assertIn('"-desktop.iso", ".iso"', self.text)

    def test_no_suppressed_failures(self):
        self.assertNotIn("|| true", self.text)
        self.assertNotIn("continue-on-error", self.text)

    def test_artifacts_are_uploaded(self):
        self.assertIn("actions/upload-artifact@", self.text)


class MakefileTargetTest(unittest.TestCase):
    """`make audit` and `make test-audit` must stay wired to the tool."""

    @classmethod
    def setUpClass(cls):
        with open(os.path.join(REPO_ROOT, "Makefile"), "r",
                  encoding="utf-8") as handle:
            cls.text = handle.read()

    def test_audit_target_runs_the_tool(self):
        self.assertRegex(self.text, r"(?m)^audit:")
        self.assertIn("tools/shreeos-audit.py repo", self.text)

    def test_test_audit_target_runs_the_suite(self):
        self.assertRegex(self.text, r"(?m)^test-audit:")
        self.assertIn("tests/audit/test-shreeos-audit.py", self.text)

    def test_audit_runs_as_part_of_the_full_test_suite(self):
        self.assertRegex(self.text, r"(?m)^test-all:.*\btest-audit\b")


class WorkflowShellSyntaxTest(unittest.TestCase):
    """Every `run: |` block in every workflow must be valid shell.

    A workflow is only executed on a runner, so a shell typo inside a `run:`
    block would otherwise surface as a CI failure long after the edit. This
    test is skipped when no bash is available, because its purpose is to parse
    the blocks, not to run them.
    """

    TOOL = os.path.join(REPO_ROOT, "tools", "check-workflow-shell.py")

    @classmethod
    def setUpClass(cls):
        try:
            subprocess.run([os.environ.get("BASH", "bash"), "-n"],
                           input="", text=True, capture_output=True, check=True)
        except (OSError, subprocess.CalledProcessError):
            raise unittest.SkipTest("no usable bash for shell syntax checking")
        cls.workflow_dir = os.path.join(REPO_ROOT, ".github", "workflows")
        cls.workflows = sorted(
            os.path.join(cls.workflow_dir, name)
            for name in os.listdir(cls.workflow_dir)
            if name.endswith((".yml", ".yaml"))
        )

    def test_at_least_one_workflow_exists(self):
        self.assertTrue(self.workflows)

    def test_every_run_block_parses(self):
        self.assertTrue(self.workflows, "no workflows found")
        for workflow in self.workflows:
            with self.subTest(workflow=os.path.basename(workflow)):
                result = subprocess.run(
                    [sys.executable, self.TOOL, workflow],
                    capture_output=True, text=True,
                    env=dict(os.environ, BASH=os.environ.get("BASH", "bash")))
                self.assertEqual(
                    result.returncode, 0,
                    "%s:\n%s%s" % (workflow, result.stdout, result.stderr))
                self.assertIn("0 failed", result.stdout)

    def test_reports_blocks_it_actually_found(self):
        # A silent zero-block pass would make the test above meaningless.
        result = subprocess.run(
            [sys.executable, self.TOOL, self.workflows[0]],
            capture_output=True, text=True,
            env=dict(os.environ, BASH=os.environ.get("BASH", "bash")))
        found = re.search(r"(\d+) run blocks checked", result.stdout)
        self.assertIsNotNone(found, result.stdout)
        self.assertGreater(int(found.group(1)), 0)

    def test_missing_file_is_an_error_not_a_pass(self):
        result = subprocess.run(
            [sys.executable, self.TOOL,
             os.path.join(self.workflow_dir, "does-not-exist.yml")],
            capture_output=True, text=True)
        self.assertNotEqual(result.returncode, 0)


class IsoParseTest(unittest.TestCase):
    """The ISO walker must be exercised against a real image, not a stub."""

    ISO = os.path.join(REPO_ROOT, "build", "audit", "cur",
                       "shreeos-0.2.2-dev-desktop.iso")

    def setUp(self):
        if not os.path.isfile(self.ISO):
            self.skipTest("released ISO not present locally")
        self.iso = audit.IsoImage(self.ISO)
        self.addCleanup(self.iso.close)

    def test_reads_volume_id_and_el_torito(self):
        self.assertTrue(self.iso.volume_id)
        self.assertTrue(self.iso.el_torito)

    def test_finds_the_three_boot_assets(self):
        self.assertIsNotNone(self.iso.find("bzImage"))
        self.assertIsNotNone(self.iso.find("initramfs.cpio.gz"))
        self.assertIsNotNone(self.iso.find("grub.cfg"))

    def test_initramfs_dominates_the_image(self):
        """Guards the audit's central claim: the live OS rides in the cpio."""
        entry = self.iso.find("initramfs.cpio.gz")
        self.assertGreater(entry[1], os.path.getsize(self.ISO) // 2)

    def test_uefi_entry_point_present(self):
        self.assertIsNotNone(self.iso.find("BOOTX64.EFI"))


if __name__ == "__main__":
    unittest.main(verbosity=2)
