#!/usr/bin/env python3
"""Inspect and retain the exact Debian packages installed into the unified ISO."""

from __future__ import annotations

import argparse
import hashlib
import io
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tarfile
from typing import Any


def run(arguments: list[str]) -> bytes:
    result = subprocess.run(arguments, check=False, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    if result.returncode != 0:
        detail = result.stderr.decode("utf-8", errors="replace").strip()
        raise RuntimeError(f"{' '.join(arguments)} failed: {detail}")
    return result.stdout


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def parse_control(raw: bytes, package_path: Path) -> dict[str, str]:
    fields: dict[str, str] = {}
    current_key: str | None = None
    for line in raw.decode("utf-8", errors="strict").splitlines():
        if line.startswith((" ", "\t")):
            if current_key is None:
                raise ValueError(f"{package_path.name} has a detached control continuation")
            fields[current_key] += "\n" + line[1:]
            continue
        key, separator, value = line.partition(":")
        if not separator or not key or key in fields:
            raise ValueError(f"{package_path.name} has malformed or duplicate control fields")
        fields[key] = value.strip()
        current_key = key
    return fields


def normalize_member_path(name: str) -> str:
    while name.startswith("./"):
        name = name[2:]
    return name.rstrip("/")


def classify_tar_member(member: tarfile.TarInfo, package_path: Path, member_path: str) -> str:
    if member.isdir():
        return "directory"
    if member.issym():
        return "symlink"
    if member.islnk():
        return "hardlink"
    if member.isfile():
        return "file"
    raise ValueError(
        f"{package_path.name}:{member_path} has unsupported archive entry type {member.type!r}"
    )


def inspect_package(path: Path, output: Path, expected: dict[str, Any], version: str) -> dict[str, Any]:
    if not path.is_file() or path.stat().st_size == 0:
        raise ValueError(f"Missing Debian package: {path}")
    fields = parse_control(run(["dpkg-deb", "--field", str(path)]), path)
    for field, value in {
        "Package": expected["name"],
        "Version": version,
        "Architecture": expected["architecture"],
    }.items():
        if fields.get(field) != value:
            raise ValueError(f"{path.name} has {field}={fields.get(field)!r}; expected {value!r}")

    depends = fields.get("Depends", "")
    for dependency in expected["dependencies"]:
        pattern = rf"(?:^|,)\s*{re.escape(dependency)}(?:\s|,|\(|$)"
        if re.search(pattern, depends) is None:
            raise ValueError(f"{path.name} is missing required dependency {dependency!r}")
    if expected.get("exact_dependency"):
        dependency = f"shreeos-tools (= {version})"
        if dependency not in depends:
            raise ValueError(f"{path.name} must depend on {dependency!r}")

    tar_bytes = run(["dpkg-deb", "--fsys-tarfile", str(path)])
    entries: list[dict[str, Any]] = []
    with tarfile.open(fileobj=io.BytesIO(tar_bytes), mode="r:") as archive:
        for member in archive.getmembers():
            member_path = normalize_member_path(member.name)
            if not member_path:
                continue
            if member.uid != 0 or member.gid != 0:
                raise ValueError(
                    f"{path.name}:{member_path} has non-root archive ownership {member.uid}:{member.gid}"
                )
            entry: dict[str, Any] = {
                "path": member_path,
                "type": classify_tar_member(member, path, member_path),
                "mode": f"{member.mode:04o}",
                "uid": member.uid,
                "gid": member.gid,
            }
            if member.isfile():
                content = archive.extractfile(member)
                if content is None:
                    raise ValueError(f"Could not read {member_path} from {path.name}")
                entry["sha256"] = hashlib.sha256(content.read()).hexdigest()
            if member.issym() or member.islnk():
                entry["target"] = member.linkname
            entries.append(entry)

    control_entries: list[dict[str, Any]] = []
    control_tar = run(["dpkg-deb", "--ctrl-tarfile", str(path)])
    with tarfile.open(fileobj=io.BytesIO(control_tar), mode="r:") as archive:
        for member in archive.getmembers():
            member_path = normalize_member_path(member.name)
            if not member_path:
                continue
            if member.uid != 0 or member.gid != 0:
                raise ValueError(
                    f"{path.name}:DEBIAN/{member_path} has non-root archive ownership {member.uid}:{member.gid}"
                )
            entry = {
                "path": member_path,
                "type": classify_tar_member(member, path, f"DEBIAN/{member_path}"),
                "mode": f"{member.mode:04o}",
                "uid": member.uid,
                "gid": member.gid,
            }
            if member.issym() or member.islnk():
                entry["target"] = member.linkname
            if member.isfile():
                content = archive.extractfile(member)
                if content is None:
                    raise ValueError(f"Could not read DEBIAN/{member_path} from {path.name}")
                entry["sha256"] = hashlib.sha256(content.read()).hexdigest()
            control_entries.append(entry)
    if expected.get("maintainer_scripts"):
        scripts = {entry["path"]: entry for entry in control_entries}
        for script, mode in expected["maintainer_scripts"].items():
            entry = scripts.get(script, {})
            if (
                entry.get("type") != "file"
                or entry.get("mode") != mode
                or not entry.get("sha256")
            ):
                raise ValueError(f"{path.name} is missing maintainer script {script} with mode {mode}")

    members = {entry["path"]: entry for entry in entries}
    for member_path, mode in expected["executables"].items():
        entry = members.get(member_path)
        if (
            entry is None
            or entry["type"] != "file"
            or entry["mode"] != mode
            or not entry.get("sha256")
        ):
            raise ValueError(f"{path.name} is missing executable {member_path} with mode {mode}")
    for member_path in expected.get("absent", []):
        if member_path in members:
            raise ValueError(f"{path.name} unexpectedly owns {member_path}")

    copied = output / path.name
    shutil.copy2(path, copied)
    (output / f"{path.name}.control.txt").write_bytes(run(["dpkg-deb", "--info", str(path)]))
    (output / f"{path.name}.contents.txt").write_bytes(run(["dpkg-deb", "--contents", str(path)]))
    (output / f"{path.name}.control-archive.txt").write_text(
        "\n".join(
            f"{entry['mode']} {entry['uid']}:{entry['gid']} {entry['path']}"
            + (f" sha256={entry['sha256']}" if "sha256" in entry else "")
            for entry in control_entries
        )
        + "\n",
        encoding="utf-8",
    )
    return {
        "file": path.name,
        "sha256": sha256(path),
        "size_bytes": path.stat().st_size,
        "control": fields,
        "control_archive": control_entries,
        "payload": entries,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--packages-dir", type=Path, required=True)
    parser.add_argument("--admindir", type=Path, required=True,
                        help="dpkg database directory from the live-build chroot")
    parser.add_argument("--iso", type=Path, required=True)
    parser.add_argument("--version", required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    args = parser.parse_args()

    try:
        if not args.iso.is_file() or args.iso.stat().st_size == 0:
            raise ValueError(f"Missing built ISO: {args.iso}")
        if not (args.admindir / "status").is_file():
            raise ValueError(f"Missing chroot dpkg status database: {args.admindir / 'status'}")
        args.output_dir.mkdir(parents=True, exist_ok=True)
        specs = (
            {
                "name": "shreeos-tools",
                "architecture": "all",
                "dependencies": [
                    "apt", "coreutils", "dpkg", "grep", "hostname", "iproute2",
                    "mawk", "procps", "sed", "systemd", "util-linux",
                ],
                "executables": {
                    "usr/bin/shreeinfo": "0755",
                    "usr/bin/shree-doctor": "0755",
                    "usr/bin/shree-netdiag": "0755",
                    "usr/bin/shree-audit": "0755",
                },
            },
            {
                "name": "shreeos-native-tools",
                "architecture": "amd64",
                "dependencies": ["adduser", "bash", "coreutils", "procps", "konsole", "systemd"],
                "exact_dependency": True,
                "maintainer_scripts": {"postinst": "0755"},
                "executables": {
                    "usr/bin/shreeos-sysmon": "0755",
                    "usr/bin/shreeos-native-status": "0755",
                    "usr/bin/shreeos-verify-installed": "0755",
                    "usr/bin/shreedctl": "0755",
                    "usr/libexec/shreeos/shreed": "0755",
                },
                "absent": ["usr/bin/shreeinfo", "usr/bin/lpm", "sbin/init", "bin/sh"],
            },
        )
        packages = []
        for spec in specs:
            package_path = args.packages_dir / f"{spec['name']}_{args.version}_{spec['architecture']}.deb"
            packages.append(inspect_package(package_path, args.output_dir, spec, args.version))

        owners: dict[str, str] = {}
        for package in packages:
            for entry in package["payload"]:
                previous = owners.setdefault(entry["path"], package["control"]["Package"])
                if entry["path"] == "usr/bin/shreeinfo" and previous != package["control"]["Package"]:
                    raise ValueError("/usr/bin/shreeinfo is owned by more than one ShreeOS package")
        if owners.get("usr/bin/shreeinfo") != "shreeos-tools":
            raise ValueError("shreeos-tools must be the sole owner of /usr/bin/shreeinfo")

        query = run([
            "dpkg-query", f"--admindir={args.admindir}", "--show",
            "--showformat=${Package}\t${Version}\t${db:Status-Status}\n",
            "shreeos-tools", "shreeos-native-tools",
        ]).decode("utf-8", errors="strict").splitlines()
        expected_status = {
            f"shreeos-tools\t{args.version}\tinstalled",
            f"shreeos-native-tools\t{args.version}\tinstalled",
        }
        if set(query) != expected_status:
            raise ValueError(f"Built chroot package database has unexpected ShreeOS package state: {query!r}")
        audit = run(["dpkg", f"--admindir={args.admindir}", "--audit"]).decode("utf-8", errors="strict")
        if audit.strip():
            raise ValueError(f"Built chroot dpkg --audit reported problems:\n{audit}")

        iso = {
            "file": args.iso.name,
            "sha256": sha256(args.iso),
            "size_bytes": args.iso.stat().st_size,
        }
        report = {
            "schema": "shreeos-debian-package-evidence-v1",
            "source_commit": os.environ.get("GITHUB_SHA", ""),
            "version": args.version,
            "iso": iso,
            "packages": packages,
            "installed_package_status": query,
            "dpkg_audit": "passed",
            "shreeinfo_owner": owners["usr/bin/shreeinfo"],
        }
        (args.output_dir / "package-evidence.json").write_text(
            json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8"
        )
        with (args.output_dir / "SHA256SUMS").open("w", encoding="utf-8") as stream:
            for package in packages:
                stream.write(f"{package['sha256']}  {package['file']}\n")
        print(f"Inspected {len(packages)} Debian packages for {iso['file']} ({iso['sha256']}).")
    except (OSError, RuntimeError, ValueError, KeyError, tarfile.TarError) as error:
        print(f"Debian package evidence capture failed: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
