# Persistent WatchedPath Folder Watching — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** "Add Folder" persists the folder path. FilesystemActor watches it with FSEvents and rescans for new repos automatically — so cloning a repo under a watched folder appears in the sidebar within seconds.

**Architecture:** A `WatchedPath` model is persisted in `workspace.state.json` via `WorkspaceStore`. When watched paths change (Add Folder or boot), `FilesystemActor` registers each parent folder with `DarwinFSEventStreamClient` for FSEvents monitoring. When FSEvents fires (new `.git` directory appears), FilesystemActor rescans using `RepoScanner` and emits `.repoDiscovered` via `bus.post()`. All topology events — boot replay, Add Folder one-shot, and FSEvents rescan — flow through the unified `RuntimeEventBus` pathway. The existing idempotent `WorkspaceCacheCoordinator` bus subscription is the single intake for all topology. A lazy fallback timer (5 minutes) rescans for robustness. No UI changes — the only entry point is the existing "Add Folder" menu item.

**Tech Stack:** Swift 6.2 (SE-0461 `NonisolatedNonsendingByDefault`), @Observable stores, DarwinFSEventStreamClient (FSEvents), AsyncStream (RuntimeEventBus), Swift Testing framework

---

## Context for the Implementing Agent

### Key Files to Read First

1. **CLAUDE.md** — State management patterns (especially patterns 2 and 4). Store boundaries are architectural decisions — ask the user before changing them.
2. **[Event System Design](docs/architecture/workspace_data_architecture.md#event-system-design-what-it-is-and-isnt)** — This is NOT CQRS. Pattern: mutate store directly → emit fact on bus → coordinator updates other store.
3. **`Sources/AgentStudio/Core/PaneRuntime/Sources/DarwinFSEventStreamClient.swift`** — Production FSEvents client. Registers paths, creates `FSEventStream` with `kFSEventStreamCreateFlagFileEvents`, pumps `FSEventBatch` through `AsyncStream`. You will reuse this for parent folder watching.
4. **`Sources/AgentStudio/Core/PaneRuntime/Sources/FilesystemActor.swift`** — Currently registers worktree roots with `DarwinFSEventStreamClient`. You will extend it to also register parent folders. Key: `register(worktreeId:, repoId:, rootPath:)` creates one FSEvent stream per path. **Critical:** `ingestRawPaths()` at line 170 has `guard roots[worktreeId] != nil` — watched-folder batches will be DROPPED if routed through this path. You must branch BEFORE `enqueueRawPaths` in the ingress loop.
5. **`Sources/AgentStudio/Infrastructure/RepoScanner.swift`** — Centralized scanner: `scanForGitRepos(in:maxDepth:)`. Walks filesystem, stops at `.git` boundary, skips submodules. All scanning MUST go through this — no ad-hoc `.git` detection.
6. **`Sources/AgentStudio/App/AppDelegate.swift`** — `handleAddFolderRequested()` (line ~823) uses `RepoScanner`. `addRepoIfNeeded()` (line ~860) currently calls `coordinator.consume()` directly — this MUST change to `bus.post()`. `replayBootTopology()` (line ~244) also calls `coordinator.consume()` directly — this MUST change to `bus.post()`.
7. **`Sources/AgentStudio/App/WorkspaceCacheCoordinator.swift`** — Uses `scopeSyncHandler` closure (not direct actor references) to communicate with `FilesystemGitPipeline`. The `startConsuming()` bus subscription becomes the single intake for ALL topology events. Init: `bus`, `workspaceStore`, `repoCache`, `scopeSyncHandler`.
8. **`Sources/AgentStudio/App/FilesystemGitPipeline.swift`** — Composition root. `applyScopeChange()` forwards `ScopeChange` to actors.

### Unified Bus Pathway (Critical Design Decision)

**All `.repoDiscovered` events flow through `RuntimeEventBus` → coordinator bus subscription.** There is no direct `coordinator.consume()` for topology. One event type, one intake pathway.

```
AppDelegate (boot replay)     ──► bus.post(.repoDiscovered) ──┐
AppDelegate (Add Folder)      ──► bus.post(.repoDiscovered) ──┤
FilesystemActor (FSEvents)    ──► bus.post(.repoDiscovered) ──┤──► EventBus ──► coordinator.startConsuming()
                                                               │                        │
                                                               │                 handleTopology()
                                                               │                   (idempotent)
```

**Why unified:** Before this feature, topology had one producer (AppDelegate) and one consumer (coordinator), so direct `consume()` was acceptable. Now FilesystemActor also produces `.repoDiscovered`, creating two producers. The bus gives a single intake with source traceability via `SystemEnvelope.source`.

**What changes:**
- `AppDelegate.addRepoIfNeeded()`: replace `coordinator.consume(envelope)` with `await bus.post(envelope)` (or emit via `PaneRuntimeEventBus.shared`)
- `AppDelegate.replayBootTopology()`: replace `coordinator.consume(envelope)` with `await bus.post(envelope)` — method becomes `async`
- `FilesystemActor.emitRepoDiscovered()`: already posts to `runtimeBus.post()` (no change)
- `coordinator.consume()` remains public for testability but is no longer called directly from app code

### Topology Authority Model

Workspace topology (which repos exist) is a **user decision**. Actors are executors within user-authorized scope, not autonomous topology owners.

- **Add Folder** = user authorizes watching a folder path
- **FilesystemActor** discovers repos only within persisted `WatchedPath` scopes
- **Coordinator** is the single canonical mutator of workspace topology (via `handleTopology()`)
- Actor may emit `.repoDiscovered` **only** when `repoPath` is under a registered watched folder scope — this is structurally enforced by `rescanAllWatchedFolders()` iterating only over `watchedFolderIds`

### Dependency Wiring Pattern

The coordinator does NOT hold direct actor references. It uses a `scopeSyncHandler` closure:

```swift
// AppDelegate wires:
scopeSyncHandler: { [weak pipeline] change in
    guard let pipeline else { return }
    await pipeline.applyScopeChange(change)
}
```

Extend `ScopeChange` enum → extend `applyScopeChange()` → call `FilesystemActor`. Never add direct actor references to the coordinator.

### Build & Test

```bash
AGENT_RUN_ID=watch-$(date +%s) mise run build    # timeout 60s
AGENT_RUN_ID=watch-$(date +%s) mise run test     # timeout 120s
AGENT_RUN_ID=watch-$(date +%s) mise run lint
```

**Never run two swift commands in parallel.** SwiftPM holds an exclusive lock. Always sequential.

---

### Task 1: WatchedPath Model + RepoScanner Constant ✅ DONE

**Files:**
- Create: `Sources/AgentStudio/Core/Models/WatchedPath.swift`
- Modify: `Sources/AgentStudio/Infrastructure/RepoScanner.swift`
- Test: `Tests/AgentStudioTests/Core/Models/WatchedPathTests.swift`

**Step 1: Add maxDepth constant to RepoScanner**

Currently `maxDepth: 3` is scattered across call sites. Centralize it:

```swift
// RepoScanner.swift — add at top of struct
struct RepoScanner {
    /// Default scan depth for parent folder discovery.
    /// Depth 4 supports layouts like ~/projects/org/suborg/repo/.git
    /// Scanning stops at the first .git boundary (no deeper).
    static let defaultMaxDepth = 4

    func scanForGitRepos(in rootURL: URL, maxDepth: Int = Self.defaultMaxDepth) -> [URL] {
        // ... existing implementation unchanged
    }
}
```

Change default from 3 to 4. The scanner already stops at `.git` — increasing depth just allows deeper folder nesting before the first repo.

**Step 2: Create WatchedPath model**

```swift
// Sources/AgentStudio/Core/Models/WatchedPath.swift
import Foundation

/// A user-added folder path persisted in workspace.state.json.
/// FilesystemActor watches this path with FSEvents and rescans for new repos.
struct WatchedPath: Codable, Identifiable, Hashable {
    let id: UUID
    var path: URL
    var addedAt: Date

    var stableKey: String { StableKey.fromPath(path) }

    init(id: UUID = UUID(), path: URL, addedAt: Date = Date()) {
        self.id = id
        self.path = path
        self.addedAt = addedAt
    }
}
```

No `kind` enum — all watched paths are parent folders. Direct repo adds use the existing `addRepoIfNeeded()` flow and don't need a WatchedPath.

**Step 3: Write tests**

```swift
// Tests/AgentStudioTests/Core/Models/WatchedPathTests.swift
import Foundation
import Testing
@testable import AgentStudio

@Suite struct WatchedPathTests {
    @Test func stableKey_isDeterministic() {
        let a = WatchedPath(path: URL(fileURLWithPath: "/projects"))
        let b = WatchedPath(path: URL(fileURLWithPath: "/projects"))
        #expect(a.stableKey == b.stableKey)
    }

    @Test func stableKey_differentPaths_differ() {
        let a = WatchedPath(path: URL(fileURLWithPath: "/projects"))
        let b = WatchedPath(path: URL(fileURLWithPath: "/other"))
        #expect(a.stableKey != b.stableKey)
    }

    @Test func codable_roundTrips() throws {
        let original = WatchedPath(path: URL(fileURLWithPath: "/projects"))
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(WatchedPath.self, from: data)
        #expect(decoded.id == original.id)
        #expect(decoded.path == original.path)
    }
}
```

**Step 4: Update all existing `maxDepth: 3` call sites to use `RepoScanner.defaultMaxDepth`**

Search for `maxDepth: 3` across the codebase. Replace with `RepoScanner.defaultMaxDepth` or remove the parameter (since 4 is now the default).

**Step 5: Verify**

```bash
AGENT_RUN_ID=watch-$(date +%s) mise run build
```

---

### Task 2: WatchedPath in WorkspaceStore + Persistence ✅ DONE

**Files:**
- Modify: `Sources/AgentStudio/Core/Stores/WorkspaceStore.swift`
- Modify: `Sources/AgentStudio/Core/Stores/WorkspacePersistor.swift`
- Test: `Tests/AgentStudioTests/Core/Stores/WorkspaceStoreTests.swift`

**Step 1: Add watchedPaths to WorkspaceStore**

```swift
private(set) var watchedPaths: [WatchedPath] = []

/// Add a watched path. Deduplicates by stableKey.
@discardableResult
func addWatchedPath(_ path: URL) -> WatchedPath? {
    let normalizedPath = path.standardizedFileURL
    let key = StableKey.fromPath(normalizedPath)
    guard !watchedPaths.contains(where: { $0.stableKey == key }) else {
        return watchedPaths.first { $0.stableKey == key }
    }
    let wp = WatchedPath(path: normalizedPath)
    watchedPaths.append(wp)
    markDirty()
    return wp
}

func removeWatchedPath(_ id: UUID) {
    watchedPaths.removeAll { $0.id == id }
    markDirty()
}
```

**Step 2: Add to PersistableState**

In `WorkspacePersistor.swift`:
- Add `var watchedPaths: [WatchedPath]` to `PersistableState`
- Add to init with default `[]`
- Add to CodingKeys
- In `init(from decoder:)`: `watchedPaths = try container.decodeIfPresent([WatchedPath].self, forKey: .watchedPaths) ?? []`

This `decodeIfPresent ?? []` is schema evolution — old files lack the field. Not backward compat ceremony.

In `WorkspaceStore`:
- Add `watchedPaths: watchedPaths` to `buildPersistableState()`
- Add `self.watchedPaths = state.watchedPaths` to `restore()`

**Step 3: Write tests**

```swift
@Test func addWatchedPath_deduplicatesByStableKey() {
    let store = WorkspaceStore()
    store.addWatchedPath(URL(fileURLWithPath: "/projects"))
    store.addWatchedPath(URL(fileURLWithPath: "/projects"))
    #expect(store.watchedPaths.count == 1)
}

@Test func removeWatchedPath_removesById() {
    let store = WorkspaceStore()
    let wp = store.addWatchedPath(URL(fileURLWithPath: "/projects"))!
    store.removeWatchedPath(wp.id)
    #expect(store.watchedPaths.isEmpty)
}
```

**Step 4: Verify**

```bash
AGENT_RUN_ID=watch-$(date +%s) mise run build
AGENT_RUN_ID=watch-$(date +%s) mise run test
```

---

### Task 3: Extend ScopeChange + FilesystemActor FSEvents Registration

This is the core task. FilesystemActor gains FSEvents-based parent folder watching.

**Files:**
- Modify: `Sources/AgentStudio/App/WorkspaceCacheCoordinator.swift` — extend `ScopeChange`
- Modify: `Sources/AgentStudio/App/FilesystemGitPipeline.swift` — forward new scope change
- Modify: `Sources/AgentStudio/Core/PaneRuntime/Sources/FilesystemActor.swift` — add parent folder FSEvents + rescan

**Step 1: Read FilesystemActor fully**

Understand how `register()` creates FSEvent streams via `fseventStreamClient.register()`. How the ingress task processes `FSEventBatch`. How `ingestRawPaths()` filters and batches changes. You're adding a parallel path for parent folders.

**Critical:** `ingestRawPaths()` at line 170 has `guard roots[worktreeId] != nil else { return }`. Watched-folder synthetic UUIDs are NOT in `roots`, so batches from watched folders will be silently dropped if routed through `enqueueRawPaths`. The ingress loop must branch BEFORE that call.

**Step 2: Add ScopeChange case**

```swift
enum ScopeChange: Sendable {
    case registerForgeRepo(repoId: UUID, remote: String)
    case unregisterForgeRepo(repoId: UUID)
    case refreshForgeRepo(repoId: UUID, correlationId: UUID?)
    case updateWatchedFolders(paths: [URL])  // NEW
}
```

Update the `CustomStringConvertible` extension.

**Step 3: Add parent folder tracking to FilesystemActor**

Key design: parent folder FSEvent registrations are keyed by a synthetic UUID (derived from folder stableKey, NOT a real worktreeId). When FSEvents fires under a parent folder, the actor runs `RepoScanner` on that folder and emits `.repoDiscovered` for each repo found. The existing idempotent coordinator handles dedup.

**Scope constraint:** The actor may only emit `.repoDiscovered` for paths discovered under a registered watched folder. This is structurally enforced — `rescanAllWatchedFolders()` iterates only over `watchedFolderIds` keys, and `handleWatchedFolderFSEvent()` checks `watchedFolderIds.values.contains(worktreeId)`.

```swift
// New state in FilesystemActor
private var watchedFolderIds: [URL: UUID] = [:]  // folder path → synthetic registration UUID
private var fallbackRescanTask: Task<Void, Never>?

func updateWatchedFolders(_ paths: [URL]) async {
    let newPaths = Set(paths.map { $0.standardizedFileURL })
    let oldPaths = Set(watchedFolderIds.keys)

    // Unregister removed folders
    for removed in oldPaths.subtracting(newPaths) {
        if let syntheticId = watchedFolderIds.removeValue(forKey: removed) {
            fseventStreamClient.unregister(worktreeId: syntheticId)
        }
    }

    // Register new folders
    for added in newPaths.subtracting(oldPaths) {
        let syntheticId = UUID()
        watchedFolderIds[added] = syntheticId
        fseventStreamClient.register(worktreeId: syntheticId, repoId: syntheticId, rootPath: added)
    }

    // Immediate scan of all watched folders
    await rescanAllWatchedFolders()

    // Fallback periodic rescan (5 minutes) for robustness
    startFallbackRescan()
}
```

**Step 4: Branch ingress for watched-folder batches**

The existing `startIngressTaskIfNeeded()` routes all `FSEventBatch` into `enqueueRawPaths()` → `ingestRawPaths()`. But `ingestRawPaths()` guards on `roots[worktreeId]` at line 170 — synthetic watched-folder UUIDs are NOT in `roots`, so those batches would be silently dropped.

**Fix:** Branch in the ingress loop BEFORE calling `enqueueRawPaths`:

```swift
private func startIngressTaskIfNeeded() {
    guard ingressTask == nil else { return }
    let stream = fseventStreamClient.events()
    ingressTask = Task { [weak self] in
        for await batch in stream {
            guard !Task.isCancelled else { break }
            // Branch: watched-folder batches go to rescan, not worktree ingress
            if let self, await self.isWatchedFolderBatch(batch.worktreeId) {
                await self.handleWatchedFolderFSEvent(batch)
            } else {
                await self?.enqueueRawPaths(worktreeId: batch.worktreeId, paths: batch.paths)
            }
        }
    }
}

private func isWatchedFolderBatch(_ worktreeId: UUID) -> Bool {
    watchedFolderIds.values.contains(worktreeId)
}

private func handleWatchedFolderFSEvent(_ batch: FSEventBatch) async {
    // Check if any path contains /.git — signals a new repo may have appeared
    let hasGitChange = batch.paths.contains { $0.contains("/.git") }
    guard hasGitChange else { return }

    // Find which watched folder owns this synthetic ID
    guard let folderPath = watchedFolderIds.first(where: { $0.value == batch.worktreeId })?.key else {
        return
    }

    // Rescan just that folder
    let repoPaths = await scanFolder(folderPath)
    for repoPath in repoPaths {
        await emitRepoDiscovered(repoPath: repoPath, parentPath: folderPath)
    }
}
```

**Step 5: Implement rescan + event emission**

**Swift 6.2 concurrency context (SE-0461):** In Swift 6.2 with `NonisolatedNonsendingByDefault`, a plain `nonisolated async` function called from inside an actor **inherits the actor's executor** — it no longer escapes to the global pool. This means blocking I/O in a `nonisolated` method would block the actor's serial executor. `@concurrent nonisolated` is the explicit opt-out: it guarantees the function runs on the global concurrent executor regardless of caller context. For blocking filesystem walks, this is a **correctness requirement**, not a stylistic choice.

```swift
/// Blocking filesystem scan — MUST run off the actor's executor.
/// Under SE-0461, plain nonisolated async inherits actor isolation.
/// @concurrent ensures this escapes to the global executor.
@concurrent nonisolated private func scanFolder(_ folderPath: URL) -> [URL] {
    RepoScanner().scanForGitRepos(in: folderPath)
}

/// Actor-isolated coordinator: reads actor state, dispatches scans off-executor,
/// hops back to emit events on the actor.
private func rescanAllWatchedFolders() async {
    for (folderPath, _) in watchedFolderIds {
        let repoPaths = await scanFolder(folderPath)
        for repoPath in repoPaths {
            await emitRepoDiscovered(repoPath: repoPath, parentPath: folderPath)
        }
    }
}

private func emitRepoDiscovered(repoPath: URL, parentPath: URL) async {
    nextEnvelopeSequence += 1
    let envelope = RuntimeEnvelope.system(
        SystemEnvelope(
            source: .builtin(.filesystemWatcher),
            seq: nextEnvelopeSequence,
            timestamp: envelopeClock.now,
            event: .topology(.repoDiscovered(repoPath: repoPath, parentPath: parentPath))
        )
    )
    await runtimeBus.post(envelope)
}
```

Use the actor's existing `nextEnvelopeSequence` monotonic counter. Do NOT hardcode `seq: 0`.

The `scanFolder` → `rescanAllWatchedFolders` split is the key pattern: `scanFolder` is `@concurrent nonisolated` so the blocking `RepoScanner` walk runs on the global executor. `rescanAllWatchedFolders` stays actor-isolated so it can safely read `watchedFolderIds` and call `emitRepoDiscovered`. The `await` on `scanFolder` is the hop boundary between the two executors.

**Step 6: Fallback timer (with injectable clock)**

The actor already has `sleepClock: any Clock<Duration>` injected at init (line 45). Use it — not `Task.sleep` — so the timer is testable.

```swift
private func startFallbackRescan() {
    fallbackRescanTask?.cancel()
    guard !watchedFolderIds.isEmpty else { return }
    fallbackRescanTask = Task { [weak self] in
        guard let self else { return }
        while !Task.isCancelled {
            try? await self.sleepClock.sleep(for: .seconds(300))  // 5 minutes
            guard !Task.isCancelled else { break }
            await self.rescanAllWatchedFolders()
        }
    }
}
```

Cancel `fallbackRescanTask` in `shutdown()`.

**Step 7: Wire FilesystemGitPipeline**

In `FilesystemGitPipeline.applyScopeChange()`:

```swift
case .updateWatchedFolders(let paths):
    await filesystemActor.updateWatchedFolders(paths)
```

**Step 8: Verify**

```bash
AGENT_RUN_ID=watch-$(date +%s) mise run build
```

---

### Task 4: Unify Topology Bus Pathway + Wire AppDelegate

This task has two parts: (A) migrate all topology events to the unified bus pathway, and (B) wire Add Folder + boot to persist WatchedPaths and trigger FSEvents watching.

**Files:**
- Modify: `Sources/AgentStudio/App/AppDelegate.swift`
- Modify: `docs/architecture/workspace_data_architecture.md`

**Step 1: Migrate `addRepoIfNeeded()` to bus pathway**

Currently `addRepoIfNeeded()` at line ~860 calls `coordinator.consume()` directly. Change to `bus.post()`:

```swift
private func addRepoIfNeeded(_ path: URL) async {
    let normalizedPath = path.standardizedFileURL

    // Skip if the path is already a known worktree of an available repo.
    let isKnownWorktree = store.repos.contains { repo in
        !store.isRepoUnavailable(repo.id)
            && repo.worktrees.contains { $0.path.standardizedFileURL == normalizedPath }
    }
    if isKnownWorktree { return }

    // Post topology fact on the bus — coordinator's subscription handles it.
    let envelope = Self.makeTopologyEnvelope(repoPath: normalizedPath, source: .builtin(.coordinator))
    await PaneRuntimeEventBus.shared.post(envelope)
    paneCoordinator.syncFilesystemRootsAndActivity()
}
```

Note: `addRepoIfNeeded` becomes `async` because `bus.post()` is async. Update its call sites (the `.addRepoAtPathRequested` handler) accordingly — it's already called from an async context.

**Step 2: Migrate `replayBootTopology()` to bus pathway**

Currently calls `coordinator.consume()` directly in a for-loop. Change to `bus.post()`:

```swift
private func replayBootTopology(store: WorkspaceStore) async {
    let activePaneRepoIds: Set<UUID> = {
        guard let activeTab = store.activeTab else { return [] }
        let repoIds = activeTab.paneIds.compactMap { store.panes[$0]?.repoId }
        return Set(repoIds)
    }()
    let prioritizedRepos = store.repos.sorted { a, b in
        let aActive = activePaneRepoIds.contains(a.id)
        let bActive = activePaneRepoIds.contains(b.id)
        if aActive != bActive { return aActive }
        return false
    }
    for repo in prioritizedRepos {
        await PaneRuntimeEventBus.shared.post(
            Self.makeTopologyEnvelope(
                repoPath: repo.repoPath,
                source: .builtin(.coordinator)
            )
        )
    }
}
```

The method becomes `async`. Update its call site in `applicationDidFinishLaunching` accordingly. The coordinator must have `startConsuming()` called BEFORE `replayBootTopology()` so the bus subscription is active.

**Step 3: Modify handleAddFolderRequested**

Add `store.addWatchedPath(rootURL)` before the existing scan. Trigger scope sync so FilesystemActor starts watching. One-shot scan results also go through `bus.post()`:

```swift
private func handleAddFolderRequested(startingAt initialURL: URL? = nil) async {
    // ... existing NSOpenPanel code unchanged ...

    // 1. Persist the watched path (direct store mutation)
    store.addWatchedPath(rootURL)

    // 2. Tell FilesystemActor to start watching (via scopeSyncHandler)
    await workspaceCacheCoordinator.syncScope(
        .updateWatchedFolders(paths: store.watchedPaths.map(\.path))
    )

    // 3. Existing one-shot scan for immediate feedback (kept for responsiveness)
    let repoPaths = await Task(priority: .userInitiated) {
        RepoScanner().scanForGitRepos(in: rootURL)
    }.value

    guard !repoPaths.isEmpty else {
        let alert = NSAlert()
        alert.messageText = "No Git Repositories Found"
        alert.informativeText = "No folders with a Git repository were found under \(rootURL.lastPathComponent). The folder will still be watched for future repos."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
        return
    }

    // 4. Post topology facts via bus (not postAppEvent → addRepoIfNeeded → consume)
    for repoPath in repoPaths {
        await PaneRuntimeEventBus.shared.post(
            Self.makeTopologyEnvelope(
                repoPath: repoPath.standardizedFileURL,
                source: .builtin(.coordinator)
            )
        )
    }
    paneCoordinator.syncFilesystemRootsAndActivity()
}
```

**Step 4: Sync watched folders on boot**

At the end of `replayBootTopology()`, add:

```swift
if !store.watchedPaths.isEmpty {
    await workspaceCacheCoordinator.syncScope(
        .updateWatchedFolders(paths: store.watchedPaths.map(\.path))
    )
}
```

**Step 5: Ensure coordinator subscription starts before boot replay**

In `applicationDidFinishLaunching`, verify that `workspaceCacheCoordinator.startConsuming()` is called BEFORE `replayBootTopology()`. If it's not already in this order, reorder. The bus subscription must be active to receive the replayed topology events.

**Step 6: Update architecture docs**

In `docs/architecture/workspace_data_architecture.md`, update the "Topology Intake Seam" section (~line 469-480) and the "What NOT to Do" section (~line 482-488):

**Replace the "Topology Intake Seam" section** with:

```markdown
### Topology Intake: Unified Bus Pathway

All topology events (`.repoDiscovered`, `.repoRemoved`) flow through `RuntimeEventBus` → `WorkspaceCacheCoordinator.startConsuming()`. There is no direct `coordinator.consume()` for topology in app code. One event type, one intake pathway.

Producers:
- **AppDelegate** — boot replay and Add Folder one-shot scan
- **FilesystemActor** — FSEvents-triggered rescan of watched folders

The coordinator's `handleTopology()` is idempotent (dedup by stableKey). Boot replay + FSEvents rescans posting the same path is a no-op on the second call.

`coordinator.consume()` remains public for testability but is not called directly from app code.
```

**Update the "What NOT to Do" bullet** from:
> "Do not make actors emit canonical topology events. Only AppDelegate (user actions + boot replay) emits `.repoDiscovered`/`.repoRemoved`."

To:
> "Actors may emit `.repoDiscovered` only within user-authorized watched-folder scopes. `FilesystemActor` rescans persisted `WatchedPath` folders and posts discoveries on the bus. This is not autonomous discovery — the user delegated authority via Add Folder."

**Step 7: Verify**

```bash
AGENT_RUN_ID=watch-$(date +%s) mise run build
```

---

### Task 5: Tests

**Files:**
- Modify: `Tests/AgentStudioTests/App/WorkspaceCacheCoordinatorTests.swift`

**Step 1: Test scope change forwarding**

```swift
@Test func updateWatchedFolders_scopeChangeForwarded() async {
    let workspaceStore = WorkspaceStore()
    let repoCache = WorkspaceRepoCache()
    var recorded: [ScopeChange] = []
    let coordinator = WorkspaceCacheCoordinator(
        workspaceStore: workspaceStore,
        repoCache: repoCache,
        scopeSyncHandler: { change in recorded.append(change) }
    )

    await coordinator.syncScope(
        .updateWatchedFolders(paths: [URL(fileURLWithPath: "/projects")])
    )

    #expect(recorded.count == 1)
    if case .updateWatchedFolders(let paths) = recorded[0] {
        #expect(paths.count == 1)
    } else {
        Issue.record("Expected updateWatchedFolders")
    }
}
```

**Step 2: Test topology via bus (not direct consume)**

Verify that topology events posted on the bus are received by the coordinator's subscription:

```swift
@Test func topologyEvent_receivedViaBusSubscription() async throws {
    let bus = EventBus<RuntimeEnvelope>()
    let workspaceStore = WorkspaceStore()
    let repoCache = WorkspaceRepoCache()
    let coordinator = WorkspaceCacheCoordinator(
        bus: bus,
        workspaceStore: workspaceStore,
        repoCache: repoCache,
        scopeSyncHandler: { _ in }
    )
    coordinator.startConsuming()

    let repoPath = URL(fileURLWithPath: "/projects/my-repo")
    let envelope = RuntimeEnvelope.system(
        SystemEnvelope(
            source: .builtin(.filesystemWatcher),
            seq: 1,
            timestamp: .now,
            event: .topology(.repoDiscovered(
                repoPath: repoPath,
                parentPath: URL(fileURLWithPath: "/projects")
            ))
        )
    )
    await bus.post(envelope)

    // Give the async subscription time to process
    try await Task.sleep(for: .milliseconds(50))

    #expect(workspaceStore.repos.count == 1)
    #expect(workspaceStore.repos.first?.repoPath == repoPath)
}
```

**Step 3: Test rescan dedup via coordinator (idempotency)**

```swift
@Test func rescan_repoDiscovered_idempotent() async {
    let workspaceStore = WorkspaceStore()
    let repoCache = WorkspaceRepoCache()
    let coordinator = WorkspaceCacheCoordinator(
        workspaceStore: workspaceStore,
        repoCache: repoCache,
        scopeSyncHandler: { _ in }
    )
    let repoPath = URL(fileURLWithPath: "/projects/my-repo")
    workspaceStore.addRepo(at: repoPath)

    // Simulate two rescans finding the same repo (boot replay + FSEvents rescan)
    let envelope = RuntimeEnvelope.system(
        SystemEnvelope(
            source: .builtin(.filesystemWatcher),
            seq: 1,
            timestamp: .now,
            event: .topology(.repoDiscovered(
                repoPath: repoPath,
                parentPath: URL(fileURLWithPath: "/projects")
            ))
        )
    )
    coordinator.consume(envelope)
    coordinator.consume(envelope)

    #expect(workspaceStore.repos.count == 1)
}
```

**Step 4: Verify**

```bash
AGENT_RUN_ID=watch-$(date +%s) mise run test
```

---

### Task 6: Verification Pass

**Step 1: Format and lint**

```bash
AGENT_RUN_ID=watch-$(date +%s) mise run format
AGENT_RUN_ID=watch-$(date +%s) mise run lint
```

**Step 2: Full test suite**

```bash
AGENT_RUN_ID=watch-$(date +%s) mise run test
```

**Step 3: Grep for consistency**

```bash
# No scattered maxDepth: 3 (should all use defaultMaxDepth or no param)
grep -rn "maxDepth: 3" Sources/ --include="*.swift"

# No direct coordinator.consume() in app code (only in tests)
grep -rn "coordinator.consume" Sources/AgentStudio/App/ --include="*.swift"

# WatchedPath in persistence
grep -rn "watchedPaths" Sources/AgentStudio/Core/Stores/WorkspacePersistor.swift

# ScopeChange has the new case
grep -rn "updateWatchedFolders" Sources/AgentStudio/App/WorkspaceCacheCoordinator.swift

# FilesystemActor handles parent folders
grep -rn "watchedFolderIds\|updateWatchedFolders\|rescanAllWatchedFolders" Sources/AgentStudio/Core/PaneRuntime/Sources/FilesystemActor.swift

# Pipeline forwards it
grep -rn "updateWatchedFolders" Sources/AgentStudio/App/FilesystemGitPipeline.swift

# Bus pathway in AppDelegate (should see bus.post, NOT coordinator.consume)
grep -rn "bus.post\|PaneRuntimeEventBus.shared.post" Sources/AgentStudio/App/AppDelegate.swift
```

Expected: zero `maxDepth: 3` matches. Zero `coordinator.consume` in `Sources/AgentStudio/App/`. All other greps return results.

---

## Summary

| Task | What | Files |
|------|------|-------|
| 1 ✅ | WatchedPath model + centralize maxDepth=4 | `WatchedPath.swift`, `RepoScanner.swift` |
| 2 ✅ | Store + persistence | `WorkspaceStore.swift`, `WorkspacePersistor.swift` |
| 3 | ScopeChange + FSEvents parent folder watching + ingress branching | `WorkspaceCacheCoordinator.swift`, `FilesystemActor.swift`, `FilesystemGitPipeline.swift` |
| 4 | Unify topology bus pathway + wire AppDelegate (Add Folder + boot) | `AppDelegate.swift`, `workspace_data_architecture.md` |
| 5 | Tests (bus pathway + idempotency) | `WorkspaceCacheCoordinatorTests.swift` |
| 6 | Verification | All |

## Key Design Decisions

| Decision | Rationale |
|----------|-----------|
| Unified bus pathway for all topology | Two producers (AppDelegate + FilesystemActor) → one intake (bus subscription). Eliminates direct `coordinator.consume()` from app code. Source traceability via `SystemEnvelope.source`. |
| FSEvents, not polling | Near-instant detection. No wasted I/O. Uses existing `DarwinFSEventStreamClient`. |
| 5-min fallback timer (injectable clock) | Robustness for edge cases where FSEvents misses something. Uses `sleepClock.sleep(for:)` not `Task.sleep` — testable via injected clock. |
| maxDepth: 4 (centralized) | Supports `~/projects/org/suborg/repo/.git`. Scanner stops at `.git` — deeper nesting is safe. |
| No `WatchedPathKind` enum | All watched paths are parent folders. Direct repos use `addRepoIfNeeded()`. YAGNI. |
| No UI changes | Entry point is existing "Add Folder" menu item. No new UI surfaces. |
| `ScopeChange`, not bus event for config | `ConfigChangeEvent.watchedPathsUpdated` exists but has no consumers. YAGNI. Don't delete it — emit when a consumer exists. |
| Synthetic UUIDs for FSEvent registration | Parent folders aren't worktrees. Use a synthetic UUID keyed by folder path so `DarwinFSEventStreamClient` can manage the stream lifecycle. |
| Ingress branching before `enqueueRawPaths` | `ingestRawPaths()` guards on `roots[worktreeId]` — synthetic watched-folder UUIDs are not in `roots`. Must branch in the ingress loop to route watched-folder batches to rescan, not worktree-level processing. |
| Actor topology scope constraint | Actor may emit `.repoDiscovered` only for paths under registered watched folders. Structurally enforced — `rescanAllWatchedFolders()` iterates only `watchedFolderIds`. User delegates authority via Add Folder; actor executes within that scope. |
| `@concurrent nonisolated` for blocking scan | SE-0461 flips `nonisolated async` to inherit caller's actor in 6.2. Without `@concurrent`, `RepoScanner.scanForGitRepos()` would block `FilesystemActor`'s serial executor. `@concurrent` guarantees escape to the global executor — correctness, not style. |
| `Task { [weak self] }` for periodic timer | Existing codebase pattern for long-lived tasks stored as actor properties. Prevents retain cycles. `[weak self]` works correctly with actors in Swift 6.2. |
| `parentPath` traceability (not WatchedPath.id) | `.repoDiscovered` carries `parentPath` for traceability. Adding `WatchedPath.id` would couple topology events to watched-path identity. Coordinator can derive scope membership from `store.watchedPaths` if needed. |
| `decodeIfPresent ?? []` for schema evolution | Old workspace files lack `watchedPaths`. Default `[]` gives correct initial state. Field written on next save. Not backward compat ceremony. |
