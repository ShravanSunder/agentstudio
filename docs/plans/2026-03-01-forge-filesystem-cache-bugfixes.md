# Forge + Filesystem + Cache Bugfixes Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Remove duplicate Forge refresh/register work, exclude unavailable repos from filesystem sync, and prune stale per-worktree cache entries on unregister with message-driven test coverage.

**Architecture:** Keep Forge ingestion event-driven (Git projector -> ForgeActor) and make WorkspaceCacheCoordinator responsible only for cache projection plus repo-level unregister on removal. Keep PaneCoordinator filesystem sync as the source of desired roots, but filter out unavailable repos. Prune cache at the same topology boundary where worktrees are unregistered.

**Tech Stack:** Swift 6, SwiftPM `Testing`, AppKit runtime bus (`EventBus<RuntimeEnvelope>`), actor-based filesystem/git/forge pipeline.

---

### Task 1: Remove Duplicate Forge Side Effects From Coordinator

**Files:**
- Modify: `Sources/AgentStudio/App/WorkspaceCacheCoordinator.swift`
- Test: `Tests/AgentStudioTests/App/WorkspaceCacheCoordinatorTests.swift`

**Step 1: Write failing tests**

```swift
@Test
func scopeSync_originChanged_doesNotRegisterForgeRepo() async { ... }

@Test
func scopeSync_branchChanged_doesNotRefreshForgeRepo() async { ... }
```

**Step 2: Run targeted tests to verify failure**

Run: `SWIFT_BUILD_DIR=".build-agent-plan" swift test --build-path "$SWIFT_BUILD_DIR" --filter WorkspaceCacheCoordinatorTests`
Expected: FAIL because coordinator still emits `.registerForgeRepo` and `.refreshForgeRepo`.

**Step 3: Implement minimal fix**

```swift
// In .branchChanged handling: remove syncScope(.refreshForgeRepo(...))
// In .originChanged handling: remove syncScope(.registerForgeRepo(...)) and keep cache updates.
// Keep repoRemoved -> syncScope(.unregisterForgeRepo(...)) as the explicit teardown path.
```

**Step 4: Run targeted tests to verify pass**

Run: `SWIFT_BUILD_DIR=".build-agent-plan" swift test --build-path "$SWIFT_BUILD_DIR" --filter WorkspaceCacheCoordinatorTests`
Expected: PASS

**Step 5: Commit**

```bash
git add Sources/AgentStudio/App/WorkspaceCacheCoordinator.swift Tests/AgentStudioTests/App/WorkspaceCacheCoordinatorTests.swift
git commit -m "fix: remove duplicate forge register/refresh from cache coordinator"
```

### Task 2: Exclude Unavailable Repos From Filesystem Root Sync

**Files:**
- Modify: `Sources/AgentStudio/App/PaneCoordinator+FilesystemSource.swift`
- Test: `Tests/AgentStudioTests/App/PaneCoordinatorTests.swift`

**Step 1: Write failing test**

```swift
@Test("syncRootsAndActivity excludes unavailable repo worktrees")
func syncRootsAndActivity_excludesUnavailableRepos() async { ... }
```

**Step 2: Run targeted test to verify failure**

Run: `SWIFT_BUILD_DIR=".build-agent-plan" swift test --build-path "$SWIFT_BUILD_DIR" --filter PaneCoordinatorTests/syncRootsAndActivity_excludesUnavailableRepos`
Expected: FAIL because unavailable worktree is still registered in filesystem source.

**Step 3: Implement minimal fix**

```swift
for repo in store.repos where !store.isRepoUnavailable(repo.id) {
    for worktree in repo.worktrees {
        contextsByWorktreeId[worktree.id] = ...
    }
}
```

**Step 4: Run targeted test to verify pass**

Run: `SWIFT_BUILD_DIR=".build-agent-plan" swift test --build-path "$SWIFT_BUILD_DIR" --filter PaneCoordinatorTests/syncRootsAndActivity_excludesUnavailableRepos`
Expected: PASS

**Step 5: Commit**

