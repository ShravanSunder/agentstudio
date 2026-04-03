# Sidebar Worktree Family Icons & Colors Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix the sidebar so each checkout gets a star icon and unique color shared by all its worktrees, and secondary worktrees get the worktree icon with the same color as their parent checkout.

**Architecture:** Wire the existing `.worktreeDiscovered` event (already defined in `GitWorkingDirectoryEvent`, never emitted) through the enrichment pipeline. `GitWorkingDirectoryProjector` calls `WorktrunkService.discoverWorktrees()` on initial worktree registration and emits `.worktreeDiscovered` facts. `WorkspaceCacheCoordinator` handles these facts by calling `WorkspaceStore.reconcileDiscoveredWorktrees()`, which merges discovered worktrees under their parent repo. The sidebar then reads correct `repo.worktrees` data and renders icons/colors accordingly.

**Tech Stack:** Swift 6.2, `WorktrunkService` (`wt list` CLI), `EventBus<RuntimeEnvelope>`, Swift Testing

---

## Architecture Context

This plan follows the established enrichment pipeline pattern documented in [Workspace Data Architecture](../../architecture/workspace_data_architecture.md) and [EventBus Design](../../architecture/pane_runtime_eventbus_design.md).

### The Enrichment Pipeline (existing pattern)

```
FilesystemActor → EventBus → GitWorkingDirectoryProjector → EventBus → WorkspaceCacheCoordinator → Stores
```

Each boundary actor enriches independently and posts facts to the bus. The coordinator is the single consolidation consumer. The bus is a dumb pipe — no domain logic, no filtering.

### What Already Exists (designed, not yet wired)

| Component | Status | Reference |
|-----------|--------|-----------|
| `.worktreeDiscovered(repoId:, worktreePath:, branch:, isMain:)` | **Defined** in `RuntimeEnvelopeCore.swift:56` | Event namespace in architecture doc line 281 |
| `.worktreeRemoved(repoId:, worktreePath:)` | **Defined** in `RuntimeEnvelopeCore.swift:57` | Event namespace in architecture doc line 282 |
| `WorkspaceCacheCoordinator` handler for `.worktreeDiscovered` | **Stub** — `break` at `WorkspaceCacheCoordinator.swift:212` | Should call `reconcileDiscoveredWorktrees` |
| `WorkspaceStore.reconcileDiscoveredWorktrees()` | **Implemented** at `WorkspaceStore.swift:1388` | Merges worktrees by path, preserves UUIDs |
| `WorktrunkService.discoverWorktrees(for:repoId:)` | **Implemented** at `WorktrunkService.swift:28` | Uses `wt list --format=json` with `git worktree list --porcelain` fallback |
| `GitWorkingDirectoryProjector` runs `git worktree list` | **Documented** in architecture (line 214) | Never implemented in projector code |
| `ForgeActor` subscribes to `.worktreeDiscovered` | **Implemented** at `ForgeActor.swift:203` | Already tracks branches from discovered worktrees |

### What's Broken (root cause)

`RepoScanner.scanForGitRepos()` (`RepoScanner.swift:32`) uses `FileManager.fileExists(atPath: gitDir.path)` which returns `true` for both `.git` directories (real clones) and `.git` files (worktree checkouts). Every on-disk directory becomes a separate `Repo` with `worktrees.count == 1` and `isMainWorktree: true`.

The projector is documented to run `git worktree list` and emit `.worktreeDiscovered` events, but this was never implemented. The coordinator handles `.worktreeDiscovered` as a no-op `break`. So the store never learns that multiple repos are actually worktrees of the same parent.

### The Fix (follows existing architecture)

Wire the missing step: after the projector receives a `.worktreeRegistered` topology event and computes git status, it also calls `WorktrunkService.discoverWorktrees()` and emits `.worktreeDiscovered` facts for each discovered worktree. The coordinator handles these facts by reconciling worktrees under the correct parent repo. No new event types. No new model fields. No changes to `RawRepoOrigin` or `RepoEnrichment`.

```
FilesystemActor emits .worktreeRegistered
    ↓ (bus)
GitWorkingDirectoryProjector
    → runs git status (existing)
    → calls WorktrunkService.discoverWorktrees() (NEW)
    → emits .worktreeDiscovered per worktree (NEW, event already defined)
    ↓ (bus)
WorkspaceCacheCoordinator
    → handles .worktreeDiscovered (currently: break)
    → calls store.reconcileDiscoveredWorktrees() (NEW wiring)
    ↓
WorkspaceStore now has correct repo.worktrees with proper isMainWorktree flags
    ↓
Sidebar reads correct data → icons and colors work
```

### Why WorktrunkService, Not Raw Git

