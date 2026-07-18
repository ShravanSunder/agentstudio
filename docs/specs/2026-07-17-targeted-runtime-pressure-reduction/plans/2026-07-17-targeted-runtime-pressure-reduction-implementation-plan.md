# Targeted Runtime Pressure Reduction Implementation Plan

Status: reviewed scope correction; ready for `implementation-execute-plan`

Accepted source:
`docs/specs/2026-07-17-targeted-runtime-pressure-reduction/targeted-runtime-pressure-reduction.md`

Accepted source SHA-256:
`a392eacfcc6e5f1884263c1996f539cecf5109d136be705d6c2e2786039972f9`

Behavioral baseline source: `5dea96b6`

Source coverage: `972/972` lines

## Outcome

Reduce AgentStudio CPU, retained/allocation pressure, fanout/task amplification,
and targeted MainActor duty during simultaneous Terminal, watched-folder/Git,
Repo Explorer, tab, and main-pane work. Coalescible observations are compressed
before expensive work; semantic facts stay exact; fleet UI derivation runs off
MainActor; compact current state is applied on MainActor; and the result is
proven against an identically instrumented baseline in the real debug app.

The implementation ends with a reviewed, proven, PR-ready branch. It does not
merge the PR.

## Fixed boundaries

- Preserve Ghostty callback/tick ownership, synchronous handled results, and
  borrowed-payload copy rules.
- Preserve the EventBus implementation and exact semantic-fact route.
- Use one narrow Terminal-local fixed-key accumulator, not a generic mailbox,
  gather thread, actor-per-pane fleet, or reusable admission framework.
- Atoms remain current state or pure derivation. They own no classification,
  timers, queues, projection, refresh, persistence, or workflow.
- Preserve FilesystemActor authority, containment, topology effects, scanner,
  Git slots/timeouts/late-result rules, and `GIT_OPTIONAL_LOCKS=0`.
- Preserve the existing strict off-main composition preparation, lean MainActor
  installation, bounded startup mount lanes, and post-presentation repo lane.
- Use one Repo Explorer feature-local projection owner; do not create a generic
  UI scheduler, atom workflow, or hidden-host lifecycle system.
- Add no persistence, migration, repair, revision, lease, pager, participant,
  heartbeat, diagnostic backend, or mount-generation system.
- Create or expand no proof script or proof harness. Run existing scripts
  unchanged; collect additional evidence through product instrumentation,
  existing Swift tests, bounded direct Victoria/OS queries, IPC, and PID-targeted
  native automation.
- Add narrow SwiftSyntax guards last. Lint is regression prevention, not
  performance proof.

## Requirements / proof matrix

| Requirement | Source | Owner | Required proof | Evidence source and freshness guard | Red/green |
| --- | --- | --- | --- | --- | --- |
| R1: coalescible Terminal samples have bounded/sublinear admission while exact facts retain order | TR-1..TR-7, P-1..P-3a | T3 | deterministic accumulator/router/runtime tests; 100k samples/10 live keys; exact-fact oracle | current candidate, exhaustive signal inventory, zero final debt | required |
| R2: local presentation samples produce zero runtime/replay/EventBus/IPC traffic | TR-4, TR-13..TR-15, TY-2/TY-3 | T3/T7 | zero-count integration assertions plus narrow final static guard | current diff and compiler-visible final route | required |
| R3: activity, search, presentation, terminal controls, Inbox behavior remain correct | TR-6, TR-8..TR-12, P-4/P-5/P-16 | T3/T8 | injected-clock semantic oracle, focused native tests, one PID-targeted smoke | candidate PID, executable, marker, managed-surface lifetime | required below smoke |
| R4: ordinary workspace changes avoid fleet reconciliation; actual topology still converges | FS-1..FS-9, P-6/P-8a | T4 | recording-source/index/coordinator tests plus unchanged large-worktree workload | fixture/source/instrumentation fingerprints and zero logical pending debt | required |
| R5: Repo Explorer structural projection is off-main and status-only changes update affected visible rows | UI-1..UI-6, P-7 | T5 | latest-input oracle, stale rejection, one projection/index per structural input, keyed row updates, collapsed-group isolation | current candidate, 118+ repo population, fresh marker | required |
| R6: AppKit/main-pane work is responsibility-specific and proportional | MP-1..MP-8, P-8 | T6 | observation/host/restore/management/geometry tests plus existing pane/tab metrics and native smoke | current candidate, prepared startup cohort, fresh PID/marker | required |
| R7: CPU, attributable retained/allocation pressure, admission, and targeted MainActor duty improve without footprint regression; stability/type/authority/privacy hold | P-9..P-15, MA-1..MA-5, TY-1..TY-5, SEC-1..SEC-9 | T1/T2/T8 | identically instrumented baseline/candidate, focused/full gates, three qualifying trials, relaunch/readiness, implementation review | frozen schema/operation/workload inventory, source/binary hashes, fresh PID/marker | required for instrumentation math and behavior changes |
| R8: branch is reviewed and PR-ready but not merged | goal R8 | T9 | pushed HEAD, CI/checks/comments/threads/mergeability | final pushed HEAD and fresh 45-second blocking watches | not applicable to product red test |

If a task cannot pass its named proof inside its write boundary, split or replan
the task. Do not weaken, delete, relabel, or defer the proof.

## Execution DAG

