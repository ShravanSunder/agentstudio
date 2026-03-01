# LUNA-349 Non-Terminal Runtimes + Filesystem Funnel Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Implement `BridgeRuntime`, `WebviewRuntime`, `SwiftPaneRuntime`, and an app-wide filesystem event source that funnels all filesystem events through `EventBus` with pane-scoped projection filters by `paneId` + `worktreeId` + `cwd`.

**Architecture:** Keep D5 layering strict: View renders, Controller owns transport, Runtime owns `PaneRuntime` contract, and boundary actors own expensive off-MainActor work. Filesystem observation is one app-wide source keyed by worktree; pane-aware filtering is a derived projection (`Contract 16` pattern), not a second watcher. Non-terminal runtimes must become first-class `PaneRuntime` conformers and register in `RuntimeRegistry` exactly like `TerminalRuntime`.

**Tech Stack:** Swift 6.2, Swift Testing (`import Testing`), AsyncStream/EventBus, AppKit/WebKit, macOS FSEvents API, `ProcessExecutor`, `mise` (`format`, `lint`, `test`).

---

## Guardrails

- Work in this dedicated worktree/branch only (`luna-349-non-terminal-paneruntime-conformers-fsevents-watcher-system`).
- Use `@superpowers:test-driven-development` and keep every task test-first.
- Use `@superpowers:verification-before-completion` before claiming done.
- Keep EventBus as a dumb fan-out pipe: no filtering or domain logic inside `EventBus`.
- Do not add compatibility shims. Hard-cut to new runtime types and filesystem source path.
- Sidebar must not perform direct filesystem/git discovery loops on the main actor.
- Sidebar consumes centralized state/events from runtime sources (`FilesystemActor` + projection stores), not ad-hoc scanners.

---

## Swift 6.2 Concurrency Gates (Imperative)

- Keep all runtime state mutation (`metadata`, `lifecycle`, replay buffer writes, `@Observable` writes) on `@MainActor`.
- Boundary work (`FilesystemActor` debounce + git status/diff compute) stays off MainActor.
- Use explicit function isolation spellings for behavior-critical helpers:
  - `nonisolated(nonsending) async` when the function must run on caller isolation.
  - `@concurrent nonisolated async` when the function must always switch off actor isolation.
  - Avoid bare `nonisolated async` in new critical paths because semantics vary by language mode/feature flag.
- `@concurrent` can only appear on (implicitly or explicitly) `nonisolated` declarations.
  - Never combine `@concurrent` with global actor isolation (for example `@MainActor`) or with `isolated` parameters.
- Heavy helper functions for filesystem/git work should default to `@concurrent nonisolated static`.
- New streams use `AsyncStream.makeStream(of:)` and set termination cleanup paths.
- Every long-lived stream/task must be canceled and continuation finished on teardown/deinit.
- No new `DispatchQueue.main.async` and no `MainActor.assumeIsolated`.
- Protocol isolation must be explicit: only mark values `Sendable` when they cross actor boundaries.
- `isolated` parameter semantics:
  - `isolated SomeActor` means function executes with that actor isolation.
  - Optional `isolated (any Actor)?` can represent dynamic isolation (`nil` behaves as non-isolated).
  - Use only when polymorphic actor inheritance is required; do not mix with `@concurrent`.
- Unstructured task caveat: `Task {}` created in nonisolated contexts does not automatically run on the caller actor. Be explicit about actor hops and captures.

Verification gate for each task touching concurrency:
- Add at least one actor-isolation test assertion.
- Run a focused test for cancellation/termination behavior.
- Add one negative test that proves non-`Sendable` captures are rejected when crossing isolation boundaries in `@concurrent` paths.

Primary references:
- SE-0461 (implemented Swift 6.2): <https://github.com/swiftlang/swift-evolution/blob/main/proposals/0461-async-function-isolation.md>
- SE-0420 (isolated parameter inheritance): <https://github.com/swiftlang/swift-evolution/blob/main/proposals/0420-inheritance-of-actor-isolation.md>
- Swift compiler userdocs (feature behavior note): <https://github.com/swiftlang/swift/blob/main/userdocs/diagnostics/nonisolated-nonsending-by-default.md>

---

## Filesystem Data Contract (Rich + Ingestion-Safe)

- Pane scoping for projections is `cwd`-first:
  - match watcher `worktreeId`
  - then filter changed paths to the pane `cwd` subtree
  - if `cwd` is nil, treat as worktree-root scope
- Source envelopes should include high-value routing/context fields (`worktreeId`, `rootPath`, `batchSeq`, timestamps, branch/git summary) without sending heavyweight blobs.
- Keep per-event payloads bounded:
  - paths are relative to worktree root
  - deduped path sets only
  - no inline patch/diff blobs in `filesChanged` or `gitStatusChanged`
- Ingestion safety rules:
  - fixed max batch size (split large bursts)
  - deterministic ordering for emitted paths
  - UTF-8 safe normalization + drop invalid/unreadable path entries
  - include lightweight counts for observability (`changed`, `staged`, `untracked`) instead of raw command output
- Sidebar contract:
  - UI reads precomputed local-git summaries from centralized stores.
  - no per-render `git` CLI fan-out in sidebar view lifecycle.
  - no direct repo/worktree discovery loops from sidebar view code.

---

## Locked V1 Decisions (2026-02-27)

- Single app-wide filesystem source:
  - one `FilesystemActor` singleton
  - one event ingress path for filesystem changes
  - no per-pane/per-sidebar filesystem subscriptions
