# LUNA-349 Filesystem + Local Git Actor Split Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Split local git status/branch computation out of `FilesystemActor` into a dedicated `GitStatusActor`, while keeping `EventBus` as fact transport and using a direct command channel for git recompute requests.

**Architecture:** Keep `FilesystemActor` as the app-wide filesystem ingress + nested-root ownership + priority drain source. After each flush, it emits `.filesChanged` facts to `EventBus` and sends one `GitStatusRequest` command to a bounded request channel. `GitStatusActor` consumes requests, coalesces per worktree, computes local git snapshots off actor isolation, and emits `.gitStatusChanged`/`.branchChanged` facts to the same `EventBus`.

**Tech Stack:** Swift 6.2 actors, `AsyncStream`/`AsyncAlgorithms`, `EventBus<PaneEventEnvelope>`, `@concurrent nonisolated` helpers, Swift Testing (`import Testing`), `mise` (`lint`, `test`, `test-e2e`).

---

## Guardrails

- Use `@superpowers:test-driven-development` for every task.
- Keep event-plane vs command-plane separation explicit:
  - Bus (`EventBus`) only carries observable facts.
  - Git recompute trigger uses direct request channel (not bus subscriber dispatch).
- Do not add per-pane filesystem watchers.
- Keep routing semantics unchanged:
  - files changed + git status remain keyed by `sourceFacets.worktreeId`.
- Keep sidebar consumers unchanged (stores consume filesystem facts from bus).
- No compatibility shim path; hard cut to split design.

---

### Task 1: Freeze Split Spec + Contract Invariants in Docs

**Files:**
- Modify: `docs/architecture/pane_runtime_eventbus_design.md`
- Modify: `docs/architecture/pane_runtime_architecture.md`
- Modify: `docs/plans/2026-02-27-luna-349-fs-event-source-and-runtime-conformers.md`

**Step 1: Write failing doc/contract assertions in plan checklist**

```markdown
- [ ] EventBus carries facts only; no git recompute work dispatch.
- [ ] FilesystemActor emits `.filesChanged` and sends `GitStatusRequest` command.
- [ ] GitStatusActor emits `.gitStatusChanged` and `.branchChanged` facts.
- [ ] Coordinator/store consumers remain unchanged.
```

**Step 2: Run grep checks to verify old wording still exists (expected fail)**

Run: `rg -n "FilesystemActor.*git status|ForgeActor.*separate from FilesystemActor|bus.*work dispatch" docs/architecture/pane_runtime_eventbus_design.md docs/architecture/pane_runtime_architecture.md`
Expected: mixed/ambiguous wording that still implies inline git status in FilesystemActor.

**Step 3: Write minimal doc updates**

```markdown
EventBus = observable fact plane only.
Local git recompute = command plane over direct channel FilesystemActor -> GitStatusActor.
```

**Step 4: Re-run grep checks**

Run: `rg -n "facts only|GitStatusActor|GitStatusRequest|command channel" docs/architecture/pane_runtime_eventbus_design.md docs/architecture/pane_runtime_architecture.md`
Expected: PASS with explicit split language.

**Step 5: Commit**

```bash
git add docs/architecture/pane_runtime_eventbus_design.md docs/architecture/pane_runtime_architecture.md docs/plans/2026-02-27-luna-349-fs-event-source-and-runtime-conformers.md
git commit -m "docs: define filesystem->git split and fact-vs-command planes"
```

---

### Task 2: Add Git Status Command Channel Contracts

**Files:**
- Create: `Sources/AgentStudio/Core/PaneRuntime/Sources/GitStatusRequestChannel.swift`
- Test: `Tests/AgentStudioTests/Core/PaneRuntime/Sources/GitStatusRequestChannelTests.swift`

**Step 1: Write failing tests for channel semantics**