```text
T0  validate live repo/spec/instructions
 │
 ▼
T1  behavior-preserving product instrumentation
 │   focused metric/privacy/bucket proof + build/lint
 ▼
T1a remove out-of-scope Bridge-only instrumentation from T1
 │   keep common resource and runtime instrumentation
 ▼
T2  freeze corrected instrumented baseline
 │   warm-up + 3 qualifying trials + calibrated receipt
 │
 ├─► T3 atomic Terminal contraction + off-main activity ────────────┐
 │     local proof; raw scrollbar cut and consumer cutover together  │
 │                                                                  │
 └─► T4 filesystem/trace-identity proportionality ──────────────────┤
       local proof + unchanged workload                              │
                                                                    ▼
T5  Repo Explorer off-main structural projection + keyed rows
 │   local proof + large-repo paired metrics
 ▼
T6  AppKit/main-pane responsibility and host/layout reductions
 │   local proof + pane/tab/geometry metrics
 ▼
T7  narrow final SwiftSyntax guards
 │
 ▼
T8  integrated candidate proof + PID-targeted native smoke
 │
 ▼
T9  implementation review/remediation + PR readiness, no merge
```

T4 may run in parallel with the atomic T3 slice after T2. T5 follows T4 because
the same Git/status workload supplies its primary pressure. T6 may proceed after
T3/T5 source dedupe lands. T7 is last because it encodes the final code shape.

## T0 — Revalidate the executable surface — complete

Purpose: ensure the accepted plan still maps to live code before edits.

Actions:

1. Confirm branch, HEAD, scoped status, and protected `.agents/` state.
2. Recheck the source anchors named in the accepted spec and planning boundary
   lane.
3. Run the smallest existing pre-change focused suites for diagnostics,
   Terminal, activity, filesystem, Repo Explorer, and main-pane AppKit to distinguish pre-existing
   failures from regressions.
4. Record any unrelated failure without editing its infrastructure.

Gate: no stale ownership, missing required source, or unrelated dirty overlap.

## T1 — Add common product instrumentation without changing behavior — complete at `25678fb2`

Purpose: create the identical comparable metric layer used by baseline and
candidate.

Write surface:

- `AgentStudioPerformanceTraceRecorder.swift`
- `AgentStudioOTLPTraceProjection.swift`
- `AgentStudioOTLPPerformanceMetrics.swift`
- `AgentStudioOTLPBootstrapper.swift`
- new `AgentStudioProcessMemorySampler.swift`
- existing diagnostics and owner tests

Frozen comparative measurement manifest:

| Event/body or external sample | Emitter file and owning symbol | Owner scope | Value and normalization | Comparison | Scored membership |
| --- | --- | --- | --- | --- | --- |
| `performance.terminal.action_capture` | T3 copied-action classification boundary | process and controlled disposition only | elapsed ms and translated-action count from the bounded owner | candidate-only absolute | classification belongs to interval |
| `performance.terminal.mainactor_route` | T3 accumulator enqueue and compact-apply successor | process and controlled disposition only | queue-age ms, service ms, task/admission count | candidate-only absolute | enqueue and completion both belong to the scored interval |
| `performance.terminal.local_sample` | T3 controlled disposition admission | process and disposition, never pane/surface ID | offered/replaced/equal-suppressed count | candidate-only absolute | offer belongs to interval |
| `performance.terminal.drain` | T3 Terminal-local accumulator; `offer`, scheduled drain, and follow-up completion | process and fixed disposition key | scheduled/follow-up/pending count and retained entry/estimated byte gauge; emitted only at bounded drain/snapshot boundaries | candidate-only absolute | drain scheduled or completed inside interval |
| `performance.terminal.compact_apply` | T3 compact presentation apply boundary | process and disposition | queue-age ms, service ms, accepted/equal-suppressed mutation count | candidate-only absolute | enqueue and commit both inside interval |
| `performance.terminal.activity_projection` | T3 bounded activity aggregate owner | process and semantic outcome | evidence/aggregate/fact/apply count and service ms | candidate-only absolute | aggregate admission or commit inside interval |
| `performance.runtime_channel.admission` | T3 fact-only runtime-channel boundary | process and finite semantic event class | local post/replay/outbound/drop count | candidate-only absolute | admitted fact belongs to interval |
| `performance.eventbus.delivery` | existing EventBus diagnostics plus the T3 fact-only route | process and finite semantic event class | posts/deliveries/replay/drops | existing aggregate diagnostics for baseline; candidate-only class detail | diagnostics snapshot belongs to interval |
| existing `performance.coordinator.write` filesystem phases | `WorkspaceSurfaceCoordinator+FilesystemSource.swift`; existing source-sync and pane-projection records | process and existing controlled phase | existing counts plus total/index/MainActor-apply durations | paired without emitter changes | existing bounded record belongs to interval |
| `performance.process.malloc_zone` | `AgentStudioProcessMemorySampler.swift`; one diagnostics-owned sampler installed by `AgentStudioPerformanceTraceRecorder` only when performance tracing is enabled | all process malloc zones in both builds | `blocks_in_use` count plus `size_in_use`, `max_size_in_use`, and `size_allocated` bytes from `malloc_zone_statistics(nil, ...)`; report interval high-water, end-minus-start growth, and post-quiescence value; normalize by scored wall interval and separately by each accepted-work population only for diagnosis | paired attributable allocation/retained-byte evidence | one sample/second inside the scored interval plus one post-quiescence sample |
| process CPU | direct `ps -o time=` start/end reading for the exact candidate PID | process | CPU-time delta / scored wall interval; additionally per accepted work only when counts differ | paired | two boundary samples |
| RSS | direct `ps -o rss=` for the exact PID | process | KiB, one sample/second; interval maximum and post-quiescence | paired secondary confirmation | timestamps inside interval plus one post-quiescence sample |
| physical footprint | direct `/usr/bin/footprint -p <pid>` | process plus child/helper population declared in the receipt | physical-footprint bytes at scored start, fixed 45-second point, and post-quiescence; no `vmmap` polling | paired primary physical-memory evidence | three fixed samples |

