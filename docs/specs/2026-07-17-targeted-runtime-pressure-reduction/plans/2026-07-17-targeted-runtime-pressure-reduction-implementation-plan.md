# Targeted Runtime Pressure Reduction Implementation Plan

Status: reviewed; ready for `implementation-execute-plan`

Accepted source:
`docs/specs/2026-07-17-targeted-runtime-pressure-reduction/targeted-runtime-pressure-reduction.md`

Accepted source commit: `677ff7db`

Behavioral baseline source: `5dea96b6`

Source coverage: `877/877` lines

## Outcome

Reduce AgentStudio CPU, retained/allocation pressure, fanout/task amplification,
and targeted MainActor duty during simultaneous Terminal, watched-folder/Git,
and Bridge work. Coalescible observations are compressed before expensive work;
semantic facts stay exact; heavy derivation runs off MainActor; compact current
state is applied on MainActor; and the result is proven against an identically
instrumented baseline in the real debug app.

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
- Hard-delete the Bridge-only `paneFilesystemContext` route; retain no dual path.
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
| R3: activity, search, presentation, terminal controls, Inbox behavior remain correct | TR-6, TR-8..TR-12, P-4/P-5/P-16 | T3/T4/T8 | injected-clock semantic oracle, focused native tests, one PID-targeted smoke | candidate PID, executable, marker, managed-surface lifetime | required below smoke |
| R4: ordinary workspace changes avoid fleet reconciliation; actual topology still converges | FS-1..FS-9, P-6/P-8a | T5 | recording-source/index/coordinator tests plus unchanged large-worktree workload | fixture/source/instrumentation fingerprints and zero logical pending debt | required |
| R5: matching current Bridge controllers receive convergent direct invalidation and stale work cannot commit | BR-1..BR-8, P-7/P-8/P-8a | T6 | projection/coordinator/controller gated tests; obsolete event absent; existing Bridge verifier | controller/package/review/pane/worktree identity plus fresh marker/scenario | required |
| R6: CPU, attributable retained/allocation pressure, admission, and targeted MainActor duty improve without footprint regression | P-9..P-14 | T1/T2/T8 | identically instrumented baseline/candidate, three qualifying trials, median per-trial comparison | frozen schema/operation/workload inventory, source/binary hashes, fresh PID/marker | required for instrumentation math |
| R7: stability, type safety, atom purity, authority, privacy, and repo health hold | MA-1..MA-5, TY-1..TY-5, SEC-1..SEC-9, P-15 | all/T7/T8 | focused tests, build/lint/full suites, content canaries, relaunch/readiness, implementation review | final scoped diff/current HEAD/fresh proof | required where behavior changes |
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
T2  freeze instrumented baseline
 │   warm-up + 3 qualifying trials + calibrated receipt
 │
 ├──── freeze one private Terminal aggregate/control contract ──────┐
 │                                                                  │
 ├─► T3 Terminal contraction ─► T4 off-main activity ───────────────┤
 │     local proof                local proof                         │
 │                                                                  │
 └─► T5 filesystem proportionality ─────────────────────────────────┤
       local proof + unchanged workload                              │
                                                                    ▼
T6  direct Bridge invalidation and stale-refresh rejection
 │   local proof + hard deletion of old route
 ▼
T7  narrow final SwiftSyntax guards
 │
 ▼
T8  integrated candidate proof + PID-targeted native smoke
 │
 ▼
