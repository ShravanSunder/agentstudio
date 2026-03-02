# Workspace Data Architecture

> **Status:** Authoritative spec for workspace-level data model, persistence, enrichment pipeline, and sidebar data flow.
> **Target:** Swift 6.2 / macOS 26
> **Companion docs:** [Pane Runtime Architecture](pane_runtime_architecture.md) (event envelope contracts, pane-level concerns), [EventBus Design](pane_runtime_eventbus_design.md) (actor threading, connection patterns), [Component Architecture](component_architecture.md) (structural overview)

## TL;DR

Workspace state is split into three persistence tiers: canonical config (user intent), derived cache (enrichment), and UI state (preferences). A sequential enrichment pipeline — `FilesystemActor → GitWorkingDirectoryProjector → ForgeActor` — produces events on the `EventBus`. A single `WorkspaceCacheCoordinator` consumes all events, writing topology changes to the canonical store and enrichment data to the cache store. The sidebar is a pure reader of all three stores via `@Observable` binding — zero imperative fetches, zero mutations.

---

## Three Persistence Tiers

Data flows DOWN only — tier N never reads tier N+1.

```
TIER A: CANONICAL CONFIG (source of truth, user intent)
  File: ~/.agentstudio/workspaces/<id>/workspace.state.json
  Owner: WorkspaceStore (@MainActor, @Observable)
  Mutated by: explicit user actions + topology consumer (discovery events)
  Contains: canonical repos, canonical worktrees, panes, tabs, layouts

TIER B: DERIVED CACHE (rebuildable from Tier A + actors)
  File: ~/.agentstudio/workspaces/<id>/workspace.cache.json
  Owner: WorkspaceRepoCache (@MainActor, @Observable)
  Mutated by: WorkspaceCacheCoordinator only (event-driven)
  Contains: repo enrichment, worktree enrichment, PR counts, notification counts

TIER C: UI STATE (preferences, non-structural)
  File: ~/.agentstudio/workspaces/<id>/workspace.ui.json
  Owner: WorkspaceUIStore (@MainActor, @Observable)
  Mutated by: sidebar view actions only
  Contains: expanded groups, checkout colors, filter state
```

### Tier A: Canonical Models

> **Files:** `Core/Models/CanonicalRepo.swift`, `Core/Models/CanonicalWorktree.swift`

```swift
struct CanonicalRepo: Codable, Identifiable, Hashable {
    let id: UUID
    var name: String               // folder name from path
    var repoPath: URL              // filesystem path
    var createdAt: Date
    var stableKey: String { StableKey.fromPath(repoPath) }  // derived, SHA-256
}

struct CanonicalWorktree: Codable, Identifiable, Hashable {
    let id: UUID
    let repoId: UUID               // FK to CanonicalRepo.id
    var name: String
    var path: URL
    var isMainWorktree: Bool
    var stableKey: String { StableKey.fromPath(path) }  // derived, SHA-256
}
```

The runtime `Worktree` model mirrors `CanonicalWorktree` — structure-only, no enrichment:

```swift
struct Worktree: Codable, Identifiable, Hashable {
    let id: UUID
    let repoId: UUID               // explicit FK (not implicit array containment)
    var name: String
    var path: URL
    var isMainWorktree: Bool
}
```

**What is NOT canonical** (lives in cache, populated by event bus):
- `organizationName`, `origin`, `upstream` → `RepoEnrichment`
- `branch`, git snapshot → `WorktreeEnrichment`
- PR counts, notification counts → `WorkspaceRepoCache` dictionaries

### Identity Semantics

Two identity types serve different purposes:

- **UUID** is the primary identity for all runtime references: pane links, event envelopes, cache keys, actor scope. UUIDs never change, even on repo/worktree move.
- **stableKey** (SHA-256 of path) is a secondary index for rebuild/re-association. If workspace config is wiped and regenerated, re-adding the same path produces the same stableKey, enabling matching against previous canonical entries.

