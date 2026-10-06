#!/usr/bin/env python3
"""Exercise repository provisioning, motion commands, and input boundaries."""

import configparser
import importlib.util
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest
from unittest import mock
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[2]
FEATURES = ROOT / "prototype/debian-live/features"
PLASMA = ROOT / "prototype/debian-live/profiles/plasma/includes.chroot"
DESKTOP = ROOT / "prototype/debian-live/profiles/desktop/includes.chroot"
spec = importlib.util.spec_from_file_location(
    "sources", FEATURES / "includes.chroot/usr/lib/calamares/modules/shreeos-sources/main.py")
sources = importlib.util.module_from_spec(spec)
spec.loader.exec_module(sources)


def shell():
    if os.name == "nt":
        return str(Path(os.environ.get("PROGRAMFILES", "C:/Program Files")) / "Git/bin/bash.exe")
    return shutil.which("bash")


class RepositoryTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name) / "target"
        for directory in ("etc/apt/sources.list.d", "etc/shreeos", "usr/share/keyrings"):
            (self.root / directory).mkdir(parents=True)
        (self.root / "etc/shreeos/firmware-policy").write_text("free\n")
        (self.root / "usr/share/keyrings/debian-archive-keyring.gpg").write_bytes(b"fixture")
        self.old = self.root / "etc/apt/sources.list"
        self.old.write_text("deb https://snapshot.debian.org/archive/debian/old trixie main\n")
        self.destination = self.root / "etc/apt/sources.list.d/debian.sources"

    def test_free_install_uses_signed_stable_and_security_not_snapshot(self):
        sources.configure_sources(str(self.root))
        text = self.destination.read_text()
        self.assertIn("Suites: trixie trixie-updates", text)
        self.assertIn("Suites: trixie-security", text)
        self.assertEqual(text.count("Signed-By:"), 2)
        self.assertNotIn("snapshot", text)
        self.assertNotIn("non-free", text)
        self.assertNotIn("backports", text)
        self.assertFalse(self.old.exists())
        self.assertTrue(self.old.with_name("sources.list.shreeos-install-backup").exists())

    def test_standard_install_preserves_firmware_updates(self):
        (self.root / "etc/shreeos/firmware-policy").write_text("standard\n")
        sources.configure_sources(str(self.root))
        self.assertEqual(self.destination.read_text().count("Components: main non-free-firmware"), 2)

    def test_failed_write_leaves_existing_repositories_available(self):
        original = self.old.read_text()
        with mock.patch.object(sources, "atomic_write", side_effect=OSError("disk full")):
            with self.assertRaisesRegex(OSError, "disk full"):
                sources.configure_sources(str(self.root))
        self.assertEqual(self.old.read_text(), original)
        self.assertFalse(self.destination.exists())

    def test_rerun_is_idempotent_and_disables_other_build_sources(self):
        extra = self.root / "etc/apt/sources.list.d/live.list"
        extra.write_text("deb file:/run/live/medium trixie main\n")
        sources.configure_sources(str(self.root))
        first = self.destination.read_text()
        sources.configure_sources(str(self.root))
        self.assertEqual(self.destination.read_text(), first)
        self.assertFalse(extra.exists())
        self.assertEqual(extra.with_name("live.list.shreeos-install-backup").read_text(),
                         "deb file:/run/live/medium trixie main\n")

    def test_missing_keyring_and_unknown_policy_fail_before_sources_change(self):
        key = self.root / "usr/share/keyrings/debian-archive-keyring.gpg"
        key.unlink()
        with self.assertRaisesRegex(ValueError, "keyring"):
            sources.configure_sources(str(self.root))
        self.assertTrue(self.old.exists())
        key.write_bytes(b"fixture")
        (self.root / "etc/shreeos/firmware-policy").write_text("unknown")
        with self.assertRaisesRegex(ValueError, "policy"):
            sources.configure_sources(str(self.root))
        self.assertTrue(self.old.exists())
        self.assertFalse(self.destination.exists())

    def test_rejects_missing_relative_and_running_root_targets(self):
        for value in (None, "", ".", Path.cwd().anchor):
            with self.subTest(value=value), self.assertRaises(ValueError):
                sources.configure_sources(value)

    def test_symlink_cannot_write_outside_target(self):
        outside = Path(self.temporary.name) / "outside"
        outside.write_text("unchanged")
        try:
            self.destination.symlink_to(outside)
        except OSError:
            self.skipTest("This host cannot create symlinks")
        with self.assertRaisesRegex(ValueError, "escapes|symlink"):
            sources.configure_sources(str(self.root))
        self.assertEqual(outside.read_text(), "unchanged")
        self.assertTrue(self.old.exists())


