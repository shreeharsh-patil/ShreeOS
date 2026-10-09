#!/usr/bin/env python3
"""Check source and exported ShreeOS branding assets without desktop libraries."""

from pathlib import Path
import struct
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[2]
LOGO = ROOT / "branding" / "logo"
ICONS = ROOT / "branding" / "icons"
PNG = LOGO / "png"

variants = (
    "shreeos-logo.svg",
    "shreeos-logo-black.svg",
    "shreeos-logo-white.svg",
    "shreeos-logo-adaptive.svg",
)
for name in variants:
    tree = ET.parse(LOGO / name)
    root = tree.getroot()
    assert root.attrib.get("viewBox") == "0 0 256 256", f"{name} has an unexpected viewBox"
    text = (LOGO / name).read_text(encoding="utf-8")
    assert "S ligature" not in text and "M 82 88 C 82 72" not in text, f"{name} still contains the old letterform"
    assert "M52 144a76 76 0 0 1 152 0z" in text, f"{name} does not use the sunrise emblem"

for name in ("shreeos-app.svg", "installer.svg"):
    root = ET.parse(ICONS / name).getroot()
    assert root.attrib.get("viewBox") == "0 0 128 128", f"{name} has an unexpected viewBox"

expected = {
    *(f"shreeos-logo-{size}.png" for size in (16, 32, 64, 128, 256, 512)),
    *(f"shreeos-logo-black-{size}.png" for size in (16, 32, 64, 128, 256, 512)),
    *(f"shreeos-logo-white-{size}.png" for size in (16, 32, 64, 128, 256, 512)),
    *(f"shreeos-app-{size}.png" for size in (128, 256, 512)),
    *(f"shreeos-installer-{size}.png" for size in (128, 256, 512)),
}
for name in expected:
    data = (PNG / name).read_bytes()
    assert data[:8] == b"\x89PNG\r\n\x1a\n", f"{name} is not a PNG"
    width, height, depth, color_type = struct.unpack(">IIBB", data[16:26])
    wanted = int(name.rsplit("-", 1)[1].split(".")[0])
    assert (width, height) == (wanted, wanted), f"{name} has wrong dimensions"
    assert depth == 8 and color_type == 6, f"{name} must be 8-bit RGBA with alpha"

print(f"ShreeOS branding assets passed ({len(variants)} vectors, {len(expected)} PNG exports).")
