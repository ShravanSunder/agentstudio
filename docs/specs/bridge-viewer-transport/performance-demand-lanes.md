# BridgeViewer Performance And Demand Lanes

Date: 2026-06-28
Status: performance contract for the stream hard-cutover goal

## Purpose

BridgeViewer stream cutover is not proven by counts alone. It must prove that
File and Review interactions are fast, graphable, and attributable across
metadata streams, demand lanes, content streams, workers, and rendering.

File data includes metadata. File-tree and review-tree metadata are
Swift/native-produced file data in production. Vite/dev-server may emulate the
same stream contract for measurement, but it does not define the authoritative
metadata source.

This document defines the shared latency vocabulary, demand-lane contract,
trace shape, metric names, and proof gates for Vite first and native parity
afterward.

## Definitions

First visible content window:
The first selected/clicked file content range that is visible and readable in
the code view. Full file hydration, full syntax highlighting, and offscreen
content warming may continue after this point.

Tree scroll settled:
A scroll movement has updated the virtual range and rendered the expected
visible rows with no blank tree window.

Normal text/source file:
A text-like file that is not classified as huge or binary. Huge files are still
measured, but their full hydration is not part of the interaction hard gate.

## Hard Interaction Budgets

File view click/open of a new normal text/source file:

```text
click_to_first_visible_content_window_ms p95 < 100
click_to_first_visible_content_window_ms p99 < 200
```

Tree scroll in File view:

```text
scroll_to_visible_rows_ms p95 < 100
scroll_to_visible_rows_ms p99 < 200
blank_tree_window_count = 0
wrong_visible_row_count = 0
```

Review tree scroll and Review item click use the same metrics where the same
behavior exists. Review diff/code materialization may carry additional role
labels, but the interaction budget remains user-perceived visible readiness.

## Sample Policy

Each proof run records:

```text
sample_count
min_ms
median_ms
p95_ms
p99_ms
max_ms
failure_count
blank_window_count
wrong_visible_row_count
scenario_id
run_marker
browser_or_native_runtime
worker_mode
commit_sha
```

Minimum automated sample count before treating percentiles as proof:

```text
file_click_samples >= 100
scroll_samples >= 100
```

If a local fast loop uses fewer samples for debugging, the artifact must mark
the run as exploratory and must not satisfy the final performance gate.

## Demand Lanes

Demand lanes are a scheduling contract, not just labels.

The lane vocabulary applies to two different work classes:

```text
metadata interest
  BridgeWeb -> Swift provider as compact control state.
  It prioritizes which metadata frames Swift emits next on the persistent
  metadata stream.

content demand
  BridgeWeb -> resource executor / ContentStreamPath.
  It prioritizes descriptor-backed file/diff/body bytes.
```

Metadata interest is not a JS metadata fetch and not a browser-side file-tree
scan. Content demand is not allowed to block selected/visible metadata.

```text
foreground
  selected/clicked file or review item metadata and content
  must not starve behind visible, nearby, speculative, or idle work

active
  already-open active content refresh or continuation work
  must stay below foreground and above visible work
  measured separately so active pressure cannot hide starvation

visible
  metadata and content for rows/items currently visible in the viewport
  must settle fast enough to preserve scroll interaction

nearby
  adjacent likely-next metadata and content
  may defer under foreground/visible pressure

speculative
  prediction work
  may be dropped freely under pressure

idle
  remaining manifest completion and warming only
  never blocks foreground or visible
```

Queue timing gates:

```text
foreground_queue_wait_ms p95 < 32
foreground_queue_wait_ms p99 < 64
visible_queue_wait_ms p95 < 64
visible_queue_wait_ms p99 < 100
```

Nearby, speculative, and idle are measured but not hard-gated except that they
must not worsen foreground or visible p95/p99.

## Required Trace Shape

Trace spans must stitch a user action through the system. Use one run marker
and one action id per interaction sample.

```text
bridge.page_load
  bridge.intake.frame
    bridge.metadata.apply
      bridge.projection.input_build
        bridge.worker.projection
          bridge.projection.store_apply
            bridge.render.first_useful

bridge.file_click
  bridge.selection.commit
    bridge.demand.enqueue
      bridge.demand.dispatch
        bridge.content.fetch
          bridge.content.first_window_visible
            bridge.worker.highlight_or_materialize

bridge.tree_scroll
  bridge.virtual_range.update
    bridge.metadata_interest.update
      bridge.intake.frame
        bridge.metadata.apply
          bridge.visible_rows.render
            bridge.demand.enqueue_visible_content
```

Required trace attributes are low cardinality:

```text
viewer=file|review
protocol=worktree-file|review
runtime=vite|native
lane=foreground|active|visible|nearby|speculative|idle
phase=<bounded phase vocabulary>
result=success|deferred|stale|aborted|failed
transport=intake|content|worker|rpc
work_class=metadata|content
generation_relation=current|stale|unknown
file_size_bucket=small|medium|large|huge|unknown
worker_mode=on|off
loaded_by=startup_window|foreground|visible|nearby|speculative|idle|delta|reset|replacement
```

