#!/usr/bin/env python3
"""Gate aggregate ShreeOS performance medians against targets and a real baseline."""

from __future__ import annotations

import argparse
import math
import sys
from pathlib import Path


BASELINE_COMMIT = "9313ebb042cf71bb148441037940b130d49920d1"
REQUIRED_METADATA = (
    "source_commit", "iso_sha256", "conditions", "probe_sha256",
    "probe_service_sha256", "probe_timer_sha256", "probe_time_helper_sha256",
    "measurement_protocol_sha256", "qemu_version",
    "qemu_package_version", "seabios_package_version", "bios_rom_sha256",
    "host_kernel", "host_cpu_model", "host_mem_total_kib", "firmware",
    "qemu_profile", "sample_count",
)
MATCHED_ENVIRONMENT = tuple(key for key in REQUIRED_METADATA if key not in {
    "source_commit", "iso_sha256", "sample_count",
})
REQUIRED_METRICS = (
    "mem_used_mib", "cpu_busy_pct", "boot_total_ms", "graphical_reached_ms",
    "desktop_ready", "pss_available", "units_failed", "storage_write_mib_s",
    "storage_read_mib_s",
)
COMPARATIVE_METRICS = ("mem_used_mib", "cpu_busy_pct", "boot_total_ms", "graphical_reached_ms")
REGRESSION_TOLERANCE_PCT = 20.0


def read_summary(path: Path) -> tuple[dict[str, str], dict[str, float]]:
    metadata: dict[str, str] = {}
    metrics: dict[str, float] = {}
    for line_number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        if line.startswith("# "):
            key, separator, value = line[2:].partition("=")
            is_sample_command = key.startswith("sample_") and key.endswith("_qemu_command")
            if separator and not is_sample_command and not key.startswith("variability_"):
                if key in metadata:
                    raise ValueError(f"duplicate metadata field {key!r} in {path}:{line_number}")
                metadata[key] = value
            continue
        if not line:
            continue
        fields = line.split("\t")
        if len(fields) != 2 or fields[0] in metrics:
            raise ValueError(f"invalid or duplicate metric in {path}:{line_number}")
        try:
            value = float(fields[1])
        except ValueError as error:
            raise ValueError(f"nonnumeric metric in {path}:{line_number}") from error
        if not math.isfinite(value):
            raise ValueError(f"non-finite metric in {path}:{line_number}")
        metrics[fields[0]] = value

    missing_metadata = [key for key in REQUIRED_METADATA if not metadata.get(key)]
    missing_metrics = [key for key in REQUIRED_METRICS if key not in metrics]
    if missing_metadata or missing_metrics:
        raise ValueError(f"{path} lacks metadata {missing_metadata} or metrics {missing_metrics}")
    if not metadata["sample_count"].isdigit() or int(metadata["sample_count"]) < 3:
        raise ValueError(f"{path} must contain at least three samples")
    if not math.isclose(metrics["desktop_ready"], 1):
        raise ValueError(f"aggregate {path} does not report a ready desktop")
    if not math.isclose(metrics["pss_available"], 1):
        raise ValueError(f"aggregate {path} does not report PSS instrumentation")
    if not math.isclose(metrics["units_failed"], 0):
        raise ValueError(f"aggregate {path} reports failed system units")
    for key in ("boot_total_ms", "graphical_reached_ms", "storage_write_mib_s", "storage_read_mib_s"):
        if metrics[key] <= 0:
            raise ValueError(f"aggregate metric {key} must be positive in {path}")
    return metadata, metrics


def read_targets(path: Path) -> list[tuple[str, float, str, str]]:
    targets = []
    for line_number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        if not line or line.startswith("#"):
            continue
        fields = line.split("\t")
        if len(fields) != 4:
            raise ValueError(f"invalid target row at {path}:{line_number}")
        key, limit, comparison, provenance = fields
        if comparison not in {"min", "max"}:
            raise ValueError(f"invalid comparison {comparison!r} at {path}:{line_number}")
        targets.append((key, float(limit), comparison, provenance))
    if not targets:
        raise ValueError(f"no performance targets were read from {path}")
    return targets