- Nested folder ownership (no duplicate delivery):
  - track all registered roots
  - route changed path to deepest matching root
  - emit one logical event per changed path per batch
  - v1 does not include git submodule-specific behavior
- Local vs remote ownership:
  - local filesystem + local git status summaries belong to `FilesystemActor`
  - remote PR/check/provider data belongs to `ForgeActor` (separate ticket)
- Priority is intentionally simple for v1:
  - `active-in-app`: root has at least one pane/session in app
  - `sidebar-only`: root tracked in workspace but no pane/session
  - active pane root gets queue precedence within `active-in-app`
- Update model:
  - push-first: FSEvents is primary update trigger
  - pull is bounded reconciliation only (wake/reconnect, overflow recovery, low-frequency drift sweep)

---

### Task 1: Freeze Filesystem Envelope Contract (Source Identity + Facets)

**Files:**
- Modify: `docs/architecture/pane_runtime_architecture.md`
- Modify: `docs/architecture/pane_runtime_eventbus_design.md`
- Modify: `Sources/AgentStudio/Core/PaneRuntime/Contracts/PaneRuntimeEvent.swift`
- Test: `Tests/AgentStudioTests/Core/PaneRuntime/Contracts/PaneRuntimeContractsTests.swift`

**Step 1: Write the failing test**

```swift
@Test("filesystem source identity is system builtin watcher with worktree in facets")
func filesystemSourceIdentityContract() {
    let worktreeId = UUID()
    let envelope = PaneEventEnvelope(
        source: .system(.builtin(.filesystemWatcher)),
        sourceFacets: PaneContextFacets(worktreeId: worktreeId),
        paneKind: nil,
        seq: 1,
        commandId: nil,
        correlationId: nil,
        timestamp: ContinuousClock().now,
        epoch: 0,
        event: .filesystem(
            .filesChanged(
                changeset: FileChangeset(
                    worktreeId: worktreeId,
                    paths: ["README.md"],
                    timestamp: ContinuousClock().now,
                    batchSeq: 1
                )
            )
        )
    )

    #expect(envelope.source == .system(.builtin(.filesystemWatcher)))
    #expect(envelope.sourceFacets.worktreeId == worktreeId)
}
```

**Step 2: Run test to verify it fails**

Run: `SWIFT_BUILD_DIR=".build-agent-l349" swift test --build-path "$SWIFT_BUILD_DIR" --filter "PaneRuntimeContractsTests/filesystemSourceIdentityContract"`
Expected: FAIL because contract test does not exist yet.

**Step 3: Write minimal implementation**

```swift
// PaneRuntimeContractsTests.swift
@Test("filesystem source identity is system builtin watcher with worktree in facets")
func filesystemSourceIdentityContract() { ... }
```

Doc change:
- Remove/replace stale wording that says filesystem source envelope uses `.worktree(id)`.
- Make both docs consistent with:
  - `source = .system(.builtin(.filesystemWatcher))`
  - `sourceFacets.worktreeId = <watcher worktree>`
  - `FileChangeset.worktreeId` remains denormalized domain copy.

**Step 4: Run test to verify it passes**

Run: `SWIFT_BUILD_DIR=".build-agent-l349" swift test --build-path "$SWIFT_BUILD_DIR" --filter "PaneRuntimeContractsTests/filesystemSourceIdentityContract"`
Expected: PASS.

Run: `rg -n "source = \\.worktree\\(id\\)" docs/architecture/pane_runtime_architecture.md`
Expected: no match for filesystem source contract wording.

**Step 5: Commit**

```bash
git add docs/architecture/pane_runtime_architecture.md docs/architecture/pane_runtime_eventbus_design.md Sources/AgentStudio/Core/PaneRuntime/Contracts/PaneRuntimeEvent.swift Tests/AgentStudioTests/Core/PaneRuntime/Contracts/PaneRuntimeContractsTests.swift
git commit -m "docs/contracts: freeze filesystem source identity to system builtin watcher"
```

---

### Task 2: Extract `BridgeRuntime` from `BridgePaneController`

**Files:**
- Create: `Sources/AgentStudio/Features/Bridge/Runtime/BridgeRuntime.swift`
- Modify: `Sources/AgentStudio/Features/Bridge/Runtime/BridgePaneController.swift`
- Modify: `Sources/AgentStudio/Features/Bridge/Views/BridgePaneView.swift`
- Test: `Tests/AgentStudioTests/Features/Bridge/Runtime/BridgeRuntimeTests.swift`

**Step 1: Write the failing test**

```swift
@MainActor
@Test("bridge runtime posts diff events to EventBus and replay")
func bridgeRuntimePostsEvents() async {
    let bus = EventBus<PaneEventEnvelope>()
    let runtime = BridgeRuntime(
        paneId: PaneId(),
        metadata: PaneMetadata(source: .floating(workingDirectory: nil, title: "Diff"), contentType: .diff),
        controller: .testDouble(),
        paneEventBus: bus
    )
    runtime.transitionToReady()
    runtime.ingestBridgeEvent(.diff(.diffLoaded(stats: DiffStats(filesChanged: 1, insertions: 2, deletions: 0))))

    let replay = await runtime.eventsSince(seq: 0)
    #expect(replay.events.count == 1)
}
```

**Step 2: Run test to verify it fails**

Run: `SWIFT_BUILD_DIR=".build-agent-l349" swift test --build-path "$SWIFT_BUILD_DIR" --filter "BridgeRuntimeTests/bridgeRuntimePostsEvents"`
Expected: FAIL with missing `BridgeRuntime`.

**Step 3: Write minimal implementation**

