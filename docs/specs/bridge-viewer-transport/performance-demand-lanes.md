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

## Demand-Lane Recovery And Speculation Contract

This section extends this file because demand priority, queue honesty,
in-flight cancellation, recovery, and proof metrics are one scheduling
contract. The parent protocol specs own source identity, app navigation, and
protocol-specific payload shape; this file owns whether user demand can be
delayed, silently dropped, or wedged.

Current source anchors:

- Worktree/File protocol identity already carries `streamId` and `generation`
  in the protocol schema (`worktree-file-surface-protocol.md:444-445`).
- The browser Worktree/File receiver rejects stream and generation mismatch
  before accepting frames (`BridgeWeb/src/app/bridge-app-native-worktree-file.ts:741`,
  `BridgeWeb/src/app/bridge-app-native-worktree-file.ts:775`).
- The browser heals `sequence_gap` by calling the stream reset callback and now
  routes resolved `generation_mismatch` / `stream_mismatch` receiver drops
  through the same reset-required callback path
  (`BridgeWeb/src/app/bridge-app-native-worktree-file.ts:172`,
  `BridgeWeb/src/app/bridge-app-native-worktree-file.ts:189`,
  `BridgeWeb/src/app/bridge-app-native-worktree-file.ts:276`).
- Native generation rotation increments the accepted generation, closes the
  gate, cancels the active tree-window task, revokes leases, resets the
  resource store, and drops stale scheduler jobs
  (`Sources/AgentStudio/Features/Bridge/Runtime/WorktreeFileSurface/BridgePaneController+WorktreeFileSurface.swift:26`,
  `Sources/AgentStudio/Features/Bridge/Runtime/WorktreeFileSurface/BridgePaneController+WorktreeFileSurface.swift:51`,
  `Sources/AgentStudio/Features/Bridge/Runtime/WorktreeFileSurface/BridgePaneController+WorktreeFileSurface.swift:436`,
  `Sources/AgentStudio/Features/Bridge/Runtime/BridgeMetadataLaneScheduler.swift:137`).
- The shared BridgeViewer app keeps mounted File and Review mode hosts instead
  of relying on remount for data-controller liveness
  (`BridgeWeb/src/app/bridge-app.tsx:257`, `BridgeWeb/src/app/bridge-app.tsx:285`).

Spec boundary / separability map:

```text
UI stimuli
  owns: selected/click, viewport, hover, mode-switch intent
  exposes: demand class and cancellation scope

App demand policy
  owns: selected/click > visible-metadata > speculative > background
  exposes: generic lane intents, freshness keys, cancellation groups

Generic schedulers and executors
  owns: queue order, in-flight pressure, aborts, stale drops, metrics
  exposes: accepted/rejected/deferred/aborted outcomes

Lineage authority
  owns: current streamId + generation per protocol
  exposes: stale/reject classification and recovery action

Recovery controller
  owns: reset-required -> reopen or unhealthy transition
  exposes: storm guard and one active reopen per stale episode
```

### Testable Requirements

R20. The user-demand taxonomy is strict:
`selected/click > visible-metadata > speculative > background`.

`selected/click` is the only absolute content preemptor. It maps to the
generic foreground lane and must never queue behind visible, nearby,
speculative, active background, or idle work. If the executor or scheduler is at
capacity, selected/click cancels or preempts lower-priority work instead of
waiting for it. Current web executor code already contains lower-priority
in-flight preemption (`BridgeWeb/src/core/demand/bridge-resource-executor.ts:228`,
`BridgeWeb/src/core/demand/bridge-resource-executor.ts:353`) and pending-load
priority order (`BridgeWeb/src/core/demand/bridge-resource-executor.ts:619`);
proof must show the same invariant for every File and Review demand entrypoint.

R21. Visible tree work is metadata-only.

Visible tree rows may request metadata interest and descriptor facts needed to
render identity, status, extent, and availability. They must not fetch content
bodies merely because a row is visible. This prevents 180-worktree-scale waste:
large trees can scroll and show status without warming hundreds of file bodies.
Review visible content hydration is a separate code-view concern and remains
bounded by its own small content window (`BridgeWeb/src/review-viewer/content/visible-review-content-hydration.ts:61`).