The paired targeted MainActor duty inventory is exactly the MainActor apply
phase of existing filesystem `coordinator.write` records and the existing
MainActor commit phases of `sidebar.projection`, `sidebar.row_index`,
`tabbar.refresh`, `pane_tab.layout`, `pane_view.restore`, and
`terminal.geometry`. Those emitter definitions remain identical in baseline and
candidate even when the optimization intentionally changes their populations.
Candidate-only `terminal.action_capture`, `terminal.mainactor_route`,
`terminal.drain`, `terminal.compact_apply`, `terminal.activity_projection`, and
the new T4/T5/T6 compact-apply metrics are absolute structural, queue-age,
service, and quiescence gates; they are excluded from the paired duty sum and
cannot satisfy a comparative improvement claim. No operation may be added to
only one side of the paired inventory. T1 must not add a trace-log record per
Terminal callback, runtime-channel emit, or EventBus delivery. Their exact
counters and duration buckets are installed only when T3/T4/T5/T6 create
bounded owners. The only product timer added
by T1 is the one-second, performance-tag-gated, fail-open all-malloc-zones
sampler; it is installed identically in baseline and candidate and stops with
the trace runtime. External RSS sampling is once per second. Physical footprint
is sampled only at the three fixed points above to keep perturbation bounded.
Candidate-only structures and counters use absolute gates and are never called
comparative.

Duration histograms use bucket upper bounds at `0.25`, `0.5`, `1`, `2`, `5`,
`8`, `16`, `20`, `60`, `100`, `250`, `500`, `1_000`, `2_500`, `5_000`, and
`10_000` ms. Counts and byte gauges are not histogrammed. Each qualifying
trial receipt records the exact manifest text digest, event schema digest,
emitter source hash, owner scope, unit, normalizer, bucket vector, and scored
monotonic start/end timestamps. A source or semantic mismatch makes the metric
absolute-only and invalidates any paired claim.

Rules:

- Bodies and dimensions are controlled, aggregate, and content-safe before both
  JSONL and OTLP fanout.
- Emit no raw path, ID, prompt, terminal/search/notification content, URL,
  payload, error, token, Git output, or projected UI content.
- Instrumentation is fail-open and owns no correctness state.
- Do not touch any proof script/harness.

Red/green proof:

- Recorder/projection/metric/bootstrap/memory-sampler tests first fail for
  missing events, buckets, arithmetic, sampling shutdown, or privacy canaries,
  then pass.
- Existing path behavior tests remain unchanged and green.
- `mise run build` and `mise run lint` pass.

Focused command:

```bash
mise run test -- --filter 'AgentStudioPerformanceTraceRecorderTests|AgentStudioOTLPTraceProjectionTests|AgentStudioOTLPPerformanceMetricsTests|AgentStudioOTLPBootstrapSmokeTests|AgentStudioProcessMemorySamplerTests'
```

Checkpoint: commit the behavior-preserving instrumentation. No behavior task
starts before T2 completes.

Split trigger: any metric requires changing route semantics or adding a proof
backend/script/harness.

## T1a — Remove the out-of-scope Bridge-only T1 instrumentation

Purpose: restore the user-corrected product boundary before freezing comparable
instrumentation.

Actions:

1. Revert only the Bridge controller and Bridge test hunks introduced by
   `25678fb2`.
2. Remove Bridge refresh fields from the T1 metric manifest and targeted
   MainActor inventory.
3. Retain the generic process memory sampler, OTLP duration buckets, resource
   math, and content-safety tests used by Terminal/filesystem/UI cells.
4. Prove Bridge source behavior is byte-for-byte back at its T1 parent shape;
   do not refactor or “improve” Bridge while reverting instrumentation.

Gate: focused diagnostics tests, Bridge regression tests covering restored
files, build, lint, and exact scoped diff proof.

Checkpoint: commit the scope correction before collecting the new baseline.

## T2 — Capture and freeze the baseline

Behavioral source: `5dea96b6` plus the corrected common instrumentation after
T1a. Construct it in a detached worktree under
`~/.agentstudio-db/performance-baselines/2026-07-17-targeted-runtime-pressure-reduction/source`,
whose canonical path must be outside both configured watched development roots:
`/Users/shravansunder/Documents/dev/open-source` and
`/Users/shravansunder/Documents/dev/project-dev`. Do not create another baseline
checkout under either watched root and do not use the candidate checkout as the
baseline executable source.

Create the detached worktree at exactly `5dea96b6`, apply only the allowlisted
common diagnostics/resource instrumentation from the verified T1a checkpoint,
and make one detached instrumentation commit. Record the detached commit/tree,
the T1a source commit, an allowlisted name-status diff, per-file hashes, and the
absence of any Terminal/filesystem/Repo Explorer/AppKit behavior hunk. The
detached worktree's deterministic debug identity, data root, zmx root, marker,
and executable remain independent from the candidate. The already-collected
three Git trials remain diagnostic/calibration evidence for the discovered
sidebar/AppKit pressure, but they are not the frozen paired baseline after the
instrumentation manifest changes.