`WorktrunkService` (`Infrastructure/WorktrunkService.swift`) is the established infrastructure component (component 3.11 in [Component Architecture](../../architecture/component_architecture.md)). It wraps `wt list --format=json` with fallback to `git worktree list --porcelain`. Using it follows the architecture's rule: domain actors don't run raw git commands — they use injected infrastructure.

---

## Event System: Concrete Flow

This section draws the exact event flow for this feature, end to end. Read this before touching code.

### The Three Data Flow Planes

The architecture has three planes (see [Pane Runtime Architecture — Three Data Flow Planes](../../architecture/pane_runtime_architecture.md)):

```
EVENT PLANE (one-way: producers → EventBus → consumers)
  Facts about the world. "A worktree exists at this path." "Branch changed."
  Never flows backward. Bus is dumb fan-out.

COMMAND PLANE (one-way: user/system → coordinator → runtime)
  Request-response. "Open this worktree." "Close this tab."
  Never flows through the EventBus.

UI PLANE (runtime → SwiftUI view)
  @Observable properties. Zero overhead. Synchronous on MainActor.
  Sidebar reads stores via @Observable — no imperative fetches.
```

This feature operates entirely on the **event plane** (enrichment pipeline) and **UI plane** (sidebar reads stores).

### Envelope Hierarchy

Events travel in typed envelopes. The bus is generic over `RuntimeEnvelope`, which is a 3-tier discriminated union:

```
RuntimeEnvelope
├── .system(SystemEnvelope)       ← topology events (repo discovered/removed, worktree registered)
├── .worktree(WorktreeEnvelope)   ← enrichment events (git status, branch, origin, worktree discovered)
└── .pane(PaneEnvelope)           ← per-pane events (title changed, bell rang)
```

For this feature:
- `.system(.topology(.worktreeRegistered))` — **trigger** (already emitted by FilesystemActor)
- `.worktree(.gitWorkingDirectory(.worktreeDiscovered))` — **new emission** from projector
- Coordinator subscribes to the bus and handles both

### Actor Boundaries

```
┌─────────────────────────────────────────────────────────────────┐
│                    COOPERATIVE POOL ACTORS                       │
│                                                                 │
│  ┌──────────────────┐     ┌───────────────────────────────┐    │
│  │ FilesystemActor   │     │ GitWorkingDirectoryProjector  │    │
│  │ (app-wide)        │     │ (app-wide, keyed by worktree) │    │
│  │                   │     │                               │    │
│  │ Owns: FSEvents,   │     │ Owns: git status enrichment   │    │
│  │ path routing,     │     │                               │    │
│  │ repo scanning     │     │ NEW: calls WorktrunkService   │    │
│  │                   │     │ .discoverWorktrees() and      │    │
│  │ Emits:            │     │ emits .worktreeDiscovered     │    │
│  │ SystemEnvelope    │     │                               │    │
│  │ (.topology(       │     │ Emits:                        │    │
│  │   .worktreeReg.)) │     │ WorktreeEnvelope              │    │
│  └────────┬──────────┘     │ (.gitWorkingDirectory(        │    │
│           │                │   .worktreeDiscovered))        │    │
│           │                └──────────┬────────────────────┘    │
│           │                           │                         │
└───────────┼───────────────────────────┼─────────────────────────┘
            │                           │
            ▼                           ▼
    ┌───────────────────────────────────────────────┐
    │         actor EventBus<RuntimeEnvelope>        │
    │         (cooperative pool, dumb fan-out)       │
    │                                               │
    │  post() → yield to all subscriber streams     │
    │  No domain logic. No filtering. No transform. │
    └───────────┬───────────────┬───────────────────┘
                │               │
                ▼               ▼
    ┌───────────────────┐   ┌──────────────────────┐
    │ ForgeActor         │   │ @MainActor consumers  │
    │ (already handles   │   │                      │
    │ .worktreeDiscovered│   │ WorkspaceCacheCoord.  │
    │ — tracks branches) │   │ (NEW: reconcile      │
    │                    │   │  discovered worktrees │
    │                    │   │  into WorkspaceStore) │
    └────────────────────┘   └──────────┬───────────┘
                                        │
                              ┌─────────┴─────────┐
                              ▼                   ▼
                      WorkspaceStore      WorkspaceRepoCache
                      (@Observable)       (@Observable)
                              │                   │
                              └─────────┬─────────┘
                                        ▼
                              Sidebar (pure reader)
                              (@Observable binding)
```

### Concrete Event Sequence (what happens when user adds a folder)

