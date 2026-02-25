# Workspace Persistence Segregation Plan (Swift 6.2 Actors + Async)

## Goal

Segregate workspace persistence into canonical state, derived cache, workspace UI state, and global preferences so:

1. stale git/forge observations never become canonical truth,
2. sidebar refresh no longer self-triggers feedback loops,
3. data flow is strictly one-way and actor-safe under Swift 6.2.

## Scope

This plan focuses on:

- repo/worktree persistence boundaries,
- sidebar metadata/status/PR source-of-truth design,
- migration to Swift 6.2 actor + async standards for source refresh and event routing.

Out of scope:

- pane management/drag/drop work,
- visual redesign details,
- non-sidebar feature behavior changes.

## Reference Architecture (Authoritative Inputs)

- `docs/architecture/pane_runtime_architecture.md` (luna-325 worktree)
- `docs/architecture/pane_runtime_eventbus_design.md` (luna-325 worktree)
- `docs/architecture/component_architecture.md` (luna-325 worktree)

This plan intentionally mirrors those patterns:

- atomic stores (`private(set)`),
- one-way mutation boundaries,
- boundary actors for expensive/external source work,
- `AsyncStream` event fan-out via EventBus.

---

## 1. Current Problems and Actual Data Flow

## 1.1 Primary Failure Modes (Current State)

1. `reloadMetadataAndStatus()` currently calls `refreshWorktrees()`, which mutates canonical `store.repos`.
2. That mutation bumps `repo.updatedAt`, which changes `reposFingerprint`.
3. `.task(id: reposFingerprint)` re-fires, creating a refresh loop and frequent task cancellation.
4. PR count merge is late in the pipeline and is frequently canceled or superseded.
5. Canonical model and derived metadata pipeline are coupled inside one flow.

Result:

- PR badges remain at `0` or stale,
- grouping/metadata updates become race-prone,
- startup/refresh behavior appears slow and inconsistent.

## 1.2 Actual Trigger Graph (As Implemented)

```text
App/Menu/Toolbar/EmptyState
  -> post(.addRepoRequested / .addFolderRequested)
  -> RepoSidebarContentView receives
  -> addRepo/addFolder
  -> WorktrunkService.discoverWorktrees(...)
  -> WorkspaceStore.updateRepoWorktrees(...)
  -> reposFingerprint changes
  -> .task(id: reposFingerprint)
  -> reloadMetadataAndStatus()
      -> refreshWorktrees()          <-- currently re-mutates store.repos
      -> metadata/status load
      -> PR count load
```

```text
reposFingerprint task
  -> reloadMetadataAndStatus()
      -> refreshWorktrees()
          -> updateRepoWorktrees()
              -> repo.updatedAt = Date()
                  -> reposFingerprint changes
                      -> task reruns
```

This is the current self-triggering loop.

## 1.3 Important Trigger/Path Notes

1. `refreshWorktreesRequested` has consumers but currently no active producer.
2. `AppCommand.refreshWorktrees` exists but is effectively no-op in active execution path.
3. Legacy `SidebarContentView` exists in file but active mounted view is `RepoSidebarContentView`.

---

## 2. Target Mental Model (Aligned to New Architecture)

## 2.1 Data Ownership Split

### Canonical (Source-of-Truth)

Owned by `WorkspaceStore`:

- repos/worktrees identity and structure,
- panes/tabs/layout/workspace structure.

Canonical must not persist derived forge/git observations as truth.

### Derived (Rebuildable Cache)

Owned by `WorkspaceCacheStore`:

- repo identity metadata (remote/org/grouping derivations),
- worktree branch status snapshots,
- PR/check/notification counts,
- generated timestamps/revision binding.

This is allowed to be stale and must be invalidatable.

### Workspace UI State

Owned by `WorkspaceUIStore`:

- expanded groups,
- checkout icon color overrides,
- sidebar filter visibility/query state (if persisted per workspace).

### Global Preferences

Owned by `PreferencesStore` and `KeybindingsStore`.

---

## 3. Swift 6.2 Actor + Async Standards (Hard Requirements)

## 3.1 Actor Roles

