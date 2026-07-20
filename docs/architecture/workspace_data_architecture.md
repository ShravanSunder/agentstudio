# Workspace Data Architecture

> **Status:** Authoritative spec for workspace-level data model, persistence, enrichment pipeline, and sidebar data flow.
> **Target:** Swift 6.2 / macOS 26
> **Companion docs:** [Pane Runtime Architecture](pane_runtime_architecture.md) (event envelope contracts, pane-level concerns), [EventBus Design](pane_runtime_eventbus_design.md) (actor threading, connection patterns), [Component Architecture](component_architecture.md) (structural overview), [Atom Persistence Boundaries](atom_persistence_boundaries.md) (write-owner atom and SQLite boundary model)

## TL;DR

Workspace state is split into three persistence tiers: canonical config (user intent), derived cache (enrichment), and UI state (preferences). A sequential enrichment pipeline — `FilesystemActor → GitWorkingDirectoryProjector → ForgeActor` — produces events on the `EventBus`. A single `WorkspaceCacheCoordinator` consumes all events, writing topology changes to the canonical store and enrichment data to the cache store. The sidebar is a pure reader of all three stores via `@Observable` binding — zero imperative fetches, zero mutations.

Normal boot opens `core.sqlite` and the selected workspace's
`<workspace-id>.local.sqlite` through one strict SQLite composition path.
Workspace composition JSON is not a boot, import, migration, fallback, or
recovery source. Valid completed core/local snapshots load exactly. Only a
newly created empty SQLite store may bootstrap one UUIDv7-backed empty
workspace. Missing, incomplete, corrupt, or invalid existing composition fails
before atom installation or terminal activation and is never repaired,
quarantined, recreated, or rewritten by startup. Historical GRDB schema
migrations remain so valid older databases can open; preference/settings JSON
and independently owned cache import policies remain separate.

---

## Three Persistence Tiers

Data flows DOWN only — tier N never reads tier N+1.

```
TIER A: CANONICAL CONFIG (source of truth, user intent)
  Live source: ~/.agentstudio/core.sqlite
  Owner: canonical workspace atoms + WorkspaceStore persistence wrapper
  Mutated by: explicit user actions + topology consumer (discovery events)
  Contains: canonical repos, canonical worktrees, panes, tabs, layouts

TIER B: CACHE FILE (rebuildable enrichment + local target memory)
  Live source: ~/.agentstudio/workspaces/<id>.local.sqlite
  Legacy import source: ~/.agentstudio/workspaces/<id>/workspace.cache.json
  Owner: RepoEnrichmentCacheAtom + RecentWorkspaceTargetAtom
  Mutated by: WorkspaceCacheCoordinator for enrichment, workspace activity
              flows for recent target memory
  Contains: repo enrichment, worktree enrichment, PR counts,
           local recent workspace targets
           (notification unread counts are derived from
            InboxNotificationAtom.unreadCount(forWorktreeId:)
            per LUNA-361)

TIER C: UI STATE (preferences, non-structural + composition state)
  Live sources: ~/.agentstudio/workspaces/<id>.settings.json and
                ~/.agentstudio/workspaces/<id>.local.sqlite
  Legacy import sources: ~/.agentstudio/workspaces/<id>/workspace.ui.json,
                         workspace.sidebar-cache.json,
                         notification-inbox.json
  Owner: WorkspaceSidebarMemoryAtom (@MainActor, @Observable)
  Mutated by: sidebar view actions, MainSplitViewController
              (publishing sidebar collapsed state), composite commands
              (⌘I / ⌘S), and repo sidebar filter actions
  Contains: filter state, sidebar collapsed state, sidebar surface
```

Only the enrichment/rebuild metadata slice is rebuildable from actors. Recent
workspace targets are local UX memory stored in this companion file until the
SQLite cutover gives them their own local table. If the whole cache file is
corrupt, `RepoCacheStore` quarantines it and resets both slices; enrichment then
rebuilds, while recent targets intentionally start empty.

