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
  Contains: watchedPaths, canonical repos, canonical worktrees, panes, tabs, layouts

TIER B: DERIVED CACHE (rebuildable from Tier A + actors)
  File: ~/.agentstudio/workspaces/<id>/workspace.cache.json
  Owner: WorkspaceCacheStore (@MainActor, @Observable)
  Mutated by: WorkspaceCacheCoordinator only (event-driven)
  Contains: repo enrichment, worktree enrichment, PR counts, notification counts

TIER C: UI STATE (preferences, non-structural)
  File: ~/.agentstudio/workspaces/<id>/workspace.ui.json
  Owner: WorkspaceUIStore (@MainActor, @Observable)
  Mutated by: sidebar view actions only
  Contains: expanded groups, checkout colors, filter state
```

### Tier A: Canonical Models

```swift
/// User-added path to watch. Either a direct repo or a parent folder.
struct WatchedPath: Codable, Identifiable, Hashable {
    let id: UUID
    var path: URL
    var kind: WatchedPathKind
    var addedAt: Date
}

enum WatchedPathKind: String, Codable {
    case parentFolder   // scan for repos up to 3 levels, stop at .git
    case directRepo     // single git repo, watch directly
}

/// Canonical repo identity. Only stable, user-facing data.
/// No inferred fields (org, remote, upstream — those are cache).
struct CanonicalRepo: Codable, Identifiable, Hashable {
    let id: UUID
    var repoPath: URL              // filesystem path (user-added or discovered)
    var name: String               // folder name from path (stable, not inferred)
    var stableKey: String          // SHA-256(path), secondary index for rebuild
    var watchedPathId: UUID?       // which watched path discovered this (nil = direct add)
    var addedAt: Date
}

/// Canonical worktree identity. Stable relationship to parent repo.
/// No branch, no status, no agent — those are derived/runtime.
struct CanonicalWorktree: Codable, Identifiable, Hashable {
    let id: UUID
    var path: URL                  // filesystem path
    var repoId: UUID               // relationship to parent CanonicalRepo
    var stableKey: String          // SHA-256(path), secondary index for rebuild
}
```

**What is NOT canonical:**
- `organizationName`, `origin`, `upstream` → RepoEnrichment (cache)
- `branch`, `isMainWorktree` → WorktreeEnrichment (cache)
- `agent`, `status` → derived from pane state at query time
- `updatedAt` on repo → removed (was the sidebar loop trigger)

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
CONFIG FILE (watchedPaths, canonical repos/worktrees, panes/tabs)
      │
      │ read at boot + on mutation
      ▼
FilesystemActor (raw filesystem I/O)
  .parentFolder → triggered rescan (maxDepth 3, stop at .git)
  .directRepo / worktree roots → deep FSEvents watch
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
                              → compute enrichment → write to WorkspaceCacheStore
                              → register with FilesystemActor (deep watch)
                              → register with ForgeActor (if has remote)
  .topology(.repoRemoved) → unregister actors → mark panes orphaned → prune cache
  .snapshotChanged → write to cache store
  .branchChanged → write to cache store (ForgeActor gets its own copy via bus fan-out)
  .pullRequestCountsChanged → map branch→worktreeId → write to cache
      │
      ▼
WorkspaceCacheStore (@Observable, passive)
  → persisted to cache file on debounced schedule
      │
      ▼
SIDEBAR (pure reader of WorkspaceStore + CacheStore + UIStore)
```

### Actor Responsibilities

#### FilesystemActor

| Aspect | Detail |
|--------|--------|
| **Owns** | FSEvents ingestion, path filtering, debounce, batching |
| **Scope** | Parent folder paths (triggered rescan) + worktree root paths (deep watch) |
| **Reads** | Config (watched paths) |
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

handleEnrichment_*  — DERIVED cache writes (WorkspaceCacheStore only)
  Events: .snapshotChanged, .branchChanged, .originChanged,
          .pullRequestCountsChanged, .checksUpdated
  Touches: WorkspaceCacheStore only

syncScope_*         — ACTOR registration management
  Operations: register/unregister worktrees with FilesystemActor, ForgeActor
  Called from topology handlers as needed
