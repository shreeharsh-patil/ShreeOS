#!/usr/bin/env python3
"""Aggregate repeated ShreeOS performance samples without losing raw inputs."""

from __future__ import annotations

import argparse
import math
import statistics
import sys
from fractions import Fraction
from pathlib import Path


METADATA_FIELDS = (
    "source_commit",
    "iso_sha256",
    "conditions",
    "probe_sha256",
    "probe_service_sha256",
    "probe_timer_sha256",
    "probe_time_helper_sha256",
    "measurement_protocol_sha256",
    "qemu_version",
    "qemu_package_version",
    "seabios_package_version",
    "bios_rom_sha256",
    "host_kernel",
    "host_cpu_model",
    "host_mem_total_kib",
    "cgroup_limit_scope",
    "cgroup_memory_event_scope",
    "cgroup_reported_path_shape",
    "cgroup_mount_root_path_shape",
    "cgroup_version",
    "cgroup_cpuset_cpus_effective",
    "cgroup_cpuset_cpu_count",
    "cgroup_cpu_quota_cores",
    "cgroup_memory_max_bytes",
    "cgroup_memory_high_bytes",
    "cgroup_memory_swap_max_bytes",
    "cgroup_pids_max",
    "collector_capeff",
    "collector_capbnd",
    "collector_nonewprivs",
    "collector_seccomp",
    "collector_seccomp_filters",
    "qemu_process_capeff",
    "qemu_process_capbnd",
    "qemu_process_nonewprivs",
    "qemu_process_seccomp",
    "qemu_process_seccomp_filters",
    "firmware",
    "qemu_profile",
)
SAMPLE_REQUIRED_METADATA_FIELDS = (*METADATA_FIELDS, "qemu_command")
METRICS = (
    "mem_used_mib",
    "cpu_busy_pct",
    "boot_total_ms",
    "graphical_reached_ms",
    "desktop_ready",
    "pss_available",
    "units_failed",
    "storage_write_mib_s",
    "storage_read_mib_s",
)
RESOURCE_COUNTERS = (
    "cgroup_cpu_stat_nr_periods_delta",
    "cgroup_cpu_stat_nr_throttled_delta",
    "cgroup_cpu_stat_throttled_usec_delta",
    "cgroup_cpu_stat_throttled_usec_local_delta",
    "cgroup_capture_elapsed_usec",
    "cgroup_memory_events_low_visible_max_delta",
    "cgroup_memory_events_high_visible_max_delta",
    "cgroup_memory_events_max_visible_max_delta",
    "cgroup_memory_events_oom_visible_max_delta",
    "cgroup_memory_events_oom_kill_visible_max_delta",
    "cgroup_memory_events_oom_group_kill_visible_max_delta",
)
MEMORY_PRESSURE_COUNTERS = RESOURCE_COUNTERS[5:]
REPORTED_METRICS = (
    *METRICS,
    *RESOURCE_COUNTERS,
    "cgroup_cpu_throttled_period_pct",
    "cgroup_cpu_local_throttled_capacity_estimate_pct",
)
MAX_THROTTLED_PERIOD_PCT = 10.0


