#!/usr/bin/env python3
"""Emit normalized container limits and process security conditions for QEMU samples."""

from __future__ import annotations

import argparse
import json
import re
import sys
from fractions import Fraction
from pathlib import Path


PROCESS_FIELDS = (
    "CapEff",
    "CapBnd",
    "NoNewPrivs",
    "Seccomp",
    "Seccomp_filters",
)


def unescape_mount_field(value: str) -> str:
    return re.sub(r"\\([0-7]{3})", lambda match: chr(int(match.group(1), 8)), value)


def cgroup_mount() -> tuple[Path, Path]:
    for line in Path("/proc/self/mountinfo").read_text(encoding="utf-8").splitlines():
        before, separator, after = line.partition(" - ")
        if not separator:
            continue
        filesystem = after.split()
        if not filesystem or filesystem[0] != "cgroup2":
            continue
        fields = before.split()
        if len(fields) < 5:
            continue
        root = Path(unescape_mount_field(fields[3]))
        mountpoint = Path(unescape_mount_field(fields[4]))
        return root, mountpoint
    raise ValueError("a cgroup v2 mount is required for comparable performance measurements")


def cgroup_directory() -> tuple[Path, Path]:
    cgroup_path = None
    for line in Path("/proc/self/cgroup").read_text(encoding="utf-8").splitlines():
        hierarchy, controllers, path = line.split(":", 2)
        if hierarchy == "0" and controllers == "":
            cgroup_path = Path(path)
            break
    if cgroup_path is None:
        raise ValueError("the process is not attached to a unified cgroup v2 hierarchy")

    mount_root, mountpoint = cgroup_mount()
    try:
        relative = cgroup_path.relative_to(mount_root)
    except ValueError as error:
        # A private cgroup namespace reports its namespace root as "/", while
        # mountinfo can retain the host-side root of the mounted subtree.
        if cgroup_path == Path("/"):
            relative = Path(".")
        else:
            raise ValueError("the process cgroup path is outside the visible cgroup v2 mount") from error
    current = (mountpoint / relative).resolve(strict=True)
    mountpoint = mountpoint.resolve(strict=True)
    try:
        current.relative_to(mountpoint)
    except ValueError as error:
        raise ValueError("the process cgroup resolved outside the visible cgroup v2 mount") from error
    if not current.is_dir():
        raise ValueError("the current cgroup v2 path is not a directory")
    return current, mountpoint


def ancestors(current: Path, mountpoint: Path) -> list[Path]:
    result = []
    path = current
    while True:
        result.append(path)
        if path == mountpoint:
            return result
        path = path.parent
        if not path.is_relative_to(mountpoint):
            raise ValueError("the visible cgroup hierarchy did not reach its mount root")


def read_hierarchy(current: Path, mountpoint: Path, filename: str) -> list[str]:
    values = []
    for directory in ancestors(current, mountpoint):
        path = directory / filename
        if path.is_file():
            values.append(path.read_text(encoding="ascii").strip())
    if not values:
        raise ValueError(f"required cgroup v2 controller file is unavailable: {filename}")
    return values


def parse_cpu_max(value: str) -> Fraction | None:
    fields = value.split()
    if len(fields) != 2 or not fields[1].isdigit():
        raise ValueError(f"invalid cpu.max value: {value!r}")
    if fields[0] == "max":
        return None
    if not fields[0].isdigit() or int(fields[1]) == 0:
        raise ValueError(f"invalid cpu.max quota: {value!r}")
    return Fraction(int(fields[0]), int(fields[1]))


def fraction_text(value: Fraction) -> str:
    return str(value.numerator) if value.denominator == 1 else f"{value.numerator}/{value.denominator}"


def effective_cpu_quota(values: list[str]) -> str:
    finite = [quota for raw in values if (quota := parse_cpu_max(raw)) is not None]
    return "max" if not finite else fraction_text(min(finite))


def effective_limit(values: list[str], field: str) -> str:
    parsed = []
    for raw in values:
        if raw == "max":
            continue
        if not raw.isdigit():
            raise ValueError(f"invalid {field} value: {raw!r}")
        parsed.append(int(raw))
    return "max" if not parsed else str(min(parsed))


