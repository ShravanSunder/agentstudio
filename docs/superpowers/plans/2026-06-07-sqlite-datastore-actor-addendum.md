# SQLite Datastore Actor Addendum Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add the missing SQLite execution boundary and recovery hardening before the next atom-split / SQLite phase proceeds.

**Architecture:** Keep atoms, observation tracking, command validation snapshots, and final hydration on `@MainActor`. Move SQLite repository ownership, GRDB pool lifecycle, local repository caching, and core/local commit sequencing behind one datastore actor. Keep normalized table work inside repositories and keep MainActor stores as snapshot/hydration owners only.

**Tech Stack:** Swift 6.2, Swift Testing, GRDB, `@MainActor @Observable` atoms, `actor` for the SQLite datastore boundary, `mise` for test/lint orchestration.

## Execution Goal And Done Contract

This addendum is execution-ready only when the implementation preserves the project's coding standards and the testing pyramid, not merely when the new actor type exists.

**Coding standards for this addendum:**

- Use explicit, role-named types at boundaries. `WorkspaceSQLiteSnapshot` is the live actor-crossing snapshot, legacy JSON payloads stay legacy DTOs, and SQLite repositories keep their row/projection records internal to persistence.
- Use discriminated enums for state-machine outcomes and recoverable failure paths. Do not encode status as unrelated booleans when the caller needs to branch on mutually exclusive outcomes.
- Do not use `@unchecked Sendable` for the new datastore boundary. If a value cannot honestly cross an actor, narrow or replace the value before it crosses.
- Do not move atoms, command validation, derived readers, or hydration logic off `@MainActor`.
- Do not let MainActor stores invoke GRDB repositories directly after the datastore route lands.
- Do not move `WorkspaceSettingsStore` JSON persistence into SQLite in this addendum. Settings scope remains intentional and file-backed here.
- Do not keep compatibility overloads that let new SQLite-enabled code bypass `WorkspaceSQLiteDatastore`.

**Testing pyramid for this addendum:**

```text
unit tests
    -> pure status decisions, import retry decisions, snapshot role/type checks,
       cursor/default synthesis rules, notification-count ownership rules

file-backed SQLite integration tests
    -> migrations, staged-vs-completed rows, core/local commit sequencing,
       corruption/quarantine behavior, per-workspace local sidecars

store and boot integration tests
    -> MainActor store async routing through WorkspaceSQLiteDatastore,
       recovery-event delivery, boot ordering, termination flush

e2e / smoke gates
    -> mise run test-e2e
    -> mise run test-zmx-e2e
```

Every implementation task must start with the relevant failing test(s), then make the smallest production change that passes them. Every task commit must leave the app compiling and the selected task tests green. The final task must run the full `mise` validation loop. If an E2E command is environment-gated, record the exact gate output; do not relabel an unrun E2E gate as passing.

Command convention: use direct `swift test --filter ...` only for focused RED/GREEN loops because the repo's `mise run test` task is intentionally full-suite and does not accept filter arguments. Use `mise run test`, `mise run lint`, `mise run test-e2e`, and `mise run test-zmx-e2e` for phase and final validation gates.

---

## What Changed In This Addendum

This addendum turns the SQLite plan from a MainActor store/repository migration into an actor-bound persistence boundary:

1. SQLite I/O moves behind `WorkspaceSQLiteDatastore`; MainActor stores capture snapshots, await actor methods, then hydrate/project committed results.
2. Core/local workspace saves use a staged commit protocol: core rows can be staged, but restore treats a workspace as authoritative only after local write succeeds and `completed_at` is marked.
3. Legacy workspace import retry control moves into typed datastore outcomes so stale JSON cannot replay after a completed snapshot, while missing status rows remain retryable only for failed first-boot materialization lanes that had no active SQLite selection before restore repair.
4. Local sidecar quarantine/recovery events are returned through datastore load results, including the first restore opener, so user-visible recovery notifications are not silently lost behind the actor cache.
5. Notification unread counts become inbox-owned; repo cache remains enrichment/recent-target state and no longer persists notification counts.
6. `WorkspaceSQLiteSnapshot` becomes the live actor-crossing snapshot type; legacy `PersistableState` remains a legacy JSON DTO and is not the SQLite bridge contract.
7. The test plan is pyramid-shaped: pure decisions first, file-backed SQLite integration next, store/boot integration after actor routing, then full `mise` and E2E gates.

---

## Why This Addendum Exists

The adversarial review found six implementation issues that should be fixed before the next SQLite phase:

1. **SQLite work is currently MainActor-bound.** `WorkspaceStore`, `RepoCacheStore`, `UIStateStore`, and `WorkspaceSQLiteStoreBackend` invoke synchronous GRDB reads/writes on the UI executor. Debounce only delays the work; it does not move the work off MainActor.
2. **Normal core/local snapshot completion is not a real commit protocol.** `WorkspaceSQLiteStoreBackend.save(_:)` commits and marks core complete before local save. If local save fails, restore accepts the newer core graph and synthesizes local cursor/window defaults.
3. **Legacy import can replay stale JSON after post-commit bookkeeping failure.** `saveImportedLegacySnapshot` writes core/local first and then records `legacy_workspace_import_status`. If that status update fails and a failed status row remains, retry logic can treat the already-completed legacy file as pending.
4. **Incomplete legacy import can become unretriable or over-retriable.** Missing status rows need lane-aware handling: failed first-boot materialization with no active SQLite selection can retry, but already-selected partial SQLite rows must reset/report instead of replaying stale legacy JSON over newer SQLite state.
5. **Notification counts have contradictory owners.** Docs say unread counts moved to `InboxNotificationAtom`, but `RepoCacheAtom.notificationCountByWorktreeId` is still persisted and drives status-chip UI.
6. **Persistence role vocabulary is still leaking through `PersistableState`.** `WorkspacePersistor.PersistableState` is documented as legacy JSON payload shape, but the live SQLite bridge still uses it as its save/load snapshot shape.

The test/doc gap is the enforcement problem for all six issues. This plan adds focused tests at the unit/integration layers before or alongside implementation, then requires the full `mise` loop and E2E gates.

## Boundary Decision

```text
@MainActor atoms/stores
  capture immutable snapshots
  await datastore actor
  hydrate/project committed results

WorkspaceSQLiteDatastore actor
  owns WorkspaceCoreRepository
  owns cached WorkspaceLocalRepository instances
  owns core/local save sequencing
  owns legacy import status decisions
  owns quarantine-aware local repository reopening

Repositories
  own GRDB SQL and normalized row replacement
  do not own atoms or UI read models
```

Do not create one actor per store. Do not put SQLite calls directly in atoms. Do not split atoms to match SQLite tables.

## File Structure

Create:

- `Sources/AgentStudio/Core/State/SQLite/WorkspaceSQLiteDatastore.swift`  
  Actor that owns the SQLite backend, repository cache, local repository open/quarantine state, and async load/save/import methods.
- `Sources/AgentStudio/Core/State/SQLite/WorkspaceSQLiteSnapshot.swift`  
  Immutable live SQLite snapshot shape used across the MainActor/datastore boundary.
- `Sources/AgentStudio/Core/State/SQLite/WorkspaceSQLiteDatastoreFactory.swift`  
  Product-specific datastore bootstrap. Replaces the MainActor-only backend factory as the AppDelegate entry point.
- `Tests/AgentStudioTests/Core/Stores/WorkspaceSQLiteDatastoreActorTests.swift`  
  Actor-boundary, local repository cache, and off-main execution tests.
- `Tests/AgentStudioTests/Core/Stores/WorkspaceSQLiteLegacyImportStatusTests.swift`  
  Legacy retry status and stale replay regression tests.
- `Tests/AgentStudioTests/Core/Stores/WorkspaceSQLiteCommitProtocolTests.swift`  
  Normal core/local snapshot commit protocol tests.
- `Tests/AgentStudioTests/App/WorkspaceNotificationCountOwnershipTests.swift`  
  Inbox-owned unread-count projection tests.

Modify:

- `Sources/AgentStudio/Core/State/MainActor/Persistence/WorkspaceStore.swift`
- `Sources/AgentStudio/Core/State/MainActor/Persistence/WorkspaceStore+LegacySQLiteImport.swift`
- `Sources/AgentStudio/Core/State/MainActor/Persistence/WorkspaceCoreRepository.swift`
- `Sources/AgentStudio/Core/State/MainActor/Persistence/WorkspaceSQLiteStoreBackend.swift`
- `Sources/AgentStudio/Core/State/MainActor/Persistence/WorkspaceSQLiteStoreBackendFactory.swift`
- `Sources/AgentStudio/Core/State/MainActor/Persistence/WorkspaceLocalRepository.swift`
- `Sources/AgentStudio/Core/State/MainActor/Persistence/WorkspaceLocalRepository+Storage.swift`
- `Sources/AgentStudio/Core/State/MainActor/Persistence/WorkspaceLocalMigrations.swift`
- `Sources/AgentStudio/Core/State/MainActor/Persistence/WorkspacePersistenceTransformer.swift`
- `Sources/AgentStudio/Core/State/MainActor/Persistence/WorkspacePersistor+Payloads.swift`
- `Sources/AgentStudio/Core/State/MainActor/Persistence/RepoCacheStore.swift`
- `Sources/AgentStudio/Core/State/MainActor/Persistence/UIStateStore.swift`
- `Sources/AgentStudio/Core/State/MainActor/Persistence/SidebarCacheStore.swift`
- `Sources/AgentStudio/Features/InboxNotification/State/MainActor/Persistence/InboxNotificationStore.swift`
- `Sources/AgentStudio/App/Boot/AppDelegate.swift`
- `Sources/AgentStudio/App/Boot/AppDelegate+WorkspaceBoot.swift`
- `Sources/AgentStudio/App/Boot/AppDelegate+InboxNotificationBoot.swift`
- `Sources/AgentStudio/App/Boot/AppDelegate+Termination.swift`
- `Sources/AgentStudio/App/Boot/WorkspaceBootSequence.swift`
- `Sources/AgentStudio/Core/State/MainActor/Atoms/RepoCacheAtom.swift`
- `Sources/AgentStudio/Core/Views/Panes/PaneManagementContext.swift`
- `Sources/AgentStudio/App/Panes/WorkspaceLauncherProjector.swift`
- `Tests/AgentStudioTests/Core/Stores/WorkspaceSQLiteStoreRecoveryTests.swift`
- `Tests/AgentStudioTests/App/AppBootSequenceTests.swift`
- `AGENTS.md`
- `docs/architecture/atom_persistence_boundaries.md`
- `docs/architecture/component_architecture.md`
- `docs/architecture/workspace_data_architecture.md`
- `docs/architecture/README.md`
- `docs/superpowers/specs/sqlite/05-write-paths-and-actors.md`
- `docs/superpowers/specs/sqlite/06-test-checkpoints.md`

---

### Task 1: Add The Datastore Boundary Spec And Owner Matrix Updates

**Files:**
- Modify: `AGENTS.md`
- Modify: `docs/architecture/atom_persistence_boundaries.md`
- Modify: `docs/architecture/component_architecture.md`
- Modify: `docs/architecture/workspace_data_architecture.md`
- Modify: `docs/architecture/README.md`
- Modify: `docs/superpowers/specs/sqlite/05-write-paths-and-actors.md`
- Modify: `docs/superpowers/specs/sqlite/06-test-checkpoints.md`

- [ ] **Step 1: Add the datastore actor rule to `docs/superpowers/specs/sqlite/05-write-paths-and-actors.md`**

Insert after the "Core Write Serialization" section:

```markdown
## SQLite Datastore Actor Boundary

Step 1 uses a single product datastore actor for SQLite I/O:

```text
@MainActor store/coordinator
  -> captures immutable snapshot or validated mutation input
  -> awaits WorkspaceSQLiteDatastore
  -> hydrates/projects the committed result on MainActor

WorkspaceSQLiteDatastore actor
  -> owns WorkspaceCoreRepository
  -> owns cached WorkspaceLocalRepository instances
  -> serializes core/local snapshot commits
  -> owns legacy import status decisions
  -> owns local quarantine/reopen state
```

The datastore actor does not own atoms, UI state, command validation, or derived readers. MainActor stores do not directly invoke GRDB writes once this boundary lands.

Recovery-event assumption:

```text
the first restore opener owns recovery evidence
    -> local sidecar quarantine/recovery can happen during workspace restore
    -> later cache/UI/sidebar/inbox lanes may only hit the actor cache
    -> therefore the datastore buffers recovery events per workspace
    -> every public restore/load result drains and returns pending events
    -> MainActor callers record them through recordPersistenceRecovery(_:)
```

This does not change the first-window readiness contract. Recovery notifications can be recorded before the inbox store exists because AppDelegate already queues pre-inbox recovery events and flushes them after inbox boot.
```

- [ ] **Step 2: Add the six-issue addendum checklist to `docs/superpowers/specs/sqlite/06-test-checkpoints.md`**

Append under "Step 0 Atomicity Matrix Tests":

```markdown
## Datastore Addendum Tests

- `WorkspaceSQLiteDatastoreActorTests.workspaceSaveRunsThroughDatastoreActor`
  verifies SQLite save work enters the datastore actor boundary instead of calling repositories directly from MainActor stores.
- `WorkspaceSQLiteCommitProtocolTests.stagedOnlyRowDoesNotCountAsCompleted`
  verifies a staged core snapshot is not authoritative until core completion is marked after local write.
- `WorkspaceSQLiteCommitProtocolTests.activeSelectionRepairIgnoresStagedOnlyRows`
  verifies active-workspace repair and fallback selection require `completed_at IS NOT NULL`.
- `WorkspaceSQLiteLegacyImportStatusTests.postCommitStatusFailureDoesNotReplayStaleLegacyJSON`
  verifies legacy import status bookkeeping failure does not make an already-completed snapshot pending again.
- `WorkspaceSQLiteLegacyImportStatusTests.missingStatusForIncompleteRowsRetriesLegacyFile`
  verifies incomplete first-boot import rows without a status row still retry the legacy file when no active SQLite selection existed before restore repair.
- `WorkspaceSQLiteStoreBridgeTests.restoreDoesNotTreatIncompleteSQLiteWorkspaceRowsAsAuthoritative`
  verifies already-selected partial SQLite rows reset/report instead of replaying stale legacy JSON after active-selection repair clears the incomplete selection.
- `WorkspaceSQLiteLocalRecoveryTests.failedLocalQuarantineDoesNotImmediatelyReopenBadSidecar`
  verifies failed local quarantine is not collapsed into recovered local state.
- `WorkspaceSQLiteDatastoreActorTests.workspaceLoadReturnsFirstLocalRestoreRecoveryEvents`
  verifies recovery events produced by the first workspace restore opener are returned to the MainActor caller instead of being lost behind the actor cache.
- `WorkspaceSQLiteDatastoreActorTests.inboxBootDrainsRecoveryEventsIfItIsFirstRestoreOpener`
  verifies inbox boot returns local quarantine/recovery events when inbox is the first lane to open the local sidecar.
- `WorkspaceSQLiteDatastoreActorTests.cacheRestoreDoesNotLoseRecoveryEventsAlreadyQueuedByWorkspaceLoad`
  verifies later cache/UI/sidebar restore calls cannot silently drop events that workspace load already queued at the datastore actor.
- `WorkspaceNotificationCountOwnershipTests.worktreeStatusChipsReadInboxProjection`
  verifies notification chips read inbox-owned unread counts, not repo-cache-restored stale counts.
- `WorkspaceSQLiteSnapshotRoleTests.liveSQLiteSnapshotIsNotLegacyPersistableState`
  verifies SQLite save/load APIs use a live SQLite snapshot type distinct from legacy JSON payload DTOs.
```

- [ ] **Step 3: Update the component table in `AGENTS.md`**

Add these rows near the SQLite persistence rows:

```markdown
| `WorkspaceSQLiteDatastore` | actor boundary for product SQLite I/O, repository caching, core/local commit sequencing, local quarantine state, and legacy import status decisions; does not own atoms | `Core/State/SQLite/WorkspaceSQLiteDatastore.swift` |
| `WorkspaceSQLiteSnapshot` | immutable live SQLite bridge snapshot passed across the MainActor/datastore boundary; not a legacy JSON DTO and not a row projection | `Core/State/SQLite/WorkspaceSQLiteSnapshot.swift` |
```

Update existing rows:

```markdown
| `RepoEnrichmentCacheAtom` | rebuildable repo/worktree enrichment, PR counts, and rebuild metadata; notification unread counts are inbox-owned | `Core/State/MainActor/Atoms/RepoCacheAtom.swift` |
| `RepoCacheAtom` | UI-facing compatibility read surface over repo enrichment + recent targets; does not own notification unread counts | `Core/State/MainActor/Atoms/RepoCacheAtom.swift` |
| `UIStateStore` | persistence wrapper for workspace sidebar shell memory only | `Core/State/MainActor/Persistence/UIStateStore.swift` |
| `WorkspaceSettingsStore` | persistence wrapper for editor bookmark, checkout colors, and inbox notification preferences until feature-specific settings stores split | `Core/State/MainActor/Persistence/WorkspaceSettingsStore.swift` |
```

Scope note: `WorkspaceSettingsStore` remains file-backed settings persistence in this addendum. It is not moved to SQLite here. The datastore owns SQLite status bookkeeping related to legacy companion import/archive readiness, including settings companion completion status, but not the settings JSON file I/O itself.

- [ ] **Step 4: Run documentation grep checks**

Run:

```bash
rg -n "WorkspaceFocusDerived|notification counts|notificationCountByWorktreeId|UIStateStore.*editor chooser|PersistableState.*SQLite|WorkspaceSQLiteDatastore" AGENTS.md docs/architecture docs/superpowers/specs/sqlite
```

Expected:

```text
Only intentional historical references remain. New docs mention WorkspaceSQLiteDatastore and no owner table says UIStateStore owns editor chooser bookmark.
```

- [ ] **Step 5: Commit**

```bash
git add AGENTS.md docs/architecture docs/superpowers/specs/sqlite
git commit -m "docs: add sqlite datastore actor addendum"
```

---

### Task 2: Split Live SQLite Snapshot From Legacy JSON Payload

**Files:**
- Create: `Sources/AgentStudio/Core/State/SQLite/WorkspaceSQLiteSnapshot.swift`
- Modify: `Sources/AgentStudio/Core/State/MainActor/Persistence/WorkspacePersistenceTransformer.swift`
- Modify: `Sources/AgentStudio/Core/State/MainActor/Persistence/WorkspaceSQLiteStoreBackend.swift`
- Modify: `Sources/AgentStudio/Core/State/MainActor/Persistence/WorkspaceStore+LegacySQLiteImport.swift`
- Modify: `Sources/AgentStudio/Core/Models/Pane.swift`
- Modify: `Sources/AgentStudio/Core/Models/Drawer.swift`
- Modify: `Sources/AgentStudio/Core/Models/Tab.swift`
- Modify: `Sources/AgentStudio/Core/Models/PaneContent.swift`
- Modify: `Sources/AgentStudio/Core/Models/PaneArrangement.swift`
- Modify: `Sources/AgentStudio/Core/Models/Layout.swift`
- Modify: `Sources/AgentStudio/Core/Models/DrawerGridLayout.swift`
- Modify: `Sources/AgentStudio/Core/Models/DrawerRearrangeTarget.swift`
- Modify: `Sources/AgentStudio/Core/Models/DynamicView.swift`
- Modify: `Sources/AgentStudio/Core/Models/TerminalSource.swift`
- Modify: `Sources/AgentStudio/Core/Models/SessionResidency.swift`
- Modify: `Sources/AgentStudio/Core/Models/Repo.swift`
- Modify: `Sources/AgentStudio/Core/Models/Worktree.swift`
- Modify: `Sources/AgentStudio/Core/Models/WatchedPath.swift`
- Modify: `Sources/AgentStudio/Core/RuntimeEventSystem/Contracts/PaneMetadata.swift`
- Modify: `Sources/AgentStudio/Core/RuntimeEventSystem/Contracts/PaneContextFacets.swift`
- Modify: `Sources/AgentStudio/Features/Bridge/State/BridgeDomainState.swift`
- Test: `Tests/AgentStudioTests/Core/Stores/WorkspaceSQLiteSnapshotRoleTests.swift`

- [x] **Step 1: Write the failing role test**

Create `Tests/AgentStudioTests/Core/Stores/WorkspaceSQLiteSnapshotRoleTests.swift`:

```swift
import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite("WorkspaceSQLiteSnapshotRoleTests")
struct WorkspaceSQLiteSnapshotRoleTests {
    @Test("live SQLite snapshot is not the legacy JSON persistable state type")
    func liveSQLiteSnapshotIsNotLegacyPersistableState() {
        let workspaceId = UUID()
        let snapshot = WorkspaceSQLiteSnapshot(
            id: workspaceId,
            name: "SQLite Snapshot",
            repos: [],
            worktrees: [],
            unavailableRepoIds: [],
            panes: [],
            tabs: [],
            activeTabId: nil,
            sidebarWidth: 250,
            windowFrame: nil,
            watchedPaths: [],
            createdAt: Date(timeIntervalSince1970: 1),
            updatedAt: Date(timeIntervalSince1970: 2)
        )

        #expect(snapshot.id == workspaceId)
        #expect(String(describing: type(of: snapshot)) == "WorkspaceSQLiteSnapshot")
        #expect(String(describing: WorkspacePersistor.PersistableState.self) != String(describing: type(of: snapshot)))
    }
}
```

- [x] **Step 2: Run the failing test**

Run:

```bash
swift test --filter WorkspaceSQLiteSnapshotRoleTests
```

Expected:

```text
FAIL: cannot find 'WorkspaceSQLiteSnapshot' in scope
```

- [x] **Step 3: Make the actor-crossing live snapshot values sendable**

`WorkspaceSQLiteSnapshot` crosses from the `@MainActor` store into `WorkspaceSQLiteDatastore`. That boundary must not rely on `@unchecked Sendable` or on non-sendable domain values.

Audit and add explicit `Sendable` conformance to the value-only domain structs that the snapshot carries, starting with:

```text
Pane
PaneKind
PaneContent
UnsupportedContent
AnyCodableValue
SessionProvider
TerminalState
WebviewState
CodeViewerState
BridgeDomainState
PaneMetadata
PaneContextFacets
SessionResidency
WorktreeUnavailableReason
TerminalSource
Drawer
Tab
PaneArrangement
DrawerView
Layout
DrawerGridLayout
DynamicViewType
DrawerRearrangeTarget
Repo
Worktree
WatchedPath
WorkspaceLocalRepository.CacheStateRecord
WorkspacePersistor.PersistableUIState
WorkspacePersistor.PersistableSidebarCache
WorkspaceCoreRepository.LegacyImportStatusRecord
```

If a nested value cannot honestly conform to `Sendable`, do not force it. Replace that snapshot field with a purpose-specific sendable persisted value before it crosses the actor boundary. The live SQLite snapshot is still not a legacy JSON DTO and still not a SQLite row projection; it is the immutable actor-crossing persistence snapshot.

- [x] **Step 4: Add the live SQLite snapshot type**

Create `Sources/AgentStudio/Core/State/SQLite/WorkspaceSQLiteSnapshot.swift`:

```swift
import CoreGraphics
import Foundation

struct WorkspaceSQLiteSnapshot: Equatable, Sendable {
    var id: UUID
    var name: String
    var repos: [CanonicalRepo]
    var worktrees: [CanonicalWorktree]
    var unavailableRepoIds: Set<UUID>
    var panes: [Pane]
    var tabs: [Tab]
    var activeTabId: UUID?
    var sidebarWidth: CGFloat
    var windowFrame: CGRect?
    var watchedPaths: [WatchedPath]
    var createdAt: Date
    var updatedAt: Date
}
```

Use `CanonicalRepo` and `CanonicalWorktree` here intentionally. The live
repository atom hydrates rich `Repo`/`Worktree` values, but the SQLite bridge
persists durable topology identity, not enrichment-bearing runtime repo values.

- [x] **Step 5: Add a shared test fixture helper**

Create a test-support extension near the SQLite store tests, not in production code:

```swift
extension WorkspaceSQLiteSnapshot {
    static func emptyFixture(
        id: UUID = UUID(),
        name: String = "Workspace",
        createdAt: Date = Date(timeIntervalSince1970: 1),
        updatedAt: Date = Date(timeIntervalSince1970: 2)
    ) -> Self {
        Self(
            id: id,
            name: name,
            repos: [],
            worktrees: [],
            unavailableRepoIds: [],
            panes: [],
            tabs: [],
            activeTabId: nil,
            sidebarWidth: 250,
            windowFrame: nil,
            watchedPaths: [],
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}
```

- [x] **Step 6: Add transformer methods for the new snapshot**

Modify `WorkspacePersistenceTransformer.swift` by adding sibling methods to the existing `makeLiveSQLiteState` path:

```swift
@MainActor
static func makeLiveSQLiteSnapshot(
    identityAtom: WorkspaceIdentityAtom,
    windowMemoryAtom: WorkspaceWindowMemoryAtom,
    repositoryTopologyAtom: WorkspaceRepositoryTopologyAtom,
    workspacePaneAtom: WorkspacePaneAtom,
    workspaceTabLayoutAtom: WorkspaceTabLayoutAtom,
    persistedAt: Date
) -> WorkspaceSQLiteSnapshot {
    let state = makeLiveSQLiteState(
        identityAtom: identityAtom,
        windowMemoryAtom: windowMemoryAtom,
        repositoryTopologyAtom: repositoryTopologyAtom,
        workspacePaneAtom: workspacePaneAtom,
        workspaceTabLayoutAtom: workspaceTabLayoutAtom,
        persistedAt: persistedAt
    )
    return WorkspaceSQLiteSnapshot(
        id: state.id,
        name: state.name,
        repos: state.repos,
        worktrees: state.worktrees,
        unavailableRepoIds: state.unavailableRepoIds,
        panes: state.panes,
        tabs: state.tabs,
        activeTabId: state.activeTabId,
        sidebarWidth: state.sidebarWidth,
        windowFrame: state.windowFrame,
        watchedPaths: state.watchedPaths,
        createdAt: state.createdAt,
        updatedAt: state.updatedAt
    )
}

static func persistableState(from snapshot: WorkspaceSQLiteSnapshot) -> WorkspacePersistor.PersistableState {
    .init(
        id: snapshot.id,
        name: snapshot.name,
        repos: snapshot.repos,
        worktrees: snapshot.worktrees,
        unavailableRepoIds: snapshot.unavailableRepoIds,
        panes: snapshot.panes,
        tabs: snapshot.tabs,
        activeTabId: snapshot.activeTabId,
        sidebarWidth: snapshot.sidebarWidth,
        windowFrame: snapshot.windowFrame,
        watchedPaths: snapshot.watchedPaths,
        createdAt: snapshot.createdAt,
        updatedAt: snapshot.updatedAt
    )
}
```

- [x] **Step 7: Change SQLite backend APIs to accept/return `WorkspaceSQLiteSnapshot`**

Modify `WorkspaceSQLiteStoreBackend.swift` signatures first:

```swift
func load(preferredWorkspaceId: UUID) throws -> WorkspaceSQLiteSnapshot?
func save(_ snapshot: WorkspaceSQLiteSnapshot) throws
func saveImportedLegacySnapshot(
    _ snapshot: WorkspaceSQLiteSnapshot,
    sourceStatePath: String
) throws
```

These signatures are temporary until Task 4 rewrites both normal save and legacy-import save through the same staged core/local commit helper. Task 2 only moves the public backend contract onto the role-named snapshot type; repository opening remains inside the backend until the staged protocol lands. Do not add a second, divergent save implementation.

Inside each method, convert only at the repository bridge boundary:

```swift
let state = WorkspacePersistenceTransformer.persistableState(from: snapshot)
```

For load, convert the existing state result:

```swift
let state = try WorkspaceSQLiteStateBridge.persistableState(from: snapshotRecord)
return WorkspaceSQLiteSnapshot(
    id: state.id,
    name: state.name,
        repos: state.repos,
        worktrees: state.worktrees,
        unavailableRepoIds: state.unavailableRepoIds,
        panes: state.panes,
        tabs: state.tabs,
        activeTabId: state.activeTabId,
        sidebarWidth: state.sidebarWidth,
        windowFrame: state.windowFrame,
        watchedPaths: state.watchedPaths,
        createdAt: state.createdAt,
        updatedAt: state.updatedAt
)
```

- [x] **Step 8: Update `WorkspaceStore` hydration call sites**

Where `WorkspaceStore` receives a SQLite snapshot, hydrate through:

```swift
hydrateWorkspaceState(WorkspacePersistenceTransformer.persistableState(from: snapshot))
```

- [x] **Step 9: Run role and bridge tests**

Run:

```bash
swift test --filter WorkspaceSQLiteSnapshotRoleTests
swift test --filter WorkspaceSQLiteStoreBridgeTests
swift test --filter WorkspaceSQLiteStoreRecoveryTests
```

Expected:

```text
All selected tests pass.
```

- [x] **Step 10: Commit**

```bash
git add Sources/AgentStudio/Core/State/SQLite/WorkspaceSQLiteSnapshot.swift \
        Sources/AgentStudio/Core/State/MainActor/Persistence/WorkspacePersistenceTransformer.swift \
        Sources/AgentStudio/Core/State/MainActor/Persistence/WorkspaceSQLiteStoreBackend.swift \
        Sources/AgentStudio/Core/State/MainActor/Persistence/WorkspaceStore+LegacySQLiteImport.swift \
        Sources/AgentStudio/Core/Models/Pane.swift \
        Sources/AgentStudio/Core/Models/Drawer.swift \
        Sources/AgentStudio/Core/Models/Tab.swift \
        Sources/AgentStudio/Core/Models/PaneContent.swift \
        Sources/AgentStudio/Core/Models/PaneArrangement.swift \
        Sources/AgentStudio/Core/Models/Layout.swift \
        Sources/AgentStudio/Core/Models/DrawerGridLayout.swift \
        Sources/AgentStudio/Core/Models/DrawerRearrangeTarget.swift \
        Sources/AgentStudio/Core/Models/DynamicView.swift \
        Sources/AgentStudio/Core/Models/TerminalSource.swift \
        Sources/AgentStudio/Core/Models/SessionResidency.swift \
        Sources/AgentStudio/Core/Models/Repo.swift \
        Sources/AgentStudio/Core/Models/Worktree.swift \
        Sources/AgentStudio/Core/Models/WatchedPath.swift \
        Sources/AgentStudio/Core/RuntimeEventSystem/Contracts/PaneMetadata.swift \
        Sources/AgentStudio/Core/RuntimeEventSystem/Contracts/PaneContextFacets.swift \
        Sources/AgentStudio/Features/Bridge/State/BridgeDomainState.swift \
        Tests/AgentStudioTests/Core/Stores/WorkspaceSQLiteSnapshotRoleTests.swift
git commit -m "refactor: separate sqlite snapshot from legacy payload"
```

---

### Task 3: Fix Legacy Import Retry Status Semantics

**Files:**
- Modify: `Sources/AgentStudio/Core/State/MainActor/Persistence/WorkspaceStore+LegacySQLiteImport.swift`
- Modify: `Sources/AgentStudio/Core/State/MainActor/Persistence/WorkspaceSQLiteStoreBackend.swift`
- Test: `Tests/AgentStudioTests/Core/Stores/WorkspaceSQLiteLegacyImportStatusTests.swift`

- [x] **Step 1: Write stale replay regression test**

Create `Tests/AgentStudioTests/Core/Stores/WorkspaceSQLiteLegacyImportStatusTests.swift`:

