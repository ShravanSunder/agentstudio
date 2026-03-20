# Actor Message-In → Message-Out Integration Tests

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Fill the two key integration test gaps: (1) FSEventBatch injected via controllable client → FilesystemActor → verify exact RuntimeEnvelope shape on the bus, and (2) watched folder FSEvent with real `.git` repo → actor runs RepoScanner → `.repoDiscovered` appears on bus → coordinator adds repo to WorkspaceStore.

**Architecture:** Both test suites inject messages via `ControllableFSEventStreamClient` (already exists), subscribe to `EventBus<RuntimeEnvelope>`, and assert on envelope shape/content. Gap 2 uses `FilesystemTestGitRepo` to create a real git repo so RepoScanner finds it. No production code changes — tests only.

**Tech Stack:** Swift 6 `Testing` framework, `EventBus<RuntimeEnvelope>`, `ControllableFSEventStreamClient`, `FilesystemTestGitRepo`

---

### Task 1: FSEventBatch → Actor → Bus Envelope Shape (Worktree Ingress)

**Context:** The existing `FilesystemActorTests` test the actor via `enqueueRawPaths()` — a direct method call that bypasses the FSEvent ingress loop. The ingress loop (`startIngressTaskIfNeeded`) reads from `fseventStreamClient.events()` and routes to `enqueueRawPaths` for worktree batches. No test currently verifies this full path: inject `FSEventBatch` via controllable client → actor's ingress loop picks it up → debounce/flush → exact `RuntimeEnvelope` appears on bus with correct shape.

**Files:**
- Modify: `Tests/AgentStudioTests/Core/PaneRuntime/Sources/FilesystemActorWatchedFolderTests.swift`

The `ControllableFSEventStreamClient` is already defined in this file and is the right test seam. We add a new `// MARK: - FSEvent Ingress → Bus Output` section to the existing `FilesystemActorWatchedFolderTests` struct.

**Step 1: Write the test — FSEventBatch worktree ingress produces correct worktree envelope**

Add the following test to `FilesystemActorWatchedFolderTests`:

```swift
// MARK: - FSEvent Ingress → Bus Output

@Test("FSEventBatch for registered worktree produces filesChanged envelope on bus")
func fsEventBatchForWorktreeProducesFilesChangedEnvelope() async throws {
    let bus = EventBus<RuntimeEnvelope>()
    let fsClient = ControllableFSEventStreamClient()
    let actor = FilesystemActor(
        bus: bus,
        fseventStreamClient: fsClient,
        debounceWindow: .zero,
        maxFlushLatency: .zero
    )

    let worktreeId = UUID()
    let repoId = UUID()
    let rootPath = URL(fileURLWithPath: "/tmp/fsevent-ingress-\(UUID().uuidString)")
    await actor.register(worktreeId: worktreeId, repoId: repoId, rootPath: rootPath)

    // Subscribe after register to skip the worktreeRegistered topology event
    let stream = await bus.subscribe()

    // Inject FSEventBatch via controllable client — this enters the ingress loop
    fsClient.send(
        FSEventBatch(
            worktreeId: worktreeId,
            paths: [
                "\(rootPath.path)/Sources/App.swift",
                "\(rootPath.path)/Sources/Model.swift",
            ]
        ))

    // Collect the envelope
    let envelope = await collectFirstEnvelope(from: stream, timeout: .milliseconds(500))
    let worktreeEnvelope = try #require(envelope.flatMap { envelope -> WorktreeEnvelope? in
        if case .worktree(let wt) = envelope { return wt }
        return nil
    })

    // Assert envelope shape
    #expect(worktreeEnvelope.worktreeId == worktreeId)
    #expect(worktreeEnvelope.repoId == repoId)
    #expect(worktreeEnvelope.source == .system(.builtin(.filesystemWatcher)))

    guard case .filesystem(.filesChanged(let changeset)) = worktreeEnvelope.event else {
        Issue.record("Expected filesChanged event, got \(worktreeEnvelope.event)")
        await actor.shutdown()
        return
    }
    #expect(changeset.worktreeId == worktreeId)
    #expect(Set(changeset.paths) == Set(["Sources/App.swift", "Sources/Model.swift"]))

    await actor.shutdown()
}
```

Also add this shared helper at the bottom of the helpers section (replacing or alongside `drainAllEnvelopes`):

```swift
private func collectFirstEnvelope(
    from stream: AsyncStream<RuntimeEnvelope>,
    timeout: Duration
) async -> RuntimeEnvelope? {
    let collectTask = Task {
        var iterator = stream.makeAsyncIterator()
        return await iterator.next()
    }
    try? await Task.sleep(for: timeout)
    collectTask.cancel()
    return await collectTask.value
}
```

