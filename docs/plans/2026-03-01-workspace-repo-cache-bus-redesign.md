# Workspace Repo Cache & Bus Redesign — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Unify all repo/worktree data flows through the RuntimeEventBus, slim the Worktree model to structure-only, rename WorkspaceCacheStore → WorkspaceRepoCache, remove unearned AgentType, and make topology handlers idempotent.

**Architecture:** Three stores with clear separation: WorkspaceStore (canonical associations, persisted), WorkspaceRepoCache (derived enrichment, rebuildable), WorkspaceUIStore (presentation prefs). All topology changes emit events on the RuntimeEventBus. WorkspaceCacheCoordinator consumes events and updates both stores. Sidebar reads store.repos for structure, cache for enrichment. Boot replays topology events with active-pane priority.

**Tech Stack:** Swift 6, SwiftUI, @Observable, AsyncStream (RuntimeEventBus), Swift Testing framework

---

## Strict Ordering Rationale

Tasks are ordered so the codebase **compiles after each task**. The strategy:
1. First: slim models and rename types (foundation changes)
2. Second: fix stores and coordinator to use new models
3. Third: fix event producers (AppDelegate, boot)
4. Fourth: fix consumers (sidebar, command bar)
5. Last: verification pass

Each task has a verification step. Do not proceed to the next task until verification passes.

## Clean Break Rules

This is NOT a gradual migration. No backward compatibility, no deprecated wrappers, no legacy affordances:
- **No `Worktree.branch`** — removed, not deprecated. All branch display comes from `WorktreeEnrichment.branch` via cache.
- **No `Worktree.status`** — removed entirely. `WorktreeStatus` enum deleted.
- **No `AgentType`** — removed from Worktree, Pane, PaneMetadata, Templates. Deleted entirely.
- **No `WorkspaceCacheStore`** — renamed to `WorkspaceRepoCache`. Zero references to old name.
- **Persistence migration** — `WorkspacePersistor` must read old workspace.json files that have `branch`/`status`/`agent` in Worktree payloads. Use `decodeIfPresent` to tolerate missing fields. Never write them back. The canonical persistence shape is `CanonicalWorktree` (already has repoId, no branch/status/agent).
- **No workaround variables** — no `_unused`, no `// removed`, no re-exports. If it's gone, it's gone.

## Idempotency Contract

All topology handlers in WorkspaceCacheCoordinator MUST be idempotent:
- **Dedup key for repos:** `stableKey` (SHA-256 of repoPath). Same path = same repo, no duplicates.
- **Dedup key for worktrees:** `worktreeId` (UUID). Same ID = upsert, not append.
- **Ordering tolerance:** `worktreeRegistered` before `repoDiscovered` = safe no-op (guard + return). No crash, no queue.
- **Boot replay safety:** Emitting topology events for already-restored repos does NOT create duplicates.

## Producer Allowlist (Convention)

Only these may emit canonical topology events (`.repoDiscovered`, `.repoRemoved`):
- `AppDelegate` — user "Add Folder" and boot replay
- Future: any topology coordinator

Runtime actors (`FilesystemActor`, `GitProjector`, `ForgeActor`) emit observation/enrichment events only (`.worktreeRegistered`, `.snapshotChanged`, `.originChanged`, etc.).

---

### Task 1: Slim Worktree Model — Remove branch, status, agent; Add repoId FK

**Why first:** Every downstream file references Worktree. Changing the model first forces all call sites to update, which prevents partial fixes.

**Files:**
- Modify: `Sources/AgentStudio/Core/Models/Worktree.swift`
- Delete contents within: `WorktreeStatus` enum, `AgentType` enum (from Worktree.swift)
- Modify: `Tests/AgentStudioTests/Helpers/ModelFactories.swift`
- Modify: `Tests/AgentStudioTests/Core/Models/WorktreeModelTests.swift`

**Step 1: Modify Worktree struct**

Remove `branch`, `status`, `agent` fields. Add `repoId: UUID` FK. Remove `WorktreeStatus` enum entirely. Keep `AgentType` enum in this file for now (moved/removed in Task 2).

