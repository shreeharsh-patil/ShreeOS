#!/usr/bin/env python3
"""Check that the ShreeOS design-token mirrors do not drift apart.

The same palette is published three times: `branding/theme/tokens.conf` for
shell scripts and window managers, `branding/theme/tokens.css` for web content,
and `prototype/.../shreeos/ui_theme.py` for the desktop theme writer. A value
changed in one file and not the others renders the shell UI and the desktop UI
with different colours, so the mirrors are compared here.
"""
from __future__ import annotations

import re
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
TOKENS_CONF = ROOT / "branding/theme/tokens.conf"
TOKENS_CSS = ROOT / "branding/theme/tokens.css"
UI_THEME = ROOT / ("prototype/debian-live/profiles/desktop/includes.chroot/usr/local"
                   "/lib/shreeos/ui_theme.py")


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit(f"FAIL: {message}")


def parse_conf(path: Path) -> dict[str, str]:
    text = path.read_text(encoding="utf-8")
    return dict(re.findall(r'^(SHREE_[A-Z0-9_]+)="([^"]*)"', text, re.MULTILINE))


def parse_css_block(text: str, selector: str) -> dict[str, str]:
    # The light rule is written as `[data-theme="light"], :root { ... }`.
    match = re.search(re.escape(selector) + r"[^{}]*\{(.*?)\n\}", text, re.DOTALL)
    if not match:
        return {}
    return dict(re.findall(r"^\s*(--shree-[a-z0-9-]+):\s*([^;]+);", match.group(1),
                            re.MULTILINE))


def parse_ui_theme(path: Path) -> dict[str, str]:
    text = path.read_text(encoding="utf-8")
    return dict(re.findall(r'"(SHREE_[A-Z0-9_]+)":\s*"([^"]*)"', text))


def normalise(value: str) -> str:
    return value.strip().rstrip(";").strip().replace(", ", ",").replace("px", "")


def as_rgba(value: str) -> tuple[float, ...] | None:
    match = re.match(r"rgba?\(([^)]+)\)", value.strip())
    if not match:
        return None
    channels = [float(part) if "." in part else int(part)
                for part in (item.strip() for item in match.group(1).split(","))]
    while len(channels) < 4:
        channels.append(1.0)
    return tuple(channels)


def same_value(left: str, right: str) -> bool:
    if normalise(left) == normalise(right):
        return True
    left_rgba, right_rgba = as_rgba(left), as_rgba(right)
    return bool(left_rgba and right_rgba and left_rgba == right_rgba)


# The token name in tokens.conf and the CSS custom property that carries it.
COMMON_TOKENS = (
    ("SHREE_ACCENT", "--shree-accent"),
    ("SHREE_ACCENT_LIGHT", "--shree-accent-light"),
    ("SHREE_ACCENT_HOVER", "--shree-accent-hover"),
    ("SHREE_SUCCESS", "--shree-success"),
    ("SHREE_WARNING", "--shree-warning"),
    ("SHREE_ERROR", "--shree-error"),
    ("SHREE_RADIUS_WINDOW", "--shree-radius-window"),
    ("SHREE_RADIUS_CONTROL", "--shree-radius-control"),
    ("SHREE_RADIUS_DOCK", "--shree-radius-dock"),
    ("SHREE_RADIUS_MENU", "--shree-radius-menu"),
    ("SHREE_GLASS_OPACITY_CLEAR", "--shree-glass-opacity-clear"),
    ("SHREE_GLASS_OPACITY_TINTED", "--shree-glass-opacity-tinted"),
    ("SHREE_GLASS_BLUR", "--shree-glass-blur"),
    ("SHREE_GLASS_SATURATION", "--shree-glass-saturation"),
)
THEME_TOKENS = (
    ("DESKTOP_BG", "--shree-bg"),
    ("SURFACE_PRIMARY", "--shree-surface"),
    ("SURFACE_SECONDARY", "--shree-surface-secondary"),
    ("TEXT_PRIMARY", "--shree-text-primary"),
    ("TEXT_SECONDARY", "--shree-text-secondary"),
    ("TEXT_MUTED", "--shree-text-muted"),
    ("BORDER", "--shree-border"),
)


def main() -> int:
    conf = parse_conf(TOKENS_CONF)
    css_text = TOKENS_CSS.read_text(encoding="utf-8")
    ui_theme = parse_ui_theme(UI_THEME)
    require(conf, "branding/theme/tokens.conf declares no tokens")
    require(ui_theme, "the desktop theme writer declares no tokens")

    root = parse_css_block(css_text, ":root")
    light = parse_css_block(css_text, '[data-theme="light"]')
    dark = parse_css_block(css_text, '[data-theme="dark"]')

    for conf_key, css_key in COMMON_TOKENS:
        require(conf_key in conf, f"tokens.conf is missing {conf_key}")
        require(css_key in root, f"tokens.css is missing {css_key}")
        require(same_value(conf[conf_key], root[css_key]),
                f"{conf_key} and {css_key} disagree: "
                f"{conf[conf_key]!r} != {root[css_key]!r}")

    for theme, block in (("LIGHT", light), ("DARK", dark)):
        for suffix, css_key in THEME_TOKENS:
            conf_key = f"SHREE_{theme}_{suffix}"
            require(conf_key in conf, f"tokens.conf is missing {conf_key}")
            require(css_key in block, f"tokens.css is missing {css_key} for {theme}")
            require(same_value(conf[conf_key], block[css_key]),
                    f"{conf_key} and {css_key} disagree: "
                    f"{conf[conf_key]!r} != {block[css_key]!r}")

    for key in sorted(set(conf) & set(ui_theme)):
        require(same_value(conf[key], ui_theme[key]),
                f"tokens.conf and the desktop theme writer disagree on {key}: "
                f"{conf[key]!r} != {ui_theme[key]!r}")

    print(f"OK: {len(conf)} design tokens agree across tokens.conf, tokens.css "
          f"and the desktop theme writer.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
