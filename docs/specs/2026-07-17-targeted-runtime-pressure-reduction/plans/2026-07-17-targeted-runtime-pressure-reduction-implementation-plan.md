# Targeted Runtime Pressure Reduction Implementation Plan

Status: reviewed and ready for `implementation-execute-plan`

Accepted source:
`docs/specs/2026-07-17-targeted-runtime-pressure-reduction/targeted-runtime-pressure-reduction.md`

Accepted source SHA-256:
`52ca5f8e7d2ca8c214688e9873d2b1601e8da9ba6482853f16dc7f23e41f4c7e`

Source coverage: `856/856` lines

Behavioral baseline source: `5dea96b6`

## Outcome

Reduce AgentStudio CPU, attributable allocation/retained-memory pressure,
EventBus fanout, task creation, and MainActor service under two pressures:

1. Ghostty/Terminal output and local terminal interaction.
2. Watched-folder, filesystem-projection, and Git-refresh activity across large
   repository populations.

The implementation contracts local Terminal samples before shared publication,
keeps semantic facts exact, replaces unconditional filesystem fleet capture with
affected-key effects, and proves the result with permanent tests plus the
existing debug, IPC, Victoria, and watched-folder workload surfaces.

Repo Explorer, AppKit hosts, tabs, panes, notifications, and startup are
unchanged downstream regression consumers. They are not implementation lanes.

The terminal condition is a reviewed, proven, PR-ready branch. The PR is not
merged by this goal.

## Fixed Scope

### In scope

- A narrow, fixed-key `TerminalLocalActionAccumulator` owned by Terminal.
- Exhaustive typed classification before per-sample MainActor scheduling.
- Local/coalesced scrollbar, search, and mouse presentation state.
- Bounded scrollbar activity aggregates and off-main activity projection.
- Exact existing command/fact order and EventBus/replay/IPC behavior.
- Affected-key pane, CWD, activity, and active-worktree filesystem effects.
- One existing full filesystem reconciliation for boot, explicit rebuild, and
  accepted topology mutation batches.
- Existing content-safe instrumentation and existing proof surfaces.

### Out of scope

- EventBus, Ghostty, zmx, callback-thread, or tick redesign.
- Agent hooks, lifecycle IPC, Herdr-style detection, screen polling, or text
  classification.
- Repo Explorer, SwiftUI, AppKit, main-pane, tab, layout, restore, or geometry
  implementation changes.
- Bridge, BridgeWeb, File View, persistence, startup, identity, or atom redesign.
- Generic mailboxes, reusable admission frameworks, actor-per-pane fleets,
  durable generations, leases, revisions, repair, or new topology algebra.
- Git slot, timeout, late-result, physical-capacity, or
  `GIT_OPTIONAL_LOCKS=0` changes.
- New scripts, runners, harnesses, ledgers, proof backends, or test-only product
  seams.

## Requirements And Proof Matrix