```swift
@MainActor
@Observable
final class BridgeRuntime: BusPostingPaneRuntime {
    let paneId: PaneId
    private(set) var metadata: PaneMetadata
    private(set) var lifecycle: PaneRuntimeLifecycle = .created
    let capabilities: Set<PaneCapability>

    func handleCommand(_ envelope: RuntimeCommandEnvelope) async -> ActionResult { ... }
    func subscribe() -> AsyncStream<PaneEventEnvelope> { ... }
    func snapshot() -> PaneRuntimeSnapshot { ... }
    func eventsSince(seq: UInt64) async -> EventReplayBuffer.ReplayResult { ... }
    func shutdown(timeout: Duration) async -> [UUID] { ... }

    func ingestBridgeEvent(_ event: PaneRuntimeEvent, commandId: UUID? = nil, correlationId: UUID? = nil) { ... }
}
```

Controller changes:
- Add typed callbacks for runtime-facing events/acks.
- Keep WebKit/RPC ownership in controller.
- Remove runtime-owned lifecycle/event sequencing logic from controller.

**Step 4: Run test to verify it passes**

Run: `SWIFT_BUILD_DIR=".build-agent-l349" swift test --build-path "$SWIFT_BUILD_DIR" --filter "BridgeRuntimeTests"`
Expected: PASS.

Run: `SWIFT_BUILD_DIR=".build-agent-l349" swift test --build-path "$SWIFT_BUILD_DIR" --filter "BridgePaneControllerTests"`
Expected: PASS (controller behavior preserved).

**Step 5: Commit**

```bash
git add Sources/AgentStudio/Features/Bridge/Runtime/BridgeRuntime.swift Sources/AgentStudio/Features/Bridge/Runtime/BridgePaneController.swift Sources/AgentStudio/Features/Bridge/Views/BridgePaneView.swift Tests/AgentStudioTests/Features/Bridge/Runtime/BridgeRuntimeTests.swift
git commit -m "feat: extract BridgeRuntime as PaneRuntime conformer"
```

---

### Task 3: Extract `WebviewRuntime` and Typed Browser Event Emission

**Files:**
- Create: `Sources/AgentStudio/Features/Webview/Runtime/WebviewRuntime.swift`
- Modify: `Sources/AgentStudio/Features/Webview/WebviewPaneController.swift`
- Modify: `Sources/AgentStudio/Features/Webview/Views/WebviewPaneView.swift`
- Test: `Tests/AgentStudioTests/Features/Webview/Runtime/WebviewRuntimeTests.swift`
- Test: `Tests/AgentStudioTests/Features/Webview/WebviewPaneControllerTests.swift`

**Step 1: Write the failing test**

```swift
@MainActor
@Test("webview runtime maps browser commands and emits navigation events")
func webviewRuntimeNavigationFlow() async {
    let runtime = WebviewRuntime(
        paneId: PaneId(),
        metadata: PaneMetadata(source: .floating(workingDirectory: nil, title: "Browser"), contentType: .browser),
        controller: .testDouble()
    )
    runtime.transitionToReady()
    _ = await runtime.handleCommand(.init(commandId: UUID(), correlationId: nil, targetPaneId: runtime.paneId, command: .browser(.reload(hard: false)), timestamp: ContinuousClock().now))
    runtime.ingestBrowserEvent(.pageLoaded(url: URL(string: "https://example.com")!))
    let replay = await runtime.eventsSince(seq: 0)
    #expect(replay.events.count == 1)
}
```

**Step 2: Run test to verify it fails**

Run: `SWIFT_BUILD_DIR=".build-agent-l349" swift test --build-path "$SWIFT_BUILD_DIR" --filter "WebviewRuntimeTests/webviewRuntimeNavigationFlow"`
Expected: FAIL with missing `WebviewRuntime`.

**Step 3: Write minimal implementation**

```swift
@MainActor
@Observable
final class WebviewRuntime: BusPostingPaneRuntime {
    // PaneRuntime surface + replay buffer + bus post logic
    func ingestBrowserEvent(_ event: BrowserEvent, commandId: UUID? = nil, correlationId: UUID? = nil) { ... }
}
```

Controller changes:
- Expose callback(s): `onBrowserEvent: ((BrowserEvent) -> Void)?`.
- Emit `.navigationCompleted` / `.pageLoaded` from navigation lifecycle points.

**Step 4: Run test to verify it passes**

Run: `SWIFT_BUILD_DIR=".build-agent-l349" swift test --build-path "$SWIFT_BUILD_DIR" --filter "WebviewRuntimeTests"`
Expected: PASS.

Run: `SWIFT_BUILD_DIR=".build-agent-l349" swift test --build-path "$SWIFT_BUILD_DIR" --filter "WebviewPaneControllerTests"`
Expected: PASS.

**Step 5: Commit**

```bash
git add Sources/AgentStudio/Features/Webview/Runtime/WebviewRuntime.swift Sources/AgentStudio/Features/Webview/WebviewPaneController.swift Sources/AgentStudio/Features/Webview/Views/WebviewPaneView.swift Tests/AgentStudioTests/Features/Webview/Runtime/WebviewRuntimeTests.swift Tests/AgentStudioTests/Features/Webview/WebviewPaneControllerTests.swift
git commit -m "feat: add WebviewRuntime and browser event runtime bridge"
```

---

### Task 4: Add `SwiftPaneRuntime` and Real Code Viewer Surface

