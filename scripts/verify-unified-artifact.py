#!/usr/bin/env python3
"""Verify a ShreeOS unified ISO and all metadata sidecars before cache reuse."""

from __future__ import annotations

import hashlib
import json
import re
import sys
from pathlib import Path

MAX_ISO_SIZE_BYTES = 1_900_000_000


def verify_image_size(size_bytes: int) -> None:
    if size_bytes >= MAX_ISO_SIZE_BYTES:
        raise ValueError(
            f"ISO is {size_bytes} bytes; the release cap is strictly below "
            f"{MAX_ISO_SIZE_BYTES} bytes"
        )


def read_key_values(path: Path) -> dict[str, str]:
    values: dict[str, str] = {}
    for line_number, raw_line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        if not raw_line or raw_line.startswith("#"):
            continue
        key, separator, value = raw_line.partition("=")
        if not separator or not key or key in values:
            raise ValueError(f"invalid or duplicate key in {path.name}:{line_number}")
        values[key] = value
    return values


def verify_bundle(
    iso_path: Path,
    checksum_path: Path,
    packages_path: Path,
    build_info_path: Path,
    manifest_path: Path,
    *,
    version: str,
    profile: str,
    architecture: str,
    suite: str,
    snapshot: str,
    live_build: str,
    expected_commit: str | None = None,
) -> None:
    for path in (iso_path, checksum_path, packages_path, build_info_path, manifest_path):
        if not path.is_file() or path.stat().st_size == 0:
            raise ValueError(f"missing or empty artifact input: {path}")

    checksum_lines = checksum_path.read_text(encoding="ascii").splitlines()
    if len(checksum_lines) != 1:
        raise ValueError("checksum sidecar must contain exactly one entry")
    checksum_match = re.fullmatch(r"([0-9a-fA-F]{64}) (?: |\*)(.+)", checksum_lines[0])
    if not checksum_match or checksum_match.group(2) != iso_path.name:
        raise ValueError("checksum sidecar does not name the ISO")

    size_bytes = iso_path.stat().st_size
    verify_image_size(size_bytes)
    with iso_path.open("rb") as stream:
        digest = hashlib.file_digest(stream, "sha256").hexdigest()
    if checksum_match.group(1).lower() != digest:
        raise ValueError("ISO bytes do not match the checksum sidecar")

    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    if not isinstance(manifest, dict):
        raise ValueError("manifest root must be a JSON object")
    expected_manifest = {
        "name": "ShreeOS",
        "version": version,
        "profile": profile,
        "architecture": architecture,
        "base_distribution": suite,
        "base_snapshot": snapshot,
        "live_build": live_build,
        "iso": iso_path.name,
        "sha256": digest,
        "size_bytes": size_bytes,
    }
    for key, expected in expected_manifest.items():
        if manifest.get(key) != expected:
            raise ValueError(f"manifest field {key!r} does not match the artifact inputs")
    if not re.fullmatch(r"[0-9a-f]{40}", manifest.get("commit", "")):
        raise ValueError("manifest has no valid source commit")
    if expected_commit and manifest["commit"] != expected_commit:
        raise ValueError("manifest source commit does not match the current source commit")
    if not isinstance(manifest.get("git_dirty"), bool):
        raise ValueError("manifest git_dirty field must be boolean")

    required_packages = {
        "linux-image-amd64": "kernel",
        "plasma-workspace": "plasma",
        "kwin-x11": "kwin",
        "sddm": "sddm",
        "shreeos-tools": "shreeos_tools",
        "shreeos-native-tools": "shreeos_native_tools",
    }
    package_versions: dict[str, str] = {}
    for line_number, raw_line in enumerate(packages_path.read_text(encoding="utf-8").splitlines(), 1):
        fields = raw_line.split()
        if not fields:
            continue
        if len(fields) < 2:
            raise ValueError(f"invalid package manifest entry at line {line_number}")
        package_versions[fields[0]] = fields[1]
    if not package_versions:
        raise ValueError("package manifest contains no packages")

    components = manifest.get("components")
    if not isinstance(components, dict):
        raise ValueError("manifest components field must be an object")
    for package, component in required_packages.items():
        package_version = package_versions.get(package)
        if not package_version:
            raise ValueError(f"package manifest is missing required package {package}")
        if components.get(component) != package_version:
            raise ValueError(f"manifest component {component!r} disagrees with the package manifest")

    build_info = read_key_values(build_info_path)
    expected_build_info = {
        "version": version,
        "artifact": iso_path.name,
        "profile": profile,
        "architecture": architecture,
        "debian_suite": suite,
        "debian_snapshot": snapshot,
        "live_build": live_build,
        "apt_recommends": "false",
        "git_commit": manifest["commit"],
        "git_dirty": "1" if manifest["git_dirty"] else "0",
        "sha256": digest,
        "size_bytes": str(size_bytes),
    }
    expected_build_info.update(
        {component: package_versions[package] for package, component in required_packages.items()}
    )
    for key, expected in expected_build_info.items():
        if build_info.get(key) != expected:
            raise ValueError(f"build-info field {key!r} does not match the artifact bundle")


def main(argv: list[str]) -> int:
    if len(argv) not in {12, 13}:
        print(
            "Usage: verify-unified-artifact.py ISO CHECKSUM PACKAGES BUILD_INFO MANIFEST "
            "VERSION PROFILE ARCH SUITE SNAPSHOT LIVE_BUILD [EXPECTED_COMMIT]",
            file=sys.stderr,
        )
        return 2
    (
        iso,
        checksum,
        packages,
        build_info,
        manifest,
        version,
        profile,
        architecture,
        suite,
        snapshot,
        live_build,
    ) = argv[1:12]
    try:
        verify_bundle(
            Path(iso),
            Path(checksum),
            Path(packages),
            Path(build_info),
            Path(manifest),
            version=version,
            profile=profile,
            architecture=architecture,
            suite=suite,
            snapshot=snapshot,
            live_build=live_build,
            expected_commit=argv[12] if len(argv) == 13 else None,
        )
    except (OSError, UnicodeError, json.JSONDecodeError, ValueError) as error:
        print(f"Unified artifact cache verification failed: {error}", file=sys.stderr)
        return 1
    print(f"Unified artifact bundle verified: {Path(iso).name}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