| Requirement | Spec source | Owner | Required proof | Freshness guard |
| --- | --- | --- | --- | --- |
| R1. Coalescible Terminal samples use bounded/sublinear admission and create zero runtime/replay/EventBus/IPC traffic. | TR-1..TR-9, TR-13..TR-15, P-1..P-3a | T3 | red/green tests; 100,000 samples across 10+ live surface keys; zero final debt | current candidate HEAD; exhaustive translated-signal inventory |
| R2. Search, presentation, activity, notification, and exact semantic behavior remain correct while activity projection moves off-main. | TR-6, TR-8..TR-12, P-4/P-5 | T3 | injected-clock activity oracle; search barriers; exact-fact order; existing Inbox/activity regressions | current surface lifetime and candidate executable |
| R3. Ordinary workspace changes are affected-key work and actual topology changes still converge. | FS-1..FS-9, P-6/P-7 | T4 | recording-source/index/coordinator tests; topology oracle; existing large-worktree workload | current candidate HEAD; fresh marker; zero logical debt |
| R4. Filesystem authority, containment, currentness, incomplete-evidence safety, Git capacity, no-lock behavior, telemetry privacy, and replay bounds remain intact. | SEC-1..SEC-9, P-7 | T2a/T3/T4 | authority, containment, timeout, late-result, shell-Git, replay, and content-canary suites | current registration identity, candidate HEAD, and workload run |
| R5. Every closed source-admission and semantic-classification family changed by this work is exhaustive at compile time; local-only Terminal samples cannot bypass contraction into semantic publication. | TY-1..TY-4 | T3/T4/T5 | exhaustive switches without default fallthrough; narrow SwiftSyntax publication-edge rule with good/bad fixtures; focused classification tests | current translated Terminal, worktree/filesystem/Git, and Inbox event inventories |
| R6. The durable architecture docs teach typed source admission, bounded contraction, semantic projection, and the approved domain-specific producer paths without presenting a generic framework. | TY-1..TY-4 and accepted user clarification | T5 | docs-maintain reconciliation against current code; link and terminology checks; concise AGENTS pointer | final reviewed implementation types and source paths |
| R7. Resource use and targeted MainActor duty improve without memory, correctness, or stability regression. | P-9..P-16 | T2/T2a/T5 | comparable trials, Victoria metrics, exact final state, bounded quiescence, LaunchServices smoke, relaunch/readiness | same paired instrumentation, workload, hardware, flavor, marker, and PID rules |
| R8. Branch is reviewed and PR-ready without merge. | Goal terminal condition | T6 | one review/remediation cycle; focused/full gates; CI/checks/comments/threads/mergeability | final pushed HEAD |

If a task cannot satisfy its proof inside its write boundary, stop and replan
that task. Do not weaken or move proof to a later catch-all phase.

## Execution DAG

    T0/T1  completed scope cleanup and comparable instrumentation
       │
       ▼
    T2     minimal comparable baseline with existing tooling
       │
       ▼
    T2a    candidate-only bounded aggregate metric vocabulary
       │
       ├───────────────────────┐
       ▼                       ▼
    T3 Terminal contraction  T4 Filesystem affected-key effects
       │                       │
       └───────────┬───────────┘
                   ▼
    T5 focused/full validation + Victoria/debug smoke
                   │
                   ▼
    T6 one implementation review/remediation + PR readiness

T3 and T4 may execute in parallel only when production and test write sets stay
disjoint. `WorkspaceSurfaceCoordinator` routing overlap is integrated by one
parent owner. Neither lane edits EventBus implementation.

## T0 — Revalidate Scope And Repo State — Complete

The branch was cleaned back to pure atom/state boundaries and the implementation
scope was reduced to Terminal plus filesystem/Git pressure.

Before each implementation checkpoint:

1. Re-read this plan, the accepted spec section, and the live owner files.
2. Confirm `git status --short` and preserve untracked `.agents/`.
3. Stop if the required change crosses an out-of-scope boundary.

## T1 — Comparable Instrumentation Foundation — Complete

The branch already contains the shared product instrumentation, content-safety
checks, duration buckets, process-resource sampling, quiescence metrics, and
strict-SQLite workload correction required for baseline/candidate proof.

Relevant checkpoints:

- `25678fb2` — comparable runtime-pressure instrumentation.
- `a9ad84b2` and `1564aa8e` — out-of-scope Bridge instrumentation removed.
- `9ecfb00c` — runtime quiescence instrumentation.
- `bb6dbd60` — existing workload corrected for strict SQLite startup.

Paired metric meanings and buckets are frozen for T2-T5. T2a may add only the
candidate-only bounded aggregate vocabulary already required by the spec.
Existing sidebar, tab, pane, and geometry metrics may be observed as passive
no-regression signals; they do not create UI implementation tasks.

## T2 — Capture The Minimal Comparable Baseline

Purpose: freeze only the evidence needed to judge T3 and T4.

Use the existing isolated debug runner, Victoria stack, IPC, and
`verify-git-refresh-performance-workload` task. Do not create or modify a
runner, script, harness, comparator, or app control seam.

Actions:

1. Reuse behavioral source `5dea96b6` with the already-prepared identical
   measurement layer. Verify equal metric meanings, buckets, resource scope,
   fixture, and strict-SQLite workload correction.
2. Run one unscored warm-up and at least three qualifying baseline trials for
   the existing watched-folder/Git workload.