> **Note on composition state.** `sidebarCollapsed` and `sidebarSurface` live on `WorkspaceSidebarMemoryAtom` as workspace-scoped shell memory. `sidebarHasFocus` lives on `SidebarFocusRuntimeAtom` and is runtime-only. `WorkspaceSidebarState` composes both for UI callers. See [directory_structure.md — composition state vs feature state](directory_structure.md).

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
- PR counts → `RepoEnrichmentCacheAtom` dictionaries
- Notification unread counts → `InboxNotificationAtom.unreadCount(forWorktreeId:)` (per LUNA-361; moved out of `RepoCacheAtom`)

### Identity Semantics

Two identity types serve different purposes:

- **UUID** is the primary identity for all runtime references: pane links, event envelopes, cache keys, actor scope. UUIDs never change, even on repo/worktree move.
- **stableKey** (SHA-256 of path) is a secondary index for rebuild/re-association. If workspace config is wiped and regenerated, re-adding the same path produces the same stableKey, enabling matching against previous canonical entries.

On repo move: UUID preserved. Path updated. stableKey recomputed from new path. Pane links use UUID and survive moves. stableKey changing is correct — the path IS different.

Duplicate prevention on discovery: coordinator checks UUID first (existing canonical), then stableKey (re-association after config rebuild). Never creates a duplicate entry.

Pane references: `Pane.metadata.facets.worktreeId` references `CanonicalWorktree.id` (UUID). Since canonical worktrees have stable UUIDs, pane references survive cache rebuilds and repo moves.

Pane metadata has two identity channels:

- `PaneMetadata.source` is fixed launch provenance. It records where the pane
  started: worktree source or floating source plus launch directory. Do not add
  `startingRepoId` or `startingWorktreeId` parallel fields.
- `PaneMetadata.facets` is live identity. Runtime cwd changes refresh
  `facets.cwd`, `facets.repoId`, and `facets.worktreeId` through
  `WorkspaceSurfaceCoordinator`, which already receives surface/runtime cwd facts and can
  resolve the current repository topology.

If a pane's cwd leaves all known worktrees, live repo/worktree facets clear
while `source` remains unchanged. User-authored `PaneMetadata.note` is neither
launch provenance nor derived identity; it is a persisted pane label used for
collapsed display and `$` search.

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

/// Cache projection shape. Live storage is local SQLite when available;
/// legacy JSON remains an import/recovery source.
struct WorkspaceCacheState: Codable {
    var workspaceId: UUID
    var sourceRevision: UInt64          // monotonic, incremented on any cache write
    var lastRebuiltAt: Date
    var repoEnrichment: [UUID: RepoEnrichment]           // keyed by CanonicalRepo.id
    var worktreeEnrichment: [UUID: WorktreeEnrichment]    // keyed by CanonicalWorktree.id
    var pullRequestCounts: [UUID: Int]                     // keyed by CanonicalWorktree.id
    // notificationCounts removed per LUNA-361: unread counts are now
    // derived from InboxNotificationAtom.unreadCount(forWorktreeId:)
    // in Features/InboxNotification/State/MainActor/Atoms/, not stored
    // in the cache tier. The bell pill reads directly from the atom.
}
```

The live `RepoEnrichmentCacheAtom` does not expose those dictionaries as the
hot observation surface. It owns each repo-cache lane through keyed
`AtomEntityMap` slots:

```swift
AtomEntityMap<UUID, RepoEnrichment>       // keyed by CanonicalRepo.id
AtomEntityMap<UUID, WorktreeEnrichment>   // keyed by CanonicalWorktree.id
AtomEntityMap<UUID, Int>                  // pull request count keyed by CanonicalWorktree.id
```

`RepoWorktreeCacheFacts` is a composed read result for surfaces that really need
both `WorktreeEnrichment?` and `pullRequestCount?`, such as status chips. Branch
labels, trace identity, tab titles, and command-bar rows should read
`worktreeEnrichment(for:)` so PR-count changes do not wake branch-only readers.
Dictionary-shaped snapshots remain available for SQLite/legacy persistence,
boot pruning, and cold batch projection. Hot UI code should prefer
`repoEnrichment(for:)`, `worktreeEnrichment(for:)`, `pullRequestCount(for:)`, or
`worktreeFacts(for:)` unless a broader snapshot path is explicitly measured and
justified.

### Tier C: Sidebar Local UX Memory

```swift
struct WorkspaceSidebarExpandedGroupState: Codable {
    var expandedGroups: Set<String>        // groupKey strings
}
```

`expandedGroups` is local workspace memory owned by `SidebarExpandedGroupAtom`.

### Tier D: Sidebar Settings-Bound Preferences

Sidebar settings intentionally do not own checkout colors. Repo/sidebar
presentation uses automatic colors, while `SidebarCheckoutColorAtom` remains a
legacy cleanup surface only. `WorkspaceSettingsStore` must ignore and clear
legacy checkout-color payloads instead of writing them back to
`<workspace-id>.settings.json`.

### Tier E: Workspace UI State

```swift
struct WorkspaceUIState: Codable {
    var filterVisible: Bool
    var filterText: String

