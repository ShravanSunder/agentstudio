# Git Enrichment Refresh Plan Amendment

Status: Spec B implemented; implementation-review fixes applied
Date: 2026-06-11
Base plan: `docs/plans/2026-06-11-agent-studio-idle-git-render-performance.md`
Spec: `docs/superpowers/specs/2026-06-11-git-enrichment-refresh-redesign.md`

## Goal

Bring the existing Spec B implementation plan into alignment with the final
Spec B design before implementation.

The base plan is still useful, but this delta is required because the final
spec moved from the earlier 3-tier/scheduler-extraction model to:

- 2 buckets plus focus boost.
- Tier-priority admission with a concurrency budget.
- Background striping.
- Mandatory input filter, optional-locks env, retry/backoff, and Swift 6.2
  pins.
- MainActor discipline fixes that make render-triggered work rare and cheap.
- Three workload proof gates, not idle-only proof.

Post-main merge note: PR #164 (`52c5e677`) added the local
OTLP/VictoriaLogs observability stack integration and beta launch helpers. That
stack changes the proof strategy for B8: use marker-scoped AgentStudio trace
records and the beta observability harness where possible instead of broad
system-log predicates. It does not add git-refresh, command-bar, tab-bar, or
topology hot-path trace call sites by itself, so this plan still owns those
performance-specific records.

## Non-Goals

- Do not implement product code in this amendment.
- Do not edit the user's live AgentStudio instance.
- Do not replace the full base plan here; this file is a delta until the base
  plan is amended or superseded.
- Do not pull Spec A AtomLib row-1 implementation into Spec B execution except
  for the interim cache gate explicitly marked below.
- Do not mutate user repos, user worktrees, or user git config during proof
  runs; busy-agent and commit-interference checks use disposable fixture
  repos/worktrees only.
- Do not delegate lint/mise/hook/script/workload-driver changes without a
  synchronous parent review before subsequent Swift edits.

## Source Coverage

- Spec B: 298 lines, read fully.
- Base plan: 709 lines, read and checkbox-scanned; 45 unchecked, 0 checked.
- Handoff packet: 204 lines, read fully.
- Debug investigation: 145 lines, read fully.

## Supersession Contract

This amendment is the source of truth anywhere it conflicts with the base plan.
Before implementation, the executor must either fold these changes into the
base plan or treat the base plan sections below as explicitly superseded:

- 3-tier foreground/active/background cadence.
- direct projector `register`/`unregister` lifecycle authority.
- direct lifecycle tests that prove the rejected authority.
- conditional Phase 3 wording for normalized topology path index, pane context
  reuse, command-bar presence batching, `paneCount` direct read, and
  SurfaceManager unchanged-write guards.
- evidence-only validation task text that forbids instrumentation/source
  changes needed for B8 proof.

One worker owns `GitWorkingDirectoryProjector.swift` at a time. Do not
parallelize policy, admission, lifecycle repair, dedup, retry, or input-filter
edits against that actor.

## Required Plan Amendments

### B0 — Completed Spec Review/Normalization Gate

- Completed before this plan-review:
  - `shravan-dev-workflow:spec-review-swarm` ran for the two-spec program.
  - Source locations were re-checked for the review packet.
  - Stale language was identified and must be normalized by this amendment:
    - Replace 3-tier foreground/active/background cadence with
      active/background buckets plus focus boost.
    - Demote scheduler extraction to conditional refactor only.
    - Reframe Phase 2 as residual render-cost reduction.

Proof: review report records accepted/contested/open findings and says whether
the base plan is amended in place or this delta is executed as the source of
truth.

### B1 — Policy Model Alignment

Write surfaces:

- `Sources/AgentStudio/Infrastructure/AppPolicies.swift`
- `Sources/AgentStudio/Core/RuntimeEventSystem/Git/GitWorkingDirectoryProjector.swift`
- `Tests/AgentStudioTests/Core/PaneRuntime/Sources/GitWorkingDirectoryProjectorTests.swift`

Tasks:

- [x] Define one `AppPolicies.GitRefresh` value type or equivalent policy
  surface.
- [x] Use active/background bucket constants:
  - active self-heal cadence: 15s
  - background cadence: 240s striped across 16 ticks
  - max concurrent status computes: about 4
  - one oldest-stale/fairness slot
  - stable-hash background stripe count/offset
  - retry/backoff constants
- [x] Add focus boost as an immediate enqueue on active pane worktree change.
- [x] Preserve explicit test fixtures; no production/test default drift.

Proof:

- Unit tests for active cadence, background stripe cadence, focus boost, and
  oldest-stale fairness with injected clock.

### B2 — Provider Optional Locks

Write surfaces:

- `Sources/AgentStudio/Core/RuntimeEventSystem/Git/GitWorkingTreeStatusProvider.swift`
- `Tests/AgentStudioTests/Helpers/MockProcessExecutor.swift`
- provider-focused tests.