New Worktree:
```swift
struct Worktree: Codable, Identifiable, Hashable {
    let id: UUID
    let repoId: UUID
    var name: String
    var path: URL
    var isMainWorktree: Bool

    var stableKey: String { StableKey.fromPath(path) }

    init(
        id: UUID = UUID(),
        repoId: UUID,
        name: String,
        path: URL,
        isMainWorktree: Bool = false
    ) {
        self.id = id
        self.repoId = repoId
        self.name = name
        self.path = path
        self.isMainWorktree = isMainWorktree
    }
}
```

Remove `WorktreeStatus` enum entirely from this file. Keep `AgentType` for now.

**Step 2: Update ModelFactories.swift**

```swift
func makeWorktree(
    id: UUID = UUID(),
    repoId: UUID = UUID(),
    name: String = "feature-branch",
    path: String = "/tmp/test-repo/feature-branch",
    isMainWorktree: Bool = false
) -> Worktree {
    Worktree(
        id: id,
        repoId: repoId,
        name: name,
        path: URL(fileURLWithPath: path),
        isMainWorktree: isMainWorktree
    )
}
```

Remove `agent` and `status` params from `makeWorktree`. Remove `agent` param from `makePane`.

**Step 3: Update WorktreeModelTests.swift**

Rewrite tests to match slimmed model. Remove tests for status, agent, branch encoding/decoding. Add test for repoId FK.

**Step 4: Fix all compilation errors from Worktree constructor changes**

This will cascade to many files. For each file that fails to compile:

| File | Change |
|------|--------|
| `WorkspaceCacheCoordinator.swift:103-110` | Add `repoId` to Worktree constructor |
| `WorkspaceStore.swift` (reconcileDiscoveredWorktrees, addRepo, runtimeRepos) | Remove branch/status/agent from Worktree construction, add repoId |
| `WorkspacePersistor.swift` (runtimeRepos) | Remove branch/status from Worktree construction, add repoId from CanonicalWorktree.repoId |
| `WorktrunkService.swift` (~6 Worktree constructors) | Remove branch param, add repoId (use a placeholder UUID for now — WorktrunkService will need a repoId param or return a different type) |
| `FilesystemActor.swift` | Update any Worktree construction |
| `PaneCoordinator+FilesystemSource.swift` | Update worktree context building |
| `PaneCoordinator+ActionExecution.swift` | Remove agent/status refs if present |
| `CommandBarDataSource.swift:570,572,608` | Remove `worktree.branch` refs → use enrichment. Remove `worktree.agent?.color` → use nil or pane.agent |
| `DynamicViewProjector.swift` | Remove `byAgentType` case and `groupByAgentType()` method entirely |
| `DynamicView.swift` | Remove `byAgentType` case from `DynamicViewType` enum entirely |
| All test files with Worktree(...) constructors | Update to new signature |

**Step 5: Verify**

```bash
mise run build
```
Expected: compiles with zero errors. Tests may fail — that's OK, we fix them in the next step.

```bash
mise run test
```
Expected: note which tests fail. These are expected from the model change. Fix test assertions that reference removed fields.

**Step 6: Commit**

```bash
git add -A && git commit -m "refactor: slim Worktree model — remove branch/status/agent, add repoId FK"
```

---

### Task 2: Remove AgentType Entirely

**Why now:** AgentType is unearned — no runtime populates it. Removing it after Task 1 (which already removed it from Worktree) cleans the remaining references.

**Files:**
- Remove: `AgentType` enum from `Worktree.swift`
- Modify: `Sources/AgentStudio/Core/Models/Pane.swift` — remove `agent` property
- Modify: `Sources/AgentStudio/Core/PaneRuntime/Contracts/PaneMetadata.swift` — remove `agentType` field
- Modify: `Sources/AgentStudio/Core/Models/Templates.swift` — remove `agent` from TerminalTemplate
- Modify: `Sources/AgentStudio/Core/Models/DynamicView.swift` — remove `byAgentType` case
- Modify: `Sources/AgentStudio/Core/Stores/DynamicViewProjector.swift` — remove `groupByAgentType`
- Modify: `Sources/AgentStudio/Features/CommandBar/CommandBarDataSource.swift` — remove `pane.agent` refs
- Modify: `Tests/AgentStudioTests/Helpers/ModelFactories.swift` — remove agent from makePane
- Ripple: all test files referencing AgentType