def parse_sample(path: Path) -> tuple[dict[str, str], dict[str, float]]:
    metadata: dict[str, str] = {}
    metrics: dict[str, float] = {}
    for line_number, raw_line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        if raw_line.startswith("# "):
            key, separator, value = raw_line[2:].partition("=")
            if separator:
                if key in metadata:
                    raise ValueError(f"duplicate metadata field {key!r} in {path}:{line_number}")
                metadata[key] = value
            continue
        if not raw_line:
            continue
        fields = raw_line.split("\t")
        if len(fields) != 2 or fields[0] in metrics:
            raise ValueError(f"invalid or duplicate metric in {path}:{line_number}")
        try:
            value = float(fields[1])
        except ValueError as error:
            raise ValueError(f"nonnumeric metric in {path}:{line_number}") from error
        if not math.isfinite(value):
            raise ValueError(f"non-finite metric in {path}:{line_number}")
        metrics[fields[0]] = value

    missing_metadata = [
        field for field in SAMPLE_REQUIRED_METADATA_FIELDS if not metadata.get(field)
    ]
    missing_metrics = [field for field in (*METRICS, *RESOURCE_COUNTERS) if field not in metrics]
    if missing_metadata or missing_metrics:
        raise ValueError(
            f"{path} is missing metadata {missing_metadata} or metrics {missing_metrics}"
        )
    if not math.isclose(metrics["desktop_ready"], 1):
        raise ValueError(f"desktop was not ready in {path}")
    if not math.isclose(metrics["pss_available"], 1):
        raise ValueError(f"per-process PSS was unavailable in {path}")
    if not math.isclose(metrics["units_failed"], 0):
        raise ValueError(f"failed system units were reported in {path}")
    for metric in ("boot_total_ms", "graphical_reached_ms", "storage_write_mib_s", "storage_read_mib_s"):
        if metrics[metric] <= 0:
            raise ValueError(f"metric {metric} must be positive in {path}")
    for counter in RESOURCE_COUNTERS:
        if metrics[counter] < 0 or not metrics[counter].is_integer():
            raise ValueError(f"resource counter {counter} must be a nonnegative integer in {path}")
    periods = metrics["cgroup_cpu_stat_nr_periods_delta"]
    throttled = metrics["cgroup_cpu_stat_nr_throttled_delta"]
    own_throttled_usec = metrics["cgroup_cpu_stat_throttled_usec_delta"]
    local_throttled_usec = metrics["cgroup_cpu_stat_throttled_usec_local_delta"]
    elapsed_usec = metrics["cgroup_capture_elapsed_usec"]
    if throttled > periods or (periods == 0 and (throttled or own_throttled_usec)):
        raise ValueError(f"invalid cgroup CPU throttling counters in {path}")
    if elapsed_usec <= 0:
        raise ValueError(f"cgroup capture duration must be positive in {path}")
    pressured = [key for key in MEMORY_PRESSURE_COUNTERS if metrics[key] > 0]
    if pressured:
        raise ValueError(f"cgroup memory pressure events were reported in {path}: {pressured}")
    metrics["cgroup_cpu_throttled_period_pct"] = throttled / periods * 100 if periods else 0.0
    cpuset_cpus = int(metadata["cgroup_cpuset_cpu_count"])
    raw_quota = metadata["cgroup_cpu_quota_cores"]
    quota_cpus = float("inf") if raw_quota == "max" else float(Fraction(raw_quota))
    available_cpus = min(float(cpuset_cpus), quota_cpus)
    if available_cpus <= 0:
        raise ValueError(f"visible cgroup CPU capacity must be positive in {path}")
    metrics["cgroup_cpu_local_throttled_capacity_estimate_pct"] = (
        local_throttled_usec / (elapsed_usec * available_cpus) * 100
    )
    if max(
        metrics["cgroup_cpu_throttled_period_pct"],
        metrics["cgroup_cpu_local_throttled_capacity_estimate_pct"],
    ) > MAX_THROTTLED_PERIOD_PCT:
        raise ValueError(
            f"cgroup CPU throttling exceeded {MAX_THROTTLED_PERIOD_PCT:g}% in {path}"
        )
    return metadata, metrics


def format_number(value: float) -> str:
    if math.isclose(value, round(value)):
        return str(round(value))
    return f"{value:.2f}".rstrip("0").rstrip(".")


def aggregate(samples: list[Path]) -> tuple[dict[str, str], dict[str, tuple[float, float, float]]]:
    if len(samples) < 2:
        raise ValueError("at least two performance samples are required to report variability")
    parsed = [parse_sample(path) for path in samples]
    metadata = parsed[0][0]
    for path, (candidate_metadata, _) in zip(samples[1:], parsed[1:], strict=True):
        mismatches = [
            field for field in METADATA_FIELDS
            if candidate_metadata.get(field) != metadata.get(field)
        ]
        if mismatches:
            raise ValueError(f"sample environment/provenance differs in {path}: {mismatches}")
    result: dict[str, tuple[float, float, float]] = {}
    for metric in REPORTED_METRICS:
        values = [sample_metrics[metric] for _, sample_metrics in parsed]
        result[metric] = (min(values), statistics.median(values), max(values))
    return metadata, result


