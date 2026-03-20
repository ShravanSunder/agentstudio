# Sidebar Add-Folder Cleanup: Watched-Folder Command, Topology Diffing, and Stable Sidebar Projection

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Replace the current half-command / half-event Add Folder flow with one clean model:
- Add Folder persists watched scope and calls one direct watched-folder refresh command
- `FilesystemActor` performs the authoritative watched-folder scan exactly once per refresh
- `FilesystemActor` owns watched-folder topology diffing and emits both `.repoDiscovered` and `.repoRemoved`
- `WorkspaceCacheCoordinator` remains the single topology consumer
- the sidebar renders unresolved repos as an explicit loading section instead of fake `pending:` groups

**Architecture:** Separate command plane from fact plane.

```text
COMMAND PLANE
User -> AppDelegate -> refreshWatchedFolders(paths) -> FilesystemActor
                                                |
                                                +-> returns scan summary

FACT PLANE
FilesystemActor -> EventBus(.repoDiscovered / .repoRemoved)
EventBus -> WorkspaceCacheCoordinator
WorkspaceCacheCoordinator -> WorkspaceStore + WorkspaceRepoCache
WorkspaceStore + WorkspaceRepoCache -> Sidebar projection
```

**Tech Stack:** Swift 6.2, AppKit + SwiftUI, `@Observable`, `AsyncStream` EventBus, `Testing` framework

---

## Context: Why the current plan is not enough

The original cleanup plan removed duplicate event posting but still preserved the underlying architectural blur:

```text
Add Folder
  -> persist watched path
  -> call updateWatchedFolders
  -> do a second scan in AppDelegate
  -> manually decide empty-folder UX
  -> sidebar infers loading via fake pending groups
```

That leaves three problems:

1. **Command and fact responsibilities are mixed**

```text
AppDelegate both:
  - initiates work
  - synthesizes topology facts
```

But `FilesystemActor` is already the owner of watched-folder scanning.

2. **Removal is not first-class in the watched-folder scan path**

The coordinator already knows how to consume `.repoRemoved`, but the watched-folder rescan path does not currently own a stable baseline and diff emit path for "repo is gone now".

3. **Sidebar loading state is encoded indirectly**

```text
unresolved repo -> fake groupKey "pending:<uuid>"
```

That forces grouping logic to pretend loading repos already belong in the final grouping model, which causes rearrangement when enrichment resolves.

---

## Cross-Referenced Current Code

| File | Current role | Why it matters |
|------|--------------|----------------|
| `Sources/AgentStudio/App/AppDelegate.swift` | `handleAddFolderRequested` persists watched path, calls `syncScope(.updateWatchedFolders)`, then runs a second scan | Current architectural blur |
| `Sources/AgentStudio/App/FilesystemGitPipeline.swift` | `applyScopeChange(_:)` bridges coordinator scope changes to `FilesystemActor` / `ForgeActor` | Current command entry point |
| `Sources/AgentStudio/Core/PaneRuntime/Sources/FilesystemActor.swift` | Owns watched-folder scan and emits `.repoDiscovered` | Correct authority for topology facts |
| `Sources/AgentStudio/App/WorkspaceCacheCoordinator.swift` | Consumes `.repoDiscovered` and `.repoRemoved` | Single topology intake stays intact |
| `Sources/AgentStudio/Features/Sidebar/RepoSidebarContentView.swift` | Filters repos, builds metadata, groups sidebar rows | Current fake pending-group behavior lives here |
| `Sources/AgentStudio/Core/Models/RepoEnrichment.swift` | `.unresolved` vs `.resolved` identity state | Sidebar loading projection should key off this |

Relevant existing behaviors:

```text
AppDelegate.handleAddFolderRequested()
  currently mixes command initiation + duplicate scan

FilesystemActor.updateWatchedFolders()
  already rescans watched folders and posts .repoDiscovered

WorkspaceCacheCoordinator.handleTopology(.repoRemoved)
  already knows how to mark unavailable and prune cache

RepoSidebarContentView.buildRepoMetadata()
  currently creates "pending:<uuid>" group keys for unresolved repos
```

---

## Swift 6.2 Constraints

This plan must follow the codebase's Swift 6.2 concurrency rules.

### Rule 1: `Task {}` inside `@MainActor` is not an off-main escape hatch

```text
@MainActor method
  -> Task { blocking scan }

still runs on MainActor
```