3. Run one warm-up and at least three qualifying combined trials using the same
   Git fixture plus bounded Terminal output sent through existing IPC.
4. Use the established population and quiescence rules from
   `tmp/performance-proof/2026-07-17-targeted-runtime-pressure-reduction/baseline/baseline-calibration.md`.
   Its historical mixed expanded/collapsed Repo Explorer group requirement is
   explicitly superseded and is not a qualification gate. Combined
   qualification depends only on the frozen Git population, Terminal stimulus,
   fresh process/marker identity, resource receipts, and bounded zero debt.
   Record fresh marker, PID, executable/source identity,
   accepted external stimuli, CPU duty, allocation/retained-byte measurements,
   physical footprint/RSS, targeted MainActor duty, and final logical debt.
5. Freeze one-sided noise bands from per-trial medians. Never pool trials.
6. Treat metrics absent or semantically different in the baseline as absolute
   candidate gates, not comparative claims.

Gate:

- same debug flavor, fixture, hardware/display environment, trace tags, and
  bounded quiescence rule;
- watched-folder/Git accepted and queued logical debt reaches zero;
- combined trials begin while the declared Git writers are active;
- no production, beta, or unrelated debug AgentStudio process is driven,
  signalled, stopped, or replaced.

No commit is required for T2 unless an existing source artifact changes. Any
required proof-infrastructure change is a stop/replan condition.

## T2a — Install Candidate-Only Aggregate Metric Vocabulary

Purpose: expose the absolute T3/T4 gates through the existing Victoria path
without changing paired T1 meanings or creating per-sample trace pressure.

Write surface is limited to:

- `Infrastructure/Diagnostics/AgentStudioPerformanceTraceRecorder.swift`;
- `Infrastructure/Diagnostics/AgentStudioOTLPTraceProjection.swift`;
- `Infrastructure/Diagnostics/AgentStudioOTLPPerformanceMetrics.swift` only if
  an existing aggregate mapping requires it; and
- their permanent recorder/projection/metric/privacy tests.

Add controlled candidate-only event/attribute vocabulary for:

- Terminal offered/replaced/equal-suppressed counts, scheduled/follow-up drain
  counts, retained-entry/byte gauges, activity aggregates, compact applies, and
  queue/service timing;
- filesystem full-reconciliation versus affected-key requests; and
- trace-identity refresh, coalescence, fleet capture, and equal suppression.

Emitters remain owner-local to T3/T4 and publish only bounded drain/effect
snapshots. No trace record is emitted per raw Terminal callback, filesystem
path, EventBus delivery, or Git status.

Proof:

    mise run test -- --filter 'AgentStudioPerformanceTraceRecorderTests|AgentStudioOTLPTraceProjectionTests|AgentStudioOTLPPerformanceMetricsTests'
    mise run build
    mise run lint

Checkpoint: commit the behavior-preserving candidate vocabulary before T3/T4
parallel work. T3/T4 may wire only their own aggregate emitters; neither may
redefine the shared vocabulary.

Stop/replan if this requires a new metric backend, script, runner, harness,
identifier/path dimension, or paired-metric semantic change.

## T3 — Contract Terminal Samples Before MainActor Scheduling

### Write surface

Likely production files:

- `Features/Terminal/Ghostty/GhosttyActionRouter.swift` and its observed/runtime
  routing extensions.
- New narrowly named Terminal-owned `GhosttyActionDisposition` and
  `TerminalLocalActionAccumulator` sources.
- `Features/Terminal/Ghostty/SurfaceManager.swift` and surface types only for
  existing lifetime lookup and cleanup.
- `Features/Terminal/Runtime/TerminalRuntime.swift`.
- `Features/Terminal/Routing/TerminalActivityRouter.swift`.
- New Terminal-owned `TerminalActivityProjector.swift` for off-main aggregate
  state, timers, and semantic derivation.
- `Features/Terminal/State/MainActor/Atoms/TerminalActivityAtom.swift` only for
  compact current-state apply.
- `App/Boot/AppDelegate+InboxNotificationBoot.swift` only for the private
  router/projector context and typed-control wiring.