Tasks:

- [x] Add `GIT_OPTIONAL_LOCKS=0` to git status/diff/config environment through
  the existing executor env merge.
- [x] Preserve inherited `PATH`/`HOME` behavior.
- [x] Do not mutate user repo config.

Proof:

- Unit tests assert every git subprocess call carries the env override.
- Concurrent commit sanity check in debug/Beta smoke if practical.

### B3 — Projector Admission, Dedup, Input Filter, Retry

Write surfaces:

- `GitWorkingDirectoryProjector.swift`
- projector tests.

Tasks:

- [x] Replace all-worktree fanout with budgeted admission.
- [x] Keep registration lifecycle single-path and topology-owned. Do not
  introduce a second direct `register`/`unregister` authority in the
  projector; repair dropped or stale lifecycle facts by re-asserting topology
  truth with an epoch/generation guard.
- [x] Accept activity and focus facts before registration; apply them when
  registration arrives.
- [x] Skip suppressed-only ignored changesets.
- [x] Preserve `.git/config` and git-internal refresh semantics.
- [x] Skip `.snapshotChanged` when the snapshot equals the last emitted
  snapshot for that worktree.
- [x] Requeue nil status once with bounded backoff.
- [x] Preserve origin checks for periodic/empty-path changesets.
- [x] Keep git compute behind the `@concurrent` provider seam.

Proof:

- Budget ceiling under 100+ worktrees.
- Background stripe only admits bounded work per tick.
- Active/focus work is not starved behind background load.
- Activity-before-registration passes.
- Ignored-only changeset triggers no provider call; git-internal changeset
  still does.
- Nil status eventually refreshes after backoff.
- Identical snapshot emits no event; snapshot-only delta emits.

### B4 — Pipeline Activity/Focus Forwarding And Topology Repair

Write surfaces:

- `Sources/AgentStudio/App/Coordination/FilesystemGitPipeline.swift`
- `Sources/AgentStudio/App/Coordination/PaneCoordinator+FilesystemSource.swift`
- topology/pipeline reconciliation tests.
- pipeline integration tests.

Tasks:

- [x] Keep `register`/`unregister` lifecycle facts flowing through one
  topology-owned path; direct pipeline calls are not a second lifecycle
  authority.
- [x] Forward `setActivity` and `setActivePaneWorktree` to both filesystem
  actor and projector.
- [x] Add a topology re-assert/repair path that can heal a dropped bus
  envelope without resurrecting removed worktrees. Use an epoch/generation or
  equivalent topology stamp so stale lifecycle facts lose to current topology
  truth.
- [x] If the current topology surfaces do not already expose a usable revision,
  add a monotonic `topologyGeneration`/`topologyRevision` on the topology owner
  and pass that stamp through the repair assertion. Do not invent a hash-based
  freshness heuristic. Implemented as the coordinator-owned filesystem
  topology assertion generation passed through the repair path.
- [x] Ensure existing bus topology handling remains idempotent under duplicate
  topology assertions.

Proof:

- Integration test where bus registration is delayed/dropped but topology
  repair recovers.
- Integration test where a stale delayed registration after topology removal
  does not resurrect a worktree.
- Focus switch causes immediate enqueue without waiting for next cadence.

### B5 — MainActor Discipline Fixes

Write surfaces:

- `Sources/AgentStudio/App/Coordination/PaneCoordinator+FilesystemSource.swift`
- `Sources/AgentStudio/Core/State/MainActor/Atoms/WorkspacePaneAtom.swift`
- `Sources/AgentStudio/Features/Terminal/**/SurfaceManager*.swift` or actual
  SurfaceManager file discovered before implementation.
- Existing tests around pane coordinator, filesystem source, and surface
  manager.

Tasks:

- [x] Guard non-filesystem/git envelope families before computing rich pane
  derivation and worktree context maps.
- [x] Add or reuse the normalized topology path index so
  `repoAndWorktree(containing:)` does not repeatedly call
  `URL.standardizedFileURL` on every render.
- [x] Reuse `PaneManagementContext.project`/pane worktree context rather than
  computing it twice for target paths, identity rows, and status chips.
- [x] Batch command-bar worktree presence construction so `>`/`#` scopes do
  not scan pane locations per row at 118/163 scale.
- [x] Memoize topology-derived worktree contexts by topology revision where
  implementation evidence shows repeated recomputation. Evidence resolved this
  as no additional cache: non-projectable envelopes are guarded before context
  construction, and the filesystem sync pass computes contexts once.
- [x] Replace `paneCount(for:)` full-derived read with a direct pane graph read.
- [x] Guard SurfaceManager health/status writes so unchanged ticks do not fire
  observation.

Proof:

- `.gitWorkingDirectory` envelope path performs zero topology path reads before
  it is known to be relevant.