    // Composition state (added LUNA-361) — app-wide UI shell state
    var sidebarCollapsed: Bool             // OWNERSHIP MOVE (LUNA-361):
                                           //   was owned by MainSplitView-
                                           //   Controller + UserDefaults
                                           //   key "sidebarCollapsed";
                                           //   now atom-owned + persisted
                                           //   in workspace.ui.json.
                                           //   Greenfield cutover: no
                                           //   dual-write, no migration
                                           //   from the legacy UserDefaults
                                           //   value. UserDefaults key is
                                           //   dead code after LUNA-361.
    var sidebarSurface: SidebarSurface     // .repos | .inbox; new surfaces
                                           //   extend the enum monotonically
    // sidebarHasFocus is NOT persisted — runtime-only, resets to false
    // on launch. Published by each sidebar surface view via @FocusState.
}
```

---

## Enrichment Pipeline

Sequential enrichment facts still travel through EventBus, but workspace
filesystem projection has two effect shapes. Boot, explicit rebuild, and an
accepted topology delta request full reconciliation. Ordinary pane mount,
removal, CWD, and active-pane changes use affected-key effects and do not
rebuild the full projection.

```
WORKSPACE STATE (canonical repos/worktrees, panes/tabs)
      │
      │ restored at boot → topology events replayed on bus (.notScanned)
      ▼
FilesystemActor (raw filesystem I/O)
  watched folder scan via RepoScanner:
    - classifies .git directory (clone root) vs .git file (linked worktree)
    - groups linked worktrees under parent clones into ScannedRepoGroup
    - diffs grouped state per watched folder, global dedup for removes
  worktree roots → deep FSEvents watch (DarwinFSEventStreamClient)
  emits: SystemEnvelope(.topology(.repoDiscovered(linkedWorktrees: .scanned([...]))))
         SystemEnvelope(.topology(.repoRemoved))
         WorktreeEnvelope(.filesystem(.filesChanged))
      │
      │ posts to EventBus<RuntimeEnvelope>
      ▼
GitWorkingDirectoryProjector (local git enrichment)
  subscribes to .filesystem(.filesChanged)
  runs: git status, git branch, git remote
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
WorkspaceCacheCoordinator (@MainActor, topology accumulator)
  .topology(.repoDiscovered, linkedWorktrees: .scanned):
    → WorktreeReconciler.reconcile(existing, discovered) → (merged, delta)
    → reconcileDiscoveredWorktrees(repoId, merged)
    → cache prune for delta.removedWorktrees
    → topologyEffectHandler.topologyDidChange(delta) → WorkspaceSurfaceCoordinator
  .topology(.repoDiscovered, linkedWorktrees: .notScanned):
    → register/reassociate repo only, skip worktree reconciliation (boot replay)
  .topology(.repoRemoved) → mark unavailable → orphan panes → prune cache
  .snapshotChanged → write to cache store
  .branchChanged → write to cache store (ForgeActor gets its own copy via bus fan-out)
  .pullRequestCountsChanged → map branch→worktreeId → write to cache
      │
      │ topology effects via TopologyEffectHandler (NOT bus):
      ▼
WorkspaceSurfaceCoordinator (ordered post-topology effects)
  topologyDidChange(delta):
    → orphanPanesForWorktree for delta.removedWorktrees
    → full filesystem reconciliation for accepted topology delta
  ordinary pane/CWD/active changes:
    → typed affected-key effect admission
    → pane or active-worktree projection only
      │
      ▼
RepoEnrichmentCacheAtom + RecentWorkspaceTargetAtom (@Observable, passive)
  → keyed atom slots for hot UI reads
  → snapshot bridges persisted to local SQLite or legacy cache JSON
      │
      ▼