```
TIME  ACTOR                    EVENT                                  ENVELOPE TYPE
────  ─────                    ─────                                  ─────────────
 t0   FilesystemActor          scans ~/projects, finds /my-repo       (internal)
 t1   FilesystemActor          .repoDiscovered(repoPath:/my-repo)     SystemEnvelope
                               → bus.post()

 t2   WorkspaceCacheCoord.     handleTopology(.repoDiscovered)        (consumes from bus)
      (MainActor)              → store.addRepo(at:/my-repo)
                               → creates Repo with 1 worktree, isMainWorktree:true
                               → cache.setEnrichment(.awaitingOrigin)

 t3   PaneCoordinator          syncs filesystem roots                 (command plane)
      (MainActor)              → filesystemActor.register(
                                   worktreeId, repoId, rootPath)

 t4   FilesystemActor          .worktreeRegistered(wt-1, repo-A,      SystemEnvelope
                                rootPath:/my-repo)
                               → bus.post()

 t5   GitWorkingDirectory      receives .worktreeRegistered           (consumes from bus)
      Projector                → runs git status via provider
                               → emits .snapshotChanged              WorktreeEnvelope
                               → emits .branchChanged                WorktreeEnvelope
                               → emits .originChanged                WorktreeEnvelope

 t6   GitWorkingDirectory      ★ NEW: initial registration detected   (internal)
      Projector                → calls WorktrunkService
                                 .discoverWorktrees(for:/my-repo)
                               → wt list returns:
                                 /my-repo (main), /my-repo.feat (secondary)

 t7   GitWorkingDirectory      .worktreeDiscovered(repo-A,            WorktreeEnvelope
      Projector                  path:/my-repo, branch:"", isMain:true)
                               → bus.post()
      GitWorkingDirectory      .worktreeDiscovered(repo-A,            WorktreeEnvelope
      Projector                  path:/my-repo.feat, branch:"",
                                 isMain:false)
                               → bus.post()

 t8   WorkspaceCacheCoord.     ★ NEW: handleEnrichment                (consumes from bus)
      (MainActor)              (.worktreeDiscovered, repo-A,
                                path:/my-repo.feat, isMain:false)
                               → appends Worktree to repo.worktrees
                               → calls store.reconcileDiscoveredWorktrees()
                               → Repo now has 2 worktrees with correct isMainWorktree

 t9   ForgeActor               handles .worktreeDiscovered            (consumes from bus)
                               → tracks branch for PR lookup
                               (already implemented, no change needed)

 t10  Sidebar                  @Observable fires                      (UI plane)
      (SwiftUI)                → repo.worktrees.count == 2
                               → main worktree: star icon, Color A
                               → secondary worktree: worktree icon, Color A
```

### Key Architecture Rules This Plan Follows

1. **Bus carries facts, not commands.** `.worktreeDiscovered` is a fact ("this worktree exists at this path"). The coordinator calls store methods in response — the bus never routes mutations.

2. **No core actor calls another core actor for event-plane data.** The projector posts to the bus; the coordinator subscribes from the bus. They never call each other directly for event data. (Command-plane calls like `forgeActor.refresh()` are direct — different plane.)

3. **Boundary actors enrich independently.** `GitWorkingDirectoryProjector` does worktree discovery via `WorktrunkService`. It doesn't ask the coordinator or the store — it discovers and emits facts.

4. **`@concurrent nonisolated` for blocking I/O.** `WorktrunkService.discoverWorktrees()` shells out to `wt list`. The projector calls it via a `@concurrent nonisolated static` helper so it runs on the cooperative pool, not on the projector's serial executor.

5. **Coordinator is sequencing-only.** The new `.worktreeDiscovered` handler calls `reconcileDiscoveredWorktrees()`. No domain logic — just "when I see X, call Y."

6. **Sidebar is a pure reader.** No new imperative fetches. The existing `@Observable` binding on `WorkspaceStore.repos` and `repo.worktrees` drives the UI update automatically when the store is mutated.

---

## File Structure

| File | Action | Responsibility |
|------|--------|----------------|
| `Sources/.../GitWorkingDirectoryProjector.swift` | Modify | Call `WorktrunkService.discoverWorktrees()` on worktree registration, emit `.worktreeDiscovered` facts |
| `Sources/.../WorkspaceCacheCoordinator.swift:212` | Modify | Handle `.worktreeDiscovered` → call `reconcileDiscoveredWorktrees` |
| `Sources/.../RepoSidebarContentView.swift:425-435,712-727` | Modify | Fix `checkoutIconKind` and `checkoutTypeIcon` — star for main/standalone, worktree icon for secondary |
| `Sources/.../RepoSidebarContentView.swift:360-385` | Modify | Fix `colorForCheckout` — color per checkout, shared across worktrees |
| `Tests/.../WorkspaceCacheCoordinatorIntegrationTests.swift` | Modify | Integration test: worktree registration → discovery → reconciliation |
| `Tests/.../RepoSidebarContentViewTests.swift` | Modify | Tests for icon kind and color with multi-worktree repos |

