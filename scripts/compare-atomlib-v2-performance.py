#!/usr/bin/env python3
import math
import pathlib
import sys

baseline_workload_path = pathlib.Path(sys.argv[1])
after_workload_path = pathlib.Path(sys.argv[2])
baseline_interaction_path = pathlib.Path(sys.argv[3])
after_interaction_path = pathlib.Path(sys.argv[4])
output_path = pathlib.Path(sys.argv[5])

REQUIRED_IMPROVEMENT_PERCENT = 50.0
MAX_REGRESSION_PERCENT = 10.0

COMMAND_BAR_SURFACES = ["performance.commandbar.items"]
COMMAND_BAR_FILTER_STABILITY_SURFACES = ["performance.commandbar.filter"]
REPO_FANOUT_SURFACES = [
    "performance.tabbar.refresh",
    "performance.sidebar.projection",
    "performance.sidebar.row_index",
    "performance.topology.repo_and_worktree",
]
COORDINATOR_SURFACES = ["performance.coordinator.write"]
REQUIRED_NUMERIC_FIELDS = [
    "victoria_metrics_count",
    "victoria_logs_count",
    "jsonl_count",
    "elapsed_ms.p95",
    "elapsed_ms.max",
]
REQUIRED_BOOLEAN_FIELDS = [
    "elapsed_ms.p95_unavailable",
]


def parse_summary(path: pathlib.Path) -> dict[str, str]:
    values: dict[str, str] = {}
    for raw_line in path.read_text(encoding="utf-8").splitlines():
        if "=" not in raw_line:
            continue
        key, value = raw_line.split("=", 1)
        values[key.strip()] = value.strip()
    return values


def numeric(values: dict[str, str], key: str) -> float:
    raw_value = values.get(key)
    if raw_value is None or raw_value == "":
        return 0.0
    try:
        value = float(raw_value)
    except ValueError:
        return 0.0
    return value if math.isfinite(value) else 0.0


def boolean(values: dict[str, str], key: str) -> bool:
    return values.get(key, "false").lower() == "true"


def improvement_percent(before: float, after: float) -> float:
    if before <= 0:
        return 0.0 if after <= 0 else -100.0
    return ((before - after) / before) * 100.0


def regression_percent(before: float, after: float) -> float:
    return -improvement_percent(before, after)


def metric_key(surface: str, metric: str) -> str:
    if metric == "count":
        return f"{surface}.victoria_metrics_count"
    if metric == "p95":
        return f"{surface}.elapsed_ms.p95"
    if metric == "max":
        return f"{surface}.elapsed_ms.max"
    raise ValueError(metric)


def surface_key(surface: str, field: str) -> str:
    return f"{surface}.{field}"


def required_numeric(
    values: dict[str, str],
    key: str,
    label: str,
    failures: list[str],
) -> float:
    raw_value = values.get(key)
    if raw_value is None or raw_value == "":
        failures.append(f"missing required metric {key} in {label}")
        return 0.0
    try:
        value = float(raw_value)
    except ValueError:
        failures.append(f"invalid required metric {key} in {label}: {raw_value}")
        return 0.0
    if not math.isfinite(value):
        failures.append(f"non-finite required metric {key} in {label}: {raw_value}")
        return 0.0
    return value


def validate_required_surface_fields(
    label: str,
    values: dict[str, str],
    surfaces: list[str],
) -> list[str]:
    failures: list[str] = []
    for surface in surfaces:
        for field in REQUIRED_NUMERIC_FIELDS:
            required_numeric(values, surface_key(surface, field), label, failures)
        for field in REQUIRED_BOOLEAN_FIELDS:
            key = surface_key(surface, field)
            raw_value = values.get(key)
            if raw_value is None or raw_value == "":
                failures.append(f"missing required metric {key} in {label}")
            elif raw_value.lower() not in ["true", "false"]:
                failures.append(f"invalid required metric {key} in {label}: {raw_value}")
    return failures


def validate_command_bar_fingerprint(
    before_values: dict[str, str],
    after_values: dict[str, str],
) -> list[str]:
    failures: list[str] = []
    key = "performance.commandbar.filter.query_character.max"
    before = required_numeric(before_values, key, "baseline interaction", failures)
    after = required_numeric(after_values, key, "after interaction", failures)
    if not failures and before != after:
        failures.append(f"command-bar interaction fingerprint changed: {key} {before:g} -> {after:g}")
    return failures


