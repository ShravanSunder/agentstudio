# Topology Event Pipeline Fixes — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Close six gaps in the topology event pipeline and persistence layer: repo removal bypassing the coordinator, unavailable repos getting stuck, partial priority ordering on filesystem sync, silent repoId fabrication on decode, legacy fallback decode in canonical state, and permissive cache/UI decode.

**Architecture:** All repo lifecycle mutations (add, remove, re-add) must flow through `WorkspaceCacheCoordinator` so cache pruning and forge scope sync happen consistently. Filesystem registration should respect the same active-pane priority as boot replay. All decode paths should fail fast on missing required fields — no legacy data exists to protect. Corrupt cache/UI files should be thrown away and rebuilt from events/defaults.

**Tech Stack:** Swift 6, SwiftUI, @Observable, AsyncStream (RuntimeEventBus), Swift Testing framework

---

## Strict Ordering Rationale

1. First: fix the Worktree decode contract (foundation — changes what data is valid)
2. Second: fix repo removal pipeline (highest-severity bug)
3. Third: fix unavailable-repo stuck state (interacts with removal fix)
4. Fourth: fix filesystem registration priority (lowest risk, depends on prior fixes being stable)
5. Fifth: integration tests proving the full lifecycle
6. Sixth: remove legacy canonical state decode (eliminates dead `[Repo]` migration path)
7. Last: harden cache + UI decode (throw away corrupt files, rebuild from events/defaults)

---

### Task 1: Harden Worktree Decode — Fail Fast on Missing repoId

**Why first:** This is a data contract change. Every other fix assumes worktrees have valid repoIds. If decode silently fabricates them, the coordinator's FK lookups are unreliable.

**Files:**
- Modify: `Sources/AgentStudio/Core/Models/Worktree.swift`
- Modify: `Tests/AgentStudioTests/Core/Models/WorktreeModelTests.swift`

**Step 1: Write failing test — decode without repoId should throw**

Add to `WorktreeModelTests.swift`:

```swift
@Test
func decode_missingRepoId_throws() throws {
    let json = """
    {"id":"11111111-1111-1111-1111-111111111111","name":"main","path":"/tmp/repo","isMainWorktree":true}
    """
    let data = Data(json.utf8)
    #expect(throws: DecodingError.self) {
        try JSONDecoder().decode(Worktree.self, from: data)
    }
}
```

**Step 2: Run test — expect FAIL (currently decodes with random UUID)**

```bash
swift test --build-path ".build-agent-t1" --filter "decode_missingRepoId_throws"
```

Expected: FAIL — no error thrown because `decodeIfPresent ?? UUID()` silently succeeds.

**Step 3: Harden the decoder**

In `Worktree.swift`, replace the custom `init(from decoder:)` with strict decoding:

```swift
init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.id = try container.decode(UUID.self, forKey: .id)
    self.repoId = try container.decode(UUID.self, forKey: .repoId)
    self.name = try container.decode(String.self, forKey: .name)
    self.path = try container.decode(URL.self, forKey: .path)
    self.isMainWorktree = try container.decode(Bool.self, forKey: .isMainWorktree)
}
```

All five fields are now required. No `decodeIfPresent`, no fabrication.

**Step 4: Run test — expect PASS**

```bash
swift test --build-path ".build-agent-t1" --filter "decode_missingRepoId_throws"
```

**Step 5: Run full suite to find any tests that relied on optional decode**

```bash
swift test --build-path ".build-agent-t1" --filter "Worktree"
```

Fix any tests that constructed JSON without `repoId` or `isMainWorktree`. All test JSON fixtures must include every field.

**Step 6: Verify full build**

```bash
swift test --build-path ".build-agent-t1" 2>&1 | tail -5
```

---

### Task 2: Route Repo Removal Through the Coordinator

**Why now:** This is the highest-severity bug. User-initiated repo removal (`removeRepoRequested`) skips cache cleanup and forge unregistration entirely.

**Files:**
- Modify: `Sources/AgentStudio/App/AppDelegate.swift` — `removeRepoRequested` handler
- Modify: `Sources/AgentStudio/App/WorkspaceCacheCoordinator.swift` — add `handleRepoRemoval` that does full cleanup then hard-deletes
- Modify: `Tests/AgentStudioTests/App/WorkspaceCacheCoordinatorTests.swift`

