#!/usr/bin/env python3
"""Keep unified ISO PR and master triggers aligned with image inputs."""

from pathlib import Path

import yaml


ROOT = Path(__file__).resolve().parents[2]
WORKFLOW = ROOT / ".github/workflows/unified-iso.yml"

REQUIRED_PATHS = {
    ".github/workflows/unified-iso.yml",
    "Makefile",
    "VERSION",
    "build.conf",
    "LICENSE",
    "docs/**",
    "release/INSTALL-ACCEPTANCE.md",
    "scripts/**",
    "desktop/**",
    "hardware/**",
    "pkgmanager/**",
    "prototype/debian-live/**",
    "branding/**",
    "themes/plasma/**",
    "tests/**",
}


def main() -> None:
    workflow = yaml.load(WORKFLOW.read_text(encoding="utf-8"), Loader=yaml.BaseLoader)
    triggers = workflow["on"]
    pull_request_paths = set(triggers["pull_request"]["paths"])
    push_paths = set(triggers["push"]["paths"])
    if pull_request_paths != push_paths:
        raise SystemExit(
            "Unified ISO pull_request and master push path filters differ: "
            f"PR-only={sorted(pull_request_paths - push_paths)}, "
            f"push-only={sorted(push_paths - pull_request_paths)}"
        )
    missing = sorted(REQUIRED_PATHS - pull_request_paths)
    if missing:
        raise SystemExit(f"Unified ISO path filters omit image inputs: {missing}")
    print(f"Unified ISO triggers cover {len(REQUIRED_PATHS)} required path patterns consistently.")


if __name__ == "__main__":
    main()