**Step 2: Build and run**

```bash
swift test --build-path ".build-agent-fix" --filter "FilesystemActorWatchedFolder" 2>&1 | tail -20
```

Expected: 4 tests pass (3 existing + 1 new).

**Step 3: Write the test — FSEventBatch with git-internal paths suppresses them from changeset**

```swift
@Test("FSEventBatch ingress suppresses .git internal paths and annotates changeset")
func fsEventBatchIngressSuppressesGitInternalPaths() async throws {
    let bus = EventBus<RuntimeEnvelope>()
    let fsClient = ControllableFSEventStreamClient()
    let actor = FilesystemActor(
        bus: bus,
        fseventStreamClient: fsClient,
        debounceWindow: .zero,
        maxFlushLatency: .zero
    )

    let worktreeId = UUID()
    let repoId = UUID()
    let rootPath = URL(fileURLWithPath: "/tmp/fsevent-git-suppress-\(UUID().uuidString)")
    await actor.register(worktreeId: worktreeId, repoId: repoId, rootPath: rootPath)

    let stream = await bus.subscribe()

    fsClient.send(
        FSEventBatch(
            worktreeId: worktreeId,
            paths: [
                "\(rootPath.path)/.git/index",
                "\(rootPath.path)/.git/objects/aa/bb",
                "\(rootPath.path)/Sources/Feature.swift",
            ]
        ))

    let envelope = await collectFirstEnvelope(from: stream, timeout: .milliseconds(500))
    let worktreeEnvelope = try #require(envelope.flatMap { envelope -> WorktreeEnvelope? in
        if case .worktree(let wt) = envelope { return wt }
        return nil
    })

    guard case .filesystem(.filesChanged(let changeset)) = worktreeEnvelope.event else {
        Issue.record("Expected filesChanged event")
        await actor.shutdown()
        return
    }
    #expect(changeset.paths == ["Sources/Feature.swift"])
    #expect(changeset.containsGitInternalChanges)
    #expect(changeset.suppressedGitInternalPathCount == 2)

    await actor.shutdown()
}
```

**Step 4: Build and run**

```bash
swift test --build-path ".build-agent-fix" --filter "FilesystemActorWatchedFolder" 2>&1 | tail -20
```

Expected: 5 tests pass.

**Step 5: Commit**

```bash
git add Tests/AgentStudioTests/Core/PaneRuntime/Sources/FilesystemActorWatchedFolderTests.swift
git commit -m "test: add FSEventBatch → bus envelope shape integration tests"
```

---

### Task 2: Watched Folder FSEvent → RepoScanner → Bus → Coordinator → Store

**Context:** The existing watched folder test (`gitTriggerMatchesOnlyGitDirectory`) proves the trigger filter works but uses `/tmp` paths where RepoScanner finds nothing. This test creates a real git repo under a watched folder so the full chain fires: FSEvent `.git/HEAD` change → actor runs RepoScanner → finds repo → emits `.repoDiscovered` on bus → coordinator picks it up → repo appears in WorkspaceStore.

**Files:**
- Create: `Tests/AgentStudioTests/Integration/WatchedFolderDiscoveryIntegrationTests.swift`

We create a new integration test file because this test uses `FilesystemTestGitRepo` (real git), `WorkspaceStore`, `WorkspaceCacheCoordinator`, and `EventBus` together — it's a cross-layer integration test, not an actor unit test.

**Step 1: Write the integration test**

