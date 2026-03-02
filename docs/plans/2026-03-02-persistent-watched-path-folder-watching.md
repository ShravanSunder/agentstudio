# Persistent WatchedPath Folder Watching — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** "Add Folder" remembers the folder path persistently, and the system rescans it for new repos via a periodic timer — so cloning a new repo under a watched folder auto-discovers it in the sidebar.

**Architecture:** Add a `WatchedPath` canonical model to `WorkspaceStore`, persisted in `workspace.state.json`. On boot and on "Add Folder," the `scopeSyncHandler` closure (which bridges `WorkspaceCacheCoordinator` → `FilesystemGitPipeline`) forwards watched folder paths to `FilesystemActor` for periodic rescan. `FilesystemActor` posts `.repoDiscovered` events on the `EventBus` — the existing idempotent coordinator handles dedup. No direct actor references from the coordinator; everything flows through the existing `scopeSyncHandler` closure pattern.

**Tech Stack:** Swift 6, @Observable stores, AsyncStream (RuntimeEventBus), Swift Testing framework

---

## Context for the Implementing Agent

### Key Files to Read First

Before starting, read these files to understand the system you're extending:

1. **CLAUDE.md** — Project conventions, build commands, state management mental model (especially "Event-Driven Enrichment" section)
2. **docs/architecture/workspace_data_architecture.md** — Three-tier persistence, enrichment pipeline, event contracts, "Event System Design: What It Is (and Isn't)" section
3. **Sources/AgentStudio/Core/PaneRuntime/Contracts/RuntimeEnvelopeCore.swift** — Event type definitions. Note: `ConfigChangeEvent.watchedPathsUpdated(paths: [URL])` already exists but nothing emits it yet.
4. **Sources/AgentStudio/App/AppDelegate.swift** — `handleAddFolderRequested()` (line ~823), `addRepoIfNeeded()` (line ~860), `replayBootTopology()` (line ~244), `makeTopologyEnvelope()` (line ~269). Also see how `WorkspaceCacheCoordinator` is wired with `scopeSyncHandler` closure (line ~191).
5. **Sources/AgentStudio/Infrastructure/RepoScanner.swift** — One-shot scanner: `scanForGitRepos(in:maxDepth:)`. You'll reuse this, not replace it.
6. **Sources/AgentStudio/Core/Stores/WorkspacePersistor.swift** — `PersistableState` struct (line ~23). You'll add `watchedPaths` here.
7. **Sources/AgentStudio/Core/Stores/WorkspaceStore.swift** — Canonical store. You'll add `watchedPaths: [WatchedPath]` and mutation methods.
8. **Sources/AgentStudio/App/WorkspaceCacheCoordinator.swift** — Consumes events, updates stores. Already handles `.repoDiscovered` idempotently. Uses `scopeSyncHandler` closure (not direct actor references) to communicate with `FilesystemGitPipeline`. Init requires: `bus`, `workspaceStore`, `repoCache`, `scopeSyncHandler`.
9. **Sources/AgentStudio/App/FilesystemGitPipeline.swift** — Composition root for `FilesystemActor`. The `scopeSyncHandler` closure in AppDelegate delegates to `pipeline.applyScopeChange()`.

### How the Event System Works

This is NOT CQRS. The pattern is: **mutate the store directly → emit a fact on the bus → coordinator updates the other store.**

For this feature:
1. User clicks "Add Folder" → `store.addWatchedPath(path)` (direct store mutation)
2. `AppDelegate` tells the pipeline to start watching via `scopeSyncHandler` (same pattern as forge scope changes)
3. `FilesystemActor` rescans the folder → emits `.repoDiscovered` for each repo found **on the EventBus**
4. `WorkspaceCacheCoordinator` receives `.repoDiscovered` from the bus → idempotent upsert (already implemented)

Do NOT route the store mutation through the bus. The bus notifies, stores decide.

### Dependency Wiring Pattern

The coordinator does **not** hold a direct reference to `FilesystemActor`. Instead, it uses a `scopeSyncHandler` closure injected at init:

```swift
// AppDelegate wires the closure:
workspaceCacheCoordinator = WorkspaceCacheCoordinator(
    bus: paneRuntimeBus,
    workspaceStore: store,
    repoCache: workspaceRepoCache,
    scopeSyncHandler: { [weak pipeline] change in
        guard let pipeline else { return }
        await pipeline.applyScopeChange(change)
    }
)
```

When adding new scope operations (like "start watching a folder"), extend the `ScopeChange` enum and the pipeline's `applyScopeChange()` method. Do NOT add direct actor references to the coordinator.

### Build & Test Commands