- Terminal/search cases in `Core/RuntimeEventSystem/Contracts/PaneRuntimeEvent.swift`.
- `Features/InboxNotification/Routing/InboxNotificationRouter.swift` only for
  required derived batch/settled consumption.

Tests stay in the permanent Swift Testing suite beside these owners.

### Implementation contract

1. Copy borrowed Ghostty payloads before callback return and preserve the
   synchronous handled Boolean.
2. Classify every translated action through one exhaustive discriminated enum:
   exact command/fact, latest presentation, activity evidence, exact local
   lifecycle, or diagnostic outcome.
3. Preserve the current route and order for exact commands and semantic facts.
4. Offer copied coalescible values to one synchronous per-surface linearization
   point with a fixed compile-time key set. Storage is bounded by live surfaces
   and keys, never raw sample count.
5. Allow at most one scheduled drain per live surface while work is pending,
   with one convergent follow-up when offers arrive during a drain.
6. Reuse existing managed-surface identity plus non-retaining lifetime evidence.
   Revalidate before apply and compare-and-remove on cleanup so old work cannot
   affect a replacement or reused address.
7. Apply latest scrollbar/search/mouse presentation in one compact MainActor
   batch and suppress equal writes.
8. Keep initial size, cell size, and configuration on existing direct host
   paths. Do not retain diagnostic-only values solely for obsolete replay.
9. Model search active/inactive as a discriminated lifecycle. Start/end/cancel
   are exact local barriers; late values cannot reactivate an ended search.
10. Preserve sufficient scrollbar statistics: positive growth before resets,
    first/latest timing, pinned entry/exit edges, observation/attention resets,
    and close/replacement boundaries.
11. Move aggregate activity windows and quiet projection into
    `TerminalActivityProjector` off MainActor. Keep `TerminalActivityRouter` as
    the thin MainActor adapter for exact semantic-fact subscription,
    attended/observation context, pane-close cleanup, and compact atom apply.
12. Cross pending evidence and attention, observation, read/dismiss, reset,
    semantic revocation, close, or replacement through a typed ordered seam:
    detach earlier aggregate, submit aggregate then control, and admit later
    evidence into the next epoch. Never infer historical context from delayed
    current MainActor state.
13. Publish changed derived pinned/observed and output-settled outcomes through
    typed `TerminalActivityEvent` cases on the existing semantic-fact route.
    Inbox consumes those facts, never raw scrollbar samples.
14. Preserve existing `agentSettled*` case/model names, thresholds, and
    pane-classification candidacy gate as compatibility vocabulary for terminal
    output settled on an already-classified pane. Do not rename or treat them as
    agent `working`, `blocked`, or `idle` lifecycle authority.
15. Equal-suppress title, tab title, CWD, progress, secure-input,
    renderer-health, and other state-like semantic facts at
    `TerminalRuntime`'s current-state boundary. Changed values retain exact
    sequence, replay, EventBus, IPC, and Inbox behavior.
16. Hard-cut raw scrollbar, search, and mouse presentation from
    `PaneRuntimeEventChannel`, replay, EventBus, and IPC waits. Exact semantic
    facts remain unchanged.
17. Keep `GhosttyActionDisposition.classify` exhaustive without a `default`
    branch. A newly translated Ghostty action must fail compilation until it is
    assigned an exact, latest-value, activity-evidence, ordered-local-lifecycle,
    or diagnostic disposition.
18. Make Inbox semantic classification exhaustive over the closed
    `PaneRuntimeEvent` families and the nested Terminal/activity cases it owns.
    Explicit typed ignore reasons replace catch-all `default` behavior. Opaque
    plugin payloads remain one intentionally ignored top-level case rather than
    a claim that external plugin vocabularies are closed.
19. At the final static-enforcement gate, add one narrow SwiftSyntax rule that
    rejects mechanically recognizable local-only Terminal cases at semantic
    publication edges. Do not add a generic EventBus, MainActor-cost, or event
    taxonomy rule.

### Red/green proof

Add the smallest failing permanent tests first:

- 100,000 coalescible samples across at least 10 live surface lifetimes.
- Independent last-value and sufficient-statistics oracles.
- Reentrant/concurrent offers, gated drains, one-follow-up behavior, bounded
  retained state, and zero final debt.