**Files:**
- Create: `Sources/AgentStudio/Core/PaneRuntime/Runtime/SwiftPaneRuntime.swift`
- Modify: `Sources/AgentStudio/Core/Views/CodeViewerPaneView.swift`
- Test: `Tests/AgentStudioTests/Core/PaneRuntime/Runtime/SwiftPaneRuntimeTests.swift`
- Test: `Tests/AgentStudioTests/Core/Views/CodeViewerPaneViewTests.swift`

**Step 1: Write the failing test**

```swift
@MainActor
@Test("swift pane runtime openFile loads content and emits fileOpened")
func swiftRuntimeOpenFile() async throws {
    let fileURL = FileManager.default.temporaryDirectory.appending(path: "l349-codeviewer.swift")
    try "print(\"hi\")\n".write(to: fileURL, atomically: true, encoding: .utf8)

    let runtime = SwiftPaneRuntime(
        paneId: PaneId(),
        metadata: PaneMetadata(source: .floating(workingDirectory: fileURL.deletingLastPathComponent(), title: "Code"), contentType: .codeViewer)
    )
    runtime.transitionToReady()
    let result = await runtime.handleCommand(
        RuntimeCommandEnvelope(
            commandId: UUID(),
            correlationId: nil,
            targetPaneId: runtime.paneId,
            command: .editor(.openFile(path: fileURL.path, line: 1, column: nil)),
            timestamp: ContinuousClock().now
        )
    )
    #expect(result.isSuccess)
}
```

**Step 2: Run test to verify it fails**

Run: `SWIFT_BUILD_DIR=".build-agent-l349" swift test --build-path "$SWIFT_BUILD_DIR" --filter "SwiftPaneRuntimeTests/swiftRuntimeOpenFile"`
Expected: FAIL with missing `SwiftPaneRuntime`.

**Step 3: Write minimal implementation**

```swift
@MainActor
@Observable
final class SwiftPaneRuntime: BusPostingPaneRuntime {
    private(set) var displayedText: String = ""
    private(set) var openedFilePath: String?
    // Handle .editor(.openFile/.save/.revert) minimally for read-only viewer.
}
```

Code viewer changes:
- Replace placeholder label-only UI with `NSScrollView + NSTextView`.
- Load file contents via runtime output.
- Keep read-only mode.

**Step 4: Run test to verify it passes**

Run: `SWIFT_BUILD_DIR=".build-agent-l349" swift test --build-path "$SWIFT_BUILD_DIR" --filter "SwiftPaneRuntimeTests"`
Expected: PASS.

Run: `SWIFT_BUILD_DIR=".build-agent-l349" swift test --build-path "$SWIFT_BUILD_DIR" --filter "CodeViewerPaneViewTests"`
Expected: PASS.

**Step 5: Commit**

```bash
git add Sources/AgentStudio/Core/PaneRuntime/Runtime/SwiftPaneRuntime.swift Sources/AgentStudio/Core/Views/CodeViewerPaneView.swift Tests/AgentStudioTests/Core/PaneRuntime/Runtime/SwiftPaneRuntimeTests.swift Tests/AgentStudioTests/Core/Views/CodeViewerPaneViewTests.swift
git commit -m "feat: add SwiftPaneRuntime and real NSTextView code viewer"
```

---

### Task 5: Register All Non-Terminal Runtimes in `PaneCoordinator`

**Files:**
- Modify: `Sources/AgentStudio/App/PaneCoordinator+ViewLifecycle.swift`
- Modify: `Sources/AgentStudio/App/PaneCoordinator.swift`
- Test: `Tests/AgentStudioTests/App/PaneCoordinatorRuntimeDispatchTests.swift`
- Test: `Tests/AgentStudioTests/App/PaneCoordinatorTests.swift`

**Step 1: Write the failing test**

```swift
@MainActor
@Test("createViewForContent registers runtime for bridge/webview/codeViewer panes")
func registersNonTerminalRuntimes() {
    // Arrange pane per content type, call createViewForContent
    // Assert runtimeRegistry.runtime(for:) != nil for each paneId
}
```

**Step 2: Run test to verify it fails**

Run: `SWIFT_BUILD_DIR=".build-agent-l349" swift test --build-path "$SWIFT_BUILD_DIR" --filter "PaneCoordinatorTests/registersNonTerminalRuntimes"`
Expected: FAIL (runtime registry currently only receives terminal runtime).

**Step 3: Write minimal implementation**

```swift
private func registerRuntimeIfNeeded(for pane: Pane, bridgeController: BridgePaneController? = nil, webviewController: WebviewPaneController? = nil) {
    switch pane.content {
    case .terminal: ...
    case .bridgePanel: registerRuntime(BridgeRuntime(...))
    case .webview: registerRuntime(WebviewRuntime(...))
    case .codeViewer: registerRuntime(SwiftPaneRuntime(...))
    case .unsupported: break
    }
}
```

Teardown updates:
- Ensure `unregisterRuntime` always runs for non-terminal panes too.
- Ensure controller `teardown()` still runs first for bridge panes.

**Step 4: Run test to verify it passes**

Run: `SWIFT_BUILD_DIR=".build-agent-l349" swift test --build-path "$SWIFT_BUILD_DIR" --filter "PaneCoordinatorTests/registersNonTerminalRuntimes"`
Expected: PASS.

Run: `SWIFT_BUILD_DIR=".build-agent-l349" swift test --build-path "$SWIFT_BUILD_DIR" --filter "PaneCoordinatorRuntimeDispatchTests"`
Expected: PASS.

**Step 5: Commit**