```swift
import Foundation
import Testing
@testable import AgentStudio

@Suite("GitStatusRequestChannel")
struct GitStatusRequestChannelTests {
    @Test("enqueues and drains requests in FIFO order")
    func fifoOrder() async throws {
        let channel = GitStatusRequestChannel(bufferLimit: 8)
        await channel.yield(.init(worktreeId: UUID(), rootPath: URL(fileURLWithPath: "/tmp/a"), triggerBatchSeq: 1))
        await channel.yield(.init(worktreeId: UUID(), rootPath: URL(fileURLWithPath: "/tmp/b"), triggerBatchSeq: 2))

        var iterator = await channel.stream().makeAsyncIterator()
        let first = try #require(await iterator.next())
        let second = try #require(await iterator.next())
        #expect(first.triggerBatchSeq == 1)
        #expect(second.triggerBatchSeq == 2)
    }
}
```

**Step 2: Run test to verify it fails**

Run: `SWIFT_BUILD_DIR=".build-agent-fs-git-split" swift test --build-path "$SWIFT_BUILD_DIR" --filter "GitStatusRequestChannelTests"`
Expected: FAIL (missing channel types).

**Step 3: Write minimal implementation**

```swift
import Foundation

struct GitStatusRequest: Sendable, Equatable {
    let worktreeId: UUID
    let rootPath: URL
    let triggerBatchSeq: UInt64
}

actor GitStatusRequestChannel {
    private let continuation: AsyncStream<GitStatusRequest>.Continuation
    private let requests: AsyncStream<GitStatusRequest>

    init(bufferLimit: Int = 64) {
        let (stream, continuation) = AsyncStream.makeStream(
            of: GitStatusRequest.self,
            bufferingPolicy: .bufferingNewest(bufferLimit)
        )
        self.requests = stream
        self.continuation = continuation
    }

    func yield(_ request: GitStatusRequest) {
        continuation.yield(request)
    }

    func stream() -> AsyncStream<GitStatusRequest> {
        requests
    }

    func finish() {
        continuation.finish()
    }
}
```

**Step 4: Run test to verify it passes**

Run: `SWIFT_BUILD_DIR=".build-agent-fs-git-split" swift test --build-path "$SWIFT_BUILD_DIR" --filter "GitStatusRequestChannelTests"`
Expected: PASS.

**Step 5: Commit**

```bash
git add Sources/AgentStudio/Core/PaneRuntime/Sources/GitStatusRequestChannel.swift Tests/AgentStudioTests/Core/PaneRuntime/Sources/GitStatusRequestChannelTests.swift
git commit -m "feat: add git status request channel contracts"
```

---

### Task 3: Introduce GitStatusActor (Consumer + Fact Producer)

**Files:**
- Create: `Sources/AgentStudio/Core/PaneRuntime/Sources/GitStatusActor.swift`
- Test: `Tests/AgentStudioTests/Core/PaneRuntime/Sources/GitStatusActorTests.swift`

**Step 1: Write failing actor tests**

```swift
import Foundation
import Testing
@testable import AgentStudio

@Suite("GitStatusActor")
struct GitStatusActorTests {
    @Test("emits gitStatusChanged and branchChanged facts from requests")
    func emitsStatusAndBranchFacts() async throws {
        let bus = EventBus<PaneEventEnvelope>()
        let channel = GitStatusRequestChannel(bufferLimit: 8)
        let provider = StubGitStatusProvider { _ in
            GitStatusSnapshot(
                summary: GitStatusSummary(changed: 2, staged: 1, untracked: 0),
                branch: "feature/split"
            )
        }
        let actor = GitStatusActor(bus: bus, requestChannel: channel, gitStatusProvider: provider)
        await actor.start()

        let worktreeId = UUID()
        await channel.yield(.init(worktreeId: worktreeId, rootPath: URL(fileURLWithPath: "/tmp/repo"), triggerBatchSeq: 42))

        let stream = await bus.subscribe()
        var iterator = stream.makeAsyncIterator()

        let first = try #require(await iterator.next())
        let second = try #require(await iterator.next())
        #expect(first.sourceFacets.worktreeId == worktreeId)
        #expect(second.sourceFacets.worktreeId == worktreeId)

        await actor.shutdown()
    }
}
```

**Step 2: Run failing tests**