### `EventBus` actor

- fan-out only,
- no domain logic,
- payload is typed event envelope.

EventBus contract (initial concrete shape):

```swift
enum WorkspaceSourceEvent: Sendable {
    case filesystem(FilesystemEventPayload)
    case forge(ForgeEventPayload)
}

struct WorkspaceSourceEnvelope: Sendable {
    let source: WorkspaceSource
    let revision: UInt64
    let timestamp: Date
    let event: WorkspaceSourceEvent
}

actor WorkspaceEventBus {
    // Use bounded buffering to avoid unbounded memory growth.
    // Policy: bufferingNewest(64) per subscriber.
    func subscribe() -> AsyncStream<WorkspaceSourceEnvelope> { ... }
    func post(_ envelope: WorkspaceSourceEnvelope) { ... }
}
```

Subscription lifecycle policy:

1. Coordinator-owned long-lived subscription starts at app bootstrap.
2. Short-lived UI subscribers must resubscribe on appearance.
3. Stream termination removes subscriber continuation immediately.

Backpressure policy:

1. Buffer with `.bufferingNewest(64)` per subscriber.
2. Consumers must tolerate dropped stale intermediate events.
3. Latest-state events (status snapshots) are preferred over full historical delivery.

### `FilesystemActor` (boundary actor)

- source for filesystem/git-derived updates,
- worktree discovery scheduling and git status recompute,
- posts source events to EventBus.

### `ForgeActor` (boundary actor)

- source for PR/check/forge-derived updates,
- uses gh/API transport internally,
- posts source events to EventBus.

## 3.2 Isolation Rules

1. `@MainActor` stores and views do not do heavy source work.
2. Boundary actors perform non-UI source work and publish envelopes.
3. Store mutations remain synchronous/typed on owner actor (`private(set)` state).
4. New event plumbing uses `AsyncStream` (`NotificationCenter` can remain only as migration bridge).

## 3.3 Swift 6.2 Concurrency Rule for Heavy One-Shot Work

When work must be kicked off from a `@MainActor` context but should run on cooperative pool:

- use `@concurrent nonisolated` helpers,
- do not rely on plain `nonisolated async` for pool execution,
- avoid `Task.detached` unless there is no better structured option.

This follows the same standard used in pane runtime/eventbus architecture docs.

## 3.4 Source Error and Degraded-Mode Policy

Boundary actors must never fail silently.

1. `FilesystemActor` and `ForgeActor` emit success or failure envelopes.
2. Cache coordinator records staleness metadata when failures occur.
3. UI reads staleness state and may render degraded indicators (instead of misleading zero/default values).
4. Retry policy:
   - transient failures: exponential backoff with jitter,
   - auth/permission failures: stop retry loop until credentials/config change,
   - hard parse/schema failures: emit error envelope and keep last known good cache snapshot.

---

## 4. Concrete Design for Repo/Worktree + PR Refresh

## 4.1 One-Way Flow

```text
User intent (add repo/folder/manual refresh)
  -> Coordinator method
  -> WorkspaceStore canonical mutation (structure only)
  -> Watch registrations for FilesystemActor/ForgeActor updated

FilesystemActor / ForgeActor
  -> EventBus.post(envelope)

WorkspaceCacheCoordinator (subscriber)
  -> WorkspaceCacheStore.apply(...)

UI
  -> reads WorkspaceStore + WorkspaceCacheStore + WorkspaceUIStore
  -> no direct source CLI calls
```

## 4.2 Structural vs Derived Refresh Separation

### Structural refresh (canonical)

Allowed to mutate `WorkspaceStore`:

- add/remove repo,
- discover worktree identities,
- explicit manual rescan.

### Derived refresh (cache)

Must never mutate canonical store:

- metadata/status/PR/check updates,
- notification count and derived chips.

Critical rule:

- `reloadMetadataAndStatus`-equivalent path must not call structural worktree discovery.

## 4.3 Persistence Files

```text
workspaces/<workspace-id>.json              (canonical)
workspaces/<workspace-id>.cache.json        (derived cache)
workspaces/<workspace-id>.ui.json           (workspace UI prefs)
preferences.json                            (global)
keybindings.json                            (global)
```