```bash
git add Sources/AgentStudio/App/PaneCoordinator+ViewLifecycle.swift Sources/AgentStudio/App/PaneCoordinator.swift Tests/AgentStudioTests/App/PaneCoordinatorRuntimeDispatchTests.swift Tests/AgentStudioTests/App/PaneCoordinatorTests.swift
git commit -m "feat: register bridge/webview/swift runtimes in pane coordinator lifecycle"
```

---

### Task 6: Implement App-Wide `FilesystemActor` (Single Ingress + Nested Ownership + Local Git)

**Files:**
- Create: `Sources/AgentStudio/Core/PaneRuntime/Sources/FilesystemActor.swift`
- Create: `Sources/AgentStudio/Core/PaneRuntime/Sources/FSEventStreamClient.swift`
- Create: `Sources/AgentStudio/Core/PaneRuntime/Sources/GitStatusProvider.swift`
- Create: `Sources/AgentStudio/Core/PaneRuntime/Sources/FilesystemRootOwnership.swift`
- Modify: `Sources/AgentStudio/Core/PaneRuntime/Contracts/PaneRuntimeEvent.swift`
- Test: `Tests/AgentStudioTests/Core/PaneRuntime/Sources/FilesystemActorTests.swift`

**Step 1: Write the failing test**

```swift
@Test("filesystem actor uses deepest-root ownership and emits one batch per changed path")
func deepestOwnershipDedupesNestedRoots() async {
    let bus = EventBus<PaneEventEnvelope>()
    let clock = TestClock()
    let actor = FilesystemActor(bus: bus, clock: clock, gitStatusProvider: .stub())
    let parentId = UUID()
    let childId = UUID()
    await actor.register(worktreeId: parentId, rootPath: URL(fileURLWithPath: "/tmp/repo"))
    await actor.register(worktreeId: childId, rootPath: URL(fileURLWithPath: "/tmp/repo/nested"))
    await actor.enqueueRawPaths(worktreeId: parentId, paths: ["nested/file.swift", "nested/file.swift"])
    await clock.advance(by: .milliseconds(500))
    // assert event routes to childId ownership and emits one logical path
}

@Test("filesystem actor prioritizes active-in-app roots before sidebar-only roots")
func activeInAppPriorityWinsQueueOrder() async {
    // register two roots, mark one active-in-app, enqueue both, assert active root flushes first
}
```

**Step 2: Run test to verify it fails**

Run: `SWIFT_BUILD_DIR=".build-agent-l349" swift test --build-path "$SWIFT_BUILD_DIR" --filter "FilesystemActorTests/deepestOwnershipDedupesNestedRoots"`
Expected: FAIL with missing ownership routing.

Run: `SWIFT_BUILD_DIR=".build-agent-l349" swift test --build-path "$SWIFT_BUILD_DIR" --filter "FilesystemActorTests/activeInAppPriorityWinsQueueOrder"`
Expected: FAIL with missing actor/files.

**Step 3: Write minimal implementation**

```swift
actor FilesystemActor {
    func register(worktreeId: UUID, rootPath: URL) async { ... }
    func unregister(worktreeId: UUID) async { ... }
    func enqueueRawPaths(worktreeId: UUID, paths: [String]) async { ... } // test seam
    func setActivity(worktreeId: UUID, isActiveInApp: Bool) async { ... }
    func setActivePaneWorktree(worktreeId: UUID?) async { ... }
    // 500ms debounce + 2s max-latency flush + sequential per-root local git status
}
```

Concurrency requirements for this task:
- Git status/diff helpers are `@concurrent nonisolated static`.
- FSEvents callback bridge captures stable values synchronously before async hops.
- No blocking process execution on MainActor.
- All per-worktree flush tasks are canceled during unregister/shutdown.

Ingress and ownership requirements:
- exactly one filesystem ingress path inside `FilesystemActor` for tracked roots.
- no duplicate per-pane/per-sidebar filesystem subscriptions.
- path routing uses deepest matching canonical root ownership.
- root registration must support `.git` directory and `.git` file indirection patterns.
- path canonicalization is required before ownership lookup (symlink + case normalization).

Push/pull requirements:
- push-first for normal updates (`filesChanged`, `gitStatusChanged`, `branchChanged`).
- bounded pull reconciliation only for:
  - wake/reconnect
  - overflow recovery
  - low-frequency drift sweep

Required invariants:
- `owningRoot(path)` is total and non-overlapping within tracked roots.
- per-root event ordering is causal by `(batchSeq, seq)`; cross-root ordering is undefined.
- root registration updates are atomic relative to batch routing.
- pull reconciliation is idempotent and delta-based.
- activity tier changes apply only to future scheduling; in-flight recompute is not dropped.

Envelope emission contract:
- `source: .system(.builtin(.filesystemWatcher))`
- `sourceFacets.worktreeId = worktreeId`
- `event: .filesystem(.filesChanged(...))`
- follow-up `.gitStatusChanged(...)` (and `.branchChanged` when changed).
- `filesChanged` payload is lightweight + bounded (relative deduped paths, no raw diff blobs).

**Step 4: Run test to verify it passes**

Run: `SWIFT_BUILD_DIR=".build-agent-l349" swift test --build-path "$SWIFT_BUILD_DIR" --filter "FilesystemActorTests"`
Expected: PASS.

**Step 5: Commit**

```bash
git add Sources/AgentStudio/Core/PaneRuntime/Sources/FilesystemActor.swift Sources/AgentStudio/Core/PaneRuntime/Sources/FSEventStreamClient.swift Sources/AgentStudio/Core/PaneRuntime/Sources/GitStatusProvider.swift Sources/AgentStudio/Core/PaneRuntime/Contracts/PaneRuntimeEvent.swift Tests/AgentStudioTests/Core/PaneRuntime/Sources/FilesystemActorTests.swift
git commit -m "feat: add app-wide FilesystemActor with debounced worktree batching"
```