Artifact root:
`tmp/performance-proof/2026-07-17-targeted-runtime-pressure-reduction/baseline/`

Record for every trial:

- behavioral source, instrumentation commit, executable SHA-256, schema/event/
  bucket/operation-inventory digest, trace tags, debug identity, marker, PID,
  hardware/display facts, workload population, and scored interval;
- direct start/end process CPU-time readings, one-second `ps -o rss=` and
  all-malloc-zones samples, fixed-point `/usr/bin/footprint -p <pid>`
  snapshots, and candidate-only event-driven retained entry/estimated-byte
  gauges; do not poll `vmmap`;
- marker-scoped Victoria counts/distributions and final debt/quiescence.

Trial policy:

- one unscored warm-up and at least three qualifying trials for watched-folder/
  Git, the separate paired Repo Explorer/AppKit UI cell, and combined real-app
  pressure;
- Repo Explorer/sidebar, tab-bar, pane-layout/restore, and terminal-geometry
  distributions are paired only when baseline and candidate have identical
  metric populations; otherwise the changed metric is absolute-only;
- per-trial values are summarized first; compare medians across trials; do not
  pool samples;
- fixture floors and one-sided noise bands are frozen separately from product
  budgets in `baseline/baseline-calibration.md`.

Before behavior changes begin, `baseline/baseline-calibration.md` also freezes:

- the literal Terminal burst command, exact record body/length/count, and
  payload SHA-256;
- the exact native key chords, tab and pane target roles, action ordering,
  successful-action counts, split-view divider starting geometry, resize delta,
  and return geometry; and
- one stable expanded Repo Explorer group containing at least one visible
  status row plus one stable collapsed group. The receipt records how those
  fixture roles/identifiers are reconstructed in every baseline and candidate
  trial without exporting them as telemetry dimensions.

Use the existing proof surfaces rather than creating a new runner or comparator.
One proof-only correction is authorized for
`verify-git-refresh-performance-workload` and its existing focused Swift test:
materialize the generated fixture through the real strict-SQLite datastore
before launch, then keep the exact candidate PID alive through the bounded
common-quiescence endpoint and final resource capture. Apply the same correction
to baseline and candidate, record its digest, and exclude fixture setup from the
scored interval. This correction must not add a production import/diagnostic
surface, schema copy, migration, IPC command, generic harness, or product/runtime
behavior. Additional direct commands/queries remain receipt-only.

Gate: parent verifies calibration receipt and identical instrumentation contract.
If common metric meaning changes later, invalidate the comparison and recollect;
do not reinterpret it.

## T3 — Atomic Terminal contraction and off-main activity cutover

Write surface:

- Ghostty action router/observed-action/adapter files;
- exactly two top-level additions: `GhosttyActionDisposition` and
  `TerminalLocalActionAccumulator`; batch/lifecycle details stay private;
- `SurfaceManager`/`SurfaceTypes` only for managed lifetime lookup/cleanup;
- `TerminalRuntime`;
- Terminal/search portions of `PaneRuntimeEvent.swift`;
- `TerminalActivityRouter.swift`, `TerminalActivityAtom.swift`,
  `AppDelegate+InboxNotificationBoot.swift`, and `InboxNotificationRouter.swift`;
- focused Terminal/activity/Inbox/runtime/replay/EventBus/IPC tests.

Implementation contract:

1. Copy any borrowed C payload before callback return.
2. Classify with one exhaustive typed disposition: exact command/fact, latest
   presentation, activity evidence, exact local lifecycle, diagnostic outcome.
3. Preserve exact command/fact routing and synchronous handled result.
4. Reuse the already-copied Sendable `GhosttyAdapter.ActionPayload` and existing
   `(ObjectIdentifier, ManagedSurface.id)` lifetime identity; add no second
   callback snapshot or lifetime registry.
5. Offer coalescible copied values through one synchronous per-surface
   linearization point into fixed compile-time keys.
6. Permit one pending drain and one convergent follow-up per live surface.
7. Resolve and revalidate managed surface lifetime immediately before apply.
8. Compare-and-remove on close/replacement so old work cannot affect a reused
   address or replacement surface.
9. Apply latest current presentation once; suppress equal writes.
10. Keep initial/cell size and configuration on their existing direct host
    cache paths. Treat size-limit/link/key-table/color cases as typed
    diagnostic/drop outcomes unless implementation revalidation finds a live
    product consumer; do not allocate retained slots for obsolete replay.
11. Make search active/inactive a discriminated lifecycle. Barrier identity
   prevents late total/selection from reactivating ended search.
12. `TerminalActivityRouter` becomes the off-main owner of bounded scrollbar
    aggregates, windows, injected-clock quiet timers, settled/revoked projection,
    and typed control order.
13. Attention, observation, read/dismiss, reset, close, and semantic revocation
    detach earlier evidence, submit aggregate then control, and start a new
    aggregate for later evidence. Historical attention is never inferred from
    delayed current MainActor state.
14. MainActor supplies narrow context and applies compact accepted state only;
    `TerminalActivityAtom` remains current state/simple mutation.
15. Inbox consumes derived pinned/observed/settled outcomes, not raw scrollbar
    samples.
