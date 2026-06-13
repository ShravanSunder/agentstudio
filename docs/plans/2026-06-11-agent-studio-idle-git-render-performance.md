# Agent Studio Git Refresh and Render Recovery Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: use `superpowers:subagent-driven-development` or `superpowers:executing-plans` to execute this task-by-task. Do not implement product code until this plan has been accepted for act mode. Steps use checkbox (`- [ ]`) syntax for tracking.

**Status:** historical base plan, not executable standalone.

**Execution source:** use
`docs/plans/2026-06-11-git-enrichment-refresh-plan-amendment.md` plus the
plan-review report. That amendment supersedes this file anywhere this file
mentions 3-tier foreground/active/background cadence, direct projector
`register`/`unregister` lifecycle authority, conditional Phase 3 MainActor
cleanup, or evidence-only validation that forbids instrumentation/source edits
needed for workload proof.

Do not hand this file to an implementation agent by itself.

**Goal:** Restore normal AgentStudio idle CPU, Cmd-P/new-tab responsiveness, management-layer responsiveness, and terminal typing latency by bounding git refresh work, stopping redundant cache invalidation, and only then touching MainActor render hot paths if profiling still proves they are hot.

**Architecture:** Keep one git refresh system, but change its trust model. A tiered, striped, budget-bounded sweep is the source of truth; filesystem events accelerate refreshes but are not the correctness boundary. Phase 1 wins by bounding off-MainActor git work, preventing process herds, filtering suppressed-only churn, and reducing MainActor invalidation frequency. Phase 2 extracts a dedicated scheduler actor only if policy inputs grow beyond the projector-internal version. Phase 3 MainActor/read-path cleanup is conditional on post-Phase-1 samples.

**Tech Stack:** Swift 6, Swift Testing, SwiftUI/AppKit, `@Observable` atoms, actor-based runtime event system, local `git` subprocess provider, `mise` build/test orchestration.

---

## Source Coverage

Validated source artifacts read in full:

- `tmp/debug-workflows/2026-06-11-agent-studio-performance-issues-cmdp-slowdown/debug-investigation.md` - 145 lines.
- `tmp/debug-workflows/2026-06-11-agent-studio-performance-issues-command-bar-slow/debug-investigation.md` - 40 lines.
- `docs/superpowers/specs/2026-06-11-git-enrichment-refresh-redesign.md` - 189 lines.
- Previous version of this plan - 422 lines.

Key code evidence inspected:

- `Sources/AgentStudio/App/Coordination/FilesystemGitPipeline.swift` - default 2s git tick and activity forwarding.
- `Sources/AgentStudio/Core/RuntimeEventSystem/Git/GitWorkingDirectoryProjector.swift` - all-worktree periodic sweep, per-worktree task fan-out, unconditional snapshot emission, bus subscription buffer.
- `Sources/AgentStudio/Core/RuntimeEventSystem/Git/GitWorkingTreeStatusProvider.swift` - `git status`, `git diff --shortstat`, and `git config` subprocesses with `environment: nil`.
- `Sources/AgentStudio/Infrastructure/ProcessExecutor.swift` - environment merging and one Dispatch queue per process execution.
- `Sources/AgentStudio/Core/RuntimeEventSystem/Filesystem/FilesystemActor.swift` - foreground/open/background priority facts, suppressed path counters, empty-path flush behavior.
- `Sources/AgentStudio/Core/RuntimeEventSystem/Filesystem/DarwinFSEventStreamClient.swift` - per-worktree streams, silent registration failure, event flags discarded.
- `Sources/AgentStudio/Core/RuntimeEventSystem/Filesystem/FilesystemRootOwnership.swift` - deepest-root ownership routing.
- `Sources/AgentStudio/App/Coordination/PaneCoordinator+FilesystemSource.swift` - topology-derived worktree registration and active-pane facts.
- `Sources/AgentStudio/App/Coordination/WorkspaceCacheCoordinator.swift` - unconditional enrichment writes from git snapshots.
- `Sources/AgentStudio/Core/Models/WorktreeEnrichment.swift` - `updatedAt` included in equality/hash, `snapshot` excluded.
- `Sources/AgentStudio/Core/State/MainActor/Atoms/RepoCacheAtom.swift` - whole-dictionary cache assignment.
- `Sources/AgentStudio/Core/State/MainActor/Atoms/WorkspaceRepositoryTopologyAtom.swift` - O(repos x worktrees) URL normalization in `repoAndWorktree(containing:)`.
- `Sources/AgentStudio/Core/Views/Panes/PaneManagementContext.swift` and `Sources/AgentStudio/Core/Views/Panes/PaneLeafContainer.swift` - repeated MainActor projection in render.
- `Sources/AgentStudio/Features/CommandBar/CommandBarDataSource+WorktreeRows.swift` and `CommandBarDataSource.swift` - eager repo/worktree row construction.

Review lanes incorporated:

- `spec-compliance`: current plan did not implement sweep-primary scheduler, omitted input filter/optional-locks, and promoted render cleanup too early.
- `architecture-assumptions`: cadence changes without admission control leave herds; scheduler actor should own policy/intents only when extracted.
- `testability-validation`: required budget/striping/tier tests, activity-before-registration tests, env tests, and numeric live gates.
- `security-reliability/adversarial`: failed computes consumed-and-dropped, projector-local registration truth fragile under bus drops, stale-badge SLA needed.

## Current Timing Model

Current behavior at 118 repos / 163 worktrees:

```text
every 2s
  FilesystemGitPipeline.gitPeriodicRefreshInterval
    -> GitWorkingDirectoryProjector.enqueuePeriodicRefreshes()
       -> enqueue every registered worktree
       -> spawn one actor task per worktree with pending work
       -> ShellGitWorkingTreeStatusProvider.status()
          -> git status
          -> git diff --shortstat
          -> git config --get remote.origin.url
       -> post .snapshotChanged unconditionally
       -> WorkspaceCacheCoordinator.handleEnrichment on MainActor
       -> RepoEnrichmentCacheAtom replaces whole worktree dictionary
       -> SwiftUI invalidates panes/sidebar/command-bar readers
       -> PaneLeafContainer.body recomputes management/inbox context
       -> repoAndWorktree(containing:) scans topology with URL.standardizedFileURL
       -> main thread queues behind render work
```

The important distinction:

- Git status computation is already outside the MainActor, but it is unbounded and creates process herds.
- Cache mutation and UI rendering are on the MainActor, and they are retriggered by every redundant snapshot.
- Moving more logic into actors only helps if those actors own backpressure, tiers, and admission. Actorization without a budget just moves the overload.

Phase 1 improves time slicing by bounding the off-MainActor git pipeline and sharply reducing MainActor invalidation frequency. It does not attempt to move SwiftUI rendering off the MainActor. Phase 3 only optimizes MainActor read paths if Phase 1 samples still prove those paths dominate.

## Diagnosis

Proven:

- `FilesystemGitPipeline` defaults `gitPeriodicRefreshInterval` to `.seconds(2)`.
- `GitWorkingDirectoryProjector.enqueuePeriodicRefreshes()` iterates every registered worktree.
- `PaneCoordinator+FilesystemSource.workspaceWorktreeContextsById()` registers every available repo/worktree.
- `GitWorkingDirectoryProjector.spawnOrCoalesce` prevents duplicate tasks per worktree but has no global concurrency cap.
- `ShellGitWorkingTreeStatusProvider.status()` can run three local git subprocesses per status compute.
- `GitWorkingDirectoryProjector.computeAndEmit()` emits `.snapshotChanged` after every successful status compute.
- `WorkspaceCacheCoordinator.handleEnrichment()` writes a fresh `WorktreeEnrichment` for every `.snapshotChanged`.
- `WorktreeEnrichment.==` includes `updatedAt` and excludes `snapshot`; both directions are dangerous for cache gating.
- `RepoEnrichmentCacheAtom.setWorktreeEnrichment` replaces the whole observed dictionary.
- `FilesystemActor.PendingWorktreeChanges.hasPendingChanges` is true for ignored-only suppressed path counts, and `flush` can emit empty `paths` changesets.
- `DarwinFSEventStreamClient` discards FSEvent flags, and EventBus subscriptions use bounded newest buffers.
- `WorkspaceRepositoryTopologyAtom.repoAndWorktree(containing:)` remains a real MainActor hot path in the baseline sample.

Inferred and to prove during execution:

- Whole-dictionary assignment broadly invalidates UI readers.
- Cmd-P will improve after the idle storm is fixed but may still have eager row-build costs.
- A sweep cannot be removed or made event-primary until linked-worktree admin-dir attribution and FSEvent overflow handling are designed and tested.

## Design Decisions

1. **Sweep-primary truth, events as acceleration.**
   Filesystem events are useful wakeups, but they are lossy and can be misattributed for linked worktrees. A slow, bounded sweep remains the self-healing correctness path.

2. **Budget before cadence.**
   A 60s inactive interval without admission control only moves the herd. The projector must cap in-flight git status computations and stripe background work before slowing background cadence.

3. **Three tiers, one policy surface.**
   Foreground means the active pane worktree. Active means at least one open pane. Background means registered worktrees with no open panes. Defaults live under `AppPolicies.GitRefresh` so tests and production do not drift.

4. **Direct lifecycle facts beat bus-only registration.**
   The projector can still listen to bus topology events, but Phase 1 must update projector registration/activity from the topology-derived `FilesystemGitPipeline.register`, `unregister`, `setActivity`, and `setActivePaneWorktree` calls. This is the minimal topology-truth bridge and avoids relying on dropped `worktreeRegistered` delivery.

5. **Do not use `WorktreeEnrichment.==` as the cache gate.**
   Phase 1 uses explicit cache-content equivalence that includes snapshot content and excludes `updatedAt`. Leave `Equatable`/`Hashable` unchanged unless a separate audit proves the global conformance can change safely.

6. **No raw FSEvents filtering in this slice.**
   Callback-level filtering remains out of scope. Post-classification filtering is in scope: ignored-only suppressed changesets must not trigger git compute, while projected paths and git-internal changes still do.