T9  implementation review/remediation + PR readiness, no merge
```

T5 may run in parallel with T3/T4 after T2. T3/T4 may be sequential if their
private contract would otherwise be edited by two agents. T6 follows T5 and the
T3 shared-contract edit. T7 is last because it encodes the final code shape.

## T0 — Revalidate the executable surface

Purpose: ensure the accepted plan still maps to live code before edits.

Actions:

1. Confirm branch, HEAD, scoped status, and protected `.agents/` state.
2. Recheck the source anchors named in the accepted spec and planning boundary
   lane.
3. Run the smallest existing pre-change focused suites for diagnostics,
   Terminal, activity, filesystem, and Bridge to distinguish pre-existing
   failures from regressions.
4. Record any unrelated failure without editing its infrastructure.

Gate: no stale ownership, missing required source, or unrelated dirty overlap.

## T1 — Add common product instrumentation without changing behavior

Purpose: create the identical comparable metric layer used by baseline and
candidate.

Write surface:

- `AgentStudioPerformanceTraceRecorder.swift`
- `AgentStudioOTLPTraceProjection.swift`
- `AgentStudioOTLPPerformanceMetrics.swift`
- `AgentStudioOTLPBootstrapper.swift`
- new `AgentStudioProcessMemorySampler.swift`
- `Features/Bridge/Runtime/BridgePaneController+DiffCommands.swift`
- `Features/Bridge/Runtime/BridgePaneController.swift` only to extend its
  existing bounded native telemetry call with typed numeric attributes
- existing diagnostics and owner tests

Frozen comparative measurement manifest:

| Event/body or external sample | Emitter file and owning symbol | Owner scope | Value and normalization | Comparison | Scored membership |
| --- | --- | --- | --- | --- | --- |
| `performance.terminal.action_capture` | T3 copied-action classification boundary | process and controlled disposition only | elapsed ms and translated-action count from the bounded owner | candidate-only absolute | classification belongs to interval |
| `performance.terminal.mainactor_route` | T3 accumulator enqueue and compact-apply successor | process and controlled disposition only | queue-age ms, service ms, task/admission count | candidate-only absolute | enqueue and completion both belong to the scored interval |
| `performance.terminal.local_sample` | T3 controlled disposition admission | process and disposition, never pane/surface ID | offered/replaced/equal-suppressed count | candidate-only absolute | offer belongs to interval |
| `performance.terminal.drain` | T3 Terminal-local accumulator; `offer`, scheduled drain, and follow-up completion | process and fixed disposition key | scheduled/follow-up/pending count and retained entry/estimated byte gauge; per offer | candidate-only absolute | drain scheduled or completed inside interval |
| `performance.terminal.compact_apply` | T3 compact presentation apply boundary | process and disposition | queue-age ms, service ms, accepted/equal-suppressed mutation count | candidate-only absolute | enqueue and commit both inside interval |
| `performance.terminal.activity_projection` | T4 bounded activity aggregate owner | process and semantic outcome | evidence/aggregate/fact/apply count and service ms | candidate-only absolute | aggregate admission or commit inside interval |
| `performance.runtime_channel.admission` | T3 fact-only runtime-channel boundary | process and finite semantic event class | local post/replay/outbound/drop count | candidate-only absolute | admitted fact belongs to interval |
| `performance.eventbus.delivery` | existing EventBus diagnostics plus the T3 fact-only route | process and finite semantic event class | posts/deliveries/replay/drops | existing aggregate diagnostics for baseline; candidate-only class detail | diagnostics snapshot belongs to interval |
| existing `performance.coordinator.write` filesystem phases | `WorkspaceSurfaceCoordinator+FilesystemSource.swift`; existing source-sync and pane-projection records | process and existing controlled phase | existing counts plus total/index/MainActor-apply durations | paired without emitter changes | existing bounded record belongs to interval |
| `performance.bridge.refresh` | `BridgePaneController+DiffCommands.swift`; current event handler/refresh and T6 direct-dirty successor | process and refresh phase | invalidation/coalesced-demand/active/stale-reject/final-commit count and elapsed ms; per accepted invalidation | paired for invalidation/refresh/commit and existing stages; candidate-only coalescing/stale counters | invalidation accepted inside interval |
| `performance.process.malloc_zone` | `AgentStudioProcessMemorySampler.swift`; one diagnostics-owned sampler installed by `AgentStudioPerformanceTraceRecorder` only when performance tracing is enabled | all process malloc zones in both builds | `blocks_in_use` count plus `size_in_use`, `max_size_in_use`, and `size_allocated` bytes from `malloc_zone_statistics(nil, ...)`; report interval high-water, end-minus-start growth, and post-quiescence value; normalize by scored wall interval and separately by each accepted-work population only for diagnosis | paired attributable allocation/retained-byte evidence | one sample/second inside the scored interval plus one post-quiescence sample |
| process CPU | direct `ps -o time=` start/end reading for the exact candidate PID | process | CPU-time delta / scored wall interval; additionally per accepted work only when counts differ | paired | two boundary samples |
| RSS | direct `ps -o rss=` for the exact PID | process | KiB, one sample/second; interval maximum and post-quiescence | paired secondary confirmation | timestamps inside interval plus one post-quiescence sample |
| physical footprint | direct `/usr/bin/footprint -p <pid>` | process plus child/helper population declared in the receipt | physical-footprint bytes at scored start, fixed 45-second point, and post-quiescence; no `vmmap` polling | paired primary physical-memory evidence | three fixed samples |

The targeted MainActor duty inventory is exactly
`terminal.action_capture`, `terminal.mainactor_route`,
`terminal.compact_apply`, the MainActor apply phase of
filesystem phases of `coordinator.write`, and the MainActor commit phase of
`bridge.refresh`.
No other operation may be added to one side of the comparison. Existing bounded
filesystem and Bridge seams remain event-driven. T1 must not add a trace-log
record per Terminal callback, runtime-channel emit, or EventBus delivery. Their
exact counters and duration buckets are installed only when T3/T4 create
bounded owners and are absolute candidate gates rather than paired metrics. The
only product timer added
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
  payload, error, token, Git output, or Bridge package data.
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

## T2 — Capture and freeze the baseline

Behavioral source: `5dea96b6` plus the T1 instrumentation commit.

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
  Git and combined real-app pressure;
- Bridge stage distributions are paired only after one unscored warm-up and at
  least three qualifying baseline trials and three qualifying candidate trials
  with identical metric populations; otherwise they are absolute-only;
- per-trial values are summarized first; compare medians across trials; do not
  pool samples;
- fixture floors and one-sided noise bands are frozen separately from product
  budgets in `baseline/baseline-calibration.md`.

Use `verify-git-refresh-performance-workload` and all other existing proof
scripts unchanged. Additional direct commands/queries are recorded in receipts,
not converted into a committed runner/comparator.

Gate: parent verifies calibration receipt and identical instrumentation contract.
If common metric meaning changes later, invalidate the comparison and recollect;
do not reinterpret it.

## T3 — Contract coalescible Ghostty samples before MainActor tasks

Write surface:

- Ghostty action router/observed-action/adapter files;
- new narrowly named Terminal-local disposition, accumulator, lifetime, and
  batch contract files;
- `SurfaceManager`/`SurfaceTypes` only for managed lifetime lookup/cleanup;
- `TerminalRuntime`;
- Terminal/search portions of `PaneRuntimeEvent.swift`;
- focused Terminal/runtime/replay/EventBus/IPC tests.

Implementation contract:

1. Copy any borrowed C payload before callback return.
2. Classify with one exhaustive typed disposition: exact command/fact, latest
   presentation, activity evidence, exact local lifecycle, diagnostic outcome.
3. Preserve exact command/fact routing and synchronous handled result.
4. Offer coalescible copied values through one synchronous per-surface
   linearization point into fixed compile-time keys.
5. Permit one pending drain and one convergent follow-up per live surface.
6. Resolve and revalidate managed surface lifetime immediately before apply.
7. Compare-and-remove on close/replacement so old work cannot affect a reused
   address or replacement surface.
8. Apply latest current presentation once; suppress equal writes.
9. Make search active/inactive a discriminated lifecycle. Barrier identity
   prevents late total/selection from reactivating ended search.
10. Hard-cut local presentation from runtime channel, replay, EventBus, and IPC
    waits; exact semantic facts remain unchanged.

Red/green proof:

- focused accumulator/router/adapter/runtime/search invariants;
- 100,000 coalescible samples across at least 10 live lifetime keys in the
  existing large/default suite;
- independent latest-value and sufficient-statistics oracles;
- reentrant/concurrent offers, gated drains, start/end/cancel barriers,
  close/address reuse, bounded storage, zero final debt;
- exact semantic count/order, zero sample-caused fact drops, and zero local
  runtime/replay/EventBus/IPC activity.

Focused command:

```bash
mise run test -- --filter 'TerminalLocalActionAccumulatorTests|GhosttyActionRouterTests|GhosttyAdapterTests|GhosttyEventRoutingCoverageTests|GhosttyScrollTranslationTests|TerminalRuntimeTests|PaneRuntimeEventChannelTests|EventBusRuntimeEnvelopeTests|EventReplayBufferTests'
```

Checkpoint: commit only after focused and large deterministic proof passes.

Split trigger: implementation needs a generic mailbox, durable generation,
strong view retention, actor-per-pane fleet, or EventBus change.

## T4 — Move activity windows and quiet timing off MainActor

Write surface:

- `TerminalActivityRouter.swift`;
- the single Terminal-private aggregate/control contract owned with T3;
- `TerminalActivityAtom.swift`;
- `AppDelegate+InboxNotificationBoot.swift`;
- `InboxNotificationRouter.swift`;
- existing activity, Inbox, heuristic, and derived-event tests.

Implementation contract:

1. `TerminalActivityRouter` becomes the off-main owner of bounded aggregates,
   windows, injected-clock quiet timers, settled/revoked projection, and typed
   control order.
2. Attention, observation, read/dismiss, reset, close, and semantic revocation
   detach earlier evidence, submit aggregate then control, and start a new
   aggregate for later evidence.
3. Historical attention is carried in ordered evidence/control; it is never
   inferred from current delayed MainActor state.
4. MainActor supplies narrow context and applies compact accepted state only.
5. `TerminalActivityAtom` stores current state/simple mutations only.
6. Inbox consumes derived pinned/observed/settled outcomes, not raw scrollbar
   samples.

Red/green proof:

- injected-clock raw-versus-aggregate semantic oracle;
- focus/blur, observe/read/dismiss, reset, semantic revocation, growth-before-
  reset, pinned edges, duplicates, close/replacement, quiet settlement, stop/
  cancellation, and no post-stop mutation;
- existing derived notification integration remains green.

Focused command:

```bash
mise run test -- --filter 'TerminalActivityRouterTests|TerminalActivityDerivedEventTests|TerminalActivityAgentSettledHeuristicTests|TerminalActivityAtomTests|DerivedActivityNotificationIntegrationTests|DerivedTerminalActivityNotificationRegressionTests|InboxNotificationRouterTests|InboxNotificationRouterObservedPaneTests|InboxNotificationRouterPayloadTests'
```

Checkpoint: commit after semantic equivalence and cancellation proof.

Split trigger: atom workflow, EventBus raw replay, current-state historical
inference, wall-clock test sleeps, or actor-per-pane ownership becomes necessary.

## T5 — Replace unconditional filesystem fleet work with fixed-key effects

Write surface:

- `WorkspaceSurfaceCoordinator+ActionExecution.swift`;
- CWD/active-pane edges in `WorkspaceSurfaceCoordinator.swift`;
- existing pane lifecycle membership edges;
- new `WorkspaceSurfaceCoordinator+FilesystemEffects.swift` for fixed-key
  coordinator effects;
- `FilesystemGitPipeline.swift` only if an existing capability needs exposure;
- existing coordinator/projection/CWD/Git authority tests.

Implementation contract:

1. Delete the unconditional action-tail full synchronization.
2. Pane create/mount/close updates that pane only.
3. CWD/worktree reassignment updates that pane and affected worktree activity.
4. Active pane changes update active-worktree priority only.
5. No-op, layout, sidebar, Inbox, and presentation actions schedule no
   filesystem reconciliation.
6. Cold boot, explicit rebuild, and accepted topology deltas retain one full
   reconciliation through the existing topology effect.
7. Preserve all filesystem authority/currentness and Git capacity semantics.

Red/green proof:

- recording-source tests prove zero full capture for unrelated actions and
  affected-key-only updates;
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

## T6 — Direct Bridge dirty demand and stale-result rejection

Write surface:

- `PaneFilesystemProjectionContracts.swift`;
- `FilesystemProjectionIndex.swift`;
- Bridge projection/delivery in
  `WorkspaceSurfaceCoordinator+FilesystemSource.swift`;
- new `WorkspaceSurfaceCoordinator+BridgeFilesystemInvalidation.swift` for
  direct controller invalidation;
- `WorkspaceSurfaceCoordinator.swift` old handler removal;
- `WorkspaceSurfaceCoordinator+NonterminalContentMounting.swift`;
- `BridgePaneController.swift` and `BridgePaneController+DiffCommands.swift`;
- obsolete `paneFilesystemContext` portions of runtime event, trace summary, and
  replay sizing;
- existing projection/coordinator/Bridge tests.

Implementation contract:

1. Projection returns a compact typed reason plus pane/current worktree
   association only for affected Bridge panes.
2. Coordinator resolves the currently mounted controller immediately before a
   non-awaiting dirty submission.
3. Composition injects a weak/lifetime-safe association predicate; Bridge does
   not import stores, atoms, ViewRegistry, or filesystem authority.
4. Controller retains one active refresh plus one latest-convergent follow-up.
5. Cancellation, lifecycle, package/review identity, and association are checked
   after awaits, before content activation, and before final commit.
6. Teardown cancels work and clears pending dirty state.
7. Delete the derived runtime envelope and every construction/handler/replay
   path in the same hard cut.

Red/green proof:

- matching/nonmatching/non-Bridge/unmounted/stale delivery;
- no global ingestion await;
- overlap, provider failure, teardown, same-controller reassignment, current
  provider oracle, no stale activation/commit, no ownership cycle;
- zero obsolete envelope construction/post/replay;
- existing Bridge verifier unchanged, with direct marker-scoped distributions
  compared only for identical populations.

Focused command:

```bash
mise run test -- --filter 'WorkspaceSurfaceBridgeFilesystemRefreshTests|FilesystemProjectionIndexTests|BridgePaneControllerTests|BridgePaneControllerTelemetryTests|BridgePerformanceTraceRecorderTests'
```

Checkpoint: commit after direct-delivery/currentness proof and obsolete-path
source scan.

Split trigger: currentness requires a mount generation, store/atom/ViewRegistry
access inside Bridge, a second scheduler, strong cycle, or awaited global work.

## T7 — Add proportionate compile-time regression guards

Write surface:

- narrowly named SwiftSyntax rules under `Tools/AgentStudioArchitectureLint`;
- rule registration, inventory/parity/focused tests, and Good/Bad fixtures;
- outer architecture-lint test only if its inventory intentionally changes.

Rules:

- forbid local-only Terminal cases from invoking the semantic publication edge
  when the final type system alone cannot make it impossible;
- forbid obsolete Bridge event construction if compiler deletion is not already
  sufficient.

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
3. Bridge deterministic convergence plus paired existing-stage distributions
   only for identical populations.
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
   terminal handle. Invoke existing IPC `command-execute openBridgeReview`; wait
   for the marker-scoped existing Bridge package/content-ready event for the
   active fixture worktree. This is the sole Bridge opening/refresh trigger.
3. At elapsed seconds `0`, `10`, `20`, `30`, `40`, and `50`, invoke existing IPC
   `terminal-send` on the preserved terminal handle with a bounded shell loop
   that emits exactly 5,000 newline-terminated, fixed-format 64-byte ASCII
   records. Total Terminal output is 30,000 records. Preserve the same payload,
   pacing, handle, and burst count in baseline and candidate.
4. The scored interval starts immediately before the first Terminal burst, only
   after Bridge readiness, and ends after Git writers finish and the bounded
   quiescence predicate succeeds. A trial is invalid if the first burst cannot
   start while all five writers are live.
5. During the scored interval, capture the frozen manifest: direct process
   CPU-time boundary readings; one-second RSS; physical footprint at start,
   second 45, and post-quiescence; and marker-scoped Victoria events. Do not run
   `vmmap`, `/usr/bin/sample`, Instruments, or any other periodic sampler in the
   comparative trials.
6. Quiescence is one bounded 30-second state wait after writer completion. It
   requires Terminal scheduled/follow-up drains `0`, activity pending timers/
   aggregates `0`, filesystem accepted/queued logical demand `0`, Git logical
   pending/running demand `0`, Bridge active/pending refresh `0`, and no final
   runtime-channel/EventBus delivery debt. A timed-out native Git drain may
   remain only while counted against the existing physical slot bound and
   unable to commit current state. Failure to reach this predicate invalidates
   the trial and fails stability proof; it is not extended ad hoc.

Accepted-work normalizers are frozen per lane: translated Terminal actions/raw
coalescible samples, accepted Git writer commits and Git refresh admissions, and
accepted Bridge invalidations/final commits. Primary CPU duty is comparable only
when each accepted-work population differs by no more than 2% between paired
trials. Otherwise the trial is invalid; the populations are not added into one
synthetic unit. Secondary per-lane ratios may diagnose a failed trial but cannot
replace the primary gate.

Run one warm-up and at least three qualifying candidate trials. Compare median
per-trial values against frozen bands; never pool trials.

Absolute gates:

- local Terminal sample global posts/replay/deliveries: `0`;
- more than one pending drain per live key: `0`;
- retained sample storage growth with raw samples: `0`;
- `paneFilesystemContext` global traffic: `0`;
- mixed-workload semantic fact drops: `0`;
- unrelated-action full reconciliation: `0`;
- stale Bridge commits: `0`;
- accepted/queued logical filesystem/Git debt after quiescence: `0`.

Timing/resource gates:

- compact MainActor apply p95 `<2 ms`, p99 `<5 ms`;
- if baseline callback-to-current-commit queue age already satisfies p95
  `<8 ms` and p99 `<16 ms`, candidate queue age must remain within the frozen
  one-sided regression band; if baseline misses either threshold, candidate
  must satisfy both absolute thresholds and improve the median tail beyond the
  frozen one-sided noise band;
- fewer than three targeted service samples `>=20 ms` and none `>=60 ms` per
  qualifying trial;
- CPU, all-malloc-zones `blocks_in_use`, `size_in_use`,
  `max_size_in_use`, and `size_allocated`, MainActor admission, and targeted
  MainActor duty improve beyond the frozen one-sided noise band. Allocation/
  retained-byte comparison uses only the identically sampled all-zones scope;
  candidate-only owner estimates cannot satisfy this gate;
- peak and post-quiescence physical footprint do not regress beyond the band.
  If baseline has repeatable workload-attributable footprint growth above the
  band, candidate growth must improve beyond the band. Symmetric RSS is
  secondary confirmation and the fallback only if `footprint` fails
  symmetrically in both builds;
- semantic counts/final state/native interaction/Git boundedness/Bridge
  correctness do not regress.

Native smoke uses the existing debug runner, verifier, IPC client, notification
and Bridge verification surfaces plus PID-targeted Peekaboo/computer-use. It
checks typing/caret, search lifecycle, scroll-away/follow-bottom, cursor/link,
notification appearance/clearing, and refreshed Bridge content. It runs in the
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
| `PaneRuntimeEvent.swift` | T3 Terminal/search cut | T6 obsolete Bridge removal | serialize edits; T6 rebases on T3 shape |
| `WorkspaceSurfaceCoordinator.swift` | T5 fixed-key edges | T6 old Bridge handler removal | T5 integrates first |
| diagnostics recorder/projection/metrics | T1 | parent integration only | common meanings/buckets freeze after baseline |
| Terminal aggregate/control contract | one T3/T4 integration owner | same owner | freeze before parallel work; no duplicate types |

## Checkpoint and rollback policy

Checkpoint commits:

1. reviewed plan;
2. behavior-preserving instrumentation;
3. T3 Terminal contraction;
4. T4 off-main activity;
5. T5 filesystem proportionality;
6. T6 Bridge direct cutover;
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
