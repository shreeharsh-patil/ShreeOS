#!/usr/bin/env python3
"""Verify checked-in PNG exports against the generated RGBA pixels."""

from pathlib import Path
import subprocess
import sys
import tempfile

from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
EXPORTER = Path(__file__).with_name("export-logo-pngs.py")
COMMITTED = ROOT / "branding" / "logo" / "png"


def main():
    with tempfile.TemporaryDirectory(prefix="shreeos-logo-png-") as temporary:
        generated = Path(temporary)
        subprocess.run(
            [sys.executable, str(EXPORTER), "--output-dir", str(generated)],
            check=True,
        )
        expected = {path.name for path in COMMITTED.glob("*.png")}
        actual = {path.name for path in generated.glob("*.png")}
        if actual != expected:
            raise SystemExit(
                f"PNG export set differs: missing={sorted(expected - actual)}, "
                f"unexpected={sorted(actual - expected)}"
            )

        for name in sorted(expected):
            with Image.open(COMMITTED / name) as committed_image:
                committed = committed_image.convert("RGBA")
            with Image.open(generated / name) as generated_image:
                rendered = generated_image.convert("RGBA")
            if committed.size != rendered.size or committed.tobytes() != rendered.tobytes():
                raise SystemExit(f"{name} differs from its generated RGBA pixels")

    print(f"ShreeOS PNG exports match the generated pixels ({len(expected)} files).")


if __name__ == "__main__":
    main()