So the original "lightweight second scan in `Task {}`" approach is not valid in this repo.

### Rule 2: blocking scan work must stay behind actor-owned or `@concurrent nonisolated` boundaries

The watched-folder scan already lives in `FilesystemActor.scanFolder(...)`, which is the right place for the blocking filesystem walk.

### Rule 3: the command caller must not infer results from `store.repos`

`handleAddFolderRequested` and `WorkspaceCacheCoordinator` consumption both run on `@MainActor`. After the refresh command returns, bus events may be posted but not yet consumed by the coordinator. The Add Folder UX must use the direct command result, not `store.repos`.

---

## Target Mental Model

### 1. Command plane and fact plane are separate

```text
COMMAND:
  "Please refresh watched folders now and tell me what you found."

FACTS:
  "Repo X was discovered."
  "Repo Y disappeared."
```

That gives us:

```text
AppDelegate
  |
  | command
  v
FilesystemGitPipeline / FilesystemActor
  |
  +-> returns summary to caller
  |
  +-> emits facts on EventBus
```

The caller gets a direct answer for immediate UX.
The rest of the app reacts to facts through the bus.

### 2. `FilesystemActor` owns watched-folder topology diffing

The actor should keep a baseline of discovered repo paths per watched folder:

```text
watchedFolderRepoPathsByRoot:

"/projects" -> {
  "/projects/app",
  "/projects/tool"
}
```

On each refresh:

```text
old set = previously known repo paths under watched root
new set = freshly scanned repo paths under watched root

added   = new - old
removed = old - new
```

Then emit:

```text
for added:
  .repoDiscovered(repoPath:, parentPath:)

for removed:
  .repoRemoved(repoPath:)
```

Then replace the baseline with `new`.

### 3. Sidebar projection is explicit

The sidebar should stop using fake pending groups.

Instead:

```text
SidebarProjection
  resolvedGroups: [SidebarRepoGroup]
  loadingRepos: [SidebarRepo]
  showsNoResults: Bool
```

Rules:

```text
.resolved    -> eligible for grouping
.unresolved  -> loading section
nil cache    -> loading section
```

Grouping code should never see unresolved repos.

---

## Target Flows

### Flow A: Add Folder

```text
User
  |
  v
AppDelegate.handleAddFolderRequested
  |
  +-> store.addWatchedPath("/projects")
  |
  +-> refreshWatchedFolders(paths: [all watched paths])
        |
        v
      FilesystemActor.updateWatchedFolders
        |
        +-> update watched-folder registrations
        +-> rescan watched folders
        +-> compute diff against prior baseline
        +-> emit .repoDiscovered / .repoRemoved
        +-> return summary for "/projects"
  |
  +-> if summary for "/projects" has zero repos:
        show empty-folder alert
  |
  +-> return
```

Important:

```text
AppDelegate does NOT:
  - run RepoScanner directly
  - post .repoDiscovered itself
  - manually sync filesystem roots afterward
```

### Flow B: Repo discovered during watched-folder refresh

```text
FilesystemActor
  |
  +-> post .repoDiscovered("/projects/app", parentPath: "/projects")
  |
  v
EventBus
  |
  v
WorkspaceCacheCoordinator.handleTopology(.repoDiscovered)
  |
  +-> add repo if new
  +-> or reassociate if previously unavailable
  +-> seed RepoEnrichment = .unresolved
  |
  v
Sidebar projection
  |
  +-> repo appears in loading section
  +-> later enrichment resolves
  +-> repo appears in final resolved group
```

### Flow C: Repo removed during watched-folder refresh

```text
prior baseline under "/projects":
  { "/projects/app", "/projects/tool" }

new scan under "/projects":
  { "/projects/tool" }

diff:
  added   = {}
  removed = { "/projects/app" }

FilesystemActor
  |
  +-> post .repoRemoved("/projects/app")
  |
  v
WorkspaceCacheCoordinator.handleTopology(.repoRemoved)
  |
  +-> mark repo unavailable
  +-> orphan panes for repo if needed
  +-> remove repo cache entries
  +-> unregister forge scope
```

### Flow D: Repo comes back later

```text
new scan under "/projects":
  { "/projects/app", "/projects/tool" }

diff:
  added   = { "/projects/app" }
  removed = {}

.repoDiscovered("/projects/app")
  |
  v
WorkspaceCacheCoordinator
  |
  +-> finds existing unavailable repo at same path
  +-> reassociateRepo(...)
  +-> preserve canonical repo identity
```