R22. Hover speculation is cancellable.

Tree-row hover may start a speculative descriptor/content warm only for the
hovered candidate. Hover-out cancels queued and in-flight hover speculation for
that candidate. Hovering another row cancels prior hover speculation and starts
only the latest candidate. The current FileViewer code exposes advisory
descriptor demand (`BridgeWeb/src/file-viewer/use-bridge-file-viewer-descriptor-request-controller.ts:77`),
but no hover-prefetch producer is present in the current codebase; implementation
must add this as a cancellable stimulus, not as route-local incidental fetches.

R23. Click changes cancel non-target speculation and promote target work.

Clicking a file or review item cancels every speculative content demand that is
not needed for the clicked target. If the clicked target already has an in-flight
speculative load, that work is promoted to selected/click authority instead of
being duplicated or forced to restart. Current Review selection aborts previous
selected content and cancels demand for the previous item
(`BridgeWeb/src/app/bridge-app-review-selection-controller.ts:136`), but the
promotion rule is a required extension over simple abort/reload behavior.

R24. Generation rotation is atomic cancellation.

When a protocol source generation rotates, all queued and in-flight work bound
to the old generation is cancelled at the ownership boundary in one lineage
transition. A stale-drop is acceptable only as the observable completion of that
cancellation for work that already crossed an async boundary; no old-generation
work may continue consuming constrained selected/click, visible, or speculative
slots after the new generation is accepted. No old-generation result may publish
content, mutate selection state, or reopen the old surface after the new
generation is accepted. Native queue stale-drop on `acceptGeneration` is
required evidence
(`Sources/AgentStudio/Features/Bridge/Runtime/BridgeMetadataLaneScheduler.swift:137`);
browser content proof must also show executor-level abort or stale completion
through freshness checks (`BridgeWeb/src/core/demand/bridge-resource-executor.ts:212`,
`BridgeWeb/src/core/demand/bridge-resource-executor.ts:567`).

R25. Stream staleness has one authority.

For Worktree/File intake, stale means `frame.streamId !== accepted.streamId` or
`frame.generation !== accepted.generation`, except that a valid reset frame may
advance the accepted generation according to the protocol receiver
(`BridgeWeb/src/app/bridge-app-native-worktree-file.ts:749`). Sequence,
descriptor, resource, and content freshness checks derive from this protocol
identity; they must not create independent stale definitions.

R26. Every stale/reject path recovers or marks unhealthy.

Any stale/reject path that can leave the user-visible surface unable to accept
future current frames must do exactly one of:

```text
reset-required -> reopen accepted source -> fresh stream identity
mark surface unhealthy -> visible failure / connection-health path
```

Silent rejection loops are contract violations. This recovery invariant covers:

- receiver sequence gaps: `sequence_gap` moves the receiver to
  `resetRequired` (`BridgeWeb/src/app/bridge-app-native-worktree-file.ts:789`)
  and triggers the reset callback
  (`BridgeWeb/src/app/bridge-app-native-worktree-file.ts:189`);
- receiver generation or stream mismatch: the receiver currently rejects these
  as `generation_mismatch` or `stream_mismatch`
  (`BridgeWeb/src/app/bridge-app-native-worktree-file.ts:741`,
  `BridgeWeb/src/app/bridge-app-native-worktree-file.ts:775`); implemented
  browser behavior sends those receiver drops through
  `signalStreamResetRequiredForReceiverRejection`, which signals the resolved
  stream's reset-required callback for the 2026-07-03 silent-reject wedge class
  (`BridgeWeb/src/app/bridge-app-native-worktree-file.ts:189`,
  `BridgeWeb/src/app/bridge-app-native-worktree-file.ts:276`);
- DOM detach/remount: mounted File and Review hosts keep controllers alive
  across mode switches (`BridgeWeb/src/app/bridge-app.tsx:257`,
  `BridgeWeb/src/app/bridge-app.tsx:285`); reopen uses an explicit
  `reopenSignal`, not accidental remount
  (`BridgeWeb/src/app/bridge-file-viewer-frame-controller.ts:14`).