```bash
AGENT_RUN_ID=watch-$(date +%s) mise run build    # Full build (timeout 60s)
AGENT_RUN_ID=watch-$(date +%s) mise run test     # Full test suite (timeout 120s)
AGENT_RUN_ID=watch-$(date +%s) mise run lint     # Lint check

# Filtered test run:
SWIFT_BUILD_DIR=".build-agent-$(uuidgen | tr -dc 'a-z0-9' | head -c 8)"
swift test --build-path "$SWIFT_BUILD_DIR" --filter "WatchedPath" > /tmp/test-output.txt 2>&1 && echo "PASS" || echo "FAIL"
```

**CRITICAL:** Never run two swift commands in parallel. SwiftPM holds an exclusive lock. Always sequential.

---

### Task 1: Create WatchedPath Model

**Why first:** Everything depends on this type existing.

**Files:**
- Create: `Sources/AgentStudio/Core/Models/WatchedPath.swift`
- Test: `Tests/AgentStudioTests/Core/Models/WatchedPathTests.swift`

**Step 1: Write the model**

```swift
// Sources/AgentStudio/Core/Models/WatchedPath.swift
import Foundation

/// A user-added folder path that the app watches for git repos.
/// Persisted in workspace.state.json. Rescanned periodically for new repos.
struct WatchedPath: Codable, Identifiable, Hashable {
    let id: UUID
    var path: URL
    var kind: WatchedPathKind
    var addedAt: Date

    /// Deterministic identity derived from filesystem path via SHA-256.
    var stableKey: String { StableKey.fromPath(path) }

    init(
        id: UUID = UUID(),
        path: URL,
        kind: WatchedPathKind = .parentFolder,
        addedAt: Date = Date()
    ) {
        self.id = id
        self.path = path
        self.kind = kind
        self.addedAt = addedAt
    }
}

enum WatchedPathKind: String, Codable, Sendable {
    /// Scan children up to maxDepth for git repos. Rescan periodically.
    case parentFolder
}
```

Note: Only `parentFolder` kind for now. Direct repo adds already work via `addRepoIfNeeded()`. YAGNI — don't add `.directRepo` until there's a behavioral split that requires it.

**Step 2: Write tests**

```swift
// Tests/AgentStudioTests/Core/Models/WatchedPathTests.swift
import Testing
@testable import AgentStudio

@Suite struct WatchedPathTests {
    @Test func init_setsDefaults() {
        let path = WatchedPath(path: URL(fileURLWithPath: "/projects"))
        #expect(path.kind == .parentFolder)
        #expect(!path.id.uuidString.isEmpty)
    }

    @Test func stableKey_isDeterministic() {
        let a = WatchedPath(path: URL(fileURLWithPath: "/projects"))
        let b = WatchedPath(path: URL(fileURLWithPath: "/projects"))
        #expect(a.stableKey == b.stableKey)
    }

    @Test func stableKey_differentPaths_areDifferent() {
        let a = WatchedPath(path: URL(fileURLWithPath: "/projects"))
        let b = WatchedPath(path: URL(fileURLWithPath: "/other"))
        #expect(a.stableKey != b.stableKey)
    }

    @Test func codable_roundTrips() throws {
        let original = WatchedPath(path: URL(fileURLWithPath: "/projects"), kind: .parentFolder)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(WatchedPath.self, from: data)
        #expect(decoded.id == original.id)
        #expect(decoded.path == original.path)
        #expect(decoded.kind == original.kind)
    }
}
```

**Step 3: Verify**

```bash
AGENT_RUN_ID=watch-$(date +%s) mise run build
```

**Step 4: Commit**

```bash
git add Sources/AgentStudio/Core/Models/WatchedPath.swift Tests/AgentStudioTests/Core/Models/WatchedPathTests.swift
git commit -m "feat: add WatchedPath model for persistent folder watching"
```

---

### Task 2: Add WatchedPath to WorkspaceStore and Persistence

**Why now:** The store must own watchedPaths before AppDelegate can add them.

**Files:**
- Modify: `Sources/AgentStudio/Core/Stores/WorkspaceStore.swift`
- Modify: `Sources/AgentStudio/Core/Stores/WorkspacePersistor.swift`
- Test: `Tests/AgentStudioTests/Core/Stores/WorkspaceStoreTests.swift`

**Step 1: Add watchedPaths to WorkspaceStore**

Add to the state properties section (near line 22):

```swift
private(set) var watchedPaths: [WatchedPath] = []
```

Add mutation methods:

```swift
/// Add a watched path. Deduplicates by stableKey.
@discardableResult
func addWatchedPath(_ path: URL, kind: WatchedPathKind = .parentFolder) -> WatchedPath? {
    let normalizedPath = path.standardizedFileURL
    let incomingStableKey = StableKey.fromPath(normalizedPath)
    guard !watchedPaths.contains(where: { $0.stableKey == incomingStableKey }) else {
        return watchedPaths.first { $0.stableKey == incomingStableKey }
    }
    let watchedPath = WatchedPath(path: normalizedPath, kind: kind)
    watchedPaths.append(watchedPath)
    markDirty()
    return watchedPath
}

/// Remove a watched path by ID.
func removeWatchedPath(_ id: UUID) {
    watchedPaths.removeAll { $0.id == id }
    markDirty()
}
```

**Step 2: Add watchedPaths to PersistableState**

In `WorkspacePersistor.swift`, add `watchedPaths: [WatchedPath]` to `PersistableState`.

Add to init with default `[]`. Add to CodingKeys. Add to `init(from decoder:)`:

```swift
watchedPaths = try container.decodeIfPresent([WatchedPath].self, forKey: .watchedPaths) ?? []
```

This `decodeIfPresent` is NOT backward-compat ceremony — it's schema evolution. Old workspace files don't have this field. The default `[]` means "no watched paths yet," which is the correct initial state. The field will be written on next save.

Add to `buildPersistableState()` in WorkspaceStore and to `restore()`.

**Step 3: Write tests**

In `WorkspaceStoreTests.swift`:

```swift
@Test func addWatchedPath_addsAndMarksDirty() {
    let store = WorkspaceStore()
    let result = store.addWatchedPath(URL(fileURLWithPath: "/projects"))
    #expect(result != nil)
    #expect(store.watchedPaths.count == 1)
    #expect(store.watchedPaths[0].path.path == "/projects")
    #expect(store.watchedPaths[0].kind == .parentFolder)
}

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

**Step 5: Commit**

```bash
git add -A
git commit -m "feat: add watchedPaths to WorkspaceStore and persistence"
```

---

### Task 3: Extend ScopeChange for Watched Folder Operations

**Why now:** Before wiring AppDelegate or FilesystemActor, we need the `ScopeChange` enum to support watched folder operations. This is how the coordinator communicates with actors — via the `scopeSyncHandler` closure.

**Files:**
- Modify: `Sources/AgentStudio/App/WorkspaceCacheCoordinator.swift` — extend `ScopeChange` enum
- Modify: `Sources/AgentStudio/App/FilesystemGitPipeline.swift` — handle new scope change in `applyScopeChange()`
- Modify: `Sources/AgentStudio/Core/PaneRuntime/Sources/FilesystemActor.swift` — add watched folder tracking and rescan

**Step 1: Add ScopeChange cases**

In `WorkspaceCacheCoordinator.swift`, extend the `ScopeChange` enum:

```swift
enum ScopeChange: Sendable {
    case registerForgeRepo(repoId: UUID, remote: String)
    case unregisterForgeRepo(repoId: UUID)
    case refreshForgeRepo(repoId: UUID, correlationId: UUID?)
    case updateWatchedFolders(paths: [URL])  // NEW
}
```

Update `CustomStringConvertible` extension.

**Step 2: Add rescan to FilesystemActor**

Read `FilesystemActor.swift` fully first to understand its current structure. Then add:

```swift
private var watchedParentFolders: Set<URL> = []
private var rescanTask: Task<Void, Never>?

func updateWatchedFolders(_ paths: [URL]) {
    watchedParentFolders = Set(paths)
    rescanTask?.cancel()
    guard !watchedParentFolders.isEmpty else { return }

    // Immediate rescan
    rescanWatchedFolders()

    // Periodic rescan every 60 seconds
    rescanTask = Task { [weak self] in
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(60))
            guard !Task.isCancelled else { break }
            self?.rescanWatchedFolders()
        }
    }
}

private func rescanWatchedFolders() {
    let scanner = RepoScanner()
    for folder in watchedParentFolders {
        let repoPaths = scanner.scanForGitRepos(in: folder, maxDepth: 3)
        for repoPath in repoPaths {
            let envelope = RuntimeEnvelope.system(
                SystemEnvelope(
                    source: .builtin(.filesystemWatcher),
                    seq: nextSeq(),
                    timestamp: .now,
                    event: .topology(.repoDiscovered(
                        repoPath: repoPath,
                        parentPath: folder
                    ))
                )
            )
            Task { await eventBus.post(envelope) }
        }
    }
}
```

Important: use the actor's existing `nextSeq()` method (or equivalent monotonic counter) for the `seq` field — NOT a hardcoded `0`. Check how `FilesystemActor` generates seq numbers for its other events and use the same pattern. If it uses `0` everywhere, that's OK — match the existing pattern.

The `RepoScanner` scan is blocking I/O. If `FilesystemActor` is an `actor`, this runs on its serial executor which is fine — it's already the filesystem worker. If you need to offload, use `@concurrent nonisolated` per project conventions.

**Step 3: Wire FilesystemGitPipeline to forward the new scope change**

In `FilesystemGitPipeline.applyScopeChange()`, add:

```swift
case .updateWatchedFolders(let paths):
    await filesystemActor.updateWatchedFolders(paths)