This is the desired identity behavior:

```text
repo disappears  -> unavailable
repo returns     -> same UUID identity restored
```

---

## API Design

The watched-folder refresh should become a dedicated command API, not a generic `syncScope` result overload.

### Why not overload `syncScope`?

```text
syncScope(change) async

works well for:
  - registerForgeRepo
  - unregisterForgeRepo
  - refreshForgeRepo

but watched-folder refresh now needs:
  - typed result
  - per-root discovered repo paths
  - immediate caller UX
```

If we generalize `syncScope` to "sometimes returns results", the API becomes muddy and every unrelated scope change pays the complexity cost.

### Target API shape

Add a dedicated command on the app-side pipeline boundary.

Command owner:

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

This is intentional:

```text
- FilesystemGitPipeline owns command dispatch for filesystem / git / forge boundary work
- WorkspaceCacheCoordinator remains an event consumer and store consolidator
- AppDelegate should not depend on the concrete FilesystemGitPipeline type
```

Do NOT introduce a generic "command executor" abstraction.

```text
BAD:
  GenericCommandExecutor.execute(.refreshWatchedFolders(...))

GOOD:
  WatchedFolderCommandHandling.refreshWatchedFolders(...)
```

Reason:

```text
- actor or pipeline isolation boundary != dependency boundary
- use a focused capability protocol for the caller that needs this behavior
- keep concrete pipeline ownership at the composition root
```

Recommended protocol:

```swift
protocol WatchedFolderCommandHandling: AnyObject {
    func refreshWatchedFolders(_ paths: [URL]) async -> WatchedFolderRefreshSummary
}
```

Injection rule:

```text
- composition root may know the concrete FilesystemGitPipeline
- AppDelegate stores only `any WatchedFolderCommandHandling`
- do not pass the concrete pipeline around feature code when a focused capability will do
```

Recommended return type:

```swift
struct WatchedFolderRefreshSummary: Sendable, Equatable {
    let repoPathsByWatchedFolder: [URL: [URL]]

    func repoPaths(in watchedFolder: URL) -> [URL]
}
```

Minimum useful semantics:

```text
- includes current discovered repo paths per watched folder
- derived from the actor's authoritative scan
- caller uses it for empty-folder UX
- caller does not infer from store state
```

Implementation note:

```text
Keep `syncScope(...)` for fire-and-forget scope changes.
Add a new dedicated watched-folder refresh command for result-bearing work.
```

Architecture rule for this branch and follow-up work:

```text
Consumers should depend on focused capability protocols, not concrete actor/pipeline types.

Apply this rule in this branch where touched:
  - AppDelegate -> WatchedFolderCommandHandling

Do not widen this branch into protocolizing every actor in the app.
Migrate other consumers incrementally when their areas are touched.
```

---

## FilesystemActor Design Changes

### New state

Add actor-owned baseline state for watched-folder repo topology:

```text
watchedFolderIds: [URL: UUID]
watchedFolderRepoPathsByRoot: [URL: Set<URL>]
```

Normalization rules:

```text
- watched roots stored as standardized file URLs
- repo paths stored as standardized file URLs
```

### Refresh algorithm

Pseudo-flow:

```text
refreshWatchedFolders(paths):
  1. reconcile watched-folder registrations
  2. for each watched root:
       scan current repo paths
       compare against prior known set
       emit .repoDiscovered for additions
       emit .repoRemoved for removals
       store new known set
  3. update fallback rescan scheduling
  4. return summary of current repo paths per watched root
```

Key property:

```text
one authoritative scan pass
  -> one returned summary
  -> one emitted fact stream
```

No second scan in `AppDelegate`.

### FSEvents-triggered rescans

The same diffing path should be reused for:

```text
- Add Folder immediate refresh
- watched-folder FSEvent-triggered refresh
- periodic fallback refresh
```

That guarantees consistent discovered/removed behavior regardless of trigger source.

---

## Coordinator and Store Semantics

`WorkspaceCacheCoordinator` remains the single topology consumer.

### `.repoDiscovered`

Keep current semantics:

```text
if repo already exists:
  - seed unresolved enrichment if missing
  - reassociate if unavailable

if repo is new:
  - add canonical repo
  - seed unresolved enrichment
```