```bash
git add Sources/AgentStudio/App/PaneCoordinator+FilesystemSource.swift Tests/AgentStudioTests/App/PaneCoordinatorTests.swift
git commit -m "fix: skip unavailable repos during filesystem root sync"
```

### Task 3: Prune Per-Worktree Cache On Topology Unregister

**Files:**
- Modify: `Sources/AgentStudio/Core/Stores/WorkspaceCacheStore.swift`
- Modify: `Sources/AgentStudio/App/WorkspaceCacheCoordinator.swift`
- Test: `Tests/AgentStudioTests/App/WorkspaceCacheCoordinatorTests.swift`

**Step 1: Write failing test**

```swift
@Test
func topology_worktreeUnregistered_prunesWorktreeCaches() { ... }
```

**Step 2: Run targeted test to verify failure**

Run: `SWIFT_BUILD_DIR=".build-agent-plan" swift test --build-path "$SWIFT_BUILD_DIR" --filter WorkspaceCacheCoordinatorTests/topology_worktreeUnregistered_prunesWorktreeCaches`
Expected: FAIL because stale entries remain in `worktreeEnrichmentByWorktreeId`, PR counts, and notification counts.

**Step 3: Implement minimal fix**

```swift
// WorkspaceCacheStore
func removeWorktree(_ worktreeId: UUID) {
    worktreeEnrichmentByWorktreeId.removeValue(forKey: worktreeId)
    pullRequestCountByWorktreeId.removeValue(forKey: worktreeId)
    notificationCountByWorktreeId.removeValue(forKey: worktreeId)
}

// WorkspaceCacheCoordinator.handleTopology(.worktreeUnregistered)
cacheStore.removeWorktree(worktreeId)
```

**Step 4: Run targeted test to verify pass**

Run: `SWIFT_BUILD_DIR=".build-agent-plan" swift test --build-path "$SWIFT_BUILD_DIR" --filter WorkspaceCacheCoordinatorTests/topology_worktreeUnregistered_prunesWorktreeCaches`
Expected: PASS

**Step 5: Commit**

```bash
git add Sources/AgentStudio/Core/Stores/WorkspaceCacheStore.swift Sources/AgentStudio/App/WorkspaceCacheCoordinator.swift Tests/AgentStudioTests/App/WorkspaceCacheCoordinatorTests.swift
git commit -m "fix: prune worktree cache state when topology unregisters worktree"
```

### Task 4: Message-Driven Integration Safety Net

**Files:**
- Modify: `Tests/AgentStudioTests/App/PrimarySidebarPipelineIntegrationTests.swift`

**Step 1: Write failing integration test (message-in, behavior-out)**

```swift
@Test("message-driven origin+branch path emits one forge update flow")
func messageDrivenOriginBranchPathDoesNotDoubleInvokeForge() async { ... }
```

**Step 2: Run targeted integration test**

Run: `SWIFT_BUILD_DIR=".build-agent-plan" swift test --build-path "$SWIFT_BUILD_DIR" --filter PrimarySidebarPipelineIntegrationTests/messageDrivenOriginBranchPathDoesNotDoubleInvokeForge`
Expected: FAIL before fix due duplicate invocation path.

**Step 3: Implement minimal test-support plumbing**

```swift
// counting stub provider in test file to count pullRequestCounts invocations
```

**Step 4: Re-run targeted integration test**

Run: `SWIFT_BUILD_DIR=".build-agent-plan" swift test --build-path "$SWIFT_BUILD_DIR" --filter PrimarySidebarPipelineIntegrationTests/messageDrivenOriginBranchPathDoesNotDoubleInvokeForge`
Expected: PASS

**Step 5: Commit**

```bash
git add Tests/AgentStudioTests/App/PrimarySidebarPipelineIntegrationTests.swift
git commit -m "test: add message-driven integration guard against duplicate forge updates"
```

### Task 5: Full Verification Loop

**Files:**
- Validate existing + modified tests

**Step 1: Run formatter/lint**

Run: `mise run format && mise run lint`
Expected: PASS

**Step 2: Run full test suite**

Run: `mise run test`
Expected: PASS

**Step 3: Final verification notes**

Capture exact failing tests fixed, pass counts, and any remaining risk.