7. **MainActor render optimization is conditional.**
   The baseline sample proves `standardizedFileURL` is hot, but the new architecture requires re-profiling after the git storm is stopped. Topology indexing, pane projection cleanup, and command-bar batching are Phase 3 only if still hot.

## Background Staleness SLA

Default accepted SLA for this plan:

- Foreground worktree stale time target: <= 2s from periodic sweep; filesystem events can refresh sooner after tier debounce.
- Active/open worktree stale time target: <= 10s from periodic sweep; filesystem events can refresh sooner after tier debounce.
- Background worktree stale time target under lost events: <= 120s plus bounded queue drain. With 163 background worktrees and a 3-per-2s stripe, a full background pass is about 109s.

If 120s background staleness is unacceptable, do not implement this plan as written; reduce `backgroundRefreshInterval` and accept more baseline git work.

## Phase 2 Scheduler Actor Contract

Phase 1 may keep scheduling inside `GitWorkingDirectoryProjector` to avoid new module surface. Extract `GitRefreshScheduler` in Phase 2 when any of these is true:

- Sidebar-visible or Cmd-P-visible worktrees become refresh inputs.
- App activation/wake ingress becomes part of refresh policy.
- The projector file approaches the repo's large-file threshold after Phase 1 changes.
- The future `agentstudio-git`/libgit2 track replaces shell subprocess status.

If extracted, `GitRefreshScheduler` owns:

- tier membership inputs: foreground worktree id, open worktree set, future visibility facts
- cadences, tier debounce, jitter/striping, budget, fairness, backoff
- per-worktree freshness and next-eligible timestamps
- refresh-intent ordering and admission
- topology-truth reconciliation input snapshots

It does not own:

- git subprocess execution
- status parsing
- snapshot/origin/branch dedup
- EventBus emission
- MainActor atoms

The scheduler emits refresh intents; the projector remains the compute and fact-emission owner.

## Non-Goals

- No zmx, Ghostty runtime, SQLite schema, release packaging, or notarization changes.
- No event-primary cutover and no sweep removal.
- No FSEvent flag seam redesign in Phase 1. Overflow flags remain a known follow-up because `FSEventBatch` currently carries only `worktreeId` and `paths`.
- No admin-dir remapping for linked worktree events in Phase 1. Sweep-primary truth bounds the stale-badge risk.
- No app-wide derived memoization framework in Phase 1.
- No UI redesign of command bar or management layer.
- No destructive operations against the user-running AgentStudio instance.
- No changes to user repo git config such as `core.untrackedCache` or `core.fsmonitor`.

## Requirements / Proof Matrix

| Requirement / Claim | Task | Proof Gate | Layer | Red/Green Required |
| --- | --- | --- | --- | --- |
| Git read commands use `GIT_OPTIONAL_LOCKS=0` without losing inherited PATH/HOME | 1 | Provider unit tests with `MockProcessExecutor` | Unit | Yes |
| Duplicate identical git snapshots do not post repeated `.snapshotChanged` events | 2 | Projector unit tests | Unit | Yes |
| Equal worktree enrichment content does not rewrite cache or bump `updatedAt` | 2 | Atom/coordinator unit tests | Unit | Yes |
| Snapshot-only summary changes still update cache | 2 | Atom/coordinator unit tests | Unit | Yes |
| Foreground/open/background tiers use separate cadences | 3 | Projector/pipeline clock tests | Unit + integration | Yes |
| Background refresh is striped and does not enqueue whole fleet on one tick | 3 | Projector clock tests with 100+ worktrees | Unit | Yes |
| In-flight git status computations are globally capped | 3 | Gate-based provider concurrency test | Unit | Yes |
| Active work cannot starve behind background backlog | 3 | Priority/fairness unit test | Unit | Yes |
| Oldest stale background work eventually runs | 3 | Oldest-stale fairness unit test | Unit | Yes |
| Activity before registration is retained and applied | 3 | Projector unit tests | Unit | Yes |
| Projector registration is not lost if bus delivery is dropped | 3 | Pipeline/projector direct lifecycle test | Unit + integration | Yes |
| Ignored-only suppressed changesets do not trigger git compute | 3 | Projector and pipeline tests | Unit + integration | Yes |
| Git-internal-only and `.git/config` changes still trigger compute | 3 | Existing plus added tests | Unit + integration | Yes |
| Failed git computes requeue with bounded backoff | 3 | Clock-driven nil-then-success provider test | Unit | Yes |
| Origin/branch freshness semantics survive dedupe/throttle | 2, 3 | Existing and added origin/branch tests | Unit | Yes |
| Real app idle/render behavior improves without touching user host app | 4 | debug/beta sample and ps watch | Smoke | Baseline + after samples |
| MainActor render cleanup is only started if after-sample still shows it hot | 4, 5 | Inter-phase profiling gate | Smoke | Yes |
| App still passes repo-local quality gates | 4 | `mise run lint`, `mise run test` | Lint + full test | No red needed |

All new async timing tests must use `TestPushClock`, gates, or bounded yield polling. Do not add wall-clock sleeps.