Run: `SWIFT_BUILD_DIR=".build-agent-fs-git-split" swift test --build-path "$SWIFT_BUILD_DIR" --filter "GitStatusActorTests"`
Expected: FAIL (missing actor).

**Step 3: Write minimal implementation**

```swift
import Foundation
import os

actor GitStatusActor {
    private static let logger = Logger(subsystem: "com.agentstudio", category: "GitStatusActor")

    private let bus: EventBus<PaneEventEnvelope>
    private let requestChannel: GitStatusRequestChannel
    private let gitStatusProvider: any GitStatusProvider
    private let clock = ContinuousClock()

    private var consumeTask: Task<Void, Never>?
    private var lastKnownBranchByWorktree: [UUID: String] = [:]
    private var nextEnvelopeSequence: UInt64 = 0

    init(
        bus: EventBus<PaneEventEnvelope> = PaneRuntimeEventBus.shared,
        requestChannel: GitStatusRequestChannel,
        gitStatusProvider: any GitStatusProvider = ShellGitStatusProvider()
    ) {
        self.bus = bus
        self.requestChannel = requestChannel
        self.gitStatusProvider = gitStatusProvider
    }

    func start() {
        guard consumeTask == nil else { return }
        let streamTask = requestChannel
        consumeTask = Task { [weak self] in
            guard let self else { return }
            let stream = await streamTask.stream()
            for await request in stream {
                await self.handle(request)
            }
        }
    }

    func shutdown() {
        consumeTask?.cancel()
        consumeTask = nil
    }

    private func handle(_ request: GitStatusRequest) async {
        guard let snapshot = await gitStatusProvider.status(for: request.rootPath) else { return }

        await emitFilesystemFact(worktreeId: request.worktreeId, event: .gitStatusChanged(summary: snapshot.summary))

        if let previous = lastKnownBranchByWorktree[request.worktreeId],
           let next = snapshot.branch,
           previous != next {
            await emitFilesystemFact(worktreeId: request.worktreeId, event: .branchChanged(from: previous, to: next))
        }
        lastKnownBranchByWorktree[request.worktreeId] = snapshot.branch
    }

    private func emitFilesystemFact(worktreeId: UUID, event: FilesystemEvent) async {
        nextEnvelopeSequence += 1
        await bus.post(
            PaneEventEnvelope(
                source: .system(.builtin(.filesystemWatcher)),
                sourceFacets: PaneContextFacets(worktreeId: worktreeId),
                paneKind: nil,
                seq: nextEnvelopeSequence,
                commandId: nil,
                correlationId: nil,
                timestamp: clock.now,
                epoch: 0,
                event: .filesystem(event)
            )
        )
    }
}
```

**Step 4: Run tests**

Run: `SWIFT_BUILD_DIR=".build-agent-fs-git-split" swift test --build-path "$SWIFT_BUILD_DIR" --filter "GitStatusActorTests"`
Expected: PASS.

**Step 5: Commit**

```bash
git add Sources/AgentStudio/Core/PaneRuntime/Sources/GitStatusActor.swift Tests/AgentStudioTests/Core/PaneRuntime/Sources/GitStatusActorTests.swift
git commit -m "feat: add GitStatusActor for local git fact production"
```

---

### Task 4: Refactor FilesystemActor to Emit Requests (No Inline Git Compute)

**Files:**
- Modify: `Sources/AgentStudio/Core/PaneRuntime/Sources/FilesystemActor.swift`
- Modify: `Sources/AgentStudio/Core/PaneRuntime/Sources/GitStatusProvider.swift` (remove now-unused test coupling if needed)
- Test: `Tests/AgentStudioTests/Core/PaneRuntime/Sources/FilesystemActorTests.swift`

**Step 1: Write failing tests for split behavior**

