#!/usr/bin/env python3
import math
import pathlib
import sys
import typing

baseline_workload_path = pathlib.Path(sys.argv[1])
after_workload_path = pathlib.Path(sys.argv[2])
baseline_interaction_path = pathlib.Path(sys.argv[3])
after_interaction_path = pathlib.Path(sys.argv[4])
output_path = pathlib.Path(sys.argv[5])

COMMAND_BAR_SURFACES = ["performance.commandbar.items"]
COMMAND_BAR_FILTER_STABILITY_SURFACES = ["performance.commandbar.filter"]
REPO_FANOUT_SURFACES = [
    "performance.tabbar.refresh",
    "performance.sidebar.projection",
    "performance.sidebar.row_index",
]
COORDINATOR_SURFACES = ["performance.coordinator.write"]
CANDIDATE_TAB_BAR_PHASE_SURFACES = [
    "performance.tabbar.capture",
    "performance.tabbar.worker",
    "performance.tabbar.current",
    "performance.tabbar.terminal",
    "performance.tabbar.publication",
    "performance.tabbar.visible",
]
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


def required_string(
    values: dict[str, str],
    key: str,
    label: str,
    failures: list[str],
) -> typing.Optional[str]:
    value = values.get(key, "").strip()
    if not value:
        failures.append(f"missing required provenance {key} in {label}")
        return None
    return value


def required_positive_number(
    values: dict[str, str],
    key: str,
    label: str,
    failures: list[str],
) -> typing.Optional[float]:
    failure_count = len(failures)
    value = required_numeric(values, key, label, failures)
    if len(failures) != failure_count:
        return None
    if value <= 0:
        failures.append(f"{key} must be positive in {label}: {value:g}")
        return None
    return value


def required_nonnegative_number(
    values: dict[str, str],
    key: str,
    label: str,
    failures: list[str],
) -> typing.Optional[float]:
    failure_count = len(failures)
    value = required_numeric(values, key, label, failures)
    if len(failures) != failure_count:
        return None
    if value < 0:
        failures.append(f"{key} must be nonnegative in {label}: {value:g}")
        return None
    return value


def validate_common_evidence(
    label: str,
    values: dict[str, str],
) -> list[str]:
    failures: list[str] = []
    required_string(values, "source_digest", label, failures)
    required_string(values, "executable_digest", label, failures)
    required_string(values, "workload_fingerprint", label, failures)
    trace_tags = required_string(values, "trace_tags", label, failures)
    if trace_tags is not None and "performance" not in [tag.strip() for tag in trace_tags.split(",")]:
        failures.append(f"trace_tags must contain performance in {label}: {trace_tags}")

    launch_method = values.get("launch_method", "")
    if launch_method != "launchservices":
        failures.append(f"requires launch_method=launchservices in {label}: {launch_method or '<missing>'}")
    activation_mode = values.get("activation_mode", "")
    if activation_mode != "background":
        failures.append(f"requires activation_mode=background in {label}: {activation_mode or '<missing>'}")

    required_positive_number(values, "issued_interaction_count", label, failures)
    required_nonnegative_number(values, "regression_boundary_percent", label, failures)

    for key in [
        "final_tab_count_equivalent",
        "final_active_tab_equivalent",
        "final_membership_equivalent",
    ]:
        if values.get(key, "").lower() != "true":
            failures.append(f"{key} must be true in {label}")
    return failures