SIDEBAR (pure reader of canonical atoms + RepoCacheAtom read surface + WorkspaceSidebarState)
```

### Actor Responsibilities

#### FilesystemActor

| Aspect | Detail |
|--------|--------|
| **Owns** | FSEvents ingestion via DarwinFSEventStreamClient, path filtering, debounce, batching |
| **Scope** | Worktree root paths (deep FSEvents watch) |
| **Reads** | Registered worktree paths from WorkspaceSurfaceCoordinator sync |
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

Single topology accumulator with three internal method groups. For topology events with `LinkedWorktreeInfo`, uses `WorktreeReconciler` (pure function) to compute a `WorktreeTopologyDelta`, then delegates ordered effects to an injected `TopologyEffectHandler`.

```
handleTopology_*    — CANONICAL mutations (WorkspaceStore)
  Events: .topology(.repoDiscovered), .topology(.repoRemoved),
          .worktreeDiscovered, .worktreeRemoved
  Touches: WorkspaceStore (register/unregister repos+worktrees)
  For .repoDiscovered with .scanned(linkedPaths):
    → WorktreeReconciler.reconcile(existing, discovered) → (merged, delta)
    → store.reconcileDiscoveredWorktrees(repoId, merged)
    → cache prune for delta.removedWorktrees (coordinator owns repoCache)
    → topologyEffectHandler.topologyDidChange(delta) → WorkspaceSurfaceCoordinator
  For .repoDiscovered with .notScanned:
    → register/reassociate repo only, skip reconciliation (boot replay)

handleEnrichment_*  — DERIVED cache writes (RepoEnrichmentCacheAtom through RepoCacheAtom)
  Events: .snapshotChanged, .branchChanged, .originChanged, .originUnavailable,
          .pullRequestCountsChanged, .checksUpdated
  Touches: repo enrichment cache only; recent targets are a separate local owner

syncScope_*         — ACTOR registration management
  Operations: register/unregister worktrees with FilesystemActor, ForgeActor
  Called from topology handlers as needed
```

Method naming convention makes responsibility explicit. If coordinator grows too large, method groups become natural extraction points. Does not run git/network commands or access filesystem directly.

### Filesystem Effect Admission And Projection

Filesystem source authority and workspace projection are separate
responsibilities. There are two independent lanes:

```text
FilesystemActor / GitWorkingDirectoryProjector
  -> globally published WorktreeScopedEvent
  -> PaneFilesystemProjectionAdmission (consumer-side)
     -> filesChanged / snapshotChanged -> project affected panes
     -> every other owned case         -> explicitly ignored here
  -> FilesystemProjectionIndex
  -> WorkspaceSurfaceCoordinator sequences any published pane facts

pane mount / removal / CWD / active-pane change
  -> local affected-key coordinator effect
  -> FilesystemProjectionIndex
  -> applied / stale / inapplicable
  -> changed activity/active-worktree update to FilesystemActor
  -> no EventBus fact solely for index maintenance