```swift
@Test("filesystem actor emits filesChanged facts and yields one git request per flush")
func emitsFilesAndRequestsGitRecompute() async throws {
    let bus = EventBus<PaneEventEnvelope>()
    let requests = GitStatusRequestChannel(bufferLimit: 8)
    let actor = FilesystemActor(bus: bus, gitStatusRequestChannel: requests)

    let worktreeId = UUID()
    await actor.register(worktreeId: worktreeId, rootPath: URL(fileURLWithPath: "/tmp/repo"))

    let busStream = await bus.subscribe()
    var busIterator = busStream.makeAsyncIterator()
    let requestStream = await requests.stream()
    var requestIterator = requestStream.makeAsyncIterator()

    await actor.enqueueRawPaths(worktreeId: worktreeId, paths: ["a.swift"])

    let event = try #require(await busIterator.next())
    let request = try #require(await requestIterator.next())

    #expect(filesChangedChangeset(from: event) != nil)
    #expect(request.worktreeId == worktreeId)

    await actor.shutdown()
}
```

**Step 2: Run failing tests**

Run: `SWIFT_BUILD_DIR=".build-agent-fs-git-split" swift test --build-path "$SWIFT_BUILD_DIR" --filter "FilesystemActorTests"`
Expected: FAIL (still expecting inline git behavior).

**Step 3: Minimal implementation change**

```swift
actor FilesystemActor {
    private let gitStatusRequestChannel: GitStatusRequestChannel

    init(..., gitStatusRequestChannel: GitStatusRequestChannel = GitStatusRequestChannel()) {
        self.gitStatusRequestChannel = gitStatusRequestChannel
    }

    private func flush(worktreeId: UUID) async {
        // existing filesChanged chunk emission

        let latestBatchSeq = root.nextBatchSeq
        await gitStatusRequestChannel.yield(
            GitStatusRequest(
                worktreeId: worktreeId,
                rootPath: root.rootPath,
                triggerBatchSeq: latestBatchSeq
            )
        )
    }
}
```

Remove inline block in `flush()` that awaits `gitStatusProvider.status(...)` and emits git facts.

**Step 4: Run tests**

Run: `SWIFT_BUILD_DIR=".build-agent-fs-git-split" swift test --build-path "$SWIFT_BUILD_DIR" --filter "FilesystemActorTests"`
Expected: PASS with updated assertions.

**Step 5: Commit**

```bash
git add Sources/AgentStudio/Core/PaneRuntime/Sources/FilesystemActor.swift Tests/AgentStudioTests/Core/PaneRuntime/Sources/FilesystemActorTests.swift
git commit -m "refactor: move FilesystemActor to request-based git trigger"
```

---

### Task 5: Add Pipeline Orchestrator and Wire App Default

**Files:**
- Create: `Sources/AgentStudio/Core/PaneRuntime/Sources/FilesystemGitPipeline.swift`
- Modify: `Sources/AgentStudio/App/PaneCoordinator+FilesystemSource.swift`
- Modify: `Sources/AgentStudio/App/PaneCoordinator.swift`
- Test: `Tests/AgentStudioTests/App/PaneCoordinatorTests.swift`

**Step 1: Write failing wiring test**

```swift
@Test("default filesystem source uses split pipeline")
func defaultFilesystemSourceUsesPipeline() {
    let coordinator = PaneCoordinator(
        store: WorkspaceStore(persistor: WorkspacePersistor(workspacesDir: URL(fileURLWithPath: "/tmp/pipeline"))),
        viewRegistry: ViewRegistry(),
        runtime: SessionRuntime(store: WorkspaceStore(persistor: WorkspacePersistor(workspacesDir: URL(fileURLWithPath: "/tmp/pipeline"))))
    )

    #expect(String(describing: type(of: coordinator.filesystemSource)).contains("FilesystemGitPipeline"))
}
```

**Step 2: Run failing test**

Run: `SWIFT_BUILD_DIR=".build-agent-fs-git-split" swift test --build-path "$SWIFT_BUILD_DIR" --filter "PaneCoordinatorTests/defaultFilesystemSourceUsesPipeline"`
Expected: FAIL (default still `FilesystemActor.shared`).

**Step 3: Implement orchestrator + default wiring**