```

Method naming convention makes responsibility explicit. If coordinator grows too large, method groups become natural extraction points. Does not run git/network commands or access filesystem directly.

### Discovery — Parent Folder Scanning

Smart scanning: walk filesystem, stop at first `.git` boundary. 3-level max depth cap. Avoids scanning into submodules. `RepoScanner` already implements this correctly. Trigger-based rescan (not continuous FSEvents on parent folders). Triggers: explicit refresh, git topology change, lazy timer.

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

The sidebar is a pure reader. It does not fetch, compute, or mutate any workspace state.

```
WorkspaceStore.repos                → canonical repo identity, structure
WorkspaceStore.worktreeAssignments  → canonical worktree-to-repo mapping
WorkspaceCacheStore.repoEnrichment  → org name, display name, grouping
WorkspaceCacheStore.worktreeEnrichment → branch, git status
WorkspaceCacheStore.pullRequestCounts → PR badges
WorkspaceUIStore                    → expanded groups, filter, colors

ZERO imperative fetches. ZERO mutations. Pure @Observable binding.
```

This eliminates the sidebar self-trigger loop in the current code: `.task(id: reposFingerprint)` → `refreshWorktrees()` → canonical mutation → fingerprint change → re-trigger. With the new architecture, the sidebar observes store changes reactively and never triggers mutations.

---

## Lifecycle Flows

### App Boot

```
1. Load config file → WorkspaceStore (watchedPaths, repos, worktrees, panes, tabs)
2. Load cache file → WorkspaceCacheStore (enrichment, PR counts)
   - If cache exists and valid: sidebar renders immediately with cached data
   - If cache missing/stale: sidebar renders structural skeleton
3. Load UI state → WorkspaceUIStore (expanded groups, filter)
4. Start EventBus
5. Start FilesystemActor → reads watchedPaths, begins watching
6. Start GitWorkingDirectoryProjector → subscribes to bus
7. Start ForgeActor → subscribes to bus
8. Start WorkspaceCacheCoordinator → subscribes to bus
9. FilesystemActor triggers initial rescan of parent folders
10. Pipeline fills cache → sidebar updates reactively
```

### User Adds Parent Folder

```
1. User: File → Add Folder → selects /projects
2. WorkspaceStore.addWatchedPath(.parentFolder, /projects)
3. Config file saved (debounced)
4. repoWorktreesDidChangeHook fires
5. PaneCoordinator → FilesystemActor.registerParentFolder(/projects)
6. FilesystemActor runs rescan (maxDepth 3, stop at .git)
7. For each discovered repo:
   → emits SystemEnvelope(.topology(.repoDiscovered(repoPath, parentPath=/projects)))
8. CacheCoordinator receives .topology(.repoDiscovered):
   a. WorkspaceStore.registerDiscoveredRepo → CanonicalRepo (UUID assigned)
   b. GitWorkingDirectoryProjector runs git worktree list
   c. emits .worktreeDiscovered for each (repoId now known)
9. CacheCoordinator receives .worktreeDiscovered:
   a. WorkspaceStore.registerWorktree → CanonicalWorktree
   b. FilesystemActor.register(worktreeId:, rootPath:) for deep watch
   c. ForgeActor.register(repoId:, remoteURL:)
10. GitWorkingDirectoryProjector emits .snapshotChanged, .branchChanged
11. ForgeActor emits .pullRequestCountsChanged
12. CacheCoordinator writes all enrichment to cache store
13. Sidebar reactively shows new repos with full enrichment
```

### Repo Moved

```
1. User moves /projects/my-repo to /archive/my-repo
2. FilesystemActor shallow watch (on next rescan) detects repo gone
   → emits SystemEnvelope(.topology(.repoRemoved(repoPath: /projects/my-repo)))
3. CacheCoordinator receives .topology(.repoRemoved):
   a. Finds canonical repo by path
   b. All panes referencing worktrees of that repo:
      pane.residency = .orphaned(.worktreeNotFound)
   c. Unregister from FilesystemActor + ForgeActor
   d. Prune from WorkspaceCacheStore
   e. Keep CanonicalRepo + CanonicalWorktree entries (for re-association)
