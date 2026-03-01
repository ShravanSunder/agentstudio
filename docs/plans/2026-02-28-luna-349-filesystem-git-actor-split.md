# LUNA-349 Event-Driven Filesystem -> Git Projector Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Split local git status from `FilesystemActor` into a dedicated event-driven `GitWorkingDirectoryProjector`, with stable current-state materialization and deterministic cleanup semantics.

**Architecture:** `FilesystemActor` emits filesystem facts only (`.filesChanged` + root lifecycle facts). `GitWorkingDirectoryProjector` subscribes to the same EventBus, consumes self-describing filesystem events (`worktreeId` + `rootPath`), dedupes by worktree identity (last-writer-wins), computes local git state off actor isolation, and emits derived git facts (`.gitSnapshotChanged` + optional `.branchChanged`).

**Tech Stack:** Swift 6.2 actors, `EventBus<PaneEventEnvelope>`, stdlib `AsyncStream`, `@concurrent nonisolated` git compute helpers, Swift Testing (`import Testing`), `mise` format/lint/test tasks.

---

## Swift 6.2 Grounding (Primary Sources)

1. `AsyncStream.Continuation` is `Sendable` and supports concurrent producers.  
   Sources:
   - https://github.com/swiftlang/swift/blob/main/stdlib/public/Concurrency/AsyncStream.swift
   - https://github.com/swiftlang/swift-evolution/blob/main/proposals/0314-async-stream.md
2. Swift 6.2 changed `nonisolated async` semantics (SE-0461). Use `@concurrent` for explicit off-actor execution.
   Source:
   - https://github.com/swiftlang/swift-evolution/blob/main/proposals/0461-async-function-isolation.md
3. SE-0406 typed backpressure/watermarks is not available (returned for revision).  
   Source:
   - https://forums.swift.org/t/se-0406-backpressure-support-for-asyncstream/66771

## Non-Negotiable Invariants

- EventBus carries facts only. No command channel between filesystem and git actors.
- `FilesystemActor` owns path ingestion/routing/chunking priority only. No local git compute.
- `GitWorkingDirectoryProjector` is a bus projector: subscribe -> filter -> resolve -> dedupe -> compute -> emit.
- Dedupe key is `worktreeId`; `rootPath` is read from each `FileChangeset` payload (no long-lived rootPath resolver index).
- Git facts must materialize stable current state in one event (`summary + branch`) to avoid branch bootstrapping acrobatics.
- `GitWorkingDirectoryProjector` must cleanup per-worktree state on worktree removal facts.
- `GitStatusProvider.status(for:)` must execute expensive git work off actor isolation (`@concurrent nonisolated` helper contract).
- Remove `FilesystemActor.shared`; pipeline owns lifecycle.

## Data Contracts (Explicit)

### Filesystem Input Fact (from `FilesystemActor`)

```swift
struct FileChangeset: Sendable {
    let worktreeId: UUID
    let rootPath: URL
    let paths: [String]
    let timestamp: ContinuousClock.Instant
    let batchSeq: UInt64
}
```

### Root Lifecycle Facts (from `FilesystemActor`)

```swift
enum FilesystemEvent: Sendable {
    case worktreeRegistered(worktreeId: UUID, rootPath: URL)
    case worktreeUnregistered(worktreeId: UUID)
    case filesChanged(changeset: FileChangeset)
    case gitSnapshotChanged(snapshot: GitWorkingTreeSnapshot)
    case branchChanged(from: String, to: String) // optional convenience event
    case diffAvailable(diffId: UUID)
}
```

### Stable Git Materialization Fact (from `GitWorkingDirectoryProjector`)

```swift
struct GitWorkingTreeSnapshot: Sendable {
    let worktreeId: UUID
    let rootPath: URL
    let summary: GitStatusSummary
    let branch: String?
}
```

`gitSnapshotChanged` is the canonical materialized state event for stores.  
`branchChanged` remains optional derivative telemetry/UX event.  
`worktreeRegistered` is retained to allow eager initial git materialization before first file change.

## Out of Scope

- Remote git/GitHub/forge status (Forge actor responsibility).
- Debounce policy changes beyond local projector coalescing window.
- FSEvent source implementation hardening beyond this split.
- Future migration to SE-0406 APIs when available.

## Deferred Follow-up (Must Track): Git Ignore + `.git` Noise Control