```swift
@MainActor
final class FilesystemGitPipeline: PaneCoordinatorFilesystemSourceManaging {
    static let shared = FilesystemGitPipeline()

    private let requestChannel: GitStatusRequestChannel
    private let filesystemActor: FilesystemActor
    private let gitStatusActor: GitStatusActor

    init(...) {
        requestChannel = GitStatusRequestChannel(bufferLimit: 64)
        filesystemActor = FilesystemActor(..., gitStatusRequestChannel: requestChannel)
        gitStatusActor = GitStatusActor(..., requestChannel: requestChannel)
        Task { await gitStatusActor.start() }
    }

    func register(worktreeId: UUID, rootPath: URL) async { await filesystemActor.register(worktreeId: worktreeId, rootPath: rootPath) }
    func unregister(worktreeId: UUID) async { await filesystemActor.unregister(worktreeId: worktreeId) }
    func setActivity(worktreeId: UUID, isActiveInApp: Bool) async { await filesystemActor.setActivity(worktreeId: worktreeId, isActiveInApp: isActiveInApp) }
    func setActivePaneWorktree(worktreeId: UUID?) async { await filesystemActor.setActivePaneWorktree(worktreeId: worktreeId) }
}
```

Update coordinator default:

```swift
filesystemSource: any PaneCoordinatorFilesystemSourceManaging = FilesystemGitPipeline.shared
```

**Step 4: Run test**

Run: `SWIFT_BUILD_DIR=".build-agent-fs-git-split" swift test --build-path "$SWIFT_BUILD_DIR" --filter "PaneCoordinatorTests/defaultFilesystemSourceUsesPipeline"`
Expected: PASS.

**Step 5: Commit**

```bash
git add Sources/AgentStudio/Core/PaneRuntime/Sources/FilesystemGitPipeline.swift Sources/AgentStudio/App/PaneCoordinator.swift Sources/AgentStudio/App/PaneCoordinator+FilesystemSource.swift Tests/AgentStudioTests/App/PaneCoordinatorTests.swift
git commit -m "feat: wire split filesystem-git pipeline as default coordinator source"
```

---

### Task 6: Add Coalescing + Backpressure Tests for GitStatusActor

**Files:**
- Modify: `Sources/AgentStudio/Core/PaneRuntime/Sources/GitStatusActor.swift`
- Modify: `Tests/AgentStudioTests/Core/PaneRuntime/Sources/GitStatusActorTests.swift`

**Step 1: Write failing coalescing test**

```swift
@Test("coalesces repeated requests for same worktree while compute in flight")
func coalescesRepeatedRequests() async throws {
    let bus = EventBus<PaneEventEnvelope>()
    let channel = GitStatusRequestChannel(bufferLimit: 2)
    let callCount = LockedCounter()
    let provider = StubGitStatusProvider { _ in
        await callCount.increment()
        try? await Task.sleep(for: .milliseconds(60))
        return GitStatusSnapshot(summary: .init(changed: 1, staged: 0, untracked: 0), branch: "main")
    }

    let actor = GitStatusActor(bus: bus, requestChannel: channel, gitStatusProvider: provider)
    await actor.start()

    let worktreeId = UUID()
    let root = URL(fileURLWithPath: "/tmp/repo")
    await channel.yield(.init(worktreeId: worktreeId, rootPath: root, triggerBatchSeq: 1))
    await channel.yield(.init(worktreeId: worktreeId, rootPath: root, triggerBatchSeq: 2))
    await channel.yield(.init(worktreeId: worktreeId, rootPath: root, triggerBatchSeq: 3))

    try? await Task.sleep(for: .milliseconds(250))
    #expect(await callCount.value <= 2)

    await actor.shutdown()
}
```

**Step 2: Run failing test**

Run: `SWIFT_BUILD_DIR=".build-agent-fs-git-split" swift test --build-path "$SWIFT_BUILD_DIR" --filter "GitStatusActorTests/coalescesRepeatedRequests"`
Expected: FAIL until coalescing exists.

**Step 3: Minimal coalescing implementation**