def evaluate(candidate_path: Path, baseline_path: Path | None, targets_path: Path,
             require_baseline: bool) -> tuple[list[str], list[str]]:
    candidate_meta, candidate = read_summary(candidate_path)
    targets = read_targets(targets_path)
    failures: list[str] = []
    details: list[str] = []

    for key, limit, comparison, provenance in targets:
        if key not in candidate:
            failures.append(f"candidate median is missing target metric {key}")
            continue
        value = candidate[key]
        passed = value >= limit if comparison == "min" else value <= limit
        details.append(f"{key}: {value:g} {comparison} {limit:g} — {'PASS' if passed else 'FAIL'} ({provenance})")
        if not passed:
            failures.append(f"candidate median missed {key}={value:g} ({comparison} {limit:g})")

    if baseline_path is None:
        if require_baseline:
            failures.append("the untouched-build performance baseline is required but missing")
        else:
            details.append("Relative comparison: skipped; no reviewed baseline TSV is committed.")
        return failures, details

    baseline_meta, baseline = read_summary(baseline_path)
    if baseline_meta["source_commit"] != BASELINE_COMMIT:
        failures.append(f"baseline source must be the untouched commit {BASELINE_COMMIT}")
    for key in MATCHED_ENVIRONMENT:
        if baseline_meta[key] != candidate_meta[key]:
            failures.append(f"baseline and candidate differ in measurement environment field {key}")

    for key in COMPARATIVE_METRICS:
        before = baseline[key]
        after = candidate[key]
        if before <= 0:
            if key == "cpu_busy_pct" and before == 0:
                details.append("cpu_busy_pct regression: skipped because the baseline is zero and the metric is already within its absolute target.")
                continue
            failures.append(f"baseline {key} must be positive for comparison")
            continue
        regression_pct = ((after - before) / before) * 100
        passed = regression_pct <= REGRESSION_TOLERANCE_PCT
        details.append(
            f"{key} regression: baseline {before:g}, candidate median {after:g}, "
            f"delta {regression_pct:+.1f}% — {'PASS' if passed else 'FAIL'}"
        )
        if not passed:
            failures.append(f"candidate median regressed {key} by {regression_pct:.1f}%")

    baseline_memory = baseline["mem_used_mib"]
    baseline_cpu = baseline["cpu_busy_pct"]
    candidate_memory = candidate["mem_used_mib"]
    candidate_cpu = candidate["cpu_busy_pct"]
    already_efficient = baseline_memory <= 850 and baseline_cpu <= 2
    improved = (
        candidate_memory <= baseline_memory * 0.8
        or candidate_cpu <= baseline_cpu * 0.8
    )
    if already_efficient or improved:
        reason = "baseline already meets both idle limits" if already_efficient else "at least one idle metric improved by 20%"
        details.append(f"Idle RAM/CPU improvement requirement: PASS ({reason}).")
    else:
        failures.append("candidate did not improve idle RAM or CPU by 20%, and baseline misses one or both absolute limits")
        details.append("Idle RAM/CPU improvement requirement: FAIL.")

    details.append(
        "Storage throughput is reported for context only; separate hosted-runner backing storage is not a product regression gate."
    )
    return failures, details


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--candidate", required=True, type=Path)
    parser.add_argument("--baseline", type=Path)
    parser.add_argument("--targets", required=True, type=Path)
    parser.add_argument("--report-output", required=True, type=Path)
    parser.add_argument("--require-baseline", action="store_true")
    args = parser.parse_args(argv[1:])
    try:
        failures, details = evaluate(args.candidate, args.baseline, args.targets, args.require_baseline)
        args.report_output.parent.mkdir(parents=True, exist_ok=True)
        with args.report_output.open("w", encoding="utf-8", newline="\n") as report:
            report.write("# Aggregate performance acceptance\n\n")
            report.write(f"Candidate: `{args.candidate}`\n\n")
            report.write(f"Baseline: `{args.baseline or 'not supplied'}`\n\n")
            for line in details:
                report.write(f"- {line}\n")
            report.write("\n")
            if failures:
                report.write("## Failed gates\n\n")
                for failure in failures:
                    report.write(f"- {failure}\n")
        for line in details:
            print(line)
        if failures:
            for failure in failures:
                print(f"PERFORMANCE GATE FAILED: {failure}", file=sys.stderr)
            return 1
        print("Aggregate performance gate passed.")
        return 0
    except (OSError, UnicodeError, ValueError) as error:
        print(f"Could not evaluate aggregate performance: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