R27. Reopen storm guard.

Only one reopen may be in flight for one stale/reject episode. Additional
generation/stream mismatch frames observed while that reopen is in flight must
record an intake reject/drop fact but must not schedule another reopen. The
implemented browser guard keys the episode by the last resolved
`streamId:generation` pair, suppresses mismatches while an open is pending as
rotation noise, and clears the guard after the reopen resolves and installs the
new accepted identity (`BridgeWeb/src/app/bridge-app-native-worktree-file.ts:177`,
`BridgeWeb/src/app/bridge-app-native-worktree-file.ts:397`). Browser tests
already encode this required behavior
(`BridgeWeb/src/app/bridge-app-native-worktree-file.browser.stream-suite.ts:597`).

R28. Review on-click adjacent-group warming is speculative and bounded.

When a Review item is clicked, the selected item loads as selected/click. The
small in-viewport group around the clicked item is the required adjacent
Review-content speculation tier and loads as one bounded batch because review
order is top-to-bottom. That batch is speculative for priority purposes: it must
cancel or pause under selected/click pressure and must not be described as
selected work in telemetry. Current visible Review hydration already includes a
selected neighborhood (`BridgeWeb/src/review-viewer/content/visible-review-content-hydration.ts:549`)
and gives adjacent items a `nearby` interest
(`BridgeWeb/src/review-viewer/content/visible-review-content-hydration.ts:204`).
The strict requirement is that this adjacent work remains below selected/click
and never delays the clicked item.

R29. Speculative content landing uses the worker-backed content cache.

Successful speculative content must land in the shared review content registry
or the equivalent worker highlight/content cache for FileViewer, composing with
the descriptor-only worker pipeline rather than bypassing it. It must not commit
directly into selected UI state. Review's registry is LRU-capped
(`BridgeWeb/src/review-viewer/content/review-content-registry.ts:55`,
`BridgeWeb/src/review-viewer/content/review-content-registry.ts:317`), clears on
package/generation change (`BridgeWeb/src/review-viewer/content/review-content-registry.ts:75`),
and is read before demand enqueue (`BridgeWeb/src/review-viewer/content/review-content-demand-loader.ts:73`).

R30. Speculative in-flight is globally bounded.

Speculative content work is limited to one or two in-flight loads per viewer,
with one as the default. Review prefetch already declares one concurrent
speculative load (`BridgeWeb/src/review-viewer/content/review-content-prefetch-policy.ts:17`)
and the controller pumps sequentially
(`BridgeWeb/src/app/bridge-app-review-content-prefetch-controller.ts:87`).
Any FileViewer hover prefetch must use the same 1-2 bound and must share executor
pressure with selected/click preemption.

R31. Mode switch cancels or demotes inactive demand.

Switching between File and Review keeps mounted shells for memory, but inactive
foreground demand is not allowed to continue as foreground. In-flight selected
loads for the inactive mode must abort, stale-drop, or be demoted to a lower
class that cannot mutate visible active-mode state. The mode hosts are mounted
but hidden (`BridgeWeb/src/app/bridge-app.tsx:265`,
`BridgeWeb/src/app/bridge-app.tsx:293`), so proof must distinguish retained
state from continuing foreground work.

### Demand Class To Implementation Lane Mapping

| Demand class | Strict priority | Generic lane(s) | Content rule | Cancellation rule |
| --- | ---: | --- | --- | --- |
| selected/click | 1 | `foreground` | selected body/range bytes and selected metadata | preempts or cancels every lower class |
| visible-metadata | 2 | `visible` metadata interest | tree/review metadata only; no tree-row content bodies | superseded by viewport generation/range changes |
| speculative | 3 | `nearby` or `speculative` | hover prefetch, review adjacent group, prediction warming | hover-out, click-elsewhere, generation rotation, pressure |
| background | 4 | `active` only for already-open explicit refresh; otherwise `idle` | manifest continuation, low-priority warming, non-visible maintenance | generation rotation, inactive-mode demotion, pressure |