4. Sidebar shows orphaned pane: "Worktree not found" + "Locate" / "Close"

5. User clicks "Locate repo" → selects /archive/my-repo
6. Coordinator:
   a. Updates CanonicalRepo.repoPath → /archive/my-repo
   b. Recomputes CanonicalRepo.stableKey = SHA-256(new path)
   c. Runs `git worktree repair` to fix worktree metadata for new location
   d. Runs `git worktree list --porcelain -z` → updates CanonicalWorktree paths + stableKeys
   e. Re-registers with FilesystemActor + ForgeActor
   f. Full enrichment pipeline runs
   g. Pane residency = .active (UUIDs unchanged, pane links survive)
```

### Branch Change → Forge Refresh

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

## Migration from Current Models

The current `Repo` and `Worktree` models are contaminated — they mix canonical config, inferred data, discovered state, and runtime state in single structs:

```
CURRENT Repo (contaminated):
  id, name, repoPath, createdAt         ← CONFIG → CanonicalRepo
  organizationName, origin, upstream    ← INFERRED → RepoEnrichment (cache)
  worktrees: [Worktree]                 ← DISCOVERED → CanonicalWorktree (canonical)
  updatedAt                              ← BUMPED BY DERIVED → REMOVED

CURRENT Worktree (contaminated):
  id, name, path, branch, isMainWorktree ← DISCOVERED → split across canonical + cache
  agent, status                           ← APP STATE → derived from pane state

PaneContextFacets (all optional, no type enforcement):
  repoId?, repoName?, worktreeId?, worktreeName?
  cwd?, parentFolder?, organizationName?, origin?, upstream?
```

The migration splits each field to its correct tier. The canonical store holds only user intent and stable identity. The cache store holds everything that can be rebuilt from actors. Runtime state is queried, not stored.

### Direct Store Mutation Callsites (12 total)

All callsites that bypass the coordinator must be routed through coordinator commands:

**MainSplitViewController.swift** — 7 callsites (lines 368, 371, 480, 482, 489, 492, 502)
**RepoSidebarContentView.swift** — 5 callsites (lines 294, 301, 479, 481, 512)

All follow the same anti-pattern: `WorktrunkService.shared.discoverWorktrees(for:)` → `store.updateRepoWorktrees()`. In the new design, sidebar views dispatch user intents as commands to the coordinator. The coordinator translates commands into the event flow.

---

## Prerequisite: FSEvents Noop

Both `FilesystemActor` and `FilesystemGitPipeline` default to `NoopFSEventStreamClient` (log `TODO(LUNA-349)`). The subscription and transformation logic exists — only the real FSEvents source is missing. This is the prerequisite for the entire enrichment pipeline.

---

## Cross-References

- **Event envelope hierarchy:** [Pane Runtime Architecture — Contract 3](pane_runtime_architecture.md#contract-3-event-envelope) defines the envelope contract — current `PaneEventEnvelope` and target `RuntimeEnvelope` 3-tier discriminated union
- **Actor threading model:** [EventBus Design](pane_runtime_eventbus_design.md) defines connection patterns and `@concurrent` helpers
- **Pane-level replay:** [Pane Runtime Architecture — Contract 14](pane_runtime_architecture.md#contract-14-replay-buffer)
- **Filesystem batching:** [Pane Runtime Architecture — Contract 6](pane_runtime_architecture.md#contract-6-filesystem-batching) defines debounce/max-latency
- **Component overview:** [Component Architecture](component_architecture.md) — data model, service layer, persistence
- **Pane identity and restore:** [Session Lifecycle](session_lifecycle.md) — pane identity contract (`PaneId` as cross-feature identity), restore sequencing, undo/residency states. Pane references (`facets.worktreeId`) link to `CanonicalWorktree.id` (UUID) defined here.
- **Surface lifecycle:** [Surface Architecture](ghostty_surface_architecture.md) — Ghostty surface ownership, health monitoring. Surface attach/detach depends on pane residency (`.active`, `.pendingUndo`, `.backgrounded`) which is tracked in `WorkspaceStore`.