This split plan intentionally keeps filesystem->git actor boundaries focused.  
A follow-up task is required to prevent noisy filesystem churn and align emitted facts with repo intent.

### Follow-up Task 10: Ignore-Aware Filesystem Filtering and `.git` Event Shaping

**Problem to solve:** `FilesystemActor` currently ingests and emits all routed paths for a worktree.  
It does not yet:
- suppress `.git/**` high-churn internals from projection-facing `filesChanged` payloads
- apply repo ignore policy (for example `.gitignore`) before app-wide path materialization

**Goal:** respect ignore policy and avoid over-reacting to `.git` folder churn while preserving correct git snapshot updates.

**Design constraints:**
- Keep EventBus facts-only architecture unchanged.
- Do not run expensive per-path shell git commands inside `FilesystemActor` hot path.
- Maintain app responsiveness for very large repositories.
- Keep dedupe key as `worktreeId` (last-writer-wins in git projector).

**Proposed shape (v1 follow-up):**
1. Add `FilesystemPathFilter` in `FilesystemActor` ingestion pipeline:
   - drop `.git/**` paths from `filesChanged` projection payloads
   - keep explicit allowlist for git-state-trigger files if needed (`.git/HEAD`, `.git/index`, `.git/refs/**`, `.git/packed-refs`)
2. Add optional `containsGitInternalChanges: Bool` in `FileChangeset` (or equivalent facet) so `GitWorkingDirectoryProjector` can still trigger refresh without flooding path lists.
3. Add ignore-policy layer for non-git files:
   - Option A: static ignore matcher cached per worktree (preferred)
   - Option B: defer ignore semantics to git snapshot only (acceptable fallback if latency/cost too high)
4. Ensure projection stores do not materialize ignored or `.git` noise paths.

**Required tests (unit + integration):**
- `FilesystemActorTests`
  - drops `.git/objects/**` and similar churn paths from emitted `filesChanged`
  - preserves necessary git trigger signals for snapshot recompute
  - filters ignored paths according to configured ignore policy
- `GitWorkingDirectoryProjectorTests`
  - git snapshot recompute still occurs when only git-internal trigger arrives
  - worktree-scoped dedupe remains last-writer-wins under bursty `.git` churn
- `FilesystemGitPipelineIntegrationTests`
  - projection store remains stable (no `.git` noise)
  - workspace git snapshot still converges correctly

**Acceptance criteria:**
- `.git` internal churn does not flood `filesChanged` events consumed by sidebar/projections.
- ignored files are not materialized in projection-facing path events.
- git snapshot correctness is preserved for branch/index/worktree changes.

### Follow-up Task 11: Replanning Pass for Filesystem Ingestion + Projection Semantics

**Problem to solve:** after the actor split lands, we still need a focused replanning pass to validate event cadence and projection semantics against real workspace behavior (large nested folders, app-wide subscriptions, pane-scoped projections).

**Goal:** produce a post-implementation mini-spec that locks remaining runtime decisions with measurements, then execute it as a separate implementation ticket.

**Scope of replanning pass:**
1. Verify app-wide single-subscription constraints end-to-end (no accidental duplicate watchers).
2. Validate batching cadence and buffering policy for active vs non-active worktrees.
3. Validate projection filtering boundaries (`paneId`, `cwd`, and worktree association rules) with concrete examples.
4. Define cleanup/retention policy for removed worktrees and stale projection state.
5. Document measurable SLOs (event lag, burst handling, memory growth ceilings) and the test harness needed to enforce them.

**Required outputs:**
- Add a dedicated follow-up plan doc section with:
  - final data-shape decisions
  - actor ownership boundaries
  - measurable acceptance criteria
- Create/track a separate execution ticket for the replanning outcomes.

**Acceptance criteria:**
- Replanning decisions are documented and linked to executable tests/benchmarks.
- No unresolved ownership ambiguity remains between filesystem ingestion, git projection, and sidebar projection consumers.
- Follow-up execution work is ticketed and scoped before implementation starts.

---

### Task 1: Update Runtime Event Contracts for Materialized Git State