- `paneCount(for:)` test proves no rich pane construction.
- Unchanged SurfaceManager tick fires no observation; changed tick still fires.

### B6 — Swift 6.2 Hygiene Pins

Write surfaces:

- `FilesystemPathFilter` loading path.
- Git provider/projection boundaries if refactor touches isolation.

Tasks:

- [x] Preserve `@concurrent` git provider compute behavior.
- [x] Move synchronous `FilesystemPathFilter.load` I/O off the
  `FilesystemActor` executor before relying harder on input filtering.

Proof:

- Focused tests or compile proof for isolation annotations.
- No actor-serialized status waits introduced.
- Evidence: `swift test --filter
  FilesystemActorHotPathArchitectureTests/pathFilterLoadingRunsThroughConcurrentAsyncBoundary
  && swift test --filter FilesystemPathFilterTests && swift test --filter
  FilesystemActorTests && swift test --filter
  FilesystemActorShellGitIntegrationTests` passed with 1 + 5 + 17 + 2 tests.

### B7 — Existing Base Plan Tasks That Remain Valid

Keep and reconcile:

- normalized topology path index
- `PaneManagementContext.project` reuse
- command-bar presence batching
- validation/proof task

But reconcile with Spec A:

- Spec B cache content gate is interim.
- Spec A row-1 deletes-and-absorbs that gate.
- Spec B per-worktree observation granularity and derived memoization are
  superseded by Spec A rows 1-2.
- The MainActor discipline tasks listed in B5 are not conditional residual
  cleanup. They are required before B8 closeout unless all three B8 workload
  gates already pass with captured artifacts from the current branch.

### B8 — Instrumentation And Workload Proof

Write surfaces:

- lightweight `AgentStudioTraceRuntime` records and/or `os_signpost`/Logger
  instrumentation in touched runtime paths, if not already present.
- `Sources/AgentStudio/Infrastructure/Diagnostics/AgentStudioTraceTag.swift`,
  if new performance trace tags are needed.
- repeatable workload driver script if no existing harness covers it.
- `tmp/debug-workflows/...` proof artifact.

Tasks:

- [x] Add safe performance trace records/signposts for tick size, compute
  duration/completions, posts/dedup skips, coordinator writes,
  `repoAndWorktree` calls/µs, `TabBarAdapter.refresh` rebuilds, and command-bar
  item construction/filter/rebuild duration.
- [x] Use safe numeric attribute keys accepted by the OTLP projection
  (`*.count`, `*.duration_ms`, `*.elapsed_ms`); do not export raw paths, UUIDs,
  prompts, payload text, error strings, command output, or repo names.
- [x] Prefer `mise run create-beta-app-bundle`, `mise run
  run-beta-observability`, and `mise run verify-beta-observability` for
  end-to-end trace transport proof when the shared stack is available.
- [x] Preserve JSONL proof even when OTLP/VictoriaLogs is available. The
  Victoria projection intentionally scrubs `process.pid`, so PID-scoped proof
  comes from the launched PID plus the JSONL filename
  `agentstudio-$AGENTSTUDIO_TRACE_NAME-$PID.jsonl`; Victoria proof comes from
  the `agentstudio.trace.name` marker.
- [x] Launch workload proof with isolated app data, for example
  `AGENTSTUDIO_DATA_DIR="$ARTIFACT/app-data"`, so the proof fixture never
  reads or mutates the user's live AgentStudio state.
- [x] Run proof on debug/Beta only.
- [x] Do not touch the user's live AgentStudio process.
- [x] Create disposable proof fixtures under
  `tmp/debug-workflows/2026-06-11-agent-studio-performance-issues-cmdp-slowdown/fixtures/`
  or a newer timestamped proof directory. The fixture setup must `git init`
  throwaway repos/worktrees and must not point at project worktrees.
- [x] Configure fixture git identity locally only (`user.email`, `user.name`,
  `commit.gpgsign=false`, `tag.gpgsign=false`) or pass equivalent `git -c`
  values per command. Do not read or mutate global git config.
- [x] Busy-agent driver starts at least five independent fixture writers that
  repeatedly modify and commit fixture files while the debug/Beta app watches
  those fixture worktrees.
- [x] Workload driver owns PID files for the beta/debug process and every
  writer, traps `EXIT`/`INT`/`TERM`, stops and waits only those PIDs, and
  proves cleanup leaves no writer PIDs.
- [x] Capture commands and outputs into a proof directory:
  - app launch command and debug/Beta PID
  - observability state file and `AGENTSTUDIO_TRACE_NAME` marker
  - JSONL trace file path when JSONL is enabled
  - VictoriaLogs query/verification output when OTLP is enabled
  - fixture setup command
  - writer-driver command
  - `/usr/bin/sample "$PID" 5 1 -file "$ARTIFACT/main-sample.txt"`
  - any fallback `log show`/signpost command must be PID-scoped or
    marker-scoped; broad `subsystem == "com.agentstudio"` capture is not
    accepted proof