- Search start/matches/end and start/selection/cancel barriers.
- Close, replacement, and address-reuse rejection.
- Zero raw-sample runtime-channel, replay, EventBus, delivery, and IPC activity.
- Unchanged count/order for interleaved exact semantic facts.
- Injected-clock activity/output-settled, pinned/observed, read/dismiss, and
  Inbox behavior, including gated aggregate-before-control order and later-epoch
  separation for focus/blur, observation/read, reset, revocation, close, and
  replacement.
- Equal semantic title/CWD/progress/security/renderer values publish nothing;
  changed values retain exact sequence and existing IPC/Inbox behavior.
- No post-stop or post-close mutation.

Focused gate:

    mise run test -- --filter 'GhosttyActionRouterTests|GhosttyCallbackRouterTests|TerminalRuntimeTests|PaneRuntimeEventChannelTests|TerminalActivityRouterTests|TerminalActivityAtomTests|InboxNotificationRouterTests|InboxNotificationRouterObservedPaneTests|DerivedActivityNotificationIntegrationTests|DerivedTerminalActivityNotificationRegressionTests'
    mise run build
    mise run lint

Checkpoint: commit the atomic T3 cut only after raw-sample publication deletion,
activity/Inbox consumer cutover, and focused proof are green.

Stop/replan if T3 requires a generic mailbox, actor-per-pane fleet, durable
generation, strong view retention, EventBus implementation change, atom
workflow, screen polling, lifecycle hooks, or wall-clock test sleeps.

## T4 — Replace Unconditional Fleet Capture With Affected-Key Effects

### Write surface

Likely production files:

- `App/Coordination/WorkspaceSurfaceCoordinator+ActionExecution.swift`.
- `App/Coordination/WorkspaceSurfaceCoordinator+FilesystemSource.swift`.
- `App/Coordination/WorkspaceSurfaceCoordinator.swift` at existing CWD,
  pane-lifecycle, and active-pane edges.
- One narrowly named
  `WorkspaceSurfaceCoordinator+FilesystemEffects.swift` if it improves the
  existing coordinator extension.
- `App/Coordination/FilesystemProjectionIndex.swift` only for existing
  affected-key mutation/currentness needs.
- `App/Coordination/FilesystemGitPipeline.swift` only if an existing capability
  needs exposure.
- `Infrastructure/Diagnostics/AgentStudioTraceIdentityStore.swift` and current
  boot/coordinator owners only for one explicit trace-identity effect.

Do not move filesystem workflow into atoms.

### Implementation contract

1. Delete the unconditional workspace-action tail that schedules full
   repository/worktree/pane capture.
2. Pane create, mount, close, CWD reassignment, and active-pane changes emit the
   narrowest affected-key effect.
3. No-op, layout, sidebar, Inbox, presentation, and unrelated actions schedule
   no filesystem reconciliation.
4. Cold boot, explicit rebuild, and accepted `WorktreeTopologyDelta` batches
   retain one existing full reconciliation.
5. Keep cost proportional to changed panes/worktrees and memberships.
6. Preserve `FilesystemActor` as the only registration/routing/filtering/path
   authority and `FilesystemProjectionIndex` as rebuildable off-main projection,
   not durable truth.
7. Preserve typed currentness and stale/superseded/inapplicable outcomes before
   registration, destructive absence, and downstream apply.
8. Remove duplicate broad trace-identity scheduling where explicit accepted
   effects own it. Coalesce concurrent requests and suppress equal sink updates.
9. Preserve scanner, Git slots, timeouts, physical-drain accounting,
   late-result rejection, and `GIT_OPTIONAL_LOCKS=0` exactly.
10. Make the affected-key projection admission decision exhaustive over
    `WorktreeScopedEvent` and the nested filesystem/Git event cases it owns.
    Replace `default` fallthrough with explicit project-versus-ignore
    dispositions so a new closed event case requires a compile-time decision.

### Red/green proof

Add the smallest failing permanent tests first:

- Unrelated actions cause zero full capture.
- Pane/CWD/active-worktree changes update only affected keys.
- Boot and accepted topology deltas converge to an independent oracle.
- Old source snapshots cannot roll back newer pane updates.
- One accepted effect creates at most one trace-identity fleet capture; equal
  snapshots do not reach the sink.