**Step 1: Remove AgentType enum from Worktree.swift**

Delete the entire `AgentType` enum (lines 77-123 in original).

**Step 2: Remove agent from Pane**

In `Pane.swift`, remove:
- `var agent: AgentType?` computed property (lines 118-121)

**Step 3: Remove agentType from PaneMetadata**

In `PaneMetadata.swift`, remove:
- `private(set) var agentType: AgentType?` field
- `mutating func updateAgentType(_ newAgentType: AgentType?)` method
- `agentType` from init, CodingKeys, encode/decode
- Remove the `init(from decoder:)` reference to agentType — make it decode gracefully (ignore unknown field)

**Step 4: Remove agent from Templates**

In `Templates.swift`, remove `agent: AgentType?` from `TerminalTemplate`. Remove `agentType: agent` from `instantiate()`.

**Step 5: Remove byAgentType from DynamicView**

In `DynamicView.swift`, remove `case byAgentType` from `DynamicViewType` enum and its `displayName`.
In `DynamicViewProjector.swift`, remove `case .byAgentType` handling and `groupByAgentType()` method.

**Step 6: Fix CommandBarDataSource**

Replace all `pane.agent?.color` with `nil`. Remove `worktree.agent?.color` with `nil`. Remove agent keyword from `keywordsForPane`.

**Step 7: Fix test factories and test files**

Update `makePane` to remove agent param. Fix all test files that reference AgentType.

**Step 8: Verify**

```bash
mise run build
mise run test
```
Expected: compiles, all tests pass.

**Step 9: Commit**

```bash
git add -A && git commit -m "refactor: remove AgentType — unearned, no runtime populates it"
```

---

### Task 3: Rename WorkspaceCacheStore → WorkspaceRepoCache

**Why now:** Pure rename with no logic changes. Do it before modifying coordinator/sidebar to avoid merge conflicts.

**Files:**
- Rename: `Sources/AgentStudio/Core/Stores/WorkspaceCacheStore.swift` → keep file, rename class
- Rename: `Tests/AgentStudioTests/Core/Stores/WorkspaceCacheStoreTests.swift` → update class name
- Update all references in:
  - `Sources/AgentStudio/App/WorkspaceCacheCoordinator.swift`
  - `Sources/AgentStudio/App/AppDelegate.swift`
  - `Sources/AgentStudio/App/MainSplitViewController.swift`
  - `Sources/AgentStudio/App/MainWindowController.swift`
  - `Sources/AgentStudio/Features/Sidebar/RepoSidebarContentView.swift`
  - All test files referencing WorkspaceCacheStore

**Step 1: Rename class in source file**

In `WorkspaceCacheStore.swift`: change `class WorkspaceCacheStore` → `class WorkspaceRepoCache`. Update doc comment.

**Step 2: Rename file**

Rename `WorkspaceCacheStore.swift` → `WorkspaceRepoCache.swift`
Rename `WorkspaceCacheStoreTests.swift` → `WorkspaceRepoCacheTests.swift`

**Step 3: Find-and-replace all references**

`WorkspaceCacheStore` → `WorkspaceRepoCache` across all files. Also update variable names: `cacheStore` → `repoCache` where it refers to this type.

**Step 4: Verify**

```bash
mise run build
mise run test
```
Expected: compiles, all tests pass. This is a pure rename — no behavior change.

**Step 5: Commit**

```bash
git add -A && git commit -m "refactor: rename WorkspaceCacheStore → WorkspaceRepoCache"
```

---

### Task 4: Make Topology Handlers Idempotent

**Why now:** Before we start emitting topology events from new places (boot, Add Folder), the handlers must be idempotent. Otherwise boot replay will create duplicate repos.

**Files:**
- Modify: `Sources/AgentStudio/App/WorkspaceCacheCoordinator.swift`
- Modify: `Sources/AgentStudio/Core/Stores/WorkspaceStore.swift` — ensure addRepo upserts by stableKey
- Add tests: `Tests/AgentStudioTests/App/WorkspaceCacheCoordinatorTests.swift`