**Step 1: Write failing test — user removal triggers cache + forge cleanup**

Add to `WorkspaceCacheCoordinatorTests.swift`:

```swift
@Test
func removeRepo_cleansUpCacheAndForgeScope() async {
    let workspaceStore = makeWorkspaceStore()
    let repoCache = WorkspaceRepoCache()
    let recordedScopeChanges = RecordedScopeChanges()
    let coordinator = WorkspaceCacheCoordinator(
        bus: EventBus<RuntimeEnvelope>(),
        workspaceStore: workspaceStore,
        repoCache: repoCache,
        scopeSyncHandler: { change in
            await recordedScopeChanges.record(change)
        }
    )

    let repoPath = URL(fileURLWithPath: "/tmp/removal-test-repo")
    let repo = workspaceStore.addRepo(at: repoPath)
    let worktreeId = repo.worktrees.first!.id

    // Seed cache with enrichment data
    repoCache.setRepoEnrichment(.unresolved(repoId: repo.id))
    repoCache.setWorktreeEnrichment(
        WorktreeEnrichment(worktreeId: worktreeId, repoId: repo.id, branch: "main")
    )
    repoCache.setPullRequestCount(3, for: worktreeId)

    // User-initiated removal
    coordinator.handleRepoRemoval(repoId: repo.id)

    // Repo should be hard-deleted from store
    #expect(workspaceStore.repos.isEmpty)

    // All cache entries should be pruned
    #expect(repoCache.repoEnrichmentByRepoId[repo.id] == nil)
    #expect(repoCache.worktreeEnrichmentByWorktreeId[worktreeId] == nil)
    #expect(repoCache.pullRequestCountByWorktreeId[worktreeId] == nil)

    // Forge scope should be unregistered
    let converged = await eventually("forge unregister should fire") {
        let changes = await recordedScopeChanges.values
        return changes.contains {
            if case .unregisterForgeRepo(let id) = $0 { return id == repo.id }
            return false
        }
    }
    #expect(converged)
}
```