**Files:**
- Modify: `Sources/AgentStudio/Core/PaneRuntime/Contracts/PaneRuntimeEvent.swift`
- Modify: `Sources/AgentStudio/Core/PaneRuntime/Projection/WorkspaceGitStatusStore.swift`
- Modify: `Sources/AgentStudio/Core/PaneRuntime/Projection/PaneFilesystemProjectionStore.swift`
- Modify: `Sources/AgentStudio/Core/PaneRuntime/Replay/EventReplayBuffer.swift`
- Modify: `Tests/AgentStudioTests/Core/PaneRuntime/Projection/WorkspaceGitStatusStoreTests.swift`
- Modify: `Tests/AgentStudioTests/Core/PaneRuntime/Projection/PaneFilesystemProjectionStoreTests.swift`
- Modify: `Tests/AgentStudioTests/Core/PaneRuntime/Replay/EventReplayBufferTests.swift`
- Modify: all tests constructing `FileChangeset` literals

**Step 1: Write failing store tests for snapshot materialization**

```swift
@Test("git snapshot event materializes summary and branch in one pass")
func gitSnapshotMaterializesSummaryAndBranch() {
    let store = WorkspaceGitStatusStore()
    let worktreeId = UUID()
    store.consume(makeFilesystemEnvelope(
        seq: 1,
        worktreeId: worktreeId,
        event: .gitSnapshotChanged(
            snapshot: GitWorkingTreeSnapshot(
                worktreeId: worktreeId,
                rootPath: URL(fileURLWithPath: "/tmp/repo"),
                summary: .init(changed: 2, staged: 1, untracked: 3),
                branch: "feature/split"
            )
        )
    ))
    let snapshot = try #require(store.snapshotsByWorktreeId[worktreeId])
    #expect(snapshot.summary.changed == 2)
    #expect(snapshot.branch == "feature/split")
}
```

**Step 2: Run failing tests**

Run: `SWIFT_BUILD_DIR=".build-agent-fs-git-split" swift test --build-path "$SWIFT_BUILD_DIR" --filter "WorkspaceGitStatusStoreTests"`
Expected: FAIL (new event shape missing).

**Step 3: Implement contract changes**

- Add `rootPath` to `FileChangeset`.
- Add `GitWorkingTreeSnapshot`.
- Replace `.gitStatusChanged(summary:)` with `.gitSnapshotChanged(snapshot:)`.
- Update `WorkspaceGitStatusStore.consume` to materialize from `.gitSnapshotChanged`.
- Update every `FilesystemEvent` switch/guard site (`WorkspaceGitStatusStore`, `EventReplayBuffer`, projection store filters) for new enum cases.
- Keep `.branchChanged` handling as optional/secondary.

**Step 4: Update all `FileChangeset` literal construction sites**

Run: `rg -n "FileChangeset\\(" Sources Tests`
Expected: every call site now provides `rootPath`.

Run: `rg -n "gitStatusChanged|switch filesystemEvent|case \\.worktreeRegistered|case \\.worktreeUnregistered" Sources Tests`
Expected: stale old-case references are replaced/handled.

**Step 5: Re-run targeted tests**

Run: `SWIFT_BUILD_DIR=".build-agent-fs-git-split" swift test --build-path "$SWIFT_BUILD_DIR" --filter "WorkspaceGitStatusStoreTests"`
Expected: PASS.

**Step 6: Commit**

```bash
git add Sources/AgentStudio/Core/PaneRuntime/Contracts/PaneRuntimeEvent.swift Sources/AgentStudio/Core/PaneRuntime/Projection/WorkspaceGitStatusStore.swift Tests/AgentStudioTests/Core/PaneRuntime/Projection/WorkspaceGitStatusStoreTests.swift
git commit -m "refactor: materialize git state as snapshot event and add rootPath to files changeset"
```

---

### Task 2: Refactor FilesystemActor to Facts-Only + Root Lifecycle Events

**Files:**
- Modify: `Sources/AgentStudio/Core/PaneRuntime/Sources/FilesystemActor.swift`
- Modify: `Tests/AgentStudioTests/Core/PaneRuntime/Sources/FilesystemActorTests.swift`

**Step 1: Add failing tests for root lifecycle facts**

```swift
@Test("register emits worktreeRegistered fact")
func registerEmitsWorktreeRegisteredFact() async throws { ... }

@Test("unregister emits worktreeUnregistered fact")
func unregisterEmitsWorktreeUnregisteredFact() async throws { ... }
```

**Step 2: Run failing suite**

Run: `SWIFT_BUILD_DIR=".build-agent-fs-git-split" swift test --build-path "$SWIFT_BUILD_DIR" --filter "FilesystemActorTests"`
Expected: FAIL.

**Step 3: Remove git behavior and emit lifecycle facts**

