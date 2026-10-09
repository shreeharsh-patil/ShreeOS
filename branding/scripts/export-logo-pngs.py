#!/usr/bin/env python3
"""Render the ShreeOS sunrise mark to transparent PNG exports using Pillow."""

from __future__ import annotations

from math import cos, pi, sin
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[2]
OUTPUT = ROOT / "branding" / "logo" / "png"
SCALE = 4


def cubic(start, control1, control2, end, count=64):
    points = []
    for step in range(1, count + 1):
        t = step / count
        u = 1 - t
        points.append((
            u**3 * start[0] + 3 * u**2 * t * control1[0]
            + 3 * u * t**2 * control2[0] + t**3 * end[0],
            u**3 * start[1] + 3 * u**2 * t * control1[1]
            + 3 * u * t**2 * control2[1] + t**3 * end[1],
        ))
    return points


def raster_mark(size: int, color: tuple[int, int, int, int], accent=None):
    canvas_size = size * SCALE
    rgba = Image.new("RGBA", (canvas_size, canvas_size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(rgba)

    def point(x, y):
        return (round(x * canvas_size / 256), round(y * canvas_size / 256))

    sun = [point(128 + 76 * cos(angle), 144 - 76 * sin(angle))
           for angle in (pi * step / 64 for step in range(65))]
    draw.polygon(sun, fill=accent or color)
    waves = (
        ((28, 150), (((64, 137), (96, 137), (128, 150)),
                     ((160, 163), (191, 163), (228, 149))), 17),
        ((50, 191), (((78, 181), (102, 181), (128, 190)),
                     ((154, 199), (178, 199), (206, 191))), 15),
    )
    for start, segments, width in waves:
        curve = [start]
        for c1, c2, end in segments:
            curve.extend(cubic(start, c1, c2, end))
            start = end
        coords = [point(x, y) for x, y in curve]
        line_width = max(1, round(width * canvas_size / 256))
        draw.line(coords, fill=color, width=line_width, joint="curve")
        cap = line_width // 2
        for x, y in (coords[0], coords[-1]):
            draw.ellipse((x - cap, y - cap, x + cap, y + cap), fill=color)
    return rgba.resize((size, size), Image.Resampling.LANCZOS)


def save_mark(stem: str, size: int, color, accent=None):
    raster_mark(size, color, accent).save(OUTPUT / f"{stem}-{size}.png", optimize=True)


def save_tile(stem: str, size: int, installer=False):
    image = Image.new("RGBA", (size * SCALE, size * SCALE), (0, 0, 0, 0))
    draw = ImageDraw.Draw(image)
    edge = round(size * SCALE * 0.03125)
    radius = round(size * SCALE * 0.2265625)
    draw.rounded_rectangle((edge, edge, size * SCALE - edge, size * SCALE - edge),
                           radius=radius, fill="#181c25")
    mark = raster_mark(size, (245, 247, 251, 255), (79, 145, 255, 255))
    mark = mark.resize((round(mark.width * SCALE), round(mark.height * SCALE)), Image.Resampling.LANCZOS)
    image.alpha_composite(mark, ((image.width - mark.width) // 2, (image.height - mark.height) // 2))
    if installer:
        overlay_size = round(size * SCALE * 0.34)
        overlay_x = image.width - overlay_size - round(size * SCALE * 0.035)
        overlay_y = image.height - overlay_size - round(size * SCALE * 0.035)
        draw = ImageDraw.Draw(image)
        draw.ellipse((overlay_x, overlay_y, overlay_x + overlay_size, overlay_y + overlay_size),
                     fill="#2878ff", outline="#181c25", width=max(1, round(size * SCALE * 0.03)))
        mid = overlay_x + overlay_size // 2
        top = overlay_y + overlay_size // 4
        bottom = overlay_y + overlay_size * 3 // 4
        stroke = max(1, round(size * SCALE * 0.035))
        draw.line((mid, top, mid, bottom), fill="white", width=stroke)
        draw.line((mid - overlay_size // 5, bottom - overlay_size // 5, mid, bottom), fill="white", width=stroke)
        draw.line((mid, bottom, mid + overlay_size // 5, bottom - overlay_size // 5), fill="white", width=stroke)
    image.resize((size, size), Image.Resampling.LANCZOS).save(OUTPUT / f"{stem}-{size}.png", optimize=True)


def main():
    OUTPUT.mkdir(parents=True, exist_ok=True)
    transparent = (255, 255, 255, 255)
    for size in (16, 32, 64, 128, 256, 512):
        save_mark("shreeos-logo", size, transparent, (79, 145, 255, 255))
        save_mark("shreeos-logo-black", size, (17, 19, 24, 255))
        save_mark("shreeos-logo-white", size, (255, 255, 255, 255))
    for size in (128, 256, 512):
        save_tile("shreeos-app", size)
        save_tile("shreeos-installer", size, installer=True)
    print(f"Exported transparent ShreeOS logo PNGs to {OUTPUT}")


if __name__ == "__main__":
    main()