```swift
import Foundation
import GRDB
import Testing

@testable import AgentStudio

@MainActor
@Suite("WorkspaceSQLiteLegacyImportStatusTests", .serialized)
struct WorkspaceSQLiteLegacyImportStatusTests {
    @Test("post-commit import-status failure does not replay stale legacy JSON")
    func postCommitStatusFailureDoesNotReplayStaleLegacyJSON() throws {
        let workspaceId = UUID(uuidString: "00000000-0000-0000-0000-00000000AA01")!
        let fixture = try makeLegacyStatusFixture()
        let persistor = makeLegacyStatusPersistor()
        try saveLegacyWorkspace(
            workspaceId,
            name: "Legacy Name",
            updatedAt: Date(timeIntervalSince1970: 1_700_003_000),
            persistor: persistor
        )
        try fixture.coreQueue.write { database in
            try database.execute(
                sql: """
                    CREATE TRIGGER fail_success_status
                    BEFORE INSERT ON legacy_workspace_import_status
                    WHEN NEW.last_error IS NULL
                    BEGIN
                        SELECT RAISE(ABORT, 'injected status success failure');
                    END
                    """
            )
        }
        let firstBoot = WorkspaceStore(persistor: persistor, sqliteBackend: fixture.backend)
        firstBoot.restore()
        try fixture.coreQueue.write { database in
            try database.execute(sql: "DROP TRIGGER fail_success_status")
        }
        try fixture.backend.save(
            WorkspaceSQLiteSnapshot(
                id: workspaceId,
                name: "SQLite Newer Name",
                createdAt: Date(timeIntervalSince1970: 1_700_003_000),
                updatedAt: Date(timeIntervalSince1970: 1_700_003_500)
            )
        )

        let secondBoot = WorkspaceStore(persistor: persistor, sqliteBackend: fixture.backend)
        secondBoot.restore()

        #expect(secondBoot.identityAtom.workspaceName == "SQLite Newer Name")
        #expect(secondBoot.identityAtom.workspaceName != "Legacy Name")
        #expect(try fixture.coreRepository.fetchWorkspace(id: workspaceId)?.name == "SQLite Newer Name")
    }

    @Test("missing status for incomplete rows retries legacy file")
    func missingStatusForIncompleteRowsRetriesLegacyFile() throws {
        let workspaceId = UUID(uuidString: "00000000-0000-0000-0000-00000000AA02")!
        let fixture = try makeLegacyStatusFixture(failingLocalWorkspaceId: workspaceId)
        let persistor = makeLegacyStatusPersistor()
        try saveLegacyWorkspace(
            workspaceId,
            name: "Retryable Legacy",
            updatedAt: Date(timeIntervalSince1970: 1_700_003_600),
            persistor: persistor
        )
        let failedBoot = WorkspaceStore(persistor: persistor, sqliteBackend: fixture.backend)
        failedBoot.restore()
        try fixture.coreQueue.write { database in
            try database.execute(
                sql: "DELETE FROM legacy_workspace_import_status WHERE workspace_id = ?",
                arguments: [workspaceId.uuidString]
            )
        }

        let retryFixture = try makeLegacyStatusFixture(coreQueue: fixture.coreQueue)
        let retryBoot = WorkspaceStore(persistor: persistor, sqliteBackend: retryFixture.backend)
        retryBoot.restore()

        #expect(retryBoot.identityAtom.workspaceId == workspaceId)
        #expect(retryBoot.identityAtom.workspaceName == "Retryable Legacy")
        #expect(try retryFixture.coreRepository.hasCompletedWorkspaceSQLiteSnapshot(workspaceId: workspaceId))
    }
}
```

Add helper functions in the same file:

```swift
private struct LegacyStatusFixture {
    let coreQueue: DatabaseQueue
    let localQueue: DatabaseQueue
    let coreRepository: WorkspaceCoreRepository
    let backend: WorkspaceSQLiteStoreBackend
}

@MainActor
private func makeLegacyStatusFixture(
    coreQueue existingCoreQueue: DatabaseQueue? = nil,
    failingLocalWorkspaceId: UUID? = nil
) throws -> LegacyStatusFixture {
    let coreQueue = try existingCoreQueue ?? SQLiteDatabaseFactory.makeInMemoryQueue(label: "AgentStudio.sqlite.legacy.status.core")
    let localQueue = try SQLiteDatabaseFactory.makeInMemoryQueue(label: "AgentStudio.sqlite.legacy.status.local")
    if existingCoreQueue == nil {
        try WorkspaceCoreMigrations.migrate(coreQueue)
    }
    try WorkspaceLocalMigrations.migrate(localQueue)
    let coreRepository = WorkspaceCoreRepository(databaseWriter: coreQueue)
    let backend = WorkspaceSQLiteStoreBackend(
        coreRepository: coreRepository,
        makeLocalRepository: { workspaceId in
            if workspaceId == failingLocalWorkspaceId {
                throw CocoaError(.fileNoSuchFile)
            }
            return WorkspaceLocalRepository(workspaceId: workspaceId, databaseWriter: localQueue)
        }
    )
    return .init(coreQueue: coreQueue, localQueue: localQueue, coreRepository: coreRepository, backend: backend)
}

private func makeLegacyStatusPersistor() -> WorkspacePersistor {
    let workspaceDirectory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    let persistor = WorkspacePersistor(workspacesDir: workspaceDirectory)
    #expect(persistor.ensureDirectory())
    return persistor
}

private func saveLegacyWorkspace(
    _ workspaceId: UUID,
    name: String,
    updatedAt: Date,
    persistor: WorkspacePersistor
) throws {
    try persistor.save(
        .init(
            id: workspaceId,
            name: name,
            createdAt: Date(timeIntervalSince1970: 1_700_003_000),
            updatedAt: updatedAt
        )
    )
}
```

- [x] **Step 2: Run the failing tests**

Run:

```bash
swift test --filter WorkspaceSQLiteLegacyImportStatusTests
```

Expected:

```text
At least one test fails because pending legacy file classification is status-only.
```

- [x] **Step 3: Change pending classification to include snapshot completeness**

Modify `WorkspaceStore+LegacySQLiteImport.swift`:

```swift
enum LegacyWorkspaceFileImportClassification: Equatable {
    case pending
    case alreadyCompleted
    case skippedByStatus
    case unavailable(String)

    var shouldImport: Bool {
        if case .pending = self { return true }
        return false
    }
}

private func classifyLegacyFileForImport(
    _ legacyFile: LegacyFile,
    mode: WorkspaceLegacySQLiteImportMode
) -> LegacyWorkspaceFileImportClassification {
    do {
        if try sqliteBackend.hasCompletedSnapshot(workspaceId: legacyFile.state.id) {
            return .alreadyCompleted
        }
        guard
            let status = try sqliteBackend.coreRepository.fetchLegacyWorkspaceImportStatus(
                workspaceId: legacyFile.state.id
            )
        else {
            return try missingStatusClassification(for: mode)
        }
        return status.coreImportedAt == nil || status.lastError != nil ? .pending : .skippedByStatus
    } catch {
        workspaceLegacySQLiteImportLogger.error(
            "Skipping legacy workspace retry because import status lookup failed: \(error.localizedDescription)"
        )
        return .unavailable(String(describing: error))
    }
}

private func missingStatusClassification(
    for mode: WorkspaceLegacySQLiteImportMode
) throws -> LegacyWorkspaceFileImportClassification {
    switch mode {
    case .initialInPlaceBootImport:
        return .pending
    case .resumeUnfinishedImportKeepingCurrentSelection:
        return .skippedByStatus
    case .resumeIncompleteInitialImport(let hadActiveSelectionBeforeRestore):
        return hadActiveSelectionBeforeRestore ? .skippedByStatus : .pending
    }
}
```

Update the caller and pass the pre-repair active-selection fact from `WorkspaceStore.restore()`:

```swift
let pendingFiles = scan.loadedFiles.filter { legacyFile in
    classifyLegacyFileForImport(legacyFile, mode: mode).shouldImport
}

let hadActiveSelectionBeforeSQLiteRestore = sqliteBackendHasActiveWorkspaceSelection(sqliteBackend)
...
resumeUnfinishedLegacySQLiteImportAfterIncompleteSQLiteRestore(
    sqliteBackend,
    hadActiveSelectionBeforeRestore: hadActiveSelectionBeforeSQLiteRestore
)
```

This remains synchronous in Task 3 because the datastore actor does not exist yet. Task 7 rewrites this classifier to await `WorkspaceSQLiteDatastore.hasCompletedSnapshot(...)` and `WorkspaceSQLiteDatastore.legacyImportStatus(...)` in an explicit async loop.

- [x] **Step 4: Keep successful snapshot status distinct from failed bookkeeping**

Modify `WorkspaceSQLiteStoreBackend.saveImportedLegacySnapshot(_:sourceStatePath:)` so legacy status bookkeeping is downstream of the committed SQLite snapshot:

```text
write core/local workspace snapshot through the current backend save path
then mark legacy_workspace_import_status.core_imported_at
```

The legacy import status write happens after the snapshot is fully committed. A failure in `markLegacyWorkspaceCoreImported` must not unwind, delete, or invalidate the committed snapshot token:

```swift
do {
    try coreRepository.markLegacyWorkspaceCoreImported(
        workspaceId: snapshot.id,
        sourceStatePath: sourceStatePath,
        importedAt: snapshot.updatedAt
    )
} catch {
    try coreRepository.markLegacyWorkspaceImportFailed(
        workspace: WorkspaceSQLiteStateBridge.workspaceRecord(from: WorkspacePersistenceTransformer.persistableState(from: snapshot)),
        sourceStatePath: sourceStatePath,
        error: "Legacy import bookkeeping failed after completed snapshot: \(String(describing: error))"
    )
}
```

The completed snapshot remains authoritative. The next retry will skip it because `hasCompletedSnapshot(workspaceId:)` is true.

Task 4 owns the broader staged core/local commit fix and its local-failure regression tests. Task 3 only makes legacy-status bookkeeping unable to invalidate or replay an already-completed snapshot.

- [x] **Step 5: Run recovery tests**

Run:

```bash
swift test --filter WorkspaceSQLiteLegacyImportStatusTests
swift test --filter WorkspaceSQLiteStoreRecoveryTests
swift test --filter WorkspaceSQLiteStoreBridgeTests
```

Expected:

```text
All selected tests pass.
```

- [x] **Step 6: Commit**

```bash
git add Sources/AgentStudio/Core/State/MainActor/Persistence/WorkspaceStore+LegacySQLiteImport.swift \
        Sources/AgentStudio/Core/State/MainActor/Persistence/WorkspaceSQLiteStoreBackend.swift \
        Sources/AgentStudio/Core/State/MainActor/Persistence/WorkspaceStore.swift \
        Tests/AgentStudioTests/Core/Stores/WorkspaceSQLiteLegacyImportStatusTests.swift \
        Tests/AgentStudioTests/Core/Models/PaneTests.swift \
        Tests/AgentStudioTests/Core/Stores/WorkspaceLocalNotificationClaimMigrationTests.swift \
        docs/superpowers/specs/sqlite/04-migration-and-recovery.md \
        docs/superpowers/specs/sqlite/06-test-checkpoints.md \
        docs/superpowers/plans/2026-06-07-sqlite-datastore-actor-addendum.md
git commit -m "fix: harden legacy sqlite import retry status"
```

---

### Task 4: Make Core/Local Snapshot Completion Explicit

**Files:**
- Modify: `Sources/AgentStudio/Core/State/MainActor/Persistence/WorkspaceSQLiteStoreBackend.swift`
- Modify: `Sources/AgentStudio/Core/State/MainActor/Persistence/WorkspaceCoreRepository.swift`
- Modify: `Sources/AgentStudio/Core/State/MainActor/Persistence/WorkspaceCoreMigrations.swift`
- Test: `Tests/AgentStudioTests/Core/Stores/WorkspaceSQLiteCommitProtocolTests.swift`
- Test: `Tests/AgentStudioTests/Core/Stores/WorkspaceSQLiteStoreRecoveryTests.swift`
- Test: `Tests/AgentStudioTests/Core/Stores/WorkspaceCoreMigrationTests.swift`

- [x] **Step 1: Write failing staged-commit tests**

Create `Tests/AgentStudioTests/Core/Stores/WorkspaceSQLiteCommitProtocolTests.swift`:

```swift
import Foundation
import GRDB
import Testing

@testable import AgentStudio

@MainActor
@Suite("WorkspaceSQLiteCommitProtocolTests", .serialized)
struct WorkspaceSQLiteCommitProtocolTests {
    @Test("staged core write is not authoritative until final commit")
    func stagedCoreWriteIsNotAuthoritativeUntilFinalCommit() throws {
        let workspaceId = UUID()
        let coreQueue = try SQLiteDatabaseFactory.makeInMemoryQueue(label: "AgentStudio.sqlite.commit.core")
        try WorkspaceCoreMigrations.migrate(coreQueue)
        let coreRepository = WorkspaceCoreRepository(databaseWriter: coreQueue)
        let snapshot = WorkspaceSQLiteSnapshot(
            id: workspaceId,
            name: "Partial Core",
            repos: [],
            worktrees: [],
            unavailableRepoIds: [],
            watchedPaths: [],
            panes: [],
            tabs: [],
            activeTabId: nil,
            sidebarWidth: 250,
            windowFrame: nil,
            createdAt: Date(timeIntervalSince1970: 1),
            updatedAt: Date(timeIntervalSince1970: 2)
        )

        let state = WorkspacePersistenceTransformer.persistableState(from: snapshot)
        try coreRepository.replaceWorkspaceSnapshotStaged(
            workspace: WorkspaceSQLiteStateBridge.workspaceRecord(from: state),
            topology: WorkspaceSQLiteStateBridge.repositoryTopologyRecord(from: state),
            paneGraph: try WorkspaceSQLiteStateBridge.paneGraphRecord(from: state),
            tabShells: WorkspaceSQLiteStateBridge.tabShellRecords(from: state),
            tabGraph: WorkspaceSQLiteStateBridge.tabGraphRecord(from: state),
            stagedAt: snapshot.updatedAt
        )

        #expect(try !coreRepository.hasCompletedWorkspaceSQLiteSnapshot(workspaceId: workspaceId))
    }

    @Test("completed snapshot checks ignore staged-only rows")
    func completedSnapshotChecksIgnoreStagedOnlyRows() throws {
        let workspaceId = UUID()
        let coreQueue = try SQLiteDatabaseFactory.makeInMemoryQueue(label: "AgentStudio.sqlite.commit.staged-only.core")
        try WorkspaceCoreMigrations.migrate(coreQueue)
        let coreRepository = WorkspaceCoreRepository(databaseWriter: coreQueue)

        try coreRepository.markWorkspaceSQLiteSnapshotStaged(
            workspaceId: workspaceId,
            stagedAt: Date(timeIntervalSince1970: 2)
        )

        #expect(try !coreRepository.hasCompletedWorkspaceSQLiteSnapshot(workspaceId: workspaceId))
        #expect(try coreRepository.fetchCompletedWorkspaceSQLiteSnapshotAt(workspaceId: workspaceId) == nil)
    }
}
```

- [x] **Step 2: Run the failing test**

Run:

```bash
swift test --filter WorkspaceSQLiteCommitProtocolTests
```

Expected:

```text
FAIL: cannot find staged status APIs in scope, or staged-only rows still count as completed.
```

- [x] **Step 3: Add staged status schema, staged core write, and final completion methods**

Add a core migration before changing repository behavior:

```text
007_stage_workspace_sqlite_snapshot_status
    rebuild workspace_sqlite_snapshot_status as:
        workspace_id TEXT PRIMARY KEY REFERENCES workspace(id) ON DELETE CASCADE
        staged_at REAL
        completed_at REAL
    backfill staged_at = completed_at for existing completed rows
```

`completed_at` must become nullable. SQLite cannot alter an existing `REAL NOT NULL` column into nullable in place, so rebuild the table in the migration instead of trying to `ALTER COLUMN`.

Update every completion reader/query:

```text
fetchCompletedWorkspaceSQLiteSnapshotAt
    -> SELECT completed_at ... WHERE workspace_id = ? AND completed_at IS NOT NULL

hasCompletedWorkspaceSQLiteSnapshot
completedWorkspaceSQLiteSnapshotExists
fetchFallbackCompletedWorkspaceIdString
repairActiveCompletedWorkspaceSelection
any active-workspace fallback query joining workspace_sqlite_snapshot_status
    -> require completed_at IS NOT NULL
```

Add tests:

```text
WorkspaceSQLiteCommitProtocolTests.stagedOnlyRowDoesNotCountAsCompleted
WorkspaceSQLiteCommitProtocolTests.activeSelectionRepairIgnoresStagedOnlyRows
WorkspaceSQLiteCommitProtocolTests.fallbackSelectionIgnoresStagedOnlyRows
WorkspaceCoreMigrationTests.freshCoreDatabaseCreatesWorkspaceSQLiteSnapshotStatusColumns
```

Then modify `WorkspaceCoreRepository` so core graph rows can be replaced without making the snapshot authoritative:

```swift
// Change the private/base replaceWorkspaceSnapshot helper to accept
// completedAt: Date? and skip authoritative status marking when nil.
// Existing public completed-write paths still pass a non-nil completedAt.
func replaceWorkspaceSnapshotStaged(
    workspace: WorkspaceRecord,
    topology: RepositoryTopologyRecord,
    paneGraph: PaneGraphRecord,
    tabShells: [TabShellRecord],
    tabGraph: TabGraphRecord,
    stagedAt: Date
) throws {
    try replaceWorkspaceSnapshot(
        workspace: workspace,
        topology: topology,
        paneGraph: paneGraph,
        tabShells: tabShells,
        tabGraph: tabGraph,
        completedAt: nil
    )
    try markWorkspaceSQLiteSnapshotStaged(workspaceId: workspace.id, stagedAt: stagedAt)
}

func markWorkspaceSQLiteSnapshotCommitted(workspaceId: UUID, committedAt: Date) throws {
    try databaseWriter.write { database in
        try database.execute(
            sql: """
                INSERT INTO workspace_sqlite_snapshot_status(workspace_id, staged_at, completed_at)
                VALUES (?, ?, ?)
                ON CONFLICT(workspace_id) DO UPDATE SET
                    staged_at = excluded.staged_at,
                    completed_at = excluded.completed_at
                """,
            arguments: [
                workspaceId.uuidString,
                committedAt.timeIntervalSince1970,
                committedAt.timeIntervalSince1970,
            ]
        )
    }
}
```

A restore must only treat a snapshot as authoritative when `completed_at` is non-null. A non-null `staged_at` with null `completed_at` means the previous save died before the full core/local pair committed and must be ignored or recovered by the next successful save.

- [x] **Step 4: Make `WorkspaceSQLiteStoreBackend.save(_:localRepository:)` the staged canonical save**

Define the staged protocol on the backend, not as a second actor-only body:

```swift
func save(_ snapshot: WorkspaceSQLiteSnapshot, localRepository: WorkspaceLocalRepository) throws {
    try replaceWorkspaceSnapshotStaged(snapshot, updatesActiveSelection: true)
    try localRepository.replaceWorkspaceSnapshotLocalState(
        cursorState: WorkspaceSQLiteStateBridge.cursorStateRecord(from: snapshot),
        windowState: WorkspaceSQLiteStateBridge.windowStateRecord(from: snapshot),
        completedAt: snapshot.updatedAt
    )
    try markWorkspaceSnapshotCommitted(workspaceId: snapshot.id, committedAt: snapshot.updatedAt)
}
```

The actor calls this method from `saveWorkspaceSnapshot`. There must be no alternate `saveWorkspaceSnapshot` implementation that manually performs a different write sequence.

Add backend wrapper methods that convert `WorkspaceSQLiteSnapshot` into repository records:

```swift
func replaceWorkspaceSnapshotStaged(
    _ snapshot: WorkspaceSQLiteSnapshot,
    updatesActiveSelection: Bool
) throws

func markWorkspaceSnapshotCommitted(workspaceId: UUID, committedAt: Date) throws
```

There is no attempt to “roll back” the core write in a catch handler. The correctness property is that staged core rows are not visible to restore as committed until the local write succeeds and the final core completion token is written. If a previous completed snapshot existed and the next save stages replacement core rows but fails before the local write, the old completion token is cleared by the staged status row; restore must treat that workspace as having no authoritative completed SQLite snapshot until a later successful save writes matching core/local completion tokens.

- [x] **Step 5: Add a positive completed-token test**

Append to `WorkspaceSQLiteCommitProtocolTests.swift`:

```swift
@Test("successful core and local save leaves matching completion tokens")
func successfulCoreAndLocalSaveLeavesMatchingCompletionTokens() throws {
    let workspaceId = UUID()
    let coreQueue = try SQLiteDatabaseFactory.makeInMemoryQueue(label: "AgentStudio.sqlite.commit.success.core")
    let localQueue = try SQLiteDatabaseFactory.makeInMemoryQueue(label: "AgentStudio.sqlite.commit.success.local")
    try WorkspaceCoreMigrations.migrate(coreQueue)
    try WorkspaceLocalMigrations.migrate(localQueue)
    let coreRepository = WorkspaceCoreRepository(databaseWriter: coreQueue)
    let localRepository = WorkspaceLocalRepository(workspaceId: workspaceId, databaseWriter: localQueue)
    let backend = WorkspaceSQLiteStoreBackend(
        coreRepository: coreRepository,
        makeLocalRepository: { WorkspaceLocalRepository(workspaceId: $0, databaseWriter: localQueue) }
    )
    let updatedAt = Date(timeIntervalSince1970: 10)

    try backend.save(
        WorkspaceSQLiteSnapshot(
            id: workspaceId,
            name: "Complete",
            repos: [],
            worktrees: [],
            unavailableRepoIds: [],
            watchedPaths: [],
            panes: [],
            tabs: [],
            activeTabId: nil,
            sidebarWidth: 250,
            windowFrame: nil,
            createdAt: Date(timeIntervalSince1970: 1),
            updatedAt: updatedAt
        ),
        localRepository: localRepository
    )

    #expect(try coreRepository.fetchCompletedWorkspaceSQLiteSnapshotAt(workspaceId: workspaceId) == updatedAt)
    #expect(try localRepository.fetchCompletedWorkspaceSQLiteSnapshotAt() == updatedAt)
}
```

Also add the failed-local regression:

```text
WorkspaceSQLiteCommitProtocolTests.failedLocalSaveClearsCoreCompletionAuthority
```

This pins the intended failure mode: after a staged core replacement fails to write local state, `fetchCompletedWorkspaceSQLiteSnapshotAt` returns nil and `load(preferredWorkspaceId:)` returns nil rather than hydrating a core graph whose local sidecar did not commit.

- [x] **Step 6: Run commit protocol tests**

Run:

```bash
swift test --filter WorkspaceSQLiteCommitProtocolTests
swift test --filter WorkspaceSQLiteStoreRecoveryTests
```

Expected:

```text
All selected tests pass.
```

- [x] **Step 7: Commit**

```bash
git add Sources/AgentStudio/Core/State/MainActor/Persistence/WorkspaceSQLiteStoreBackend.swift \
        Sources/AgentStudio/Core/State/MainActor/Persistence/WorkspaceCoreRepository.swift \
        Sources/AgentStudio/Core/State/MainActor/Persistence/WorkspaceCoreMigrations.swift \
        Tests/AgentStudioTests/Core/Stores/WorkspaceSQLiteCommitProtocolTests.swift
git commit -m "fix: require matched core local sqlite commits"
```

---

### Task 5: Preserve Failed Local Quarantine Outcome

**Files:**
- Modify: `Sources/AgentStudio/Core/State/MainActor/Persistence/WorkspaceSQLiteStoreBackend.swift`
- Modify: `Sources/AgentStudio/Core/State/MainActor/Persistence/WorkspaceSQLiteStoreBackendFactory.swift`
- Test: `Tests/AgentStudioTests/Core/Stores/WorkspaceSQLiteStoreBackendFactoryTests.swift`
- Test: `Tests/AgentStudioTests/Core/Stores/WorkspaceSQLiteStoreRecoveryTests.swift`

- [x] **Step 1: Write the failing quarantine outcome test**

Append to `WorkspaceSQLiteStoreBackendFactoryTests.swift` or create a focused test if the existing file is crowded:

```text
WorkspaceSQLiteStoreRecoveryTests.quarantineFailureDoesNotRepairOrReopenBadLocalSidecar
```

Expected before production changes:

```text
FAIL: quarantine failure is collapsed into recovered/default local state, or repair opens the same failed sidecar immediately.
```

- [x] **Step 2: Add the new local recovery error cases**

Modify `WorkspaceSQLiteStoreBackend.swift`:

```swift
enum WorkspaceLocalSQLiteStoreBackendError: Error {
    case recoveredFromCorruption(UUID)
    case quarantineFailed(UUID)
}
```

- [x] **Step 3: Update factory to preserve quarantine failure**

Modify `WorkspaceSQLiteStoreBackendFactory.swift` local restore branch:

```swift
let quarantine = SQLiteSidecarQuarantine.quarantine(
    databaseURL: localDatabaseURL(workspaceId)
)
recoveryReporter?(
    .init(
        store: .workspace,
        workspaceId: workspaceId,
        recovery: quarantine.succeeded ? .quarantinedAndReset : .quarantineFailed,
        quarantinedFilename: quarantine.recoveryFilename
    )
)
guard quarantine.succeeded else {
    throw WorkspaceLocalSQLiteStoreBackendError.quarantineFailed(workspaceId)
}
do {
    _ = try makeLocalRepository(workspaceId: workspaceId)
} catch {
    workspaceSQLiteBackendFactoryLogger.error(
        "Failed to prepare local SQLite workspace backend after quarantine: \(error.localizedDescription)"
    )
}
throw WorkspaceLocalSQLiteStoreBackendError.recoveredFromCorruption(workspaceId)
```

When this path is later moved behind `WorkspaceSQLiteDatastore`, do not call `PersistenceRecoveryReporter` from inside the actor. Return the `PersistenceRecoveryEvent` with the restore/open outcome and let the MainActor boot/store caller record it.

- [x] **Step 4: Skip local repair when quarantine failed**

Modify `WorkspaceSQLiteStoreBackend.loadCompletedSnapshot`:

```swift
let localRepository: WorkspaceLocalRepository?
let localRepairDisposition: LocalSnapshotRepairDisposition
do {
    localRepository = try localBackend.restoreRepository(for: workspace.id)
    localRepairDisposition = .repairAllowed
} catch WorkspaceLocalSQLiteStoreBackendError.recoveredFromCorruption {
    localRepository = nil
    localRepairDisposition = .repairAllowed
} catch WorkspaceLocalSQLiteStoreBackendError.quarantineFailed {
    localRepository = nil
    localRepairDisposition = .repairBlockedByQuarantineFailure
} catch {
    localRepository = nil
    localRepairDisposition = .repairAllowed
}
```

Wrap the repair call:

```swift
enum LocalSnapshotRepairDisposition: Equatable {
    case repairAllowed
    case repairBlockedByQuarantineFailure
}

if localRepairDisposition == .repairAllowed {
    repairLocalSnapshotIfPossible(
        workspaceId: workspace.id,
        cursorState: cursorState,
        windowState: windowState,
        completedAt: coreCompletedAt
    )
}
```

- [x] **Step 5: Complete backend test with injected quarantine failure**

Append to `WorkspaceSQLiteStoreBackendFactoryTests.swift` or create a focused test if the existing file is crowded:

```swift
@MainActor
@Test("quarantine failed local restore does not immediately repair same sidecar")
func quarantineFailedLocalRestoreDoesNotImmediatelyRepairSameSidecar() throws {
    let workspaceId = UUID()
    let coreQueue = try SQLiteDatabaseFactory.makeInMemoryQueue(label: "AgentStudio.sqlite.quarantine.failed.core")
    try WorkspaceCoreMigrations.migrate(coreQueue)
    let coreRepository = WorkspaceCoreRepository(databaseWriter: coreQueue)
    var repairOpenCount = 0
    let backend = WorkspaceSQLiteStoreBackend(
        coreRepository: coreRepository,
        makeLocalRepository: { workspaceId in
            repairOpenCount += 1
            return WorkspaceLocalRepository(
                workspaceId: workspaceId,
                databaseWriter: try SQLiteDatabaseFactory.makeInMemoryQueue(label: "AgentStudio.sqlite.quarantine.failed.local.repair")
            )
        },
        makeLocalRestoreRepository: { workspaceId in
            throw WorkspaceLocalSQLiteStoreBackendError.quarantineFailed(workspaceId)
        }
    )
    let initialLocalRepository = WorkspaceLocalRepository(
        workspaceId: workspaceId,
        databaseWriter: try SQLiteDatabaseFactory.makeInMemoryQueue(label: "AgentStudio.sqlite.quarantine.failed.local.initial")
    )
    try backend.save(
        WorkspaceSQLiteSnapshot(
            id: workspaceId,
            name: "Core Only",
            repos: [],
            worktrees: [],
            unavailableRepoIds: [],
            watchedPaths: [],
            panes: [],
            tabs: [],
            activeTabId: nil,
            sidebarWidth: 250,
            windowFrame: nil,
            createdAt: Date(timeIntervalSince1970: 1),
            updatedAt: Date(timeIntervalSince1970: 2)
        ),
        localRepository: initialLocalRepository
    )
    repairOpenCount = 0

    _ = try backend.load(preferredWorkspaceId: workspaceId)

    #expect(repairOpenCount == 0)
}
```

- [x] **Step 6: Run factory/recovery tests**

Run:

```bash
swift test --filter WorkspaceSQLiteStoreBackendFactoryTests
swift test --filter WorkspaceSQLiteStoreRecoveryTests
```

Expected:

```text
All selected tests pass.
```

- [x] **Step 7: Commit**

```bash
git add Sources/AgentStudio/Core/State/MainActor/Persistence/WorkspaceSQLiteStoreBackend.swift \
        Sources/AgentStudio/Core/State/MainActor/Persistence/WorkspaceSQLiteStoreBackendFactory.swift \
        Tests/AgentStudioTests/Core/Stores/WorkspaceSQLiteStoreBackendFactoryTests.swift \
        Tests/AgentStudioTests/Core/Stores/WorkspaceSQLiteStoreRecoveryTests.swift
git commit -m "fix: preserve failed local sqlite quarantine outcome"
```

---

### Task 6: Introduce `WorkspaceSQLiteDatastore` Actor

**Files:**
- Create: `Sources/AgentStudio/Core/State/SQLite/WorkspaceSQLiteDatastore.swift`
- Create: `Sources/AgentStudio/Core/State/SQLite/WorkspaceSQLiteDatastoreFactory.swift`
- Modify: `Sources/AgentStudio/Core/State/MainActor/Persistence/WorkspaceCoreRepository.swift`
- Modify: `Sources/AgentStudio/Core/State/MainActor/Persistence/WorkspaceLocalRepository.swift`
- Modify: `Sources/AgentStudio/Core/State/MainActor/Persistence/WorkspaceSQLiteStoreBackend.swift`
- Modify: `Sources/AgentStudio/Core/State/MainActor/Persistence/WorkspaceSQLiteStoreBackendFactory.swift`
- Modify: `Sources/AgentStudio/Features/InboxNotification/State/MainActor/Persistence/InboxNotificationStore.swift`
- Test: `Tests/AgentStudioTests/Core/Stores/WorkspaceSQLiteDatastoreActorTests.swift`
- Test: `Tests/AgentStudioTests/Core/Stores/WorkspaceSQLiteStoreRecoveryTests.swift`

**Boundary rule for this task:** `WorkspaceSQLiteDatastore` owns SQLite sequencing and repository lifecycle. GRDB `DatabaseWriter` inherits `Sendable` through `DatabaseReader`; repository structs may be sendable if their stored properties are sendable. Do not use `@unchecked Sendable` to paper over non-sendable closures or MainActor-bound callbacks. The values that cross the actor boundary, such as `WorkspaceSQLiteSnapshot`, load outcomes, status decisions, recovery events, and errors, must be honestly `Sendable`.

The actor must also own local repository opening. A wrapper that merely calls `WorkspaceSQLiteStoreBackend.save(...)` while the backend opens a fresh local repository internally does not satisfy the cache requirement. Refactor backend helper methods so the datastore resolves the cached `WorkspaceLocalRepository` first, then invokes synchronous core/local repository operations with that repository.

Keep restore/open-for-read separate from save/open-for-write:

```text
restore/open-for-read
    -> uses WorkspaceLocalSQLiteStoreBackend.restoreRepository(for:)
    -> preserves corruption quarantine and recovered/reset semantics
    -> used by workspace restore, repo-cache restore, UI/sidebar restore, and inbox boot/load

save/open-for-write
    -> uses WorkspaceLocalSQLiteStoreBackend.repository(for:)
    -> used by normal flush/save paths after boot has settled
```

Do not collapse these into one cache method. That would bypass local quarantine handling on restore.

- [ ] **Step 1: Write actor boundary tests**

Create `Tests/AgentStudioTests/Core/Stores/WorkspaceSQLiteDatastoreActorTests.swift`:

```swift
import Foundation
import GRDB
import Testing

@testable import AgentStudio

@MainActor
@Suite("WorkspaceSQLiteDatastoreActorTests", .serialized)
struct WorkspaceSQLiteDatastoreActorTests {
    @Test("workspace save runs through datastore actor probe")
    func workspaceSaveRunsThroughDatastoreActorProbe() async throws {
        let workspaceId = UUID()
        let coreQueue = try SQLiteDatabaseFactory.makeInMemoryQueue(label: "AgentStudio.sqlite.datastore.core")
        let localQueue = try SQLiteDatabaseFactory.makeInMemoryQueue(label: "AgentStudio.sqlite.datastore.local")
        try WorkspaceCoreMigrations.migrate(coreQueue)
        try WorkspaceLocalMigrations.migrate(localQueue)
        let recorder = DatastoreProbeRecorder()
        let datastore = WorkspaceSQLiteDatastore(
            backend: WorkspaceSQLiteStoreBackend(
                coreRepository: WorkspaceCoreRepository(databaseWriter: coreQueue),
                makeLocalRepository: { WorkspaceLocalRepository(workspaceId: $0, databaseWriter: localQueue) }
            ),
            probe: { event in recorder.record(event) }
        )

        try await datastore.saveWorkspaceSnapshot(
            WorkspaceSQLiteSnapshot(
                id: workspaceId,
                name: "Datastore",
                repos: [],
                worktrees: [],
                unavailableRepoIds: [],
                watchedPaths: [],
                panes: [],
                tabs: [],
                activeTabId: nil,
                sidebarWidth: 250,
                windowFrame: nil,
                createdAt: Date(timeIntervalSince1970: 1),
                updatedAt: Date(timeIntervalSince1970: 2)
            )
        )

        #expect(await recorder.events.contains(.saveWorkspaceSnapshot))
        #expect(await recorder.events.contains(.localRepositoryOpened(workspaceId, .save)))
    }

    @Test("local repository is cached by workspace id")
    func localRepositoryIsCachedByWorkspaceIdAcrossProductionSaves() async throws {
        let workspaceId = UUID()
        let coreQueue = try SQLiteDatabaseFactory.makeInMemoryQueue(label: "AgentStudio.sqlite.datastore.cache.core")
        let localQueue = try SQLiteDatabaseFactory.makeInMemoryQueue(label: "AgentStudio.sqlite.datastore.cache.local")
        try WorkspaceCoreMigrations.migrate(coreQueue)
        try WorkspaceLocalMigrations.migrate(localQueue)
        let recorder = DatastoreProbeRecorder()
        let datastore = WorkspaceSQLiteDatastore(
            coreRepository: WorkspaceCoreRepository(databaseWriter: coreQueue),
            makeLocalRepository: { workspaceId in
                return WorkspaceLocalRepository(workspaceId: workspaceId, databaseWriter: localQueue)
            },
            probe: { event in recorder.record(event) }
        )

        try await datastore.saveWorkspaceSnapshot(.emptyFixture(id: workspaceId, name: "One"))
        try await datastore.saveWorkspaceSnapshot(.emptyFixture(id: workspaceId, name: "Two"))

        #expect(await recorder.events.filter { $0 == .localRepositoryOpened(workspaceId, .save) }.count == 1)
    }

    @Test("local repository is cached by workspace id across production load")
    func localRepositoryIsCachedByWorkspaceIdAcrossProductionLoad() async throws {
        let workspaceId = UUID()
        let coreQueue = try SQLiteDatabaseFactory.makeInMemoryQueue(label: "AgentStudio.sqlite.datastore.load.core")
        let localQueue = try SQLiteDatabaseFactory.makeInMemoryQueue(label: "AgentStudio.sqlite.datastore.load.local")
        try WorkspaceCoreMigrations.migrate(coreQueue)
        try WorkspaceLocalMigrations.migrate(localQueue)
        let recorder = DatastoreProbeRecorder()
        let datastore = WorkspaceSQLiteDatastore(
            coreRepository: WorkspaceCoreRepository(databaseWriter: coreQueue),
            makeLocalRepository: { workspaceId in
                return WorkspaceLocalRepository(workspaceId: workspaceId, databaseWriter: localQueue)
            },
            probe: { event in recorder.record(event) }
        )

        try await datastore.saveWorkspaceSnapshot(.emptyFixture(id: workspaceId, name: "Loaded"))
        _ = await datastore.loadWorkspaceSnapshot(preferredWorkspaceId: workspaceId)

        #expect(await recorder.events.filter { $0 == .localRepositoryOpened(workspaceId, .save) }.count == 1)
        #expect(await recorder.events.filter { $0 == .localRepositoryOpened(workspaceId, .restore) }.count == 1)
    }
}

private actor DatastoreProbeRecorder {
    private(set) var events: [WorkspaceSQLiteDatastore.ProbeEvent] = []

    func record(_ event: WorkspaceSQLiteDatastore.ProbeEvent) {
        events.append(event)
    }
}

```

- [ ] **Step 2: Run the failing datastore tests**

Run:

```bash
swift test --filter WorkspaceSQLiteDatastoreActorTests
```

Expected:

```text
FAIL: cannot find 'WorkspaceSQLiteDatastore' in scope
```

- [ ] **Step 3: Add sendable inbox SQLite snapshot payloads**

Before `WorkspaceSQLiteDatastore` references inbox payload types, add explicit sendable snapshots inside `InboxNotificationStore`:

```swift
struct SQLiteSnapshot: Sendable, Equatable {
    var notifications: [InboxNotification]
    var collapsedGroups: Set<InboxNotificationGroupKey>
    var markLegacyImport: Bool
}

struct SQLiteLoadSnapshot: Sendable, Equatable {
    var notifications: [InboxNotification]
    var collapsedGroups: Set<InboxNotificationGroupKey>
    var hasPersistedState: Bool
    var hasMaterializedLegacyImport: Bool
}
```

This step does not route inbox persistence yet; it only creates the typed actor-boundary payloads needed for the datastore actor to compile in this task. The actual inbox store routing remains in Task 7.

- [ ] **Step 4: Implement the datastore actor**

Create `Sources/AgentStudio/Core/State/SQLite/WorkspaceSQLiteDatastore.swift`:

```swift
import Foundation

struct WorkspaceSQLiteDatastoreConfiguration: Sendable {
    var coreDatabaseURL: URL
    var localDatabaseURL: @Sendable (UUID) -> URL
}

actor WorkspaceSQLiteDatastore {
    enum LocalRepositoryOpenMode: Equatable, Sendable {
        case restore
        case save
    }

    enum ProbeEvent: Equatable, Sendable {
        case saveWorkspaceSnapshot
        case loadWorkspaceSnapshot
        case localRepositoryOpened(UUID, LocalRepositoryOpenMode)
    }

    enum LoadResult: Sendable, Equatable {
        case loaded(WorkspaceSQLiteSnapshot, recoveryEvents: [PersistenceRecoveryEvent])
        case uninitialized(recoveryEvents: [PersistenceRecoveryEvent])
        case unavailable(WorkspaceSQLiteDatastoreFailure, recoveryEvents: [PersistenceRecoveryEvent])
    }

    enum LegacyImportStatusResult: Sendable, Equatable {
        case found(WorkspaceCoreRepository.LegacyImportStatusRecord)
        case missing
        case unavailable(WorkspaceSQLiteDatastoreFailure)
    }

    enum WorkspaceRowsInspectionResult: Sendable, Equatable {
        case hasWorkspaceRows
        case empty
        case unavailable(WorkspaceSQLiteDatastoreFailure)
    }

    enum InboxSQLiteBootDecision: Sendable, Equatable {
        case available(InboxSQLiteBootPolicy, recoveryEvents: [PersistenceRecoveryEvent])
        case unavailable(WorkspaceSQLiteDatastoreFailure, recoveryEvents: [PersistenceRecoveryEvent])
    }

    struct InboxSQLiteBootPolicy: Sendable, Equatable {
        var hasSQLiteRepository: Bool
        var allowLegacyFilePersistence: Bool
        var allowLegacyFileImport: Bool
        var canArchiveLegacyInboxFileAfterBlockedImport: Bool
    }

    enum InboxLoadResult: Sendable, Equatable {
        case loaded(InboxNotificationStore.SQLiteLoadSnapshot, recoveryEvents: [PersistenceRecoveryEvent])
        case unavailable(WorkspaceSQLiteDatastoreFailure, recoveryEvents: [PersistenceRecoveryEvent])
    }

    private var backend: WorkspaceSQLiteStoreBackend?
    private let configuration: WorkspaceSQLiteDatastoreConfiguration?
    private var restoreLocalRepositoryCache: [UUID: WorkspaceLocalRepository] = [:]
    private var saveLocalRepositoryCache: [UUID: WorkspaceLocalRepository] = [:]
    private var pendingRecoveryEventsByWorkspaceId: [UUID: [PersistenceRecoveryEvent]] = [:]
    private let makeLocalRepositoryOverride: (@Sendable (UUID) throws -> WorkspaceLocalRepository)?
    private let makeLocalRestoreRepositoryOverride: (@Sendable (UUID) throws -> WorkspaceLocalRepository)?
    private let probe: (@Sendable (ProbeEvent) async -> Void)?

    init(
        configuration: WorkspaceSQLiteDatastoreConfiguration,
        probe: (@Sendable (ProbeEvent) async -> Void)? = nil
    ) {
        self.backend = nil
        self.configuration = configuration
        self.makeLocalRepositoryOverride = nil
        self.makeLocalRestoreRepositoryOverride = nil
        self.probe = probe
    }

    // Test-only initializer for in-memory backend fixtures. Production code uses
    // WorkspaceSQLiteDatastoreConfiguration so open/migrate work happens inside the actor.
    init(
        backend: WorkspaceSQLiteStoreBackend,
        probe: (@Sendable (ProbeEvent) async -> Void)? = nil
    ) {
        self.backend = backend
        self.configuration = nil
        self.makeLocalRepositoryOverride = nil
        self.makeLocalRestoreRepositoryOverride = nil
        self.probe = probe
    }

    init(
        coreRepository: WorkspaceCoreRepository,
        makeLocalRepository: @escaping @Sendable (UUID) throws -> WorkspaceLocalRepository,
        makeLocalRestoreRepository: (@Sendable (UUID) throws -> WorkspaceLocalRepository)? = nil,
        probe: (@Sendable (ProbeEvent) async -> Void)? = nil
    ) {
        self.backend = WorkspaceSQLiteStoreBackend(
            coreRepository: coreRepository,
            makeLocalRepository: { _ in
                throw WorkspaceSQLiteDatastoreError.useDatastoreLocalRepositoryCache
            }
        )
        self.configuration = nil
        self.makeLocalRepositoryOverride = makeLocalRepository
        self.makeLocalRestoreRepositoryOverride = makeLocalRestoreRepository ?? makeLocalRepository
        self.probe = probe
    }

    private func resolvedBackend() throws -> WorkspaceSQLiteStoreBackend {
        if let backend { return backend }
        guard let configuration else {
            throw WorkspaceSQLiteDatastoreError.missingConfiguration
        }
        let openedBackend = try WorkspaceSQLiteStoreBackendFactory(configuration: configuration).openBackend()
        backend = openedBackend
        return openedBackend
    }

    func saveWorkspaceSnapshot(_ snapshot: WorkspaceSQLiteSnapshot) async throws {
        await probe?(.saveWorkspaceSnapshot)
        let backend = try resolvedBackend()
        let localRepository = try await cachedSaveLocalRepository(workspaceId: snapshot.id)
        try backend.save(snapshot, localRepository: localRepository)
    }

    func loadWorkspaceSnapshot(preferredWorkspaceId: UUID) async -> LoadResult {
        await probe?(.loadWorkspaceSnapshot)
        do {
            let backend = try resolvedBackend()
            let snapshot = try await backend.loadCompletedSnapshot(
                preferredWorkspaceId: preferredWorkspaceId,
                localRepositoryForWorkspaceId: { workspaceId in
                    try await cachedRestoreLocalRepository(workspaceId: workspaceId)
                },
                repairLocalRepositoryForWorkspaceId: { workspaceId in
                    try await cachedSaveLocalRepository(workspaceId: workspaceId)
                }
            )
            return .loaded(snapshot, recoveryEvents: drainRecoveryEvents(workspaceId: snapshot.id))
        } catch is BackendUninitializedError {
            return .uninitialized(recoveryEvents: drainAllRecoveryEvents())
        } catch {
            return .unavailable(.init(error), recoveryEvents: drainAllRecoveryEvents())
        }
    }

    func hasCompletedSnapshot(workspaceId: UUID) async throws -> Bool {
        let backend = try resolvedBackend()
        try backend.hasCompletedSnapshot(workspaceId: workspaceId)
    }

    func selectActiveWorkspace(_ workspaceId: UUID, updatedAt: Date) async throws {
        let backend = try resolvedBackend()
        try backend.selectActiveWorkspace(workspaceId, updatedAt: updatedAt)
    }

    func markLegacyWorkspaceCompanionImportsCompleted(
        workspaceId: UUID,
        importedAt: Date
    ) async throws {
        let backend = try resolvedBackend()
        try backend.markLegacyWorkspaceCompanionImportsCompleted(
            workspaceId: workspaceId,
            importedAt: importedAt
        )
    }

    func markLegacyWorkspaceArchived(
        workspaceId: UUID,
        archivedAt: Date
    ) async throws {
        let backend = try resolvedBackend()
        try backend.markLegacyWorkspaceArchived(
            workspaceId: workspaceId,
            archivedAt: archivedAt
        )
    }

    func inspectWorkspaceRows() async -> WorkspaceRowsInspectionResult {
        do {
            let backend = try resolvedBackend()
            return try backend.coreRepository.fetchWorkspaces().isEmpty ? .empty : .hasWorkspaceRows
        } catch {
            return .unavailable(.init(error))
        }
    }

    func legacyImportStatus(workspaceId: UUID) async -> LegacyImportStatusResult {
        do {
            let backend = try resolvedBackend()
            guard let status = try backend.coreRepository.fetchLegacyWorkspaceImportStatus(workspaceId: workspaceId) else {
                return .missing
            }
            return .found(status)
        } catch {
            return .unavailable(.init(error))
        }
    }

    func saveImportedLegacySnapshot(
        _ snapshot: WorkspaceSQLiteSnapshot,
        sourceStatePath: String
    ) async throws {
        let backend = try resolvedBackend()
        let localRepository = try await cachedSaveLocalRepository(workspaceId: snapshot.id)
        try backend.saveImportedLegacySnapshot(
            snapshot,
            sourceStatePath: sourceStatePath,
            localRepository: localRepository
        )
    }

    func markLegacyWorkspaceImportFailed(
        _ snapshot: WorkspaceSQLiteSnapshot,
        sourceStatePath: String,
        error: any Error
    ) async -> LegacyImportFailureRecordOutcome {
        do {
            let backend = try resolvedBackend()
            try backend.markLegacyWorkspaceImportFailed(
                snapshot,
                sourceStatePath: sourceStatePath,
                error: error
            )
            return .recorded
        } catch {
            return .failedToRecord(.init(error))
        }
    }

    func makeInboxSQLiteBootDecision(workspaceId: UUID) async -> InboxSQLiteBootDecision {
        do {
            let backend = try resolvedBackend()
            let localRepository = try await cachedRestoreLocalRepository(workspaceId: workspaceId)
            let legacyImportDecision = try backend.localBackend.legacyImportDecision(
                for: workspaceId,
                lane: .local
            )
            let inboxRepository = InboxNotificationSQLiteRepository(
                workspaceId: workspaceId,
                databaseWriter: localRepository.databaseWriter
            )
            let hasMaterializedLegacyInboxImport = try inboxRepository.hasMaterializedLegacyImport()
            return .available(
                .init(
                    hasSQLiteRepository: true,
                    allowLegacyFilePersistence: true,
                    allowLegacyFileImport: legacyImportDecision.allowsLegacyImport,
                    canArchiveLegacyInboxFileAfterBlockedImport: legacyImportDecision.canArchiveLegacyFile
                        && hasMaterializedLegacyInboxImport
                ),
                recoveryEvents: drainRecoveryEvents(workspaceId: workspaceId)
            )
        } catch {
            return .unavailable(.init(error), recoveryEvents: drainRecoveryEvents(workspaceId: workspaceId))
        }
    }

    func loadInboxNotifications(workspaceId: UUID) async -> InboxLoadResult {
        do {
            let repository = try await inboxNotificationRepositoryForRestore(workspaceId: workspaceId)
            return .loaded(
                .init(
                    notifications: try repository.fetchNotifications(),
                    collapsedGroups: try repository.fetchCollapsedGroups(),
                    hasPersistedState: try repository.hasPersistedState(),
                    hasMaterializedLegacyImport: try repository.hasMaterializedLegacyImport()
                ),
                recoveryEvents: drainRecoveryEvents(workspaceId: workspaceId)
            )
        } catch {
            return .unavailable(.init(error), recoveryEvents: drainRecoveryEvents(workspaceId: workspaceId))
        }
    }

    func saveInboxNotifications(
        _ snapshot: InboxNotificationStore.SQLiteSnapshot,
        workspaceId: UUID
    ) async throws {
        let repository = try await inboxNotificationRepositoryForSave(workspaceId: workspaceId)
        if snapshot.markLegacyImport {
            try repository.replaceLegacyImportSnapshot(
                notifications: snapshot.notifications,
                collapsedGroups: snapshot.collapsedGroups
            )
        } else {
            try repository.replaceSnapshot(
                notifications: snapshot.notifications,
                collapsedGroups: snapshot.collapsedGroups
            )
        }
    }

    private func inboxNotificationRepositoryForRestore(workspaceId: UUID) async throws -> InboxNotificationSQLiteRepository {
        let localRepository = try await cachedRestoreLocalRepository(workspaceId: workspaceId)
        return InboxNotificationSQLiteRepository(
            workspaceId: workspaceId,
            databaseWriter: localRepository.databaseWriter
        )
    }

    private func inboxNotificationRepositoryForSave(workspaceId: UUID) async throws -> InboxNotificationSQLiteRepository {
        let localRepository = try await cachedSaveLocalRepository(workspaceId: workspaceId)
        return InboxNotificationSQLiteRepository(
            workspaceId: workspaceId,
            databaseWriter: localRepository.databaseWriter
        )
    }

    private func cachedRestoreLocalRepository(workspaceId: UUID) async throws -> WorkspaceLocalRepository {
        if let repository = restoreLocalRepositoryCache[workspaceId] {
            return repository
        }
        let repository: WorkspaceLocalRepository
        if let makeLocalRestoreRepositoryOverride {
            repository = try makeLocalRestoreRepositoryOverride(workspaceId)
        } else {
            let backend = try resolvedBackend()
            let outcome = try backend.localBackend.restoreRepositoryWithRecoveryEvents(for: workspaceId)
            switch outcome {
            case .opened(let openedRepository, let recoveryEvents):
                repository = openedRepository
                appendRecoveryEvents(recoveryEvents, workspaceId: workspaceId)
            case .failed(let failure, let recoveryEvents):
                appendRecoveryEvents(recoveryEvents, workspaceId: workspaceId)
                throw failure
            }
        }
        restoreLocalRepositoryCache[workspaceId] = repository
        await probe?(.localRepositoryOpened(workspaceId, .restore))
        return repository
    }

    private func appendRecoveryEvents(_ events: [PersistenceRecoveryEvent], workspaceId: UUID) {
        guard !events.isEmpty else { return }
        pendingRecoveryEventsByWorkspaceId[workspaceId, default: []].append(contentsOf: events)
    }

    private func drainRecoveryEvents(workspaceId: UUID) -> [PersistenceRecoveryEvent] {
        let events = pendingRecoveryEventsByWorkspaceId[workspaceId, default: []]
        pendingRecoveryEventsByWorkspaceId[workspaceId] = []
        return events
    }

    private func drainAllRecoveryEvents() -> [PersistenceRecoveryEvent] {
        let events = pendingRecoveryEventsByWorkspaceId.values.flatMap { $0 }
        pendingRecoveryEventsByWorkspaceId.removeAll()
        return events
    }

    private func cachedSaveLocalRepository(workspaceId: UUID) async throws -> WorkspaceLocalRepository {
        if let repository = saveLocalRepositoryCache[workspaceId] {
            return repository
        }
        guard let makeLocalRepositoryOverride else {
            let backend = try resolvedBackend()
            let repository = try backend.localBackend.repository(for: workspaceId)
            saveLocalRepositoryCache[workspaceId] = repository
            await probe?(.localRepositoryOpened(workspaceId, .save))
            return repository
        }
        let repository = try makeLocalRepositoryOverride(workspaceId)
        saveLocalRepositoryCache[workspaceId] = repository
        await probe?(.localRepositoryOpened(workspaceId, .save))
        return repository
    }

    func invalidateLocalRepository(workspaceId: UUID) {
        restoreLocalRepositoryCache.removeValue(forKey: workspaceId)
        saveLocalRepositoryCache.removeValue(forKey: workspaceId)
    }
}

enum LegacyImportFailureRecordOutcome: Sendable, Equatable {
    case recorded
    case failedToRecord(WorkspaceSQLiteDatastoreFailure)
}

enum WorkspaceSQLiteDatastoreError: Error, Equatable {
    case useDatastoreLocalRepositoryCache
    case missingConfiguration
}

struct WorkspaceSQLiteDatastoreFailure: Error, Sendable, Equatable {
    let message: String

    init(_ error: any Error) {
        self.message = String(describing: error)
    }
}
```