### `.repoRemoved`

Keep current semantics, but the event should now come from watched-folder diffing too:

```text
repoRemoved(repoPath)
  -> mark repo unavailable
  -> orphan panes if needed
  -> remove repo cache
  -> unregister forge scope
```

Important semantic rule:

```text
watched-folder removal means:
  repo becomes unavailable

watched-folder removal does NOT mean:
  hard-delete canonical repo identity
```

Target lifecycle:

```text
repo disappears
  -> unavailable(UUID stays stable)

repo returns later
  -> reassociate existing canonical repo identity
```

One implementation improvement to consider while executing:

```text
Current .repoRemoved path uses Task { [weak self] in await syncScope(...) }.
Because coordinator is @MainActor, verify whether this should remain a fire-and-forget
unregister or become a direct awaited command within the topology handling contract.
```

This does not change the architecture, but it is worth auditing during implementation.

---

## Sidebar Projection Design

### Current behavior to remove

```text
unresolved repo
  -> buildRepoMetadata()
  -> assign groupKey = "pending:<uuid>"
  -> group renderer treats it as a real group
```

This is the wrong abstraction boundary.

### Target projection

Introduce a pure projection helper near the sidebar content view:

```swift
struct SidebarProjection {
    let resolvedGroups: [SidebarRepoGroup]
    let loadingRepos: [SidebarRepo]
    let showsNoResults: Bool
}
```

Recommended pure helper:

```swift
static func projectSidebar(
    repos: [SidebarRepo],
    repoEnrichmentByRepoId: [UUID: RepoEnrichment],
    query: String
) -> SidebarProjection
```

Projection rules:

```text
1. Partition repos by enrichment state
   resolved = .resolved
   loading  = .unresolved or nil

2. Filter resolved repos with existing SidebarFilter behavior
   repo name match => keep repo
   matching worktree names => filtered worktree subset

3. Filter loading repos by repo name only
   loading rows do not show worktree metadata, so repo-level filter is enough

4. Build groups from resolved repos only

5. showsNoResults = resolvedGroups.isEmpty && loadingRepos.isEmpty when query is non-empty
```

### Target rendering

```text
+----------------------------------+
| SIDEBAR                          |
|                                  |
|  [resolved groups]               |
|                                  |
|  Scanning...                     |
|    my-app                        |
|    other-project                 |
+----------------------------------+
```

Rendering properties:

```text
- loading section appears after resolved groups
- loading rows are disabled and non-interactive
- loading rows display only repo folder name
- section disappears when loadingRepos is empty
- no fake pending groups in normal path
```

---

## Testing Strategy

### Task 1: command/result path

Add tests for the new watched-folder refresh command:

```text
- refreshWatchedFolders returns discovered repo paths per watched root
- Add Folder empty-folder UX can be driven from returned summary
- no second scan needed in AppDelegate
```

### Task 2: watched-folder diffing

Extend `FilesystemActorWatchedFolderTests` to verify:

```text
- first refresh emits .repoDiscovered for new repos
- second refresh with same repo set emits nothing
- repo removed from watched folder emits .repoRemoved
- repo re-added emits .repoDiscovered again
- returned summary matches actor baseline
```

### Task 3: coordinator topology handling

Verify with existing coordinator tests:

```text
- .repoRemoved from watched-folder diff marks repo unavailable
- cache pruned on removal
- reassociation on later .repoDiscovered preserves identity
```

### Task 4: sidebar projection

Prefer pure projection tests over only raw partition tests:

```text
- unresolved repo appears in loading list, not groups
- resolved repo appears in groups, not loading list
- nil enrichment treated as loading
- query that matches only loading repo keeps loading section visible
- query with no matches in either section shows no-results state
```

### Task 5: manual / visual verification

Verify the full sequence:

```text
1. Add watched folder with multiple repos
2. Observe loading rows first
3. Observe resolved groups appear without rearrangement
4. Remove a repo from disk
5. Trigger watched-folder refresh / wait for rescan
6. Observe repo disappears from sidebar and store is pruned
7. Recreate repo
8. Observe repo returns with preserved identity semantics
```

---

## Implementation Tasks

### Task 1: Introduce dedicated watched-folder refresh command

Files:
- `Sources/AgentStudio/App/FilesystemGitPipeline.swift`
- `Sources/AgentStudio/App/WorkspaceCacheCoordinator.swift`
- `Sources/AgentStudio/App/AppDelegate.swift`

