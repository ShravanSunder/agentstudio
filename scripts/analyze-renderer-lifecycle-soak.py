#!/usr/bin/env python3
"""Fail-closed analysis for the fixed renderer lifecycle certification run."""

import argparse
import json
import math
import pathlib
import sys
import typing as t


FINAL_SAMPLE_COUNT = 180
WARMUP_SAMPLE_COUNT = 60
SAMPLE_INTERVAL_SECONDS = 10.0
T_CRITICAL_95_DF_178 = 1.973381

LIFECYCLE_FIELDS = (
    "created_total",
    "active_current",
    "hidden_current",
    "close_undo_current",
    "release_total",
    "free_total",
    "live_current",
    "manager_owned_current",
    "orphan_current",
    "visibility_delivery_total",
    "visibility_equal_suppressed_total",
    "projection_evaluation_total",
    "projection_changed_surface_total",
    "projection_equal_surface_total",
    "lifecycle_valid",
    "sample_sequence",
)
SYSTEM_FIELDS = (
    "app_physical_bytes",
    "app_iosurface_bytes",
    "app_ioaccelerator_bytes",
    "windowserver_footprint_bytes",
    "compressor_bytes",
    "swap_used_bytes",
    "raw_free_memory_bytes",
)
DECISION_FIELDS = SYSTEM_FIELDS[:-1] + ("free_memory_pressure_bytes",)
EXPECTED_SCENARIOS = {
    "tab_switch": 20,
    "drawer_toggle": 20,
    "arrangement_switch": 20,
    "background_reactivate": 20,
    "zoom_retarget": 20,
    "parent_minimize": 20,
    "drawer_minimize": 20,
    "window_minimize": 20,
    "window_occlusion": 20,
    "repair_recreate": 20,
    "close_immediate_undo": 10,
    "close_expiry": 10,
}
EXPECTED_MILESTONES = {
    "fixture_ready",
    "equal_reconciliation_verified",
    "changed_delivery_verified",
    "warmup_started",
    "warmup_completed",
    "final_window_started",
    "final_window_completed",
}
EXPECTED_MILESTONE_COUNTS = {
    "equal_reconciliation_verified": 20,
    "changed_delivery_verified": 40,
}


class CertificationFailure(Exception):
    pass


def read_json_lines(path: pathlib.Path) -> list[dict[str, t.Any]]:
    try:
        lines = path.read_text(encoding="utf-8").splitlines()
    except OSError as error:
        raise CertificationFailure(f"cannot read {path}: {error}") from error
    rows: list[dict[str, t.Any]] = []
    for line_number, line in enumerate(lines, start=1):
        if not line.strip():
            continue
        try:
            decoded = json.loads(line)
        except json.JSONDecodeError as error:
            raise CertificationFailure(f"invalid JSON at {path}:{line_number}") from error
        if not isinstance(decoded, dict):
            raise CertificationFailure(f"row at {path}:{line_number} is not an object")
        rows.append(decoded)
    if not rows:
        raise CertificationFailure(f"no rows in {path}")
    return rows


def require_number(row: dict[str, t.Any], field: str, row_index: int) -> float:
    value = row.get(field)
    if isinstance(value, bool) or not isinstance(value, (int, float)) or not math.isfinite(float(value)):
        raise CertificationFailure(f"sample {row_index} missing finite {field}")
    return float(value)


def validate_identity(rows: list[dict[str, t.Any]], progress: list[dict[str, t.Any]]) -> tuple[str, int, int]:
    marker_values = {row.get("marker") for row in rows + progress}
    app_pids = {row.get("app_pid") for row in rows + progress}
    windowserver_pids = {row.get("windowserver_pid") for row in rows}
    if len(marker_values) != 1 or not isinstance(next(iter(marker_values)), str):
        raise CertificationFailure("marker is missing, stale, or changes during the run")
    if len(app_pids) != 1 or not isinstance(next(iter(app_pids)), int):
        raise CertificationFailure("app PID is missing or changes during the run")
    if len(windowserver_pids) != 1 or not isinstance(next(iter(windowserver_pids)), int):
        raise CertificationFailure("WindowServer PID is missing or changes during the run")
    return t.cast(str, next(iter(marker_values))), t.cast(int, next(iter(app_pids))), t.cast(
        int, next(iter(windowserver_pids))
    )


