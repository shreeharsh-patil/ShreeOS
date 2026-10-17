#!/usr/bin/env python3
"""Emit visible cgroup limits and collector/QEMU process security conditions."""

from __future__ import annotations

import argparse
import json
import re
import sys
import time
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


def process_cgroup_path(pid: int | None = None) -> Path:
    cgroup_path = None
    cgroup_file = Path("/proc/self/cgroup") if pid is None else Path("/proc", str(pid), "cgroup")
    for line in cgroup_file.read_text(encoding="utf-8").splitlines():
        hierarchy, controllers, path = line.split(":", 2)
        if hierarchy == "0" and controllers == "":
            cgroup_path = Path(path)
            break
    if cgroup_path is None:
        raise ValueError("the process is not attached to a unified cgroup v2 hierarchy")
    return cgroup_path


def cgroup_directory(pid: int | None = None) -> tuple[Path, Path]:
    cgroup_path = process_cgroup_path(pid)
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


def cgroup_reported_path_shape() -> str:
    return "root" if process_cgroup_path() == Path("/") else "non-root"


def cgroup_mount_root_path_shape() -> str:
    mount_root, _ = cgroup_mount()
    return "slash" if mount_root == Path("/") else "subpath"


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


def process_status(pid: int | None = None) -> dict[str, str]:
    status = {}
    status_path = Path("/proc/self/status") if pid is None else Path("/proc", str(pid), "status")
    for line in status_path.read_text(encoding="ascii").splitlines():
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


def collect_counters() -> dict[str, object]:
    current, mountpoint = cgroup_directory()
    memory_events = {}
    for level, directory in enumerate(ancestors(current, mountpoint)):
        path = directory / "memory.events.local"
        if not path.is_file():
            raise ValueError(f"memory.events.local is unavailable at visible cgroup level {level}")
        memory_events[f"level_{level}"] = read_counters(path)
    if not memory_events:
        raise ValueError("memory.events.local is unavailable in the visible cgroup hierarchy")
    required_memory_events = {"low", "high", "max", "oom", "oom_kill", "oom_group_kill"}
    if any(not required_memory_events.issubset(values) for values in memory_events.values()):
        raise ValueError("visible cgroup memory event counters are incomplete")
    cpu_stat_local = read_counters(current / "cpu.stat.local")
    if "throttled_usec" not in cpu_stat_local:
        raise ValueError("cpu.stat.local does not expose inherited cgroup throttling")
    return {
        "cpu_stat": read_counters(current / "cpu.stat"),
        "cpu_stat_local": cpu_stat_local,
        "memory_events_local": memory_events,
        "captured_monotonic_ns": time.monotonic_ns(),
    }


def emit_counter_delta(snapshot: Path) -> None:
    before = json.loads(snapshot.read_text(encoding="utf-8"))
    after = collect_counters()
    rows = []
    for group in ("cpu_stat", "cpu_stat_local"):
        if set(before.get(group, {})) != set(after[group]):
            raise ValueError(f"cgroup {group} counters changed shape during the QEMU capture")
        for key, value in sorted(after[group].items()):
            delta = value - int(before[group][key])
            if delta < 0:
                raise ValueError(f"cgroup {group} counter moved backwards: {key}")
            metric_group = group.removesuffix("_local")
            suffix = "_local_delta" if group.endswith("_local") else "_delta"
            rows.append((f"cgroup_{metric_group}_{key}{suffix}", str(delta)))
    before_memory = before.get("memory_events_local", {})
    after_memory = after["memory_events_local"]
    if set(before_memory) != set(after_memory):
        raise ValueError("visible cgroup memory event scopes changed during the QEMU capture")
    memory_keys = set().union(*(set(values) for values in before_memory.values()))
    for level in before_memory:
        if set(before_memory[level]) != set(after_memory[level]):
            raise ValueError("visible cgroup memory event counters changed shape during the QEMU capture")
    for key in sorted(memory_keys):
        deltas = []
        for level in before_memory:
            delta = after_memory[level][key] - int(before_memory[level][key])
            if delta < 0:
                raise ValueError(f"visible cgroup memory event counter moved backwards: {level}/{key}")
            deltas.append(delta)
        # memory.events.local is local to each cgroup, so taking the largest
        # visible-ancestor delta avoids counting the same pressure episode at
        # multiple levels while still detecting pressure at any visible level.
        rows.append((f"cgroup_memory_events_{key}_visible_max_delta", str(max(deltas))))
    elapsed_ns = int(after["captured_monotonic_ns"]) - int(before["captured_monotonic_ns"])
    if elapsed_ns <= 0:
        raise ValueError("cgroup capture elapsed time is not positive")
    rows.append(("cgroup_capture_elapsed_usec", str(elapsed_ns // 1000)))
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
        ("cgroup_limit_scope", "visible-hierarchy-ancestors"),
        ("cgroup_memory_event_scope", "visible-hierarchy-local-events"),
        ("cgroup_reported_path_shape", cgroup_reported_path_shape()),
        ("cgroup_mount_root_path_shape", cgroup_mount_root_path_shape()),
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
        rows.append((f"collector_{field.lower()}", status[field]))
    return rows


def collect_process(pid: int) -> list[tuple[str, str]]:
    if pid <= 0:
        raise ValueError("QEMU process ID must be positive")
    verify_qemu_pid(pid)
    verify_same_cgroup(pid)
    status = process_status(pid)
    return [(f"qemu_process_{field.lower()}", status[field]) for field in PROCESS_FIELDS]


def verify_qemu_pid(pid: int) -> None:
    executable = Path("/proc", str(pid), "exe").resolve(strict=True)
    if executable.name != "qemu-system-x86_64":
        raise ValueError(f"process {pid} is not the expected qemu-system-x86_64 executable")


def verify_same_cgroup(pid: int) -> None:
    collector_cgroup, _ = cgroup_directory()
    qemu_cgroup, _ = cgroup_directory(pid)
    if collector_cgroup != qemu_cgroup:
        raise ValueError("QEMU is not in the cgroup whose resource counters are being sampled")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--snapshot", type=Path)
    parser.add_argument("--delta", type=Path)
    parser.add_argument("--process-pid", type=int, help="emit security fields for this live process")
    args = parser.parse_args()
    if sum(value is not None for value in (args.snapshot, args.delta, args.process_pid)) > 1:
        parser.error("--snapshot, --delta, and --process-pid cannot be combined")
    try:
        if args.snapshot:
            args.snapshot.write_text(json.dumps(collect_counters(), sort_keys=True) + "\n", encoding="utf-8")
            return 0
        if args.delta:
            emit_counter_delta(args.delta)
            return 0
        rows = collect_process(args.process_pid) if args.process_pid is not None else collect()
        for key, value in rows:
            if "\n" in value or "\r" in value or "=" in value:
                raise ValueError(f"unsafe metadata value for {key}")
            print(f"# {key}={value}")
    except (OSError, UnicodeError, ValueError) as error:
        print(f"Could not collect comparable performance environment: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
