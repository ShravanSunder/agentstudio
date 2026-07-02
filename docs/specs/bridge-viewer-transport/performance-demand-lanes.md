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
foreground_queue_wait_ms p95 < 16
foreground_queue_wait_ms p99 < 32
visible_queue_wait_ms p95 < 32
visible_queue_wait_ms p99 < 64
```

Nearby, speculative, and idle are measured but not hard-gated except that they
must not worsen foreground or visible p95/p99.

## Native Metadata Production Scheduler

Demand lanes on the native side are a real scheduler, not frame labels.
The Swift provider must route all metadata production for an accepted source
through a generic, protocol-agnostic lane scheduler:

```text
scheduler ownership
  one scheduler instance per pane; jobs are keyed by protocol id plus
  source/generation identity. worktree-file and review metadata interest
  share the same generic scheduler component. lane names stay generic;
  the scheduler never learns tree/review semantics, and it never learns
  active-context state: pausing an inactive context's production is the
  interest producer's responsibility under R18, not the scheduler's.

lane queues
  per-lane FIFO queues with strict priority
  foreground > active > visible > nearby > speculative > idle
  within a lane, jobs order by arrival; protocol id is identity and
  stale-drop scope, never priority.

idle continuation
  full-manifest continuation is enqueued as idle-lane work inside the same
  scheduler. a free-running continuation loop outside the scheduler is a
  contract violation. only protocols with manifest continuation supply
  idle jobs; review supplies none today.

preemption granularity
  idle work executes in bounded batches. a queued higher-lane job waits at
  most one bounded idle batch before dequeue. the idle batch bound is an
  AppPolicies constant sized so one batch cannot consume the foreground
  queue-wait budget.

idle no-starvation budget
  when higher lanes are active, the scheduler must still service at least
  one idle batch per N higher-lane jobs drained. N is an AppPolicies
  constant, not a literal in production or proof code. N counts drained
  higher-lane jobs per pane.

queue wait
  measured per job as enqueue-to-dequeue by the scheduler's own
  instrumentation and emitted per lane. a request-to-delivered-frame span
  is not queue wait and must not be labeled, aliased, or artifact-keyed as
  queue wait.

stale drop
  queued jobs bound to a replaced source/generation are dropped and counted.

test seams
  the scheduler accepts an injected clock and a test-drivable continuation
  step/gate as ordinary constructor parameters. proof drives contention
  deterministically through these seams with no wall-clock sleeps. `#if
  DEBUG` production hooks are prohibited.
```

Per-protocol dispatch gates: each protocol id has a dispatch gate that
opens when the browser's intake-ready arrives for the current stream
identity and closes on teardown or when a new source generation supersedes
the stream. Closed-gate jobs hold in their lanes without blocking other
protocols. Failed delivery closes the protocol's gate and retains the
failed job at the front of its lane with its sequence reservation rolled
back, so reopening the gate (a fresh intake-ready) retries in order and
redelivers with the same sequence — a retry must never leave a sequence
gap. Retained jobs re-enter the queue at retention time, so retry
queue-wait measures requeue-to-dequeue rather than folding the gate-closed
recovery gap into lane percentiles. Symmetrically, jobs held behind a
closed gate are re-stamped when the gate opens, so queue wait measures
open-to-dequeue: browser boot and recovery parking are not scheduler
pressure.

Scheduler queues are bounded per lane
(`AppPolicies.Bridge.metadataSchedulerMaxQueuedJobsPerLane`). A pane whose
gate never reopens must not grow its queues without bound from
watch-driven producers: when a lane exceeds its cap, the scheduler drops
that lane's oldest job and emits an overflow-drop fact
(`performance.bridge.swift.metadata_scheduler_overflow_drop`, per-lane),
so the loss is observable and never silent. Newest facts win; recovery is
the normal reset/reopen path, which rebuilds from the manifest. Overflow
drops are a wedged-pane safety valve — a healthy pane must never emit
them, and the gated benchmark treats any overflow drop during a proof run
as a failure.

Manifest index contract:

```text
index ownership
  a single-writer owner holds the manifest index for the accepted source
  generation on one isolation domain off the MainActor. enumeration build,
  watch-event patches, and interest reads all go through that owner. the
  stateless materializer is not the index owner. source reset or a
  generation bump discards and rebuilds the index.

index content and scope
  the index holds compact ordered path/key entries plus the facts needed
  to serve tree rows; it does not hold hydrated file bodies. the index and
  the completeness expected set are scoped identically: pathScope
  intersected with the publication policy.

index ordering
  manifest ordering is deterministic and policy-owned. a generic provider
  must not encode a specific repository's folder names in its ordering
  policy.