def validate_progress(progress: list[dict[str, t.Any]]) -> None:
    milestones = {row.get("stage") for row in progress}
    missing_milestones = EXPECTED_MILESTONES - milestones
    if missing_milestones:
        raise CertificationFailure(f"missing progress milestones: {sorted(missing_milestones)}")
    for stage, expected_count in EXPECTED_MILESTONE_COUNTS.items():
        matching_rows = [row for row in progress if row.get("stage") == stage]
        if len(matching_rows) != 1:
            raise CertificationFailure(f"{stage} progress is missing or ambiguous")
        row = matching_rows[0]
        if row.get("completed_count") != expected_count or row.get("expected_count") != expected_count:
            raise CertificationFailure(f"{stage} did not prove exact delivery cardinality")
    completed: dict[str, int] = {}
    for row in progress:
        if row.get("stage") == "scenario_completed":
            scenario = row.get("scenario")
            count = row.get("completed_count")
            expected = row.get("expected_count")
            if not isinstance(scenario, str) or not isinstance(count, int) or count != expected:
                raise CertificationFailure("invalid scenario completion progress")
            completed[scenario] = count
    if completed != EXPECTED_SCENARIOS:
        raise CertificationFailure(f"wrong workload counts: {completed}")
    final_start_times = [row.get("timestamp_seconds") for row in progress if row.get("stage") == "final_window_started"]
    if len(final_start_times) != 1 or not isinstance(final_start_times[0], (int, float)):
        raise CertificationFailure("final window start is missing or ambiguous")
    final_start = float(final_start_times[0])
    if any(
        row.get("stage") in {"scenario_progress", "scenario_completed"}
        and isinstance(row.get("timestamp_seconds"), (int, float))
        and float(row["timestamp_seconds"]) > final_start
        for row in progress
    ):
        raise CertificationFailure("transition progress occurred inside the final window")


def validate_samples(rows: list[dict[str, t.Any]]) -> list[dict[str, t.Any]]:
    prior_sequence: float | None = None
    for index, row in enumerate(rows, start=1):
        for field in LIFECYCLE_FIELDS + SYSTEM_FIELDS:
            require_number(row, field, index)
        created = require_number(row, "created_total", index)
        active = require_number(row, "active_current", index)
        hidden = require_number(row, "hidden_current", index)
        undo = require_number(row, "close_undo_current", index)
        freed = require_number(row, "free_total", index)
        live = require_number(row, "live_current", index)
        manager_owned = require_number(row, "manager_owned_current", index)
        orphan = require_number(row, "orphan_current", index)
        released = require_number(row, "release_total", index)
        sequence = require_number(row, "sample_sequence", index)
        if any(value < 0 for value in (created, active, hidden, undo, freed, live, manager_owned, orphan)):
            raise CertificationFailure(f"negative lifecycle value at sample {index}")
        if live != created - freed:
            raise CertificationFailure(f"live algebra invalid at sample {index}")
        if manager_owned != active + hidden + undo:
            raise CertificationFailure(f"manager-owned algebra invalid at sample {index}")
        if orphan != live - manager_owned:
            raise CertificationFailure(f"orphan algebra invalid at sample {index}")
        if freed > released or released > created:
            raise CertificationFailure(f"release/free algebra invalid at sample {index}")
        if require_number(row, "lifecycle_valid", index) != 1:
            raise CertificationFailure(f"lifecycle validity false at sample {index}")
        if sequence <= 0 or (prior_sequence is not None and sequence < prior_sequence):
            raise CertificationFailure(f"sample sequence is stale or regressed at sample {index}")
        prior_sequence = sequence

    warmup = [row for row in rows if row.get("window") == "warmup"]
    final = [row for row in rows if row.get("window") == "final"]
    validate_window(warmup, WARMUP_SAMPLE_COUNT, "warmup")
    validate_window(final, FINAL_SAMPLE_COUNT, "final")
    require_quiescent_final_lifecycle(final)
    final_last = final[-1]
    if (
        require_number(final_last, "live_current", len(rows)) != 20
        or require_number(final_last, "manager_owned_current", len(rows)) != 20
        or require_number(final_last, "close_undo_current", len(rows)) != 0
        or require_number(final_last, "orphan_current", len(rows)) != 0
    ):
        raise CertificationFailure("final renderer population is not settled")
    return final


def require_quiescent_final_lifecycle(rows: list[dict[str, t.Any]]) -> None:
    fields = LIFECYCLE_FIELDS
    baseline = {field: require_number(rows[0], field, 1) for field in fields}
    for index, row in enumerate(rows[1:], start=2):
        for field in fields:
            if require_number(row, field, index) != baseline[field]:
                raise CertificationFailure(f"final lifecycle was not quiescent: {field} changed at sample {index}")
    if baseline["created_total"] != 50 or baseline["release_total"] != 30 or baseline["free_total"] != 30:
        raise CertificationFailure("final lifecycle totals do not match the exact soak workload")