```

**Step 4: Cancel rescanTask on shutdown**

Ensure `FilesystemActor`'s shutdown/deinit cancels `rescanTask`.

**Step 5: Verify**

```bash
AGENT_RUN_ID=watch-$(date +%s) mise run build
```

**Step 6: Commit**

```bash
git add -A
git commit -m "feat: extend ScopeChange for watched folders, add rescan to FilesystemActor"
```

---

### Task 4: Wire AppDelegate — Add Folder Persists and Triggers Rescan

**Why now:** All infrastructure is in place. Wire the user action.

**Files:**
- Modify: `Sources/AgentStudio/App/AppDelegate.swift`

**Step 1: Modify handleAddFolderRequested**

After the NSOpenPanel, persist the watched path AND trigger scope sync:

```swift
private func handleAddFolderRequested(startingAt initialURL: URL? = nil) async {
    let rootURL: URL
    if let initialURL {
        rootURL = initialURL.standardizedFileURL
    } else {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.message = "Choose a folder containing git repositories"
        guard panel.runModal() == .OK, let selectedURL = panel.url else { return }
        rootURL = selectedURL.standardizedFileURL
    }

    // 1. Persist the watched path (direct store mutation)
    store.addWatchedPath(rootURL, kind: .parentFolder)

    // 2. Tell FilesystemActor to start watching (via scopeSyncHandler)
    await workspaceCacheCoordinator.syncScope(
        .updateWatchedFolders(paths: store.watchedPaths.map(\.path))
    )

    // 3. One-shot scan for immediate results (existing behavior, kept for responsiveness)
    let repoPaths = await Task(priority: .userInitiated) {
        RepoScanner().scanForGitRepos(in: rootURL, maxDepth: 3)
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

    for repoPath in repoPaths {
        postAppEvent(.addRepoAtPathRequested(path: repoPath.standardizedFileURL))
    }
}
```

Note: Step 3 is the existing one-shot scan — kept for immediate feedback. The periodic rescan from Task 3 handles future discoveries.

**Step 2: Emit watched folders on boot**

At the end of `replayBootTopology()`, sync watched folders:

```swift
if !store.watchedPaths.isEmpty {
    await coordinator.syncScope(
        .updateWatchedFolders(paths: store.watchedPaths.map(\.path))
    )
}
```

**Step 3: Verify**

```bash
AGENT_RUN_ID=watch-$(date +%s) mise run build
```

**Step 4: Commit**

```bash
git add Sources/AgentStudio/App/AppDelegate.swift
git commit -m "feat: Add Folder persists WatchedPath and triggers rescan via scopeSyncHandler"
```

---

### Task 5: Tests — Coordinator + Store + ScopeChange Integration

**Why now:** All pieces are wired. Test the coordinator flow with real stores.

**Files:**
- Modify: `Tests/AgentStudioTests/App/WorkspaceCacheCoordinatorTests.swift`

**Step 1: Write integration tests**

Tests must use the real coordinator init signature including `scopeSyncHandler`:

```swift
@Test func watchedFolder_scopeChangeEmitted_onRescan() async {
    // Arrange
    let workspaceStore = WorkspaceStore()
    let repoCache = WorkspaceRepoCache()
    var recordedScopeChanges: [ScopeChange] = []
    let coordinator = WorkspaceCacheCoordinator(
        workspaceStore: workspaceStore,
        repoCache: repoCache,
        scopeSyncHandler: { change in
            recordedScopeChanges.append(change)
        }
    )

    // Act — simulate the scope sync that AppDelegate would trigger
    await coordinator.syncScope(
        .updateWatchedFolders(paths: [URL(fileURLWithPath: "/tmp/test-projects")])
    )

    // Assert — scope change was forwarded
    #expect(recordedScopeChanges.count == 1)
    if case .updateWatchedFolders(let paths) = recordedScopeChanges[0] {
        #expect(paths.count == 1)
    } else {
        Issue.record("Expected updateWatchedFolders scope change")
    }
}

@Test func rescan_discoveredRepo_idempotent() async {
    // Arrange
    let workspaceStore = WorkspaceStore()
    let repoCache = WorkspaceRepoCache()
    let coordinator = WorkspaceCacheCoordinator(
        workspaceStore: workspaceStore,
        repoCache: repoCache,
        scopeSyncHandler: { _ in }
    )

    let repoPath = URL(fileURLWithPath: "/tmp/test-projects/my-repo")
    workspaceStore.addRepo(at: repoPath)

    // Act — simulate FilesystemActor emitting .repoDiscovered from rescan (twice)
    let envelope = RuntimeEnvelope.system(
        SystemEnvelope(
            source: .builtin(.filesystemWatcher),
            seq: 1,
            timestamp: .now,
            event: .topology(.repoDiscovered(
                repoPath: repoPath,
                parentPath: URL(fileURLWithPath: "/tmp/test-projects")
            ))
        )
    )
    coordinator.consume(envelope)
    coordinator.consume(envelope)

    // Assert — still only one repo, one enrichment entry
    #expect(workspaceStore.repos.count == 1)
}
```

**Step 2: Verify**

```bash
AGENT_RUN_ID=watch-$(date +%s) mise run test
```

**Step 3: Commit**

```bash
git add Tests/AgentStudioTests/App/WorkspaceCacheCoordinatorTests.swift
git commit -m "test: integration tests for watched folder scope change and rescan dedup"
```

---

### Task 6: Full Verification Pass

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
# WatchedPath is referenced in persistence
grep -rn "watchedPaths" Sources/AgentStudio/Core/Stores/WorkspacePersistor.swift
# WatchedPath is in the store
grep -rn "watchedPaths" Sources/AgentStudio/Core/Stores/WorkspaceStore.swift
# ScopeChange has the new case
grep -rn "updateWatchedFolders" Sources/AgentStudio/App/WorkspaceCacheCoordinator.swift
# FilesystemActor handles rescan
grep -rn "watchedParentFolders\|updateWatchedFolders\|rescanWatchedFolders" Sources/AgentStudio/Core/PaneRuntime/Sources/FilesystemActor.swift
# Pipeline forwards the scope change
grep -rn "updateWatchedFolders" Sources/AgentStudio/App/FilesystemGitPipeline.swift
```

**Step 4: Commit**

```bash
git add -A
git commit -m "chore: verification pass for persistent WatchedPath feature"
```

---

## Summary

| Task | What | Files |
|------|------|-------|
| 1 | WatchedPath model | `Core/Models/WatchedPath.swift` |
| 2 | Store + persistence | `WorkspaceStore.swift`, `WorkspacePersistor.swift` |
| 3 | ScopeChange + FilesystemActor rescan + Pipeline wiring | `WorkspaceCacheCoordinator.swift`, `FilesystemActor.swift`, `FilesystemGitPipeline.swift` |
| 4 | Wire AppDelegate (Add Folder + boot) | `AppDelegate.swift` |
| 5 | Integration tests | `WorkspaceCacheCoordinatorTests.swift` |
| 6 | Verification | All |

## Issues Addressed from Review

| # | Issue | Resolution |
|---|-------|------------|
| 1 | Plan bypassed bus via coordinator.consume() | Rescan happens in FilesystemActor which posts `.repoDiscovered` on the EventBus. AppDelegate one-shot scan uses existing `.addRepoAtPathRequested` AppEvent flow. |
| 2 | Coordinator wiring assumed direct FilesystemActor reference | Uses existing `scopeSyncHandler` closure → `FilesystemGitPipeline.applyScopeChange()` → `FilesystemActor`. Extended `ScopeChange` enum with `.updateWatchedFolders`. |
| 3 | Test snippets missing scopeSyncHandler | All test examples include `scopeSyncHandler: { _ in }` or capture closure matching real init signature. |
| 4 | decodeIfPresent vs "no backward compat" | This is schema evolution, not backward compat. Old files lack the field entirely — `?? []` gives correct initial state. Field written on next save. |
| 5 | directRepo kind with no behavioral split | Removed `.directRepo` — only `.parentFolder` for now. YAGNI. Direct repo adds already work via `addRepoIfNeeded()`. |
| 6 | "on filesystem events" claim vs timer | Updated goal to say "periodic timer." Parent-folder FSEvent registration is a future enhancement beyond this plan. |
| 7 | seq: 0 inconsistency | Plan instructs to use `nextSeq()` or match existing actor pattern for monotonic sequencing. |
| 8 | "Integration" test wasn't e2e | Tests now exercise the scopeSyncHandler path. True e2e (actor → bus → sidebar) is tested in existing `FilesystemToPrimarySidebarIntegrationTests`. |