```

`PaneFilesystemProjectionAdmission` exhaustively switches over the owned
`WorktreeScopedEvent`, `FilesystemEvent`, and `GitWorkingDirectoryEvent`
families. Every case explicitly selects projection or `.ignored`; no catch-all
default silently schedules work. This is pane-projection admission after the
bounded worktree fact reaches EventBus, not Terminal-style pre-publication
source admission. The original filesystem/Git facts remain globally available
to other consumers; only relevant cases derive pane-scoped
`PaneFilesystemContextEvent` facts.

Effect rules:

- Full reconciliation is reserved for boot, explicit rebuild, and an accepted
  topology delta.
- Pane mount, pane removal, and pane CWD changes update only the keyed pane.
- Active-pane changes project only the active-worktree effect.
- Unrelated actions schedule no filesystem projection work.
- `FilesystemProjectionIndex.applyPaneUpdate` reports `.applied`, `.stale`, or
  `.inapplicable`, so the coordinator can distinguish a committed projection
  from obsolete or irrelevant work.
- Full source-sync requests carry an explicit
  `appliedContextsByWorktreeId` baseline with no implicit empty default.
  Coordinator mirrors advance immediately after each awaited source write, so
  a superseding pass compares desired state with registration, activity, and
  active-worktree effects that actually completed rather than an optimistic
  committed index snapshot.

`FilesystemActor` remains the authority for observed filesystem facts and root
registration. `FilesystemProjectionIndex` remains a rebuildable, off-main
projection of those facts and of current pane/worktree membership; it does not
become canonical workspace state. Terminal contraction and filesystem
projection deliberately use separate domain types rather than a generic
admission framework.

### Discovery — Repo Scanning

`RepoScanner` walks the filesystem from a root URL and classifies each `.git` entry:
- `.git` **directory** → clone root (real `git init`/`git clone`)
- `.git` **file** → linked worktree (reads `gitdir:` line to derive parent clone path by stripping `/.git/worktrees/<name>`)
- `.git` exists but unreadable → treated as clone root (conservative boundary — scanner stops descending)

After classification, linked worktrees are grouped under their parent clone into `RepoScanGroup` entries via `groupClassifiedPaths()`. The existing validation behavior is preserved: `git rev-parse --is-inside-work-tree` and submodule exclusion via `--show-superproject-working-tree`.

Used by `FilesystemActor` as the blocking filesystem walk behind watched-folder refresh. The grouped results enable the coordinator to create correct worktree families from the first topology event.

> **Files:** `Infrastructure/RepoScanner.swift`, `Infrastructure/WorktreeReconciler.swift`

### Event Namespaces

```
TopologyEvent (envelope: SystemEnvelope, all via bus)
  .repoDiscovered(repoPath:, parentPath:, linkedWorktrees: LinkedWorktreeInfo = .notScanned)
      — producer: AppDelegate (boot replay with .notScanned), FilesystemActor (watched folder diff with .scanned)
      — LinkedWorktreeInfo distinguishes "scanner found these linked worktrees" from "no scan performed"
      — .scanned([]) = authoritative empty (remove stale linked worktrees)
      — .scanned([url1, url2]) = authoritative list (reconcile to match)
      — .notScanned = boot replay / manual add (leave existing worktrees unchanged)
  .repoRemoved(repoPath:)                   — producer: FilesystemActor (watched folder diff, global dedup)
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
RepoCacheAtom.repoEnrichment      → org name, display name, groupKey (how to group)
RepoCacheAtom.worktreeEnrichment  → branch, git status (how to display)
RepoCacheAtom.pullRequestCounts   → PR badges
InboxNotificationAtom.unreadCount(forWorktreeId:) → notification bells
                                 (per LUNA-361; moved from RepoCacheAtom)
WorkspaceSidebarState          → filter and sidebar shell composition
                                 (collapsed / surface / runtime focus)

ZERO imperative fetches. ZERO mutations. Pure @Observable binding.
```

This is not a "join" problem — each store has one clear job. The bus ensures both are in sync. The sidebar does not do complex data merging; it reads structure from one, display data from the other.

Branch display: `WorktreeEnrichment.branch` from cache, falling back to `"detached HEAD"`. No branch field on the `Worktree` model itself.

---

## Lifecycle Flows

### App Boot (implemented)

Boot is driven by `WorkspaceBootSequence` (`App/Boot/WorkspaceBootSequence.swift`), which defines ordered steps executed synchronously on the main actor:

```
WorkspaceBootStep (in order):
  1. loadCanonicalStore      → load repos, worktrees, panes, tabs from workspace.state.json
  2. loadCacheStore           → warm-start from workspace.cache.json (sidebar renders immediately)
  3. loadUIStore              → expanded groups, filter, colors from workspace.ui.json
  4. establishRuntimeBus      → create/reset PaneRuntimeEventBus
  5. startFilesystemActor     → start FilesystemActor
  6. startGitProjector        → start GitWorkingDirectoryProjector
  7. startForgeActor          → start ForgeActor
  8. startCacheCoordinator    → start WorkspaceCacheCoordinator, subscribes to bus
  9. triggerInitialTopologySync → replayBootTopology — emit .repoDiscovered for each persisted repo
                                  Phase A: active-pane repos first (priority)
                                  Phase B: remaining repos
 10. readyForReactiveSidebar  → prune stale cache entries, sidebar enters reactive mode