- Incomplete, timed-out, cancelled, stale, or superseded evidence cannot express
  destructive absence.
- Logical Git timeout cannot free physical capacity or admit late mutation.
- Deepest-root/canonical containment and no-lock shell Git behavior remain
  unchanged.

Focused gate:

    mise run test -- --filter 'WorkspaceSurfaceCoordinatorTests|WorkspaceSurfaceCoordinatorFilesystemSourceTests|WorkspaceSurfaceCoordinatorCWDIdentityTests|FilesystemProjectionIndexTests|FilesystemGitPipelineIntegrationTests|AgentStudioGitWorkingTreeStatusProviderTests|FilesystemActorShellGitIntegrationTests|GitWorkingDirectoryProjectorTests|AgentStudioTraceIdentityStoreTests|FilesystemActorHotPathArchitectureTests'
    mise run verify-git-refresh-performance-workload
    mise run build
    mise run lint

Checkpoint: commit T4 only after focused integration, existing workload, final
zero logical debt, and authority/currentness proof pass.

Stop/replan if T4 requires new topology algebra, persistent indexes, scanner/Git
ownership changes, more Git capacity, timeout widening, repository locks, or a
proof-harness change.

## T5 — Integrated Validation And Runtime Proof

### Final typed-admission and documentation guard

Inspect the final type surface and complete the accepted exhaustive-admission
contract:

1. Preserve the exhaustive Terminal disposition switch.
2. Remove catch-all fallthrough from the filesystem projection and Inbox
   semantic-classification decisions for their closed event families.
3. Add one narrow SwiftSyntax rule forbidding local-only Terminal dispositions
   from semantic publication because the translated `GhosttyEvent` vocabulary
   remains shared with the exact semantic route. Cover the rule with good/bad
   fixtures and the architecture-lint rule inventory.
4. Use `docs-maintain` to update the smallest durable source-of-truth set with
   progressive disclosure: architecture overview, typed source-admission and
   contraction flow, domain-specific Terminal/filesystem/notification details,
   then a concise `AGENTS.md` pointer for future agents. Reconcile existing
   EventBus documentation rather than creating a parallel event-system design.

The compile-time contract applies to closed enums and owned semantic families.
It does not claim exhaustiveness for filesystem paths, user text, external
process output, or opaque plugin-defined payload vocabularies.

Do not add a generic pure-atom rule, expensive-MainActor heuristic,
Repo-Explorer rule, shell/regex checker, type-resolution framework, or
control-flow analyzer.

### Validation ladder

    mise run test-fast
    mise run test-large
    mise run build
    mise run lint
    mise run test

The authoritative `mise run lint` gate must exercise the architecture-lint
rule, fixtures, and stable rule inventory; do not introduce a second lint
runner or shell/regex checker.

### Candidate performance proof

1. Run the deterministic Terminal contraction/activity cell.
2. Run one warm-up and at least three candidate watched-folder/Git trials
   through the existing workload.
3. Run one warm-up and at least three combined Terminal + Git trials with the
   identical T2 workload and measurement contract.
4. Compare median per-trial values against T2 bands; do not pool trials.
5. Require absolute zeros for raw local Terminal sample global traffic, extra
   pending drains, retained-state growth with raw sample count, mixed-workload
   semantic-fact drops, unrelated-action full reconciliation, duplicate
   trace-identity fleet capture, and post-quiescence logical filesystem/Git debt.
6. Require compact MainActor apply p95 below 2 ms and p99 below 5 ms;
   callback-to-current-batch-commit queue age p95 below 8 ms and p99 below
   16 ms; fewer than three targeted service samples at or above 20 ms; and none
   at or above 60 ms per qualifying trial.
7. Require CPU, attributable allocation/retained-byte pressure, and paired
   targeted MainActor duty to improve beyond the frozen noise band. Peak and
   post-quiescence physical footprint/RSS cannot regress beyond the band.
8. Treat sidebar, pane, tab, notification, and startup metrics only as unchanged
   regression evidence. Add no UI statistical cell or automation seam.