On repo move: UUID preserved. Path updated. stableKey recomputed from new path. Pane links use UUID and survive moves. stableKey changing is correct — the path IS different.

Duplicate prevention on discovery: coordinator checks UUID first (existing canonical), then stableKey (re-association after config rebuild). Never creates a duplicate entry.

Pane references: `Pane.metadata.facets.worktreeId` references `CanonicalWorktree.id` (UUID). Since canonical worktrees have stable UUIDs, pane references survive cache rebuilds and repo moves.

### Tier B: Cache Models

```swift
/// Enrichment data for a canonical repo. Derived from git remote inspection.
struct RepoEnrichment: Codable, Sendable, Equatable {
    var organizationName: String?
    var origin: String?            // normalized remote URL
    var upstream: String?          // normalized remote URL
    var remoteSlug: String?        // "owner/repo" extracted from remote
    var groupKey: String           // "remote:<normalized>" or "common:<dir>" or "path:<path>"
    var displayName: String        // "repo-name · org-name" for sidebar
    var remoteFingerprint: String? // normalized remote for dedup
    var worktreeCommonDirectory: String?  // git common dir for worktree grouping
}

/// Enrichment data for a canonical worktree. Derived from git status/branch.
struct WorktreeEnrichment: Codable, Sendable, Equatable {
    var branch: String
    var isMainWorktree: Bool
    var gitSnapshot: GitWorkingTreeSnapshot?  // changed/staged/untracked counts
}

/// Top-level cache container. Persisted as single JSON file.
struct WorkspaceCacheState: Codable {
    var workspaceId: UUID
    var sourceRevision: UInt64          // monotonic, incremented on any cache write
    var lastRebuiltAt: Date
    var repoEnrichment: [UUID: RepoEnrichment]           // keyed by CanonicalRepo.id
    var worktreeEnrichment: [UUID: WorktreeEnrichment]    // keyed by CanonicalWorktree.id
    var pullRequestCounts: [UUID: Int]                     // keyed by CanonicalWorktree.id
    var notificationCounts: [UUID: Int]                    // keyed by CanonicalWorktree.id
}
```

### Tier C: UI State

```swift
struct WorkspaceUIState: Codable {
    var expandedGroups: Set<String>       // groupKey strings
    var checkoutColors: [String: String]  // repoId → color name
    var filterVisible: Bool
    var filterText: String
}
```

---

## Enrichment Pipeline

Sequential enrichment via EventBus. Each stage subscribes to the bus and produces enriched events back to the bus. The bus fans out — the coordinator gets intermediate events directly (no latency blocking).

```
WORKSPACE STATE (canonical repos/worktrees, panes/tabs)
      │
      │ restored at boot → topology events replayed on bus
      ▼
FilesystemActor (raw filesystem I/O)
  worktree roots → deep FSEvents watch (DarwinFSEventStreamClient)
  emits: SystemEnvelope(.topology(..))     ← repo discovery/removal
         WorktreeEnvelope(.filesystem(..)) ← file change facts
      │
      │ posts to EventBus<RuntimeEnvelope>
      ▼
GitWorkingDirectoryProjector (local git enrichment)
  subscribes to .filesystem(.filesChanged)
  runs: git status, git branch, git remote, git worktree list
  emits: .snapshotChanged, .branchChanged, .originChanged
         .worktreeDiscovered, .worktreeRemoved
      │
      │ posts to EventBus
      ▼
ForgeActor (remote forge enrichment)
  subscribes to .branchChanged, .originChanged, .worktreeDiscovered
  runs: gh pr list, GitHub API
  emits: .pullRequestCountsChanged, .checksUpdated, .refreshFailed
      │
      │ all three post to EventBus, fan-out to:
      ▼
WorkspaceCacheCoordinator (@MainActor, consolidation consumer)
  .topology(.repoDiscovered) → register canonical repo+worktrees in WorkspaceStore
                              → compute enrichment → write to WorkspaceRepoCache
                              → register with FilesystemActor (deep watch)
                              → register with ForgeActor (if has remote)
  .topology(.repoRemoved) → unregister actors → mark panes orphaned → prune cache
  .snapshotChanged → write to cache store
  .branchChanged → write to cache store (ForgeActor gets its own copy via bus fan-out)
  .pullRequestCountsChanged → map branch→worktreeId → write to cache
      │
      ▼
WorkspaceRepoCache (@Observable, passive)
  → persisted to cache file on debounced schedule
      │
      ▼
SIDEBAR (pure reader of WorkspaceStore + WorkspaceRepoCache + WorkspaceUIStore)
```