```

After the boot sequence completes, `AppDelegate` calls `observeLaunchRestoreReadiness()` which creates a `WindowRestoreBridge`. The bridge observes `WindowLifecycleAtom.isReadyForLaunchRestore` and yields trusted terminal container bounds once the window layout has settled. `AppDelegate` then calls `workspaceSurfaceCoordinator.restoreAllViews(in: bounds)` to create views for all persisted panes. See [Deferred Launch Restore](#deferred-launch-restore) for the geometry gate that handles panes whose bounds are not yet available.

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
   b. Seed enrichment to .awaitingOrigin in RepoEnrichmentCacheAtom
7. WorkspaceSurfaceCoordinator reacts from topology facts and syncs registered worktree roots
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

### Deferred Launch Restore

> **Files:** `App/Boot/AppDelegate+LaunchRestore.swift`, `App/Lifecycle/WindowRestoreBridge.swift`, `App/Boot/AppDelegateLaunchRestoreObservationState.swift`, `App/Coordination/WorkspaceSurfaceCoordinator+ViewLifecycle.swift`, `Features/Terminal/Hosting/TerminalStatusPlaceholderView.swift`, `Features/Terminal/Restore/TerminalRestoreScheduler.swift`

zmx terminal panes require a trusted `initialFrame` before Ghostty surface creation. During app boot, `terminalContainerBounds` may be zero because the window has not settled layout yet. The deferred launch restore flow handles this geometry gate.

**Geometry gate.** When `WorkspaceSurfaceCoordinator.createView(for:...)` is called for a zmx pane and `initialFrame` is nil, it does not create a Ghostty surface. Instead it registers a `.preparing` placeholder via `registerTerminalPlaceholderIfNeeded(for:mode:)` and returns nil. The same gate applies to floating zmx panes (drawers, standalone terminals) in `createFloatingTerminalView`.

**Placeholder modes.** `TerminalStatusPlaceholderView` has two modes:
- `.preparing` — transient waiting-for-geometry state. `shouldRetryCreationWhenBoundsChange` returns true.
- `.failedToStart` — resting startup-failure state (surface creation failed). `shouldRetryCreationWhenBoundsChange` returns false. The user can retry or close.

**Retry trigger.** When AppKit delivers a layout pass, `PaneTabViewController.handleTerminalContainerBoundsChanged()` calls `WorkspaceSurfaceCoordinator.restoreViewsForActiveTabIfNeeded()`. This method checks the active tab for any `.preparing` placeholders, resolves geometry from the now-settled bounds, and calls `createViewForContent(pane:initialFrame:treatAsRestoredSessionStart:)` with real frames. The placeholder is replaced by the live terminal surface.

**Restore ordering.** `TerminalRestoreScheduler.order(_:resolver:)` sorts panes by `VisibilityTier` — `p0Visible` first, then `p1Hidden`. Within the visible tier, the active pane sorts first. This ensures the active tab paints before background tabs are hydrated. Background tabs are restored cooperatively with `Task.yield()` after every two panes.

**Background hidden-pane restore behavior.** Hidden zmx panes are restored at boot only when a live zmx session already exists (discovered via `discoverLiveSessionIds()`). This is fixed product behavior, not a user-configurable preference.

**The flow:**

```
AppDelegate: WorkspaceBootSequence.run() → stores loaded, actors started, topology replayed
  ↓
AppDelegate: observeLaunchRestoreReadiness()
  → creates WindowRestoreBridge (observes WindowLifecycleAtom)
  ↓
WindowLifecycleAtom: recordTerminalContainerBounds() + recordLaunchLayoutSettled()
  → isReadyForLaunchRestore becomes true
  ↓
WindowRestoreBridge: yields trusted bounds via AsyncStream
  ↓
AppDelegate: finishLaunchRestore(using: bounds)
  → workspaceSurfaceCoordinator.restoreAllViews(in: bounds)
  ↓
restoreAllViews:
  → TerminalRestoreScheduler orders panes (p0Visible first)
  → For each pane: resolveInitialFramesByTabId(in: bounds)
    → createViewForContent(pane, initialFrame, treatAsRestoredSessionStart: true)
      ↓ zmx pane with initialFrame available → surface created
      ↓ zmx pane with initialFrame == nil → .preparing placeholder registered
  ↓
Window layout settles (AppKit viewDidLayout)
  → PaneTabViewController.handleTerminalContainerBoundsChanged()
  ↓