- [x] cmd-P proof uses the real command-bar filtering seam discovered in code
  with a 118-repo / 163-worktree fixture. Pure `CommandBarSearch.filter`
  timing is supporting evidence only; the required gate times command-bar item
  construction, presence map/build, filter, and rebuild for `>`/`#` scopes. If
  run as an app smoke, record trace/signpost events for keystroke-to-filter
  rebuild and sample the debug/Beta PID.

Required gates:

- Idle: main thread <10% busy; `repoAndWorktree` samples approximately zero;
  git computations <=2/s after warmup. The active cadence is 15s because the
  earlier 2s active tick kept 14 open panes at roughly 7-9 git computations/s
  even after background striping. Background cadence is 240s because the first
  180s stripe pass left only marginal headroom against the <=2/s idle gate.
- Busy-agent: at least 5 synthetic writers; main thread <=30%; per-change
  render <1 frame after render tasks.
- cmd-P: keystroke/filter rebuild <= about 8ms at 118/163 scale.

Implementation proof captured:

- Idle final policy proof:
  `/tmp/asperf/idle-postcadence240-023014`, trace
  `idle-postcadence240-023014`, PID `68258`, JSONL
  `/tmp/asperf/idle-postcadence240-023014/traces/agentstudio-idle-postcadence240-023014-68258.jsonl`.
  Post-warmup git status rates were 1.759/s after 90s, 1.719/s after 120s,
  and 1.895/s after 150s; max Git running was 4; sampled app CPU was 0.0%.
- Busy/cmd-P final policy proof:
  `/tmp/asperf/perf-postcadence240-023536`, trace
  `perf-postcadence240-023536`, PID `76444`, JSONL
  `/tmp/asperf/perf-postcadence240-023536/traces/agentstudio-perf-postcadence240-023536-76444.jsonl`.
  The run used 118 repos, 163 worktrees, 14 active panes, 5 fixture writers,
  and startup command-bar filtering. `performance.commandbar.filter` p95 was
  1.668ms, `performance.commandbar.items` p95 was 4.453ms, `performance.git.status`
  p95 was 126.047ms, and max Git running was 4.
- Implementation review accepted two in-scope fixes after external Claude/Gemini
  counsel: derive `backgroundCadence` from `activeCadence * backgroundStripeCount`
  so policy cannot drift, and make the workload script capture a proof-app PID
  before trace discovery so cleanup cannot orphan the launched proof process.

### B9 — Execution Packet Split

Execute Spec B in sequential packets. Later packets can be delegated only after
the parent has reviewed the previous packet's diff and validation output:

- B9.1 policy constants and injected-clock tests.
- B9.2 projector admission/budget/stripe/fairness.
- B9.3 provider optional-locks env, input filter, dedup, retry/backoff.
- B9.4 topology repair and focus/activity forwarding.
- B9.5 mandatory MainActor discipline fixes.
- B9.6 instrumentation/driver design review with exact argv, fixture root,
  app-data path, marker/PID evidence, and cleanup assertions.
- B9.7 workload proof execution.

## Requirements And Proof Matrix

| Requirement | Tasks | Proof | Layer | Red/Green |
|---|---|---|---|---|
| Final model is active/background + focus boost | B0-B1 | plan-review + cadence/focus tests | review/unit | yes |
| Git subprocess storm is bounded | B1-B3 | budget/stripe/fairness tests + idle sample | unit/smoke | yes |
| Ignored-only churn does not run git | B3 | provider call-count tests | unit/integration | yes |
| Optional locks prevent index lock interference | B2 | env propagation tests | unit | yes |
| Projector does not emit redundant snapshots | B3 | identical vs changed snapshot tests | unit | yes |
| MainActor work is guarded before expensive derivation | B5 | envelope/paneCount/SurfaceManager tests | unit/integration | yes |
| Swift 6.2 isolation behavior is preserved | B6 | compile/focused tests | unit/build | yes |
| Workload proof covers idle, busy, cmd-P | B8 | debug artifacts with commands/counts | smoke/e2e | no waiver |
| Spec A cutover remains clean | B7 | plan-review verifies no permanent dual gate | review | no |

## Review And Execution Route

1. `shravan-dev-workflow:spec-review-swarm` for B0.
2. `shravan-dev-workflow:plan-review-swarm` on this delta plus base plan.
3. `shravan-dev-workflow:implementation-execute-plan` after accepted review.
4. `shravan-dev-workflow:implementation-review-swarm` after implementation.

External Claude/Gemini review lanes are included when the user explicitly asks
for them and the harness is available; otherwise write copy-paste prompts and
record that the lane was not actually run.