---

## Task 1: Emit `.worktreeDiscovered` from GitWorkingDirectoryProjector

**Files:**
- Modify: `Sources/AgentStudio/Core/PaneRuntime/Sources/GitWorkingDirectoryProjector.swift`

- [ ] **Step 1: Write the failing integration test**

Add to `Tests/AgentStudioTests/App/WorkspaceCacheCoordinatorIntegrationTests.swift`:

```swift
@Test
func integration_worktreeDiscoveryReconcilesSiblingWorktrees() async {
    let bus = EventBus<RuntimeEnvelope>()
    let workspaceStore = makeWorkspaceStore()
    let repoCache = WorkspaceRepoCache()
    let coordinator = WorkspaceCacheCoordinator(
        bus: bus,
        workspaceStore: workspaceStore,
        repoCache: repoCache,
        scopeSyncHandler: { _ in }
    )
    let mainRepoPath = URL(fileURLWithPath: "/tmp/worktree-discovery-main")
    let secondaryPath = URL(fileURLWithPath: "/tmp/worktree-discovery-feature")

    let projector = GitWorkingDirectoryProjector(
        bus: bus,
        gitWorkingTreeProvider: .stub { _ in
            GitWorkingTreeStatus(
                summary: GitWorkingTreeSummary(changed: 0, staged: 0, untracked: 0),
                branch: "main",
                origin: "git@github.com:askluna/agent-studio.git"
            )
        },
        worktreeDiscoverer: .stub { path, repoId in
            // Simulate: WorktrunkService discovers two worktrees for this repo
            [
                Worktree(repoId: repoId, name: "main", path: mainRepoPath, isMainWorktree: true),
                Worktree(repoId: repoId, name: "feature", path: secondaryPath, isMainWorktree: false),
            ]
        },
        coalescingWindow: .zero
    )

    await withStartedCoordinatorAndProjector(bus: bus, coordinator: coordinator, projector: projector) {
        // Add the main repo
        let repo = workspaceStore.addRepo(at: mainRepoPath)
        #expect(repo.worktrees.count == 1)
        #expect(repo.worktrees[0].isMainWorktree == true)

        // Register worktree → triggers projector → discovers siblings → emits .worktreeDiscovered
        let worktreeId = UUID()
        _ = await bus.post(
            .system(
                SystemEnvelope.test(
                    event: .topology(
                        .worktreeRegistered(worktreeId: worktreeId, repoId: repo.id, rootPath: mainRepoPath)
                    ),
                    source: .builtin(.filesystemWatcher)
                )
            )
        )

        let reconciled = await eventually("repo should have 2 worktrees after discovery") {
            guard let updatedRepo = workspaceStore.repos.first(where: { $0.id == repo.id }) else {
                return false
            }
            return updatedRepo.worktrees.count == 2
                && updatedRepo.worktrees.contains(where: { $0.isMainWorktree && $0.path == mainRepoPath })
                && updatedRepo.worktrees.contains(where: { !$0.isMainWorktree && $0.path == secondaryPath })
        }
        #expect(reconciled)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --build-path ".build-agent-$(uuidgen | tr -dc 'a-z0-9' | head -c 8)" --filter "integration_worktreeDiscoveryReconcilesSiblingWorktrees" > /tmp/test-output.txt 2>&1 && echo "PASS" || echo "FAIL"`
Expected: FAIL — `worktreeDiscoverer` parameter doesn't exist on `GitWorkingDirectoryProjector`.

- [ ] **Step 3: Define `WorktreeDiscoverer` protocol and inject into projector**

The projector needs to call `WorktrunkService.discoverWorktrees()`, but actors don't call concrete services directly — they use injected protocols (architecture rule: transport-agnostic, testable).

Create a protocol and make `WorktrunkService` conform:

```swift
// Add to GitWorkingDirectoryProjector.swift (or a nearby contracts file)
protocol WorktreeDiscovering: Sendable {
    func discoverWorktrees(for projectPath: URL, repoId: UUID) -> [Worktree]
}

extension WorktrunkService: WorktreeDiscovering {}
```

Add a stub for testing in `Tests/AgentStudioTests/TestSupport/PaneRuntimeProviderStubs.swift`:

```swift
struct StubWorktreeDiscoverer: WorktreeDiscovering {
    let handler: @Sendable (URL, UUID) -> [Worktree]

    func discoverWorktrees(for projectPath: URL, repoId: UUID) -> [Worktree] {
        handler(projectPath, repoId)
    }
}

extension WorktreeDiscovering where Self == StubWorktreeDiscoverer {
    static func stub(
        _ handler: @escaping @Sendable (URL, UUID) -> [Worktree]
    ) -> StubWorktreeDiscoverer {
        StubWorktreeDiscoverer(handler: handler)
    }
}
```