---

### Task 7: Wire FilesystemActor Lifecycle + Activity Priority from Workspace State

**Files:**
- Create: `Sources/AgentStudio/App/PaneCoordinator+FilesystemSource.swift`
- Modify: `Sources/AgentStudio/App/PaneCoordinator.swift`
- Modify: `Sources/AgentStudio/Core/Stores/WorkspaceStore.swift`
- Test: `Tests/AgentStudioTests/App/PaneCoordinatorTests.swift`

**Step 1: Write the failing test**

```swift
@MainActor
@Test("workspace updates sync root registration and active-in-app activity")
func syncRootsAndActivity() async {
    // mutate WorkspaceStore worktrees
    // assert register/unregister and setActivity calls reflect pane/session presence
}
```

**Step 2: Run test to verify it fails**

Run: `SWIFT_BUILD_DIR=".build-agent-l349" swift test --build-path "$SWIFT_BUILD_DIR" --filter "PaneCoordinatorTests/syncRootsAndActivity"`
Expected: FAIL (no watcher sync path yet).

**Step 3: Write minimal implementation**

```swift
// WorkspaceStore.swift
var onWorktreesChanged: (() -> Void)?
// call hook from updateRepoWorktrees/removeRepo

// PaneCoordinator+FilesystemSource.swift
func syncFilesystemWatchesToWorkspace() async { ... } // diff desired vs registered
func syncFilesystemActivityToWorkspace() async { ... } // active-in-app vs sidebar-only
```

Initialization:
- On coordinator init: sync watches for restored workspace.
- On worktree mutations: resync.
- On pane/session activity changes: update root activity and active-pane root precedence.

**Step 4: Run test to verify it passes**

Run: `SWIFT_BUILD_DIR=".build-agent-l349" swift test --build-path "$SWIFT_BUILD_DIR" --filter "PaneCoordinatorTests/syncRootsAndActivity"`
Expected: PASS.

**Step 5: Commit**

```bash
git add Sources/AgentStudio/App/PaneCoordinator+FilesystemSource.swift Sources/AgentStudio/App/PaneCoordinator.swift Sources/AgentStudio/Core/Stores/WorkspaceStore.swift Tests/AgentStudioTests/App/PaneCoordinatorTests.swift
git commit -m "feat: synchronize filesystem roots and activity priority with workspace lifecycle"
```

---

### Task 7b: Centralize Sidebar Filesystem/Git Ingestion Off MainActor

**Files:**
- Modify: `Sources/AgentStudio/Features/Sidebar/RepoSidebarContentView.swift`
- Create: `Sources/AgentStudio/Core/PaneRuntime/Projection/WorkspaceGitStatusStore.swift`
- Modify: `Sources/AgentStudio/App/PaneCoordinator.swift`
- Test: `Tests/AgentStudioTests/Features/Sidebar/RepoSidebarContentViewTests.swift`
- Test: `Tests/AgentStudioTests/Core/PaneRuntime/Projection/WorkspaceGitStatusStoreTests.swift`

**Step 1: Write the failing test**

```swift
@MainActor
@Test("sidebar reload path does not call direct worktree discovery or local git status fan-out")
func sidebarUsesCentralizedStatusStore() async {
    // assert RepoSidebarContentView consumes injected status store snapshots
    // and does not invoke direct discovery/status refresh loops.
}
```

**Step 2: Run test to verify it fails**

Run: `SWIFT_BUILD_DIR=".build-agent-l349" swift test --build-path "$SWIFT_BUILD_DIR" --filter "RepoSidebarContentViewTests/sidebarUsesCentralizedStatusStore"`
Expected: FAIL with current direct calls.

**Step 3: Write minimal implementation**

```swift
@MainActor
@Observable
final class WorkspaceGitStatusStore {
    private(set) var metadataByRepoId: [UUID: RepoIdentityMetadata] = [:]
    private(set) var statusByWorktreeId: [UUID: GitBranchStatus] = [:]
    func ingestFilesystemEnvelope(_ envelope: PaneEventEnvelope) { ... }
}
```

Sidebar migration:
- remove direct `refreshWorktrees()` + direct local git fan-out from sidebar reload path.
- sidebar reads centralized `WorkspaceGitStatusStore` + projection state.
- keep remote PR counts as separate forge/service concern (future `ForgeActor`), not filesystem source.
- keep filesystem source subscriptions centralized; sidebar only consumes store snapshots.

**Step 4: Run test to verify it passes**

Run: `SWIFT_BUILD_DIR=".build-agent-l349" swift test --build-path "$SWIFT_BUILD_DIR" --filter "RepoSidebarContentViewTests"`
Expected: PASS.

Run: `SWIFT_BUILD_DIR=".build-agent-l349" swift test --build-path "$SWIFT_BUILD_DIR" --filter "WorkspaceGitStatusStoreTests"`
Expected: PASS.

**Step 5: Commit**

```bash
git add Sources/AgentStudio/Features/Sidebar/RepoSidebarContentView.swift Sources/AgentStudio/Core/PaneRuntime/Projection/WorkspaceGitStatusStore.swift Sources/AgentStudio/App/PaneCoordinator.swift Tests/AgentStudioTests/Features/Sidebar/RepoSidebarContentViewTests.swift Tests/AgentStudioTests/Core/PaneRuntime/Projection/WorkspaceGitStatusStoreTests.swift
git commit -m "refactor: centralize sidebar filesystem/local-git ingestion via runtime projection stores"
```