16. Hard-cut local presentation from runtime channel, replay, EventBus, and IPC
    waits; exact semantic facts remain unchanged.

Red/green proof:

- focused accumulator/router/adapter/runtime/search invariants;
- 100,000 coalescible samples across at least 10 live lifetime keys in the
  existing large/default suite;
- independent latest-value and sufficient-statistics oracles;
- reentrant/concurrent offers, gated drains, start/end/cancel barriers,
  close/address reuse, bounded storage, zero final debt;
- exact semantic count/order, zero sample-caused fact drops, and zero local
  runtime/replay/EventBus/IPC activity;
- injected-clock raw-versus-aggregate semantic oracle covering focus/blur,
  observe/read/dismiss, reset, semantic revocation, growth-before-reset, pinned
  edges, duplicates, close/replacement, quiet settlement, stop/cancellation,
  and no post-stop mutation;
- existing derived notification integration remains green.

Focused command:

```bash
mise run test -- --filter 'TerminalLocalActionAccumulatorTests|GhosttyActionRouterTests|GhosttyAdapterTests|GhosttyEventRoutingCoverageTests|GhosttyScrollTranslationTests|TerminalRuntimeTests|PaneRuntimeEventChannelTests|EventBusRuntimeEnvelopeTests|EventReplayBufferTests|TerminalActivityRouterTests|TerminalActivityDerivedEventTests|TerminalActivityAgentSettledHeuristicTests|TerminalActivityAtomTests|DerivedActivityNotificationIntegrationTests|DerivedTerminalActivityNotificationRegressionTests|InboxNotificationRouterTests|InboxNotificationRouterObservedPaneTests|InboxNotificationRouterPayloadTests'
```

Checkpoint: one atomic commit only after sample publication deletion, activity/
Inbox consumer cutover, focused proof, and the large deterministic cell all pass.
Do not commit a T3 state that deletes raw scrollbar publication while current
activity/Inbox consumers still depend on it.

Split trigger: implementation needs a generic mailbox, durable generation,
strong view retention, actor-per-pane fleet, EventBus change, atom workflow,
current-state historical inference, or wall-clock test sleeps.

## T4 — Replace unconditional filesystem fleet work with fixed-key effects

Write surface:

- `WorkspaceSurfaceCoordinator+ActionExecution.swift`;
- CWD/active-pane edges in `WorkspaceSurfaceCoordinator.swift`;
- existing pane lifecycle membership edges;
- new `WorkspaceSurfaceCoordinator+FilesystemEffects.swift` for fixed-key
  coordinator effects;
- `FilesystemGitPipeline.swift` only if an existing capability needs exposure;
- `WorkspaceCacheCoordinator.swift`, `AppDelegate+WorkspaceBoot.swift`, and
  `AgentStudioTraceIdentityStore.swift` for one explicit trace-identity effect;
- existing coordinator/projection/CWD/Git/trace-identity authority tests.

Implementation contract:

1. Delete the unconditional action-tail full synchronization.
2. Pane create/mount/close updates that pane only.
3. CWD/worktree reassignment updates that pane and affected worktree activity.
4. Active pane changes update active-worktree priority only.
5. No-op, layout, sidebar, Inbox, and presentation actions schedule no
   filesystem reconciliation.
6. Cold boot, explicit rebuild, and accepted topology deltas retain one full
   reconciliation through the existing topology effect.
7. Remove the duplicate broad trace-identity observation when explicit accepted
   topology/pane-association/enrichment effects already own refresh. Coalesce
   concurrent explicit requests and suppress equal snapshots before sink update.
8. Preserve all filesystem authority/currentness and Git capacity semantics.

Red/green proof:

- recording-source tests prove zero full capture for unrelated actions and
  affected-key-only updates;
- trace-identity tests prove one fleet capture per accepted current batch and no
  duplicate observer/callback capture or equal sink update;
- bootstrap and topology delta converge to the independent oracle;
- existing containment, authority, no-lock, logical-timeout/physical-drain, and
  late-result suites remain green;
- run the existing watched-folder workload unchanged and obtain paired Victoria
  metrics by direct queries; final logical pending work is zero.

Focused command:

```bash
mise run test -- --filter 'WorkspaceSurfaceCoordinatorTests|WorkspaceSurfaceCoordinatorFilesystemSourceTests|WorkspaceSurfaceCoordinatorCWDIdentityTests|FilesystemProjectionIndexTests|FilesystemGitPipelineIntegrationTests|AgentStudioGitWorkingTreeStatusProviderTests|FilesystemActorShellGitIntegrationTests|GitWorkingDirectoryProjectorTests|FilesystemActorHotPathArchitectureTests'
```

Checkpoint: commit after focused integration and unchanged workload proof.

Split trigger: fixed-key behavior requires fleet capture, new topology algebra,
or any scanner/Git authority/capacity/lock/timeout change.

## T5 — Move Repo Explorer structural projection off MainActor

Write surface:

- `RepoExplorerSnapshot.swift`, `RepoExplorerProjection.swift`, and
  `RepoExplorerRowIndex.swift` to make the structural input/output explicitly
  immutable and Sendable;
- one feature-local `RepoExplorerProjectionOwner.swift` (or equivalently named
  owner) for latest-input coalescence, off-main computation, stale rejection,
  and compact MainActor apply;
- `RepoExplorerView.swift` and worktree row composition for accepted structural
  state plus keyed visible-row facts;