- [ ] **Step 5: Make backend non-MainActor and remove backend-owned local opening**

Remove `@MainActor` from `WorkspaceSQLiteStoreBackend` and move MainActor-only legacy import decision calls out of backend methods that can run on the datastore actor. Keep `WorkspaceLocalSQLiteLegacyImportDecision` as `Sendable` enum values.

Do not use `@unchecked Sendable`. Fix the actual non-sendable pieces:

```text
WorkspaceCoreRepository
WorkspaceLocalRepository
WorkspaceSQLiteStoreBackend
WorkspaceLocalSQLiteStoreBackend
WorkspaceLocalSQLiteStoreBackend.makeLocalRepository
WorkspaceLocalSQLiteStoreBackend.makeLocalRestoreRepository
WorkspaceLocalSQLiteStoreBackend.legacyImportDecision closure
WorkspaceSQLiteStoreBackendFactory.localDatabaseURL
```

`WorkspaceCoreRepository` and `WorkspaceLocalRepository` may conform to `Sendable` because their stored GRDB `DatabaseWriter` value is Sendable through `DatabaseReader`. `WorkspaceSQLiteStoreBackend` and `WorkspaceLocalSQLiteStoreBackend` may conform to `Sendable` only after every stored closure is `@Sendable` and no stored callback is MainActor-bound.

These closures must become `@Sendable` and non-MainActor. `AppDataPaths.workspaceLocalSQLiteURL(workspaceId:)` is usable from the actor, so the URL closure does not need MainActor isolation.

Move SQLite backend bootstrap/open/migration off MainActor as well. `WorkspaceSQLiteStoreBackendFactory.openBackend()` must be actor-usable and must not synchronously report recovery through `PersistenceRecoveryReporter`. Production datastore construction passes a sendable `WorkspaceSQLiteDatastoreConfiguration` into `WorkspaceSQLiteDatastore`; the actor lazily opens/migrates core and local repositories on its own executor. Test-only initializers may still pass in-memory repositories directly.

Move quarantine/recovery reporting out of synchronous local-repository open closures. `PersistenceRecoveryReporter` is `@MainActor`; actor-run restore/open code must return `PersistenceRecoveryEvent` values or typed recovery outcomes, and the MainActor caller records them.

Because the first local restore open normally happens during `loadCanonicalStore`, not during cache/UI/sidebar restore, recovery events must be buffered at the datastore actor. `cachedRestoreLocalRepository(workspaceId:)` appends any quarantine/recovery events into `pendingRecoveryEventsByWorkspaceId`; public restore/load APIs drain and return those events:

```text
loadWorkspaceSnapshot
makeInboxSQLiteBootDecision
loadInboxNotifications
loadRepoCacheState
loadUIState
loadSidebarState
```

The MainActor caller records every returned event with `recordPersistenceRecovery(_:)`. This is safe before inbox boot because the current app already queues pre-inbox events and `flushPersistenceRecoveryNotifications()` appends them after `InboxNotificationStore` loads.

The target backend signatures take a caller-supplied local repository instead of opening one internally:

```swift
struct WorkspaceSQLiteStoreBackend {
    let coreRepository: WorkspaceCoreRepository
    let localBackend: WorkspaceLocalSQLiteStoreBackend

    func save(_ snapshot: WorkspaceSQLiteSnapshot, localRepository: WorkspaceLocalRepository) throws

    func loadCompletedSnapshot(
        preferredWorkspaceId: UUID,
        localRepositoryForWorkspaceId: (UUID) async throws -> WorkspaceLocalRepository,
        repairLocalRepositoryForWorkspaceId: (UUID) async throws -> WorkspaceLocalRepository
    ) async throws -> WorkspaceSQLiteSnapshot
}

struct WorkspaceLocalSQLiteStoreBackend {
    enum RestoreRepositoryOutcome: Sendable {
        case opened(WorkspaceLocalRepository, recoveryEvents: [PersistenceRecoveryEvent])
        case failed(WorkspaceSQLiteDatastoreFailure, recoveryEvents: [PersistenceRecoveryEvent])
    }

    private let makeLocalRepository: @Sendable (UUID) throws -> WorkspaceLocalRepository
    private let makeLocalRestoreRepository: @Sendable (UUID) throws -> WorkspaceLocalRepository

    func repository(for workspaceId: UUID) throws -> WorkspaceLocalRepository
    func restoreRepository(for workspaceId: UUID) throws -> WorkspaceLocalRepository
    func restoreRepositoryWithRecoveryEvents(for workspaceId: UUID) throws -> RestoreRepositoryOutcome
    func legacyImportDecision(
        for workspaceId: UUID,
        lane: WorkspaceLocalSQLiteLegacyLane
    ) throws -> WorkspaceLocalSQLiteLegacyImportDecision
}
```

Rewrite `loadCompletedSnapshot` and `repairLocalSnapshotIfPossible` together:

```text
loadCompletedSnapshot
    -> obtains restore repo through localRepositoryForWorkspaceId
    -> preserves recoveredFromCorruption / quarantineFailed handling
    -> when default local state must be repaired, obtains write repo through repairLocalRepositoryForWorkspaceId

repairLocalSnapshotIfPossible
    -> never calls localBackend.repository(for:) directly
    -> never silently ignores the actor cache
    -> returns a typed repair outcome for tests/logging
```

Add tests:

```text
WorkspaceSQLiteDatastoreActorTests.restoreRepairUsesSaveRepositoryCache
WorkspaceSQLiteStoreRecoveryTests.localCorruptionStillRestoresWithDefaultState
WorkspaceSQLiteStoreRecoveryTests.quarantineFailureDoesNotRepairOrReopenBadLocalSidecar
WorkspaceSQLiteDatastoreActorTests.workspaceLoadReturnsFirstLocalRestoreRecoveryEvents
WorkspaceSQLiteDatastoreActorTests.inboxBootDrainsRecoveryEventsIfItIsFirstRestoreOpener
WorkspaceSQLiteDatastoreActorTests.cacheRestoreDoesNotLoseRecoveryEventsAlreadyQueuedByWorkspaceLoad
```

- [ ] **Step 6: Create datastore factory**

Create `Sources/AgentStudio/Core/State/SQLite/WorkspaceSQLiteDatastoreFactory.swift`:

```swift
import Foundation

struct WorkspaceSQLiteDatastoreFactory {
    var configuration: WorkspaceSQLiteDatastoreConfiguration

    init(
        coreDatabaseURL: URL = AppDataPaths.coreSQLiteURL(),
        localDatabaseURL: @escaping @Sendable (UUID) -> URL = { workspaceId in
            AppDataPaths.workspaceLocalSQLiteURL(workspaceId: workspaceId)
        }
    ) {
        self.configuration = WorkspaceSQLiteDatastoreConfiguration(
            coreDatabaseURL: coreDatabaseURL,
            localDatabaseURL: localDatabaseURL
        )
    }

    func makeDatastore() -> WorkspaceSQLiteDatastore {
        WorkspaceSQLiteDatastore(configuration: configuration)
    }
}
```

This factory is intentionally not `@MainActor` and does not open GRDB pools. AppDelegate may create it from MainActor, but SQLite open/migration happens only when the datastore actor resolves its backend.

- [ ] **Step 7: Run datastore and backend tests**

Run:

```bash
swift test --filter WorkspaceSQLiteDatastoreActorTests
swift test --filter WorkspaceSQLiteStoreBackendFactoryTests
swift test --filter WorkspaceSQLiteStoreRecoveryTests
```

Expected:

```text
All selected tests pass.
```

- [ ] **Step 8: Commit**

```bash
git add Sources/AgentStudio/Core/State/SQLite/WorkspaceSQLiteDatastore.swift \
        Sources/AgentStudio/Core/State/SQLite/WorkspaceSQLiteDatastoreFactory.swift \
        Sources/AgentStudio/Core/State/MainActor/Persistence/WorkspaceCoreRepository.swift \
        Sources/AgentStudio/Core/State/MainActor/Persistence/WorkspaceLocalRepository.swift \
        Sources/AgentStudio/Core/State/MainActor/Persistence/WorkspaceSQLiteStoreBackend.swift \
        Sources/AgentStudio/Core/State/MainActor/Persistence/WorkspaceSQLiteStoreBackendFactory.swift \
        Sources/AgentStudio/Features/InboxNotification/State/MainActor/Persistence/InboxNotificationStore.swift \
        Tests/AgentStudioTests/Core/Stores/WorkspaceSQLiteDatastoreActorTests.swift \
        Tests/AgentStudioTests/Core/Stores/WorkspaceSQLiteStoreRecoveryTests.swift
git commit -m "feat: add sqlite datastore actor boundary"
```

---

### Task 7: Route MainActor Stores Through The Datastore

**Files:**
- Modify: `Sources/AgentStudio/Core/State/MainActor/Persistence/WorkspaceStore.swift`
- Modify: `Sources/AgentStudio/Core/State/MainActor/Persistence/WorkspaceStore+LegacySQLiteImport.swift`
- Modify: `Sources/AgentStudio/Core/State/MainActor/Persistence/RepoCacheStore.swift`
- Modify: `Sources/AgentStudio/Core/State/MainActor/Persistence/UIStateStore.swift`
- Modify: `Sources/AgentStudio/Core/State/MainActor/Persistence/SidebarCacheStore.swift`
- Modify: `Sources/AgentStudio/Features/InboxNotification/State/MainActor/Persistence/InboxNotificationStore.swift`
- Modify: `Sources/AgentStudio/App/Boot/AppDelegate.swift`
- Modify: `Sources/AgentStudio/App/Boot/AppDelegate+WorkspaceBoot.swift`
- Modify: `Sources/AgentStudio/App/Boot/AppDelegate+InboxNotificationBoot.swift`
- Modify: `Sources/AgentStudio/App/Boot/AppDelegate+Termination.swift`
- Modify: `Sources/AgentStudio/App/Boot/WorkspaceBootSequence.swift`
- Test: `Tests/AgentStudioTests/App/AppBootSequenceTests.swift`
- Test: existing store tests

**TDD ordering for this broad task:** implement this as small red/green sub-slices. Before each production edit below, add and run the failing boundary test for that slice:

```text
WorkspaceStore async restore/flush
    -> WorkspaceSQLiteStoreBridgeTests / WorkspaceSQLiteStoreRecoveryTests

RepoCacheStore, UIStateStore, SidebarCacheStore routing
    -> RepoCacheStoreSQLiteBoundaryTests
    -> UIStateStoreSQLiteBoundaryTests
    -> SidebarCacheStoreSQLiteBoundaryTests

InboxNotificationStore routing
    -> InboxNotificationStoreSQLiteBoundaryTests

AppDelegate boot and termination routing
    -> AppBootSequenceTests
    -> AppDelegatePersistenceRecoveryTests
```

Do not batch all Task 7 production edits and then add tests afterward. Each sub-slice must fail for the old direct-backend path first, then pass through `WorkspaceSQLiteDatastore`.

- [ ] **Step 1: Change `WorkspaceStore` initializer to receive datastore**

Change stored property:

```swift
private let sqliteDatastore: WorkspaceSQLiteDatastore?
```

Change initializer parameter:

```swift
sqliteDatastore: WorkspaceSQLiteDatastore? = nil
```

Remove direct `sqliteBackend` initializer use in the same pass. Tests that need SQLite should build a `WorkspaceSQLiteDatastore` through the factory or a test fixture helper. Do not keep a compatibility overload that lets new code bypass the datastore actor.

- [ ] **Step 2: Make restore async at the SQLite boundary**

Add:

```swift
func restore() async {
    if let sqliteDatastore {
        switch await restoreFromSQLite(sqliteDatastore) {
        case .restored(let recoveryEvents):
            recoveryEvents.forEach { recoveryReporter?($0) }
            await resumeUnfinishedLegacySQLiteImportKeepingCurrentSelection(sqliteDatastore)
            return
        case .uninitialized(let recoveryEvents):
            recoveryEvents.forEach { recoveryReporter?($0) }
            break
        case .unavailable(let recoveryEvents):
            recoveryEvents.forEach { recoveryReporter?($0) }
            return
        }
    }
    restoreFromLegacyJSON()
}
```

Keep synchronous `restore()` only as a JSON fallback wrapper if needed by tests:

```swift
func restore() {
    guard sqliteDatastore == nil else {
        assertionFailure("Use await restore() when SQLite datastore is enabled")
        return
    }
    restoreFromLegacyJSON()
}
```

- [ ] **Step 3: Move legacy SQLite import control flow onto datastore APIs**

Change `WorkspaceLegacySQLiteImporter`:

```text
sqliteBackend: WorkspaceSQLiteStoreBackend
    -> sqliteDatastore: WorkspaceSQLiteDatastore
```

Replace direct backend/core-repository calls:

```text
sqliteBackend.coreRepository.fetchLegacyWorkspaceImportStatus(...)
    -> await sqliteDatastore.legacyImportStatus(workspaceId:)

sqliteBackend.saveImportedLegacySnapshot(...)
    -> await sqliteDatastore.saveImportedLegacySnapshot(...)

sqliteBackend.markLegacyWorkspaceImportFailed(...)
    -> await sqliteDatastore.markLegacyWorkspaceImportFailed(...)

sqliteBackend.selectActiveWorkspace(...)
    -> await sqliteDatastore.selectActiveWorkspace(...)

sqliteBackend.hasCompletedSnapshot(...)
    -> await sqliteDatastore.hasCompletedSnapshot(...)
```

Change `sqliteBackendHasWorkspaceRows(...)`:

```text
sqliteBackend.coreRepository.fetchWorkspaces()
    -> await sqliteDatastore.inspectWorkspaceRows()
```

`WorkspaceStore+LegacySQLiteImport.swift` must not reference `WorkspaceSQLiteStoreBackend` or `WorkspaceCoreRepository` directly after this task. Add a source-boundary test that scans this file for those direct references.

When `markLegacyWorkspaceImportFailed(...)` returns `.failedToRecord`, log the returned failure and emit a testable recovery/reporting path. Do not silently swallow status-write failures; this is part of the legacy retry-control hardening.

Because `classifyLegacyFileForImport(...)` now awaits the datastore, replace the synchronous `filter` with an explicit async loop:

```swift
var pendingFiles: [LegacyFile] = []
for legacyFile in scan.loadedFiles {
    let classification = await classifyLegacyFileForImport(legacyFile, mode: mode)
    if classification.shouldImport {
        pendingFiles.append(legacyFile)
    }
}
```

- [ ] **Step 4: Make SQLite persistence async**

Add:

```swift
enum WorkspaceStoreFlushOutcome: Equatable {
    case persisted
    case failed(String)

    var succeeded: Bool {
        if case .persisted = self { return true }
        return false
    }
}

@discardableResult
func flush() async -> WorkspaceStoreFlushOutcome {
    debouncedSaveTask?.cancel()
    debouncedSaveTask = nil
    return await persistNow()
}

@discardableResult
private func persistNow() async -> WorkspaceStoreFlushOutcome {
    prePersistHook?()
    let persistedAt = Date()
    do {
        if let sqliteDatastore {
            let snapshot = WorkspacePersistenceTransformer.makeLiveSQLiteSnapshot(
                identityAtom: identityAtom,
                windowMemoryAtom: windowMemoryAtom,
                repositoryTopologyAtom: repositoryTopologyAtom,
                workspacePaneAtom: paneAtom,
                workspaceTabLayoutAtom: tabLayoutAtom,
                persistedAt: persistedAt
            )
            try await sqliteDatastore.saveWorkspaceSnapshot(snapshot)
        } else {
            try persistLegacyJSONSnapshot(persistedAt: persistedAt)
        }
        if isDirty {
            isDirty = false
            ProcessInfo.processInfo.enableSuddenTermination()
        }
        return .persisted
    } catch {
        workspaceStoreLogger.error("Failed to persist workspace: \(error.localizedDescription)")
        reportSaveFailed()
        return .failed(String(describing: error))
    }
}
```

Update debounce:

```swift
debouncedSaveTask = Task { @MainActor [weak self] in
    guard let self else { return }
    try? await self.clock.sleep(for: self.persistDebounceDuration)
    guard !Task.isCancelled else { return }
    _ = await self.persistNow()
}
```

- [ ] **Step 5: Route local UX/cache/sidebar stores through datastore methods**

Change `RepoCacheStore`, `UIStateStore`, and `SidebarCacheStore` so they receive `WorkspaceSQLiteDatastore?` instead of `WorkspaceLocalSQLiteStoreBackend?`.

Add datastore APIs with sendable payloads and legacy decisions for each local store lane:

```swift
enum WorkspaceLocalCacheLoadResult: Sendable, Equatable {
    case loaded(WorkspaceLocalCacheLoadPayload)
    case unavailable(WorkspaceSQLiteDatastoreFailure, recoveryEvents: [PersistenceRecoveryEvent])
}

struct WorkspaceLocalCacheLoadPayload: Sendable, Equatable {
    var state: WorkspaceLocalRepository.CacheStateRecord?
    var cacheLegacyDecision: WorkspaceLocalSQLiteLegacyImportDecision
    var recentTargetLegacyDecision: WorkspaceLocalSQLiteLegacyImportDecision
    var recoveryEvents: [PersistenceRecoveryEvent]
}

enum WorkspaceLocalUILoadResult: Sendable, Equatable {
    case loaded(WorkspaceLocalUILoadPayload)
    case unavailable(WorkspaceSQLiteDatastoreFailure, recoveryEvents: [PersistenceRecoveryEvent])
}

struct WorkspaceLocalUILoadPayload: Sendable, Equatable {
    var state: WorkspacePersistor.PersistableUIState?
    var legacyDecision: WorkspaceLocalSQLiteLegacyImportDecision
    var recoveryEvents: [PersistenceRecoveryEvent]
}

enum WorkspaceLocalSidebarLoadResult: Sendable, Equatable {
    case loaded(WorkspaceLocalSidebarLoadPayload)
    case unavailable(WorkspaceSQLiteDatastoreFailure, recoveryEvents: [PersistenceRecoveryEvent])
}

struct WorkspaceLocalSidebarLoadPayload: Sendable, Equatable {
    var state: WorkspacePersistor.PersistableSidebarCache?
    var legacyDecision: WorkspaceLocalSQLiteLegacyImportDecision
    var recoveryEvents: [PersistenceRecoveryEvent]
}

func loadRepoCacheState(workspaceId: UUID) async -> WorkspaceLocalCacheLoadResult
func saveRepoCacheState(_ state: WorkspaceLocalRepository.CacheStateRecord, workspaceId: UUID) async throws

func loadUIState(workspaceId: UUID) async -> WorkspaceLocalUILoadResult
func saveUIState(_ state: WorkspacePersistor.PersistableUIState, workspaceId: UUID) async throws

func loadSidebarState(workspaceId: UUID) async -> WorkspaceLocalSidebarLoadResult
func saveSidebarState(_ state: WorkspacePersistor.PersistableSidebarCache, workspaceId: UUID) async throws
```

Load methods resolve through `cachedRestoreLocalRepository(workspaceId:)`. Save methods resolve through `cachedSaveLocalRepository(workspaceId:)`. MainActor stores do not call `repository(for:)` or `restoreRepository(for:)` directly after this task.

Every load result includes `recoveryEvents: drainRecoveryEvents(workspaceId:)`, even when the open was satisfied from cache. This is what carries the event generated by the first local restore opener to whichever MainActor boot step receives it.

MainActor stores use the returned legacy decisions for the current JSON fallback/archive behavior:

```text
RepoCacheStore
    cache lane decision + local recent-target lane decision

UIStateStore
    local lane decision

SidebarCacheStore
    local lane decision
```

Do not drop replay/archive semantics while removing `WorkspaceLocalSQLiteStoreBackend`.

Add store-level tests:

```text
RepoCacheStoreSQLiteBoundaryTests.restoreUsesDatastoreActor
RepoCacheStoreSQLiteBoundaryTests.flushUsesDatastoreActor
UIStateStoreSQLiteBoundaryTests.restoreUsesDatastoreActor
UIStateStoreSQLiteBoundaryTests.flushUsesDatastoreActor
SidebarCacheStoreSQLiteBoundaryTests.restoreUsesDatastoreActor
SidebarCacheStoreSQLiteBoundaryTests.flushUsesDatastoreActor
InboxNotificationStoreSQLiteBoundaryTests.loadUsesDatastoreActor
InboxNotificationStoreSQLiteBoundaryTests.saveUsesDatastoreActor
```

The tests inject a probe datastore and assert the relevant actor API is called. They also assert legacy replay/archive decisions are honored when SQLite state is missing. They include a source-boundary assertion that these stores no longer reference `WorkspaceLocalSQLiteStoreBackend`.

- [ ] **Step 6: Route inbox notification SQLite through datastore**

Change `InboxNotificationStore` so SQLite mode receives `WorkspaceSQLiteDatastore?` plus `workspaceId` instead of `InboxNotificationSQLiteRepository?`.

Use the explicit sendable inbox snapshots added in Task 6. If implementation reveals a missing field, extend these payload types in this task before routing the store:

```swift
struct SQLiteSnapshot: Sendable, Equatable {
    var notifications: [InboxNotification]
    var collapsedGroups: Set<InboxNotificationGroupKey>
    var markLegacyImport: Bool
}

struct SQLiteLoadSnapshot: Sendable, Equatable {
    var notifications: [InboxNotification]
    var collapsedGroups: Set<InboxNotificationGroupKey>
    var hasPersistedState: Bool
    var hasMaterializedLegacyImport: Bool
}
```

Rewrite the SQLite branches:

```text
load()
    -> await datastore.loadInboxNotifications(workspaceId:)
    -> apply SQLiteLoadSnapshot on MainActor
    -> if no SQLite state and legacy import allowed, decode legacy JSON on MainActor and call datastore.saveInboxNotifications(... markLegacyImport: true)

save()/flush()
    -> capture SQLiteSnapshot on MainActor
    -> await datastore.saveInboxNotifications(snapshot, workspaceId:)
```

Remove `InboxNotificationSQLiteRepository` from `InboxNotificationStore` stored properties. The repository is actor-internal to `WorkspaceSQLiteDatastore`.

Update `AppDelegate+InboxNotificationBoot.swift`:

```text
bootLoadInboxNotificationStore(persistor:)
    -> async

makeInboxNotificationSQLiteRepository(...)
    -> delete

workspaceSQLiteDatastore?.makeInboxSQLiteBootDecision(workspaceId:)
    -> controls allowLegacyFilePersistence / allowLegacyFileImport / archive readiness

InboxNotificationStore(...)
    -> receives sqliteDatastore: workspaceSQLiteDatastore, workspaceId: workspaceId
```

Delete `workspaceLocalSQLiteStoreBackend` from `AppDelegate` unconditionally in this task. No AppDelegate boot path should keep a raw local SQLite backend.

- [ ] **Step 7: Route legacy workspace archive bookkeeping through datastore**

Change `bootArchiveLegacyWorkspaceFilesIfNeeded(persistor:)` to `async` and replace raw backend calls:

```text
workspaceSQLiteStoreBackend.hasCompletedSnapshot(...)
    -> await workspaceSQLiteDatastore?.hasCompletedSnapshot(...)

workspaceSQLiteStoreBackend.markLegacyWorkspaceCompanionImportsCompleted(...)
    -> await workspaceSQLiteDatastore?.markLegacyWorkspaceCompanionImportsCompleted(...)

workspaceSQLiteStoreBackend.markLegacyWorkspaceArchived(...)
    -> await workspaceSQLiteDatastore?.markLegacyWorkspaceArchived(...)
```

This method may still call `persistor.archiveLegacyWorkspaceFiles(...)` on MainActor because the archive operation is file-system legacy cleanup, not SQLite repository work. SQLite status reads/writes must go through `WorkspaceSQLiteDatastore`.

Add a boot-source boundary assertion:

```text
AppDelegate+WorkspaceBoot.swift must not reference workspaceSQLiteStoreBackend or WorkspaceSQLiteStoreBackend after Task 7.
```

- [ ] **Step 8: Make boot sequencing async where canonical restore runs**

Change `WorkspaceBootSequence.run`:

```swift
@MainActor
static func run(_ perform: (WorkspaceBootStep) async -> Void) async {
    for step in orderedSteps {
        await perform(step)
    }
}
```

Change `bootWorkspaceServices(...)` to `async` and await the sequence:

```swift
func bootWorkspaceServices(
    persistor: WorkspacePersistor,
    paneRuntimeBus: EventBus<RuntimeEnvelope>,
    filesystemSource: inout FilesystemGitPipeline?
) async {
    await WorkspaceBootSequence.run { [self] step in
        recordBootStep(step)
        await executeBootStep(
            step,
            persistor: persistor,
            paneRuntimeBus: paneRuntimeBus,
            filesystemSource: &filesystemSource
        )
    }
}
```

Make `executeBootStep(...)` async even though most steps remain synchronous. The canonical workspace restore step awaits `store.restore()`, and the inbox store boot step awaits `bootLoadInboxNotificationStore(persistor:)` because inbox SQLite load/save is also behind the datastore actor.

Decide the boot readiness contract explicitly in this task:

```text
required before first window:
    canonical restore
    slot seeding for restored panes
    cache/UI/inbox restore

allowed to continue after first window:
    filesystem/git/forge actor startup
    initial topology replay
    persistence observation arming after topology replay
```

Do not write a test that requires initial topology replay and persistence observation arming to complete before window creation unless the product decision is to delay window presentation behind filesystem/git/forge startup. If that decision changes, make `bootTriggerInitialTopologySync` and `bootArmPersistenceObservation` awaited steps and accept the launch-latency tradeoff explicitly.

Update `Sources/AgentStudio/App/Boot/AppDelegate.swift` so `applicationDidFinishLaunching(...)` starts an explicit launch task that awaits `bootWorkspaceServices(...)` before creating the main window. Do not create the window until canonical restore and pre-window slot seeding have completed.

- [ ] **Step 9: Update AppDelegate datastore properties and store creation**

In `AppDelegate+WorkspaceBoot.swift`, replace backend property creation:

```swift
workspaceSQLiteDatastore = makeWorkspaceSQLiteDatastore()
```

Delete `workspaceLocalSQLiteStoreBackend` as an AppDelegate-held property. Local UX, cache, and inbox notification SQLite persistence must call datastore APIs rather than receiving a raw local backend. `WorkspaceSettingsStore` remains file-backed and is not part of the SQLite datastore actor cutover.

Update store creation:

```swift
store = WorkspaceStore(
    identityAtom: atomStore.workspaceIdentity,
    windowMemoryAtom: atomStore.workspaceWindowMemory,
    repositoryTopologyAtom: atomStore.workspaceRepositoryTopology,
    paneAtom: atomStore.workspacePane,
    tabLayoutAtom: atomStore.workspaceTabLayout,
    mutationCoordinator: atomStore.workspaceMutationCoordinator,
    sqliteDatastore: workspaceSQLiteDatastore,
    recoveryReporter: { [weak self] event in
        self?.recordPersistenceRecovery(event)
    }
)
```

Update boot restore:

```swift
await store.restore()
```

- [ ] **Step 10: Rewrite boot tests in the same task**

Update `AppBootSequenceTests` in this task, not later:

```text
old source-string assertions for workspaceSQLiteStoreBackend/workspaceLocalSQLiteStoreBackend
    -> datastore-property and async-boot assertions

WorkspaceBootSequence.run tests
    -> await WorkspaceBootSequence.run

boot ordering tests
    -> prove create-main-window happens only after canonical restore, slot seeding, and cache/UI/inbox restore
    -> prove persistence observation is armed only after topology replay completes
    -> do not require filesystem/git/forge topology replay before first window unless the boot readiness contract is deliberately changed
```

- [ ] **Step 11: Update termination flush**

In `AppDelegate+Termination.swift`, change SQLite-backed store flushes to async:

```swift
if !store.flush() {
    appLogger.warning("Workspace flush failed at termination")
}
```