interest serving
  metadata interest is served from the index in O(requested paths) plus a
  freshness stat of the requested paths. serving interest must not
  re-enumerate the worktree. when the stat disagrees with the index, stat
  truth wins: the provider never emits a stale upsert; it patches the
  index and emits the corrected row or a removal delta instead.

live updates
  filesystem/git watch events patch the index and emit delta-lineage rows.

expected set
  manifest-completeness truth is a files-only path-set comparison with an
  empty symmetric difference, never a count equality, and never the
  provider's own emission counters. until AgentStudioGit ships
  tracked-path enumeration, the expected set is: an independent test-owned
  filesystem walk (structural exclusions only: `.git` internals and nested
  worktree roots) minus the AgentStudioGit (libgit2) ignored set. when
  `trackedPaths` lands, the expected set cuts over to git truth:
  trackedPaths union untracked-non-ignored. publication policy is
  git-truth only per the Worktree/File protocol spec; directory rows are
  derived from file parents on both sides of the comparison.
```

Worktree/File metadata lineage (`loaded_by`, `lane`) is typed frame-level
metadata on snapshot/window/delta frames, with a one-lineage-per-frame
invariant: emitters must not coalesce rows of differing lineage into a
single frame; they split frames per lineage instead. Per-row duplicated
lineage inside encoded Worktree/File wire frames and post-hoc JSON rewriting
of encoded frames are contract violations. Browser materializers may derive
per-item lineage facts from accepted frame-level lineage for classification
and proof. Review's existing per-item wire lineage is an accepted residual
outside this cutover; changing it belongs to a later review-protocol slice.

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
agentstudio_performance_event_elapsed_ms_bucket{event="performance.bridge.native.metadata_interest_to_frame", ...}
agentstudio_performance_event_elapsed_ms_bucket{event="performance.bridge.native.metadata_window_produce", ...}
agentstudio_performance_event_elapsed_ms_bucket{event="performance.bridge.web.projection_input_build", ...}
agentstudio_performance_event_elapsed_ms_bucket{event="performance.bridge.web.projection_worker", ...}
agentstudio_performance_event_elapsed_ms_bucket{event="performance.bridge.web.projection_store_apply", ...}
agentstudio_performance_event_elapsed_ms_bucket{event="performance.bridge.web.click_to_first_visible_content_window", ...}
agentstudio_performance_event_elapsed_ms_bucket{event="performance.bridge.web.scroll_to_visible_rows", ...}
agentstudio_performance_event_elapsed_ms_bucket{event="performance.bridge.swift.metadata_scheduler_queue_wait", lane="...", ...}
agentstudio_performance_event_elapsed_ms_bucket{event="performance.bridge.viewer.demand_inflight", lane="...", ...}
agentstudio_performance_event_elapsed_ms_bucket{event="performance.bridge.web.content_fetch", ...}
agentstudio_performance_event_elapsed_ms_bucket{event="performance.bridge.web.content_first_window_materialize", ...}
```

The contract names above are the required cross-runtime histogram surface for
Vite and native. Exact dashboard aliases such as
`bridge_click_to_first_visible_content_window_ms` may be added later, but they
must be aliases over the same bounded event histogram data rather than a
separate Vite-only metric path.

Measurement honesty rules:

- `performance.bridge.swift.metadata_scheduler_queue_wait{lane}` measures scheduler
  enqueue-to-dequeue only, in both runtimes. Native emits it from the generic
  lane scheduler. A runtime without a real queue must not emit or synthesize
  this metric.
- `performance.bridge.native.metadata_interest_to_frame` measures interest
  request to delivered intake frame. It legitimately includes intake-ready
  wait; it must not be renamed, aliased, or artifact-keyed as queue wait.
- `performance.bridge.web.metadata_apply` is browser-side frame apply time
  only. Native frame preparation/dispatch time is
  `performance.bridge.native.metadata_window_produce`. Neither runtime may
  report its own phase under the other runtime's metric name.
- queue-wait claims require structural evidence: per-lane sample counts
  greater than one for every hard-gated lane; under the contention
  scenario, at least one lower lane records nonzero queue wait while a
  higher lane drains; samples originate from the scheduler's own
  enqueue/dequeue instrumentation, not from intake-frame delivery
  timestamps; and for any single job, `demand_queue_wait` must not equal
  `metadata_interest_to_frame`.

Counters and gauges:

```text
bridge_demand_queue_depth
bridge_demand_inflight_count
bridge_demand_inflight_bytes
bridge_demand_deferred_total
bridge_demand_stale_drop_total
bridge_demand_overflow_drop_total
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
native-wkwebview-review-click
native-wkwebview-review-tree-scroll
native-victoria-trace-stitching
```