- focused Repo Explorer projection/filter/grouping/row-index/view-model tests.

Implementation contract:

1. Structural input includes repository/worktree topology, repo-origin identity,
   filter query, and expanded-group state. It excludes branch/status/PR/unread.
2. One owner accepts the latest immutable structural input, has at most one
   active computation plus one convergent latest follow-up, and rejects stale
   completion before compact MainActor apply.
3. Grouping, filtering, topology-fault detection, ordering, and row-index
   construction run off MainActor exactly once for the accepted input.
4. `RepoExplorerView.body` consumes one stored projection/index; the empty and
   list paths never call the fleet projector independently.
5. Visible row views read keyed worktree enrichment/PR/notification facts.
   Status-only changes do not invalidate structural projection, and collapsed
   groups do not subscribe to their worktree statuses.
6. Duplicate topology identities remain an explicit degraded state. The owner
   does not repair topology or mutate/persist atoms.

Red/green proof:

- independent projection and row-index oracle across topology/origin/query/
  expansion changes;
- gated overlapping inputs prove latest convergence, stale rejection, one
  accepted apply, and zero final work debt;
- status-only updates produce zero structural projections and update only the
  affected visible row;
- collapsed-group isolation and no-results/list projection identity;
- 118+ repository workload shows materially lower projection count/MainActor
  duty while final rendered group/row/status content matches baseline.

Focused command:

```bash
mise run test -- --filter 'RepoExplorerProjectionTests|RepoExplorerRowIndexTests|RepoExplorerFilterTests|RepoPresentationGroupingTests|RepoExplorerViewModelTests'
```

Checkpoint: commit after focused proof and one candidate large-repo trial shows
the intended structural count reduction. Do not wait for final three-trial
resource acceptance before checkpointing the proven slice.

Split trigger: implementation requires a generic projection scheduler, atom
workflow, persistence, canonical topology mutation, or broad hidden-host system.

## T6 — Reduce AppKit/main-pane invalidation and host/layout work

Write surface:

- `TerminalRuntime.swift`, `PaneMetadata.swift`, and pane-graph mutation tests
  for earliest-owner semantic equality suppression plus defensive equal writes;
- `PaneTabViewController.swift` and narrowly extracted observation helpers;
- `WorkspaceSurfaceCoordinator+ActiveTabRestore.swift` and target-frame helpers;
- `PaneLeafContainer.swift` / `PaneManagementContext.swift` for same-target reuse;
- terminal geometry owners only where the duplicate unchanged refresh is proven;
- existing tab-host, restore, geometry, pane-management, and startup tests.

Implementation contract:

1. Normalize/equal-suppress title, tab title, CWD, and other state-like facts
   before runtime publication and canonical mutation; changed facts retain order.
2. Split the broad AppKit observation by tab membership, selection/focus,
   empty-state inputs, and pane-inbox pruning. Each callback performs only its
   owned effect.
3. Remove pane-slot and tab-membership scans from `viewWillLayout`; lifecycle
   edges own membership, and active selection toggles only previous/next hosts.
4. Before restore fleet ordering/frame resolution, return when all target
   visible hosts exist. Missing-host work is target-only and preserves prepared
   startup owner signalling while the startup cohort is unsettled.
5. Reuse one `PaneManagementContext` when management and location target pane IDs
   match; retain a second projection only for a truly distinct target.
6. Preserve immediate resize feedback, but suppress the second unchanged
   geometry/refresh path. Startup and failed-placeholder retry remain explicit.
7. Do not convert pane graph storage to `AtomEntityMap`, evict hidden hosts, or
   build a CodeViewer runtime in this slice. Those require post-cut evidence.

Red/green proof:

- equal title/CWD cases create no runtime event, topology lookup, pane mutation,
  tab refresh, or view invalidation; changed cases retain exact order;
- recording AppKit owners prove each observed input invokes only its effect;
- ordinary layout performs zero membership scans; selection updates only the
  old/new host; missing-host restore is target-only; prepared startup routing is
  unchanged;
- management target equality produces one projection;
- resize sequences preserve visible geometry and produce no duplicate unchanged
  Ghostty refresh;
- existing startup restore, tab switching, drawers, focus, notification, and
  terminal geometry suites remain green.

Focused command:

```bash
mise run test -- --filter 'TerminalRuntimeTests|WorkspacePaneGraphAtomTests|PaneTabViewControllerTests|WorkspaceSurfaceCoordinatorActiveTabRestoreTests|PaneManagementContextTests|GhosttySurfaceViewGeometryCommitTests|TerminalGeometrySynchronizationTests|WorkspacePreparedContentMountCoordinatorTests'
```

Checkpoint: commit after focused proof, build/lint, and one marker-scoped native
interaction pass covering tab switch and resize.

Split trigger: the narrow cuts require canonical atom-family conversion, hidden
host eviction, startup redesign, or a new UI runtime.

## T7 — Add proportionate compile-time regression guards

Write surface:

- narrowly named SwiftSyntax rules under `Tools/AgentStudioArchitectureLint`;
- rule registration, inventory/parity/focused tests, and Good/Bad fixtures;
- outer architecture-lint test only if its inventory intentionally changes.

Rules:

- forbid local-only Terminal cases from invoking the semantic publication edge
  when the final type system alone cannot make it impossible;
- forbid direct Repo Explorer fleet projection/row-index construction inside
  `RepoExplorerView.body` when the final type surface alone cannot make it
  impossible.