## Phase 1 Task 1: Make Git Status Reads Non-Interfering

**Files:**

- Modify: `Sources/AgentStudio/Core/RuntimeEventSystem/Git/GitWorkingTreeStatusProvider.swift`
- Test: add/extend provider tests, or add focused tests beside `Tests/AgentStudioTests/Core/PaneRuntime/Sources/FilesystemActorShellGitIntegrationTests.swift` if no provider test file exists.
- Reuse: `Tests/AgentStudioTests/Helpers/MockProcessExecutor.swift`

- [ ] **Step 1: Add failing env propagation test**

Create a provider unit test using `MockProcessExecutor` that enqueues success responses for `status`, `diff`, and `config`, then asserts each recorded call includes:

```swift
environment?["GIT_OPTIONAL_LOCKS"] == "0"
```

Expected failure before implementation: each call has `environment == nil`.

- [ ] **Step 2: Add provider environment constant**

In `ShellGitWorkingTreeStatusProvider`, add a private environment constant such as:

```swift
private static let gitReadOnlyEnvironment = ["GIT_OPTIONAL_LOCKS": "0"]
```

Pass it to all provider-owned git invocations: `status`, `diff --shortstat`, and `config --get remote.origin.url`.

Do not change `DefaultProcessExecutor.normalizedEnvironment`; it already merges overrides with inherited PATH/HOME.

- [ ] **Step 3: Run focused provider tests**

```bash
swift test --filter GitWorkingTreeStatusProvider
```

If no provider-specific test target exists yet, run the exact new test filter after creating it.

## Phase 1 Task 2: Stop Duplicate Snapshot and Cache Mutation Fan-Out

**Files:**

- Modify: `Sources/AgentStudio/Core/RuntimeEventSystem/Git/GitWorkingDirectoryProjector.swift`
- Modify: `Sources/AgentStudio/Core/Models/WorktreeEnrichment.swift`
- Modify: `Sources/AgentStudio/Core/State/MainActor/Atoms/RepoCacheAtom.swift`
- Modify: `Sources/AgentStudio/App/Coordination/WorkspaceCacheCoordinator.swift` only if branch/origin handlers still force timestamp-only writes after the atom guard.
- Test: `Tests/AgentStudioTests/Core/PaneRuntime/Sources/GitWorkingDirectoryProjectorTests.swift`
- Test: `Tests/AgentStudioTests/App/WorkspaceCacheCoordinatorTests.swift`
- Optional test: `Tests/AgentStudioTests/Core/Stores/WorkspaceRepoCacheTests.swift`

- [ ] **Step 1: Add failing projector test for identical snapshot suppression**

Register one worktree, return the same `GitWorkingTreeStatus` twice, post two refresh-triggering changesets, and expect exactly one `.snapshotChanged`.

Expected failure before implementation: snapshot count reaches 2.

- [ ] **Step 2: Add failing projector test for changed snapshot still emitting**

Use a provider that returns changed summary or branch on the second call. Expect two snapshots.

Expected failure before implementation if suppression is too broad: the second snapshot is missing.

- [ ] **Step 3: Add failing cache no-op test**

Exercise `RepoEnrichmentCacheAtom.setWorktreeEnrichment` or coordinator consumption with two enrichments that have the same cache content and different `updatedAt`. Expect the original `updatedAt` to remain and the dictionary not to be replaced by timestamp-only content.

Expected failure before implementation: the second write replaces the value.

- [ ] **Step 4: Add failing snapshot-only cache update test**

Use two enrichments with the same `worktreeId`, `repoId`, `branch`, and `isMainWorktree`, but different `snapshot.summary` values. Expect the cache to update and `updatedAt` to represent the actual content change.

Expected failure before implementation if the gate accidentally uses `WorktreeEnrichment.==`: the summary-only update is skipped.

- [ ] **Step 5: Implement explicit worktree enrichment content equivalence**

Add a method such as:

```swift
extension WorktreeEnrichment {
    func hasSameCacheContent(as other: WorktreeEnrichment) -> Bool {
        worktreeId == other.worktreeId
            && repoId == other.repoId
            && branch == other.branch
            && isMainWorktree == other.isMainWorktree
            && snapshot == other.snapshot
    }
}
```

Do not change `Equatable` or `Hashable` in this task. Existing persistence/projection code may depend on the current conformance shape, and `GitWorkingTreeSnapshot` is `Equatable` but not `Hashable`.

- [ ] **Step 6: Guard worktree enrichment writes**

In `RepoEnrichmentCacheAtom.setWorktreeEnrichment`, no-op when the existing value has the same cache content. This protects every write caller, not only `WorkspaceCacheCoordinator`.

- [ ] **Step 7: Dedupe projector snapshot emission**

In `GitWorkingDirectoryProjector`, add `lastEmittedSnapshotByWorktreeId: [UUID: GitWorkingTreeSnapshot]`. In `computeAndEmit`, build `nextSnapshot`, emit `.snapshotChanged` only when it differs from the last emitted snapshot, and still run branch/origin handling afterward.

Clear the snapshot cache on unregister and shutdown.

