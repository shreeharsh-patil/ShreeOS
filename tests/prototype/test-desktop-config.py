#!/usr/bin/env python3
"""Check the ShreeOS XFCE, Plank, GTK, and artwork profile contract."""
from __future__ import annotations

import ast
import configparser
import sys
import xml.etree.ElementTree as ET
from pathlib import Path
from urllib.parse import unquote, urlparse


ROOT = Path(__file__).resolve().parents[2]
PROFILE = ROOT / "prototype/debian-live/profiles/desktop"
INCLUDES = PROFILE / "includes.chroot"
SKEL = INCLUDES / "etc/skel"


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit(f"FAIL: {message}")


def parse_xml(path: Path) -> ET.Element:
    try:
        return ET.parse(path).getroot()
    except (ET.ParseError, OSError) as exc:
        raise SystemExit(f"FAIL: invalid XML {path}: {exc}") from exc


def main() -> int:
    grub_dir = ROOT / "prototype/debian-live/config/bootloaders/grub-pc"
    grub_splash = parse_xml(grub_dir / "splash.svg")
    require(grub_splash.tag == "{http://www.w3.org/2000/svg}svg"
            and grub_splash.get("viewBox") == "0 0 800 600",
            "ShreeOS GRUB splash artwork is missing or has an unexpected canvas")
    grub_theme_path = grub_dir / "live-theme/theme.txt"
    grub_theme = grub_theme_path.read_text(encoding="utf-8")
    for contract in ('desktop-image: "../splash.png"', 'title-text: "ShreeOS"',
                     'text = "A calmer way to compute"', '+ boot_menu {',
                     'selected_item_color = "#ffffff"'):
        require(contract in grub_theme,
                f"ShreeOS GRUB menu theme is missing {contract}")

    panel_path = SKEL / ".config/xfce4/xfconf/xfce-perchannel-xml/xfce4-panel.xml"
    panel = parse_xml(panel_path)
    require(panel.tag == "channel" and panel.get("name") == "xfce4-panel",
            "XFCE panel channel is missing or misnamed")
    require(panel.find("property[@name='configver']") is not None
            and panel.find("property[@name='configver']").get("value") == "2",
            "XFCE panel defaults do not declare the current panel configuration schema")
    panels = panel.find("property[@name='panels']")
    require(panels is not None and panels.find("value[@value='1']") is not None,
            "XFCE panel IDs are not stored in the current panel configuration hierarchy")
    panel_one = panels.find("property[@name='panel-1']")
    require(panel_one is not None, "ShreeOS top panel is not configured")
    plugin_ids = {
        int(item.get("value", "-1"))
        for item in panel_one.findall("property[@name='plugin-ids']/value")
    }
    plugins_parent = panel.find("property[@name='plugins']")
    require(plugins_parent is not None, "XFCE panel plugin configuration is missing")
    plugins = {
        int(prop.get("name", "plugin-0").removeprefix("plugin-")): prop
        for prop in plugins_parent.findall("property")
    }
    require(plugin_ids == set(plugins), "panel plugin IDs do not match configured plugins")
    expected_plugins = {
        "applicationsmenu", "tasklist", "pager", "systray", "pulseaudio",
        "power-manager-plugin", "clock", "actions", "launcher", "notification-plugin",
    }
    configured_plugins = {prop.get("value") for prop in plugins.values()}
    require(expected_plugins <= configured_plugins,
            "top panel is missing an app menu, workspace, status, or power control")
    require(plugins[1].find("property[@name='button-title']").get("value") == "ShreeOS",
            "top panel menu is not branded ShreeOS")
    panel_items = plugins[12].find("property[@name='items']")
    require(panel_items is not None and panel_items.find("value").get("value") == "shreeos-control-center.desktop",
            "top panel is missing the ShreeOS Control Center launcher")

    wm = parse_xml(SKEL / ".config/xfce4/xfconf/xfce-perchannel-xml/xfwm4.xml")
    button_layout = wm.find("./property[@name='general']/property[@name='button_layout']")
    require(button_layout is not None and button_layout.get("value") == "CMH|",
            "window controls are not left aligned")
    require(wm.find("./property[@name='general']/property[@name='workspace_count']").get("value") == "4",
            "four-workspace default is missing")

    appearance = configparser.ConfigParser()
    appearance.read(SKEL / ".config/gtk-3.0/settings.ini", encoding="utf-8")
    require(appearance.get("Settings", "gtk-theme-name") == "Arc-Dark",
            "dark ShreeOS GTK theme is not the default")
    require(appearance.get("Settings", "gtk-icon-theme-name") == "Papirus-Dark",
            "desktop icon theme is not configured")
    require(appearance.get("Settings", "gtk-font-name").startswith("Inter"),
            "Inter UI font is not configured")
    xsettings = parse_xml(SKEL / ".config/xfce4/xfconf/xfce-perchannel-xml/xsettings.xml")
    require(xsettings.find("./property[@name='Net']/property[@name='ThemeName']").get("value") == "Arc-Dark",
            "XFCE theme service will not apply Arc-Dark")
    require(xsettings.find("./property[@name='Net']/property[@name='IconThemeName']").get("value") == "Papirus-Dark",
            "XFCE theme service will not apply Papirus-Dark")

    dconf = configparser.ConfigParser()
    dconf.read(INCLUDES / "usr/share/shreeos/defaults/plank.dconf", encoding="utf-8")
    dock = dconf["net/launchpad/plank/docks/dock1"]
    require(dock.get("theme") == "'ShreeOS'", "ShreeOS dock theme is not selected")
    require((INCLUDES / "usr/share/plank/themes/ShreeOS-Light/dock.theme").is_file(),
            "light appearance does not have a matching ShreeOS dock palette")
    require(dock.getboolean("zoom-enabled"), "dock hover magnification is not enabled")
    require(dock.get("position") == "'bottom'" and dock.get("alignment") == "'center'",
            "dock is not centered at the bottom")
    require(dock.get("hide-mode") == "'none'",
            "ShreeOS dock should remain visible on the desktop")
    dock_autostart = configparser.ConfigParser(interpolation=None)
    dock_autostart.read(INCLUDES / "etc/xdg/autostart/shreeos-dock.desktop", encoding="utf-8")
    require(dock_autostart.get("Desktop Entry", "Exec", fallback="")
            == "/usr/local/bin/shreeos-dock-session",
            "XFCE does not start the ShreeOS dock with its ShreeOS configuration")
    dock_items = ast.literal_eval(dock["dock-items"])
    launcher_dir = SKEL / ".config/plank/launchers"
    require(set(dock_items) == {path.name for path in launcher_dir.glob("*.dockitem")},
            "Plank launchers do not match the configured dock items")
    require({"shreeos-search.dockitem", "shreeos-overview.dockitem",
             "shreeos-control-center.dockitem", "shreeos-store.dockitem"} <= set(dock_items),
            "the dock is missing a ShreeOS search, overview, software, or quick-controls launcher")
    known_debian_desktops = {
        "thunar.desktop", "firefox-esr.desktop", "xfce4-terminal.desktop",
        "org.xfce.ristretto.desktop", "org.xfce.mousepad.desktop",
        "xfce4-settings-manager.desktop",
    }
    for item in dock_items:
        launcher = configparser.ConfigParser()
        launcher.read(launcher_dir / item, encoding="utf-8")
        target = unquote(urlparse(launcher["PlankDockItemPreferences"]["Launcher"]).path)
        desktop_id = Path(target).name
        if desktop_id in known_debian_desktops:
            continue
        require((INCLUDES / target.lstrip("/")).is_file(),
                f"ShreeOS dock launcher target is missing: {target}")

    for desktop in INCLUDES.rglob("*.desktop"):
        entry = configparser.ConfigParser(interpolation=None)
        entry.read(desktop, encoding="utf-8")
        require(entry.has_section("Desktop Entry") and entry.has_option("Desktop Entry", "Exec"),
                f"invalid ShreeOS desktop entry: {desktop}")
        command = entry.get("Desktop Entry", "Exec").split()[0]
        if command.startswith("/usr/local/bin/shreeos-"):
            require((INCLUDES / command.lstrip("/")).is_file(),
                    f"ShreeOS desktop entry command is missing: {command}")

    store = INCLUDES / "usr/local/bin/shreeos-store"
    store_source = store.read_text(encoding="utf-8")
    require(store.is_file() and "apt-cache" in store_source
            and '"/usr/bin/apt-get"' in store_source and '"pkexec"' in store_source,
            "ShreeOS Software is not connected to the real APT package manager")
    store_icon = parse_xml(INCLUDES / "usr/share/icons/hicolor/scalable/apps/shreeos-store.svg")
    require("shreeos-store.desktop" in {path.name for path in (INCLUDES / "usr/share/applications").glob("*.desktop")}
            and store_icon.tag == "{http://www.w3.org/2000/svg}svg",
            "ShreeOS Software is missing its desktop launcher or original icon")

    builder = (ROOT / "scripts/build-debian-prototype.sh").read_text(encoding="utf-8")
    require('XFCE_DEFAULTS_TARGET="$BUILD_DIR/config/includes.chroot/etc/xdg/xfce4/xfconf/xfce-perchannel-xml"' in builder
            and 'cp "$XFCE_DEFAULTS_SOURCE"/*.xml "$XFCE_DEFAULTS_TARGET/"' in builder,
            "live image does not install ShreeOS XFCE defaults system-wide")
    session_setup = INCLUDES / "usr/local/bin/shreeos-session-setup"
    session_setup_source = session_setup.read_text(encoding="utf-8")
    require(session_setup.is_file() and "xfce4-panel --restart" not in session_setup_source
            and "xfce4-desktop" in session_setup_source and "xfdesktop --reload" in session_setup_source,
            "first login does not safely apply ShreeOS panel and wallpaper settings")
    require((INCLUDES / "etc/xdg/autostart/shreeos-session-setup.desktop").is_file(),
            "first-login ShreeOS desktop setup is not registered with XFCE")
    boot_check = (ROOT / "prototype/debian-live/config/includes.chroot/usr/local/sbin/shreeos-live-boot-check").read_text(encoding="utf-8")
    require("/home/shree/.config/shreeos/xfce-session-ready" in boot_check,
            "desktop boot acceptance does not wait for first-login ShreeOS setup")

    app_icon = INCLUDES / "usr/share/icons/hicolor/scalable/apps/shreeos-control-center.svg"
    parse_xml(app_icon)
    require((INCLUDES / "usr/share/applications/shreeos-control-center.desktop").is_file(),
            "ShreeOS Control Center application entry is missing")
    control_center = INCLUDES / "usr/local/bin/shreeos-control-center"
    require(control_center.is_file() and control_center.read_text().startswith("#!/usr/bin/python3"),
            "ShreeOS Control Center executable is missing")
    controls_source = control_center.read_text(encoding="utf-8")
    require('"brightnessctl", "set"' in controls_source and '"Focus mode"' in controls_source,
            "Control Center is missing hardware brightness or notification focus controls")
    require('"About ShreeOS"' in controls_source
            and (INCLUDES / "usr/local/bin/shreeos-about").is_file(),
            "Control Center is missing the ShreeOS release information page")
    release_info = configparser.ConfigParser(interpolation=None)
    release_path = ROOT / "prototype/debian-live/config/includes.chroot/etc/os-release"
    release_info.read_string("[os]\n" + release_path.read_text(encoding="utf-8"))
    require(release_info["os"].get("ID") == "shreeos"
            and release_info["os"].get("ID_LIKE") == "debian"
            and "ShreeOS" in release_info["os"].get("PRETTY_NAME", "")
            and "Debian" in release_info["os"].get("PRETTY_NAME", ""),
            "prototype OS release metadata does not identify ShreeOS and its Debian base")
    require("def battery_status()" in controls_source
            and 'Path("/sys/class/power_supply")' in controls_source,
            "Control Center does not display battery state on supported laptops")
    require('["plank", "--preferences"]' in controls_source,
            "Control Center is missing the dock preferences entry")
    for appearance_contract in (
            '"/general/theme", "-s", theme',
            '"/Gtk/PreferDarkTheme"',
            '"-l"]).splitlines()',
            'item.startswith("/backdrop/") and item.endswith("/last-image")',
            '"ShreeOS-Light"'):
        require(appearance_contract in controls_source,
                f"appearance toggle does not update {appearance_contract}")
    search_script = INCLUDES / "usr/local/bin/shreeos-search"
    require(search_script.is_file() and search_script.read_text().startswith("#!/usr/bin/python3"),
            "Shree Search executable is missing")
    require((INCLUDES / "usr/share/applications/shreeos-search.desktop").is_file(),
            "Shree Search application entry is missing")
    shortcuts = parse_xml(SKEL / ".config/xfce4/xfconf/xfce-perchannel-xml/xfce4-keyboard-shortcuts.xml")
    search_shortcut = shortcuts.find("./property/property/property[@name='<Super>space']")
    require(search_shortcut is not None and search_shortcut.get("value") == "/usr/local/bin/shreeos-search",
            "Super+Space is not bound to Shree Search")
    screenshot_shortcut = shortcuts.find("./property/property/property[@name='<Super><Shift>s']")
    require(screenshot_shortcut is not None
            and screenshot_shortcut.get("value") == "xfce4-screenshooter -r",
            "Super+Shift+S is not bound to the screenshot region tool")
    require(shortcuts.find("./property/property/property[@name='<Super>l']") is None,
            "a password-locked live account must not expose an unusable lock shortcut")
    overview_shortcut = shortcuts.find("./property/property/property[@name='<Super>Up']")
    require(overview_shortcut is not None and overview_shortcut.get("value") == "/usr/local/bin/shreeos-overview",
            "Super+Up is not bound to Workspace Overview")
    workspace_shortcuts = shortcuts.find("./property[@name='xfwm4']/property[@name='custom']")
    require(workspace_shortcuts is not None, "XFWM workspace keyboard controls are missing")
    shortcut_map = {item.get("name"): item.get("value")
                    for item in workspace_shortcuts.findall("property")}
    require(shortcut_map.get("<Primary><Alt>Left") == "left_workspace_key"
            and shortcut_map.get("<Primary><Alt>Right") == "right_workspace_key",
            "keyboard workspace switching is not configured")
    require(all(shortcut_map.get(f"<Super>{number}") == f"workspace_{number}_key"
                for number in range(1, 5)),
            "direct shortcuts for all four workspaces are missing")
    overview_script = INCLUDES / "usr/local/bin/shreeos-overview"
    require(overview_script.is_file() and overview_script.read_text().startswith("#!/usr/bin/python3"),
            "Workspace Overview executable is missing")
    require((INCLUDES / "usr/share/applications/shreeos-overview.desktop").is_file(),
            "Workspace Overview application entry is missing")
    control_center = (INCLUDES / "usr/local/bin/shreeos-control-center").read_text(encoding="utf-8")
    require("from gi.repository import Gdk, GLib, Gtk" in control_center,
            "Control Center brightness slider is missing its GLib runtime")
    require('"Airplane mode"' in control_center and "change_airplane_mode" in control_center,
            "Control Center is missing the airplane mode radio toggle")
    bookmarks = (SKEL / ".config/gtk-3.0/bookmarks").read_text(encoding="utf-8").splitlines()
    for favorite in ("Desktop", "Documents", "Downloads", "Pictures", "Music", "Videos"):
        require(any(line.endswith(f" {favorite}") for line in bookmarks),
                f"Thunar Places sidebar is missing {favorite}")
    for location in ("computer:///", "network:///", "trash:///"):
        require(any(line.startswith(location) for line in bookmarks),
                f"Thunar Places sidebar is missing {location}")

    for wallpaper in (ROOT / "branding/wallpapers").glob("*.svg"):
        parse_xml(wallpaper)
    require((ROOT / "branding/wallpapers/shreeos-calm-dark.svg").is_file(),
            "dark wallpaper is missing from the source artwork")
    require((ROOT / "branding/wallpapers/shreeos-calm-light.svg").is_file(),
            "light wallpaper is missing from the source artwork")
    lightdm = (INCLUDES / "etc/lightdm/lightdm-gtk-greeter.conf.d/50-shreeos.conf").read_text()
    require("theme-name=Arc-Dark" in lightdm and "logo=/usr/share/pixmaps/shreeos-logo.svg" in lightdm,
            "login screen does not use ShreeOS theme and logo")
    require("/usr/share/backgrounds/shreeos/shreeos-calm-dark.svg" in lightdm,
            "login screen does not use original ShreeOS wallpaper")
    builder = (ROOT / "scripts/build-debian-prototype.sh").read_text()
    require('branding/wallpapers/*.svg' in builder,
            "build must package the original dark and light wallpaper set")
    print("ShreeOS desktop configuration contract passed.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