### Actor Responsibilities

#### FilesystemActor

| Aspect | Detail |
|--------|--------|
| **Owns** | FSEvents ingestion via DarwinFSEventStreamClient, path filtering, debounce, batching |
| **Scope** | Worktree root paths (deep FSEvents watch) |
| **Reads** | Registered worktree paths from PaneCoordinator sync |
| **Produces** | `SystemEnvelope(.topology(.repoDiscovered/.repoRemoved))` — discovery events |
| | `WorktreeEnvelope(.filesystem(.filesChanged))` — file change facts |
| **Does not** | Run git commands, access network, mutate canonical store |

#### GitWorkingDirectoryProjector

| Aspect | Detail |
|--------|--------|
| **Owns** | Local git state materialization |
| **Scope** | Per-worktree, keyed by worktreeId |
| **Subscribes to** | `.filesystem(.filesChanged)` from EventBus |
| **Runs** | `git status`, `git branch`, `git remote get-url`, `git worktree list` via `@concurrent nonisolated` helpers |
| **Produces** | `GitWorkingDirectoryEvent` envelopes on EventBus |
| **Carries forward** | `correlationId` from source `.filesChanged` event |
| **Does not** | Access network, scan filesystem for repos, mutate canonical store |

#### ForgeActor

| Aspect | Detail |
|--------|--------|
| **Owns** | Remote forge API interaction (PR status, checks, reviews) |
| **Scope** | Per-repo, keyed by repoId + remoteURL |
| **Subscribes to** | `.gitWorkingDirectory(.branchChanged)`, `.originChanged`, `.worktreeDiscovered` from EventBus |
| **Runs** | `gh pr list`, GitHub REST API via `@concurrent nonisolated` helpers |
| **Self-driven** | Polling timer (30-60s) as fallback |
| **Command-plane** | `refresh(repo:)` after git push |
| **Produces** | `ForgeEvent` envelopes on EventBus |
| **Does not** | Scan filesystem, run git commands, discover repos, mutate canonical store |

#### WorkspaceCacheCoordinator

Single consolidation consumer with three internal method groups:

```
handleTopology_*    — CANONICAL mutations (WorkspaceStore)
  Events: .topology(.repoDiscovered), .topology(.repoRemoved),
          .worktreeDiscovered, .worktreeRemoved
  Touches: WorkspaceStore (register/unregister repos+worktrees)

handleEnrichment_*  — DERIVED cache writes (WorkspaceRepoCache only)
  Events: .snapshotChanged, .branchChanged, .originChanged,
          .pullRequestCountsChanged, .checksUpdated
  Touches: WorkspaceRepoCache only

syncScope_*         — ACTOR registration management
  Operations: register/unregister worktrees with FilesystemActor, ForgeActor
  Called from topology handlers as needed
```

Method naming convention makes responsibility explicit. If coordinator grows too large, method groups become natural extraction points. Does not run git/network commands or access filesystem directly.

### Discovery — Repo Scanning

`RepoScanner` walks the filesystem from a root URL, stops at the first `.git` boundary (file or directory), caps depth at 3 levels, skips hidden directories and symlinks, validates with `git rev-parse --is-inside-work-tree`, and excludes submodules via `--show-superproject-working-tree`.