- Remove `gitStatusProvider` property + init parameter.
- Remove unused `clock` init parameter.
- Remove `RootState.lastKnownBranch`.
- Remove `static let shared`.
- `register(...)` posts `.worktreeRegistered(...)`.
- `unregister(...)` posts `.worktreeUnregistered(...)`.
- `flush(...)` emits only `.filesChanged(changeset:)` with `rootPath`.

**Step 4: Update existing test constructors (all current call sites)**

- Replace `FilesystemActor(bus:..., gitStatusProvider: ...)` with `FilesystemActor(bus: ...)`.
- Remove assertions that belong to git actor behavior.

**Step 5: Re-run suite**

Run: `SWIFT_BUILD_DIR=".build-agent-fs-git-split" swift test --build-path "$SWIFT_BUILD_DIR" --filter "FilesystemActorTests"`
Expected: PASS.

**Step 6: Commit**

```bash
git add Sources/AgentStudio/Core/PaneRuntime/Sources/FilesystemActor.swift Tests/AgentStudioTests/Core/PaneRuntime/Sources/FilesystemActorTests.swift
git commit -m "refactor: make FilesystemActor filesystem-facts-only with root lifecycle events"
```

---

### Task 3: Build GitWorkingDirectoryProjector Projector + Dedupe/Coalescer

**Files:**
- Create: `Sources/AgentStudio/Core/PaneRuntime/Sources/GitWorkingDirectoryProjector.swift`
- Create: `Tests/AgentStudioTests/Core/PaneRuntime/Sources/GitWorkingDirectoryProjectorTests.swift`

**Step 1: Write failing projector tests**

```swift
@Test("filesChanged triggers git snapshot fact")
func filesChangedTriggersGitSnapshotFact() async throws { ... }

@Test("coalesces same worktree to latest while compute in-flight")
func coalescesSameWorktreeToLatest() async throws { ... }

@Test("independent worktrees run independently")
func independentWorktreesRunIndependently() async throws { ... }

@Test("worktree unregistration cancels and clears state")
func worktreeUnregistrationCancelsAndClearsState() async throws { ... }
```

**Step 2: Run failing suite**

Run: `SWIFT_BUILD_DIR=".build-agent-fs-git-split" swift test --build-path "$SWIFT_BUILD_DIR" --filter "GitWorkingDirectoryProjectorTests"`
Expected: FAIL.

**Step 3: Implement actor internals**

```swift
actor GitWorkingDirectoryProjector {
    private let bus: EventBus<PaneEventEnvelope>
    private let gitStatusProvider: any GitStatusProvider
    private let envelopeClock: ContinuousClock
    private let coalescingWindow: Duration
    private let sleepClock: any Clock<Duration>

    private var subscriptionTask: Task<Void, Never>?
    private var worktreeTasks: [UUID: Task<Void, Never>] = [:]
    private var pendingByWorktreeId: [UUID: FileChangeset] = [:]
    private var lastKnownBranchByWorktree: [UUID: String] = [:]
    private var nextEnvelopeSequence: UInt64 = 0
}
```

Subscription loop:

1. `for await envelope in bus.subscribe(bufferingPolicy: .bufferingNewest(256))`
2. Handle `.worktreeRegistered` -> optional eager initial status compute (seed snapshot).
3. Handle `.worktreeUnregistered` -> cancel task + clear `pendingByWorktreeId` + clear `lastKnownBranchByWorktree`.
4. Handle `.filesChanged` -> `pendingByWorktreeId[changeset.worktreeId] = changeset`, `spawnOrCoalesce(worktreeId:)`.

Drain behavior:

1. Per-worktree task loops `while let changeset = pendingByWorktreeId.removeValue(...)`.
2. Optional short coalescing window (`coalescingWindow`, default `.zero`) to absorb burst tails when enabled.
3. Compute via `gitStatusProvider.status(for: changeset.rootPath)`; provider contract requires off-actor compute (`@concurrent nonisolated` helper), so actor executor is not occupied by shell git work.
4. Emit `.gitSnapshotChanged(snapshot:)`.
5. Emit `.branchChanged(from:to:)` only when actual branch delta exists.

Cleanup behavior (implemented in this task):

- On `.worktreeUnregistered`, cancel any in-flight worktree task.
- Remove pending changeset + last known branch state for that worktree.
- Ignore late completions from canceled tasks.