Generic scheduler lane names remain implementation vocabulary. Product proof
must report demand class and generic lane separately where both are present, so
an implementation cannot relabel a `visible` or `speculative` wait as
selected/click latency.

### Cancellation Semantics

```text
hover-out
  -> cancel hover candidate speculative queue entries
  -> abort in-flight hover load if no selected/click consumer shares it

hover A -> hover B
  -> cancel A speculation
  -> start B only if speculation slots are available

click target already speculative
  -> promote shared in-flight work to selected/click authority
  -> continue the existing target work without abort/restart or duplicate fetch
  -> selected/click telemetry starts at actionability-checked click

click different target
  -> cancel all other queued and in-flight speculative work
  -> selected/click enters foreground immediately

generation rotation
  -> atomically cancel or stale-drop all old-generation queued/in-flight work
  -> clear old-generation cache entries that are not content-addressed safe
  -> accept only frames/resources for the new streamId + generation
```

### Speculation Tiers

Tier S1: tree-row hover prefetch.

Tree hover is the narrowest speculation. It warms one hover target and cancels
on hover-out or hover-elsewhere. It never widens to the visible tree and never
fetches every row in the viewport.

Tier S2: Review on-click adjacent-group prefetch.

After the clicked item enters selected/click, the small group around it may warm
as a batch. Current Review code uses a selected neighborhood of at most two
before and two after the selected item
(`BridgeWeb/src/review-viewer/content/visible-review-content-hydration.ts:606`)
and caps visible hydration concurrency at two
(`BridgeWeb/src/review-viewer/content/visible-review-content-hydration.ts:62`).
That behavior may satisfy the first adjacent-group shape only if proof shows it
never delays the clicked item.

Tier S3: visible-tree metadata.

Visible tree means metadata interest only. It can improve scroll, extent, and
descriptor readiness. It is not a content prefetch tier.

Speculative cache landing:

```text
speculative load success
  -> authoritative content cache / worker highlight cache
  -> no selected-state commit
  -> selected/click may later consume as a cache hit

speculative load stale/aborted
  -> no UI error
  -> telemetry/drop counter records why
```

### Scenario Matrix

| Scenario | Trigger | Expected lane behavior | Expected cancellation outcome | Expected recovery outcome | Proof layer |
| --- | --- | --- | --- | --- | --- |
| receiver sequence gap | intake frame jumps `nextSequence` | no further same-generation work treated as healthy | pending old sequence work rejected or retained only for retry | reset-required callback fires; reopen or unhealthy, never silent loop | browser + smoke |
| receiver generation mismatch | current receiver sees future/old generation | stale frame cannot enter any lane | old mismatch episode schedules at most one reopen | reset-required/reopen or unhealthy; no silent-reject wedge | browser + smoke |
| receiver stream mismatch | current receiver sees foreign streamId | no lane admission | stale frame dropped; current work not poisoned | reset-required/reopen or unhealthy; no cross-stream loop | browser + smoke |
| DOM detach/remount | mode switch hides active File/Review shell | demand controllers remain mounted statefully | inactive foreground work aborts/demotes | no lost listener wedge; reopenSignal handles unhealthy stream | browser |
| click during speculation, same target | speculative content for target already pending/in-flight | target promotes to selected/click | do not duplicate; shared work gains selected authority | selected paints; no lower-lane wait counted as selected queue wait | unit + browser |
| click during speculation, different target | user clicks another file/item | clicked target enters selected/click immediately | all non-target speculation cancelled or preempted | selected paints; cancelled speculation records aborted/deferred | unit + browser |
| hover then click same target | hover prefetch in flight, then click row | selected/click consumes/promotes target work | hover cancellation group replaced by selected group | selected paints from promoted work, or from a fresh selected fetch when no target speculation exists | unit + browser |
| hover then hover elsewhere | pointer leaves A and enters B | only B may remain speculative | A queued/in-flight work aborted unless shared by selected | no UI error; A cache only if completed before cancel and still fresh | unit |
| generation rotation mid-speculative fetch | native accepts new generation while S1/S2 running | old speculative work loses freshness | old queued/in-flight speculative work aborts or stale-drops | no old-generation cache/UI commit; new generation can demand fresh | unit + browser |
| generation rotation mid-selected fetch | selected/click fetch crosses generation change | selected work fails closed for old generation | old selected fetch aborts/stale-drops; UI shows loading/stale for new identity | no old body paints; surface reopens or marks stale/unhealthy | browser + smoke |
| reopen storm guard | repeated mismatch frames while reopen pending | no new lanes opened for stale frames | only first mismatch schedules reopen; later mismatches record rejects | second reopen allowed only after prior reopen resolves | browser |
| descriptor stale rejection | descriptor RPC returns stale generation | descriptor demand not retried in same stale identity | pending selected descriptor clears or waits for reopened identity | reset-required/reopen or unhealthy; no permanent pending click | browser |
| windowed or oversized content demand | clicked huge/binary/oversized file | selected/click asks for bounded window or unavailable state | speculative and visible content for that file stay off | selected visible state is ready/unavailable, not wedged loading | unit + browser |
| mode switch with in-flight demands | Files <-> Review while demand active | inactive mode has no foreground work | selected/visible inactive work aborts/demotes; state memory retained | active mode remains responsive; stale completions cannot mutate active UI | browser + smoke |
| visible tree over large worktree | scroll 180-worktree-scale tree viewport | visible-metadata only | no content bodies scheduled for every visible row | scroll settles with metadata; content demand only after click/spec tier | browser + smoke |
| review on-click adjacent group | click review item in code view | clicked item selected/click; adjacent group speculative/nearby | adjacent loads pause/cancel under selected pressure | selected paints first; adjacent cache hits may follow | unit + browser |
| speculation never delays click | executor saturated with speculative loads, then click | selected/click preempts immediately | speculative in-flight/queued loads abort until selected can start | selected queue wait is honest and below budget | unit + browser + smoke |