def validate_candidate_evidence(
    label: str,
    values: dict[str, str],
) -> list[str]:
    failures: list[str] = []

    capture_count = required_positive_number(values, "performance.tabbar.capture_count", label, failures)
    terminal_count = required_positive_number(values, "performance.tabbar.terminal_count", label, failures)
    if capture_count is not None and terminal_count is not None and capture_count != terminal_count:
        failures.append(
            f"tab bar lifecycle continuity failed in {label}: "
            f"capture={capture_count:g} terminal={terminal_count:g}"
        )

    if values.get("performance.tabbar.lifecycle_exact", "").lower() != "true":
        failures.append(f"performance.tabbar.lifecycle_exact must be true in {label}")
    lifecycle_count_fields = [
        ("performance.tabbar.duplicate_capture_sequence_count", "duplicate capture sequences"),
        ("performance.tabbar.duplicate_terminal_sequence_count", "duplicate terminal sequences"),
        ("performance.tabbar.missing_terminal_sequence_count", "missing terminal sequences"),
        ("performance.tabbar.unexpected_terminal_sequence_count", "unexpected terminal sequences"),
        ("performance.tabbar.invalid_terminal_outcome_count", "invalid terminal outcomes"),
    ]
    for key, description in lifecycle_count_fields:
        count = required_nonnegative_number(values, key, label, failures)
        if count is not None and count != 0:
            failures.append(f"tab bar lifecycle has {count:g} {description} in {label}")

    dropped_count = required_nonnegative_number(
        values,
        "agentstudio.performance.trace_queue.dropped_record.count",
        label,
        failures,
    )
    if dropped_count is not None and dropped_count != 0:
        failures.append(f"trace queue dropped {dropped_count:g} records in {label}")
    required_nonnegative_number(
        values,
        "agentstudio.performance.trace_queue.high_watermark",
        label,
        failures,
    )
    return failures


def validate_matched_value(
    left_values: dict[str, str],
    right_values: dict[str, str],
    key: str,
    mismatch_label: str,
) -> list[str]:
    left = left_values.get(key)
    right = right_values.get(key)
    if left and right and left != right:
        return [f"{mismatch_label}: {left} -> {right}"]
    return []


def validate_provenance_matches(
    baseline_workload: dict[str, str],
    candidate_workload: dict[str, str],
    baseline_interaction: dict[str, str],
    candidate_interaction: dict[str, str],
) -> list[str]:
    failures: list[str] = []
    for side, workload, interaction in [
        ("baseline", baseline_workload, baseline_interaction),
        ("candidate", candidate_workload, candidate_interaction),
    ]:
        for key in ["source_digest", "executable_digest"]:
            failures.extend(validate_matched_value(
                workload,
                interaction,
                key,
                f"{side} {key} differs between workload and interaction",
            ))

    for lane, baseline, candidate in [
        ("workload", baseline_workload, candidate_workload),
        ("interaction", baseline_interaction, candidate_interaction),
    ]:
        failures.extend(validate_matched_value(
            baseline,
            candidate,
            "workload_fingerprint",
            f"{lane} workload_fingerprint changed",
        ))
        baseline_count = numeric(baseline, "issued_interaction_count")
        candidate_count = numeric(candidate, "issued_interaction_count")
        boundary = numeric(baseline, "regression_boundary_percent")
        if baseline_count > 0 and candidate_count > 0:
            drift_percent = abs(candidate_count - baseline_count) / baseline_count * 100
            if drift_percent > boundary:
                failures.append(
                    f"{lane} issued_interaction_count drift exceeded {boundary:g}%: "
                    f"{baseline_count:g} -> {candidate_count:g} ({drift_percent:.1f}%)"
                )

    reference_trace_tags = baseline_workload.get("trace_tags")
    for label, values in [
        ("candidate workload", candidate_workload),
        ("baseline interaction", baseline_interaction),
        ("candidate interaction", candidate_interaction),
    ]:
        trace_tags = values.get("trace_tags")
        if reference_trace_tags and trace_tags and trace_tags != reference_trace_tags:
            failures.append(
                f"trace_tags changed between baseline workload and {label}: "
                f"{reference_trace_tags} -> {trace_tags}"
            )

    reference_boundary = baseline_workload.get("regression_boundary_percent")
    for label, values in [
        ("candidate workload", candidate_workload),
        ("baseline interaction", baseline_interaction),
        ("candidate interaction", candidate_interaction),
    ]:
        boundary = values.get("regression_boundary_percent")
        if reference_boundary and boundary and boundary != reference_boundary:
            failures.append(
                f"regression_boundary_percent differs between baseline workload and {label}: "
                f"{reference_boundary} -> {boundary}"
            )
    return failures


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