**Step 1: Write failing tests for idempotency**

Add tests to `WorkspaceCacheCoordinatorTests.swift`:
- `test_repoDiscovered_duplicatePath_doesNotCreateSecondRepo` — emit `.repoDiscovered` twice for same path, assert only one repo exists
- `test_worktreeRegistered_duplicateId_doesNotCreateSecondWorktree` — emit `.worktreeRegistered` twice for same worktreeId, assert only one worktree
- `test_repoDiscovered_afterRestore_upsertsNotAppends` — restore a repo from persistence, then emit `.repoDiscovered` for same path, assert repo count is still 1

**Step 2: Run tests to verify they fail**

```bash
SWIFT_BUILD_DIR=".build-agent-$(uuidgen | tr -dc 'a-z0-9' | head -c 8)" swift test --build-path "$SWIFT_BUILD_DIR" --filter "WorkspaceCacheCoordinator" > /tmp/test-output.txt 2>&1 && echo "PASS" || echo "FAIL"
```

**Step 3: Make handlers idempotent**

In `WorkspaceCacheCoordinator.handleTopology()`:
- `.repoDiscovered`: check `workspaceStore.repos.contains { $0.repoPath == repoPath || $0.stableKey == StableKey.fromPath(repoPath) }` before adding. If exists, just ensure enrichment is set.
- `.worktreeRegistered`: check `worktrees.contains(where: { $0.id == worktreeId })` before appending (already partially done at line 101).

In `WorkspaceStore.addRepo()`:
- Check stableKey dedup, not just repoPath equality. Return existing repo if match found.

**Step 4: Run tests to verify they pass**

```bash
SWIFT_BUILD_DIR=".build-agent-$(uuidgen | tr -dc 'a-z0-9' | head -c 8)" swift test --build-path "$SWIFT_BUILD_DIR" --filter "WorkspaceCacheCoordinator" > /tmp/test-output.txt 2>&1 && echo "PASS" || echo "FAIL"
```

**Step 5: Verify full suite**

```bash
mise run test
```

**Step 6: Commit**

```bash
git add -A && git commit -m "fix: make topology handlers idempotent — dedup by stableKey/worktreeId"
```

---

### Task 5: Emit .repoDiscovered from AppDelegate (Add Folder Path)

**Why now:** With idempotent handlers in place, we can safely emit topology events from AppDelegate without fear of duplicates.

**Files:**
- Modify: `Sources/AgentStudio/App/AppDelegate.swift` — `addRepoIfNeeded()` emits `.repoDiscovered`
- Add tests: verify event is emitted and coordinator processes it

**Step 1: Write failing test**

Test that calling the Add Folder flow results in a `.repoDiscovered` event on the bus, and that the coordinator creates the repo AND sets enrichment to `.unresolved`.

**Step 2: Modify addRepoIfNeeded()**

After `store.addRepo(at:)`, emit the topology event:

```swift
func addRepoIfNeeded(_ path: URL) {
    let normalizedPath = path.standardizedFileURL
    // ... existing dedup checks ...
    let repo = store.addRepo(at: normalizedPath)

    // Emit topology event so coordinator + cache learn about it
    let envelope = RuntimeEnvelope.system(
        SystemEnvelope(
            source: .builtin(.filesystemWatcher),
            seq: 0,
            timestamp: Date(),
            event: .topology(.repoDiscovered(repoPath: normalizedPath, parentPath: normalizedPath.deletingLastPathComponent()))
        )
    )
    Task { await paneRuntimeBus.post(envelope) }

    paneCoordinator.syncFilesystemRootsAndActivity()
}
```

Note: Because the handler is idempotent (Task 4), the coordinator will see the repo already exists and just ensure enrichment is set.

**Step 3: Verify**

```bash
mise run build
mise run test
```

**Step 4: Commit**

```bash
git add -A && git commit -m "fix: emit .repoDiscovered from Add Folder flow"
```

---

### Task 6: Boot Topology Replay with Priority

**Why now:** The last missing event path. After boot restore, replay topology events so the coordinator validates and refreshes everything through the bus.