def validate_instrumentation_continuity(
    label: str,
    values: dict[str, str],
    surfaces: list[str],
) -> list[str]:
    failures: list[str] = []
    for surface in surfaces:
        metrics_count = numeric(values, surface_key(surface, "victoria_metrics_count"))
        logs_count = numeric(values, surface_key(surface, "victoria_logs_count"))
        jsonl_count = numeric(values, surface_key(surface, "jsonl_count"))
        if metrics_count <= 0 and (logs_count > 0 or jsonl_count > 0):
            failures.append(
                f"instrumentation loss: {surface} in {label} has logs/jsonl events but no Victoria metrics"
            )
    return failures


def p95_available(before_values: dict[str, str], after_values: dict[str, str], surface: str) -> bool:
    return not (
        boolean(before_values, f"{surface}.elapsed_ms.p95_unavailable")
        or boolean(after_values, f"{surface}.elapsed_ms.p95_unavailable")
    )


def improvement_line(before_values: dict[str, str], after_values: dict[str, str], surface: str, metric: str) -> str:
    before = numeric(before_values, metric_key(surface, metric))
    after = numeric(after_values, metric_key(surface, metric))
    return f"{metric_key(surface, metric)}: {before:g} -> {after:g} ({improvement_percent(before, after):.1f}% better)"


def surface_has_required_win(before_values: dict[str, str], after_values: dict[str, str], surface: str) -> bool:
    count_before = numeric(before_values, metric_key(surface, "count"))
    count_after = numeric(after_values, metric_key(surface, "count"))
    if improvement_percent(count_before, count_after) >= REQUIRED_IMPROVEMENT_PERCENT:
        return True

    if p95_available(before_values, after_values, surface):
        p95_before = numeric(before_values, metric_key(surface, "p95"))
        p95_after = numeric(after_values, metric_key(surface, "p95"))
        return improvement_percent(p95_before, p95_after) >= REQUIRED_IMPROVEMENT_PERCENT

    max_before = numeric(before_values, metric_key(surface, "max"))
    max_after = numeric(after_values, metric_key(surface, "max"))
    return improvement_percent(max_before, max_after) >= REQUIRED_IMPROVEMENT_PERCENT


def regression_failures(
    before_values: dict[str, str],
    after_values: dict[str, str],
    surfaces: list[str],
    metrics: list[str],
) -> list[str]:
    failures: list[str] = []
    for surface in surfaces:
        for metric in metrics:
            if metric == "p95" and not p95_available(before_values, after_values, surface):
                continue
            before = numeric(before_values, metric_key(surface, metric))
            after = numeric(after_values, metric_key(surface, metric))
            if before <= 0 and after <= 0:
                continue
            regression = regression_percent(before, after)
            if regression > MAX_REGRESSION_PERCENT:
                failures.append(
                    f"{metric_key(surface, metric)} regressed {regression:.1f}% ({before:g} -> {after:g})"
                )
    return failures


baseline_workload = parse_summary(baseline_workload_path)
after_workload = parse_summary(after_workload_path)
baseline_interaction = parse_summary(baseline_interaction_path)
after_interaction = parse_summary(after_interaction_path)

failures: list[str] = []

failures.extend(validate_required_surface_fields(
    "baseline interaction",
    baseline_interaction,
    [*COMMAND_BAR_SURFACES, *COMMAND_BAR_FILTER_STABILITY_SURFACES],
))
failures.extend(validate_required_surface_fields(
    "after interaction",
    after_interaction,
    [*COMMAND_BAR_SURFACES, *COMMAND_BAR_FILTER_STABILITY_SURFACES],
))
failures.extend(validate_required_surface_fields(
    "baseline workload",
    baseline_workload,
    [*REPO_FANOUT_SURFACES, *COORDINATOR_SURFACES],
))
failures.extend(validate_required_surface_fields(
    "after workload",
    after_workload,
    [*REPO_FANOUT_SURFACES, *COORDINATOR_SURFACES],
))
failures.extend(validate_command_bar_fingerprint(baseline_interaction, after_interaction))
failures.extend(validate_instrumentation_continuity(
    "baseline interaction",
    baseline_interaction,
    [*COMMAND_BAR_SURFACES, *COMMAND_BAR_FILTER_STABILITY_SURFACES],
))
failures.extend(validate_instrumentation_continuity(
    "after interaction",
    after_interaction,
    [*COMMAND_BAR_SURFACES, *COMMAND_BAR_FILTER_STABILITY_SURFACES],
))
failures.extend(validate_instrumentation_continuity(
    "baseline workload",
    baseline_workload,
    [*REPO_FANOUT_SURFACES, *COORDINATOR_SURFACES],
))
failures.extend(validate_instrumentation_continuity(
    "after workload",
    after_workload,
    [*REPO_FANOUT_SURFACES, *COORDINATOR_SURFACES],
))

