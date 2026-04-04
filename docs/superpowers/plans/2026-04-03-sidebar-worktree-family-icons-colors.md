# Sidebar Worktree Family Icons & Colors

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Linked worktrees render as one checkout family in the sidebar — star icon for main checkout, worktree icon for secondaries, shared color per family.

**Architecture:** Fix canonical topology at its source. Scanner classifies `.git` file vs directory. FilesystemActor emits grouped `.repoDiscovered`. Coordinator sequences reconciliation via a pure `WorktreeReconciler` function, updates the store via the existing `reconcileDiscoveredWorktrees`, handles cache cleanup itself, and passes a typed `TopologyDelta` to an injected `TopologyEffectHandler`. PaneCoordinator handles pane orphaning and filesystem root sync via the handler — NOT via a bus topology subscription. Cache pruning stays in the coordinator (which already owns `repoCache`). Independent consumers (ForgeActor, NotificationReducer) still consume raw facts from the bus. No dependency on the atoms refactor — works with the current `WorkspaceStore` shape.

**Tech Stack:** Swift 6.2, `EventBus<RuntimeEnvelope>`, Swift Testing

---

## 1. The Mental Model

Five layers. Each layer's output is the next layer's input. No layer reaches back.

```
LAYER                    OWNS                           DOES NOT OWN
───────────────────────  ─────────────────────────────  ──────────────────────
Fact Producers           Observing the world            Interpreting observations
(FilesystemActor)        Emitting raw facts             Deciding what facts mean

Publication              Fan-out delivery               Ordering, filtering,
(EventBus)               To all subscribers             interpretation

Accumulator              Interpreting facts             Domain diff logic
(Coordinator)            Sequencing effects             Identity preservation
                         Calling reconciler + handler   Filesystem/git work

Reconciler + Store       Canonical state (store)        Sequencing effects
(WorktreeReconciler,     Identity preservation          Event bus interaction
 WorkspaceStore)         Diff computation (reconciler)  External system calls

Ordered Effects          Orphan panes, sync roots,      Interpreting raw facts
(TopologyEffectHandler)  prune cache                    Mutating canonical state
                                                        Computing diffs
```

**The rule:** facts in → accumulator interprets → reconciler computes merged state + delta → store mutated → cache pruned → ordered effects → UI reads.

```
fact → accumulator → reconciler(old, new) → (merged, delta) → store.reconcile(merged) → coordinator prunes cache → effects(delta) → UI reads
```

---

## 2. The Architecture: Bus for Notification, Handler for Sequencing