**Files:**
- Modify: `Sources/AgentStudio/App/AppDelegate.swift` — add boot replay in `triggerInitialTopologySync`
- Add tests: verify boot replay emits events in priority order (active panes first)

**Step 1: Write failing test**

Test that after `store.restore()`, the boot sequence emits `.repoDiscovered` for each persisted repo, with active-pane repos emitted first.

**Step 2: Implement boot replay**

In `executeBootStep(.triggerInitialTopologySync)`:

```swift
case .triggerInitialTopologySync:
    // Phase A: Active-pane repos first
    let activePaneWorktreeIds = store.activeTab?.paneIds
        .compactMap { store.panes[$0]?.worktreeId } ?? []
    let activeRepoIds = Set(activePaneWorktreeIds.compactMap { wtId in
        store.repos.first { $0.worktrees.contains { $0.id == wtId } }?.id
    })

    let prioritizedRepos = store.repos.sorted { a, b in
        let aActive = activeRepoIds.contains(a.id)
        let bActive = activeRepoIds.contains(b.id)
        if aActive != bActive { return aActive }
        return false
    }

    for repo in prioritizedRepos {
        let envelope = RuntimeEnvelope.system(
            SystemEnvelope(
                source: .builtin(.filesystemWatcher),
                seq: 0,
                timestamp: Date(),
                event: .topology(.repoDiscovered(repoPath: repo.repoPath, parentPath: repo.repoPath.deletingLastPathComponent()))
            )
        )
        Task { await paneRuntimeBus.post(envelope) }
    }

    paneCoordinator.syncFilesystemRootsAndActivity()
```

**Step 3: Add cache pruning on boot**

After loading cache from disk but before replay, prune entries for IDs that no longer exist in the restored store:

```swift
case .loadCacheStore:
    // ... existing cache load ...
    // Prune stale cache entries
    let validRepoIds = Set(store.repos.map(\.id))
    let validWorktreeIds = Set(store.repos.flatMap(\.worktrees).map(\.id))
    for repoId in repoCache.repoEnrichmentByRepoId.keys where !validRepoIds.contains(repoId) {
        repoCache.removeRepo(repoId)
    }
    for worktreeId in repoCache.worktreeEnrichmentByWorktreeId.keys where !validWorktreeIds.contains(worktreeId) {
        repoCache.removeWorktree(worktreeId)
    }
```

**Step 4: Verify**

```bash
mise run build
mise run test
```

**Step 5: Commit**

```bash
git add -A && git commit -m "feat: boot topology replay with active-pane priority + cache pruning"
```

---

### Task 7: Update Sidebar to Read Enrichment from Cache

**Why now:** All event paths are now working. Update the sidebar to use enrichment data from the renamed WorkspaceRepoCache consistently.

**Files:**
- Modify: `Sources/AgentStudio/Features/Sidebar/RepoSidebarContentView.swift`
- Modify: `Tests/AgentStudioTests/Features/Sidebar/RepoSidebarContentViewTests.swift`

**Step 1: Update store references**

The sidebar already reads `store.repos` for structure and `cacheStore` (now `repoCache`) for enrichment. Changes needed:
- Rename all `cacheStore` → `repoCache` references
- `resolvedBranchName()`: remove fallback to `worktree.branch` (it no longer exists). Only use `enrichment?.branch` or "detached HEAD".
- Remove any direct `worktree.branch` references (now gone from model)
- Remove any `worktree.agent` or `worktree.status` references

**Step 2: Update branch resolution**

```swift
static func resolvedBranchName(worktree: Worktree, enrichment: WorktreeEnrichment?) -> String {
    let cachedBranch = enrichment?.branch.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    if !cachedBranch.isEmpty {
        return cachedBranch
    }
    return "detached HEAD"
}
```

**Step 3: Fix tests**

Update `RepoSidebarContentViewTests.swift` to use renamed cache and updated Worktree constructors.

**Step 4: Verify**

```bash
mise run build
mise run test
```

**Step 5: Commit**

```bash
git add -A && git commit -m "refactor: sidebar uses WorkspaceRepoCache for all enrichment display"
```

---

### Task 8: Update CommandBarDataSource

