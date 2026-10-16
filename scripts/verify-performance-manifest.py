#!/usr/bin/env python3
"""Validate that a measured ISO has clean, byte-matched build provenance."""

import hashlib
import json
from pathlib import Path
import re
import sys


def main(arguments):
    if len(arguments) != 2:
        print("Usage: verify-performance-manifest.py MANIFEST.json IMAGE.iso", file=sys.stderr)
        return 2

    manifest_path, iso_path = map(Path, arguments)
    try:
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
        iso_size = iso_path.stat().st_size
        with iso_path.open("rb") as stream:
            iso_sha256 = hashlib.file_digest(stream, "sha256").hexdigest()
    except (OSError, json.JSONDecodeError) as error:
        print(f"Could not read image provenance: {error}", file=sys.stderr)
        return 1

    commit = manifest.get("commit", "")
    if not re.fullmatch(r"[0-9a-f]{40}", commit):
        print("Image manifest has no valid source commit", file=sys.stderr)
        return 1
    if manifest.get("git_dirty") is not False:
        print("Performance measurements require an ISO built from a clean source commit", file=sys.stderr)
        return 1
    if manifest.get("sha256") != iso_sha256:
        print("Image manifest SHA256 does not match the ISO being measured", file=sys.stderr)
        return 1
    size_bytes = manifest.get("size_bytes")
    if isinstance(size_bytes, bool) or not isinstance(size_bytes, int) or size_bytes != iso_size:
        print("Image manifest size does not match the ISO being measured", file=sys.stderr)
        return 1

    print(commit)
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