Changes:

```text
- add `WatchedFolderCommandHandling`
- make `FilesystemGitPipeline` conform
- inject `any WatchedFolderCommandHandling` into AppDelegate instead of concrete pipeline access for this feature path
- add a dedicated refresh API that returns WatchedFolderRefreshSummary
- keep `syncScope(...)` for fire-and-forget scope changes
- change Add Folder to use returned summary for empty-folder alert
- remove second RepoScanner pass from AppDelegate
- remove duplicate event posting from AppDelegate
- remove manual filesystem-root sync from Add Folder path unless implementation proves it is still required
```

### Task 2: Move watched-folder topology diffing into FilesystemActor

Files:
- `Sources/AgentStudio/Core/PaneRuntime/Sources/FilesystemActor.swift`
- `Tests/AgentStudioTests/Core/PaneRuntime/Sources/FilesystemActorWatchedFolderTests.swift`

Changes:

```text
- add actor baseline state for discovered repo paths per watched root
- implement scan diffing and `.repoRemoved` emission
- reuse same diffing path for immediate refresh, FSEvent-triggered refresh, and periodic rescan
- return authoritative refresh summary from actor
```

### Task 3: Audit topology consumer behavior

Files:
- `Sources/AgentStudio/App/WorkspaceCacheCoordinator.swift`
- `Tests/AgentStudioTests/App/WorkspaceCacheCoordinatorTests.swift`
- `Tests/AgentStudioTests/App/WorkspaceCacheCoordinatorRepoMoveTests.swift`

Changes:

```text
- verify .repoRemoved path still matches desired unavailable / reassociation semantics
- tighten tests around removal and rediscovery from watched-folder diffs
- audit forge unregister side effect behavior during removal
```

### Task 4: Replace pending-group loading behavior with explicit sidebar projection

Files:
- `Sources/AgentStudio/Features/Sidebar/RepoSidebarContentView.swift`
- `Tests/AgentStudioTests/Features/Sidebar/RepoSidebarContentViewTests.swift`
- `Tests/AgentStudioTests/Features/Sidebar/SidebarEnrichmentFilterTests.swift` or equivalent projection test file

Changes:

```text
- add pure projection helper returning resolvedGroups + loadingRepos + showsNoResults
- remove unresolved repos from normal grouping input
- render disabled loading section explicitly
- preserve existing resolved grouping behavior
- ensure query state handles loading rows correctly
```

### Task 5: Verify end-to-end behavior

Run:

```text
mise run build
mise run test
mise run lint
```

Manual / visual:

```text
- Add Folder with repos
- Add Folder with empty folder
- repo disappears under watched root
- repo returns under watched root
- sidebar loading and resolved transitions
```

### Task 6: Update architecture docs

Files:
- `docs/architecture/workspace_data_architecture.md`
- `docs/architecture/pane_runtime_architecture.md`
- any other authoritative doc touched by the implementation

Changes:

```text
- update watched-folder topology ownership to reflect FilesystemActor diffing
- update Add Folder command flow to reflect dedicated watched-folder command
- update topology fact ownership if docs still imply AppDelegate owns live watched-folder discovery/removal
- add the focused capability-protocol rule where relevant
```

---

## Success Criteria

The work is done when all of the following are true:

```text
1. Add Folder performs one authoritative watched-folder scan path
2. AppDelegate does not post watched-folder topology facts directly
3. Empty-folder alert uses the direct command result, not store inference
4. FilesystemActor emits both discovered and removed topology facts from watched-folder diffs
5. WorkspaceCacheCoordinator remains the single topology consumer
6. Sidebar loading state is explicit and does not rely on fake pending groups
7. Repo removal and rediscovery through watched-folder scans preserve canonical identity semantics
8. Concrete ownership remains in the composition root; AppDelegate depends on a focused watched-folder capability, not the concrete pipeline
9. Full build, tests, and lint pass
```

---

## Dependency Order

```text
Task 1: watched-folder command API
  |
  v
Task 2: FilesystemActor diffing + summary
  |
  +------------------------+
  |                        |
  v                        v
        Task 3: coordinator audit  Task 4: sidebar projection
  |                        |
  +-----------+------------+
              |
              v
        Task 5: verification
              |
              v
        Task 6: docs update
```