### Candidate debug smoke

Use only the isolated candidate debug identity:

    mise run observability:up
    AGENTSTUDIO_IPC_UNSAFE_NO_AUTH=1 \
    AGENTSTUDIO_IPC_DEBUG_TOKEN_ESCROW=1 \
    mise run smoke-debug-launchservices

Then use existing IPC and PID-targeted native automation to verify typing/caret,
search lifecycle, scroll-away/follow-bottom, cursor/link behavior, notification
appearance/clearing, watched-folder discovery, Git convergence, and basic
pane/tab/startup stability as regression observation.

Do not take foreground control of, terminate, or modify production, beta, or
another debug AgentStudio process.

Require the state receipt to report LaunchServices, not
`direct_executable`. Resolve the existing `agentstudio-ipc` executable and the
fresh metadata file, then require accepted `current-pane`,
`terminal-status pane:<current-ordinal>`, and bounded `terminal-send` calls
before native observations. Perform PID-targeted UI work in the background where
supported.

Finally, terminate only the exact candidate debug PID recorded by the fresh
state file, relaunch through the same LaunchServices smoke with a new marker,
and require fresh accepted IPC current-pane and terminal-status readiness.

## T6 — One Review/Remediation Cycle And PR Readiness

1. Run `implementation-review-swarm` on the final diff and proof matrix.
2. Verify every finding against live source.
3. Apply one bounded remediation pass and rerun affected gates.
4. Commit the review-remediation checkpoint.
5. Push the scoped branch and open or update the PR.
6. Use blocking GitHub watches with `--interval 45`; verify checks, comments,
   review threads, mergeability, and final pushed HEAD.
7. Commit any final PR-readiness-only scoped correction after proof.
8. Stop with the PR ready and unmerged.

## Shared-File Integration Ownership

| Shared surface | Owner | Rule |
| --- | --- | --- |
| Ghostty action routing and Terminal local accumulator | T3 | one atomic sample-classification and lifetime owner |
| `PaneRuntimeEvent.swift` and channel call sites | T3 | delete local-sample publication; preserve exact facts and EventBus implementation; add only TR-10 derived activity outcome cases |
| Terminal activity and Inbox derived input | T3 | thin MainActor router + off-main projector; one ordered aggregate/control cutover; atoms remain current state |
| `WorkspaceSurfaceCoordinator` filesystem edges | T4 | one affected-key effect owner; no compatibility tail |
| `FilesystemProjectionIndex` and trace identity | T4 | preserve currentness and one explicit refresh route |
| Closed source-admission and semantic-classification switches | T3/T4/T5 | exhaustive domain-owned decisions; no generic classifier or catch-all fallthrough |
| Architecture-lint Terminal publication guard | T5 | one SwiftSyntax rule with good/bad fixtures and stable inventory entry |
| `AGENTS.md` and current architecture docs | T5 | progressive-disclosure guidance linked to live code; no duplicated event-system architecture |
| Diagnostics event/OTLP vocabulary | T2a | candidate-only aggregate cases freeze before T3/T4; no per-sample emitters |
| Proof scripts/runners/harnesses | frozen T1 | no edits in T2a-T6 |

## Checkpoint Commits

1. Corrected spec and plan.
2. T2a candidate-only aggregate metric vocabulary.
3. T3 Terminal contraction.
4. T4 filesystem affected-key effects.
5. T5 typed-admission guard, durable docs, and integrated runtime proof.
6. One review-remediation checkpoint.
7. PR-ready state.

Every product checkpoint requires scoped proof first. Never stage `.agents/`.
Rollback is a commit-level revert of a failing hard cut; retain no dual route,
feature flag, or compatibility publication.

## Stop And Replan Triggers

- Live code contradicts the accepted owner/actor boundary.
- A task needs an excluded architecture or product surface.
- Required proof needs a new or expanded script, runner, harness, backend, or
  app control seam.
- A required gate cannot pass within its owning task.
- Comparable instrumentation semantics change after T2.
- An unrelated build/test/tooling failure would require out-of-scope edits.

Otherwise, T2-T6 checkpoints are not stop conditions. Continue to the PR-ready,
non-merge terminal.