Important: origin checks must still run for periodic empty-path changesets even when the snapshot is identical, because origin freshness is not represented in `GitWorkingTreeSnapshot`.

- [ ] **Step 8: Run focused tests**

```bash
swift test --filter GitWorkingDirectoryProjectorTests
swift test --filter WorkspaceCacheCoordinatorTests
```

Expected: new red tests pass; existing branch/origin/coalescing tests continue to pass.

## Phase 1 Task 3: Replace the All-Worktree Sweep with Budgeted Tiered Admission

**Files:**

- Modify: `Sources/AgentStudio/Infrastructure/AppPolicies.swift`
- Modify: `Sources/AgentStudio/App/Coordination/FilesystemGitPipeline.swift`
- Modify: `Sources/AgentStudio/Core/RuntimeEventSystem/Git/GitWorkingDirectoryProjector.swift`
- Modify: `Sources/AgentStudio/Core/RuntimeEventSystem/Filesystem/FilesystemActor.swift` only if the ignored-only integration proof cannot be handled at projector admission.
- Test: `Tests/AgentStudioTests/Core/PaneRuntime/Sources/GitWorkingDirectoryProjectorTests.swift`
- Test: `Tests/AgentStudioTests/Integration/FilesystemGitPipelineIntegrationTests.swift`
- Test: `Tests/AgentStudioTests/Core/PaneRuntime/Sources/FilesystemActorTests.swift` only for classification/flush coverage.

- [ ] **Step 1: Add `AppPolicies.GitRefresh`**

Add one policy value surface for production defaults and test fixtures. Start with these defaults unless tests show a hidden contract:

```swift
enum AppPolicies {
    enum GitRefresh {
        static let fastTickInterval: Duration = .seconds(2)
        static let foregroundRefreshInterval: Duration = .seconds(2)
        static let activeRefreshInterval: Duration = .seconds(10)
        static let backgroundRefreshInterval: Duration = .seconds(120)
        static let foregroundEventDebounce: Duration = .milliseconds(200)
        static let activeEventDebounce: Duration = .milliseconds(750)
        static let backgroundEventDebounce: Duration = .seconds(15)
        static let backgroundRefreshesPerTick: Int = 3
        static let maxConcurrentStatusComputes: Int = 4
        static let initialFailureBackoff: Duration = .seconds(15)
        static let maximumFailureBackoff: Duration = .seconds(120)
    }
}
```

If direct static constants make clock tests awkward, introduce a small `GitRefreshPolicy: Sendable` value and have `AppPolicies.GitRefresh.defaultPolicy` create it.

- [ ] **Step 2: Add failing tests for tier membership and cadence**

Use `TestPushClock` and a provider call counter to prove:

- foreground worktree is due on the 2s tick
- open-but-not-foreground worktree is not due on the 2s tick but is due by 10s
- background worktree is not due at 10s but is due by 120s
- filesystem event requests can wake a worktree before its periodic interval after the tier debounce

Expected failure before implementation: the 2s tick enqueues all registered worktrees.

- [ ] **Step 3: Add failing global-budget test**

Register at least 100 worktrees and use a gated provider that records concurrent `status(for:)` calls. Advance the clock or enqueue enough changes to make all worktrees due.

Assert:

- max concurrent provider calls never exceeds `maxConcurrentStatusComputes`
- an active/foreground request can start while background requests are queued
- background requests remain queued instead of spawning one task per worktree

Expected failure before implementation: concurrency grows with worktree count.

- [ ] **Step 4: Add failing background striping and oldest-stale tests**

With 100+ background worktrees:

- each fast tick enqueues at most `backgroundRefreshesPerTick` background periodic refreshes
- oldest-stale background work is eventually admitted even when foreground/open work remains busy
- no single tick enqueues the whole background fleet

Expected failure before implementation: every registered background worktree is enqueued on each periodic tick.

- [ ] **Step 5: Add failing activity-before-registration tests**

Add projector tests for both orderings:

- `setActivity(worktreeId:isActiveInApp: true)` before register, then register -> first periodic decision treats the worktree as active
- register, then `setActivePaneWorktree(worktreeId:)` -> next periodic decision treats it as foreground

Expected failure before implementation: pre-registration activity is ignored or foreground does not affect projector scheduling.

- [ ] **Step 6: Add failing direct lifecycle / bus-drop recovery test**

Do not rely only on `.worktreeRegistered` bus delivery for projector truth. Add direct lifecycle methods on the projector, then update `FilesystemGitPipeline.register` and `unregister` to call them directly from the topology-derived pane-coordinator sync path.

Test the pipeline/projector path with a scenario where the bus topology event is not delivered to the projector but `FilesystemGitPipeline.register` is called. The projector must still schedule the worktree.

Expected failure before implementation: projector only knows registrations from the bus stream.

- [ ] **Step 7: Add failing ignored-only input filter tests**

Pin the empty-path cases separately:

- ignored-only suppressed changeset: `paths.isEmpty`, `containsGitInternalChanges == false`, `suppressedIgnoredPathCount > 0` -> no provider call
- git-internal-only changeset: `paths.isEmpty`, `containsGitInternalChanges == true` -> provider call
- projected path changeset: `paths` non-empty -> provider call
- `.git/config` projected path -> provider call and origin logic preserved