```swift
private var inFlightWorktrees: Set<UUID> = []
private var deferredLatestRequestByWorktree: [UUID: GitStatusRequest] = [:]

private func handle(_ request: GitStatusRequest) async {
    if inFlightWorktrees.contains(request.worktreeId) {
        deferredLatestRequestByWorktree[request.worktreeId] = request
        return
    }

    inFlightWorktrees.insert(request.worktreeId)
    defer {
        inFlightWorktrees.remove(request.worktreeId)
    }

    await computeAndEmit(for: request)

    if let deferred = deferredLatestRequestByWorktree.removeValue(forKey: request.worktreeId) {
        await computeAndEmit(for: deferred)
    }
}
```

**Step 4: Run tests**

Run: `SWIFT_BUILD_DIR=".build-agent-fs-git-split" swift test --build-path "$SWIFT_BUILD_DIR" --filter "GitStatusActorTests"`
Expected: PASS.

**Step 5: Commit**

```bash
git add Sources/AgentStudio/Core/PaneRuntime/Sources/GitStatusActor.swift Tests/AgentStudioTests/Core/PaneRuntime/Sources/GitStatusActorTests.swift
git commit -m "feat: add per-worktree git request coalescing"
```

---

### Task 7: Integration Test the Split Pipeline with Stores

**Files:**
- Create: `Tests/AgentStudioTests/Core/PaneRuntime/Sources/FilesystemGitPipelineIntegrationTests.swift`
- Modify: `Tests/AgentStudioTests/Features/Sidebar/RepoSidebarContentViewTests.swift`

**Step 1: Write failing integration test**

```swift
@Test("split pipeline updates projection and workspace git stores via same bus")
@MainActor
func splitPipelineUpdatesBothStores() async throws {
    let bus = EventBus<PaneEventEnvelope>()
    let channel = GitStatusRequestChannel(bufferLimit: 8)
    let filesystem = FilesystemActor(bus: bus, gitStatusRequestChannel: channel)
    let git = GitStatusActor(
        bus: bus,
        requestChannel: channel,
        gitStatusProvider: .stub { _ in
            GitStatusSnapshot(summary: .init(changed: 3, staged: 1, untracked: 2), branch: "feature/x")
        }
    )
    await git.start()

    let projection = PaneFilesystemProjectionStore()
    let workspaceGit = WorkspaceGitStatusStore()

    // consume bus and fan into stores (same as coordinator behavior)
    let stream = await bus.subscribe()
    let worktreeId = UUID()
    let paneId = UUID()

    await filesystem.register(worktreeId: worktreeId, rootPath: URL(fileURLWithPath: "/tmp/repo"))
    await filesystem.enqueueRawPaths(worktreeId: worktreeId, paths: ["Sources/File.swift"])

    // assert both stores receive appropriate facts
}
```

**Step 2: Run failing integration test**

Run: `SWIFT_BUILD_DIR=".build-agent-fs-git-split" swift test --build-path "$SWIFT_BUILD_DIR" --filter "FilesystemGitPipelineIntegrationTests"`
Expected: FAIL until pipeline fully wired.

**Step 3: Implement minimal integration harness + assertions**

Use eventual polling with bounded attempts; assert:
- projection snapshot contains changed file path,
- workspace git snapshot has summary + branch.

**Step 4: Run tests**

Run: `SWIFT_BUILD_DIR=".build-agent-fs-git-split" swift test --build-path "$SWIFT_BUILD_DIR" --filter "FilesystemGitPipelineIntegrationTests"`
Expected: PASS.

**Step 5: Commit**

```bash
git add Tests/AgentStudioTests/Core/PaneRuntime/Sources/FilesystemGitPipelineIntegrationTests.swift Tests/AgentStudioTests/Features/Sidebar/RepoSidebarContentViewTests.swift
git commit -m "test: add split filesystem-git pipeline integration coverage"
```

---

### Task 8: E2E with Real tmp Git Repo Through Split Pipeline

**Files:**
- Modify: `Tests/AgentStudioTests/Integration/FilesystemSourceE2ETests.swift`
- Modify: `Tests/AgentStudioTests/Helpers/FilesystemTestGitRepo.swift`