### Measurement And Honesty

Required telemetry evidence:

- `performance.bridge.web.selected_content_painted` proves selected/click
  click-to-paint and frame/materialize timing
  (`BridgeWeb/src/foundation/telemetry/bridge-viewer-telemetry-adapter.ts:657`,
  `BridgeWeb/src/review-viewer/code-view/bridge-code-view-panel.tsx:952`).
- `performance.bridge.web.review_content_demand` proves Review demand interest,
  result, intent counts, lane counts, pressure, stale drops, and load outcomes
  (`BridgeWeb/src/foundation/telemetry/bridge-viewer-telemetry-adapter.ts:692`,
  `BridgeWeb/src/review-viewer/content/review-content-demand-types.ts:66`).
- `performance.bridge.swift.metadata_scheduler_queue_wait` proves native
  metadata scheduler enqueue-to-dequeue only
  (`Sources/AgentStudio/Features/Bridge/Runtime/WorktreeFileSurface/BridgePaneController+WorktreeFileIntakeFrames.swift:16`).
- A required new browser intake-reject event must record
  `protocol`, `receiverReason`, `generation_relation`, `stream_match`,
  `reopen_state`, and `recovery_action`. Existing probe/drop recording is
  debug state (`BridgeWeb/src/app/bridge-app-native-worktree-file.ts:83`), not
  enough for production proof.

Measurement honesty rules:

- Selected/click latency starts at the actionability-checked click. A cache hit
  may lower selected latency, but speculative wait before the click must not be
  counted as selected queue wait.
- Queue wait means scheduler/executor enqueue-to-dequeue/start. It is not
  request-to-frame, content fetch duration, WebKit delivery delay, or reopen
  recovery time.
- A cancelled speculative load that freed capacity for selected/click must be
  reported as speculative aborted/deferred, never hidden as success.
- Intake reject recovery is not optional telemetry. A stale rejection without a
  matching heal/unhealthy fact is a failing proof artifact even if the final UI
  later appears healthy.

### Open Decisions And Current Gaps

OD-P1. FileViewer hover prefetch producer.

No current FileViewer hover-prefetch producer was found. The spec requires one
if hover speculation is implemented; until then, S1 is an unimplemented tier,
not an implicit visible-tree content prefetch.

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