def validate_window(rows: list[dict[str, t.Any]], expected_count: int, name: str) -> None:
    if len(rows) != expected_count:
        raise CertificationFailure(f"{name} window requires exactly {expected_count} samples, found {len(rows)}")
    for index, row in enumerate(rows, start=1):
        elapsed = require_number(row, "window_elapsed_seconds", index)
        expected = index * SAMPLE_INTERVAL_SECONDS
        if abs(elapsed - expected) > 0.5:
            raise CertificationFailure(f"{name} cadence gap at sample {index}: {elapsed} != {expected}")
        if index > 1:
            prior_timestamp = require_number(rows[index - 2], "timestamp_seconds", index - 1)
            timestamp = require_number(row, "timestamp_seconds", index)
            if abs((timestamp - prior_timestamp) - SAMPLE_INTERVAL_SECONDS) > 2.0:
                raise CertificationFailure(f"{name} actual cadence gap at sample {index}")


def ols_slope_and_ci(values: list[float]) -> dict[str, float]:
    if len(values) != FINAL_SAMPLE_COUNT:
        raise CertificationFailure("OLS requires exactly 180 values")
    x_values = [index * SAMPLE_INTERVAL_SECONDS for index in range(1, len(values) + 1)]
    x_mean = sum(x_values) / len(x_values)
    y_mean = sum(values) / len(values)
    ss_xx = sum((value - x_mean) ** 2 for value in x_values)
    slope = sum((x - x_mean) * (y - y_mean) for x, y in zip(x_values, values)) / ss_xx
    intercept = y_mean - slope * x_mean
    residual_sum_squares = sum(
        (y - (intercept + slope * x)) ** 2 for x, y in zip(x_values, values)
    )
    standard_error = math.sqrt(max(0.0, residual_sum_squares / 178.0) / ss_xx)
    margin = T_CRITICAL_95_DF_178 * standard_error
    return {"slope_per_second": slope, "lower_95": slope - margin, "upper_95": slope + margin}


def analyze(samples: list[dict[str, t.Any]], progress: list[dict[str, t.Any]]) -> dict[str, t.Any]:
    marker, app_pid, windowserver_pid = validate_identity(samples, progress)
    validate_progress(progress)
    final = validate_samples(samples)
    validate_milestone_windows(samples, progress)
    for row in final:
        row["free_memory_pressure_bytes"] = -require_number(row, "raw_free_memory_bytes", 0)
    slopes = {
        field: ols_slope_and_ci([require_number(row, field, index) for index, row in enumerate(final, start=1)])
        for field in DECISION_FIELDS
    }
    anomalies = [field for field, result in slopes.items() if result["lower_95"] > 0]
    return {
        "passed": not anomalies,
        "marker": marker,
        "app_pid": app_pid,
        "windowserver_pid": windowserver_pid,
        "final_sample_count": len(final),
        "raw_free_memory_first": final[0]["raw_free_memory_bytes"],
        "raw_free_memory_last": final[-1]["raw_free_memory_bytes"],
        "slopes": slopes,
        "anomalies": anomalies,
    }


def validate_milestone_windows(samples: list[dict[str, t.Any]], progress: list[dict[str, t.Any]]) -> None:
    def milestone_time(stage: str) -> float:
        values = [row.get("timestamp_seconds") for row in progress if row.get("stage") == stage]
        if len(values) != 1 or not isinstance(values[0], (int, float)):
            raise CertificationFailure(f"milestone {stage} is missing or ambiguous")
        return float(values[0])

    warmup = [row for row in samples if row.get("window") == "warmup"]
    final = [row for row in samples if row.get("window") == "final"]
    warmup_started = milestone_time("warmup_started")
    warmup_completed = milestone_time("warmup_completed")
    final_started = milestone_time("final_window_started")
    final_completed = milestone_time("final_window_completed")
    if require_number(warmup[0], "timestamp_seconds", 1) <= warmup_started:
        raise CertificationFailure("warmup sampling did not begin after warmup_started")
    if require_number(warmup[-1], "timestamp_seconds", len(warmup)) > warmup_completed:
        raise CertificationFailure("warmup transitions overlapped the final warmup sample")
    if require_number(final[0], "timestamp_seconds", 1) <= final_started:
        raise CertificationFailure("final sampling did not begin after final_window_started")
    if require_number(final[-1], "timestamp_seconds", len(final)) > final_completed:
        raise CertificationFailure("driver completed before the final sample")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--samples", type=pathlib.Path, required=True)
    parser.add_argument("--progress", type=pathlib.Path, required=True)
    parser.add_argument("--report", type=pathlib.Path, required=True)
    args = parser.parse_args()
    try:
        report = analyze(read_json_lines(args.samples), read_json_lines(args.progress))
        args.report.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")
        if not report["passed"]:
            print(f"renderer lifecycle soak failed: positive lower CI for {report['anomalies']}", file=sys.stderr)
            return 1
        print(json.dumps(report, sort_keys=True))
        return 0
    except (CertificationFailure, OSError) as error:
        print(f"renderer lifecycle soak certification error: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