---

### Task 8: Implement Pane-Scoped Filesystem Projection Filters (PaneId + CWD)

**Files:**
- Create: `Sources/AgentStudio/Core/PaneRuntime/Projection/PaneFilesystemProjectionStore.swift`
- Modify: `Sources/AgentStudio/App/PaneCoordinator.swift`
- Modify: `Sources/AgentStudio/Core/PaneRuntime/Contracts/PaneRuntimeEvent.swift`
- Test: `Tests/AgentStudioTests/Core/PaneRuntime/Projection/PaneFilesystemProjectionStoreTests.swift`

**Step 1: Write the failing test**

```swift
@MainActor
@Test("projection filters filesystem changes by pane worktree and cwd subtree")
func paneProjectionFiltersByCwd() async {
    // Given pane metadata: worktreeId=W1, cwd=/repo/src
    // When filesystem event paths include src/a.swift and docs/readme.md
    // Then projection for pane emits only src/a.swift
}
```

**Step 2: Run test to verify it fails**

Run: `SWIFT_BUILD_DIR=".build-agent-l349" swift test --build-path "$SWIFT_BUILD_DIR" --filter "PaneFilesystemProjectionStoreTests/paneProjectionFiltersByCwd"`
Expected: FAIL with missing projection store.

**Step 3: Write minimal implementation**

```swift
@MainActor
@Observable
final class PaneFilesystemProjectionStore {
    private(set) var byPaneId: [PaneId: PaneFilesystemProjection] = [:]
    func ingest(_ envelope: PaneEventEnvelope, paneSnapshots: [PaneId: PaneRuntimeSnapshot]) { ... }
}
```

Filtering rules:
- accept only `source == .system(.builtin(.filesystemWatcher))`
- match `sourceFacets.worktreeId` to pane worktree
- if pane `cwd` exists, keep only paths within that subtree
- projection updates are batched and monotonic by `batchSeq`.
- if pane `cwd` is nil, projection falls back to entire worktree scope.

**Step 4: Run test to verify it passes**

Run: `SWIFT_BUILD_DIR=".build-agent-l349" swift test --build-path "$SWIFT_BUILD_DIR" --filter "PaneFilesystemProjectionStoreTests"`
Expected: PASS.

**Step 5: Commit**

```bash
git add Sources/AgentStudio/Core/PaneRuntime/Projection/PaneFilesystemProjectionStore.swift Sources/AgentStudio/App/PaneCoordinator.swift Sources/AgentStudio/Core/PaneRuntime/Contracts/PaneRuntimeEvent.swift Tests/AgentStudioTests/Core/PaneRuntime/Projection/PaneFilesystemProjectionStoreTests.swift
git commit -m "feat: add pane-scoped filesystem projection filters by worktree and cwd"
```

---

### Task 9: Runtime Command + Lifecycle Coverage for New Runtime Types

**Files:**
- Modify: `Tests/AgentStudioTests/App/PaneCoordinatorRuntimeDispatchTests.swift`
- Modify: `Tests/AgentStudioTests/Core/PaneRuntime/Registry/RuntimeRegistryTests.swift`
- Modify: `Tests/AgentStudioTests/Core/PaneRuntime/Reduction/NotificationReducerTests.swift`

**Step 1: Write the failing test**

```swift
@Test("dispatchRuntimeCommand routes browser command to WebviewRuntime and diff command to BridgeRuntime")
func dispatchRoutesByRuntimeType() async { ... }
```

```swift
@Test("notification reducer prioritizes filesystem system-source events as critical")
func reducerPrioritizesFilesystemSystemEvents() async { ... }
```

**Step 2: Run test to verify it fails**

Run: `SWIFT_BUILD_DIR=".build-agent-l349" swift test --build-path "$SWIFT_BUILD_DIR" --filter "PaneCoordinatorRuntimeDispatchTests/dispatchRoutesByRuntimeType"`
Expected: FAIL before test/logic updates.

**Step 3: Write minimal implementation**

Update test fixtures and coordinator/runtime routing only as needed to satisfy:
- command dispatch by content/runtime kind
- lifecycle guard behavior on new runtimes
- system-source filesystem events treated as critical.

**Step 4: Run test to verify it passes**

Run: `SWIFT_BUILD_DIR=".build-agent-l349" swift test --build-path "$SWIFT_BUILD_DIR" --filter "PaneCoordinatorRuntimeDispatchTests"`
Expected: PASS.

Run: `SWIFT_BUILD_DIR=".build-agent-l349" swift test --build-path "$SWIFT_BUILD_DIR" --filter "NotificationReducerTests"`
Expected: PASS.

**Step 5: Commit**

```bash
git add Tests/AgentStudioTests/App/PaneCoordinatorRuntimeDispatchTests.swift Tests/AgentStudioTests/Core/PaneRuntime/Registry/RuntimeRegistryTests.swift Tests/AgentStudioTests/Core/PaneRuntime/Reduction/NotificationReducerTests.swift
git commit -m "test: extend runtime dispatch and reducer coverage for non-terminal runtimes and filesystem source"
```

---

### Task 10: Full Verification + Visual Sanity + Ticket Sync

**Files:**
- Modify: `docs/architecture/pane_runtime_architecture.md` (if any post-implementation contract clarifications remain)
- Modify: `docs/architecture/pane_runtime_eventbus_design.md` (if any post-implementation contract clarifications remain)
- Modify: `docs/plans/2026-02-27-luna-349-fs-event-source-and-runtime-conformers.md` (mark execution ledger)