Forbidden trace or metric attributes:

```text
raw path
item id
content hash
raw URL
historical raw agentstudio.bridge.lane attribute
prompt
payload text
raw error
token or secret
```

Browser/native telemetry must use the safe source attribute
`agentstudio.bridge.demand.lane` and may project it to a metric label named
`lane`. The older generic `agentstudio.bridge.lane` attribute remains
forbidden because it is too broad for the strict validator contract.

## Required Metrics

Latency histograms:

```text
agentstudio_performance_event_elapsed_ms_bucket{event="performance.bridge.web.page_first_tree_visible", ...}
agentstudio_performance_event_elapsed_ms_bucket{event="performance.bridge.web.page_selected_content_ready", ...}
agentstudio_performance_event_elapsed_ms_bucket{event="performance.bridge.web.metadata_apply", ...}
agentstudio_performance_event_elapsed_ms_bucket{event="performance.bridge.web.metadata_interest_to_frame", ...}
agentstudio_performance_event_elapsed_ms_bucket{event="performance.bridge.native.metadata_open_to_first_window", ...}
agentstudio_performance_event_elapsed_ms_bucket{event="performance.bridge.native.metadata_full_manifest_complete", ...}
agentstudio_performance_event_elapsed_ms_bucket{event="performance.bridge.web.projection_input_build", ...}
agentstudio_performance_event_elapsed_ms_bucket{event="performance.bridge.web.projection_worker", ...}
agentstudio_performance_event_elapsed_ms_bucket{event="performance.bridge.web.projection_store_apply", ...}
agentstudio_performance_event_elapsed_ms_bucket{event="performance.bridge.web.click_to_first_visible_content_window", ...}
agentstudio_performance_event_elapsed_ms_bucket{event="performance.bridge.web.scroll_to_visible_rows", ...}
agentstudio_performance_event_elapsed_ms_bucket{event="performance.bridge.viewer.demand_queue_wait", lane="...", ...}
agentstudio_performance_event_elapsed_ms_bucket{event="performance.bridge.viewer.demand_inflight", lane="...", ...}
agentstudio_performance_event_elapsed_ms_bucket{event="performance.bridge.web.content_fetch", ...}
agentstudio_performance_event_elapsed_ms_bucket{event="performance.bridge.web.content_first_window_materialize", ...}
```

The contract names above are the required cross-runtime histogram surface for
Vite and native. Exact dashboard aliases such as
`bridge_click_to_first_visible_content_window_ms` may be added later, but they
must be aliases over the same bounded event histogram data rather than a
separate Vite-only metric path.

Counters and gauges:

```text
bridge_demand_queue_depth
bridge_demand_inflight_count
bridge_demand_inflight_bytes
bridge_demand_deferred_total
bridge_demand_stale_drop_total
bridge_demand_abort_total
bridge_demand_lane_upgrade_total
bridge_blank_tree_window_total
bridge_wrong_visible_row_total
bridge_metadata_revision_gap_total
bridge_metadata_interest_update_total
bridge_metadata_interest_drop_total
bridge_metadata_manifest_expected_total
bridge_metadata_manifest_emitted_total
bridge_metadata_manifest_remaining_total
bridge_metadata_manifest_completion_total
```

Percentile reports are derived from histogram samples in the verifier artifact
and, where available, VictoriaMetrics.

## Proof Scenarios

Vite first:

```text
page-load-current-worktree
file-click-random-100
tree-scroll-sampled-100
review-click-random-100
review-tree-scroll-sampled-100
demand-pressure-no-starvation
```

Native parity:

```text
native-headless-manifest-completeness
native-headless-metadata-lane-order
native-headless-demand-pressure-no-starvation
native-wkwebview-page-load
native-wkwebview-file-click
native-wkwebview-tree-scroll
native-victoria-trace-stitching
```

## Passing Criteria

Vite performance proof passes only when:

```text
100 file click samples are recorded
100 tree scroll samples are recorded
p95 and p99 are computed for the hard interaction metrics
File click p95 < 100ms and p99 < 200ms
Tree scroll p95 < 100ms and p99 < 200ms
blank_tree_window_count = 0
wrong_visible_row_count = 0
foreground and visible queue wait percentiles are reported
foreground/visible metadata interest-to-frame percentiles are reported
content latency is separated from metadata latency
artifact records run marker, runtime, worker mode, and commit SHA
```

Native performance proof passes only when the same metric names and scenario
shape are visible through the native WKWebView path and Victoria-backed proof.

Headless Swift-plane proof is required before native WKWebView proof can close:

```text
all non-ignored files in the current worktree are counted as expected metadata
all expected rows eventually appear in emitted metadata frames
each emitted row records loaded_by and lane lineage
selected/open and visible metadata beat idle continuation under pressure
full-manifest completion has p95/p99 and no-starvation progress counters
content descriptor demand is measured separately from metadata frame emission
p95/p99 are reported for open-to-first-window, metadata-interest-to-frame,
full-manifest-complete, queue wait by lane, metadata apply, and content fetch
```