def write_summary(output: Path, report: Path, samples: list[Path]) -> None:
    metadata, metrics = aggregate(samples)
    parsed_samples = [parse_sample(path) for path in samples]
    output.parent.mkdir(parents=True, exist_ok=True)
    report.parent.mkdir(parents=True, exist_ok=True)
    with output.open("w", encoding="utf-8", newline="\n") as stream:
        for field in METADATA_FIELDS:
            stream.write(f"# {field}={metadata[field]}\n")
        stream.write(f"# sample_count={len(samples)}\n")
        for index, (sample_metadata, _) in enumerate(parsed_samples, 1):
            stream.write(
                f"# sample_{index}_qemu_command={sample_metadata['qemu_command']}\n"
            )
        for metric in REPORTED_METRICS:
            minimum, median, maximum = metrics[metric]
            stream.write(
                f"# variability_{metric}=min:{format_number(minimum)},"
                f"median:{format_number(median)},max:{format_number(maximum)}\n"
            )
        for metric in REPORTED_METRICS:
            stream.write(f"{metric}\t{format_number(metrics[metric][1])}\n")

    with report.open("w", encoding="utf-8", newline="\n") as stream:
        stream.write("# Repeated ShreeOS performance summary\n\n")
        stream.write(f"Samples: {len(samples)}\n\n")
        stream.write(f"Source commit: `{metadata['source_commit']}`\n\n")
        stream.write(f"ISO SHA-256: `{metadata['iso_sha256']}`\n\n")
        stream.write(f"Conditions: {metadata['conditions']}\n\n")
        stream.write(f"Measurement protocol SHA-256: `{metadata['measurement_protocol_sha256']}`\n\n")
        stream.write(f"QEMU: {metadata['qemu_version']}\n\n")
        stream.write(f"QEMU package: `{metadata['qemu_package_version']}`\n\n")
        stream.write(f"Host: {metadata['host_kernel']}; {metadata['host_cpu_model']}; "
                     f"{metadata['host_mem_total_kib']} KiB RAM\n\n")
        stream.write(f"Firmware: {metadata['firmware']}\n\n")
        stream.write(f"SeaBIOS package: `{metadata['seabios_package_version']}`\n\n")
        stream.write(f"SeaBIOS ROM SHA-256: `{metadata['bios_rom_sha256']}`\n\n")
        stream.write("Per-sample QEMU commands:\n\n")
        for index, (sample_metadata, _) in enumerate(parsed_samples, 1):
            stream.write(f"- Sample {index}: `{sample_metadata['qemu_command']}`\n")
        stream.write("\n")
        stream.write("| Metric | Minimum | Median | Maximum |\n| --- | ---: | ---: | ---: |\n")
        for metric, (minimum, median, maximum) in metrics.items():
            stream.write(
                f"| {metric} | {format_number(minimum)} | {format_number(median)} | "
                f"{format_number(maximum)} |\n"
            )
        stream.write("\nRaw per-run TSVs and logs are retained beside this summary. Cgroup counters cover the visible hierarchy; CPU local throttling includes inherited ancestor throttling where the kernel exposes it.\n")


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--report-output", required=True, type=Path)
    parser.add_argument("samples", nargs="+", type=Path)
    args = parser.parse_args(argv[1:])
    try:
        write_summary(args.output, args.report_output, args.samples)
    except (OSError, UnicodeError, ValueError) as error:
        print(f"Could not aggregate performance samples: {error}", file=sys.stderr)
        return 1
    print(f"Aggregated {len(args.samples)} performance samples into {args.output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