class CommandTests(unittest.TestCase):
    def test_builder_rejects_bad_feature_selection_before_touching_build_tree(self):
        for values in ({"SHREEOS_FIRMWARE": "unknown"},
                       {"SHREEOS_TOOLSETS": "security,../../outside"},
                       {"SHREEOS_TOOLSETS": "security,"},
                       {"SHREEOS_TOOLSETS": "developer,,creative"}):
            with self.subTest(values=values):
                env = dict(os.environ, SHREEOS_FIRMWARE="free", SHREEOS_TOOLSETS="")
                env.update(values)
                result = subprocess.run([shell(), (ROOT / "scripts/build-debian-prototype.sh").as_posix()],
                                        env=env, capture_output=True, text=True, timeout=5)
                self.assertEqual(result.returncode, 2, result.stderr)
                self.assertNotIn("must be built as root", result.stderr)

    def test_xdg_profile_marker_preserves_existing_layout(self):
        with tempfile.TemporaryDirectory() as temporary:
            folder = Path(temporary)
            config = folder / "custom-config"
            marker = config / "shreeos/plasma-defaults-applied"
            marker.parent.mkdir(parents=True)
            marker.write_text("existing")
            layout = config / "plasma-org.kde.plasma.desktop-appletsrc"
            layout.write_text("custom layout")
            env = dict(os.environ, HOME=(folder / "home").as_posix(), XDG_CONFIG_HOME=config.as_posix())
            result = subprocess.run([shell(), (PLASMA / "usr/local/bin/shreeos-plasma-first-login").as_posix()],
                                    env=env, capture_output=True, text=True, timeout=5)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(layout.read_text(), "custom layout")
            self.assertFalse((folder / "home/.config").exists())

    def test_motion_profiles_write_expected_settings_without_resetting_layout(self):
        with tempfile.TemporaryDirectory() as temporary:
            folder = Path(temporary)
            log = folder / "calls"
            # Execute the real script with fake session commands, never changing
            # host settings or requiring a running Plasma desktop.
            for name in ("kwriteconfig6", "dconf", "dbus-send", "notify-send"):
                stub = folder / name
                stub.write_text('#!/bin/sh\nprintf "%s" "${0##*/}" >> "$CALLS"\n'
                                'printf " <%s>" "$@" >> "$CALLS"\nprintf "\\n" >> "$CALLS"\n')
                stub.chmod(0o755)
            env = dict(os.environ, PATH=folder.as_posix() + (";" if os.name == "nt" else ":") + os.environ["PATH"],
                       CALLS=log.as_posix())
            for mode, factor, blur in (("balanced", "0.8", "true"), ("performance", "0.5", "false"),
                                       ("reduced", "0", "false")):
                if log.exists():
                    log.unlink()
                result = subprocess.run([shell(), (PLASMA / "usr/local/bin/shreeos-motion").as_posix(), mode],
                                        env=env, text=True, capture_output=True, timeout=10)
                self.assertEqual(result.returncode, 0, result.stderr)
                text = log.read_text()
                self.assertIn(f"<AnimationDurationFactor> <{factor}>", text)
                self.assertIn(f"<blurEnabled> <{blur}>", text)
                self.assertIn("<squashEnabled> <false>", text)
                self.assertNotIn("plasma-org.kde.plasma.desktop-appletsrc", text)
                self.assertIn("org.kde.KWin.reconfigure", text)

    def test_bad_arguments_do_not_launch_privileged_actions(self):
        cases = [
            (PLASMA / "usr/local/bin/shreeos-motion", ["bad-mode"]),
            (FEATURES / "includes.chroot/usr/local/bin/shreeos-software", ["install", "../../etc/passwd"]),
            (FEATURES / "includes.chroot/usr/local/bin/shreeos-software", ["install", "security", "--yes"]),
            (DESKTOP / "usr/local/bin/shreeos-installer", ["--config", "/tmp/untrusted"]),
            (DESKTOP / "usr/local/libexec/shreeos-installer-privileged", ["--config", "/tmp/untrusted"]),
        ]
        for script, arguments in cases:
            with self.subTest(script=script, arguments=arguments):
                result = subprocess.run([shell(), script.as_posix(), *arguments],
                                        capture_output=True, text=True, timeout=5)
                self.assertEqual(result.returncode, 2, result.stderr)

    def test_installer_display_policy_is_scoped_to_fixed_wrapper(self):
        policy = ET.parse(DESKTOP / "usr/share/polkit-1/actions/org.shreeos.installer.policy")
        actions = policy.findall("action")
        self.assertEqual(len(actions), 1)
        annotations = {node.get("key"): node.text for node in actions[0].findall("annotate")}
        self.assertEqual(annotations["org.freedesktop.policykit.exec.path"],
                         "/usr/local/libexec/shreeos-installer-privileged")
        self.assertEqual(annotations["org.freedesktop.policykit.exec.allow_gui"], "true")
        self.assertEqual(actions[0].findtext("defaults/allow_inactive"), "no")

    def test_shortcuts_have_valid_kconfig_lists(self):
        config = configparser.RawConfigParser()
        config.read(PLASMA / "etc/skel/.config/kglobalshortcutsrc")
        for section in config.sections():
            for key, value in config[section].items():
                self.assertEqual(len(value.split(",")), 3, f"Invalid shortcut: {key}")


if __name__ == "__main__":
    unittest.main()
