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
        self.assertEqual(dock["hide-mode"], "'none'")
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
            env = dict(os.environ, HOME=home.as_posix(), XDG_CONFIG_HOME=(home / ".config").as_posix())
            result = subprocess.run([shell, (INCLUDES / "usr/local/bin/shreeos-plasma-first-login").as_posix()],
                                    env=env, capture_output=True, text=True, timeout=5)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(custom.read_text(), "user-owned layout")
            self.assertEqual(marker.read_text(), "existing profile")


if __name__ == "__main__":
    unittest.main()