All native scenarios run against the current worktree source set. Native parity
includes FileView and worktree-backed Review as separate scenario families:
FileView click/open and tree scroll cannot stand in for Review item click/open
or Review tree scroll, and Review proof cannot stand in for FileView proof.

Headless Swift-plane proof runs in two lanes:

```text
compact proof (always-on, `mise run test`)
  proves contract truth without wall-clock latency gates: manifest
  completeness per the expected-set composition above, ignored-path
  exclusion via a seeded ignored fixture, typed frame-level loaded_by/lane
  lineage decoded from the typed field with a negative assertion that
  Worktree/File rows carry no duplicated per-row lineage, interest
  preemption of mid-flight idle continuation under the normative contention
  scenario driven through the scheduler's test seams, idle-budget progress
  during that contention, the structural preemption bound (a queued
  higher-lane job dequeues after at most one bounded idle batch), and
  proof-artifact shape. latency percentiles are recorded report-only in
  this lane. window sizes and budgets are asserted as observed behavior
  equal to the AppPolicies constant production uses; constant-to-constant
  comparisons prove nothing. obligations activate slice by slice as the
  implementation lands; a required assertion whose input exists must fail
  closed, not skip silently.

gated benchmark (`mise run verify-bridge-headless-manifest`)
  this task is REQUIRED to exist and is the authoritative command for
  closing R17.b; the compact lane alone can never close it. the task sets
  the environment that activates the gated assertions, runs the benchmark
  loop against the current worktree with metadata_interest_samples >= 100
  total and >= 50 for each hard-gated lane (foreground, visible), and
  content samples >= 20. it enforces the queue-wait and interest-to-frame
  budgets as hard gates, writes the proof artifact, exports the same
  histograms to the shared Victoria stack through the standard debug
  observability path, and finishes with a marker-scoped VictoriaMetrics
  query proving the named native histogram events landed for the run
  marker. a gated run with a partially-set environment fails closed.
```

The contention scenario is normative for `demand-pressure-no-starvation` and
is defined measurably: the proof drives the scheduler's injected clock and
continuation step/gate seams so idle continuation is mid-flight, injects
foreground and visible interest, and asserts (a) idle-lane frames exist with
delivery indices strictly before AND strictly after the injection point,
proving idle was actively producing; (b) the injected higher-lane frames are
delivered after at most one bounded idle batch (the AppPolicies preemption
bound); and (c) idle progress counters strictly increase across the
injection, proving no starvation. Sequentially awaited interest probes
issued before intake-ready do not satisfy this scenario, because buffer
insertion order would prove test choreography rather than scheduler
behavior. Wall-clock sleeps and `#if DEBUG` hooks are prohibited; the seams
are ordinary constructor parameters.

## Passing Criteria

Vite performance proof passes only when:

```text
100 file click samples are recorded
100 tree scroll samples are recorded
p95 and p99 are computed for the hard interaction metrics
File click p95 < 50ms and p99 < 100ms
Tree scroll p95 < 50ms and p99 < 100ms
Native interest-to-delivered-frame p95 < 32ms and p99 < 64ms
blank_tree_window_count = 0
wrong_visible_row_count = 0
foreground and visible queue wait percentiles are reported
foreground/visible metadata interest-to-frame percentiles are reported
content latency is separated from metadata latency
artifact records run marker, runtime, worker mode, and commit SHA
```

Native performance proof passes only when the current-worktree headless
Swift-plane artifact and native WKWebView artifact both report the required
p95/p99 metrics, `loaded_by`/lane lineage, manifest-completeness facts,
no-starvation facts, and separate FileView versus Review scenario results
through Victoria-backed proof.

Headless Swift-plane proof is required before native WKWebView proof can close:

```text
the expected metadata set follows the expected-set composition in the
  manifest index contract: independent test-owned walk minus the libgit2
  ignored set today, cutting over to trackedPaths union
  untracked-non-ignored when AgentStudioGit ships it; never the provider's
  own emission counters; expected-versus-emitted is a files-only path-set
  comparison with an empty symmetric difference, not a count equality
a seeded ignored-path fixture is absent from every emitted frame
all expected rows eventually appear in emitted metadata frames
every frame records typed loaded_by and lane lineage at frame level
selected/open and visible metadata beat active idle continuation under the
  normative contention scenario, and idle progress counters still advance
full-manifest completion has p95/p99 and no-starvation progress counters
content descriptor demand is measured separately from metadata frame emission
queue wait by lane comes from the generic lane scheduler's
  enqueue-to-dequeue instrumentation with real per-lane sample counts;
  a relabeled request-to-delivery span is a failing substitute
p95/p99 are reported for open-to-first-window, metadata-interest-to-frame,
full-manifest-complete, queue wait by lane, metadata window produce,
web metadata apply, and content fetch
```
