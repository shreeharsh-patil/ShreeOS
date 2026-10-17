#!/usr/bin/env python3
"""Aggregate repeated ShreeOS performance samples without losing raw inputs."""

from __future__ import annotations

import argparse
import math
import statistics
import sys
from pathlib import Path


METADATA_FIELDS = (
    "source_commit",
    "iso_sha256",
    "conditions",
    "probe_sha256",
    "probe_service_sha256",
    "probe_time_helper_sha256",
    "qemu_version",
    "qemu_package_version",
    "seabios_package_version",
    "bios_rom_sha256",
    "host_kernel",
    "host_cpu_model",
    "host_mem_total_kib",
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
    missing_metrics = [field for field in METRICS if field not in metrics]
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
    for metric in METRICS:
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
        for metric in METRICS:
            minimum, median, maximum = metrics[metric]
            stream.write(
                f"# variability_{metric}=min:{format_number(minimum)},"
                f"median:{format_number(median)},max:{format_number(maximum)}\n"
            )
        for metric in METRICS:
            stream.write(f"{metric}\t{format_number(metrics[metric][1])}\n")

    with report.open("w", encoding="utf-8", newline="\n") as stream:
        stream.write("# Repeated ShreeOS performance summary\n\n")
        stream.write(f"Samples: {len(samples)}\n\n")
        stream.write(f"Source commit: `{metadata['source_commit']}`\n\n")
        stream.write(f"ISO SHA-256: `{metadata['iso_sha256']}`\n\n")
        stream.write(f"Conditions: {metadata['conditions']}\n\n")
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
        stream.write("\nRaw per-run TSVs and logs are retained beside this summary.\n")


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