Cache file carries:

- `workspaceId`,
- `sourceRevision`,
- `generatedAt`,
- cache payload maps.

`sourceRevision` definition:

1. `WorkspaceStore` owns a monotonic `UInt64 canonicalRevision`.
2. Increment revision on canonical structural mutations only (repo/worktree identity changes, add/remove, layout structure updates that affect source scope).
3. Cache snapshots are tagged with the revision they were derived from.
4. On load mismatch:
   - keep canonical load,
   - invalidate only mismatched cache scopes when possible,
   - schedule async repopulation from actors.
5. `canonicalRevision` is persisted in canonical workspace file (`WorkspacePersistor` becomes canonical-only persistor).
6. Write ordering rule: canonical write with bumped revision must commit before writing cache snapshot for that revision.

Partial invalidation policy:

1. If repo/worktree set changed for subset of repos, invalidate only affected entries.
2. Full cache discard is fallback only when scope mapping cannot be safely determined.
3. Invalidation key granularity: `repoId + worktreeId` scoped entries (repo-level metadata can invalidate by `repoId`).

## 4.4 Coordinator Ownership and Lifecycle

`WorkspaceCacheCoordinator` ownership:

1. Lives in `App/` as cross-store sequencer (`App/WorkspaceCacheCoordinator.swift`).
2. Created by `AppDelegate` alongside existing coordinators.
3. Owns EventBus subscription lifecycle.
4. Applies envelopes into `WorkspaceCacheStore` only.
5. Does not mutate canonical store except explicit structural workflows initiated by user intent.
6. `WorkspaceCacheCoordinator` is `@MainActor`; it performs the actor->MainActor hop before applying store mutations.

Relationship to `PaneCoordinator`:

1. `PaneCoordinator` remains pane/model/view sequencing owner.
2. `WorkspaceCacheCoordinator` owns workspace source-cache sequencing.
3. Coordinators may share EventBus as read consumers, but do not call each other for domain decisions.

Watch lifecycle mechanism:

1. After canonical structural mutation, coordinator computes desired watch set (`repoId`, `worktreeId`, path).
2. Coordinator calls async reconcile APIs on boundary actors:
   - `FilesystemActor.reconcileWatchSet(...)`
   - `ForgeActor.reconcileScopeSet(...)`
3. Boundary actors own internal add/remove diffing and resource lifecycle.

## 4.5 Workspace UI Persistence Trigger Policy

`WorkspaceUIStore` persistence policy:

1. Debounced save (500ms after last mutation) for frequent UI toggles.
2. Forced flush on app termination.
3. Workspace-scoped file keyed by workspace id.
4. Crash recovery accepts bounded loss within debounce window.

## 4.6 Forge Credentials and Auth Inputs

`ForgeActor` credential policy:

1. Primary credentials come from app-managed auth state (OAuth/keychain-backed store).
2. CLI fallback path (`gh`) may be used when app credentials are unavailable.
3. Auth failures emit typed failure envelopes (no silent defaults), and retries pause until credential state changes.

## 4.7 File Placement and Boundary Map

Planned location map:

1. `Core/Stores/WorkspaceCacheStore.swift`
2. `Core/Stores/WorkspaceUIStore.swift`
3. `Core/Stores/WorkspaceCachePersistor.swift`
4. `Core/Stores/WorkspaceUIPersistor.swift`
5. `App/WorkspaceCacheCoordinator.swift`
6. `Core/Events/WorkspaceEventBus.swift` (or equivalent domain-neutral event location)
7. `Features/Sidebar/FilesystemActor.swift` and `Features/Sidebar/ForgeActor.swift` initially, promote to `Core` if reused across features.
8. `Core/Stores/WorkspacePersistor.swift` remains canonical persistor and drops derived/UI concerns.

---

## 5. Migration Plan (Execution Order)

## Phase 1: Document and Guard Current Behavior

1. Capture current trigger graph and failure modes in docs (this file).
2. Add temporary diagnostics for refresh generation and PR merge stage completion.
3. Add regression tests that reproduce task-loop/late-stage cancel behavior.