restoreViewsForActiveTabIfNeeded()
  → checks: .preparing placeholders in active tab? bounds non-empty?
  → For each .preparing pane: createViewForContent(pane, initialFrame: REAL_FRAME)
    → surface created, placeholder replaced
```

**Timeout recovery.** `AppDelegateLaunchRestoreObservationState` installs a 10-second diagnostic timer. If `WindowRestoreBridge` has not yielded by then, the timer attempts restore with whatever bounds are currently recorded in `WindowLifecycleAtom` as a fallback.

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

Cache coordinator and cache atoms use value-equality checks: if the incoming
fact matches the existing cached content, the write is skipped and no atom
invalidation is fired. `RepoEnrichment` cache equality ignores timestamp-only
refreshes. `sourceRevision` on `WorkspaceCacheState` increments on actual cache
changes. On boot, if cache is missing/corrupt/stale, coordinator sets
`needsFullRebuild` and treats all events from initial scan as new.

---

## Event System Design: What It Is (and Isn't)

The event bus is a **notification mechanism** — runtime actors produce facts, the coordinator consumes them and calls store methods. This is NOT CQRS. There is no command bus, no command/event segregation, no command handlers.

### How It Works

**Events are facts about the world.** "A repo exists at this path." "Branch changed to X." "PR count is 3." Events carry data, not instructions.

**Canonical state is mutated by the owning atoms or `WorkspaceMutationCoordinator`.** The bus does not route mutations, and `WorkspaceStore` is not a convenience mutation facade.

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
// 7. WorkspaceCacheCoordinator writes enrichment to RepoCacheAtom
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
         ├── seed enrichment in RepoCacheAtom
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

### Topology Accumulator Pattern

Topology facts flow through a layered pipeline. Each layer's output is the next layer's input. No layer reaches back.

```
LAYER              COMPONENT                        OWNS
─────              ─────────                        ────
Fact Producer      FilesystemActor                  Observing filesystem, emitting raw facts
Publication        EventBus                         Fan-out to all subscribers (dumb pipe)
Accumulator        WorkspaceCacheCoordinator         Interpreting facts, sequencing effects
Reconciler         WorktreeReconciler (pure func)   Identity preservation, diff computation
State              WorkspaceStore                   Canonical truth, mutation methods
Effects            TopologyEffectHandler             Ordered follow-on work (WorkspaceSurfaceCoordinator)
Reader             Sidebar                          Rendering truth via @Observable
```

**Why not pure pub/sub for topology:** Multiple bus subscribers independently inferring what changed from raw events is fragile — ordering implicit, diffs rediscovered, cleanup ad hoc. The accumulator pattern ensures one interpreter, one diff (via `WorktreeReconciler`), one ordered effect chain (via `TopologyEffectHandler`).

**Why the bus still exists for topology:** Independent consumers (ForgeActor, NotificationReducer) subscribe to raw topology facts on the bus. They react independently, don't depend on store state, and don't need ordering guarantees. The bus serves notification; the handler serves sequencing.

**The handler pattern:**
- `WorkspaceCacheCoordinator` produces a `WorktreeTopologyDelta` after reconciliation
- It handles cache cleanup itself (it owns `repoCache`)
- It calls `topologyEffectHandler.topologyDidChange(delta)` for ordering-sensitive effects and a full filesystem reconciliation
- `WorkspaceSurfaceCoordinator` conforms to `TopologyEffectHandler`: it orphans panes for removed worktrees and reconciles filesystem roots after accepted topology changes
- `WorkspaceSurfaceCoordinator` does NOT subscribe to topology events on the bus — it receives topology changes only via the handler

Ordinary pane mount/removal/CWD and active-pane changes do not re-enter this
topology accumulator. They use the separate affected-key entry points described
in [Filesystem Effect Admission And Projection](#filesystem-effect-admission-and-projection).

This replaces the previous pattern where `WorkspaceSurfaceCoordinator` subscribed to topology events on the bus and scheduled a deferred filesystem sync. That worked by accident (deferred `Task` ran after the coordinator's synchronous store mutation) but was fragile — any change to the timing would break ordering.

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
        let repoCache = RepoCacheAtom()
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
        let repoCache = RepoCacheAtom()
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
- **Assert on both stores.** A topology event should update both `WorkspaceStore` (canonical) and `RepoCacheAtom` (enrichment).
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
