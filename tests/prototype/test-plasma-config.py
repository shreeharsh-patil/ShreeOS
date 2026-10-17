#!/usr/bin/env python3
"""Check Plasma asset wiring and preservation of existing user preferences."""

import ast
import configparser
import json
import os
from pathlib import Path
import shutil
import struct
import subprocess
import tempfile
import unittest
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[2]
PROFILE = ROOT / "prototype/debian-live/profiles/plasma"
INCLUDES = PROFILE / "includes.chroot"
STYLE = ROOT / "themes/plasma/shreeos-glass"


def read_ini(path):
    parser = configparser.RawConfigParser()
    parser.read(path, encoding="utf-8")
    return parser


def shell_path(path):
    if os.name != "nt":
        return str(path)
    cygpath = Path(os.environ.get("PROGRAMFILES", "C:/Program Files")) / "Git/usr/bin/cygpath.exe"
    result = subprocess.run([str(cygpath), "-u", str(path)],
                            check=True, capture_output=True, text=True)
    return result.stdout.strip()


class PlasmaConfigTests(unittest.TestCase):
    def test_every_pinned_app_has_a_launcher_and_an_installed_provider(self):
        dock = read_ini(INCLUDES / "usr/share/shreeos/defaults/plasma-plank.dconf")
        dock = dock["net/launchpad/plank/docks/dock1"]
        items = ast.literal_eval(dock["dock-items"])
        self.assertEqual(len(items), len(set(items)), "Duplicate dock launchers")
        packages = set((PROFILE / "package-lists/shreeos-plasma.list.chroot").read_text().splitlines())
        native_apps = {
            "org.kde.dolphin": "dolphin", "firefox-esr": "firefox-esr",
            "org.kde.kate": "kate", "org.kde.gwenview": "gwenview",
            "org.kde.okular": "okular", "org.kde.kcalc": "kcalc",
            "org.kde.konsole": "konsole", "org.kde.discover": "plasma-discover",
            "systemsettings": "kde-plasma-desktop",
        }
        for item in items:
            path = INCLUDES / "etc/skel/.config/plank/dock1/launchers" / item
            self.assertTrue(path.is_file(), f"Missing pinned launcher: {item}")
            url = read_ini(path)["PlankDockItemPreferences"]["Launcher"]
            self.assertTrue(url.startswith("file:///usr/share/applications/"))
            app = url.rsplit("/", 1)[1].removesuffix(".desktop")
            if app in native_apps:
                self.assertIn(native_apps[app], packages, f"{app} lacks its package")
            else:
                local = INCLUDES / "usr/share/applications" / f"{app}.desktop"
                shared = ROOT / "prototype/debian-live/profiles/desktop/includes.chroot/usr/share/applications" / f"{app}.desktop"
                self.assertTrue(local.is_file() or shared.is_file(), f"Missing app: {app}")
        self.assertEqual(dock["hide-mode"], "'auto'")
        self.assertEqual(dock["zoom-enabled"], "true")
        self.assertIn("plank", packages)
        self.assertIn("dconf-cli", packages)

    def test_light_defaults_agree_across_native_gtk_and_terminal_apps(self):
        kde = read_ini(INCLUDES / "etc/skel/.config/kdeglobals")
        defaults = read_ini(INCLUDES / "usr/share/plasma/look-and-feel/org.shreeos.desktop/contents/defaults")
        terminal = read_ini(INCLUDES / "etc/skel/.local/share/konsole/ShreeOS.profile")
        self.assertEqual(kde["General"]["ColorScheme"], "ShreeOS Light")
        self.assertEqual(defaults["kdeglobals][General"]["ColorScheme"], kde["General"]["ColorScheme"])
        self.assertEqual(terminal["Appearance"]["ColorScheme"], kde["General"]["ColorScheme"])
        self.assertEqual(kde["Icons"]["Theme"], "Papirus")
        for version in ("3.0", "4.0"):
            gtk = read_ini(INCLUDES / f"etc/skel/.config/gtk-{version}/settings.ini")["Settings"]
            self.assertEqual(gtk["gtk-theme-name"], "Breeze")
            self.assertEqual(gtk["gtk-icon-theme-name"], kde["Icons"]["Theme"])
            self.assertEqual(gtk["gtk-application-prefer-dark-theme"], "0")

    def test_style_has_complete_surface_and_opaque_fallback(self):
        metadata = json.loads((STYLE / "metadata.json").read_text())
        self.assertEqual(metadata["KPlugin"]["Id"], STYLE.name)
        self.assertEqual(read_ini(INCLUDES / "etc/skel/.config/plasmarc")["Theme"]["name"], STYLE.name)
        required = {"center", "top", "topleft", "topright", "left", "right",
                    "bottom", "bottomleft", "bottomright"}
        for relative in ("widgets/panel-background.svg", "opaque/widgets/panel-background.svg"):
            svg = ET.parse(STYLE / relative)
            ids = {element.get("id") for element in svg.iter()}
            self.assertTrue(required.issubset(ids), f"Incomplete panel frame: {relative}")
        opaque = ET.parse(STYLE / "opaque/widgets/panel-background.svg")
        surface = next(e for e in opaque.iter() if e.get("class") == "ColorScheme-Background")
        self.assertEqual(surface.get("fill-opacity"), "1")

    def test_macos_inspired_desktop_contract(self):
        layout = (ROOT / "desktop/plasma/layout.js").read_text()
        self.assertIn('menuBar.height = 30;', layout)
        self.assertIn('launcher.writeConfig("menuLabel", "ShreeOS")', layout)
        self.assertIn('org.kde.plasma.appmenu', layout)
        self.assertIn('org.kde.plasma.systemtray', layout)

        dock = read_ini(INCLUDES / "usr/share/shreeos/defaults/plasma-plank.dconf")
        dock = dock["net/launchpad/plank/docks/dock1"]
        self.assertEqual(dock["alignment"], "'center'")
        self.assertEqual(dock["position"], "'bottom'")
        self.assertEqual(dock["icon-size"], "50")
        self.assertEqual(dock["zoom-percent"], "145")
        self.assertEqual(dock["theme"], "'ShreeOS-Glass'")
        for variant in ("ShreeOS-Glass", "ShreeOS-Glass-Dark"):
            theme = read_ini(INCLUDES / f"usr/share/plank/themes/{variant}/dock.theme")
            self.assertEqual(theme["PlankTheme"]["TopRoundness"], "18")
            self.assertEqual(theme["PlankTheme"]["BottomRoundness"], "18")

        shortcuts = read_ini(INCLUDES / "etc/skel/.config/kglobalshortcutsrc")
        self.assertEqual(shortcuts["kwin"]["Overview"].split(",")[0], "Meta+Ctrl+Up")
        self.assertEqual(shortcuts["kwin"]["Switch to Next Desktop"].split(",")[0], "Meta+Ctrl+Right")
        self.assertEqual(shortcuts["kwin"]["Switch to Previous Desktop"].split(",")[0], "Meta+Ctrl+Left")
        self.assertEqual(shortcuts["org.kde.krunner.desktop"]["_launch"].split(",")[0], "Meta+Space")
        greeter = (INCLUDES / "usr/share/sddm/themes/shreeos/Main.qml").read_text()
        self.assertIn("Qt.formatTime(root.currentDate", greeter)
        self.assertIn("Qt.formatDate(root.currentDate", greeter)
        self.assertIn("root.height >= 750", greeter)

    def test_wallpaper_is_real_png_with_desktop_proportions(self):
        image = ROOT / "branding/wallpapers/shreeos-alpenglow.png"
        header = image.read_bytes()[:24]
        self.assertEqual(header[:8], b"\x89PNG\r\n\x1a\n")
        width, height = struct.unpack(">II", header[16:24])
        self.assertGreaterEqual(width, 1280)
        self.assertAlmostEqual(width / height, 16 / 9, delta=0.01)

    def test_plasma_dock_keeps_existing_pinned_app_settings(self):
        dock_script = (INCLUDES / "usr/local/bin/shreeos-plasma-dock").read_text()
        self.assertIn("existing_items=", dock_script)
        self.assertIn("if [ -z \"$existing_items\" ]; then", dock_script)
        self.assertIn("dconf load / <", dock_script)
        self.assertIn('touch "$marker"', dock_script)

    def test_first_login_preserves_an_existing_profile(self):
        shell = shutil.which("sh")
        if os.name == "nt":
            shell = str(Path(os.environ.get("PROGRAMFILES", "C:/Program Files")) / "Git/bin/bash.exe")
        self.assertTrue(shell and Path(shell).is_file(), "A POSIX shell is required")
        with tempfile.TemporaryDirectory() as temporary:
            home = Path(temporary)
            marker = home / ".config/shreeos/plasma-defaults-applied"
            marker.parent.mkdir(parents=True)
            marker.write_text("existing profile")
            custom = home / ".config/plasma-org.kde.plasma.desktop-appletsrc"
            custom.write_text("user-owned layout")
            env = dict(os.environ, HOME=shell_path(home),
                       XDG_CONFIG_HOME=shell_path(home / ".config"))
            result = subprocess.run([shell, shell_path(INCLUDES / "usr/local/bin/shreeos-plasma-first-login")],
                                    env=env, capture_output=True, text=True, timeout=5)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(custom.read_text(), "user-owned layout")
            self.assertEqual(marker.read_text(), "existing profile")

    def test_fresh_profile_marker_is_installed_in_skel(self):
        marker = INCLUDES / "etc/skel/.config/shreeos/plasma-fresh-profile"
        self.assertTrue(marker.is_file())
        self.assertIn("fresh shreeos accounts", marker.read_text().lower())

    def test_first_login_handles_restarted_and_in_place_shell_layout_updates(self):
        shell = shutil.which("sh")
        if os.name == "nt":
            shell = str(Path(os.environ.get("PROGRAMFILES", "C:/Program Files")) / "Git/bin/bash.exe")
        self.assertTrue(shell and Path(shell).is_file(), "A POSIX shell is required")
        with tempfile.TemporaryDirectory() as temporary:
            folder = Path(temporary)
            calls = folder / "calls"
            config_home = folder / "config"
            stubs = {
                "sleep": '#!/bin/sh\nprintf "sleep\\n" >> "$CALLS"\n',
                "pgrep": (
                    '#!/bin/sh\n'
                    'count_file="$CALLS.pgrep-count"\n'
                    'count=0; [ ! -f "$count_file" ] || count="$(cat "$count_file")"\n'
                    'count=$((count + 1)); printf "%s\\n" "$count" > "$count_file"\n'
                    'printf "pgrep:%s\\n" "$count" >> "$CALLS"\n'
                    '[ "${PGREP_MODE:-restart}" != stable ] || { echo 4321; exit 0; }\n'
                    'case "$count" in 1|2) echo 4321 ;; 4|5|6) echo 5678 ;; *) exit 1 ;; esac\n'
                ),
                "plasma-apply-lookandfeel": (
                    '#!/bin/sh\nprintf "lookandfeel\\n" >> "$CALLS"\n'
                    'mkdir -p "$XDG_CONFIG_HOME"\n'
                    'printf "plugin=org.kde.plasma.systemtray\\nplugin=org.kde.plasma.kickoff\\n'
                    'plugin=org.kde.plasma.appmenu\\nplugin=org.kde.plasma.digitalclock\\n" '
                    '> "$XDG_CONFIG_HOME/plasma-org.kde.plasma.desktop-appletsrc"\n'
                ),
                "plasma-apply-desktoptheme": '#!/bin/sh\nprintf "desktoptheme\\n" >> "$CALLS"\n',
                "shreeos-theme": '#!/bin/sh\nprintf "theme\\n" >> "$CALLS"\n',
                "plasma-apply-wallpaperimage": '#!/bin/sh\nprintf "wallpaper\\n" >> "$CALLS"\n',
                "plasma-apply-colorscheme": '#!/bin/sh\nprintf "colorscheme\\n" >> "$CALLS"\n',
                "kwriteconfig6": '#!/bin/sh\nprintf "kwriteconfig\\n" >> "$CALLS"\n',
                "logger": '#!/bin/sh\nprintf "logger\\n" >> "$CALLS"\n',
                "dpkg-query": '#!/bin/sh\nexit 0\n',
                "dconf": '#!/bin/sh\nprintf "dconf\\n" >> "$CALLS"\n',
                "notify-send": '#!/bin/sh\nprintf "notify\\n" >> "$CALLS"\n',
            }
            for name, body in stubs.items():
                stub = folder / name
                stub.write_text(body)
                stub.chmod(0o755)
            if os.name == "nt":
                stub_paths = [shell_path(stub) for stub in folder.iterdir() if stub.name != "shreeos-plasma-first-login"]
                subprocess.run([shell, "-c", 'chmod +x "$@"', "sh", *stub_paths],
                               check=True, capture_output=True, text=True)
            script_text = (INCLUDES / "usr/local/bin/shreeos-plasma-first-login").read_text()
            self.assertEqual(script_text.count("/usr/local/bin/shreeos-theme"), 1)
            script = folder / "shreeos-plasma-first-login"
            script.write_text(script_text.replace("/usr/local/bin/shreeos-theme", "shreeos-theme"))
            if os.name == "nt":
                env = dict(os.environ,
                           HOME=shell_path(folder / "home"),
                           XDG_CONFIG_HOME=shell_path(config_home),
                           SHREEOS_PLASMA_FIRST_LOGIN_SERVICE="1",
                           CALLS=shell_path(calls),
                           SHREEOS_TEST_BIN=shell_path(folder))
                command = 'PATH="$SHREEOS_TEST_BIN:$PATH"; export PATH; exec "$SHREEOS_TEST_SCRIPT"'
                env["SHREEOS_TEST_SCRIPT"] = shell_path(script)
                invocation = [shell, "-c", command]
            else:
                env = dict(os.environ, PATH=folder.as_posix() + ":" + os.environ["PATH"],
                           HOME=(folder / "home").as_posix(), XDG_CONFIG_HOME=config_home.as_posix(),
                           SHREEOS_PLASMA_FIRST_LOGIN_SERVICE="1", CALLS=calls.as_posix())
                invocation = [shell, script.as_posix()]
            result = subprocess.run(invocation,
                                    env=env, capture_output=True, text=True, timeout=10)
            self.assertEqual(result.returncode, 0, result.stderr)
            trace = calls.read_text().splitlines()
            self.assertLess(trace.index("pgrep:1"), trace.index("lookandfeel"))
            self.assertLess(trace.index("lookandfeel"), trace.index("pgrep:2"))
            self.assertLess(trace.index("pgrep:2"), trace.index("pgrep:3"))
            self.assertLess(trace.index("pgrep:3"), trace.index("pgrep:4"))
            self.assertLess(trace.index("pgrep:4"), trace.index("pgrep:5"))
            self.assertLess(trace.index("pgrep:5"), trace.index("wallpaper"))

            # Plasma may update the applet layout without replacing its shell.
            # That must still finish first-login setup and release dock startup.
            marker = config_home / "shreeos/plasma-defaults-applied"
            marker.unlink()
            (config_home / "shreeos/plasma-fresh-profile").touch()
            calls.write_text("")
            Path(f"{calls}.pgrep-count").unlink()
            stable_env = dict(env, PGREP_MODE="stable")
            result = subprocess.run(invocation,
                                    env=stable_env, capture_output=True, text=True, timeout=10)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertTrue(marker.is_file())
            self.assertIn("wallpaper", calls.read_text().splitlines())

            # An existing profile without the fresh-account marker may belong
            # to a user upgrade; preserve its layout when ShreeOS defaults have
            # not yet been recorded for that account.
            marker.unlink()
            (config_home / "shreeos/plasma-fresh-profile").unlink(missing_ok=True)
            custom_layout = config_home / "plasma-org.kde.plasma.desktop-appletsrc"
            custom_layout.write_text("user-owned custom layout\n")
            custom_theme = config_home / "kdeglobals"
            custom_theme.write_text("user-owned color scheme\n")
            calls.write_text("")
            Path(f"{calls}.pgrep-count").unlink()
            result = subprocess.run(invocation,
                                    env=stable_env, capture_output=True, text=True, timeout=10)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(custom_layout.read_text(), "user-owned custom layout\n")
            self.assertEqual(custom_theme.read_text(), "user-owned color scheme\n")
            self.assertEqual(calls.read_text().splitlines(), ["logger"])
            self.assertTrue(marker.is_file())


if __name__ == "__main__":
    unittest.main()