- [ ] **Step 4: Add `worktreeDiscoverer` to `GitWorkingDirectoryProjector` init**

In `GitWorkingDirectoryProjector.swift`, add the dependency:

```swift
private let worktreeDiscoverer: any WorktreeDiscovering

init(
    bus: EventBus<RuntimeEnvelope> = PaneRuntimeEventBus.shared,
    gitWorkingTreeProvider: any GitWorkingTreeStatusProvider = ShellGitWorkingTreeStatusProvider(),
    worktreeDiscoverer: any WorktreeDiscovering = WorktrunkService.shared,
    // ... existing params unchanged
) {
    // ... existing assignments
    self.worktreeDiscoverer = worktreeDiscoverer
}
```

- [ ] **Step 5: Emit `.worktreeDiscovered` after initial worktree registration**

In `computeAndEmit`, after the `snapshotChanged` emission (around line 232), add worktree discovery on the **first** status computation for a worktree (when it's freshly registered — `changeset.paths.isEmpty` indicates initial registration, not a file change):

```swift
// After emitting snapshotChanged, check if this is initial registration
if changeset.paths.isEmpty {
    await discoverAndEmitWorktrees(repoId: changeset.repoId, rootPath: changeset.rootPath)
}
```

Add the discovery method:

```swift
private func discoverAndEmitWorktrees(repoId: UUID, rootPath: URL) async {
    let discovered = await Self.runWorktreeDiscovery(
        rootPath: rootPath,
        repoId: repoId,
        discoverer: worktreeDiscoverer
    )
    guard !discovered.isEmpty else { return }

    for worktree in discovered {
        let branch = "" // Branch enrichment comes separately via snapshotChanged
        await emitGitWorkingDirectoryEvent(
            worktreeId: worktree.id,
            repoId: repoId,
            event: .worktreeDiscovered(
                repoId: repoId,
                worktreePath: worktree.path,
                branch: branch,
                isMain: worktree.isMainWorktree
            )
        )
    }
}

/// Blocking worktree discovery — runs off actor isolation.
@concurrent
nonisolated private static func runWorktreeDiscovery(
    rootPath: URL,
    repoId: UUID,
    discoverer: any WorktreeDiscovering
) async -> [Worktree] {
    discoverer.discoverWorktrees(for: rootPath, repoId: repoId)
}
```

- [ ] **Step 6: Update `FilesystemGitPipeline` to pass `worktreeDiscoverer` through**

In `Sources/AgentStudio/App/FilesystemGitPipeline.swift`, add the parameter:

```swift
init(
    // ... existing params
    worktreeDiscoverer: any WorktreeDiscovering = WorktrunkService.shared,
    // ...
) {
    self.gitWorkingDirectoryProjector = GitWorkingDirectoryProjector(
        bus: bus,
        gitWorkingTreeProvider: gitWorkingTreeProvider,
        worktreeDiscoverer: worktreeDiscoverer,
        // ... existing params
    )
    // ... rest unchanged
}
```

- [ ] **Step 7: Run test — should still fail (coordinator doesn't handle the event yet)**

Run: `swift test --build-path ".build-agent-$(uuidgen | tr -dc 'a-z0-9' | head -c 8)" --filter "integration_worktreeDiscoveryReconcilesSiblingWorktrees" > /tmp/test-output.txt 2>&1 && echo "PASS" || echo "FAIL"`
Expected: FAIL — events are emitted but coordinator has `break` for `.worktreeDiscovered`.

- [ ] **Step 8: Commit projector changes**

```bash
git add Sources/AgentStudio/Core/PaneRuntime/Sources/GitWorkingDirectoryProjector.swift
git add Sources/AgentStudio/App/FilesystemGitPipeline.swift
git add Tests/AgentStudioTests/TestSupport/PaneRuntimeProviderStubs.swift
git add Tests/AgentStudioTests/App/WorkspaceCacheCoordinatorIntegrationTests.swift
git commit -m "feat: emit .worktreeDiscovered from GitWorkingDirectoryProjector via WorktrunkService"
```

---

## Task 2: Handle `.worktreeDiscovered` in WorkspaceCacheCoordinator

**Files:**
- Modify: `Sources/AgentStudio/App/WorkspaceCacheCoordinator.swift:212`

- [ ] **Step 1: Replace the `break` stub with reconciliation logic**

In `WorkspaceCacheCoordinator.swift`, replace the `.worktreeDiscovered` handler (line 212):

```swift
case .worktreeDiscovered(let repoId, let worktreePath, _, let isMain):
    guard let repo = workspaceStore.repos.first(where: { $0.id == repoId }) else {
        Self.logger.debug(
            "Ignoring worktreeDiscovered for unknown repoId=\(repoId.uuidString, privacy: .public)"
        )
        break
    }
    let normalizedPath = worktreePath.standardizedFileURL
    // Only reconcile if this worktree isn't already known
    if !repo.worktrees.contains(where: { $0.path.standardizedFileURL == normalizedPath }) {
        var worktrees = repo.worktrees
        worktrees.append(
            Worktree(
                repoId: repoId,
                name: normalizedPath.lastPathComponent,
                path: normalizedPath,
                isMainWorktree: isMain
            )
        )
        workspaceStore.reconcileDiscoveredWorktrees(repoId, worktrees: worktrees)
    }
case .worktreeRemoved, .diffAvailable:
    break
```

- [ ] **Step 2: Run the integration test**

Run: `swift test --build-path ".build-agent-$(uuidgen | tr -dc 'a-z0-9' | head -c 8)" --filter "integration_worktreeDiscoveryReconcilesSiblingWorktrees" > /tmp/test-output.txt 2>&1 && echo "PASS" || echo "FAIL"`
Expected: PASS

- [ ] **Step 3: Run full test suite to check for regressions**

Run: `mise run test > /tmp/test-output.txt 2>&1 && echo "PASS" || echo "FAIL"`
Expected: PASS

- [ ] **Step 4: Commit**

```bash
git add Sources/AgentStudio/App/WorkspaceCacheCoordinator.swift
git commit -m "feat: handle .worktreeDiscovered to reconcile worktrees under parent repo"
```

---

## Task 3: Fix sidebar icon logic

**Files:**
- Modify: `Sources/AgentStudio/Features/Sidebar/RepoSidebarContentView.swift:425-435,712-727,777`

- [ ] **Step 1: Write failing tests for icon kinds**

Add to `Tests/AgentStudioTests/Features/Sidebar/RepoSidebarContentViewTests.swift`:

```swift
@Test("standalone repo with one worktree gets star icon")
func standaloneRepoGetsStarIcon() {
    let repoId = UUID()
    let worktree = Worktree(
        repoId: repoId, name: "my-repo",
        path: URL(fileURLWithPath: "/tmp/my-repo"), isMainWorktree: true
    )
    let repo = SidebarRepo(
        id: repoId, name: "my-repo",
        repoPath: URL(fileURLWithPath: "/tmp/my-repo"),
        stableKey: "my-repo", worktrees: [worktree]
    )

    let iconKind = RepoSidebarContentView.checkoutIconKind(for: worktree, in: repo)
    #expect(iconKind == .mainCheckout)
}

@Test("main worktree in multi-worktree repo gets star icon")
func mainWorktreeGetsStarIcon() {
    let repoId = UUID()
    let main = Worktree(
        repoId: repoId, name: "my-repo",
        path: URL(fileURLWithPath: "/tmp/my-repo"), isMainWorktree: true
    )
    let secondary = Worktree(
        repoId: repoId, name: "feature",
        path: URL(fileURLWithPath: "/tmp/my-repo.feature"), isMainWorktree: false
    )
    let repo = SidebarRepo(
        id: repoId, name: "my-repo",
        repoPath: URL(fileURLWithPath: "/tmp/my-repo"),
        stableKey: "my-repo", worktrees: [main, secondary]
    )

    let iconKind = RepoSidebarContentView.checkoutIconKind(for: main, in: repo)
    #expect(iconKind == .mainCheckout)
}

@Test("secondary worktree in multi-worktree repo gets worktree icon")
func secondaryWorktreeGetsWorktreeIcon() {
    let repoId = UUID()
    let main = Worktree(
        repoId: repoId, name: "my-repo",
        path: URL(fileURLWithPath: "/tmp/my-repo"), isMainWorktree: true
    )
    let secondary = Worktree(
        repoId: repoId, name: "feature",
        path: URL(fileURLWithPath: "/tmp/my-repo.feature"), isMainWorktree: false
    )
    let repo = SidebarRepo(
        id: repoId, name: "my-repo",
        repoPath: URL(fileURLWithPath: "/tmp/my-repo"),
        stableKey: "my-repo", worktrees: [main, secondary]
    )

    let iconKind = RepoSidebarContentView.checkoutIconKind(for: secondary, in: repo)
    #expect(iconKind == .gitWorktree)
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --build-path ".build-agent-$(uuidgen | tr -dc 'a-z0-9' | head -c 8)" --filter "standaloneRepoGetsStarIcon|mainWorktreeGetsStarIcon|secondaryWorktreeGetsWorktreeIcon" > /tmp/test-output.txt 2>&1 && echo "PASS" || echo "FAIL"`
Expected: FAIL — `checkoutIconKind` is a private instance method, not a static testable one. Also, standalone currently returns `.standaloneCheckout`, not `.mainCheckout`.

- [ ] **Step 3: Rewrite `checkoutIconKind` as a static method**

Replace the private instance method at line 425-435:

```swift
static func checkoutIconKind(for worktree: Worktree, in repo: SidebarRepo) -> SidebarCheckoutIconKind {
    let isMainCheckout =
        worktree.isMainWorktree
        || worktree.path.standardizedFileURL.path == repo.repoPath.standardizedFileURL.path

    if isMainCheckout {
        return .mainCheckout
    }
    return .gitWorktree
}
```

This is simpler: main worktree → star, everything else → worktree icon. No `.standaloneCheckout` needed — a standalone repo is just a main worktree that happens to have no siblings.

Update the private instance call site to forward to the static method:

```swift
private func checkoutIconKind(for worktree: Worktree, in repo: SidebarRepo) -> SidebarCheckoutIconKind {
    Self.checkoutIconKind(for: worktree, in: repo)
}
```

- [ ] **Step 4: Make `SidebarCheckoutIconKind` internal (not private)**

Change at line 777 from `private enum` to `enum` so tests can reference it.

- [ ] **Step 5: Update `checkoutTypeIcon` — remove `.standaloneCheckout` branch**

At line 712-727, simplify:

```swift
@ViewBuilder
private var checkoutTypeIcon: some View {
    let checkoutTypeSize = AppStyle.textBase
    switch checkoutIconKind {
    case .mainCheckout, .standaloneCheckout:
        OcticonImage(name: "octicon-star-fill", size: checkoutTypeSize)
            .foregroundStyle(iconColor)
    case .gitWorktree:
        OcticonImage(name: "octicon-git-worktree", size: checkoutTypeSize)
            .foregroundStyle(iconColor)
            .rotationEffect(.degrees(180))
    }
}
```

- [ ] **Step 6: Run tests**

Run: `swift test --build-path ".build-agent-$(uuidgen | tr -dc 'a-z0-9' | head -c 8)" --filter "standaloneRepoGetsStarIcon|mainWorktreeGetsStarIcon|secondaryWorktreeGetsWorktreeIcon" > /tmp/test-output.txt 2>&1 && echo "PASS" || echo "FAIL"`
Expected: PASS

- [ ] **Step 7: Commit**

```bash
git add Sources/AgentStudio/Features/Sidebar/RepoSidebarContentView.swift
git add Tests/AgentStudioTests/Features/Sidebar/RepoSidebarContentViewTests.swift
git commit -m "fix: sidebar icon logic — star for main/standalone, worktree icon for secondary"
```

---

## Task 4: Fix sidebar color logic

**Files:**
- Modify: `Sources/AgentStudio/Features/Sidebar/RepoSidebarContentView.swift:360-385`
- Modify: `Tests/AgentStudioTests/Features/Sidebar/RepoSidebarContentViewTests.swift`

- [ ] **Step 1: Write failing test for color sharing within a repo's worktrees**

```swift
@Test("all worktrees in same repo share color")
func worktreesInSameRepoShareColor() {
    let repoId = UUID()
    let main = Worktree(
        repoId: repoId, name: "my-repo",
        path: URL(fileURLWithPath: "/tmp/my-repo"), isMainWorktree: true
    )
    let secondary = Worktree(
        repoId: repoId, name: "feature",
        path: URL(fileURLWithPath: "/tmp/my-repo.feature"), isMainWorktree: false
    )
    let repo = SidebarRepo(
        id: repoId, name: "my-repo",
        repoPath: URL(fileURLWithPath: "/tmp/my-repo"),
        stableKey: "my-repo", worktrees: [main, secondary]
    )
    let group = SidebarRepoGroup(
        id: "remote:org/my-repo", repoTitle: "my-repo",
        organizationName: "org", repos: [repo]
    )

    let colorMain = RepoSidebarContentView.colorHexForCheckout(
        repo: repo, in: group, checkoutColorOverrides: [:]
    )
    let colorSecondary = RepoSidebarContentView.colorHexForCheckout(
        repo: repo, in: group, checkoutColorOverrides: [:]
    )

    #expect(colorMain == colorSecondary)
}

@Test("different repos in same group get different colors")
func differentReposGetDifferentColors() {
    let repoA = SidebarRepo(
        id: UUID(), name: "repo-a",
        repoPath: URL(fileURLWithPath: "/tmp/repo-a"),
        stableKey: "a",
        worktrees: [Worktree(repoId: UUID(), name: "a", path: URL(fileURLWithPath: "/tmp/repo-a"), isMainWorktree: true)]
    )
    let repoB = SidebarRepo(
        id: UUID(), name: "repo-b",
        repoPath: URL(fileURLWithPath: "/tmp/repo-b"),
        stableKey: "b",
        worktrees: [Worktree(repoId: UUID(), name: "b", path: URL(fileURLWithPath: "/tmp/repo-b"), isMainWorktree: true)]
    )
    let group = SidebarRepoGroup(
        id: "remote:org/repo", repoTitle: "repo",
        organizationName: "org", repos: [repoA, repoB]
    )

    let colorA = RepoSidebarContentView.colorHexForCheckout(
        repo: repoA, in: group, checkoutColorOverrides: [:]
    )
    let colorB = RepoSidebarContentView.colorHexForCheckout(
        repo: repoB, in: group, checkoutColorOverrides: [:]
    )

    #expect(colorA != colorB)
}
```

- [ ] **Step 2: Run tests to verify they fail**

Expected: FAIL — `colorHexForCheckout` static method doesn't exist.

- [ ] **Step 3: Extract color logic into a testable static method**

The current `colorForCheckout` at line 360 assigns color per `repo.id`. Since worktrees are now properly nested under their parent repo, all worktrees of the same repo share the same `repo.id` → same color. The logic is already correct for the data model after Task 1+2. But we need to make it testable and fix the single-repo-in-group case (currently always returns palette[0]).

Add static method and update the instance method to forward:

```swift
static func colorHexForCheckout(
    repo: SidebarRepo,
    in group: SidebarRepoGroup,
    checkoutColorOverrides: [String: String]
) -> String {
    let overrideKey = repo.id.uuidString
    if let hex = checkoutColorOverrides[overrideKey] {
        return hex
    }

    let orderedRepos = group.repos.sorted { lhs, rhs in
        lhs.stableKey.localizedCaseInsensitiveCompare(rhs.stableKey) == .orderedAscending
    }

    guard orderedRepos.count > 1 else {
        return SidebarRepoGrouping.automaticPaletteHexes[0]
    }

    guard let repoIndex = orderedRepos.firstIndex(where: { $0.id == repo.id }) else {
        return SidebarRepoGrouping.automaticPaletteHexes[0]
    }

    return SidebarRepoGrouping.colorHexForCheckoutIndex(
        repoIndex,
        seed: "\(group.id)|\(repo.stableKey)|\(repo.id.uuidString)"
    )
}

private func colorForCheckout(repo: SidebarRepo, in group: SidebarRepoGroup) -> Color {
    let hex = Self.colorHexForCheckout(
        repo: repo, in: group, checkoutColorOverrides: checkoutColorByRepoId
    )
    return Color(nsColor: NSColor(hex: hex) ?? .controlAccentColor)
}
```

- [ ] **Step 4: Run tests**

Run: `swift test --build-path ".build-agent-$(uuidgen | tr -dc 'a-z0-9' | head -c 8)" --filter "worktreesInSameRepoShareColor|differentReposGetDifferentColors" > /tmp/test-output.txt 2>&1 && echo "PASS" || echo "FAIL"`
Expected: PASS

- [ ] **Step 5: Run full test suite**

Run: `mise run test > /tmp/test-output.txt 2>&1 && echo "PASS" || echo "FAIL"`
Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add Sources/AgentStudio/Features/Sidebar/RepoSidebarContentView.swift
git add Tests/AgentStudioTests/Features/Sidebar/RepoSidebarContentViewTests.swift
git commit -m "fix: sidebar colors per-checkout with worktrees sharing parent color"
```

---

## Task 5: Full validation

- [ ] **Step 1: Run full test suite**

Run: `mise run test > /tmp/test-output.txt 2>&1 && echo "PASS" || echo "FAIL"`
Show pass/fail counts and exit code.

- [ ] **Step 2: Run lint**

Run: `mise run lint > /tmp/lint-output.txt 2>&1 && echo "PASS" || echo "FAIL"`
Zero errors expected.

- [ ] **Step 3: Build and visually verify**

```bash
AGENT_RUN_ID=$(uuidgen) mise run build > /tmp/build-output.txt 2>&1 && echo "PASS" || echo "FAIL"
pkill -9 -f "AgentStudio" 2>/dev/null
.build/debug/AgentStudio &
PID=$(pgrep -f ".build/debug/AgentStudio")
peekaboo see --app "PID:$PID" --json
```

Verify:
- Main worktrees show star icon
- Secondary worktrees show worktree icon (rotated)
- Worktrees of same checkout share color
- Different checkouts in same group have different colors

- [ ] **Step 4: Final commit if any fixes needed**

```bash
git add -A
git commit -m "chore: lint and format fixes"
```