```swift
import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite(.serialized)
struct WatchedFolderDiscoveryIntegrationTests {

    @Test("FSEvent in watched folder with real .git repo produces repoDiscovered and adds repo to store")
    func watchedFolderFSEventWithRealRepoDiscoversAndAddsToStore() async throws {
        // Arrange — create a real git repo inside a watched folder
        let watchedFolder = FileManager.default.temporaryDirectory
            .appending(path: "watched-discovery-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: watchedFolder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: watchedFolder) }

        let repoURL = try FilesystemTestGitRepo.create(
            named: "watched-discovery-repo",
            under: watchedFolder
        )

        // Wire up the full pipeline: bus, actor, coordinator, store
        let bus = EventBus<RuntimeEnvelope>()
        let fsClient = ControllableFSEventStreamClient()
        let actor = FilesystemActor(
            bus: bus,
            fseventStreamClient: fsClient,
            debounceWindow: .zero,
            maxFlushLatency: .zero
        )

        let workspaceDir = FileManager.default.temporaryDirectory
            .appending(path: "watched-discovery-ws-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: workspaceDir) }
        let persistor = WorkspacePersistor(workspacesDir: workspaceDir)
        persistor.ensureDirectory()
        let store = WorkspaceStore(persistor: persistor)
        store.restore()
        let repoCache = WorkspaceRepoCache()
        let coordinator = WorkspaceCacheCoordinator(
            bus: bus,
            workspaceStore: store,
            repoCache: repoCache,
            scopeSyncHandler: { _ in }
        )
        coordinator.startConsuming()
        defer { coordinator.stopConsuming() }

        // Register the watched folder
        await actor.updateWatchedFolders([watchedFolder])
        let syntheticId = fsClient.registeredWorktreeIds.first!

        // Act — simulate FSEvent with a .git/ path inside the watched folder
        fsClient.send(
            FSEventBatch(
                worktreeId: syntheticId,
                paths: ["\(repoURL.path)/.git/HEAD"]
            ))

        // Assert — repo should appear in WorkspaceStore via bus → coordinator
        let repoAppeared = await eventually("repo should be discovered and added to store") {
            store.repos.contains { $0.repoPath == repoURL }
        }
        #expect(repoAppeared)

        // Assert — enrichment should be seeded
        if let repo = store.repos.first(where: { $0.repoPath == repoURL }) {
            #expect(repoCache.repoEnrichmentByRepoId[repo.id] != nil)
        }

        await actor.shutdown()
    }

    @Test("watched folder rescan on updateWatchedFolders discovers pre-existing repos")
    func updateWatchedFoldersDiscoversPreExistingRepos() async throws {
        // Arrange — create a real git repo BEFORE registering the watched folder
        let watchedFolder = FileManager.default.temporaryDirectory
            .appending(path: "watched-prescan-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: watchedFolder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: watchedFolder) }

        let repoURL = try FilesystemTestGitRepo.create(
            named: "watched-prescan-repo",
            under: watchedFolder
        )

        let bus = EventBus<RuntimeEnvelope>()
        let fsClient = ControllableFSEventStreamClient()
        let actor = FilesystemActor(
            bus: bus,
            fseventStreamClient: fsClient,
            debounceWindow: .zero,
            maxFlushLatency: .zero
        )

        let workspaceDir = FileManager.default.temporaryDirectory
            .appending(path: "watched-prescan-ws-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: workspaceDir) }
        let persistor = WorkspacePersistor(workspacesDir: workspaceDir)
        persistor.ensureDirectory()
        let store = WorkspaceStore(persistor: persistor)
        store.restore()
        let repoCache = WorkspaceRepoCache()
        let coordinator = WorkspaceCacheCoordinator(
            bus: bus,
            workspaceStore: store,
            repoCache: repoCache,
            scopeSyncHandler: { _ in }
        )
        coordinator.startConsuming()
        defer { coordinator.stopConsuming() }

        // Act — register the watched folder; initial rescan should discover the repo
        await actor.updateWatchedFolders([watchedFolder])

        // Assert — repo should appear from the initial rescan (no FSEvent needed)
        let repoAppeared = await eventually("pre-existing repo should be discovered on initial scan") {
            store.repos.contains { $0.repoPath == repoURL }
        }
        #expect(repoAppeared)

        await actor.shutdown()
    }

    @Test("watched folder discovery is idempotent — same repo discovered twice does not duplicate")
    func watchedFolderDiscoveryIdempotent() async throws {
        let watchedFolder = FileManager.default.temporaryDirectory
            .appending(path: "watched-idemp-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: watchedFolder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: watchedFolder) }

        let repoURL = try FilesystemTestGitRepo.create(
            named: "watched-idemp-repo",
            under: watchedFolder
        )

        let bus = EventBus<RuntimeEnvelope>()
        let fsClient = ControllableFSEventStreamClient()
        let actor = FilesystemActor(
            bus: bus,
            fseventStreamClient: fsClient,
            debounceWindow: .zero,
            maxFlushLatency: .zero
        )

        let workspaceDir = FileManager.default.temporaryDirectory
            .appending(path: "watched-idemp-ws-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: workspaceDir) }
        let persistor = WorkspacePersistor(workspacesDir: workspaceDir)
        persistor.ensureDirectory()
        let store = WorkspaceStore(persistor: persistor)
        store.restore()
        let repoCache = WorkspaceRepoCache()
        let coordinator = WorkspaceCacheCoordinator(
            bus: bus,
            workspaceStore: store,
            repoCache: repoCache,
            scopeSyncHandler: { _ in }
        )
        coordinator.startConsuming()
        defer { coordinator.stopConsuming() }

        await actor.updateWatchedFolders([watchedFolder])
        let syntheticId = fsClient.registeredWorktreeIds.first!

        // Wait for initial rescan
        let repoAppeared = await eventually("repo should be discovered") {
            store.repos.contains { $0.repoPath == repoURL }
        }
        #expect(repoAppeared)

        let countAfterFirst = store.repos.count

        // Trigger another FSEvent — should NOT add a second repo
        fsClient.send(
            FSEventBatch(
                worktreeId: syntheticId,
                paths: ["\(repoURL.path)/.git/HEAD"]
            ))

        // Allow processing
        try await Task.sleep(for: .milliseconds(200))

        #expect(store.repos.count == countAfterFirst, "Duplicate discovery must not add a second repo")

        await actor.shutdown()
    }

    // MARK: - Helpers

    private func eventually(
        _ description: String,
        maxAttempts: Int = 200,
        pollIntervalNanoseconds: UInt64 = 20_000_000,
        condition: @escaping @MainActor () -> Bool
    ) async -> Bool {
        for _ in 0..<maxAttempts {
            if condition() {
                return true
            }
            await Task.yield()
            try? await Task.sleep(nanoseconds: pollIntervalNanoseconds)
        }
        Issue.record("\(description) timed out")
        return false
    }
}
```

