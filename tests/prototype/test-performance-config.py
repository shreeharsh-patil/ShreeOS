#!/usr/bin/env python3
"""Regression tests for the ShreeOS idle-cost and power-profile defaults.

These assert the *mechanisms* that keep idle RAM, CPU and package weight down.
They are deliberately about configuration and script structure, because the
actual resource measurements can only be taken inside a booted QEMU guest
(tests/qemu) -- a configuration change is not evidence of a resource win.
"""

import configparser
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
PROFILE = ROOT / "prototype/debian-live/profiles/plasma"
INCLUDES = PROFILE / "includes.chroot"
BIN = INCLUDES / "usr/local/bin"
PACKAGE_LIST = PROFILE / "package-lists/shreeos-plasma.list.chroot"


def shell():
    if os.name == "nt":
        return str(Path(os.environ.get("PROGRAMFILES", "C:/Program Files")) / "Git/bin/bash.exe")
    return shutil.which("bash")


def read_ini(path):
    parser = configparser.RawConfigParser()
    parser.read(path, encoding="utf-8")
    return parser


def package_entries():
    lines = PACKAGE_LIST.read_text(encoding="utf-8").splitlines()
    return [line.strip() for line in lines if line.strip() and not line.lstrip().startswith("#")]


class IndexerTests(unittest.TestCase):
    def test_baloo_keeps_filename_search_but_not_full_text_indexing(self):
        baloo = read_ini(INCLUDES / "etc/skel/.config/baloofilerc")
        settings = baloo["Basic Settings"]
        self.assertEqual(settings["Indexing-Enabled"], "true",
                         "File search must keep working; do not disable Baloo outright")
        self.assertEqual(settings["Only Basic Indexing"], "true",
                         "Content extraction is the dominant avoidable idle cost")

    def test_baloo_uses_only_documented_keys_and_no_contradictions(self):
        text = (INCLUDES / "etc/skel/.config/baloofilerc").read_text(encoding="utf-8")
        keys = [line.split("=", 1)[0].strip()
                for line in text.splitlines()
                if "=" in line and not line.lstrip().startswith("#")]
        self.assertEqual(len(keys), len(set(keys)), f"Contradictory duplicate keys: {keys}")
        self.assertEqual(set(keys), {"Indexing-Enabled", "Only Basic Indexing"})


class CompositingTests(unittest.TestCase):
    def test_compositing_is_not_forced_off_for_every_install(self):
        kwinrc = read_ini(INCLUDES / "etc/skel/.config/kwinrc")
        if kwinrc.has_section("Compositing"):
            self.assertNotEqual(
                kwinrc["Compositing"].get("Enabled"), "false",
                "Forcing compositing off leaves every installation without a compositor")

    def test_blur_setting_agrees_with_the_compositor_being_available(self):
        kwinrc = read_ini(INCLUDES / "etc/skel/.config/kwinrc")
        forced_off = (kwinrc.has_section("Compositing")
                      and kwinrc["Compositing"].get("Enabled") == "false")
        self.assertFalse(forced_off and kwinrc["Plugins"]["blurEnabled"] == "true",
                         "Blur cannot be enabled while compositing is forced off")

    def test_live_media_is_the_only_place_that_disables_compositing(self):
        first_login = (BIN / "shreeos-plasma-first-login").read_text(encoding="utf-8")
        self.assertIn("/run/live/medium", first_login)
        self.assertRegex(first_login, r"Compositing[^\n]*Enabled false")
        # The guard must be the live-medium test, not an unconditional write.
        guarded = re.search(
            r"if \[ -d /run/live/medium \][^\n]*\n(?:.*\n)*?fi\n", first_login)
        self.assertIsNotNone(guarded, "Live compositing change must be inside its guard")

    def test_desktop_still_gets_four_workspaces_and_left_window_controls(self):
        kwinrc = read_ini(INCLUDES / "etc/skel/.config/kwinrc")
        self.assertEqual(kwinrc["Desktops"]["Number"], "4")
        self.assertEqual(kwinrc["org.kde.kdecoration2"]["ButtonsOnLeft"], "XIA")
        self.assertEqual(kwinrc["org.kde.kdecoration2"]["ButtonsOnRight"], "")