**Why now:** CommandBar reads worktree.branch and worktree.agent which no longer exist.

**Files:**
- Modify: `Sources/AgentStudio/Features/CommandBar/CommandBarDataSource.swift`
- Modify: `Tests/AgentStudioTests/Features/CommandBar/CommandBarDataSourceTests.swift`

**Step 1: Fix branch references**

Replace `worktree.branch` with lookup from `WorkspaceRepoCache.worktreeEnrichmentByWorktreeId[worktree.id]?.branch ?? ""`.

CommandBarDataSource needs access to `WorkspaceRepoCache`. Add it as a dependency.

**Step 2: Remove agent color references**

Replace all `pane.agent?.color` and `worktree.agent?.color` with `nil` (or remove the iconColor parameter if it's optional).

**Step 3: Fix tests**

**Step 4: Verify**

```bash
mise run build
mise run test
```

**Step 5: Commit**

```bash
git add -A && git commit -m "fix: CommandBarDataSource reads branch from cache, removes agent refs"
```

---

### Task 9: Update WorktrunkService

**Why now:** WorktrunkService creates Worktree instances with branch data from git output. With branch removed from Worktree, it needs to return structure-only Worktrees.

**Files:**
- Modify: `Sources/AgentStudio/Infrastructure/WorktrunkService.swift`
- Modify: `Tests/AgentStudioTests/Infrastructure/WorktrunkParsingTests.swift`

**Step 1: Update Worktree construction in WorktrunkService**

All `Worktree(name:, path:, branch:, isMainWorktree:)` calls become `Worktree(repoId:, name:, path:, isMainWorktree:)`.

WorktrunkService methods that discover worktrees need a `repoId` parameter since Worktree now requires it.

The branch data parsed from git output is NOT lost — it's just not stored on the Worktree model. The existing enrichment pipeline (GitProjector → bus → cache) provides branch data.

**Step 2: Update method signatures**

`discoverWorktrees(for:)` → `discoverWorktrees(for:, repoId:)` — pass repoId through.
`parseGitWorktreeOutput(_:)` → returns a lightweight struct (not Worktree) with path/branch/name, then the caller builds Worktree with repoId.

Or simpler: add repoId parameter to all discovery methods and pass it to Worktree constructor.

**Step 3: Fix tests**

**Step 4: Verify**

```bash
mise run build
mise run test
```

**Step 5: Commit**

```bash
git add -A && git commit -m "refactor: WorktrunkService constructs Worktree with repoId FK, no branch"
```

---

### Task 10: Ordering Tolerance — Handle Out-of-Order Events

**Why now:** With more producers emitting topology events, we need to handle race conditions.

**Files:**
- Modify: `Sources/AgentStudio/App/WorkspaceCacheCoordinator.swift`
- Add tests for ordering edge cases

**Step 1: Write failing tests**

- `test_worktreeRegistered_beforeRepoExists_doesNotCrash` — emit `.worktreeRegistered` for unknown repoId, verify no crash, verify no-op or queued
- `test_enrichment_beforeWorktreeRegistered_doesNotCrash` — emit `.snapshotChanged` for unknown worktreeId, verify cache still updates

**Step 2: Fix handlers**

The coordinator's `handleTopology` already guards with `guard let repo = ...` and returns. Verify this is safe for all cases. Add logging for dropped events.

**Step 3: Verify**

```bash
mise run test
```

**Step 4: Commit**

```bash
git add -A && git commit -m "fix: topology handlers tolerate out-of-order events"
```

---

### Task 11: Full Verification Pass

**Why this is critical:** After all changes, run the complete verification suite to catch any regressions.

**Step 1: Format and lint**

```bash
mise run format
mise run lint
```
Expected: zero errors.

**Step 2: Full build**

```bash
mise run build
```
Expected: zero errors, zero warnings related to our changes.

**Step 3: Full test suite**

```bash
mise run test
```
Expected: all tests pass. Record pass/fail counts.

**Step 4: Grep for dangling references**

```bash
# No references to removed types
grep -r "WorktreeStatus" Sources/ Tests/ --include="*.swift" | grep -v "\.build"
grep -r "WorkspaceCacheStore" Sources/ Tests/ --include="*.swift" | grep -v "\.build"

# No Worktree constructors with old params
grep -rn "Worktree(" Sources/ Tests/ --include="*.swift" | grep "branch:" | grep -v "\.build"
grep -rn "Worktree(" Sources/ Tests/ --include="*.swift" | grep "status:" | grep -v "\.build"
grep -rn "Worktree(" Sources/ Tests/ --include="*.swift" | grep "agent:" | grep -v "\.build"

# No worktree.branch or worktree.agent access
grep -rn "worktree\.branch" Sources/ Tests/ --include="*.swift" | grep -v "\.build" | grep -v "WorktreeEnrichment"
grep -rn "worktree\.agent" Sources/ Tests/ --include="*.swift" | grep -v "\.build"
grep -rn "worktree\.status" Sources/ Tests/ --include="*.swift" | grep -v "\.build"
```
Expected: zero matches for all grep commands.

**Step 5: Verify sidebar data flow**

Build and launch the app. Add a folder. Verify:
1. Sidebar shows repo with worktrees grouped correctly
2. Branch names appear (from cache enrichment, not model)
3. PR counts appear
4. Resizing the split view does NOT cause re-layout (the original staggering bug)

```bash
mise run build
.build/debug/AgentStudio &
```
Use Peekaboo to screenshot and verify sidebar renders correctly.

**Step 6: Final commit**

```bash
git add -A && git commit -m "chore: verification pass — lint, format, grep for dangling refs"
```

---

## Verification Checklist (use after ALL tasks complete)

- [ ] `mise run build` — zero errors
- [ ] `mise run test` — all tests pass, show pass/fail counts
- [ ] `mise run lint` — zero errors
- [ ] No `WorktreeStatus` references in source
- [ ] No `WorkspaceCacheStore` references in source
- [ ] No `Worktree.branch` access in source
- [ ] No `Worktree.agent` access in source
- [ ] No `Worktree.status` access in source
- [ ] No `AgentType` references in source
- [ ] Boot replay emits topology events (verified by test)
- [ ] Add Folder emits topology events (verified by test)
- [ ] Topology handlers are idempotent (verified by test)
- [ ] Sidebar renders correctly after launch (verified by Peekaboo)
- [ ] Sidebar does NOT stagger on load (original bug fixed)

## File Impact Summary

| File | Task | Change |
|------|------|--------|
| `Core/Models/Worktree.swift` | 1, 2 | Slim to structure-only, remove AgentType enum |
| `Core/Models/Pane.swift` | 2 | Remove agent property |
| `Core/Models/Templates.swift` | 2 | Remove agent from TerminalTemplate |
| `Core/Models/DynamicView.swift` | 2 | Remove byAgentType case |
| `Core/PaneRuntime/Contracts/PaneMetadata.swift` | 2 | Remove agentType field |
| `Core/Stores/WorkspaceCacheStore.swift` | 3 | Rename → WorkspaceRepoCache |
| `Core/Stores/WorkspaceStore.swift` | 1, 4 | Update Worktree usage, idempotent addRepo |
| `Core/Stores/WorkspacePersistor.swift` | 1 | Update Worktree serialization |
| `Core/Stores/DynamicViewProjector.swift` | 2 | Remove groupByAgentType |
| `App/WorkspaceCacheCoordinator.swift` | 3, 4, 10 | Rename refs, idempotent handlers, ordering |
| `App/AppDelegate.swift` | 3, 5, 6 | Rename refs, emit events, boot replay |
| `App/MainSplitViewController.swift` | 3 | Rename refs |
| `App/MainWindowController.swift` | 3 | Rename refs |
| `Features/Sidebar/RepoSidebarContentView.swift` | 3, 7 | Rename refs, use cache for branch |
| `Features/CommandBar/CommandBarDataSource.swift` | 8 | Read branch from cache, remove agent |
| `Infrastructure/WorktrunkService.swift` | 9 | Add repoId to Worktree construction |
| `Tests/Helpers/ModelFactories.swift` | 1, 2 | Update factories |
| ~15 test files | 1-10 | Update constructors, assertions, rename refs |