**Step 2: Add `FilesystemTestGitRepo.create(named:under:)` overload**

The existing `FilesystemTestGitRepo.create(named:)` creates repos under `$CWD/tmp/filesystem-git-tests/`. We need an overload that creates repos under a specific parent directory (the watched folder).

Modify `Tests/AgentStudioTests/Helpers/FilesystemTestGitRepo.swift` — add a new static method:

```swift
/// Creates a git repo under the specified parent directory.
/// The caller owns cleanup of the parent (and its contents).
static func create(named prefix: String, under parentDir: URL) throws -> URL {
    let repoURL = parentDir.appending(path: "\(prefix)-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: repoURL, withIntermediateDirectories: true)
    try runGit(at: repoURL, args: ["init"])
    try runGit(at: repoURL, args: ["config", "user.email", "luna-tests@example.com"])
    try runGit(at: repoURL, args: ["config", "user.name", "Luna Tests"])
    try runGit(at: repoURL, args: ["config", "commit.gpgsign", "false"])
    try runGit(at: repoURL, args: ["config", "tag.gpgsign", "false"])

    // Seed an initial commit so `rev-parse --is-inside-work-tree` returns true
    let readmePath = repoURL.appending(path: "README.md")
    try "# Test\n".write(to: readmePath, atomically: true, encoding: .utf8)
    try runGit(at: repoURL, args: ["add", "."])
    try runGit(at: repoURL, args: ["commit", "-m", "Initial commit"])

    return repoURL
}
```

**Important:** The initial commit is required because `RepoScanner.isValidGitWorkingTree` calls `git rev-parse --is-inside-work-tree`, which only returns `true` after at least one commit.

**Step 3: Make `runGit` accessible to the new method**

The existing `runGit` is `private static`. Since the new `create(named:under:)` is also `static` on the same type, it already has access. No visibility change needed.

**Step 4: Build and run**

```bash
swift test --build-path ".build-agent-fix" --filter "WatchedFolderDiscovery" 2>&1 | tail -20
```

Expected: 3 tests pass.

**Step 5: Run full watched-folder + integration tests together**

```bash
swift test --build-path ".build-agent-fix" --filter "FilesystemActorWatchedFolder|WatchedFolderDiscovery" 2>&1 | tail -25
```

Expected: 8 tests pass (5 from Task 1 + 3 from Task 2).

**Step 6: Commit**

```bash
git add Tests/AgentStudioTests/Integration/WatchedFolderDiscoveryIntegrationTests.swift Tests/AgentStudioTests/Helpers/FilesystemTestGitRepo.swift
git commit -m "test: add watched folder → RepoScanner → bus → store integration tests"
```

---

### Task 3: Verification Pass

**Step 1: Format**

```bash
mise run format
```

**Step 2: Lint**

```bash
mise run lint
```

Fix any violations in files we touched. Pre-existing violations in other files are out of scope.

**Step 3: Run full targeted test suite**

```bash
swift test --build-path ".build-agent-fix" --filter "FilesystemActorWatchedFolder|WatchedFolderDiscovery|WorkspacePersistor|WorkspaceCacheCoordinator" 2>&1 | tail -30
```

Expected: All pass. No regressions.

**Step 4: Commit any formatting fixes**

```bash
git add -u
git commit -m "chore: format and lint cleanup for integration test additions"
```

(Skip if no changes.)