Currently used as a one-shot scan when the user clicks "Add Folder." A planned enhancement will persist the folder path as a `WatchedPath` and rescan periodically — see `docs/plans/2026-03-02-persistent-watched-path-folder-watching.md`.

> **File:** `Infrastructure/RepoScanner.swift`

### Event Namespaces

```
TopologyEvent (producer: FilesystemActor, envelope: SystemEnvelope)
  .repoDiscovered(repoPath:, parentPath:)
  .repoRemoved(repoPath:)

FilesystemEvent (producer: FilesystemActor, envelope: WorktreeEnvelope)
  .filesChanged(changeset:)
  .worktreeRegistered(worktreeId:, repoId:, rootPath:)
  .worktreeUnregistered(worktreeId:, repoId:)

GitWorkingDirectoryEvent (producer: GitWorkingDirectoryProjector, envelope: WorktreeEnvelope)
  .snapshotChanged(snapshot:)
  .branchChanged(worktreeId:, repoId:, from:, to:)
  .originChanged(repoId:, from:, to:)
  .worktreeDiscovered(repoId:, worktreePath:, branch:, isMain:)
  .worktreeRemoved(repoId:, worktreePath:)
  .diffAvailable(diffId:, worktreeId:, repoId:)

ForgeEvent (producer: ForgeActor, envelope: WorktreeEnvelope)
  .pullRequestCountsChanged(repoId:, countsByBranch:)
  .checksUpdated(repoId:, status:)
  .refreshFailed(repoId:, error:)
  .rateLimited(repoId:, retryAfter:)
```