**Step 1: Write the failing test**

Add/update an execution checklist in this plan file with unchecked verification gates.

**Step 2: Run verification to catch failures**

Run: `mise run format`
Expected: exit code `0`.

Run: `mise run lint`
Expected: exit code `0`.

Run: `mise run test`
Expected: exit code `0`, full suite passes.

If any command fails, stop and fix root cause before continuing.

**Step 3: Implement minimal fixes**

Apply only required code/doc fixes for failing gates. Re-run the exact failed command after each fix.

**Step 4: Re-run full verification**

Run in order:
1. `mise run format`
2. `mise run lint`
3. `mise run test`

Expected: all pass with exit code `0`.

Visual verification (required for UI-affecting changes):
1. `pkill -9 -f "AgentStudio"`
2. `.build/debug/AgentStudio &`
3. `PID=$(pgrep -f ".build/debug/AgentStudio")`
4. `peekaboo app switch --to "PID:$PID"`
5. `peekaboo see --app "PID:$PID" --json`

Expected: debug-build UI shows functional webview navigation and code viewer rendering.

**Step 5: Commit**

```bash
git add -A
git commit -m "feat: complete LUNA-349 runtime conformers and filesystem event funnel with pane projections"
```

---

### Task 11: Test Value Audit + Gap Closure Plan (Unit + Integration)

**Files:**
- Create: `docs/plans/2026-02-27-luna-349-test-value-plan.md`
- Modify: `docs/plans/2026-02-27-luna-349-fs-event-source-and-runtime-conformers.md` (this file; execution ledger)
- Modify: `Tests/AgentStudioTests/Core/PaneRuntime/Sources/FilesystemActorTests.swift` (if gaps found)
- Modify: `Tests/AgentStudioTests/Core/PaneRuntime/Projection/PaneFilesystemProjectionStoreTests.swift` (if gaps found)
- Modify: `Tests/AgentStudioTests/Features/Sidebar/RepoSidebarContentViewTests.swift` (if gaps found)

**Step 1: Investigate current test value**

Write an explicit risk-to-test map before adding new tests:
- app-wide watcher fan-in correctness
- nested root dedupe correctness
- active-in-app vs sidebar-only priority correctness
- local git snapshot ingestion correctness
- sidebar rendering correctness from centralized stores

Mark each test as:
- `unit`: single component, deterministic in-memory logic
- `integration`: multi-component flow with real sequencing boundaries
- `non-functional`: load, batching, ordering, cancellation, teardown

**Step 2: Define value rubric in test plan**

Document and enforce this rubric in `2026-02-27-luna-349-test-value-plan.md`:
- catches a production regression mode (not just line coverage)
- validates an explicit invariant from architecture docs/contracts
- deterministic signal (low flake, stable assertions)
- minimal mocking at integration boundaries

**Step 3: Add missing high-value tests only where map shows gaps**

Required gap checks:
- FilesystemActor burst splitting + deterministic path ordering under large batches
- deep nested root registration dedupe (no double-watch/no duplicate delivery)
- projection filtering correctness when pane cwd is nil vs scoped subtree
- end-to-end sidebar local status derivation from centralized git snapshot store

**Step 4: Verification**

Run:
1. `mise run lint`
2. `mise run test`

Expected: both pass with exit code `0`.

**Step 5: Commit**

```bash
git add docs/plans/2026-02-27-luna-349-test-value-plan.md docs/plans/2026-02-27-luna-349-fs-event-source-and-runtime-conformers.md Tests/AgentStudioTests/Core/PaneRuntime/Sources/FilesystemActorTests.swift Tests/AgentStudioTests/Core/PaneRuntime/Projection/PaneFilesystemProjectionStoreTests.swift Tests/AgentStudioTests/Features/Sidebar/RepoSidebarContentViewTests.swift
git commit -m "plan/test: add LUNA-349 test value audit and gap-closure plan"
```

---

## Final Acceptance Checklist

- [ ] `BridgeRuntime` exists and is registered/unregistered in `RuntimeRegistry`.
- [ ] `WebviewRuntime` exists and is registered/unregistered in `RuntimeRegistry`.
- [ ] `SwiftPaneRuntime` exists and powers real code viewer content loading.
- [ ] `FilesystemActor` is app-wide, keyed by worktree, debounced (500ms) with 2s max latency.
- [ ] `FilesystemActor` is the single filesystem ingress path (no per-pane/per-sidebar duplicate subscriptions).
- [ ] Filesystem envelopes flow through `EventBus` with `source = .system(.builtin(.filesystemWatcher))`.
- [ ] Nested folders route by deepest root ownership with no duplicate per-path delivery.
- [ ] Activity priority is simple and explicit: `active-in-app` vs `sidebar-only`, with active pane root precedence.
- [ ] Pull reconciliation is bounded to wake/recovery/drift checks; push events remain primary.
- [ ] Pane projection filtering by `paneId + worktreeId + cwd` exists for future git sinks.
- [ ] LUNA-349 test value plan exists and maps risks to unit/integration/non-functional coverage.
- [ ] Added/updated tests are explicitly high-signal for regression modes (not coverage-only assertions).
- [ ] Swift 6.2 concurrency gates are met (`@MainActor` ownership, `@concurrent nonisolated` heavy work, deterministic stream teardown).
- [ ] `mise run format`, `mise run lint`, and `mise run test` pass with exit code `0`.
- [ ] UI-affecting changes are visually verified with PID-targeted Peekaboo on debug build.