class SessionStartupTests(unittest.TestCase):
    """Session scripts must not poll a process table once per second."""

    def assert_backoff(self, name):
        text = (BIN / name).read_text(encoding="utf-8")
        self.assertRegex(text, r"interval=\$\(\([a-z_]*interval \* 2\)\)",
                         f"{name} must grow its wait interval instead of polling")

        # Isolate the process-table wait loops: a block that polls pgrep must not
        # also hardcode a one-second interval. Retry loops around expensive
        # commands are a different thing and are intentionally not checked.
        poll_loops = [block for block in re.findall(r"while\b.*?\ndone\n", text, re.DOTALL)
                      if "pgrep" in block]
        self.assertTrue(poll_loops,
                        f"{name} no longer contains a process wait loop; the check is stale")
        for block in poll_loops:
            self.assertNotRegex(block, r"^\s*sleep 1\s*$",
                                f"{name} still polls pgrep on a fixed one-second interval")

    def test_dock_waits_with_backoff(self):
        self.assert_backoff("shreeos-plasma-dock")

    def test_first_login_waits_with_backoff(self):
        self.assert_backoff("shreeos-plasma-first-login")

    def test_first_login_records_the_default_power_profile_without_polling(self):
        text = (BIN / "shreeos-plasma-first-login").read_text(encoding="utf-8")
        self.assertIn("--key PowerProfile balanced", text)

    def test_performance_probe_waits_for_a_ready_desktop_and_reports_pss(self):
        probe = (ROOT / "prototype/debian-live/config/includes.chroot/usr/local/sbin/shreeos-perf-probe").read_text(encoding="utf-8")
        self.assertIn("DESKTOP_WAIT_SECONDS=180", probe)
        self.assertIn("plasma-defaults-applied", probe)
        self.assertIn('emit desktop_ready "$ready"', probe)
        self.assertIn("smaps_rollup", probe)
        self.assertIn('emit pss_available "$pss_supported"', probe)


class PowerProfileTests(unittest.TestCase):
    STUBS = {
        "powerprofilesctl": (
            '#!/bin/sh\n'
            'case "${1:-}" in\n'
            '  list) printf "performance:\\n\\tDriver: intel_pstate\\nbalanced:\\n\\tDriver: intel_pstate\\n'
            'power-saver:\\n\\tDriver: intel_pstate\\n" ;;\n'
            '  get) printf "balanced\\n" ;;\n'
            '  set) printf "set %s\\n" "$2" >> "$CALLS" ;;\n'
            'esac\n'
        ),
        "shreeos-motion": '#!/bin/sh\nprintf "shreeos-motion %s\\n" "$1" >> "$CALLS"\n',
        "kwriteconfig6": (
            '#!/bin/sh\nprintf "kwriteconfig6" >> "$CALLS"\n'
            'printf " <%s>" "$@" >> "$CALLS"\nprintf "\\n" >> "$CALLS"\n'
        ),
        "notify-send": '#!/bin/sh\nprintf "notify-send\\n" >> "$CALLS"\n',
        "kdialog": '#!/bin/sh\nprintf "balanced\\n"\n',
    }

    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.folder = Path(self.temporary.name)
        self.calls = self.folder / "calls"
        for name, body in self.STUBS.items():
            stub = self.folder / name
            stub.write_text(body)
            stub.chmod(0o755)
        separator = ";" if os.name == "nt" else ":"
        self.env = dict(
            os.environ,
            PATH=self.folder.as_posix() + separator + os.environ["PATH"],
            CALLS=self.calls.as_posix(),
            XDG_CONFIG_HOME=(self.folder / "config").as_posix(),
            HOME=(self.folder / "home").as_posix(),
        )

    def run_power(self, *arguments):
        return subprocess.run([shell(), (BIN / "shreeos-power").as_posix(), *arguments],
                              env=self.env, capture_output=True, text=True, timeout=15)

    def calls_text(self):
        return self.calls.read_text() if self.calls.exists() else ""

    def test_the_three_profiles_map_to_platform_power_and_motion(self):
        expected = {
            "performance": ("set performance", "shreeos-motion performance"),
            "balanced": ("set balanced", "shreeos-motion balanced"),
            "battery-saver": ("set power-saver", "shreeos-motion reduced"),
        }
        for profile, wanted in expected.items():
            with self.subTest(profile=profile):
                if self.calls.exists():
                    self.calls.unlink()
                result = self.run_power(profile)
                self.assertEqual(result.returncode, 0, result.stderr)
                text = self.calls_text()
                for fragment in wanted:
                    self.assertIn(fragment, text)
                self.assertIn(f"--key> <PowerProfile> <{profile}>", text)

    def test_battery_saver_description_matches_implemented_behavior(self):
        result = self.run_power()
        self.assertEqual(result.returncode, 0, result.stderr)
        chooser = (BIN / "shreeos-power").read_text(encoding="utf-8")
        self.assertIn("Lower platform power use, fewer visual effects", chooser)
        self.assertNotIn("reduced background work", chooser)

    def test_an_unsupported_platform_profile_is_reported_not_claimed(self):
        # power-profiles-daemon on a desktop usually advertises no power-saver.
        (self.folder / "powerprofilesctl").write_text(
            '#!/bin/sh\ncase "${1:-}" in\n'
            '  list) printf "performance:\\nbalanced:\\n" ;;\n'
            '  get) printf "balanced\\n" ;;\n'
            '  set) printf "set %s\\n" "$2" >> "$CALLS" ;;\nesac\n')
        (self.folder / "powerprofilesctl").chmod(0o755)
        result = self.run_power("battery-saver")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("did not confirm", result.stdout)
        self.assertNotIn("set power-saver", self.calls_text())

    def test_a_system_without_power_profiles_daemon_still_switches_motion(self):
        (self.folder / "powerprofilesctl").unlink()
        result = self.run_power("battery-saver")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("shreeos-motion reduced", self.calls_text())

    def test_invalid_profiles_are_rejected_before_anything_is_applied(self):
        for value in ("turbo", "Performance", "", "--force"):
            with self.subTest(value=value):
                if self.calls.exists():
                    self.calls.unlink()
                result = self.run_power(value) if value else self.run_power()
                if value == "":
                    # No argument opens the chooser (stubbed) rather than failing.
                    self.assertEqual(result.returncode, 0, result.stderr)
                    continue
                self.assertEqual(result.returncode, 2, result.stderr)
                self.assertNotIn("shreeos-motion", self.calls_text())

    def test_status_reports_both_layers(self):
        config = self.folder / "config"
        config.mkdir(parents=True, exist_ok=True)
        (config / "shreeosrc").write_text("[Desktop]\nPowerProfile=balanced\nMotion=balanced\n")
        result = self.run_power("--status")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("power-profiles-daemon=balanced", result.stdout)
        self.assertIn("motion=balanced", result.stdout)