Not all event consumers are equal. Some are **independent** (react to facts, don't care about store state). Others are **dependent** (MUST run after store mutation, need to know WHAT changed). Using one mechanism for both is where ordering fragility comes from.

```
┌─────────────────────────────────────────────────────────────────────────┐
│                                                                         │
│  CHANNEL 1: EventBus (fan-out, independent consumers)                  │
│                                                                         │
│  FilesystemActor ──post()──► EventBus ──fan-out──► ForgeActor          │
│                                                  ► NotificationReducer  │
│                                                  ► Coordinator (intake) │
│                                                                         │
│  Bus is DUMB. No ordering. No priority. No sequencing.                 │
│                                                                         │
│  CHANNEL 2: TopologyEffectHandler (sequential, dependent consumers)    │
│                                                                         │
│  Coordinator ──topologyDidChange(delta)──► PaneCoordinator             │
│  (direct call, after store mutation, deterministic)                     │
│                                                                         │
│  Handler is DETERMINISTIC. Always runs after mutation. Always ordered.  │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

### Why This Split

| Consumer | Independent? | Reads store? | Current mechanism | Proposed mechanism |
|----------|-------------|-------------|-------------------|-------------------|
| ForgeActor | Yes | No | Bus subscription | Bus subscription (unchanged) |
| NotificationReducer | Yes | No | Bus subscription | Bus subscription (unchanged) |
| WorkspaceCacheCoordinator | N/A (IS the accumulator) | Yes | Bus subscription | Bus subscription (unchanged) |
| PaneCoordinator (topology sync) | **No** — must run after store mutation | **Yes** — reads `store.repos` | Bus subscription (accidental ordering) | **TopologyEffectHandler** (deterministic) |

### Why Not Other Ordering Approaches

| Approach | Problem |
|----------|---------|
| Subscriber priority on bus | Makes bus smart. Violates "dumb pipe." Priority inversion risk. |
| Cascading events (`.topologyReconciled`) | Every primary→secondary dep needs a new event type. Long chains hard to trace. |
| CausationId for runtime ordering | Forces consumers to invent protocol on top of bus. Hard to test. |
| Store returns delta | Violates atoms model — atoms are pure state, no interpretation/diff results. |

---

## 3. WorktreeReconciler: Pure Function for Diff + Identity Preservation

The reconciliation logic (match by path, preserve existing UUIDs, compute delta) is extracted into a **pure function** — not on the atom, not on the coordinator. This fits the atoms refactor: atoms are dumb state containers, coordinators sequence, reconcilers compute.

```
SEPARATION OF CONCERNS:

  Store        = "canonical state, mutated via existing reconcileDiscoveredWorktrees" (current API)
  Reconciler   = "match old vs new, preserve identities, compute delta" (pure function, extracted)
  Coordinator  = "call reconciler, update store, prune cache, call effect handler" (sequencing)
  EffectHandler = "orphan panes, sync filesystem roots" (ordered effects, PaneCoordinator)
```

**Note:** This plan works with the CURRENT `WorkspaceStore` shape. `reconcileDiscoveredWorktrees` remains the store mutation method. The `WorktreeReconciler` is extracted alongside it as a pure function for delta computation. When the atoms refactor lands later, the reconciler already fits — no rework needed.

### The Types

```swift
struct WorktreeTopologyDelta: Sendable, Equatable {
    let repoId: UUID
    let addedWorktreeIds: [UUID]
    let removedWorktreeIds: [UUID]
    let preservedWorktreeIds: [UUID]
    let didChange: Bool
    let traceId: UUID?  // links to originating event for observability
}

enum WorktreeReconciler {
    /// Pure function. No side effects. No store access.
    /// Matches discovered worktrees against existing by path (primary),
    /// main worktree flag, and name (fallback). Preserves existing UUIDs.
    /// Returns the merged list AND a typed delta.
    static func reconcile(
        repoId: UUID,
        existing: [Worktree],
        discovered: [Worktree],
        traceId: UUID? = nil
    ) -> (merged: [Worktree], delta: WorktreeTopologyDelta)
}
```

### Why a Pure Function

- **Testable without stores, bus, or actors.** Input: two arrays. Output: merged array + delta. Dozens of edge cases testable in milliseconds.
- **Atoms stay dumb.** The atom gets `setWorktrees(repoId, merged)` — a simple setter. No return values, no interpretation.
- **Coordinator stays sequencing-only.** It doesn't contain diff logic — it calls the reconciler and passes the result through.
- **The reconciliation logic is the same** as what `WorkspaceStore.reconcileDiscoveredWorktrees` does today (`WorkspaceStore.swift:1388-1433`). It just moves from an inline store method to an extracted pure function.

---

## 4. How FSEvents Become Topology Facts

The FilesystemActor uses a **rescan-based** strategy. It never parses individual FSEvent paths for topology meaning.

```
macOS FSEvents delivers raw paths
    ↓
FilesystemActor ingress task routes by worktreeId:
  watched folder batch? → handleWatchedFolderFSEvent()   ← TOPOLOGY PATH
  registered worktree?  → enqueueRawPaths()               ← FILE CHANGE PATH (unrelated)
    ↓
handleWatchedFolderFSEvent:
  Any path contains "/.git/" or ends with "/.git"?
    NO  → ignore (not topology-relevant)
    YES → FULL RESCAN of that watched folder
    ↓
refreshWatchedFolder:
  1. Run enhanced scanner on entire folder (@concurrent, blocking I/O)
  2. Diff current grouped scan results vs previous stored state
  3. Emit topology events for differences
  4. Store current state for next diff
```

**Key design properties:**
- Rescan, don't parse. One mechanism handles `git worktree add`, `rm -rf`, `git clone`, `mv`.
- Heuristic gate is cheap (string check, no I/O).
- Full rescan is correct by construction — no state machine.
- Periodic fallback (300s) catches anything FSEvents missed.

---

## 5. What's Broken and Why

### Root Cause

`RepoScanner.scanForGitRepos()` (`RepoScanner.swift:32`) uses `FileManager.fileExists(atPath:)` which returns `true` for both `.git` directories (clones) and `.git` files (linked worktrees). Every path becomes a separate Repo with `worktrees.count == 1`.

### `.git` File Classification (Pure Filesystem, No Git Commands)

A linked worktree's `.git` is a plain text file:
```
$ cat ~/projects/my-repo.feature/.git
gitdir: /Users/dev/projects/my-repo/.git/worktrees/feature
```

The scanner can:
1. `stat` `.git` → file or directory? (`FileManager`, `isDirectory`)
2. If file → read contents → parse `gitdir:` line
3. Strip `/.git/worktrees/<name>` → parent clone path

This is the same category as `FileManager.fileExists` — pure filesystem within FilesystemActor's boundary. The scanner preserves its existing git validation (`rev-parse --is-inside-work-tree`, submodule exclusion) after classification.

---

## 6. Topology Triggers and Downstream Effects

Every topology-relevant filesystem change triggers: FSEvents → heuristic gate → rescan → grouped diff → emit.

```
TRIGGER                        RESCAN RESULT                            EMIT
────────────────────────────────────────────────────────────────────────────────
User adds watched folder       Full scan, all groups                    .repoDiscovered per clone
git worktree add               Clone's linked list grows               .repoDiscovered (updated linked list)
git worktree remove            Clone's linked list shrinks             .repoDiscovered (updated linked list)
git clone (new repo)           New clone group appears                 .repoDiscovered (new clone)
rm -rf repo                    Clone group disappears                  .repoRemoved
Periodic rescan (300s)         Full scan                               Whatever changed
App boot replay                Replays persisted repos                 Validates against disk
```

### Full Flow: `git worktree add` While Running

```
t0  User: git worktree add ../my-repo.experiment feat
    → creates ~/projects/my-repo.experiment/.git (file)

t1  FSEvents fires → heuristic gate: contains "/.git" → rescan

t2  Enhanced scanner returns:
      ScannedRepoGroup(/my-repo, linked:[.feature, .hotfix, .experiment])
    Diff: /my-repo linked list changed (.experiment added)
    Emit: .repoDiscovered(/my-repo, linked:[.feature, .hotfix, .experiment])

t3  Coordinator receives .repoDiscovered
    → repo /my-repo exists (dedup by stableKey)
    → builds discovered worktree list: [main, .feature, .hotfix, .experiment]
    → WorktreeReconciler.reconcile(existing, discovered)
      → returns (merged, delta: {added: [.experiment.id], removed: []})
    → atom.setWorktrees(repoId, merged)
    → topologyEffectHandler.topologyDidChange(delta)

t4  PaneCoordinator.topologyDidChange(delta)
    → no removed worktrees → no orphaning needed
    → syncFilesystemRootsAndActivity()
      → reads store.repos (ALREADY mutated)
      → registers /my-repo.experiment with FilesystemActor
      → FilesystemActor emits .worktreeRegistered

t5  Projector receives .worktreeRegistered
    → git status → .snapshotChanged, .branchChanged
    → .originChanged

t6  ForgeActor receives .branchChanged → refreshes PR counts

t7  Sidebar updates via @Observable
    → new worktree row, worktree icon, same color as parent
```

### Full Flow: `git worktree remove` While Running

```
t0  User: git worktree remove ../my-repo.hotfix

t1  FSEvents → rescan

t2  Scanner: ScannedRepoGroup(/my-repo, linked:[.feature])  ← .hotfix gone
    Diff: linked list changed
    Emit: .repoDiscovered(/my-repo, linked:[.feature])

t3  Coordinator
    → WorktreeReconciler.reconcile(existing, discovered)
      → returns (merged, delta: {added: [], removed: [hotfix.id]})
    → atom.setWorktrees(repoId, merged)
    → topologyEffectHandler.topologyDidChange(delta)

t4  PaneCoordinator.topologyDidChange(delta)
    → orphan panes for delta.removedWorktreeIds
    → repoCache.removeWorktree(hotfix.id)  — prunes enrichment, PR counts
    → syncFilesystemRootsAndActivity()
      → reads store.repos → /my-repo.hotfix not in desired set
      → unregisters from FilesystemActor → .worktreeUnregistered

t5  Sidebar updates: .hotfix row disappears
```

---

## 7. Diff Contract: Full Grouped State

The diff tracks complete grouped state, not just clone paths. This handles linked worktree additions AND removals.

### State Tracking

```
CURRENT (flat, broken):
  watchedFolderRepoPathsByRoot: [URL: Set<URL>]
  → detects clone appeared/disappeared
  → CANNOT detect linked worktree list changes

FIXED (grouped):
  watchedFolderGroupsByRoot: [URL: [ScannedRepoGroup]]
  → detects clone appeared/disappeared AND linked list changes
```

### Diff Logic

```
For each watched folder, compare previous vs current [ScannedRepoGroup]:

1. New clone (not in previous)
   → emit .repoDiscovered(clone, linked:[...])

2. Existing clone with changed linked worktree list
   → re-emit .repoDiscovered(clone, linked:[current list])
   → coordinator reconciles via reconciler (handles adds AND removes)

3. Removed clone (not in current)
   → GLOBAL dedup: check ALL watched folders before emitting
   → only emit .repoRemoved if no other folder references this clone
   → emit .repoRemoved(clone)

4. Unchanged → no event (idempotent)
```

### Global Dedup for Removes

```
Folder A: ~/worktrees-a/feat → linked to ~/repos/my-project
Folder B: ~/worktrees-b/fix  → linked to ~/repos/my-project

User removes folder A:
  → folder A's ~/repos/my-project entry removed
  → BUT folder B still references same parent
  → global check: still alive in folder B → DON'T emit .repoRemoved
```

---

## 8. Envelope Types

### Widened `.repoDiscovered`

```swift
// RuntimeEnvelopeCore.swift
enum TopologyEvent: Sendable {
    case repoDiscovered(repoPath: URL, parentPath: URL, linkedWorktrees: LinkedWorktreeInfo = .notScanned)
    case repoRemoved(repoPath: URL)
    case worktreeRegistered(worktreeId: UUID, repoId: UUID, rootPath: URL)
    case worktreeUnregistered(worktreeId: UUID, repoId: UUID)
}

/// Discriminated union distinguishing "scanner ran and found these" from "no scan performed."
/// Avoids the nil-vs-empty-array ambiguity.
enum LinkedWorktreeInfo: Sendable, Equatable {
    /// Scanner ran and found these linked worktrees. Empty array = no linked worktrees exist.
    case scanned([URL])
    /// No scan performed (boot replay, manual add). Leave existing worktrees unchanged.
    case notScanned
}
```

**Why a union, not `[URL]?`:** `nil` vs `[]` is a convention you have to know. `.scanned([])` reads as "we scanned and found nothing." `.notScanned` reads as "we didn't scan." The pattern match makes the decision point visible in code review — nobody can accidentally conflate "absent" with "empty."

```
Boot replay:  .repoDiscovered(path, parent, linkedWorktrees: .notScanned)
              → coordinator skips reconciliation, worktrees preserved from restore

Scanner:      .repoDiscovered(path, parent, linkedWorktrees: .scanned([feat, hotfix]))
              → coordinator reconciles full family

Scanner (all removed): .repoDiscovered(path, parent, linkedWorktrees: .scanned([]))
              → coordinator reconciles to main-only, removes stale linked worktrees
```

Default `= []` keeps existing call sites and boot replay backward-compatible. Pattern matches require updating (see Task 1).

### TraceId for Observability

`TopologyDelta.traceId` links to the originating event's `eventId`. For observability — tracing causation in logs — not for runtime ordering:

```
[t=100ms] EventBus delivered .repoDiscovered eventId=E1
[t=101ms] Coordinator reconciled, delta: added=[wt1], traceId=E1
[t=102ms] PaneCoordinator.topologyDidChange, synced roots, traceId=E1
```

---

## 9. TopologyEffectHandler

### The Protocol

```swift
@MainActor
protocol TopologyEffectHandler: AnyObject {
    func topologyDidChange(_ delta: WorktreeTopologyDelta)
}
```

### Who Handles What in the Delta

Cache pruning stays in the coordinator (it already owns `repoCache`). Pane/filesystem effects go to PaneCoordinator (it already owns `store` and `filesystemSource`). The coordinator sequences both:

```swift
// In WorkspaceCacheCoordinator, after reconciliation:
if delta.didChange {
    // 1. Cache cleanup (coordinator owns repoCache)
    for worktreeId in delta.removedWorktreeIds {
        repoCache.removeWorktree(worktreeId)
    }

    // 2. Pane/filesystem effects (PaneCoordinator owns these)
    topologyEffectHandler?.topologyDidChange(delta)
}
```

### PaneCoordinator Conforms

PaneCoordinator does NOT get `repoCache`. It handles only what it already owns:

```swift
extension PaneCoordinator: TopologyEffectHandler {
    func topologyDidChange(_ delta: WorktreeTopologyDelta) {
        // 1. Orphan panes for removed worktrees
        for (worktreeId, path) in delta.removedWorktrees {
            store.orphanPanesForWorktree(worktreeId, path: path.path)
        }

        // 2. Sync filesystem roots (handles both adds and removes)
        syncFilesystemRootsAndActivity()
    }
}
```

**Note:** `WorkspaceStore` currently has `orphanPanesForRepo(_:)` but not `orphanPanesForWorktree(_:)`. This plan adds the narrower variant — same logic, scoped to one worktreeId instead of all worktrees in a repo. See Task 3 step for implementation.
```

### PaneCoordinator Stops Subscribing to Topology on the Bus

Current code (`PaneCoordinator+FilesystemSource.swift:26-30`):
```swift
case .system(let systemEnvelope):
    guard case .topology = systemEnvelope.event else { return false }
    scheduleFilesystemRootAndActivitySync()  // ← accidental ordering
    return true
```

After: this topology branch is **removed**. PaneCoordinator only receives topology changes via the handler. Its bus subscription narrows to worktree-scoped events for filesystem projection.

### Wiring at Composition Root

```swift
// AppDelegate.swift
let paneCoordinator = PaneCoordinator(...)
let workspaceCacheCoordinator = WorkspaceCacheCoordinator(
    bus: paneRuntimeBus,
    workspaceStore: store,
    repoCache: workspaceRepoCache,
    scopeSyncHandler: { ... },
    topologyEffectHandler: paneCoordinator  // ← NEW
)
```

---

## 10. Testing Strategy

Every layer testable in isolation. No wall-clock waits. No real filesystem or git in unit tests.

### WorktreeReconciler (Pure Function Tests)

```swift
@Test("preserves existing UUIDs for matching paths")
@Test("adds new worktrees with fresh UUIDs")
@Test("removes worktrees not in discovered list")
@Test("delta reflects added/removed/preserved")
@Test("matches main worktree by isMainWorktree flag")
@Test("empty discovered list removes all worktrees")
@Test("identical lists produce didChange: false")
```

No mocking. Input: two arrays. Output: merged array + delta.

### Scanner Classification (Unit Tests)

```swift
@Test(".git directory → .cloneRoot")              // temp dir, no git
@Test(".git file with gitdir → .linkedWorktree")  // temp dir, no git
@Test("no .git → nil")                            // temp dir, no git
@Test("parseParentClonePath from absolute gitdir") // pure string, no filesystem
@Test("parseParentClonePath from relative gitdir") // pure string, no filesystem
@Test("groupClassifiedPaths groups linked under parent") // pure function, no filesystem
@Test("groupClassifiedPaths handles orphaned linked worktrees") // pure function
```

Classification tests use temp directories — no git commands needed (they test `.git` file/directory stat and content parsing). Grouping tests are pure functions operating on `[(URL, GitEntryKind)]` arrays.

The full `scanForGitReposGrouped` calls `scanForGitRepos` which runs `git rev-parse` validation (hardcoded in `RepoScanner.runGit`, no injection seam). Integration tests for the full scan path go through `FilesystemActor` with an injected `groupedWatchedFolderScanner` closure that returns pre-built `[ScannedRepoGroup]` results — bypassing the real scanner entirely.

### Coordinator Integration (Event Bus Tests)

```swift
@Test(".repoDiscovered with linked worktrees → grouped repo in store")
@Test(".repoDiscovered update → reconciles worktree list via reconciler")
@Test(".repoDiscovered without linked → standalone repo (backward compat)")
@Test("topology delta passed to effect handler")
@Test("removed worktree delta includes correct worktreeIds")
```

Pattern: create bus + store + coordinator with mock effect handler. Post events. Assert store state and handler invocations. Uses `eventually()` polling — no `Task.sleep`.

### Effect Handler (Unit Tests)

```swift
@Test("orphans panes for removed worktreeIds")
@Test("prunes cache for removed worktreeIds")
@Test("calls syncFilesystemRootsAndActivity")
@Test("no-op for empty delta")
```

### Sidebar (Unit Tests)

```swift
@Test("main worktree → star icon")
@Test("secondary worktree → worktree icon")
@Test("standalone repo → star icon")
@Test("all worktrees in same repo share color")
```

Pure function tests on static methods. No bus, no actors.

---

## 11. File Structure

| File | Action | What Changes |
|------|--------|-------------|
| `Sources/.../Infrastructure/RepoScanner.swift` | Modify | Add `GitEntryKind`, `classifyGitEntry()`, `parseParentClonePath()`, `groupClassifiedPaths()`, `scanForGitReposGrouped()` |
| `Sources/.../Infrastructure/WorktreeReconciler.swift` | **Create** | Pure function: `reconcile(existing, discovered) → (merged, delta)`. Extracted from `WorkspaceStore.reconcileDiscoveredWorktrees` |
| `Sources/.../Contracts/RuntimeEnvelopeCore.swift:22` | Modify | Add `LinkedWorktreeInfo` enum, widen `.repoDiscovered` with `linkedWorktrees: LinkedWorktreeInfo = .notScanned` |
| `Sources/.../Filesystem/FilesystemActor.swift` | Modify | Use grouped scanner, track `[ScannedRepoGroup]` per folder, grouped diff, global dedup for removes |
| `Sources/.../App/Coordination/WorkspaceCacheCoordinator.swift` | Modify | Use `WorktreeReconciler`, inject `TopologyEffectHandler`, call handler with delta |
| `Sources/.../App/Coordination/PaneCoordinator+FilesystemSource.swift` | Modify | Remove topology bus subscription, conform to `TopologyEffectHandler` |
| `Sources/.../App/Coordination/PaneCoordinator.swift` | Modify | Add `TopologyEffectHandler` conformance |
| `Sources/.../App/Boot/AppDelegate.swift` | Modify | Wire `topologyEffectHandler: paneCoordinator` into coordinator |
| `Sources/.../Replay/EventReplayBuffer.swift` | Modify | Update `.repoDiscovered` pattern match and sizing |
| `Sources/.../Sidebar/RepoSidebarContentView.swift` | Modify | Simplify `checkoutIconKind`, remove `standaloneCheckout` enum case, star for main |
| `Tests/.../Infrastructure/RepoScannerTests.swift` | **Create** | Classification + grouping tests |
| `Tests/.../Infrastructure/WorktreeReconcilerTests.swift` | **Create** | Reconciler pure function tests |
| `Tests/.../App/WorkspaceCacheCoordinatorIntegrationTests.swift` | Modify | Grouped discovery + delta tests |
| `Tests/.../Sidebar/RepoSidebarContentViewTests.swift` | Modify | Icon tests with multi-worktree repos |
| `docs/architecture/workspace_data_architecture.md` | Modify | Document `.repoDiscovered` contract change, topology accumulator pattern, effect handler |
| `docs/architecture/pane_runtime_eventbus_design.md` | Modify | Document handler pattern alongside bus |

---

## Task 1: Contract and Infrastructure

**Files:**
- Modify: `Sources/AgentStudio/Core/RuntimeEventSystem/Contracts/RuntimeEnvelopeCore.swift`
- Create: `Sources/AgentStudio/Infrastructure/WorktreeReconciler.swift`
- Modify: `Sources/AgentStudio/Infrastructure/RepoScanner.swift`
- Create: `Tests/AgentStudioTests/Infrastructure/WorktreeReconcilerTests.swift`
- Create: `Tests/AgentStudioTests/Infrastructure/RepoScannerTests.swift`

This task establishes the two new building blocks (reconciler + scanner classification) and widens the topology event. Everything is testable without actors or bus.

- [ ] **Step 1: Write failing reconciler tests**

```swift
import Foundation
import Testing

@testable import AgentStudio

@Suite("WorktreeReconciler")
struct WorktreeReconcilerTests {
    @Test("preserves existing UUID when path matches")
    func preservesUUID() {
        let existingId = UUID()
        let existing = [Worktree(id: existingId, repoId: UUID(), name: "main", path: URL(fileURLWithPath: "/repo"), isMainWorktree: true)]
        let discovered = [Worktree(repoId: UUID(), name: "main", path: URL(fileURLWithPath: "/repo"), isMainWorktree: true)]

        let (merged, delta) = WorktreeReconciler.reconcile(repoId: UUID(), existing: existing, discovered: discovered)

        #expect(merged[0].id == existingId)
        #expect(delta.didChange == false)
        #expect(delta.addedWorktreeIds.isEmpty)
        #expect(delta.removedWorktreeIds.isEmpty)
    }

    @Test("adds new worktree and reports in delta")
    func addsNewWorktree() {
        let repoId = UUID()
        let existing = [Worktree(repoId: repoId, name: "main", path: URL(fileURLWithPath: "/repo"), isMainWorktree: true)]
        let discovered = [
            Worktree(repoId: repoId, name: "main", path: URL(fileURLWithPath: "/repo"), isMainWorktree: true),
            Worktree(repoId: repoId, name: "feat", path: URL(fileURLWithPath: "/repo.feat"), isMainWorktree: false),
        ]

        let (merged, delta) = WorktreeReconciler.reconcile(repoId: repoId, existing: existing, discovered: discovered)

        #expect(merged.count == 2)
        #expect(delta.addedWorktreeIds.count == 1)
        #expect(delta.removedWorktreeIds.isEmpty)
        #expect(delta.didChange == true)
    }

    @Test("removes missing worktree and reports in delta")
    func removesMissingWorktree() {
        let repoId = UUID()
        let removedId = UUID()
        let existing = [
            Worktree(repoId: repoId, name: "main", path: URL(fileURLWithPath: "/repo"), isMainWorktree: true),
            Worktree(id: removedId, repoId: repoId, name: "hotfix", path: URL(fileURLWithPath: "/repo.hotfix"), isMainWorktree: false),
        ]
        let discovered = [
            Worktree(repoId: repoId, name: "main", path: URL(fileURLWithPath: "/repo"), isMainWorktree: true),
        ]

        let (merged, delta) = WorktreeReconciler.reconcile(repoId: repoId, existing: existing, discovered: discovered)

        #expect(merged.count == 1)
        #expect(delta.removedWorktrees.map(\.id) == [removedId])
        #expect(delta.removedWorktrees[0].path == URL(fileURLWithPath: "/repo.hotfix"))
        #expect(delta.didChange == true)
    }

    @Test("empty discovered list removes all")
    func emptyDiscoveredRemovesAll() {
        let repoId = UUID()
        let existing = [
            Worktree(repoId: repoId, name: "main", path: URL(fileURLWithPath: "/repo"), isMainWorktree: true),
            Worktree(repoId: repoId, name: "feat", path: URL(fileURLWithPath: "/repo.feat"), isMainWorktree: false),
        ]

        let (merged, delta) = WorktreeReconciler.reconcile(repoId: repoId, existing: existing, discovered: [])

        #expect(merged.isEmpty)
        #expect(delta.removedWorktrees.count == 2)
    }
}
```

- [ ] **Step 2: Run tests — verify they fail**
- [ ] **Step 3: Implement `WorktreeReconciler`**

Create `Sources/AgentStudio/Infrastructure/WorktreeReconciler.swift`:

```swift
import Foundation

struct WorktreeTopologyDelta: Sendable, Equatable {
    let repoId: UUID
    let addedWorktreeIds: [UUID]
    let removedWorktrees: [(id: UUID, path: URL)]  // path needed for orphaning reason
    let preservedWorktreeIds: [UUID]
    let didChange: Bool
    let traceId: UUID?
}

enum WorktreeReconciler {
    static func reconcile(
        repoId: UUID,
        existing: [Worktree],
        discovered: [Worktree],
        traceId: UUID? = nil
    ) -> (merged: [Worktree], delta: WorktreeTopologyDelta) {
        let existingByPath = Dictionary(
            existing.map { ($0.path.standardizedFileURL, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let existingMain = existing.first(where: \.isMainWorktree)
        let existingByName = Dictionary(
            existing.map { ($0.name, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        var preservedIds: [UUID] = []
        var addedIds: [UUID] = []

        let merged = discovered.map { disc -> Worktree in
            if let match = existingByPath[disc.path.standardizedFileURL] {
                preservedIds.append(match.id)
                var updated = match
                updated.name = disc.name
                updated.isMainWorktree = disc.isMainWorktree
                return updated
            }
            if disc.isMainWorktree, let existingMain {
                preservedIds.append(existingMain.id)
                return Worktree(
                    id: existingMain.id, repoId: repoId,
                    name: disc.name, path: disc.path,
                    isMainWorktree: disc.isMainWorktree
                )
            }
            if let matched = existingByName[disc.name] {
                preservedIds.append(matched.id)
                return Worktree(
                    id: matched.id, repoId: repoId,
                    name: disc.name, path: disc.path,
                    isMainWorktree: disc.isMainWorktree
                )
            }
            let newWorktree = Worktree(
                repoId: repoId, name: disc.name,
                path: disc.path, isMainWorktree: disc.isMainWorktree
            )
            addedIds.append(newWorktree.id)
            return newWorktree
        }

        let preservedSet = Set(preservedIds)
        let removedWorktrees = existing
            .filter { !preservedSet.contains($0.id) }
            .map { (id: $0.id, path: $0.path) }
        let didChange = merged != existing

        return (
            merged: merged,
            delta: WorktreeTopologyDelta(
                repoId: repoId,
                addedWorktreeIds: addedIds,
                removedWorktrees: removedWorktrees,
                preservedWorktreeIds: preservedIds,
                didChange: didChange,
                traceId: traceId
            )
        )
    }
}
```

- [ ] **Step 4: Run reconciler tests — verify they pass**
- [ ] **Step 5: Write failing scanner classification tests**

```swift
import Foundation
import Testing

@testable import AgentStudio

@Suite("RepoScanner classification")
struct RepoScannerClassificationTests {
    @Test(".git directory → cloneRoot")
    func gitDirectoryIsClone() throws {
        let tmp = FileManager.default.temporaryDirectory.appending(path: "scanner-\(UUID().uuidString)")
        let repo = tmp.appending(path: "my-repo")
        try FileManager.default.createDirectory(at: repo.appending(path: ".git"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }
        #expect(RepoScanner.classifyGitEntry(at: repo) == .cloneRoot)
    }

    @Test(".git file → linkedWorktree with parent path")
    func gitFileIsLinked() throws {
        let tmp = FileManager.default.temporaryDirectory.appending(path: "scanner-\(UUID().uuidString)")
        let parent = tmp.appending(path: "my-repo")
        let wt = tmp.appending(path: "my-repo.feat")
        try FileManager.default.createDirectory(at: parent.appending(path: ".git"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: wt, withIntermediateDirectories: true)
        try "gitdir: \(parent.path)/.git/worktrees/feat\n"
            .write(to: wt.appending(path: ".git"), atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tmp) }

        guard case .linkedWorktree(let parentPath) = RepoScanner.classifyGitEntry(at: wt) else {
            Issue.record("Expected linkedWorktree"); return
        }
        #expect(parentPath.standardizedFileURL == parent.standardizedFileURL)
    }

    @Test("no .git → nil")
    func noGitIsNil() throws {
        let tmp = FileManager.default.temporaryDirectory.appending(path: "scanner-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }
        #expect(RepoScanner.classifyGitEntry(at: tmp) == nil)
    }

    @Test("parseParentClonePath from absolute gitdir")
    func parseAbsolute() {
        let result = RepoScanner.parseParentClonePath(
            fromGitFileContent: "gitdir: /dev/my-repo/.git/worktrees/feat\n"
        )
        #expect(result == URL(fileURLWithPath: "/dev/my-repo"))
    }

    @Test("groupClassifiedPaths groups linked under clone")
    func grouping() {
        let clone = URL(fileURLWithPath: "/tmp/repo")
        let wt = URL(fileURLWithPath: "/tmp/repo.feat")
        let standalone = URL(fileURLWithPath: "/tmp/other")

        let groups = RepoScanner.groupClassifiedPaths([
            (clone, .cloneRoot),
            (wt, .linkedWorktree(parentClonePath: clone)),
            (standalone, .cloneRoot),
        ])

        #expect(groups.count == 2)
        let cloneGroup = groups.first { $0.clonePath.standardizedFileURL == clone.standardizedFileURL }
        #expect(cloneGroup?.linkedWorktreePaths.count == 1)
    }

    @Test("groupClassifiedPaths handles orphaned linked worktrees")
    func orphanGrouping() {
        let orphanParent = URL(fileURLWithPath: "/other/repo")
        let wt = URL(fileURLWithPath: "/tmp/repo.feat")

        let groups = RepoScanner.groupClassifiedPaths([
            (wt, .linkedWorktree(parentClonePath: orphanParent)),
        ])

        #expect(groups.count == 1)
        #expect(groups[0].clonePath.standardizedFileURL == orphanParent.standardizedFileURL)
    }
}
```

- [ ] **Step 6: Implement scanner classification** (see Section 5 for the code: `GitEntryKind`, `classifyGitEntry`, `parseParentClonePath`, `groupClassifiedPaths`, `scanForGitReposGrouped`)
- [ ] **Step 7: Run scanner tests — verify they pass**
- [ ] **Step 8: Add `LinkedWorktreeInfo` and widen `.repoDiscovered` in `RuntimeEnvelopeCore.swift`**

```swift
enum LinkedWorktreeInfo: Sendable, Equatable {
    case scanned([URL])
    case notScanned
}

// In TopologyEvent:
case repoDiscovered(repoPath: URL, parentPath: URL, linkedWorktrees: LinkedWorktreeInfo = .notScanned)
```

Default `.notScanned` keeps boot replay and existing call sites backward-compatible.

- [ ] **Step 9: Update ALL `.repoDiscovered` pattern matches and consumers**

Run: `grep -rn 'case .repoDiscovered\|\.repoDiscovered(' Sources/ Tests/ --include='*.swift'`

Known sites requiring update:
- `WorkspaceCacheCoordinator.handleTopology` (`WorkspaceCacheCoordinator.swift:72`)
- `EventReplayBuffer` sizing (`EventReplayBuffer.swift:255`)
- `FilesystemActorWatchedFolderTests` (`FilesystemActorWatchedFolderTests.swift:220`)
- `RuntimeEnvelopeFactories.swift` — check `SystemEnvelope.test()` factory
- Boot replay in `AppDelegate`
- Any contract or serialization tests

- [ ] **Step 10: Build — verify compilation**
- [ ] **Step 11: Run full test suite**
- [ ] **Step 12: Commit**

```bash
git commit -m "feat: WorktreeReconciler, scanner classification, widen .repoDiscovered"
```

---

## Task 2: FilesystemActor Grouped Diff

**Files:**
- Modify: `Sources/AgentStudio/Core/RuntimeEventSystem/Filesystem/FilesystemActor.swift`

- [ ] **Step 1: Add grouped scanner injection and state**

```swift
private let groupedWatchedFolderScanner: @Sendable (URL) -> [ScannedRepoGroup]
private var watchedFolderGroupsByRoot: [URL: [ScannedRepoGroup]] = [:]
```

- [ ] **Step 2: Rewrite `refreshWatchedFolder` with grouped diff**

Diff logic per Section 7: new clones, changed linked lists (re-emit), removed clones (global dedup).

- [ ] **Step 3: Update `emitRepoDiscovered` to pass `LinkedWorktreeInfo.scanned(paths)`**

Scanner results use `.scanned(linkedPaths)` — this is authoritative. Boot replay uses `.notScanned` (the default).
- [ ] **Step 4: Clean up state in `shutdown()`**
- [ ] **Step 5: Build and run tests**
- [ ] **Step 6: Commit**

```bash
git commit -m "feat: FilesystemActor emits grouped .repoDiscovered with linked worktrees"
```

---

## Task 3: Coordinator Uses Reconciler + Effect Handler

**Files:**
- Modify: `Sources/AgentStudio/App/Coordination/WorkspaceCacheCoordinator.swift`
- Modify: `Sources/AgentStudio/App/Coordination/PaneCoordinator+FilesystemSource.swift`
- Modify: `Sources/AgentStudio/App/Coordination/PaneCoordinator.swift`
- Modify: `Sources/AgentStudio/App/Boot/AppDelegate.swift`
- Modify: `Tests/AgentStudioTests/App/WorkspaceCacheCoordinatorIntegrationTests.swift`

- [ ] **Step 1: Define `TopologyEffectHandler` protocol**

```swift
@MainActor
protocol TopologyEffectHandler: AnyObject {
    func topologyDidChange(_ delta: WorktreeTopologyDelta)
}
```

- [ ] **Step 2: Inject handler into coordinator**

Add `topologyEffectHandler: (any TopologyEffectHandler)?` to `WorkspaceCacheCoordinator.init`.

- [ ] **Step 3: Update `.repoDiscovered` handler to use reconciler + call handler**

```swift
case .repoDiscovered(let repoPath, _, let linkedWorktrees):
    // ... existing dedup logic (stableKey check, addRepo) ...

    // Only reconcile when scanner provided authoritative data.
    // .notScanned (boot replay) → skip, leave existing worktrees unchanged.
    // .scanned([]) → authoritative empty, remove all linked worktrees.
    // .scanned([paths]) → authoritative list, reconcile to match.
    guard case .scanned(let linkedPaths) = linkedWorktrees else { break }

    let discovered = buildDiscoveredWorktreeList(
        clonePath: repoPath, linkedPaths: linkedPaths, repoId: repo.id
    )
    let existing = repo.worktrees
    let (merged, delta) = WorktreeReconciler.reconcile(
        repoId: repo.id, existing: existing, discovered: discovered,
        traceId: envelope.eventId
    )
    if delta.didChange {
        // 1. Store mutation (existing API)
        workspaceStore.reconcileDiscoveredWorktrees(repo.id, worktrees: merged)
        // 2. Cache cleanup — must happen before pane effects below
        //    (coordinator owns repoCache; prevents stale enrichment reads)
        for (worktreeId, _) in delta.removedWorktrees {
            repoCache.removeWorktree(worktreeId)
        }
        // 3. Pane/filesystem effects (PaneCoordinator)
        topologyEffectHandler?.topologyDidChange(delta)
    }
```

- [ ] **Step 4: Add `orphanPanesForWorktree` to WorkspaceStore**

The existing `orphanPanesForRepo(_:)` (`WorkspaceStore.swift:1340`) orphans ALL panes for a repo. We need the narrower variant for single worktree removal.

The residency model uses `SessionResidency.orphaned(reason:)` with `WorktreeUnavailableReason` (`SessionResidency.swift:5-33`):

```swift
enum SessionResidency: Equatable, Codable, Hashable {
    case active
    case pendingUndo(expiresAt: Date)
    case backgrounded
    case orphaned(reason: WorktreeUnavailableReason)
}

enum WorktreeUnavailableReason: Equatable, Codable, Hashable {
    case worktreeNotFound(path: String)
}
```

Implementation:

```swift
@discardableResult
func orphanPanesForWorktree(_ worktreeId: UUID) -> [UUID] {
    guard let worktree = repos.flatMap(\.worktrees).first(where: { $0.id == worktreeId }) else {
        return []
    }
    let worktreePath = worktree.path.path
    let affectedPaneIds = panes.values
        .filter { $0.worktreeId == worktreeId }
        // Skip panes in transition (pendingUndo, already orphaned) — only orphan resident panes
        .filter { $0.residency == .active || $0.residency == .backgrounded }
        .map(\.id)
    for paneId in affectedPaneIds {
        panes[paneId]?.residency = .orphaned(reason: .worktreeNotFound(path: worktreePath))
    }
    if !affectedPaneIds.isEmpty { markDirty() }
    return affectedPaneIds
}
```

**Note:** Call `orphanPanesForWorktree` BEFORE the worktree is removed from the store's `repo.worktrees` array — otherwise the worktree path lookup fails. The coordinator handles this by calling the effect handler (which orphans panes) after `reconcileDiscoveredWorktrees` removes the worktree from the array. To fix this ordering: the coordinator should capture the removed worktree paths from the delta BEFORE calling reconcile, or `orphanPanesForWorktree` should accept a path parameter directly. Simplest: change the signature to accept the path:

```swift
@discardableResult
func orphanPanesForWorktree(_ worktreeId: UUID, path: String) -> [UUID] {
    let affectedPaneIds = panes.values
        .filter { $0.worktreeId == worktreeId }
        .filter { $0.residency == .active || $0.residency == .backgrounded }
        .map(\.id)
    for paneId in affectedPaneIds {
        panes[paneId]?.residency = .orphaned(reason: .worktreeNotFound(path: path))
    }
    if !affectedPaneIds.isEmpty { markDirty() }
    return affectedPaneIds
}
```

And `WorktreeTopologyDelta` should carry removed paths alongside removed IDs:

```swift
struct WorktreeTopologyDelta: Sendable, Equatable {
    let repoId: UUID
    let addedWorktreeIds: [UUID]
    let removedWorktrees: [(id: UUID, path: URL)]  // ← path needed for orphaning reason
    let preservedWorktreeIds: [UUID]
    let didChange: Bool
    let traceId: UUID?
}
```

- [ ] **Step 5: PaneCoordinator conforms to `TopologyEffectHandler`**

See Section 9 for the implementation. PaneCoordinator calls `store.orphanPanesForWorktree` (the new method) and `syncFilesystemRootsAndActivity` (existing method). It does NOT touch `repoCache`.

- [ ] **Step 5: Remove topology bus subscription from PaneCoordinator**

In `PaneCoordinator+FilesystemSource.swift`, remove the `.system(.topology)` branch from `handleFilesystemEnvelopeIfNeeded`.

- [ ] **Step 6: Wire in AppDelegate**

```swift
topologyEffectHandler: paneCoordinator
```

- [ ] **Step 7: Write integration tests**

```swift
@Test("repoDiscovered with .scanned([wt1,wt2]) creates grouped repo and calls effect handler")
@Test("repoDiscovered with .scanned([wt1]) after .scanned([wt1,wt2]) removes wt2 and produces delta")
@Test("repoDiscovered with .scanned([]) removes all linked worktrees")
@Test("repoDiscovered with .notScanned leaves existing worktrees unchanged (boot replay)")
@Test("effect handler receives correct delta with removed worktree paths")
```

- [ ] **Step 8: Run full test suite**
- [ ] **Step 9: Commit**

```bash
git commit -m "feat: coordinator uses WorktreeReconciler + TopologyEffectHandler"
```

---

## Task 4: Sidebar Icons

**Files:**
- Modify: `Sources/AgentStudio/Features/Sidebar/RepoSidebarContentView.swift`
- Modify: `Tests/AgentStudioTests/Features/Sidebar/RepoSidebarContentViewTests.swift`

Once Tasks 1-3 land, `repo.worktrees` has correct `isMainWorktree` flags. Sidebar changes are minimal.

- [ ] **Step 1: Write icon tests**

```swift
@Test("main worktree → star") ...
@Test("secondary worktree → worktree icon") ...
@Test("standalone repo → star") ...
```

- [ ] **Step 2: Rewrite `checkoutIconKind` as static method**

```swift
static func checkoutIconKind(for worktree: Worktree, in repo: SidebarRepo) -> SidebarCheckoutIconKind {
    let isMain = worktree.isMainWorktree
        || worktree.path.standardizedFileURL.path == repo.repoPath.standardizedFileURL.path
    return isMain ? .mainCheckout : .gitWorktree
}
```

- [ ] **Step 3: Remove `standaloneCheckout` enum case entirely**

```swift
enum SidebarCheckoutIconKind {
    case mainCheckout    // star — main worktree or standalone repo
    case gitWorktree     // worktree icon — secondary worktree
}
```

No producer emits `.standaloneCheckout`. Removing it prevents drift.
Run `grep -rn 'standaloneCheckout' Sources/` to find and update all references.

- [ ] **Step 4: Update `checkoutTypeIcon` for two-case enum**

Use `OcticonImage` for custom octicon assets and SF Symbols (`Image(systemName:)`) for Apple system icons. Do NOT use `WorkspaceOcticonImage` — it should be removed if it exists.
- [ ] **Step 5: Verify color logic needs no changes** (all worktrees share `repo.id` → same color)
- [ ] **Step 6: Run tests, run full suite**
- [ ] **Step 7: Commit**

```bash
git commit -m "fix: sidebar icons — star for main/standalone, worktree for secondary"
```

---

## Task 5: Update Architecture Docs

Four docs need updates. Each owns a specific concern — update only what that doc is authoritative for.

**Files:**
- Modify: `docs/architecture/workspace_data_architecture.md`
- Modify: `docs/architecture/pane_runtime_eventbus_design.md`
- Modify: `docs/architecture/component_architecture.md`
- Modify: `docs/architecture/README.md`

### `workspace_data_architecture.md` — Topology, Enrichment, Sidebar

This is the authoritative doc for topology contracts, enrichment pipeline, and sidebar data flow. Heaviest changes.

- [ ] **Step 1: Update Event Namespaces section (line 265-292)**

Update the `TopologyEvent` listing to show the widened `.repoDiscovered`:

```
TopologyEvent (envelope: SystemEnvelope, all via bus)
  .repoDiscovered(repoPath:, parentPath:, linkedWorktrees: LinkedWorktreeInfo = .notScanned)
      — producer: AppDelegate (boot replay), FilesystemActor (watched folder diff)
      — .scanned([urls]) = authoritative scanner result (may be empty = no linked worktrees)
      — .notScanned = no scan performed (boot replay), leave existing worktrees unchanged
  .repoRemoved(repoPath:)
  .worktreeRegistered(worktreeId:, repoId:, rootPath:)
  .worktreeUnregistered(worktreeId:, repoId:)
```

- [ ] **Step 2: Update Enrichment Pipeline diagram (line 149-192)**

Add scanner classification and grouped discovery to the pipeline:

```
WORKSPACE STATE (canonical repos/worktrees, panes/tabs)
      │
      │ restored at boot → topology events replayed on bus
      ▼
FilesystemActor (raw filesystem I/O)
  watched folder scan via RepoScanner:
    - classifies .git directory (clone) vs .git file (linked worktree)
    - groups linked worktrees under parent clones
    - diffs grouped state, emits .repoDiscovered with .scanned(linkedPaths)
  worktree roots → deep FSEvents watch (DarwinFSEventStreamClient)
  emits: SystemEnvelope(.topology(..))     ← repo discovery/removal (grouped)
         WorktreeEnvelope(.filesystem(..)) ← file change facts
```

- [ ] **Step 3: Update Coordinator responsibilities (line 232-252)**

Update `handleTopology_*` to document the reconciler + effect handler pattern:

```
handleTopology_*    — CANONICAL mutations (WorkspaceStore)
  Events: .topology(.repoDiscovered), .topology(.repoRemoved)
  Flow:
    1. Interpret fact (extract linked worktree paths from event)
    2. Build discovered worktree list
    3. Call WorktreeReconciler.reconcile(existing, discovered)
       → pure function, returns (merged, TopologyDelta)
    4. Update store with merged worktree list
    5. Call topologyEffectHandler.topologyDidChange(delta)
       → PaneCoordinator handles ordered effects
  
  The coordinator is sequencing-only. Diff/identity logic lives in
  WorktreeReconciler (pure function). Ordered effects live in
  TopologyEffectHandler (PaneCoordinator).
```

- [ ] **Step 4: Update "User Adds a Folder" lifecycle flow (line 338-360)**

Update steps 6-8:

```
6. WorkspaceCacheCoordinator.handleTopology(.repoDiscovered):
   a. Idempotent check by stableKey — skip if repo already exists
   b. If new: addRepo(at:), seed .awaitingOrigin
   c. If linkedWorktrees is .scanned(paths):
      - Build discovered worktree list (main + linked)
      - WorktreeReconciler.reconcile(existing, discovered)
      - Update store with merged list
      - topologyEffectHandler.topologyDidChange(delta)
7. TopologyEffectHandler (PaneCoordinator):
   a. Orphan panes for delta.removedWorktreeIds
   b. Prune cache for removed worktrees
   c. syncFilesystemRootsAndActivity() — registers new roots, unregisters removed
8. Actors start producing enrichment events → cache updates → sidebar renders
```

- [ ] **Step 5: Add new section: Topology Accumulator Pattern**

Add after "Event System Design: What It Is (and Isn't)" section (around line 428):

```markdown
### Topology Accumulator Pattern

Topology facts flow through a layered pipeline where each layer's output is the next layer's input:

| Layer | Component | Owns | Does Not Own |
|-------|-----------|------|--------------|
| Fact | FilesystemActor | Observing filesystem, emitting raw facts | Interpreting what facts mean |
| Publication | EventBus | Fan-out to all subscribers | Ordering, filtering |
| Accumulator | WorkspaceCacheCoordinator | Interpreting facts, sequencing effects | Domain diff logic, identity preservation |
| Reconciler | WorktreeReconciler (pure function) | Identity preservation, diff computation | Store access, side effects |
| State | WorkspaceStore (atom) | Canonical truth, simple setters | Sequencing, events, diffs |
| Effects | TopologyEffectHandler (PaneCoordinator) | Ordered follow-on work (orphan panes, sync roots) | Interpreting raw facts, mutating canonical state |
| Reader | Sidebar | Rendering truth via @Observable | Mutating anything |

**Why not pure pub/sub for topology:**
Multiple subscribers independently inferring what changed from raw events is fragile — ordering implicit, diffs rediscovered, cleanup ad hoc. The accumulator pattern ensures one interpreter, one diff, one ordered effect chain.

**Why the bus still exists for topology:**
Independent consumers (ForgeActor, NotificationReducer) subscribe to raw topology facts on the bus. They react independently, don't depend on store state, and don't need ordering guarantees. The bus serves notification; the handler serves sequencing.
```

- [ ] **Step 6: Update Scanner section (line 254-260)**

Add classification behavior to the RepoScanner description:

```markdown
### Discovery — Repo Scanning

`RepoScanner` walks the filesystem from a root URL and classifies each `.git` entry:
- `.git` directory → clone root (real `git init`/`git clone`)
- `.git` file → linked worktree (reads `gitdir:` to derive parent clone path)

After classification, it groups linked worktrees under their parent clone into `ScannedRepoGroup` entries. The existing validation behavior is preserved: `git rev-parse --is-inside-work-tree` and submodule exclusion via `--show-superproject-working-tree`.

Used by `FilesystemActor` as the blocking filesystem walk behind watched-folder refresh. The grouped results enable the coordinator to create correct worktree families from the first topology event.

> **File:** `Infrastructure/RepoScanner.swift`
```

### `pane_runtime_eventbus_design.md` — Bus Coordination Patterns

This doc is authoritative for how actors connect to the bus and the threading model.

- [ ] **Step 7: Update WorkspaceCacheCoordinator connection inventory**

Find the `WorkspaceCacheCoordinator` entry in the Per-Actor Connection Inventory and add the effect handler output:

```
| **Out** | `topologyEffectHandler.topologyDidChange(delta)` | Direct call | Ordered effects that depend on store mutation completing first. Deterministic — not via bus. |
```

- [ ] **Step 8: Update PaneCoordinator connection inventory**

Remove the topology bus subscription entry. Add the handler entry:

```
| **In** | `TopologyEffectHandler.topologyDidChange(delta)` | Direct call from coordinator | Deterministic post-topology effects. Replaces bus topology subscription for ordering-sensitive work. |
```

- [ ] **Step 9: Add note to "Connection Patterns" section (line 613-625)**

Add a new pattern:

```
HANDLER CHAIN (ordered dependent effects):
  When a consumer MUST run after another consumer's mutation:
  1. Primary consumer mutates state
  2. Primary consumer calls injected handler with typed delta
  3. Handler runs ordered effects

  This is NOT a bus concern. The bus carries facts; the handler
  carries processed deltas. The bus is for "something happened,
  react if you care." The handler is for "I changed X, here's
  exactly what changed, do Y in order."
```

- [ ] **Step 10: Update event namespace listing (line 265-289)**

Same `.repoDiscovered` update as workspace_data_architecture.md.

### `component_architecture.md` — Component Table

- [ ] **Step 11: Add `WorktreeReconciler` to component → slice map**

Add to the Infrastructure section of the component table:

```
| `WorktreeReconciler` | `Infrastructure/` | Pure function: matches existing vs discovered worktrees, preserves UUIDs, returns merged list + TopologyDelta |
```

- [ ] **Step 12: Update `PaneCoordinator` entry**

Add note that PaneCoordinator conforms to `TopologyEffectHandler` for deterministic post-topology filesystem root sync and pane orphaning.

- [ ] **Step 13: Update `WorkspaceCacheCoordinator` entry**

Add note that it uses `WorktreeReconciler` for worktree family reconciliation and invokes `TopologyEffectHandler` after topology mutations.

### `README.md` — Architecture Index

- [ ] **Step 14: Update Mutation Flow summary (line 101-120)**

Add topology accumulator flow:

```
Topology fact → EventBus → WorkspaceCacheCoordinator
  → WorktreeReconciler.reconcile() → atom.setWorktrees()
  → TopologyEffectHandler.topologyDidChange(delta)
    → PaneCoordinator: orphan panes, sync roots, prune cache
```

### CLAUDE.md

- [ ] **Step 15: Update CLAUDE.md Coordination Plane Decision Table**

Add a row for topology effects:

```
| Topology fact (repo/worktree discovered/removed) | `PaneRuntimeEventBus` | Fact fan-out only. Coordinator is the single accumulator. |
| Ordered post-topology effects (root sync, pane orphan) | `TopologyEffectHandler` | Direct handler call from coordinator. NOT via bus. |
```

- [ ] **Step 16: Commit**

```bash
git add docs/architecture/workspace_data_architecture.md
git add docs/architecture/pane_runtime_eventbus_design.md
git add docs/architecture/component_architecture.md
git add docs/architecture/README.md
git add CLAUDE.md
git commit -m "docs: topology accumulator pattern, WorktreeReconciler, TopologyEffectHandler"
```

---

## Task 6: Full Validation

- [ ] **Step 1: `mise run test`** — show pass/fail counts and exit code
- [ ] **Step 2: `mise run lint`** — zero errors
- [ ] **Step 3: Build and visually verify with Peekaboo**

```bash
AGENT_RUN_ID=$(uuidgen) mise run build
pkill -9 -f "AgentStudio" 2>/dev/null; .build/debug/AgentStudio &
PID=$(pgrep -f ".build/debug/AgentStudio")
peekaboo see --app "PID:$PID" --json
```

Verify: star for main, worktree icon for secondary, shared colors per family.

- [ ] **Step 4: Commit any fixes**
