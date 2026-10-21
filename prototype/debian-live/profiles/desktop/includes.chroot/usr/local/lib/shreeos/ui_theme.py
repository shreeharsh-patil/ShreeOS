"""Shared ShreeOS GTK palette helpers.

The token file is a simple shell-assignment file, but values are parsed as
literals instead of being executed. UI colors follow the selected XFCE
appearance when available and fall back to the packaged token default.
"""

from __future__ import annotations

import ast
import re
import subprocess
from pathlib import Path


TOKEN_FILE = Path("/etc/shreeos/tokens.conf")

DEFAULTS = {
    "SHREE_THEME_MODE": "dark",
    "SHREE_DARK_DESKTOP_BG": "#19191B",
    "SHREE_DARK_SURFACE_PRIMARY": "#252527",
    "SHREE_DARK_SURFACE_SECONDARY": "#1E1E20",
    "SHREE_DARK_TEXT_PRIMARY": "#F5F5F7",
    "SHREE_DARK_TEXT_SECONDARY": "#A1A1A6",
    "SHREE_DARK_TEXT_MUTED": "#86868B",
    "SHREE_DARK_BORDER": "rgba(255,255,255,0.12)",
    "SHREE_DARK_BORDER_HEX": "#38383A",
    "SHREE_LIGHT_DESKTOP_BG": "#F4EFE9",
    "SHREE_LIGHT_SURFACE_PRIMARY": "#FFFDFA",
    "SHREE_LIGHT_SURFACE_SECONDARY": "#F6F1EC",
    "SHREE_LIGHT_TEXT_PRIMARY": "#1D1D1F",
    "SHREE_LIGHT_TEXT_SECONDARY": "#6E6E73",
    "SHREE_LIGHT_TEXT_MUTED": "#86868B",
    "SHREE_LIGHT_BORDER": "rgba(45,39,34,0.10)",
    "SHREE_LIGHT_BORDER_HEX": "#E5E5EA",
    "SHREE_ACCENT": "#2878FF",
    "SHREE_ACCENT_LIGHT": "#5E9BFF",
    "SHREE_ACCENT_HOVER": "#1A62E8",
    "SHREE_ACCENT_MUTED": "rgba(40,120,255,0.18)",
    "SHREE_RADIUS_WINDOW": "12",
    "SHREE_RADIUS_CONTROL": "9",
    "SHREE_RADIUS_MENU": "12",
    "SHREE_FONT_UI": "Inter",
    "SHREE_FONT_SIZE_TITLE": "20",
    "SHREE_FONT_SIZE_SECTION": "16",
    "SHREE_FONT_SIZE_UI": "13",
    "SHREE_FONT_SIZE_SM": "11",
}


def tokens() -> dict[str, str]:
    values = DEFAULTS.copy()
    try:
        lines = TOKEN_FILE.read_text(encoding="utf-8").splitlines()
    except OSError:
        return values

    for line in lines:
        match = re.fullmatch(r"\s*(SHREE_[A-Z0-9_]+)\s*=\s*(.*?)\s*", line)
        if not match or match.group(1) not in values:
            continue
        raw = match.group(2)
        try:
            value = ast.literal_eval(raw)
        except (SyntaxError, ValueError):
            continue
        if isinstance(value, str):
            values[match.group(1)] = value
    return values


def current_dark() -> bool:
    """Read XFCE's selected GTK theme; use the shipped mode if unavailable."""
    try:
        result = subprocess.run(
            ["xfconf-query", "-c", "xsettings", "-p", "/Net/ThemeName"],
            capture_output=True, text=True, timeout=2, check=False,
        )
        if result.returncode == 0 and result.stdout.strip():
            return result.stdout.strip().lower().endswith("-dark")
    except (OSError, subprocess.TimeoutExpired):
        pass
    return tokens()["SHREE_THEME_MODE"].strip().lower() != "light"


def palette(dark: bool | None = None) -> dict[str, str]:
    values = tokens()
    dark = current_dark() if dark is None else dark
    prefix = "SHREE_DARK_" if dark else "SHREE_LIGHT_"
    return {
        "bg": values[prefix + "DESKTOP_BG"],
        "surface": values[prefix + "SURFACE_PRIMARY"],
        "surface_alt": values[prefix + "SURFACE_SECONDARY"],
        "text": values[prefix + "TEXT_PRIMARY"],
        "text_secondary": values[prefix + "TEXT_SECONDARY"],
        "text_muted": values[prefix + "TEXT_MUTED"],
        "border": values[prefix + "BORDER"],
        "border_hex": values[prefix + "BORDER_HEX"],
        "accent": values["SHREE_ACCENT"],
        "accent_light": values["SHREE_ACCENT_LIGHT"],
        "accent_hover": values["SHREE_ACCENT_HOVER"],
        "accent_muted": values["SHREE_ACCENT_MUTED"],
        "radius_window": values["SHREE_RADIUS_WINDOW"] + "px",
        "radius_control": values["SHREE_RADIUS_CONTROL"] + "px",
        "radius_menu": values["SHREE_RADIUS_MENU"] + "px",
        "font_ui": values["SHREE_FONT_UI"],
        "font_size_title": values["SHREE_FONT_SIZE_TITLE"] + "px",
        "font_size_section": values["SHREE_FONT_SIZE_SECTION"] + "px",
        "font_size_ui": values["SHREE_FONT_SIZE_UI"] + "px",
        "font_size_sm": values["SHREE_FONT_SIZE_SM"] + "px",
    }


def themed_css(template: str, dark: bool | None = None) -> str:
    result = template
    for key, value in palette(dark).items():
        result = result.replace(f"@{key}@", value)
    return result