class PackageManifestTests(unittest.TestCase):
    def test_plasma_manifest_has_no_duplicate_entries(self):
        entries = package_entries()
        duplicates = sorted({entry for entry in entries if entries.count(entry) > 1})
        self.assertEqual(duplicates, [], f"Duplicate package entries: {duplicates}")

    def test_only_one_desktop_environment_is_installed(self):
        entries = set(package_entries())
        self.assertIn("kde-plasma-desktop", entries)
        for foreign in ("task-xfce-desktop", "xfce4", "gnome-shell", "budgie-desktop"):
            self.assertNotIn(foreign, entries,
                             f"{foreign} would add a second desktop suite to the image")

    def test_one_dock_provider_only(self):
        entries = set(package_entries())
        # The dock is Plank. A second dock provider would double the process tree.
        for competing in ("latte-dock", "kdeplasma-addons-applets-latte", "docky", "cairo-dock"):
            self.assertNotIn(competing, entries, f"{competing} competes with the ShreeOS dock")

    def test_large_office_and_media_suites_stay_optional(self):
        entries = set(package_entries())
        for package in ("libreoffice-writer", "libreoffice-calc", "libreoffice-impress",
                        "libreoffice-kf6", "vlc"):
            self.assertNotIn(package, entries, f"{package} should be optional")
        for bundle in ("office", "multimedia"):
            self.assertTrue((ROOT / f"prototype/debian-live/features/toolsets/{bundle}.list.chroot").is_file())

    def test_shared_base_services_are_not_redeclared_in_the_plasma_manifest(self):
        self.assertNotIn("network-manager", package_entries())

    def test_power_and_compression_stack_is_present(self):
        entries = set(package_entries())
        for required in ("power-profiles-daemon", "systemd-zram-generator",
                         "plasma-pa", "plasma-nm", "bluedevil", "powerdevil"):
            self.assertIn(required, entries)

    def test_every_shipped_launcher_points_at_a_real_program(self):
        desktop_dir = INCLUDES / "usr/share/applications"
        entries = sorted(desktop_dir.glob("shreeos-*.desktop"))
        self.assertGreaterEqual(len(entries), 5)
        for entry in entries:
            exec_line = next(line for line in entry.read_text(encoding="utf-8").splitlines()
                             if line.startswith("Exec="))
            command = exec_line.split("=", 1)[1].split()[0]
            if command.startswith("/usr/local/bin/"):
                # ShreeOS-owned tools ship in the image and must actually be there.
                self.assertTrue((BIN / Path(command).name).is_file(),
                                f"{entry.name} launches {command}, which is not packaged")
            else:
                # An upstream program may be named absolutely or resolved through
                # PATH (krunner). Either way it must be a concrete program name so
                # the launcher cannot be a placeholder.
                self.assertRegex(Path(command).name, r"^[A-Za-z0-9._+-]+$",
                                 f"{entry.name} has an invalid program name")