**Step 4: Re-run suite**

Run: `SWIFT_BUILD_DIR=".build-agent-fs-git-split" swift test --build-path "$SWIFT_BUILD_DIR" --filter "GitWorkingDirectoryProjectorTests"`
Expected: PASS.

**Step 5: Commit**

```bash
git add Sources/AgentStudio/Core/PaneRuntime/Sources/GitWorkingDirectoryProjector.swift Tests/AgentStudioTests/Core/PaneRuntime/Sources/GitWorkingDirectoryProjectorTests.swift
git commit -m "feat: add event-driven GitWorkingDirectoryProjector with per-worktree coalescing"
```

---

### Task 4: Deterministic Coalescing + Buffering Tests (No Sleep Flakes)

**Files:**
- Modify: `Tests/AgentStudioTests/Core/PaneRuntime/Sources/GitWorkingDirectoryProjectorTests.swift`
- Reuse/Add: helper clock/gate test utilities

**Step 1: Add failing deterministic tests**

- `coalescingWindowCompactsBurstToSingleFollowupCompute`
- `boundedSubscriberBufferStillConvergesToLatestSnapshot`

Use helper actors:

```swift
private actor AsyncGate { ... }
private actor CallCounter { ... }
```

Use test clock (existing helper style) for window timing where needed.

**Step 2: Run failing tests**

Run: `SWIFT_BUILD_DIR=".build-agent-fs-git-split" swift test --build-path "$SWIFT_BUILD_DIR" --filter "GitWorkingDirectoryProjectorTests"`
Expected: FAIL before full behavior.

**Step 3: Implement missing behavior**

- Ensure last-writer-wins by replacing pending entry.
- Ensure actor never blocks subscription loop on git compute.
- Ensure coalescing window logic is deterministic with injected test clock.

**Step 4: Re-run suite**

Run: `SWIFT_BUILD_DIR=".build-agent-fs-git-split" swift test --build-path "$SWIFT_BUILD_DIR" --filter "GitWorkingDirectoryProjectorTests"`
Expected: PASS.

**Step 5: Commit**

```bash
git add Tests/AgentStudioTests/Core/PaneRuntime/Sources/GitWorkingDirectoryProjectorTests.swift Sources/AgentStudio/Core/PaneRuntime/Sources/GitWorkingDirectoryProjector.swift
git commit -m "test: add deterministic coalescing and buffering coverage for git projector"
```

---

### Task 5: Add FilesystemGitPipeline Composition Root (No Command Wiring)

**Files:**
- Create: `Sources/AgentStudio/Core/PaneRuntime/Sources/FilesystemGitPipeline.swift`
- Modify: `Sources/AgentStudio/App/PaneCoordinator.swift`
- Modify: `Sources/AgentStudio/App/PaneCoordinator+FilesystemSource.swift`

**Step 1: Write failing integration wiring test**

**Test file:** `Tests/AgentStudioTests/Integration/FilesystemGitPipelineIntegrationTests.swift`

```swift
@Test("pipeline emits filesChanged and gitSnapshotChanged on shared bus")
func pipelineEmitsFilesAndGitSnapshotOnSharedBus() async throws { ... }
```

**Step 2: Run failing test**

Run: `SWIFT_BUILD_DIR=".build-agent-fs-git-split" swift test --build-path "$SWIFT_BUILD_DIR" --filter "FilesystemGitPipelineIntegrationTests/pipelineEmitsFilesAndGitSnapshotOnSharedBus"`
Expected: FAIL.

**Step 3: Implement pipeline**

- `FilesystemGitPipeline` owns:
  - `FilesystemActor`
  - `GitWorkingDirectoryProjector`
- Delegates `PaneCoordinatorFilesystemSourceManaging` methods to filesystem actor.
- `start()` starts git actor subscription.
- `shutdown()` shuts both actors down.
- Add test seam `enqueueRawPathsForTesting(...)`.
- Configure production coalescing window here (`.milliseconds(200)`), while `GitWorkingDirectoryProjector` default remains `.zero` for deterministic tests.
- Do not introduce `FilesystemGitPipeline.shared`; wire as regular dependency.
- Update `PaneCoordinator` init to support non-singleton default construction pattern, e.g.:
  - `filesystemSource: (any PaneCoordinatorFilesystemSourceManaging)? = nil`
  - `self.filesystemSource = filesystemSource ?? FilesystemGitPipeline(bus: paneEventBus, coalescingWindow: .milliseconds(200))`