def cpuset_count(value: str) -> int:
    if not value:
        raise ValueError("cpuset.cpus.effective is empty")
    count = 0
    for item in value.split(","):
        bounds = item.split("-", 1)
        if len(bounds) == 1 and bounds[0].isdigit():
            count += 1
        elif len(bounds) == 2 and all(bound.isdigit() for bound in bounds):
            first, last = map(int, bounds)
            if last < first:
                raise ValueError(f"invalid cpuset range: {item!r}")
            count += last - first + 1
        else:
            raise ValueError(f"invalid cpuset.cpus.effective value: {value!r}")
    return count


def process_status() -> dict[str, str]:
    status = {}
    for line in Path("/proc/self/status").read_text(encoding="ascii").splitlines():
        key, separator, value = line.partition(":")
        if separator and key in PROCESS_FIELDS:
            status[key] = value.strip()
    missing = [field for field in PROCESS_FIELDS if not status.get(field)]
    if missing:
        raise ValueError(f"process security status fields are unavailable: {missing}")
    return status


def read_counters(path: Path) -> dict[str, int]:
    counters = {}
    for line in path.read_text(encoding="ascii").splitlines():
        fields = line.split()
        if len(fields) != 2 or not fields[1].isdigit():
            raise ValueError(f"invalid cgroup counter line in {path}: {line!r}")
        if fields[0] in counters:
            raise ValueError(f"duplicate cgroup counter in {path}: {fields[0]}")
        counters[fields[0]] = int(fields[1])
    return counters


def collect_counters() -> dict[str, dict[str, int]]:
    current, _ = cgroup_directory()
    return {
        "cpu_stat": read_counters(current / "cpu.stat"),
        "memory_events": read_counters(current / "memory.events"),
    }


def emit_counter_delta(snapshot: Path) -> None:
    before = json.loads(snapshot.read_text(encoding="utf-8"))
    after = collect_counters()
    rows = []
    for group in ("cpu_stat", "memory_events"):
        if set(before.get(group, {})) != set(after[group]):
            raise ValueError(f"cgroup {group} counters changed shape during the QEMU capture")
        for key, value in sorted(after[group].items()):
            delta = value - int(before[group][key])
            if delta < 0:
                raise ValueError(f"cgroup {group} counter moved backwards: {key}")
            rows.append((f"cgroup_{group}_{key}_delta", str(delta)))
    for key, value in rows:
        print(f"# {key}={value}")


def collect() -> list[tuple[str, str]]:
    current, mountpoint = cgroup_directory()
    cpu_values = read_hierarchy(current, mountpoint, "cpu.max")
    cpus_path = current / "cpuset.cpus.effective"
    if not cpus_path.is_file():
        raise ValueError("required cgroup v2 controller file is unavailable: cpuset.cpus.effective")
    cpuset = cpus_path.read_text(encoding="ascii").strip()
    rows = [
        ("cgroup_version", "2"),
        ("cgroup_cpuset_cpus_effective", cpuset),
        ("cgroup_cpuset_cpu_count", str(cpuset_count(cpuset))),
        ("cgroup_cpu_quota_cores", effective_cpu_quota(cpu_values)),
    ]
    for filename, key in (
        ("memory.max", "cgroup_memory_max_bytes"),
        ("memory.high", "cgroup_memory_high_bytes"),
        ("memory.swap.max", "cgroup_memory_swap_max_bytes"),
        ("pids.max", "cgroup_pids_max"),
    ):
        rows.append((key, effective_limit(read_hierarchy(current, mountpoint, filename), filename)))
    status = process_status()
    for field in PROCESS_FIELDS:
        rows.append((f"process_{field.lower()}", status[field]))
    return rows


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--snapshot", type=Path)
    parser.add_argument("--delta", type=Path)
    args = parser.parse_args()
    if args.snapshot and args.delta:
        parser.error("--snapshot and --delta cannot be used together")
    try:
        if args.snapshot:
            args.snapshot.write_text(json.dumps(collect_counters(), sort_keys=True) + "\n", encoding="utf-8")
            return 0
        if args.delta:
            emit_counter_delta(args.delta)
            return 0
        for key, value in collect():
            if "\n" in value or "\r" in value or "=" in value:
                raise ValueError(f"unsafe metadata value for {key}")
            print(f"# {key}={value}")
    except (OSError, UnicodeError, ValueError) as error:
        print(f"Could not collect comparable performance environment: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