Expected failure before implementation: ignored-only changeset still computes.

- [ ] **Step 8: Add failing nil-status retry/backoff test**

Use a provider that returns nil once and a valid status after the backoff. With `TestPushClock`, prove the refresh is requeued after `initialFailureBackoff` and eventually emits the snapshot.

Also prove retry state is cleared on success, unregister, and shutdown.

Expected failure before implementation: nil status is consumed and dropped.

- [ ] **Step 9: Implement request admission inside the projector**

Keep this projector-internal unless the file grows beyond a maintainable size; if it does, extract `GitRefreshScheduler` immediately using the Phase 2 contract.

Implementation shape:

- replace direct `spawnOrCoalesce` fan-out with a ready queue plus `startWorktreeTasksIfBudgetAllows()`
- track `inFlightStatusComputeCount` or equivalent using `worktreeTasks.count`
- keep `pendingByWorktreeId` as the coalescing surface; newer changesets still replace older pending work per worktree
- track tier state:
  - `activeWorktreeIds: Set<UUID>`
  - `activePaneWorktreeId: UUID?`
  - pending pre-registration activity facts
- track freshness:
  - `lastRefreshAttemptByWorktreeId`
  - `lastSuccessfulRefreshByWorktreeId`
  - `nextEligibleRefreshByWorktreeId`
  - `failureBackoffByWorktreeId`
- periodic tick enqueues:
  - foreground if due
  - active/open worktrees if due
  - at most `backgroundRefreshesPerTick` due background worktrees, ordered by oldest successful refresh plus stable tie-break
- event changesets enqueue after tier debounce and are prioritized by tier
- oldest-stale background work gets at least one admission opportunity so it cannot starve behind foreground/open churn

Do not spawn a task for every pending worktree. Start only up to the budget.

- [ ] **Step 10: Wire foreground and activity into the projector**

Update `FilesystemGitPipeline.setActivity` to forward to both `filesystemActor` and `gitWorkingDirectoryProjector`.

Update `FilesystemGitPipeline.setActivePaneWorktree` to forward to both `filesystemActor` and `gitWorkingDirectoryProjector`.

Update `FilesystemGitPipeline.register` and `unregister` so the projector receives direct lifecycle facts from the topology-derived registration path, not only via the EventBus.

Direct projector lifecycle methods must be idempotent because bus topology events may still arrive.

- [ ] **Step 11: Preserve branch/origin semantics**

Keep origin checks for periodic empty-path refreshes and `.git/config` changes. Snapshot dedupe must not skip origin/branch handling.

- [ ] **Step 12: Preserve lifecycle cleanup**

On unregister and shutdown, clear:

- pending changeset/request state
- ready queue membership
- in-flight task references
- activity and foreground facts for that worktree
- last snapshot/freshness/backoff state
- branch/origin state where applicable

- [ ] **Step 13: Run focused tests**

```bash
swift test --filter GitWorkingDirectoryProjectorTests
swift test --filter FilesystemGitPipelineIntegrationTests
swift test --filter FilesystemActorTests
```

Expected: active refresh behavior preserved, background sweep striped, git compute budget enforced, suppressed-only churn filtered, failed computes retried, origin/branch behavior preserved.

## Phase 1 Task 4: Validation, Profiling, and Stop/Continue Gate

**Files:**

- Evidence output: `tmp/debug-workflows/2026-06-11-agent-studio-performance-issues-cmdp-slowdown/`
- No source changes unless previous tasks require test-only helpers.

- [ ] **Step 1: Run formatting/lint**

```bash
mise run format
mise run lint
```

Expected: zero formatter/lint errors.

- [ ] **Step 2: Run full default test gate**

```bash
mise run test
```

Expected: all default Swift tests pass. E2E and Zmx E2E remain skipped unless explicitly enabled by environment, matching repo default.

- [ ] **Step 3: Build a debug app for smoke**

```bash
mise run build
```

Expected: debug build succeeds and prints the allocated build path.

- [ ] **Step 4: Smoke only debug or beta app**

Do not shut down or manipulate the user-running AgentStudio host app. Launch the debug build or use AgentStudio Beta for live experiments.

Capture before/after evidence in the debug workflow directory:

- idle `sample` for 5 seconds
- `ps` watch for AgentStudio child `git` processes
- foreground active-pane typing responsiveness
- open-but-not-focused worktree freshness
- background-only fleet refresh behavior
- Cmd-P/everything open responsiveness
- Cmd-T/# repo scope open responsiveness
- management-layer toggle responsiveness
- linked-worktree fallback scenario: make an external git change in a linked worktree and prove the sweep-primary path refreshes the correct badge within the accepted SLA

Numeric acceptance targets:

- idle CPU target: < 10% after settle in debug/beta smoke
- concurrent child `git` processes: <= `maxConcurrentStatusComputes` during steady state, excluding unrelated user git processes
- status compute rate: roughly <= 2/s during idle background reconciliation at the current 163-worktree scale
- main-thread sample no longer dominated by continuous `PaneLeafContainer.body` -> `repoAndWorktree(containing:)` -> `URL.standardizedFileURL` loop
- typing in foreground terminal and Cmd-P input should not queue behind a continuous render storm