**Step 4: Re-run targeted test**

Run: `SWIFT_BUILD_DIR=".build-agent-fs-git-split" swift test --build-path "$SWIFT_BUILD_DIR" --filter "FilesystemGitPipelineIntegrationTests/pipelineEmitsFilesAndGitSnapshotOnSharedBus"`
Expected: PASS.

**Step 5: Commit**

```bash
git add Sources/AgentStudio/Core/PaneRuntime/Sources/FilesystemGitPipeline.swift Sources/AgentStudio/App/PaneCoordinator.swift Sources/AgentStudio/App/PaneCoordinator+FilesystemSource.swift Tests/AgentStudioTests/Integration/FilesystemGitPipelineIntegrationTests.swift
git commit -m "feat: compose filesystem and git projector actors in FilesystemGitPipeline"
```

---

### Task 6: Store Integration Tests (Projection + Workspace Git Store)

**Files:**
- Modify/Create: `Tests/AgentStudioTests/Integration/FilesystemGitPipelineIntegrationTests.swift`
- Modify (if needed): `Tests/AgentStudioTests/Features/Sidebar/RepoSidebarContentViewTests.swift`

**Step 1: Write failing store fan-in test**

```swift
@MainActor
@Test("bus facts from split pipeline update projection and git stores")
func busFactsFromSplitPipelineUpdateStores() async throws { ... }
```

**Step 2: Run failing test**

Run: `SWIFT_BUILD_DIR=".build-agent-fs-git-split" swift test --build-path "$SWIFT_BUILD_DIR" --filter "FilesystemGitPipelineIntegrationTests/busFactsFromSplitPipelineUpdateStores"`
Expected: FAIL.

**Step 3: Implement test harness**

- Subscribe to bus first.
- Fan into `WorkspaceGitStatusStore.consume` and `PaneFilesystemProjectionStore.consume`.
- Register worktree, enqueue paths, assert eventual snapshot materialization.

**Step 4: Re-run suite**

Run: `SWIFT_BUILD_DIR=".build-agent-fs-git-split" swift test --build-path "$SWIFT_BUILD_DIR" --filter "FilesystemGitPipelineIntegrationTests"`
Expected: PASS.

**Step 5: Commit**

```bash
git add Tests/AgentStudioTests/Integration/FilesystemGitPipelineIntegrationTests.swift Tests/AgentStudioTests/Features/Sidebar/RepoSidebarContentViewTests.swift
git commit -m "test: verify projection and workspace git stores via event-driven split pipeline"
```

---

### Task 7: E2E Migration with Real tmp Git Repo

**Files:**
- Modify: `Tests/AgentStudioTests/Integration/FilesystemSourceE2ETests.swift`
- Modify (if needed): `Tests/AgentStudioTests/Helpers/FilesystemTestGitRepo.swift`

**Step 1: Write failing E2E adaptation**

```swift
@Test("event-driven split pipeline propagates filesystem and git snapshots end-to-end")
func eventDrivenSplitPipelinePropagatesEndToEnd() async throws { ... }
```

**Step 2: Run failing E2E**

Run: `SWIFT_BUILD_DIR=".build-agent-fs-git-split" swift test --build-path "$SWIFT_BUILD_DIR" --filter "E2ESerializedTests/FilesystemSourceE2ETests"`
Expected: FAIL before migration.

**Step 3: Implement E2E migration**

- Use `FilesystemGitPipeline` in coordinator injection.
- Call `pipeline.start()` before enqueue actions.
- Ensure teardown calls `pipeline.shutdown()`.
- Keep file operations confined to helper-created temp repo paths.

**Step 4: Re-run E2E**

Run: `SWIFT_BUILD_DIR=".build-agent-fs-git-split" swift test --build-path "$SWIFT_BUILD_DIR" --filter "E2ESerializedTests/FilesystemSourceE2ETests"`
Expected: PASS.

**Step 5: Commit**

```bash
git add Tests/AgentStudioTests/Integration/FilesystemSourceE2ETests.swift Tests/AgentStudioTests/Helpers/FilesystemTestGitRepo.swift
git commit -m "test: migrate filesystem e2e to event-driven split pipeline"
```

---

### Task 8: Architecture Doc Updates (Final Truth)