**Step 1: Write failing E2E assertion for split producers**

```swift
@Test("split pipeline emits files and local git facts from tmp repo")
func splitPipelineE2E() async throws {
    // create tmp repo under tmp/filesystem-git-tests
    // seed tracked + untracked changes
    // run FilesystemActor + GitStatusActor on shared bus
    // assert filesChanged + gitStatusChanged both observed
}
```

**Step 2: Run failing E2E test**

Run: `SWIFT_BUILD_DIR=".build-agent-fs-git-split" swift test --build-path "$SWIFT_BUILD_DIR" --filter "E2ESerializedTests/FilesystemSourceE2ETests"`
Expected: FAIL until test updated for split.

**Step 3: Implement minimal E2E updates**

- Reuse `FilesystemTestGitRepo` helper.
- Ensure cleanup only touches `tmp/filesystem-git-tests`.
- Assert sidebar-facing store state after event propagation.

**Step 4: Run E2E + integration tests**

Run: `SWIFT_BUILD_DIR=".build-agent-fs-git-split" swift test --build-path "$SWIFT_BUILD_DIR" --filter "E2ESerializedTests/FilesystemSourceE2ETests"`
Expected: PASS.

**Step 5: Commit**

```bash
git add Tests/AgentStudioTests/Integration/FilesystemSourceE2ETests.swift Tests/AgentStudioTests/Helpers/FilesystemTestGitRepo.swift
git commit -m "test: validate split fs-git actor pipeline with tmp git e2e"
```

---

### Task 9: Verification + Final Spec Sync

**Files:**
- Modify: `docs/plans/2026-02-27-luna-349-test-value-plan.md`
- Modify: `docs/plans/2026-02-28-luna-349-filesystem-git-actor-split.md` (this plan, task checklist updates)

**Step 1: Add final checklist entries**

```markdown
- [x] FilesystemActor is fact source + command trigger only.
- [x] GitStatusActor is local git fact source.
- [x] Stores/Sidebar consume unchanged fact envelopes from EventBus.
- [x] Unit + integration + E2E tests pass for split pipeline.
```

**Step 2: Run format/lint/test gates**

Run: `mise run format`
Expected: PASS.

Run: `mise run lint`
Expected: PASS (0 violations).

Run: `SWIFT_BUILD_DIR=".build-agent-fs-git-split" mise run test`
Expected: PASS (default suite + WebKit serialized).

Run: `SWIFT_BUILD_DIR=".build-agent-fs-git-split" mise run test-e2e`
Expected: PASS (`E2ESerializedTests`, including filesystem split E2E).

**Step 3: Capture targeted evidence**

Run:
- `SWIFT_BUILD_DIR=".build-agent-fs-git-split" swift test --build-path "$SWIFT_BUILD_DIR" --filter "FilesystemActorTests"`
- `SWIFT_BUILD_DIR=".build-agent-fs-git-split" swift test --build-path "$SWIFT_BUILD_DIR" --filter "GitStatusActorTests"`
- `SWIFT_BUILD_DIR=".build-agent-fs-git-split" swift test --build-path "$SWIFT_BUILD_DIR" --filter "FilesystemGitPipelineIntegrationTests"`

Expected: PASS for all targeted suites.

**Step 4: Commit verification/docs**

```bash
git add docs/plans/2026-02-27-luna-349-test-value-plan.md docs/plans/2026-02-28-luna-349-filesystem-git-actor-split.md
git commit -m "docs: finalize split pipeline verification and test plan"
```

---

## Design Notes to Preserve During Execution

- Keep `PaneCoordinator.handleFilesystemEnvelopeIfNeeded` unchanged for consumer stability.
- Keep payload schema unchanged (`FilesystemEvent` remains source-compatible).
- If `AsyncStream` watermark APIs are unavailable in current toolchain, use bounded buffering (`.bufferingNewest`) + explicit per-worktree coalescing inside `GitStatusActor`.
- `GitStatusActor` must surface failure as structured facts (follow-up improvement if current contract lacks explicit error event for git failures).