class ResourceBoundTests(unittest.TestCase):
    def test_zram_is_bounded_and_not_a_swap_thrash_source(self):
        conf = (INCLUDES / "usr/lib/systemd/zram-generator.conf.d/50-shreeos.conf"
                ).read_text(encoding="utf-8")
        self.assertRegex(conf, r"zram-size\s*=\s*min\(ram / 2, 2048\)")
        self.assertIn("compression-algorithm = lz4", conf)
        self.assertIn("swap-priority = 100", conf)

    def test_no_script_uses_an_unbounded_busy_wait(self):
        offenders = []
        for script in sorted(BIN.iterdir()):
            if not script.is_file():
                continue
            text = script.read_text(encoding="utf-8", errors="replace")
            if not text.startswith("#!"):
                continue
            # `while true` / `until false` with no deadline is the pattern to avoid.
            if re.search(r"while\s+(true|:)\s*;", text):
                offenders.append(script.name)
        self.assertEqual(offenders, [], f"Unbounded waits: {offenders}")


class MeasurementProvenanceTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.folder = Path(self.temporary.name)
        self.iso = self.folder / "image.iso"
        self.iso.write_bytes(b"ShreeOS fixture image")
        self.manifest = self.folder / "image-manifest.json"
        self.commit = "9313ebb042cf71bb148441037940b130d49920d1"
        self.iso_sha256 = hashlib.sha256(self.iso.read_bytes()).hexdigest()
        self.iso_size = self.iso.stat().st_size
        self.metadata = {
            "commit": self.commit,
            "git_dirty": False,
            "sha256": self.iso_sha256,
            "size_bytes": self.iso_size,
        }

    def verify(self, allow_instrumentation_overlay=False):
        self.manifest.write_text(json.dumps(self.metadata), encoding="utf-8")
        arguments = [sys.executable, str(ROOT / "scripts/verify-performance-manifest.py"),
                     str(self.manifest), str(self.iso)]
        if allow_instrumentation_overlay:
            arguments.append("--allow-instrumentation-overlay")
        return subprocess.run(
            arguments,
            capture_output=True, text=True, timeout=10,
        )

    def test_accepts_clean_image_with_matching_checksum_and_size(self):
        result = self.verify()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip(), self.commit)

    def test_rejects_dirty_source(self):
        self.metadata["git_dirty"] = True
        result = self.verify()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("clean source commit", result.stderr)

    def test_accepts_only_explicitly_authorized_instrumentation_overlay(self):
        self.metadata["git_dirty"] = True
        result = self.verify(allow_instrumentation_overlay=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip(), self.commit)

    def test_rejects_checksum_or_size_mismatch(self):
        for field, value, message in (
            ("sha256", "0" * 64, "SHA256 does not match"),
            ("size_bytes", self.iso_size + 1, "size does not match"),
        ):
            with self.subTest(field=field):
                self.metadata[field] = value
                result = self.verify()
                self.assertNotEqual(result.returncode, 0)
                self.assertIn(message, result.stderr)
                self.metadata[field] = self.iso_sha256 if field == "sha256" else self.iso_size

    def test_rejects_invalid_commit(self):
        self.metadata["commit"] = "not-a-commit"
        result = self.verify()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("valid source commit", result.stderr)

    def test_performance_runner_checks_required_tools(self):
        report = (ROOT / "tests/prototype/test-performance-report.sh").read_text(encoding="utf-8")
        for tool in ("unsquashfs", "xvfb-run", "sha256sum"):
            self.assertIn(tool, report)

    def test_performance_runner_rejects_a_different_embedded_probe(self):
        report = (ROOT / "tests/prototype/test-performance-report.sh").read_text(encoding="utf-8")
        self.assertIn('cmp -s "$PROBE_SOURCE" "$TEST_DIR/probe"', report)
        self.assertIn('cmp -s "$SERVICE_SOURCE" "$TEST_DIR/probe.service"', report)
        self.assertIn("ALLOW_PERFORMANCE_INSTRUMENTATION_OVERLAY", report)
        baseline = (ROOT / ".github/workflows/performance-baseline.yml").read_text(encoding="utf-8")
        self.assertIn('install -D "../measurement-harness/$probe_path" "$probe_path"', baseline)
        self.assertIn('install -D "../measurement-harness/$unit_path" "$unit_path"', baseline)
        self.assertIn("expected_changes=", baseline)

    def test_boot_time_parser_handles_minute_and_second_values(self):
        probe = (ROOT / "prototype/debian-live/config/includes.chroot/usr/local/sbin/shreeos-perf-probe").read_text(encoding="utf-8")
        minutes_case = probe.index("    *min*)")
        seconds_case = probe.index("    *s) awk")
        self.assertLess(minutes_case, seconds_case,
                        "Minute durations must be parsed before the generic seconds suffix")


if __name__ == "__main__":
    unittest.main()