Do not add a generic pure-atom rule, expensive-MainActor heuristic, shell/regex
checker, type-resolution framework, or control-flow analyzer.

Proof:

```bash
swift test --package-path Tools/AgentStudioArchitectureLint
mise run test -- --filter ArchitectureSwiftLintRulesTests
mise run lint
```

Checkpoint: commit only after behavior is green and good/bad/parity fixtures
pass.

## T8 — Integrated candidate proof

Artifact root:
`tmp/performance-proof/2026-07-17-targeted-runtime-pressure-reduction/candidate/`

Automated ladder:

```bash
mise run test-fast
mise run test-large
mise run test-webkit
mise run build
mise run lint
mise run test
```

Focused filters run before these broad gates as named in T1/T3/T4/T5/T6.

Performance cells:

1. Candidate-only deterministic Terminal contraction/activity equivalence.
2. Paired watched-folder/Git workload through the existing unchanged verifier.
3. Repo Explorer/AppKit proportionality under the same large-repository fixture,
   with deterministic latest-projection proof and paired existing distributions
   only where baseline and candidate populations are identical.
4. One candidate-only PID-targeted native smoke.
5. Paired combined real-app resource qualification.

Frozen combined-cell workload, executed as direct operator commands and not as
a committed script:

1. Start the shared observability stack. Launch the existing unchanged
   `verify-git-refresh-performance-workload` with exactly 118 repositories, 163
   worktrees, 14 active terminal panes, five Git writers, a 90-second writer
   duration, command-bar driving disabled, unsafe-no-auth/token escrow enabled,
   and a fresh trace name.
2. Wait on the existing state/IPC metadata for a fresh running PID and current
   terminal handle. Verify the Repo Explorer is the visible sidebar surface and
   reproduce the T2 mixed-group receipt: at least one stable expanded group with
   one visible status row and at least one stable collapsed group. A trial with
   all groups collapsed or no visible keyed status row is invalid. No
   presentation change is inferred from `command.execute`; current IPC does not
   execute tab navigation commands.
3. At elapsed seconds `0`, `10`, `20`, `30`, `40`, and `50`, invoke existing IPC
   `terminal-send` on the preserved terminal handle with the literal bounded
   shell command frozen in T2. Each burst emits exactly 5,000 newline-terminated,
   fixed-format 64-byte ASCII records whose body and SHA-256 match the receipt;
   total Terminal output is 30,000 records. Preserve the same bytes, pacing,
   handle role, and burst count in baseline and candidate.
4. The scored interval starts immediately before the first Terminal burst, only
   after Repo Explorer readiness, and ends after Git writers finish and the
   bounded quiescence predicate succeeds. A trial is invalid if the first burst
   cannot start while all five writers are live.
5. During the scored interval, capture the frozen manifest: direct process
   CPU-time boundary readings; one-second RSS; physical footprint at start,
   second 45, and post-quiescence; and marker-scoped Victoria events. Do not run
   `vmmap`, `/usr/bin/sample`, Instruments, or any other periodic sampler in the
   comparative trials.
6. Quiescence uses one common bounded 30-second state wait after writer
   completion. In both builds the interval-ending predicate requires filesystem
   accepted/queued logical demand `0`, Git logical pending/running demand `0`,
   and no final common runtime-channel/EventBus delivery debt. At that same
   endpoint the candidate additionally requires Terminal scheduled/follow-up
   drains `0`, activity pending timers/aggregates `0`, Repo Explorer projection
   pending/follow-up work `0`, and trace-identity refresh pending work `0`.
   Those candidate-only gauges are structurally not applicable to baseline and
   do not alter its interval-ending predicate. A timed-out native Git drain may
   remain only while counted against the existing physical slot bound and unable
   to commit current state. Failure to reach the applicable predicate invalidates
   the trial and fails stability proof; it is not extended ad hoc.

Comparability populations are external stimuli only: translated Terminal
actions/records, Git writer mutations, topology/status mutation stimuli, and
successful native actions. Each corresponding external population must differ
by no more than 2% between paired trials, with exact equality required where the
frozen command/action recipe makes it possible. Refresh admissions, drains,
tasks, fleet captures, structural inputs, accepted projections, and row-index
builds are measured optimization outcomes expected to contract; they never
invalidate comparability merely because they differ. The external populations
are not added into one synthetic unit. Secondary per-lane ratios may diagnose a
failed trial but cannot replace the primary gate.

The separate paired UI cell reuses the same 118-repository fixture but is not
folded into the resource interval. Before scoring, create the second disposable
terminal tab named by the T2 fixture-role receipt. Against the exact debug PID,
replay the frozen native recipe: 20 `nextTab`/`prevTab` cycles using its recorded
key chords, 20 visible-pane focus changes between its recorded pane roles, and
10 split-view resize out-and-back cycles using its recorded divider start,
delta, and return geometry while Git status updates continue. Use the existing
command shortcuts and accessibility surfaces; do not add IPC command execution
or a committed driver. Baseline and candidate must receive the same successful
action counts and target-role sequence. This cell proves
tab/main-pane/layout/resize proportionality and supplies paired sidebar,
tab-bar, pane-layout/restore, management-context, and terminal-geometry
distributions where their metric definitions are identical.

For paired cells 2, 3, and 5, T2 records one warm-up and at least three
qualifying baseline trials, and T8 records one warm-up and at least three
qualifying candidate trials. Compare median per-trial values against frozen
bands; never pool trials.