- [ ] **Step 5: Decide Phase 3**

If post-Phase-1 sample still shows `WorkspaceRepositoryTopologyAtom.repoAndWorktree(containing:)`, `PaneManagementContext.project`, or command-bar repo row building as a top offender, continue to Phase 3 in this plan.

If the Phase 1 sample meets the targets and MainActor hot paths no longer dominate, stop and record that Phase 3 is deferred. Do not touch render/command-bar code just because it appears in the old plan.

- [ ] **Step 6: Record proof summary**

Update the debug workflow artifact with:

- commands run
- pass/fail counts
- sample paths
- ps-watch summary
- threshold results
- remaining unresolved performance symptoms
- decision: stop after Phase 1 or continue to Phase 3

## Conditional Phase 3 Task 5: Move Repo/Worktree Path Matching to a Topology-Owned Normalized Index

Only execute if Task 4 proves `repoAndWorktree(containing:)` / `URL.standardizedFileURL` remains a top MainActor offender after Phase 1.

**Files:**

- Modify: `Sources/AgentStudio/Core/State/MainActor/Atoms/WorkspaceRepositoryTopologyAtom.swift`
- Test: `Tests/AgentStudioTests/Core/Views/WorkspaceLookupDerivedTests.swift`
- Test: add `Tests/AgentStudioTests/Core/State/MainActor/Atoms/WorkspaceRepositoryTopologyAtomTests.swift` if no existing topology atom test file fits.

- [ ] **Step 1: Add behavior tests for path lookup before refactor**

Cover:

- cwd inside a worktree resolves that repo/worktree
- longest matching worktree path wins
- main worktree tie-break behavior remains stable
- missing cwd returns nil
- removed/reconciled worktree is no longer matched

- [ ] **Step 2: Add private normalized path index**

Keep `repos` and `watchedPaths` public state unchanged. Add a private helper/index derived from `repos`, with cached normalized strings and existing tie-break metadata.

Do not add normalized cache fields to `Repo`, `Worktree`, `PaneContextFacets`, or `PaneMetadata`.

- [ ] **Step 3: Rebuild/update the index at topology mutation points**

Update index maintenance in:

- `hydrate(_:)`
- `addRepo(at:)`
- `removeRepo(_:)`
- `reassociateRepo(_:to:)`
- `reconcileDiscoveredWorktrees(_:worktrees:)`

- [ ] **Step 4: Update `repoAndWorktree(containing:)`**

Normalize the incoming cwd once. Compare against cached candidate strings. Preserve the current candidate ordering and tie-break semantics.

- [ ] **Step 5: Run focused tests**

```bash
swift test --filter WorkspaceLookupDerivedTests
swift test --filter WorkspaceRepositoryTopologyAtomTests
```

Expected: behavior preserved with fewer render-time URL normalizations.

## Conditional Phase 3 Task 6: Reduce Render-Path Duplicate Pane Context Projection

Only execute if Task 4 proves pane management/context projection remains hot after Phase 1.

**Files:**

- Modify: `Sources/AgentStudio/Core/Views/Panes/PaneManagementContext.swift`
- Modify: `Sources/AgentStudio/Core/Views/Panes/PaneLeafContainer.swift`
- Test: `Tests/AgentStudioTests/Core/Views/PaneManagementContextTests.swift`

- [ ] **Step 1: Add tests for explicit ids avoiding fallback lookup**

Add or extend tests so a pane with valid `repoId`/`worktreeId` resolves management context without requiring cwd fallback. The behavior assertion should remain user-facing: correct repo name, worktree name, target path, branch chips, and notification chips.

- [ ] **Step 2: Reuse resolved context inside `PaneManagementContext.project`**

Ensure the method computes resolved context once and reuses it for target path, identity rows, and status chips. Avoid a second `workspaceLookup.repoAndWorktree(containing:)` call after the first resolved context is known.

- [ ] **Step 3: Avoid duplicate projection in `PaneLeafContainer.body`**

When `currentLocationTargetPaneId == paneHost.id`, reuse the already-computed `managementContext` as the `locationContext`. Only compute a second context when the location target differs.

- [ ] **Step 4: Keep broad memoization out of scope**

Do not introduce revision-keyed `WorkspacePaneDerived` caching in this plan. If render samples still show repeated derived recompute after Tasks 5-6, split a dedicated derived-reader memoization plan.

- [ ] **Step 5: Run focused tests**

```bash
swift test --filter PaneManagementContextTests
```

Expected: existing management-context behavior preserved.

## Conditional Phase 3 Task 7: Reduce Command-Bar Repo/Worktree Eagerness

Only execute if Task 4 proves Cmd-P/# remains slow after Phase 1 or command-bar row builders remain hot in sample.

**Files:**