## Phase 2: Introduce Segregated Persistence Types

1. Add `WorkspaceCachePersistor`.
2. Add `WorkspaceUIPersistor`.
3. Refactor existing `WorkspacePersistor` to canonical-only schema with persisted `canonicalRevision`.
4. Define canonical/cache/ui file models and migration entrypoint from legacy mixed payload.

## Phase 3: Add Stores with Atomic Boundaries

1. Add `WorkspaceCacheStore` (`@Observable`, `private(set)`).
2. Add `WorkspaceUIStore` (`@Observable`, `private(set)`).
3. Ensure views read stores only, no direct persistence in view code.

## Phase 4: Add EventBus + Boundary Source Actors

1. Add shared `EventBus` actor for source envelopes with explicit buffering and termination behavior.
2. Add `FilesystemActor` source production path.
3. Add `ForgeActor` source production path.
4. Add `WorkspaceCacheCoordinator` subscriber to apply envelopes into cache store.

## Phase 4.5: Bootstrap and Restore Wiring

1. Wire cache/UI restore ordering in app bootstrap:
   - load canonical first,
   - load UI state,
   - load cache with revision check,
   - start coordinator subscription,
   - trigger async repopulation for invalidated scopes.
2. Ensure startup path does not block first paint on forge/network calls.
3. Explicitly mark this as transitional if old sidebar read path still exists.

## Phase 5: Decouple Sidebar Refresh

1. Remove structural refresh from metadata/status refresh path.
2. Route metadata/status/PR updates through cache store only.
3. Keep structural worktree updates explicit and separate.
4. Audit every existing caller of structural refresh and classify each path as:
   - canonical structural update,
   - derived cache refresh,
   - invalid/mixed path to remove.
5. Execute Phase 4.5 + Phase 5 in one cutover PR when feasible to minimize dual-path drift window.

## Phase 6: Preferences/Keybindings and Remaining Defaults

1. Migrate workspace-scoped and global preference keys from scattered defaults.
2. Route command/keybinding overrides through dedicated stores.

## Phase 7: Verification and Closure

1. Targeted tests for migration, cache invalidation, and actor event application.
2. Full format/lint/test run.
3. Update architecture docs to reflect final ownership and data flow.

---

## 6. Test Strategy (Pyramid + Actor Safety)

## 6.1 Unit Tests

1. Persistor migration split tests (legacy mixed payload -> canonical/cache/ui).
2. `WorkspaceCacheStore` mutation tests (replace snapshot, patch PR/check counts).
3. `WorkspaceStore` canonical serialization excludes stale-derived fields.
4. `FilesystemActor` and `ForgeActor` envelope emission tests with mocked executors.

## 6.2 Integration Tests

1. EventBus fan-out to cache coordinator + reducer consumers.
2. Revision mismatch invalidates cache and triggers repopulation.
3. Sidebar load path reads canonical+cache without structural mutation loops.
4. Boundary actor failure envelopes correctly mark cache entries stale.

## 6.3 Behavioral Regression Tests

1. PR badge remains non-zero for known open PR after refresh sequence.
2. No repeated self-trigger loop from metadata refresh path.
3. Grouping does not duplicate under repeated refresh.

---

## 7. Acceptance Criteria

1. Canonical persistence remains stable and free of derived forge/git observation fields.
2. Sidebar PR/check/status chips are fed from cache store and update deterministically.
3. Structural worktree refresh is explicit; metadata refresh is cache-only.
4. Source collection is actorized (`FilesystemActor`, `ForgeActor`) with EventBus fan-out.
5. New pipeline conforms to Swift 6.2 actor + async standards, including `@concurrent nonisolated` pattern for heavy non-UI work.

---

## 8. Notes

1. Keep Swift command execution strictly sequential (`mise`/`swift test` lock rules).
2. No destructive git commands.
3. Coordinator methods sequence stores/actors; domain decisions remain in store/actor owners.
4. This plan is intentionally architecture-first and implementation-second: no code changes should bypass the ownership boundaries defined here.