to:

```swift
if !(await store.flush()).succeeded {
    appLogger.warning("Workspace flush failed at termination")
}
```

Also update:

```text
try repoCacheStore.flush(for:)
try sidebarCacheStore.flush(for:)
try uiStateStore.flush(for:)
try inboxNotificationStore.flush()
```

to their async datastore-backed equivalents. `workspaceSettingsStore.flush(for:)` remains synchronous/file-backed in this addendum.

- [ ] **Step 12: Update tests from sync flush/restore to async where SQLite is enabled**

For tests that pass a SQLite backend/datastore, change:

```swift
store.restore()
#expect(store.flush())
```

to:

```swift
await store.restore()
#expect(await store.flush())
```

Tests that use JSON-only `WorkspaceStore()` may continue using the synchronous fallback until the final cleanup task.

- [ ] **Step 13: Run store and boot tests**

Run:

```bash
swift test --filter WorkspaceSQLiteStoreBridgeTests
swift test --filter WorkspaceSQLiteStoreRecoveryTests
swift test --filter RepoCacheStoreSQLiteBoundaryTests
swift test --filter UIStateStoreSQLiteBoundaryTests
swift test --filter SidebarCacheStoreSQLiteBoundaryTests
swift test --filter InboxNotificationStoreSQLiteBoundaryTests
swift test --filter WorkspaceStoreTests
swift test --filter AppBootSequenceTests
```

Expected:

```text
All selected tests pass.
```

- [ ] **Step 14: Commit**

```bash
git add Sources/AgentStudio/Core/State/MainActor/Persistence/WorkspaceStore.swift \
        Sources/AgentStudio/Core/State/MainActor/Persistence/WorkspaceStore+LegacySQLiteImport.swift \
        Sources/AgentStudio/Core/State/MainActor/Persistence/RepoCacheStore.swift \
        Sources/AgentStudio/Core/State/MainActor/Persistence/UIStateStore.swift \
        Sources/AgentStudio/Core/State/MainActor/Persistence/SidebarCacheStore.swift \
        Sources/AgentStudio/Features/InboxNotification/State/MainActor/Persistence/InboxNotificationStore.swift \
        Sources/AgentStudio/App/Boot/AppDelegate.swift \
        Sources/AgentStudio/App/Boot/AppDelegate+WorkspaceBoot.swift \
        Sources/AgentStudio/App/Boot/AppDelegate+InboxNotificationBoot.swift \
        Sources/AgentStudio/App/Boot/AppDelegate+Termination.swift \
        Sources/AgentStudio/App/Boot/WorkspaceBootSequence.swift \
        Tests/AgentStudioTests
git commit -m "refactor: route workspace persistence through datastore actor"
```

---

### Task 8: Resolve Notification Count Ownership

**Files:**
- Modify: `Sources/AgentStudio/Core/State/MainActor/Atoms/RepoCacheAtom.swift`
- Modify: `Sources/AgentStudio/Core/State/MainActor/Persistence/RepoCacheStore.swift`
- Modify: `Sources/AgentStudio/Core/State/MainActor/Persistence/WorkspaceLocalRepository.swift`
- Modify: `Sources/AgentStudio/Core/State/MainActor/Persistence/WorkspaceLocalRepository+Storage.swift`
- Modify: `Sources/AgentStudio/Core/State/MainActor/Persistence/WorkspaceLocalMigrations.swift`
- Modify: `Sources/AgentStudio/Core/State/MainActor/Persistence/WorkspacePersistor+Payloads.swift`
- Modify: `Sources/AgentStudio/Core/Views/Panes/PaneManagementContext.swift`
- Create: `Sources/AgentStudio/App/Panes/WorkspaceNotificationCountProjection.swift`
- Modify: `Sources/AgentStudio/App/Panes/WorkspaceLauncherProjector.swift`
- Test: `Tests/AgentStudioTests/App/WorkspaceNotificationCountOwnershipTests.swift`

- [ ] **Step 1: Write failing inbox-owned projection test**

Create `Tests/AgentStudioTests/App/WorkspaceNotificationCountOwnershipTests.swift`:

```swift
import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite("WorkspaceNotificationCountOwnershipTests")
struct WorkspaceNotificationCountOwnershipTests {
    @Test("pane status chips read inbox unread counts")
    func paneStatusChipsReadInboxUnreadCounts() {
        let worktreeId = UUID()
        let staleRepoCacheCount = 9
        let inboxAtom = InboxNotificationAtom()
        inboxAtom.append(
            InboxNotification(
                id: UUID(),
                timestamp: Date(timeIntervalSince1970: 1),
                kind: .unseenActivity,
                title: "Unread",
                body: "Unread notification",
                source: .pane(
                    .init(
                        paneId: UUID(),
                        worktreeId: worktreeId,
                        worktreeName: "main"
                    )
                ),
                isRead: false,
                isDismissedFromPaneInbox: false
            )
        )

        let count = WorkspaceNotificationCountProjection.unreadCount(
            worktreeId: worktreeId,
            inboxAtom: inboxAtom
        )

        #expect(count == 1)
        #expect(count != staleRepoCacheCount)
    }
}
```

- [ ] **Step 2: Run the failing test**

Run:

```bash
swift test --filter WorkspaceNotificationCountOwnershipTests
```

Expected:

```text
FAIL: cannot find WorkspaceNotificationCountProjection
```

- [ ] **Step 3: Add App-owned inbox projection helper**

Create `Sources/AgentStudio/App/Panes/WorkspaceNotificationCountProjection.swift`. This file lives in App because it depends on the feature-owned `InboxNotificationAtom`; Core files must not import the InboxNotification feature slice.

```swift
@MainActor
enum WorkspaceNotificationCountProjection {
    static func unreadCount(
        worktreeId: UUID,
        inboxAtom: InboxNotificationAtom
    ) -> Int {
        inboxAtom.unreadCount(forWorktreeId: worktreeId)
    }
}
```

- [ ] **Step 4: Route UI call sites without violating the Core -> Feature DAG**

Update `PaneManagementContext.swift` so Core receives a plain resolver closure instead of reading the feature atom:

```swift
static func project(
    paneId: UUID,
    store: WorkspaceStore,
    notificationCountForWorktree: (UUID) -> Int = { _ in 0 }
) -> Self
```

Inside Core status-chip projection:

```swift
notificationCount: notificationCountForWorktree(worktreeId)
```

Update App-owned call sites that create pane management context to pass:

```swift
notificationCountForWorktree: { worktreeId in
    WorkspaceNotificationCountProjection.unreadCount(
        worktreeId: worktreeId,
        inboxAtom: atom(\.inboxNotification)
    )
}
```

Update `WorkspaceLauncherProjector.swift`:

```swift
notificationCount: WorkspaceNotificationCountProjection.unreadCount(
    worktreeId: worktree.id,
    inboxAtom: atom(\.inboxNotification)
)
```

- [ ] **Step 5: Remove repo-cache notification persistence lane**

Remove `notificationCountByWorktreeId` from:

```text
RepoEnrichmentCacheAtom.HydrationState
RepoEnrichmentCacheAtom
RepoCacheAtom.HydrationState
RepoCacheAtom
RepoCacheStore.persistNow
WorkspaceLocalRepository.CacheStateRecord
WorkspaceLocalRepository+Storage cache insert/fetch rows
WorkspacePersistor.PersistableCacheState
```

Leave the existing SQLite table in migrations for already-created databases, but stop writing and reading it. Add a doc note in `WorkspaceLocalMigrations.swift`:

```swift
// cache_notification_count is retained for migration compatibility only.
// Unread notification counts are owned by InboxNotificationAtom and its feature store.
```

- [ ] **Step 6: Update tests that manually seeded repo-cache notification counts**

Replace synthetic `repoCache.setNotificationCount(...)` assertions with inbox atom seeding and `WorkspaceNotificationCountProjection.unreadCount(...)`.

- [ ] **Step 7: Run notification and repo-cache tests**

Run:

```bash
swift test --filter WorkspaceNotificationCountOwnershipTests
swift test --filter RepoCacheStoreTests
swift test --filter WorkspaceRepoCacheTests
swift test --filter PaneManagementContextTests
swift test --filter WorkspaceLauncherProjectorTests
```

Expected:

```text
All selected tests pass.
```

- [ ] **Step 8: Commit**

```bash
git add Sources/AgentStudio/Core/State/MainActor/Atoms/RepoCacheAtom.swift \
        Sources/AgentStudio/Core/State/MainActor/Persistence/RepoCacheStore.swift \
        Sources/AgentStudio/Core/State/MainActor/Persistence/WorkspaceLocalRepository.swift \
        Sources/AgentStudio/Core/State/MainActor/Persistence/WorkspaceLocalRepository+Storage.swift \
        Sources/AgentStudio/Core/State/MainActor/Persistence/WorkspaceLocalMigrations.swift \
        Sources/AgentStudio/Core/State/MainActor/Persistence/WorkspacePersistor+Payloads.swift \
        Sources/AgentStudio/Core/Views/Panes/PaneManagementContext.swift \
        Sources/AgentStudio/App/Panes/WorkspaceNotificationCountProjection.swift \
        Sources/AgentStudio/App/Panes/WorkspaceLauncherProjector.swift \
        Tests/AgentStudioTests
git commit -m "fix: make inbox own notification counts"
```

---

### Task 9: Strengthen Pyramid Tests And File-Backed SQLite Fixtures

**Files:**
- Modify: `Tests/AgentStudioTests/Core/Stores/WorkspaceSQLiteStoreBridgeTests.swift`
- Modify: `Tests/AgentStudioTests/Core/Stores/WorkspaceSQLiteStoreRecoveryTests.swift`
- Modify: `Tests/AgentStudioTests/App/AppBootSequenceTests.swift`
- Test: add focused helpers in existing test files

Task 9 is a hardening pass over the already-routed implementation. Do not defer behavior coverage from Tasks 4-7 until this task; those tasks must already have their red/green tests. Task 9 upgrades fixture realism, adds regression assertions that need the full cutover in place, and runs the E2E smoke gates.

- [ ] **Step 1: Replace shared local-queue multi-workspace fixtures**

In multi-workspace SQLite tests, replace:

```swift
let localQueue = try SQLiteDatabaseFactory.makeInMemoryQueue(label: "AgentStudio.sqlite.retry.local")
makeLocalRepository: { WorkspaceLocalRepository(workspaceId: $0, databaseWriter: localQueue) }
```

with file-backed per-workspace local URLs:

```swift
let tempRoot = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
makeLocalRepository: { workspaceId in
    let url = tempRoot.appending(path: "\(workspaceId.uuidString).local.sqlite")
    let pool = try SQLiteDatabaseFactory.makeFileBackedPool(
        at: url,
        label: "AgentStudio.sqlite.test.local.\(workspaceId.uuidString)"
    )
    try WorkspaceLocalMigrations.migrate(pool)
    return WorkspaceLocalRepository(workspaceId: workspaceId, databaseWriter: pool)
}
```

- [ ] **Step 2: Add cursor default synthesis assertions**

Extend stale/missing local tests with a two-tab snapshot and assert:

```swift
#expect(loaded.activeTabId == loaded.tabs.first?.id)
#expect(loaded.tabs.allSatisfy { $0.activeArrangementId == $0.arrangements.first?.id })
#expect(loaded.tabs.flatMap(\.arrangements).allSatisfy { arrangement in
    arrangement.activePaneId == arrangement.layout.paneIds.first {
        !arrangement.minimizedPaneIds.contains($0)
    } ?? arrangement.layout.paneIds.first
})
```

- [ ] **Step 3: Replace boot source-string tests with behavior tests**

For archive/import-status tests, build temp core/local SQLite files and invoke the boot helper path directly. Assert:

```swift
#expect(try coreRepository.fetchLegacyWorkspaceImportStatus(workspaceId: workspaceId)?.settingsImportedAt != nil)
#expect(try coreRepository.fetchLegacyWorkspaceImportStatus(workspaceId: workspaceId)?.localImportedAt != nil)
#expect(try coreRepository.fetchLegacyWorkspaceImportStatus(workspaceId: workspaceId)?.cacheImportedAt != nil)
#expect(try coreRepository.fetchLegacyWorkspaceImportStatus(workspaceId: workspaceId)?.archivedAt != nil)
```

- [ ] **Step 4: Run pyramid tests**

Run:

```bash
swift test --filter WorkspaceSQLiteStoreBridgeTests
swift test --filter WorkspaceSQLiteStoreRecoveryTests
swift test --filter AppBootSequenceTests
mise run test-e2e
mise run test-zmx-e2e
```

Expected:

```text
All selected tests and both E2E commands pass. If an E2E command is environment-gated, record the exact skip output.
```

- [ ] **Step 5: Commit**

```bash
git add Tests/AgentStudioTests/Core/Stores/WorkspaceSQLiteStoreBridgeTests.swift \
        Tests/AgentStudioTests/Core/Stores/WorkspaceSQLiteStoreRecoveryTests.swift \
        Tests/AgentStudioTests/App/AppBootSequenceTests.swift
git commit -m "test: strengthen sqlite recovery integration gates"
```

---

### Task 10: Final Cleanup, Docs, And Full Verification

**Files:**
- Modify: `AGENTS.md`
- Modify: `docs/architecture/atom_persistence_boundaries.md`
- Modify: `docs/architecture/component_architecture.md`
- Modify: `docs/architecture/workspace_data_architecture.md`
- Modify: `docs/architecture/README.md`
- Modify: code/tests touched by Tasks 2-9

- [ ] **Step 1: Remove temporary compatibility overloads**

Verify there is no remaining `WorkspaceStore(... sqliteBackend:)` initializer or app/test call site after Task 7. The cutover is hard: SQLite-enabled stores use `WorkspaceSQLiteDatastore`.

- [ ] **Step 2: Run stale terminology scan**

Run:

```bash
rg -n "WorkspaceFocusDerived|notificationCountByWorktreeId|UIStateStore.*editor chooser|PersistableState.*SQLite|sqliteBackend: workspaceSQLiteStoreBackend|WorkspaceSQLiteStoreBackendFactory\\(" AGENTS.md docs Sources Tests
```

Expected:

```text
No stale owner claims remain. Backend factory references remain only inside datastore factory or focused backend tests.
```

- [ ] **Step 3: Run focused SQLite test suite**

Run:

```bash
swift test --filter WorkspaceSQLite
swift test --filter RepoCacheStoreTests
swift test --filter UIStateStoreTests
swift test --filter SidebarCacheStoreTests
swift test --filter WorkspaceSettingsStoreTests
swift test --filter InboxNotificationStoreTests
```

Expected:

```text
All selected tests pass.
```

- [ ] **Step 4: Run full project verification**

Run:

```bash
git diff --check
mise run lint
mise run test
mise run test-e2e
mise run test-zmx-e2e
```

Expected:

```text
git diff --check exits 0.
mise run lint exits 0 with swiftlint reporting 0 violations.
mise run test exits 0.
mise run test-e2e exits 0 or reports an explicit environment gate.
mise run test-zmx-e2e exits 0 or reports an explicit environment gate.
```

- [ ] **Step 5: Commit**

```bash
git add AGENTS.md docs Sources Tests
git commit -m "chore: align sqlite datastore docs and tests"
```

---

## Execution Notes

- Use TDD. Do not write implementation before the failing test for that behavior exists.
- Keep commits small. Each task has its own commit.
- Do not move atoms off MainActor.
- Do not let repositories read atoms.
- Do not add one actor per SQLite table or per atom.
- If the datastore actor forces a contorted API, stop and re-open the design with evidence before continuing.

## Self-Review Checklist

- Spec coverage: Tasks 1-10 cover datastore boundary, core/local commit protocol, legacy retry status, local quarantine failure, notification-count ownership, DTO/snapshot split, and pyramid tests.
- Banned-term scan: This plan avoids vague marker terms and hand-waved edge handling. Any implementation step with code includes concrete target types and method names.
- Type consistency: The plan consistently uses `WorkspaceSQLiteDatastore`, `WorkspaceSQLiteSnapshot`, `WorkspaceSQLiteStoreBackend`, and `WorkspaceLocalSQLiteStoreBackendError.quarantineFailed`.
- Risk note: Task 7 is the broadest change because async restore/flush touches boot, termination, and many tests. If execution reveals the current boot pipeline cannot become async cleanly, pause and return with the exact boot call chain and proposed revised boundary.