Discovery events (`.repoDiscovered`, `.repoRemoved`) live in `SystemEnvelope` because the canonical repo does not exist yet at emit time — no repoId is available. All other workspace events live in `WorktreeEnvelope` where repoId is always present. For the full 3-tier envelope hierarchy, see [Pane Runtime Architecture — Contract 3](pane_runtime_architecture.md#contract-3-paneeventenvelope).

---

## Sidebar Data Flow

The sidebar is a pure reader. It reads structure from one store, display data from another.

```
WorkspaceStore.repos                → canonical repo/worktree structure (what exists)
WorkspaceRepoCache.repoEnrichment  → org name, display name, groupKey (how to group)
WorkspaceRepoCache.worktreeEnrichment → branch, git status (how to display)
WorkspaceRepoCache.pullRequestCounts → PR badges
WorkspaceRepoCache.notificationCounts → notification bells
WorkspaceUIStore                    → expanded groups, filter, colors (user prefs)

ZERO imperative fetches. ZERO mutations. Pure @Observable binding.
```

This is not a "join" problem — each store has one clear job. The bus ensures both are in sync. The sidebar does not do complex data merging; it reads structure from one, display data from the other.

Branch display: `WorktreeEnrichment.branch` from cache, falling back to `"detached HEAD"`. No branch field on the `Worktree` model itself.

---

## Lifecycle Flows

### App Boot (implemented)

```
1. WorkspaceStore.restore() → load repos, worktrees, panes, tabs from workspace.state.json
2. WorkspaceRepoCache.loadCache() → warm-start from workspace.cache.json
   - Sidebar renders immediately with cached enrichment data
3. WorkspaceUIStore.load() → expanded groups, filter, colors from workspace.ui.json
4. Start runtime actors (FilesystemActor, GitProjector, ForgeActor)
5. Start WorkspaceCacheCoordinator → subscribes to bus
6. replayBootTopology() — emit .repoDiscovered for each persisted repo
   - Phase A: active-pane repos first (priority)
   - Phase B: remaining repos
7. Prune stale cache entries (IDs not in restored store)
8. Actors process topology events → produce enrichment events
9. Cache converges → sidebar updates reactively
```

Boot replay uses the same `.repoDiscovered` event and same coordinator code path as live discovery. The cached data provides instant display; the replay validates and refreshes everything.

### User Adds a Folder (implemented)

```
1. User: File → Add Folder → selects /projects
2. RepoScanner().scanForGitRepos(in: /projects, maxDepth: 3)
   - Walks filesystem, stops at .git boundary, skips submodules
3. For each discovered repo path:
   → AppDelegate posts .addRepoAtPathRequested(path:) via AppEventBus
4. addRepoIfNeeded(path) for each:
   a. Dedup check (skip if path matches existing worktree)
   b. Emit .repoDiscovered on RuntimeEventBus via makeTopologyEnvelope()
5. WorkspaceCacheCoordinator.handleTopology(.repoDiscovered):
   a. Idempotent check by stableKey — skip if repo already exists
   b. Seed enrichment to .unresolved in WorkspaceRepoCache
6. PaneCoordinator.syncFilesystemRootsAndActivity() — register with actors
7. Actors start producing enrichment events → cache updates → sidebar renders
```

> **Planned enhancement:** Persist the folder as a `WatchedPath` so FilesystemActor can rescan periodically for newly cloned repos. See `docs/plans/2026-03-02-persistent-watched-path-folder-watching.md`.

### User Adds a Repo (implemented)

```
1. User: File → Add Repo → selects /projects/my-repo
2. AppDelegate validates it has a .git directory
3. If path is a child of a repo (not the repo root), offers to add the parent folder instead
4. addRepoIfNeeded(path) → same flow as step 4 above
```

### Branch Change → Forge Refresh (implemented)

```
1. User runs `git checkout feat-2` in worktree wt-1
2. FSEvents fires → FilesystemActor detects .git/HEAD change
   → emits .filesChanged (contains .git internal changes)
3. GitWorkingDirectoryProjector:
   → runs git status → detects branch changed
   → emits .branchChanged(wt-1, repo-A, from: "feat-1", to: "feat-2")
   → emits .snapshotChanged(new snapshot)
4. ForgeActor subscribes to .branchChanged (via bus fan-out):
   → immediate refresh for repo-A
   → gh pr list for new branch
   → emits .pullRequestCountsChanged
5. CacheCoordinator writes all to cache store (gets branchChanged + prCountsChanged from bus)
6. Sidebar: branch chip updates, PR badge updates
```

Note: ForgeActor gets `.branchChanged` directly from the bus fan-out. The coordinator does NOT additionally trigger ForgeActor — this prevents duplicate network refreshes.

### Repo Moved (planned, not yet implemented)

When a repo directory moves on disk, the plan is:
1. FilesystemActor detects repo gone on rescan → emits `.repoRemoved`
2. Coordinator marks panes orphaned, prunes cache, keeps canonical entries for re-association
3. User can "Locate" the repo at its new path → coordinator updates path, recomputes stableKey, re-registers with actors

---

## Ordering, Replay, and Idempotency

### Ordering Contract

Per-source `seq` counter (monotonic `UInt64`). Each source maintains its own counter starting at 1.

- Counter resets to 1 when the source actor is restarted (app relaunch)
- Reset is detectable: new `seq=1` + newer `timestamp` than last seen event from that source
- Cross-source ordering NOT guaranteed — use `timestamp` for cross-source comparison
- Within a single source, `seq` ordering is authoritative

Gap handling: if consumer sees `seq=5` after `seq=3` from same source, buffer overflowed. Cache consumer treats gaps as "full refresh needed" — re-queries source for current state. This is pragmatic: the enrichment pipeline is idempotent and stateless per-event.

### Replay

Two distinct, complementary replay layers:

- **Bus-level replay:** Per-source buffer (256 events) on EventBus for late-joining bus subscribers catching up on recent workspace events. Not persistent — on restart, actors re-emit current state via initial scan.
- **Pane-level replay (C14):** Per-pane replay buffer on PaneRuntime for UI consumers catching up on a specific pane's event stream. Distinct concern — serves UI, not coordination.

### Idempotency

Every cache write is a "set to latest value" operation, not a delta. Writing the same `WorktreeEnrichment.branch = "feat-1"` twice is a no-op. The entire enrichment pipeline is naturally idempotent by design.

Cache coordinator uses value-equality check: if the incoming snapshot matches what's already in the cache store, the write is skipped. `sourceRevision` on `WorkspaceCacheState` increments on any actual cache change. On boot, if cache is missing/corrupt/stale, coordinator sets `needsFullRebuild` and treats all events from initial scan as new.

---

## Event System Design: What It Is (and Isn't)

The event bus is a **notification mechanism** — runtime actors produce facts, the coordinator consumes them and calls store methods. This is NOT CQRS. There is no command bus, no command/event segregation, no command handlers.

### How It Works

**Events are facts about the world.** "A repo exists at this path." "Branch changed to X." "PR count is 3." Events carry data, not instructions.

**Stores are mutated by their own methods.** `WorkspaceStore.addRepo(at:)` is a direct method call, not a command dispatched through the bus. The bus does not route mutations.

**The coordinator bridges events to store methods.** `WorkspaceCacheCoordinator` subscribes to the bus, pattern-matches on events, and calls the appropriate store methods. It contains no domain logic — just "when I see X, call Y."

### Concrete Flow: User Adds a Folder

```swift
// 1. User clicks Add Folder → AppDelegate receives path
func addRepoIfNeeded(_ path: URL) {
    let normalizedPath = path.standardizedFileURL

    // 2. Direct store mutation (NOT via bus)
    let repo = store.addRepo(at: normalizedPath)

    // 3. Emit topology event so the rest of the system learns
    workspaceCacheCoordinator.consume(
        Self.makeTopologyEnvelope(repoPath: normalizedPath, source: .builtin(.coordinator))
    )

    // 4. Sync filesystem roots so actors start watching
    paneCoordinator.syncFilesystemRootsAndActivity()
}

// 5. WorkspaceCacheCoordinator handles the event:
func handleTopology(_ event: TopologyEvent) {
    switch event {
    case .repoDiscovered(let repoPath, _):
        let incomingStableKey = StableKey.fromPath(repoPath)
        let existingRepo = workspaceStore.repos.first {
            $0.repoPath == repoPath || $0.stableKey == incomingStableKey
        }
        if let repo = existingRepo {
            // Idempotent: seed enrichment only if missing
            if repoCache.repoEnrichmentByRepoId[repo.id] == nil {
                repoCache.setRepoEnrichment(.unresolved(repoId: repo.id))
            }
        }
        // ... FilesystemActor/GitProjector start producing enrichment events
    }
}

// 6. Later, GitProjector emits .snapshotChanged, .branchChanged
// 7. WorkspaceCacheCoordinator writes enrichment to WorkspaceRepoCache
// 8. Sidebar re-renders via @Observable
```

The pattern is always: **mutate the store directly → emit a fact on the bus → coordinator updates the other store**.

### What NOT to Do

- **Do not add command enums or command handlers.** Store methods ARE the commands.
- **Do not route store mutations through the bus.** The bus carries facts, not instructions.
- **Do not create separate command/event types for the same action.** One event type per fact.
- **Do not build CQRS-style read/write segregation.** Both stores are read/write via their own methods.
- **Do not make actors emit canonical topology events.** Only `AppDelegate` (user actions + boot replay) emits `.repoDiscovered`/`.repoRemoved`. Runtime actors emit observation events only (`.worktreeRegistered`, `.snapshotChanged`, etc.).

### Idempotency Contract

All topology handlers in `WorkspaceCacheCoordinator` are idempotent:

| Event | Dedup key | Behavior |
|-------|-----------|----------|
| `.repoDiscovered` | `stableKey` (SHA-256 of path) | Upsert: skip if exists, seed enrichment if missing |
| `.worktreeRegistered` | `worktreeId` (UUID) | Upsert: skip if exists |
| `.snapshotChanged` | `worktreeId` | Overwrite: latest wins |
| `.branchChanged` | `worktreeId` | Overwrite: latest wins |

Ordering tolerance: `.worktreeRegistered` arriving before `.repoDiscovered` is a safe no-op (guard + return). No crash, no queue.

### Writing Integration Tests with Events

Test the full event flow: emit an event → coordinator processes it → assert both stores updated.

```swift
@Suite struct WorkspaceCacheCoordinatorTests {
    @Test func repoDiscovered_seedsEnrichmentInCache() async {
        // Arrange
        let store = WorkspaceStore()
        let repoCache = WorkspaceRepoCache()
        let coordinator = WorkspaceCacheCoordinator(
            workspaceStore: store,
            repoCache: repoCache
        )
        let repoPath = URL(fileURLWithPath: "/tmp/test-repo")
        store.addRepo(at: repoPath)

        // Act — emit the topology event
        let envelope = AppDelegate.makeTopologyEnvelope(
            repoPath: repoPath,
            source: .builtin(.coordinator)
        )
        coordinator.consume(envelope)

        // Assert — cache has unresolved enrichment for the repo
        let repo = store.repos.first!
        let enrichment = repoCache.repoEnrichmentByRepoId[repo.id]
        #expect(enrichment != nil)
    }

    @Test func repoDiscovered_idempotent_doesNotDuplicate() async {
        // Arrange
        let store = WorkspaceStore()
        let repoCache = WorkspaceRepoCache()
        let coordinator = WorkspaceCacheCoordinator(
            workspaceStore: store,
            repoCache: repoCache
        )
        let repoPath = URL(fileURLWithPath: "/tmp/test-repo")
        store.addRepo(at: repoPath)

        // Act — emit the same event twice
        let envelope = AppDelegate.makeTopologyEnvelope(
            repoPath: repoPath,
            source: .builtin(.coordinator)
        )
        coordinator.consume(envelope)
        coordinator.consume(envelope)

        // Assert — still only one repo, one enrichment entry
        #expect(store.repos.count == 1)
        #expect(repoCache.repoEnrichmentByRepoId.count == 1)
    }
}
```

Key testing principles:
- **Test the event path, not the store in isolation.** The coordinator IS the glue — test it with real stores.
- **Assert on both stores.** A topology event should update both `WorkspaceStore` (canonical) and `WorkspaceRepoCache` (enrichment).
- **Test idempotency.** Emit the same event twice. Assert no duplicates.
- **Test ordering tolerance.** Emit events in wrong order. Assert no crash.

---

## Cross-References

- **Event envelope hierarchy:** [Pane Runtime Architecture — Contract 3](pane_runtime_architecture.md#contract-3-paneeventenvelope) — `RuntimeEnvelope` 3-tier discriminated union (`SystemEnvelope`, `WorktreeEnvelope`, `PaneEnvelope`)
- **Actor threading model:** [EventBus Design](pane_runtime_eventbus_design.md) — connection patterns, `@concurrent` helpers, multiplexing rule
- **Pane-level replay:** [Pane Runtime Architecture — Contract 14](pane_runtime_architecture.md#contract-14-replay-buffer)
- **Filesystem batching:** [Pane Runtime Architecture — Contract 6](pane_runtime_architecture.md#contract-6-filesystem-batching) — debounce/max-latency
- **Component overview:** [Component Architecture](component_architecture.md) — data model, store boundaries, coordinator role
- **Pane identity and restore:** [Session Lifecycle](session_lifecycle.md) — pane identity contract, restore sequencing, undo/residency states
- **Surface lifecycle:** [Surface Architecture](ghostty_surface_architecture.md) — Ghostty surface ownership, health monitoring
- **Planned: persistent folder watching:** `docs/plans/2026-03-02-persistent-watched-path-folder-watching.md` — `WatchedPath` model, periodic rescan