- Modify: `Sources/AgentStudio/Core/State/MainActor/Atoms/WorkspaceLookupDerived.swift`
- Modify: `Sources/AgentStudio/Features/CommandBar/CommandBarDataSource+WorktreeRows.swift`
- Modify: `Sources/AgentStudio/Features/CommandBar/CommandBarDataSource.swift` if the root/everything scope call sites need to pass a precomputed presence index.
- Test: `Tests/AgentStudioTests/Features/CommandBar/WorktreePresenceTests.swift`
- Test: `Tests/AgentStudioTests/Features/CommandBar/CommandBarDataSourceTests.swift`
- Test: `Tests/AgentStudioTests/Features/CommandBar/CommandBarUnifiedWorktreeDataSourceTests.swift`
- Test: `Tests/AgentStudioTests/Features/CommandBar/CommandBarWorktreeRowBuilderTests.swift`

- [ ] **Step 1: Add failing regression test for repeated pane-location scans**

Introduce a test seam or pure helper that proves repo scope computes pane locations once per command-bar item build, not once per repo/worktree row. Keep the test behavior-focused if direct call counting would make production APIs uglier.

- [ ] **Step 2: Add a batch pane-location helper**

Add a `WorkspaceLookupDerived` method that builds `[UUID: [WorkspacePaneLocation]]` for all worktrees by traversing panes/tabs once.

- [ ] **Step 3: Pass precomputed presence into repo/worktree row builders**

Build a `WorktreePresence` map once inside repo/everything scope construction. Pass it into `repoRootItem`, `repoRootSubtitle`, `buildRepoLevel`, and unified worktree rows instead of calling `buildWorktreePresence` repeatedly.

- [ ] **Step 4: Defer action-model laziness unless tests show it is still needed**

Do not change `CommandBarItem.action` to a closure or lazy command-level factory in this plan unless the precomputed presence map still leaves Cmd-P/# open measurably slow. That change touches more command-bar action semantics and deserves its own proof.

- [ ] **Step 5: Run focused command-bar tests**

```bash
swift test --filter CommandBarDataSourceTests
swift test --filter WorktreePresenceTests
swift test --filter CommandBarUnifiedWorktreeDataSourceTests
swift test --filter CommandBarWorktreeRowBuilderTests
```

Expected: command-bar row behavior preserved; repo scope no longer repeats pane-location scans per row.

## Split / Replan Triggers

- If adding scheduler/admission state pushes `GitWorkingDirectoryProjector.swift` near the repo's large-file smell threshold, stop and extract `GitRefreshScheduler` instead of bloating the projector.
- If Task 1 optional-locks tests require changing `DefaultProcessExecutor`, stop and re-evaluate; the intended change belongs in the git status provider.
- If Task 2 does not reduce cache mutation counts, instrument `RepoEnrichmentCacheAtom.setWorktreeEnrichment` and `WorkspaceCacheCoordinator.handleEnrichment` before changing refresh policy.
- If Task 3 breaks origin retry or ahead/behind freshness tests, preserve sweep-primary correctness and revise tier timing instead of disabling periodic refresh.
- If ignored-only filtering risks suppressing `.git/config` or git-internal changes, stop and split a filesystem classification design note.
- If Task 4 smoke cannot produce a stable debug/beta sample without manipulating the user-running AgentStudio host app, stop and report the validation blocker.
- If Phase 3 path resolution changes behavior, stop and re-evaluate normalization semantics before touching render code.
- If Phase 3 requires a broad derived memoization owner, split that into a separate design/plan.
- If Phase 3 requires changing `CommandBarItem.action` or navigation semantics, split command-bar action laziness into a separate plan.
- If lint/build/test failures are outside these code paths, stop edits and report scoped pass/fail status before changing tooling or infrastructure.

## Security and Trust Boundaries

- The hot path runs local `git` subprocesses with structured arguments, not shell interpolation.
- `GIT_OPTIONAL_LOCKS=0` reduces interference with user and agent git operations; it does not change repository config.
- Budgeting reduces local subprocess pressure and filesystem observation pressure.
- This plan does not introduce network calls, plugin/MCP execution, new shell command construction, or broader filesystem permissions.
- FSEvents paths already flow through existing classification. Raw callback filtering and overflow-flag handling are deferred.
- Stale context risk is correctness-sensitive: UI must not copy, reveal, or label the wrong repo/worktree path. This is why direct topology-derived lifecycle facts feed the projector and why event-primary correctness is rejected here.

## Recommended Execution Order

1. Phase 1 Task 1 only, then focused provider tests.
2. Phase 1 Task 2 only, then projector/coordinator tests.
3. Phase 1 Task 3 only, then projector/pipeline/filesystem tests.
4. Phase 1 Task 4 full quality gates and debug/beta smoke.
5. Stop if Task 4 meets thresholds.
6. Only if Task 4 proves remaining MainActor or command-bar hotspots, execute conditional Phase 3 tasks in order: Task 5, Task 6, Task 7, each with its focused tests and a sample checkpoint.

## Recommended Next Skill

Use `shravan-dev-workflow:implementation-execute-plan` or `superpowers:subagent-driven-development` only after the user explicitly switches to act mode for this revised plan. Do not implement code yet.