Absolute gates:

- local Terminal sample global posts/replay/deliveries: `0`;
- more than one pending drain per live key: `0`;
- retained sample storage growth with raw samples: `0`;
- mixed-workload semantic fact drops: `0`;
- unrelated-action full reconciliation: `0`;
- status-only Repo Explorer structural projections: `0`;
- more than one accepted Repo Explorer projection/row index per current
  structural input: `0`;
- ordinary layout pane/tab membership scans: `0`;
- already-complete active-tab restore fleet ordering/frame resolution: `0`;
- duplicate trace-identity fleet captures for one accepted effect: `0`;
- accepted/queued logical filesystem/Git debt after quiescence: `0`.

Timing/resource gates:

- compact MainActor apply p95 `<2 ms`, p99 `<5 ms`;
- candidate-only callback-to-current-commit queue age satisfies p95 `<8 ms`
  and p99 `<16 ms` in every qualifying candidate trial; it is excluded from
  paired comparison because the baseline has no equivalent emitter;
- fewer than three targeted service samples `>=20 ms` and none `>=60 ms` per
  qualifying trial;
- CPU, all-malloc-zones `blocks_in_use`, `size_in_use`, `max_size_in_use`,
  `size_allocated`, and paired targeted MainActor duty improve beyond the frozen
  one-sided noise band. Candidate-only Terminal admission/task counts separately
  satisfy the structural contraction gates. Allocation/retained-byte comparison
  uses only the identically sampled all-zones scope; candidate-only owner
  estimates cannot satisfy this gate;
- peak and post-quiescence physical footprint do not regress beyond the band.
  If baseline has repeatable workload-attributable footprint growth above the
  band, candidate growth must improve beyond the band. Symmetric RSS is
  secondary confirmation and the fallback only if `footprint` fails
  symmetrically in both builds;
- semantic counts/final state/native interaction/Git boundedness/sidebar
  content/tab/main-pane correctness do not regress.

Native smoke uses the existing debug runner, verifier, IPC client, notification
verification surfaces, and PID-targeted Peekaboo/computer-use. It checks
typing/caret, search lifecycle, scroll-away/follow-bottom, cursor/link,
notification appearance/clearing, Repo Explorer status/group visibility, tab
switching, pane-host visibility, and split-resize behavior. It runs in the
background where supported and never replaces the production app.

Stability includes an explicit relaunch gate after the workload/native smoke:
terminate only the exact debug PID recorded by the fresh state file, wait
boundedly for that PID to exit, relaunch through the unchanged
`run-debug-observability -- --detach` task with a new trace name, and require a
new PID and marker. Run unchanged `verify-debug-observability`, then use the
fresh IPC metadata to require `current-pane` and `terminal-status` readiness for
the restored terminal. Reuse neither the old marker nor old socket metadata.

## T9 — Review, remediate, and prepare the PR

1. Run `implementation-review-swarm` over the final diff and proof matrix.
2. Verify every candidate finding against source and accept/reject explicitly.
3. Apply one bounded remediation pass, rerunning affected local and higher proof.
4. Commit the proven remediation checkpoint.
5. Push the scoped branch and open/update the PR.
6. Use blocking GitHub watches with `--interval 45`; verify checks, comments,
   review threads, mergeability, and final pushed HEAD.
7. Stop with the PR ready and not merged.

## Shared-file integration ownership

| Shared file | First owner | Final owner | Rule |
| --- | --- | --- | --- |
| `PaneRuntimeEvent.swift` | T3 Terminal/search cut | T3 | one atomic Terminal/activity owner; no later compatibility edit |
| `WorkspaceSurfaceCoordinator.swift` and extensions | T4 fixed-key effects | T6 active-tab/host restore | serialize any overlapping edits; preserve startup mount routing |
| Repo Explorer projection/view sources | T5 | T5 | one feature owner integrates structural projection and keyed-row cutover |
| diagnostics recorder/projection/metrics | T1 | parent integration only | common meanings/buckets freeze after baseline |
| Terminal aggregate/control contract | T3 | T3 | one atomic sample/activity owner; no duplicate types |

## Checkpoint and rollback policy

Checkpoint commits:

1. corrected spec/plan artifact checkpoint;
2. T1a out-of-scope instrumentation removal;
3. T3 atomic Terminal contraction and off-main activity;
4. T4 filesystem/trace-identity proportionality;
5. T5 Repo Explorer structural projection;
6. T6 AppKit/main-pane reductions;
7. T7 static guards;
8. implementation-review remediation;
9. PR-ready state.

Baseline/candidate receipts under `tmp/performance-proof/` are ignored evidence,
not product code. Every code checkpoint requires its scoped proof first.

Rollback is a commit-level revert of the failing hard cut. Do not retain feature
flags, compatibility publication, dual event routes, or temporary fallback fleet
sync. Never revert unrelated user work or stage `.agents/`.

## Stop and replan triggers

- Reality contradicts the accepted actor/owner boundary.
- A task needs a generic mailbox/EventBus redesign, persistence system, mount
  generation, new topology algebra, or Git authority/capacity change.
- Required proof needs a new/expanded script/harness/backend.
- A required gate cannot pass inside its owning task.
- Comparable instrumentation changes after baseline capture.
- An unrelated build/test/tooling failure would require out-of-scope edits.

Otherwise, phase and checkpoint completion are not stop conditions; continue to
the PR-ready non-merge terminal.
