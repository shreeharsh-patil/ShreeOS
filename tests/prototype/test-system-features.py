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


def shell_path(path):
    if os.name != "nt":
        return str(path)
    cygpath = Path(os.environ.get("PROGRAMFILES", "C:/Program Files")) / "Git/usr/bin/cygpath.exe"
    result = subprocess.run([str(cygpath), "-u", str(path)],
                            check=True, capture_output=True, text=True)
    return result.stdout.strip()


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
                result = subprocess.run([shell(), shell_path(ROOT / "scripts/build-debian-prototype.sh")],
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
            env = dict(os.environ, HOME=shell_path(folder / "home"),
                       XDG_CONFIG_HOME=shell_path(config))
            result = subprocess.run([shell(), shell_path(PLASMA / "usr/local/bin/shreeos-plasma-first-login")],
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
            if os.name == "nt":
                stub_paths = [shell_path(stub) for stub in folder.iterdir()]
                subprocess.run([shell(), "-c", 'chmod +x "$@"', "sh", *stub_paths],
                               check=True, capture_output=True, text=True)
                env = dict(os.environ, SHREEOS_TEST_BIN=shell_path(folder),
                           CALLS=shell_path(log))
                path_setup = 'PATH="$SHREEOS_TEST_BIN:$PATH"; export PATH; '
            else:
                env = dict(os.environ, PATH=f'{folder.as_posix()}{os.pathsep}{os.environ["PATH"]}',
                           CALLS=log.as_posix())
            for mode, factor, blur in (("balanced", "0.8", "true"), ("performance", "0.5", "false"),
                                       ("reduced", "0", "false")):
                if log.exists():
                    log.unlink()
                if os.name == "nt":
                    invocation = [shell(), "-c", path_setup + 'exec "$SHREEOS_TEST_SCRIPT" "$1"',
                                  "sh", mode]
                    env["SHREEOS_TEST_SCRIPT"] = shell_path(PLASMA / "usr/local/bin/shreeos-motion")
                else:
                    invocation = [shell(), shell_path(PLASMA / "usr/local/bin/shreeos-motion"), mode]
                result = subprocess.run(invocation,
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
            (PLASMA / "usr/local/bin/shreeos-power", ["turbo"]),
            (PLASMA / "usr/local/bin/shreeos-power", ["balanced", "extra"]),
            (FEATURES / "includes.chroot/usr/local/bin/shreeos-software", ["install", "../../etc/passwd"]),
            (FEATURES / "includes.chroot/usr/local/bin/shreeos-software", ["install", "security", "--yes"]),
            (DESKTOP / "usr/local/bin/shreeos-installer", ["--config", "/tmp/untrusted"]),
            (DESKTOP / "usr/local/libexec/shreeos-installer-privileged", ["--config", "/tmp/untrusted"]),
        ]
        for script, arguments in cases:
            with self.subTest(script=script, arguments=arguments):
                result = subprocess.run([shell(), shell_path(script), *arguments],
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

    def test_calamares_3314_guided_layout_uses_supported_gpt_partition_options(self):
        partition = (ROOT / "prototype/debian-live/profiles/desktop/includes.chroot"
                     / "etc/calamares/modules/partition.conf").read_text(encoding="utf-8")
        self.assertNotIn("createHybridBootloaderLayout", partition)
        self.assertIn("defaultPartitionTableType: gpt", partition)
        self.assertIn("requiredPartitionTableType: gpt", partition)
        self.assertIn("enableLuksAutomatedPartitioning: false", partition)
        self.assertRegex(partition, r"(?m)^lvm:\s*\n\s+enable: false$")
        self.assertRegex(partition, r"(?s)directoryFilesystemRestrictions:.*?directory: \"/\".*?allowedFilesystemTypes: \[\"ext4\"\]")
        self.assertRegex(partition, r"(?s)mountpoint: \"efi\".*?allowedFilesystemTypes: \[\"fat32\"\]")
        self.assertIn("mountPoint: /boot/efi", partition)
        self.assertIn("recommendedSize: 512MiB", partition)
        self.assertRegex(partition, r"(?s)partitionLayout:.*?type: \"21686148-6449-6E6F-744E-656564454649\".*?filesystem: unformatted.*?mountPoint: /.*?size: 100%")
        self.assertIn("efi:", partition)

    def test_installer_rejects_bios_mode_before_starting_calamares(self):
        includes = (ROOT / "prototype/debian-live/profiles/desktop/includes.chroot")
        launcher = (includes / "usr/local/bin/shreeos-installer").read_text(encoding="utf-8")
        privileged = (includes / "usr/local/libexec/shreeos-installer-privileged").read_text(
            encoding="utf-8"
        )
        guard = "/sys/firmware/efi"
        self.assertIn(guard, launcher)
        self.assertIn(guard, privileged)
        self.assertLess(launcher.index(guard), launcher.index("exec /usr/local/libexec/shreeos-installer-privileged"))
        self.assertLess(privileged.index(guard), privileged.index("/usr/bin/calamares"))

    def test_calamares_3314_runs_validated_bios_grub_install_after_efi_install(self):
        bootloader = (ROOT / "prototype/debian-live/profiles/desktop/includes.chroot"
                     / "etc/calamares/modules/bootloader.conf").read_text(encoding="utf-8")
        settings = (ROOT / "prototype/debian-live/profiles/desktop/includes.chroot"
                    / "etc/calamares/settings.conf").read_text(encoding="utf-8")
        preflight_config = (ROOT / "prototype/debian-live/profiles/desktop/includes.chroot"
                            / "etc/calamares/modules/shellprocess-storage-preflight.conf").read_text(
                                encoding="utf-8"
                            )
        shellprocess = (ROOT / "prototype/debian-live/profiles/desktop/includes.chroot"
                        / "etc/calamares/modules/shellprocess.conf").read_text(encoding="utf-8")
        helper = (ROOT / "prototype/debian-live/profiles/desktop/includes.chroot"
                  / "usr/local/libexec/shreeos-install-bios-grub").read_text(encoding="utf-8")
        self.assertIn("efiBootLoader: grub", bootloader)
        self.assertIn("efiBootloaderId: debian", bootloader)
        self.assertIn("installEFIFallback: true", bootloader)
        self.assertNotIn("installHybridGRUB", bootloader)
        self.assertRegex(settings, r"(?s)- mount\s+- shellprocess@storage-preflight\s+- unpackfs")
        self.assertRegex(settings, r"(?s)- bootloader\s+- packages\s+- shellprocess")
        self.assertIn("id: storage-preflight", settings)
        self.assertIn("config: shellprocess-storage-preflight.conf", settings)
        self.assertIn("dontChroot: true", preflight_config)
        self.assertIn("--validate-only", preflight_config)
        self.assertNotIn("-/bin/sh", preflight_config)
        self.assertIn("dontChroot: true", shellprocess)
        self.assertIn("/usr/local/libexec/shreeos-install-bios-grub", shellprocess)
        self.assertIn("${ROOT}", shellprocess)
        self.assertIn("${gs[firmwareType]}", shellprocess)
        self.assertIn('findmnt --noheadings --raw --output SOURCE --target "$target_root/boot/efi"', helper)
        self.assertIn('[ "$#" -eq 2 ] || [ "$#" -eq 3 ]', helper)
        self.assertIn("--validate-only", helper)
        self.assertIn('"$esp_filesystem" = vfat', helper)
        self.assertIn('"$root_filesystem" = ext4', helper)
        self.assertIn('"$firmware_type" = efi', helper)
        self.assertIn('findmnt --noheadings --raw --output SOURCE --target "$target_root"', helper)
        self.assertIn('"$root_disk" = "$disk"', helper)
        self.assertIn("c12a7328-f81f-11d2-ba4b-00a0c93ec93b", helper)
        self.assertIn("21686148-6449-6e6f-744e-656564454649", helper)
        self.assertIn('chroot "$target_root" grub-install --target=i386-pc --recheck', helper)
        builder = (ROOT / "scripts/build-debian-prototype.sh").read_text(encoding="utf-8")
        self.assertRegex(
            builder,
            r'install -Dm0755 \\\s+"\$CONFIG_SOURCE/profiles/desktop/includes\.chroot/usr/local/libexec/shreeos-install-bios-grub" \\\s+"\$BUILD_DIR/config/includes\.chroot/usr/local/libexec/shreeos-install-bios-grub"',
        )
        self.assertIn("grub-pc-bin", (ROOT / "prototype/debian-live/profiles/plasma/package-lists"
                                      / "shreeos-plasma.list.chroot").read_text(encoding="utf-8"))
        self.assertIn("grub-efi-amd64-bin", (ROOT / "prototype/debian-live/profiles/plasma/package-lists"
                                             / "shreeos-plasma.list.chroot").read_text(encoding="utf-8"))

    def test_installer_docs_require_uefi_origin_and_define_crossboot_matrix(self):
        acceptance = (ROOT / "release/INSTALL-ACCEPTANCE.md").read_text(encoding="utf-8")
        normalized = " ".join(acceptance.split())
        self.assertIn("boot the ISO in **UEFI mode** for both the guided", normalized)
        self.assertIn("boot on each installed disk in legacy BIOS mode", normalized)

    def test_dolphin_smb_kio_worker_is_explicit_when_recommends_are_disabled(self):
        package_list = (ROOT / "prototype/debian-live/profiles/plasma/package-lists"
                        / "shreeos-plasma.list.chroot").read_text(encoding="utf-8")
        builder = (ROOT / "scripts/build-debian-prototype.sh").read_text(encoding="utf-8")
        self.assertRegex(package_list, r"(?m)^kio-extras$")
        self.assertIn("kio-extras", builder)
        self.assertIn('if [ "$SHREEOS_UNIFIED" = 1 ]; then APT_RECOMMENDS=false; fi', builder)

    def test_native_hardware_daemon_runs_without_root_and_uses_group_socket(self):
        package_builder = (ROOT / "scripts/package-unified-native.sh").read_text(encoding="utf-8")
        daemon = (ROOT / "hardware/daemon/shreed.c").read_text(encoding="utf-8")
        test_source = (ROOT / "hardware/tests/test-shreed.c").read_text(encoding="utf-8")
        header = (ROOT / "hardware/include/shreed.h").read_text(encoding="utf-8")
        network_script = (ROOT / "hardware/scripts/shree-network").read_text(encoding="utf-8")
        hardware_readme = (ROOT / "hardware/README.md").read_text(encoding="utf-8")
        self.assertIn("User=shreed", package_builder)
        self.assertIn("Group=shree-hardware", package_builder)
        self.assertIn("CapabilityBoundingSet=", package_builder)
        self.assertIn("ProtectSystem=strict", package_builder)
        self.assertIn("adduser --system --quiet --no-create-home", package_builder)
        self.assertIn("chmod(socket_path, 0660)", daemon)
        self.assertNotIn("chmod(socket_path, 0666)", daemon)
        self.assertIn('#define SHREED_SOCKET_PATH "/run/shreeos/shreed.sock"', header)
        self.assertIn('/run/shreeos/shreed.sock', network_script)
        self.assertIn('`0660`', hardware_readme)
        self.assertNotIn('`0666`', hardware_readme)
        self.assertIn('setgid(hardware->gr_gid)', test_source)
        self.assertIn('status.st_gid == expected_gid', test_source)
        self.assertIn('bool test_socket_open = chmod(socket_path, 0666) == 0;', test_source)
        self.assertIn('chmod(socket_path, 0660) == 0', test_source)

    def test_manual_cross_firmware_layout_names_the_required_gpt_types(self):
        docs = (ROOT / "docs/UNIFIED-IMAGE.md").read_text(encoding="utf-8")
        acceptance = (ROOT / "release/INSTALL-ACCEPTANCE.md").read_text(encoding="utf-8")
        for source in (docs, acceptance):
            normalized = " ".join(source.split())
            self.assertIn("21686148-6449-6e6f-744e-656564454649", normalized)
            self.assertIn("c12a7328-f81f-11d2-ba4b-00a0c93ec93b", normalized)

    def test_shortcuts_have_valid_kconfig_lists(self):
        config = configparser.RawConfigParser()
        config.read(PLASMA / "etc/skel/.config/kglobalshortcutsrc")
        for section in config.sections():
            for key, value in config[section].items():
                self.assertEqual(len(value.split(",")), 3, f"Invalid shortcut: {key}")


if __name__ == "__main__":
    unittest.main()
