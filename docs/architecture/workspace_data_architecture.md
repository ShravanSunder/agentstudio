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
/// Repo identity resolution is explicit. The cache distinguishes
/// "still resolving", "confirmed local-only", and "resolved remote".
enum RepoEnrichment: Codable, Sendable, Equatable {
    case awaitingOrigin(repoId: UUID)
    case resolvedLocal(repoId: UUID, identity: RepoIdentity, updatedAt: Date)
    case resolvedRemote(repoId: UUID, raw: RawRepoOrigin, identity: RepoIdentity, updatedAt: Date)
}

struct RawRepoOrigin: Codable, Sendable, Equatable {
    var origin: String
    var upstream: String?
}

struct RepoIdentity: Codable, Sendable, Equatable {
    var groupKey: String
    var remoteSlug: String?
    var organizationName: String?
    var displayName: String
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
  emits: .snapshotChanged, .branchChanged, .originChanged, .originUnavailable
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
  Events: .snapshotChanged, .branchChanged, .originChanged, .originUnavailable,
          .pullRequestCountsChanged, .checksUpdated
  Touches: WorkspaceRepoCache only

syncScope_*         — ACTOR registration management
  Operations: register/unregister worktrees with FilesystemActor, ForgeActor
  Called from topology handlers as needed
```

Method naming convention makes responsibility explicit. If coordinator grows too large, method groups become natural extraction points. Does not run git/network commands or access filesystem directly.

### Discovery — Repo Scanning

`RepoScanner` walks the filesystem from a root URL, stops at the first `.git` boundary (file or directory), caps depth at `RepoScanner.defaultMaxDepth` (4 levels), skips hidden directories and symlinks, validates with `git rev-parse --is-inside-work-tree`, and excludes submodules via `--show-superproject-working-tree`.

Used by `FilesystemActor` as the blocking filesystem walk behind watched-folder refresh. Add Folder no longer calls `RepoScanner` directly from `AppDelegate`; the scan is owned by the watched-folder command path.

> **File:** `Infrastructure/RepoScanner.swift`

### Event Namespaces

```
TopologyEvent (envelope: SystemEnvelope, all via bus)
  .repoDiscovered(repoPath:, parentPath:)   — producer: AppDelegate (boot replay), FilesystemActor (watched folder diff)
  .repoRemoved(repoPath:)                   — producer: FilesystemActor (watched folder diff)
  .worktreeRegistered(worktreeId:, repoId:, rootPath:) — producer: FilesystemActor
  .worktreeUnregistered(worktreeId:, repoId:)          — producer: FilesystemActor

FilesystemEvent (producer: FilesystemActor, envelope: WorktreeEnvelope)
  .filesChanged(changeset:)
  .worktreeRegistered(worktreeId:, repoId:, rootPath:)
  .worktreeUnregistered(worktreeId:, repoId:)

GitWorkingDirectoryEvent (producer: GitWorkingDirectoryProjector, envelope: WorktreeEnvelope)
  .snapshotChanged(snapshot:)
  .branchChanged(worktreeId:, repoId:, from:, to:)
  .originChanged(repoId:, from:, to:)
  .originUnavailable(repoId:)
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
2. AppDelegate persists watched scope:
   → store.addWatchedPath(/projects)
3. AppDelegate calls watched-folder command:
   → refreshWatchedFolders(paths: store.watchedPaths.map(\.path))
4. FilesystemActor performs the authoritative scan:
   a. Reconcile watched-folder registrations
   b. Scan watched roots via RepoScanner
   c. Diff current repo set against prior baseline
   d. Emit .repoDiscovered / .repoRemoved on RuntimeEventBus
   e. Return WatchedFolderRefreshSummary to caller
5. AppDelegate uses returned summary for immediate UX:
   a. If zero repos under /projects → show empty-folder alert
   b. Does NOT emit topology facts directly
6. WorkspaceCacheCoordinator.handleTopology(.repoDiscovered):
   a. Idempotent check by stableKey — skip if repo already exists
   b. Seed enrichment to .awaitingOrigin in WorkspaceRepoCache
7. PaneCoordinator reacts from topology facts and syncs registered worktree roots
8. Actors start producing enrichment events → cache updates → sidebar renders
```

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
func handleAddFolderRequested(path: URL) async {
    let rootURL = path.standardizedFileURL

    // 2. Persist the watched path (direct store mutation)
    store.addWatchedPath(rootURL)

    // 3. Call the focused watched-folder command surface.
    // Do not depend on the concrete FilesystemGitPipeline type here.
    let refreshSummary = await watchedFolderCommands.refreshWatchedFolders(
        store.watchedPaths.map(\.path)
    )

    // 4. Use the returned summary for immediate UX only.
    // Topology facts come from FilesystemActor, not AppDelegate.
    let repoPaths = refreshSummary.repoPaths(in: rootURL)
    if repoPaths.isEmpty {
        showEmptyFolderAlert(for: rootURL)
    }
}

// 5. WorkspaceCacheCoordinator's bus subscription picks up topology facts:
func handleTopology(_ event: TopologyEvent) {
    switch event {
    case .repoDiscovered(let repoPath, _):
        let incomingStableKey = StableKey.fromPath(repoPath)
        let existingRepo = workspaceStore.repos.first {
            $0.repoPath == repoPath || $0.stableKey == incomingStableKey
        }
        if let repo = existingRepo {
            if repoCache.repoEnrichmentByRepoId[repo.id] == nil {
                repoCache.setRepoEnrichment(.awaitingOrigin(repoId: repo.id))
            }
        } else {
            let repo = workspaceStore.addRepo(at: repoPath)
            repoCache.setRepoEnrichment(.awaitingOrigin(repoId: repo.id))
        }
    }
}

// 6. Later, GitProjector emits .snapshotChanged, .branchChanged
// 7. WorkspaceCacheCoordinator writes enrichment to WorkspaceRepoCache
// 8. Sidebar re-renders via @Observable
```

The pattern is: **persist user intent → call watched-folder command → actor scans once and posts facts via bus → coordinator processes all topology uniformly**.

### Capability Protocol Rule

The actor or pipeline that owns the work is not automatically the type that
feature code should depend on.

```text
concurrency boundary != dependency boundary
```

Use focused capability protocols for direct commands:

```text
AppDelegate
  |
  v
WatchedFolderCommandHandling
  |
  v
FilesystemGitPipeline
  |
  v
FilesystemActor
```

This keeps the caller's dependency honest:

```text
AppDelegate may ask for watched-folder refresh.
AppDelegate may not reach into unrelated pipeline methods.
```

Composition-root rule:

```text
- composition root may know the concrete pipeline type
- feature consumers should store only the focused capability they need
- do not introduce a generic command executor abstraction
```

### Topology Intake: Single Bus Pathway

All `.repoDiscovered` events flow through the `EventBus`. The coordinator's bus subscription is the single intake for all topology facts. There are no direct `coordinator.consume()` calls for topology.

**Authority model:** The user authorizes a scope (by clicking Add Folder → `store.addWatchedPath()`). The actor executes within that authorized scope (rescans only persisted watched folders). The bus carries the results.

```
User: "Watch /projects"
         │
         ▼
AppDelegate ──► store.addWatchedPath(/projects)     [authority persisted]
         │
         ▼
WatchedFolderCommandHandling ──► FilesystemActor    [direct command]
         │
         ├── return WatchedFolderRefreshSummary     [command result]
         │
         ▼
AppDelegate uses summary for immediate UX           [empty-folder alert]
         │
         ▼
FilesystemActor ──► bus.post(.repoDiscovered/.repoRemoved) [reports facts]
         │
         ▼
Bus ──► WorkspaceCacheCoordinator                   [single intake]
         │
         ├── idempotent upsert (dedup by stableKey)
         ├── seed enrichment in WorkspaceRepoCache
         └── sidebar re-renders via @Observable
```

Boot replay follows the same bus path:

```
Boot: restore() loads watchedPaths + repos
         │
         ├── AppDelegate posts .repoDiscovered on bus for each persisted repo
         ├── scopeSyncHandler(.updateWatchedFolders) → actor starts watching
         │         │
         │         └── actor rescans → posts .repoDiscovered for anything new
         │
         ▼
Bus ──► Coordinator (single intake, dedup by stableKey)
```

**Constraint:** FilesystemActor may emit `.repoDiscovered` and `.repoRemoved` only for paths under a persisted watched scope (`store.watchedPaths`). This is structurally enforced — watched-folder refresh scans only `watchedFolderIds` paths and diffs against the actor-owned baseline for those roots. The `parentPath` field on `.repoDiscovered` provides traceability back to the watched scope without coupling the event type to `WatchedPath.id`.

### What NOT to Do

- **Do not add command enums or command handlers.** Store methods ARE the commands.
- **Do not route store mutations through the bus.** The bus carries facts, not instructions.
- **Do not create separate command/event types for the same action.** One event type per fact.
- **Do not build CQRS-style read/write segregation.** Both stores are read/write via their own methods.
- **Actors may emit `.repoDiscovered` and `.repoRemoved` only within user-authorized watched-folder scopes.** `FilesystemActor` rescans persisted `WatchedPath` folders, diffs against its prior baseline, and posts topology facts on the bus. This is not autonomous discovery — the user delegated authority via Add Folder. All topology events flow through the unified bus pathway.

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

Test the full event flow: emit an event → coordinator processes it → assert both stores updated. Tests call `coordinator.consume(_:)` directly — this is a deliberate test seam. App code must always flow through the bus; tests bypass it to verify coordinator logic in isolation.

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

        // Assert — cache is waiting for origin resolution for the repo
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