**Files:**
- Modify: `docs/architecture/pane_runtime_architecture.md`
- Modify: `docs/architecture/pane_runtime_eventbus_design.md`
- Modify: `docs/plans/2026-02-27-luna-349-fs-event-source-and-runtime-conformers.md`
- Modify: `docs/plans/2026-02-27-luna-349-test-value-plan.md`

**Step 1: Add explicit diagrams and decisions**

- Filesystem facts-only emitter.
- Git projector subscriber pattern.
- Worktree-keyed dedupe design without persistent rootPath index.
- Cleanup on `worktreeUnregistered`.
- Stable materialization via `gitSnapshotChanged`.

**Step 2: Validate wording**

Run: `rg -n "command channel|gitStatusRequest|inline git status in FilesystemActor" docs/architecture docs/plans`
Expected: no stale architecture wording.

**Step 3: Commit**

```bash
git add docs/architecture/pane_runtime_architecture.md docs/architecture/pane_runtime_eventbus_design.md docs/plans/2026-02-27-luna-349-fs-event-source-and-runtime-conformers.md docs/plans/2026-02-27-luna-349-test-value-plan.md
git commit -m "docs: finalize event-driven filesystem-git projector architecture and tests"
```

---

### Task 9: Final Verification Gate

**Step 1: Run formatting/lint**

Run: `mise run format`  
Expected: PASS

Run: `mise run lint`  
Expected: PASS

**Step 2: Run targeted + full tests**

Run: `SWIFT_BUILD_DIR=".build-agent-fs-git-split" swift test --build-path "$SWIFT_BUILD_DIR" --filter "FilesystemActorTests"`  
Expected: PASS

Run: `SWIFT_BUILD_DIR=".build-agent-fs-git-split" swift test --build-path "$SWIFT_BUILD_DIR" --filter "GitWorkingDirectoryProjectorTests"`  
Expected: PASS

Run: `SWIFT_BUILD_DIR=".build-agent-fs-git-split" swift test --build-path "$SWIFT_BUILD_DIR" --filter "FilesystemGitPipelineIntegrationTests"`  
Expected: PASS

Run: `SWIFT_BUILD_DIR=".build-agent-fs-git-split" swift test --build-path "$SWIFT_BUILD_DIR" --filter "E2ESerializedTests/FilesystemSourceE2ETests"`  
Expected: PASS

Run: `SWIFT_BUILD_DIR=".build-agent-fs-git-split" mise run test`  
Expected: PASS

**Step 3: Final checklist**

```markdown
- [x] FilesystemActor emits filesystem + lifecycle facts only
- [x] GitWorkingDirectoryProjector is pure event-driven projector
- [x] Dedupe is worktree-scoped, last-writer-wins
- [x] Event-local rootPath resolution (`FileChangeset.rootPath`) implemented and tested
- [x] Stable git snapshot materialization implemented
- [x] Cleanup on worktree removal implemented and tested
- [x] Unit + integration + E2E pass
```

**Step 4: Commit**

```bash
git add docs/plans/2026-02-28-luna-349-filesystem-git-actor-split.md
git commit -m "docs: finalize detailed execution and verification plan for event-driven fs->git split"
```

---

## Assumptions Locked for Execution

1. Dedupe key is `worktreeId` (not repo-wide id) to support multiple worktrees per repo.
2. `gitSnapshotChanged` is canonical state materialization; `branchChanged` is optional derivative event.
3. `GitWorkingDirectoryProjector` default `coalescingWindow` is `.zero`; production wiring sets `.milliseconds(200)` in `FilesystemGitPipeline`.
4. Cleanup is event-driven through `worktreeUnregistered` facts.
5. Independent `envelope.seq` counters across FilesystemActor and GitWorkingDirectoryProjector are safe because stores do not perform cross-producer sequence comparisons.

---

## Task 10: Residual Runtime Comment Sweep

1. `TerminalRuntime` unsupported command failures must report `envelope.command.requiredCapability` (not hardcoded `.input`) for accurate diagnostics.
2. `PaneCoordinatorFilesystemSourceManaging` must require explicit `start()`/`shutdown()` implementations (remove default protocol no-ops).
3. Bridge/Webview interaction-script JavaScript calls must avoid silent `try?`; failures log at `.debug`.
4. `PaneRuntimeEventChannel.emit` fire-and-forget EventBus hop remains an intentional tradeoff:
   pane-local replay/subscribers are ordered/synchronous; global bus bridge is best-effort to keep runtime command paths non-blocking.