if not any(surface_has_required_win(baseline_interaction, after_interaction, surface) for surface in COMMAND_BAR_SURFACES):
    failures.append(
        "command-bar interaction did not improve performance.commandbar.items count or p95 by >=50%"
    )

if not any(surface_has_required_win(baseline_workload, after_workload, surface) for surface in REPO_FANOUT_SURFACES):
    failures.append(
        "repo-cache fanout did not improve any required surface count or p95 by >=50%"
    )

failures.extend(regression_failures(
    baseline_interaction,
    after_interaction,
    COMMAND_BAR_SURFACES,
    ["count", "p95", "max"],
))
failures.extend(regression_failures(
    baseline_interaction,
    after_interaction,
    COMMAND_BAR_FILTER_STABILITY_SURFACES,
    ["count", "p95"],
))
failures.extend(regression_failures(
    baseline_workload,
    after_workload,
    [*REPO_FANOUT_SURFACES, *COORDINATOR_SURFACES],
    ["count", "p95", "max"],
))

lines: list[str] = []
lines.append("AtomLib v2 final performance comparison")
lines.append("")
lines.append(f"baseline_workload={baseline_workload_path}")
lines.append(f"after_workload={after_workload_path}")
lines.append(f"baseline_interaction={baseline_interaction_path}")
lines.append(f"after_interaction={after_interaction_path}")
lines.append("")
lines.append("Equivalent command-bar interaction")
for surface in [*COMMAND_BAR_SURFACES, *COMMAND_BAR_FILTER_STABILITY_SURFACES]:
    lines.append(improvement_line(baseline_interaction, after_interaction, surface, "count"))
    lines.append(improvement_line(baseline_interaction, after_interaction, surface, "p95"))
    lines.append(improvement_line(baseline_interaction, after_interaction, surface, "max"))
lines.append(
    "performance.commandbar.filter.query_character.max: "
    f"{numeric(baseline_interaction, 'performance.commandbar.filter.query_character.max'):g} -> "
    f"{numeric(after_interaction, 'performance.commandbar.filter.query_character.max'):g}"
)
lines.append("performance.commandbar.filter.elapsed_ms.max is informational; filter count and p95 are gated.")
lines.append("")
lines.append("Full git-refresh workload")
for surface in REPO_FANOUT_SURFACES:
    lines.append(improvement_line(baseline_workload, after_workload, surface, "count"))
    lines.append(improvement_line(baseline_workload, after_workload, surface, "p95"))
    lines.append(improvement_line(baseline_workload, after_workload, surface, "max"))
lines.append("")
lines.append("Coordinator workload")
for surface in COORDINATOR_SURFACES:
    lines.append(improvement_line(baseline_workload, after_workload, surface, "count"))
    lines.append(improvement_line(baseline_workload, after_workload, surface, "p95"))
    lines.append(improvement_line(baseline_workload, after_workload, surface, "max"))
lines.append("")
lines.append("Proof verdict")
if failures:
    lines.append("not_ready")
    for failure in failures:
        lines.append(f"failure: {failure}")
else:
    lines.append("ready")
    lines.append("command-bar interaction threshold met")
    lines.append("repo-cache fanout threshold met")
    lines.append("no targeted regression exceeded 10%")

output_path.write_text("\n".join(lines) + "\n", encoding="utf-8")

if failures:
    for failure in failures:
        print(f"performance comparison failed: {failure}", file=sys.stderr)
    sys.exit(1)