**Step 2: Run test — expect FAIL (method doesn't exist yet)**

```bash
swift test --build-path ".build-agent-t2" --filter "removeRepo_cleansUpCacheAndForgeScope"
```

**Step 3: Implement `handleRepoRemoval` on WorkspaceCacheCoordinator**

Add to `WorkspaceCacheCoordinator.swift`:

```swift
/// Full repo removal: cache cleanup, forge unregister, then hard-delete from store.
/// This is the user-initiated removal path — harder than `.repoRemoved` topology
/// which only soft-deletes (marks unavailable).
func handleRepoRemoval(repoId: UUID) {
    guard let repo = workspaceStore.repos.first(where: { $0.id == repoId }) else { return }

    // 1. Prune all worktree-level cache entries for this repo
    for worktree in repo.worktrees {
        repoCache.removeWorktree(worktree.id)
    }

    // 2. Prune repo-level cache
    repoCache.removeRepo(repoId)

    // 3. Unregister from forge scope
    Task { [weak self] in
        await self?.syncScope(.unregisterForgeRepo(repoId: repoId))
    }

    // 4. Hard-delete from store (removes from repos array + persistence)
    workspaceStore.removeRepo(repoId)
}
```

**Step 4: Wire AppDelegate to use the new method**

In `AppDelegate.swift`, change the `removeRepoRequested` handler:

```swift
// Before:
case .removeRepoRequested(let repoId):
    self.store.removeRepo(repoId)
    self.paneCoordinator.syncFilesystemRootsAndActivity()

// After:
case .removeRepoRequested(let repoId):
    self.workspaceCacheCoordinator.handleRepoRemoval(repoId: repoId)
    self.paneCoordinator.syncFilesystemRootsAndActivity()
```

**Step 5: Run test — expect PASS**

```bash
swift test --build-path ".build-agent-t2" --filter "removeRepo_cleansUpCacheAndForgeScope"
```

**Step 6: Write test — removal of unknown repoId is a no-op**

```swift
@Test
func removeRepo_unknownRepoId_isNoOp() {
    let workspaceStore = makeWorkspaceStore()
    let repoCache = WorkspaceRepoCache()
    let coordinator = WorkspaceCacheCoordinator(
        bus: EventBus<RuntimeEnvelope>(),
        workspaceStore: workspaceStore,
        repoCache: repoCache,
        scopeSyncHandler: { _ in }
    )

    // Should not crash or mutate anything
    coordinator.handleRepoRemoval(repoId: UUID())
    #expect(workspaceStore.repos.isEmpty)
}
```

**Step 7: Run focused tests**

```bash
swift test --build-path ".build-agent-t2" --filter "WorkspaceCacheCoordinator"
```

---

### Task 3: Fix Unavailable Repos Getting Stuck on Re-Add

**Why now:** Depends on removal working correctly (Task 2). The guard in `addRepoIfNeeded` blocks re-adding paths that belong to unavailable repos.

**Files:**
- Modify: `Sources/AgentStudio/App/AppDelegate.swift` — `addRepoIfNeeded` guard
- Add test: `Tests/AgentStudioTests/App/WorkspaceCacheCoordinatorTests.swift`

**Step 1: Write failing test — re-adding an unavailable repo's worktree path should reassociate**

```swift
@Test
func topology_repoDiscovered_unavailableRepo_reassociates() {
    let workspaceStore = makeWorkspaceStore()
    let repoCache = WorkspaceRepoCache()
    let coordinator = WorkspaceCacheCoordinator(
        bus: EventBus<RuntimeEnvelope>(),
        workspaceStore: workspaceStore,
        repoCache: repoCache,
        scopeSyncHandler: { _ in }
    )

    let repoPath = URL(fileURLWithPath: "/tmp/unavailable-repo")
    let repo = workspaceStore.addRepo(at: repoPath)
    workspaceStore.markRepoUnavailable(repo.id)
    #expect(workspaceStore.isRepoUnavailable(repo.id))

    // Re-discover same path — should clear unavailable
    coordinator.handleTopology(
        SystemEnvelope.test(
            event: .topology(.repoDiscovered(repoPath: repoPath, parentPath: repoPath.deletingLastPathComponent()))
        )
    )

    #expect(!workspaceStore.isRepoUnavailable(repo.id))
    #expect(workspaceStore.repos.count == 1)
    #expect(workspaceStore.repos[0].id == repo.id)
}
```

This test should already pass (the coordinator's `.repoDiscovered` handler has the `isRepoUnavailable` → `reassociateRepo` path). Run it to confirm.

**Step 2: Write the real failing test — the AppDelegate-level guard blocks unavailable worktrees**

This test verifies the *guard logic* in `addRepoIfNeeded`. Since `addRepoIfNeeded` is a private method on AppDelegate and hard to unit-test directly, we test the guard condition in isolation:

```swift
@Test
func addRepoGuard_unavailableRepoWorktree_shouldNotBlock() {
    let workspaceStore = makeWorkspaceStore()
    let repoPath = URL(fileURLWithPath: "/tmp/stuck-repo")
    let repo = workspaceStore.addRepo(at: repoPath)
    workspaceStore.markRepoUnavailable(repo.id)

    // The guard should NOT match unavailable repos
    let normalizedPath = repoPath.standardizedFileURL
    let isKnownAvailableWorktree = workspaceStore.repos.contains { repo in
        !workspaceStore.isRepoUnavailable(repo.id)
            && repo.worktrees.contains { $0.path.standardizedFileURL == normalizedPath }
    }
    #expect(!isKnownAvailableWorktree)
}
```

**Step 3: Fix the guard in `addRepoIfNeeded`**

In `AppDelegate.swift`:

```swift
// Before:
let isKnownWorktree = store.repos.contains { repo in
    repo.worktrees.contains { $0.path.standardizedFileURL == normalizedPath }
}

// After:
let isKnownWorktree = store.repos.contains { repo in
    !store.isRepoUnavailable(repo.id)
        && repo.worktrees.contains { $0.path.standardizedFileURL == normalizedPath }
}
```

**Step 4: Run all coordinator tests**

```bash
swift test --build-path ".build-agent-t3" --filter "WorkspaceCacheCoordinator"
```

---

### Task 4: Priority-Aware Filesystem Registration

**Why now:** All lifecycle paths are correct from Tasks 1-3. Now we can optimize the registration order without worrying about correctness bugs.

**Files:**
- Modify: `Sources/AgentStudio/App/PaneCoordinator+FilesystemSource.swift` — `sortWorktreeIds` → priority sort
- Modify: `Tests/AgentStudioTests/App/PaneCoordinatorTests.swift`

**Step 1: Understand the current sort**

`PaneCoordinator+FilesystemSource.swift` line 155:
```swift
nonisolated private static func sortWorktreeIds(_ lhs: UUID, _ rhs: UUID) -> Bool {
    lhs.uuidString < rhs.uuidString
}
```

This UUID-string sort is used for both registration (line 88) and activity sync (line 107). It's deterministic but ignores active-pane relevance.

**Step 2: Change sort to prioritize active-pane worktree**

The method `syncFilesystemRootsAndActivity` already computes `activePaneWorktreeId` (line 48). Pass it into the sort:

Replace the `sortWorktreeIds` helper and its call sites. In the registration loop (line 88-90):

```swift
// Before:
let desiredContextEntries = desiredContextsByWorktreeId.sorted { lhs, rhs in
    Self.sortWorktreeIds(lhs.key, rhs.key)
}

// After:
let desiredContextEntries = desiredContextsByWorktreeId.sorted { lhs, rhs in
    Self.sortWorktreeByPriority(
        lhs.key, rhs.key, activePaneWorktreeId: activePaneWorktreeId
    )
}
```

Same for the activity loop (line 107-109).

New sort method:

```swift
nonisolated private static func sortWorktreeByPriority(
    _ lhs: UUID, _ rhs: UUID, activePaneWorktreeId: UUID?
) -> Bool {
    let lhsActive = lhs == activePaneWorktreeId
    let rhsActive = rhs == activePaneWorktreeId
    if lhsActive != rhsActive { return lhsActive }
    return lhs.uuidString < rhs.uuidString
}
```

**Step 3: Write test**

```swift
@Test
func sortWorktreeByPriority_activePaneFirst() {
    let active = UUID()
    let other1 = UUID()
    let other2 = UUID()
    let ids = [other1, active, other2]

    let sorted = ids.sorted {
        PaneCoordinator.sortWorktreeByPriority($0, $1, activePaneWorktreeId: active)
    }

    #expect(sorted.first == active)
}
```

Note: `sortWorktreeByPriority` is `private` — either make it `internal` for testing, or test it indirectly through `syncFilesystemRootsAndActivity` behavior. Prefer the indirect approach if there's already a sync test harness.

**Step 4: Run tests**

```bash
swift test --build-path ".build-agent-t4" --filter "PaneCoordinator"
```

**Step 5: Verify full suite**

```bash
mise run test
```

---

### Task 5: Integration Tests — Full Repo Lifecycle Through Event Pipeline

**Why last:** All fixes are in place. These tests prove the end-to-end lifecycle works.

**Files:**
- Modify: `Tests/AgentStudioTests/App/WorkspaceCacheCoordinatorTests.swift`

**Step 1: Add full lifecycle integration test — add, enrich, remove**

```swift
@Test
func integration_fullRepoLifecycle_addEnrichRemove() async {
    let bus = EventBus<RuntimeEnvelope>()
    let workspaceStore = makeWorkspaceStore()
    let repoCache = WorkspaceRepoCache()
    let recordedScopeChanges = RecordedScopeChanges()
    let coordinator = WorkspaceCacheCoordinator(
        bus: bus,
        workspaceStore: workspaceStore,
        repoCache: repoCache,
        scopeSyncHandler: { change in
            await recordedScopeChanges.record(change)
        }
    )
    let projector = GitWorkingDirectoryProjector(
        bus: bus,
        gitWorkingTreeProvider: .stub { _ in
            GitWorkingTreeStatus(
                summary: GitWorkingTreeSummary(changed: 0, staged: 0, untracked: 0),
                branch: "main",
                origin: "git@github.com:askluna/agent-studio.git"
            )
        },
        coalescingWindow: .zero
    )

    coordinator.startConsuming()
    await projector.start()
    defer {
        coordinator.stopConsuming()
    }

    // Phase 1: Discover repo
    let repoPath = URL(fileURLWithPath: "/tmp/lifecycle-test-repo")
    coordinator.handleTopology(
        SystemEnvelope.test(
            event: .topology(.repoDiscovered(repoPath: repoPath, parentPath: repoPath.deletingLastPathComponent()))
        )
    )
    #expect(workspaceStore.repos.count == 1)
    let repo = workspaceStore.repos[0]

    // Phase 2: Register worktree → triggers enrichment via projector
    let worktreeId = UUID()
    _ = await bus.post(
        .system(
            SystemEnvelope.test(
                event: .topology(
                    .worktreeRegistered(worktreeId: worktreeId, repoId: repo.id, rootPath: repoPath)
                ),
                source: .builtin(.filesystemWatcher)
            )
        )
    )

    let enriched = await eventually("enrichment should resolve") {
        guard case .some(.resolved(_, _, let identity, _)) = repoCache.repoEnrichmentByRepoId[repo.id] else {
            return false
        }
        return identity.groupKey == "remote:askluna/agent-studio"
    }
    #expect(enriched)
    #expect(repoCache.worktreeEnrichmentByWorktreeId[worktreeId]?.branch == "main")

    // Phase 3: User removes repo
    coordinator.handleRepoRemoval(repoId: repo.id)

    // Repo gone
    #expect(workspaceStore.repos.isEmpty)

    // Cache fully pruned
    #expect(repoCache.repoEnrichmentByRepoId[repo.id] == nil)
    #expect(repoCache.worktreeEnrichmentByWorktreeId[worktreeId] == nil)

    // Forge unregistered
    let unregistered = await eventually("forge unregister should fire") {
        let changes = await recordedScopeChanges.values
        return changes.contains {
            if case .unregisterForgeRepo(let id) = $0 { return id == repo.id }
            return false
        }
    }
    #expect(unregistered)

    await projector.shutdown()
}
```

**Step 2: Add test — unavailable repo re-add lifecycle**

```swift
@Test
func integration_unavailableRepoReAdd_clearsUnavailableState() async {
    let workspaceStore = makeWorkspaceStore()
    let repoCache = WorkspaceRepoCache()
    let coordinator = WorkspaceCacheCoordinator(
        bus: EventBus<RuntimeEnvelope>(),
        workspaceStore: workspaceStore,
        repoCache: repoCache,
        scopeSyncHandler: { _ in }
    )

    // Setup: add repo, mark unavailable (simulating filesystem disappearance)
    let repoPath = URL(fileURLWithPath: "/tmp/re-add-test-repo")
    let repo = workspaceStore.addRepo(at: repoPath)
    workspaceStore.markRepoUnavailable(repo.id)
    #expect(workspaceStore.isRepoUnavailable(repo.id))

    // User re-adds the same path
    coordinator.handleTopology(
        SystemEnvelope.test(
            event: .topology(.repoDiscovered(repoPath: repoPath, parentPath: repoPath.deletingLastPathComponent()))
        )
    )

    // Should be available again, same ID, enrichment seeded
    #expect(!workspaceStore.isRepoUnavailable(repo.id))
    #expect(workspaceStore.repos.count == 1)
    #expect(workspaceStore.repos[0].id == repo.id)
    #expect(repoCache.repoEnrichmentByRepoId[repo.id] == .unresolved(repoId: repo.id))
}
```

**Step 3: Run all tests**

```bash
mise run test
```

Expected: all pass. Record pass/fail counts.

**Step 4: Run dangling reference grep**

```bash
# Verify no direct store.removeRepo calls outside coordinator
grep -rn "store\.removeRepo\|\.removeRepo(" Sources/AgentStudio/App/ --include="*.swift"
```

Expected: only `WorkspaceCacheCoordinator.handleRepoRemoval` contains `removeRepo`. AppDelegate should have zero direct calls.

---

### Task 6: Remove Legacy Canonical State Decode

**Why now:** All lifecycle fixes are stable. This eliminates the dead `[Repo]` migration path from `PersistableState.init(from:)`. Greenfield project — no legacy workspace files exist.

**Files:**
- Modify: `Sources/AgentStudio/Core/Stores/WorkspacePersistor.swift` — `PersistableState.init(from:)`
- Modify: `Tests/AgentStudioTests/Core/Stores/WorkspacePersistorTests.swift`

**Step 1: Write failing test — JSON missing `worktrees` key returns `.corrupt`**

Add to `WorkspacePersistorTests.swift`:

```swift
@Test
func test_load_canonicalState_missingWorktrees_returnsCorrupt() throws {
    let id = UUID()
    let json = """
    {
        "schemaVersion": 1,
        "id": "\(id.uuidString)",
        "name": "Test",
        "repos": [],
        "unavailableRepoIds": [],
        "panes": [],
        "tabs": [],
        "sidebarWidth": 250,
        "createdAt": 0,
        "updatedAt": 0
    }
    """
    let fileURL = tempDir.appending(path: "\(id.uuidString).workspace.state.json")
    try Data(json.utf8).write(to: fileURL, options: .atomic)
    #expect(persistor.load().isCorrupt)
}
```

**Step 2: Run test — expect FAIL (currently decodes with empty worktrees via legacy fallback)**

```bash
swift test --build-path ".build-agent-t6" --filter "test_load_canonicalState_missingWorktrees_returnsCorrupt"
```

Expected: FAIL — the legacy fallback path reconstructs worktrees from `legacyRepos` or defaults to `[]`.

**Step 3: Delete the custom `init(from decoder:)` on PersistableState**

In `WorkspacePersistor.swift`, remove the entire `init(from decoder: Decoder) throws` block (lines 67-123). The auto-synthesized `Codable` conformance will make all non-optional fields required and decode optionals (`activeTabId: UUID?`, `windowFrame: CGRect?`) from `null` correctly.

Remove this block entirely:

```swift
init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    // ... entire legacy decode block (lines 67-123)
}
```

The auto-synthesized decoder replaces it. All fields are strict. `activeTabId` and `windowFrame` are already `UUID?` and `CGRect?` — the synthesized decoder handles `null` for these.

**Step 4: Write test — JSON missing `schemaVersion` returns `.corrupt`**

```swift
@Test
func test_load_canonicalState_missingSchemaVersion_returnsCorrupt() throws {
    let id = UUID()
    let json = """
    {
        "id": "\(id.uuidString)",
        "name": "Test",
        "repos": [],
        "worktrees": [],
        "unavailableRepoIds": [],
        "panes": [],
        "tabs": [],
        "sidebarWidth": 250,
        "createdAt": 0,
        "updatedAt": 0
    }
    """
    let fileURL = tempDir.appending(path: "\(id.uuidString).workspace.state.json")
    try Data(json.utf8).write(to: fileURL, options: .atomic)
    #expect(persistor.load().isCorrupt)
}
```

**Step 5: Run tests — expect PASS**

```bash
swift test --build-path ".build-agent-t6" --filter "WorkspacePersistor"
```

Fix any round-trip tests that break. All existing round-trip tests should still pass because the encoder writes all fields.

**Step 6: Verify existing round-trip tests still pass**

```bash
swift test --build-path ".build-agent-t6" --filter "WorkspacePersistor"
```

---

### Task 7: Harden Cache and UI Decode — Strict Fields, Throw Away Corrupt

**Why last for persistence:** Independent of canonical state. Cache and UI files are rebuildable. Corrupt cache → discard and rebuild from events. Corrupt UI → discard and use defaults. Boot code already handles `.corrupt` for both.

**Files:**
- Modify: `Sources/AgentStudio/Core/Stores/WorkspacePersistor.swift` — `PersistableCacheState` and `PersistableUIState`
- Modify: `Tests/AgentStudioTests/Core/Stores/WorkspacePersistorTests.swift`

**Step 1: Write failing test — cache JSON missing `repoEnrichmentByRepoId` returns `.corrupt`**

```swift
@Test
func test_loadCache_missingRequiredField_returnsCorrupt() throws {
    let workspaceId = UUID()
    let json = """
    {
        "schemaVersion": 1,
        "workspaceId": "\(workspaceId.uuidString)",
        "worktreeEnrichmentByWorktreeId": {},
        "pullRequestCountByWorktreeId": {},
        "notificationCountByWorktreeId": {},
        "sourceRevision": 0
    }
    """
    let cacheURL = tempDir.appending(path: "\(workspaceId.uuidString).workspace.cache.json")
    try Data(json.utf8).write(to: cacheURL, options: .atomic)
    #expect(persistor.loadCache(for: workspaceId).isCorrupt)
}
```

**Step 2: Run test — expect FAIL (currently silently defaults to `[:]`)**

```bash
swift test --build-path ".build-agent-t7" --filter "test_loadCache_missingRequiredField_returnsCorrupt"
```

**Step 3: Delete custom decoders from PersistableCacheState and PersistableUIState**

In `WorkspacePersistor.swift`:

1. Delete `PersistableCacheState.init(from decoder:)` (lines 167-186) — the entire custom decoder.
2. Delete the `private enum CodingKeys` on `PersistableCacheState` (lines 137-146) — redundant since property names match JSON keys.
3. Delete `PersistableUIState.init(from decoder:)` (lines 213-231) — the entire custom decoder.

Auto-synthesized Codable replaces all three. All non-optional fields become required. `lastRebuiltAt: Date?` decodes `null` correctly.

**Step 4: Write test — UI JSON missing `expandedGroups` returns `.corrupt`**

```swift
@Test
func test_loadUI_missingRequiredField_returnsCorrupt() throws {
    let workspaceId = UUID()
    let json = """
    {
        "schemaVersion": 1,
        "workspaceId": "\(workspaceId.uuidString)",
        "checkoutColors": {},
        "filterText": "",
        "isFilterVisible": false
    }
    """
    let uiURL = tempDir.appending(path: "\(workspaceId.uuidString).workspace.ui.json")
    try Data(json.utf8).write(to: uiURL, options: .atomic)
    #expect(persistor.loadUI(for: workspaceId).isCorrupt)
}
```

**Step 5: Run all persistor tests**

```bash
swift test --build-path ".build-agent-t7" --filter "WorkspacePersistor"
```

**Step 6: Full verification**

```bash
mise run test
```

---

## Verification Checklist (use after ALL tasks complete)

- [ ] `mise run build` — zero errors
- [ ] `mise run test` — all tests pass, show pass/fail counts
- [ ] `mise run lint` — only pre-existing violations (GitWorkingDirectoryProjectorTests file/type length)
- [ ] `mise run format` — zero issues
- [ ] No `decodeIfPresent` on `repoId` or `isMainWorktree` in `Worktree.swift`
- [ ] No direct `store.removeRepo` calls in `AppDelegate.swift`
- [ ] Unavailable repo re-add clears unavailable state (verified by test)
- [ ] Repo removal prunes cache + forge scope (verified by test)
- [ ] Full lifecycle test passes: add → enrich → remove → verify cleanup
- [ ] No custom `init(from decoder:)` on `PersistableState` (auto-synthesized Codable)
- [ ] No custom `init(from decoder:)` on `PersistableCacheState` (auto-synthesized Codable)
- [ ] No custom `init(from decoder:)` on `PersistableUIState` (auto-synthesized Codable)
- [ ] No `decodeIfPresent` anywhere in `WorkspacePersistor.swift`
- [ ] Cache JSON missing a required field → `.corrupt` (verified by test)
- [ ] UI JSON missing a required field → `.corrupt` (verified by test)

## File Impact Summary

| File | Task | Change |
|------|------|--------|
| `Core/Models/Worktree.swift` | 1 | `decodeIfPresent` → `decode` for repoId + isMainWorktree |
| `App/WorkspaceCacheCoordinator.swift` | 2 | Add `handleRepoRemoval` — full cleanup then hard-delete |
| `App/AppDelegate.swift` | 2, 3 | Route removal through coordinator; fix unavailable guard |
| `App/PaneCoordinator+FilesystemSource.swift` | 4 | Priority sort by active-pane worktree |
| `Core/Stores/WorkspacePersistor.swift` | 6, 7 | Delete all custom decoders; auto-synthesized strict Codable |
| `Tests/.../WorkspaceCacheCoordinatorTests.swift` | 1-5 | New tests for decode, removal, re-add, lifecycle |
| `Tests/.../WorktreeModelTests.swift` | 1 | Test decode failure on missing repoId |
| `Tests/.../PaneCoordinatorTests.swift` | 4 | Test priority sort |
| `Tests/.../WorkspacePersistorTests.swift` | 6, 7 | Negative tests for missing required fields |