def validate_command_bar_query_evidence(
    before_values: dict[str, str],
    after_values: dict[str, str],
) -> list[str]:
    failures: list[str] = []
    key = "performance.commandbar.filter.query_character.max"
    required_numeric(before_values, key, "baseline interaction", failures)
    required_numeric(after_values, key, "after interaction", failures)
    return failures


def validate_candidate_phase_evidence(
    label: str,
    values: dict[str, str],
) -> list[str]:
    failures = validate_required_surface_fields(label, values, CANDIDATE_TAB_BAR_PHASE_SURFACES)
    for surface in CANDIDATE_TAB_BAR_PHASE_SURFACES:
        count = numeric(values, surface_key(surface, "victoria_metrics_count"))
        if count <= 0:
            failures.append(f"candidate phase metric {surface} must be present in {label}")
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


def regression_failures(
    before_values: dict[str, str],
    after_values: dict[str, str],
    surfaces: list[str],
    metrics: list[str],
    regression_boundary_percent: float,
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
            if regression > regression_boundary_percent:
                failures.append(
                    f"{metric_key(surface, metric)} regressed {regression:.1f}% ({before:g} -> {after:g})"
                )
    return failures


baseline_workload = parse_summary(baseline_workload_path)
after_workload = parse_summary(after_workload_path)
baseline_interaction = parse_summary(baseline_interaction_path)
after_interaction = parse_summary(after_interaction_path)

failures: list[str] = []

for label, values in [
    ("baseline workload", baseline_workload),
    ("candidate workload", after_workload),
    ("baseline interaction", baseline_interaction),
    ("candidate interaction", after_interaction),
]:
    failures.extend(validate_common_evidence(label, values))
for label, values in [
    ("candidate workload", after_workload),
    ("candidate interaction", after_interaction),
]:
    failures.extend(validate_candidate_evidence(label, values))
failures.extend(validate_provenance_matches(
    baseline_workload,
    after_workload,
    baseline_interaction,
    after_interaction,
))

boundary_failures: list[str] = []
regression_boundary_percent = required_nonnegative_number(
    baseline_workload,
    "regression_boundary_percent",
    "baseline workload",
    boundary_failures,
)

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
failures.extend(validate_candidate_phase_evidence("after workload", after_workload))
failures.extend(validate_command_bar_query_evidence(baseline_interaction, after_interaction))
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
    [*REPO_FANOUT_SURFACES, *COORDINATOR_SURFACES, *CANDIDATE_TAB_BAR_PHASE_SURFACES],
))

if regression_boundary_percent is not None:
    failures.extend(regression_failures(
        baseline_interaction,
        after_interaction,
        COMMAND_BAR_SURFACES,
        ["count", "p95", "max"],
        regression_boundary_percent,
    ))
    failures.extend(regression_failures(
        baseline_interaction,
        after_interaction,
        COMMAND_BAR_FILTER_STABILITY_SURFACES,
        ["count", "p95"],
        regression_boundary_percent,
    ))
    failures.extend(regression_failures(
        baseline_workload,
        after_workload,
        [*REPO_FANOUT_SURFACES, *COORDINATOR_SURFACES],
        ["count", "p95", "max"],
        regression_boundary_percent,
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
    lines.append(f"frozen regression boundary: {regression_boundary_percent:g}%")
    lines.append("all provenance, completeness, final-state, and regression gates passed")

output_path.write_text("\n".join(lines) + "\n", encoding="utf-8")

if failures:
    for failure in failures:
        print(f"performance comparison failed: {failure}", file=sys.stderr)
    sys.exit(1)
