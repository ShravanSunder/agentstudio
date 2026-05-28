# Write Paths And Actors

## Status

Checkpoint C4 for the AgentStudio SQLite cutover.

This file owns how atoms, repositories, actors, and GRDB interact.

## Core Principle

Atoms remain the live observable model for SwiftUI/AppKit. SQLite is the durable
store and query/index store. The write path changes by data criticality.

```text
core data
  -> DB-first
  -> validated semantic mutation commits
  -> atoms project committed result

settings and local data
  -> atom-first
  -> UI changes immediately
  -> coalesced persistence follows
```

## Core Flow

Core mutations should commit durable rows and update atoms as one semantic
operation.

```text
user action
  -> resolver / validator builds domain mutation
  -> WorkspaceMutationCoordinator sequences the mutation
  -> WorkspaceCoreRepository writes one SQLite transaction off MainActor
  -> repository returns committed domain result
  -> coordinator applies result to @MainActor atoms
  -> UI reads atoms
```

Core invariant:

```text
one semantic workspace mutation
  = one SQLite transaction
  = one atom projection update
```

`WorkspaceMutationCoordinator` remains the cross-atom sequencing owner. It
should coordinate with a repository/transaction boundary, not let atoms write
SQLite directly.

## Migration From Observation-Driven Snapshots

The existing save path observes atom fields, debounces for 500 ms, and serializes
the whole `PersistableState`. That model must be removed for core rows.

```text
current model
  atom mutation
    -> withObservationTracking notices any persisted field
    -> debounce
    -> serialize full JSON snapshot

Step 1 core model
  validated domain mutation
    -> repository writes scoped rows in one transaction
    -> coordinator applies committed result to atoms once
```

No core atom should independently observe itself and write to SQLite. Core writes
enter through the existing validated command/coordinator path or an explicitly
named store method used during boot/import. Local UX and settings may still use
debounced writes because their loss semantics are different.

The current observation set must be dismantled by persistence boundary, not
ported as one SQLite save trigger. For example, `WorkspaceStore` currently
observes workspace identity, topology, panes, tabs, active tab, sidebar width,
and window frame together. After cutover:

```text
workspace id / name / createdAt / updatedAt
repo / worktree topology
pane / tab graph
  -> validated core repository transaction

active tab / active arrangement / active pane
drawer expansion / active drawer child
sidebar width / window frame
  -> local cursor/window writes only

editor bookmark / checkout colors / notification prefs
  -> settings writes only
```

A sidebar-width drag must not schedule a core transaction. A workspace rename
must not rewrite local cursor rows unless that same semantic command also
changes cursor state.

## Core Write Serialization

Core repositories must provide a single-writer boundary per `core.sqlite`.

```text
@MainActor coordinator
  -> builds validated mutation from current atom snapshot
  -> awaits WorkspaceCoreRepository on a non-MainActor executor
  -> repository serializes writes through GRDB DatabaseWriter.write
  -> repository returns committed domain result
  -> coordinator updates atoms on MainActor
```

There must not be two concurrent core workspace mutations racing to project
different versions of the same pane/tab graph into atoms. If implementation uses
an actor, that actor is the serialization boundary. If implementation uses a
repository queue, that queue is the serialization boundary. The spec requires
the boundary; the concrete type can follow the final code shape.

## Composed Atoms With Split Persistence

Some current atoms and domain values are composed for UI ergonomics even though
their fields land in different persistence boundaries. Step 1 may keep those
domain values composed in memory, but persistence must route by field.

Classify every state surface, but do not persist every state surface. Each
field belongs to one lifecycle lane:

```text
core graph
  -> durable workspace structure and validated semantic state

local UX memory
  -> per-workspace focus, selection, window/sidebar memory, and resettable cache
     facts

settings
  -> user preferences outside the workspace graph

runtime / presentation
  -> transient UI, keyboard, focus, pending-request, health, and display facts
  -> no SQLite write ownership in Step 1

derived read model
  -> composed UI/validator shape
  -> reads lanes, never owns persistence
```

Atom rule:

```text
write-owner atom
  -> one lifecycle
  -> one write path
  -> may own a cohesive set of related tables

derived atom / derived reader
  -> combines write-owner atoms
  -> may look like the rich domain model
  -> never owns persistence

legacy import DTO
  -> decodes old Codable JSON payloads
  -> never becomes the live SQLite write model

row projection
  -> repository-facing SQL table shape
  -> never becomes the UI read model by accident
```

Write-owner atoms are not table models. A single write-owner atom should own the
set of fields that one validated command must project coherently. SQLite can
normalize that state into many tables, but SwiftUI and command validation should
not observe table-shaped fragments for one domain operation.

Step 0 should split lifecycle-mixed atoms before SQLite lands. This includes the
obvious low-risk atoms and the pane/tab arrangement atoms that would otherwise
force repository code to route graph, cursor, and runtime fields out of one
mutable owner.

```text
ActiveWorkspaceSelectionAtom -> add
  core      -> app_workspace_selection.active_workspace_id

WorkspaceMetadataAtom -> split
  core      -> WorkspaceIdentityAtom
  local     -> WorkspaceWindowMemoryAtom

UIStateAtom -> split
  local     -> WorkspaceSidebarMemoryAtom
  runtime   -> SidebarFocusRuntimeAtom

SidebarCacheAtom -> split
  local     -> SidebarExpandedGroupAtom
  settings  -> SidebarCheckoutColorAtom

WorkspaceTabShellAtom -> split
  core      -> WorkspaceTabShellAtom
  local     -> WorkspaceTabCursorAtom

WorkspaceTabArrangementAtom -> split
  core      -> WorkspaceTabGraphAtom
  local     -> WorkspaceArrangementCursorAtom
  runtime   -> WorkspacePanePresentationAtom

WorkspacePaneAtom -> split
  core      -> WorkspacePaneGraphAtom
  local     -> WorkspaceDrawerCursorAtom

RepoCacheAtom -> split
  cache     -> RepoEnrichmentCacheAtom
  local     -> RecentWorkspaceTargetAtom

EditorChooserAtom -> split
  settings  -> EditorPreferenceAtom
  runtime   -> EditorChooserRuntimeAtom

InboxSidebarStateAtom -> split
  local     -> InboxSidebarMemoryAtom
  runtime   -> InboxSidebarRuntimeAtom

InboxNotificationPrefsAtom
  settings -> grouping, sort, bellEnabled
```

The repository layer returns enough committed domain data for the coordinator to
project the composed atom values after the core transaction. Local cursor values
are joined during boot and repaired if they reference missing core ids.

Do not split atoms solely because SQLite has multiple tables. Split atoms when
their fields have different lifecycles or write paths. For pane and arrangement
state, that condition is already true: drawer expansion, active arrangement,
active pane, active drawer child, and zoom presentation do not share the same
durability semantics as pane membership and layout rows.

Step 0 must also classify the Swift types that cross those boundaries. Rich
domain names such as `Pane`, `Drawer`, `Tab`, `PaneArrangement`, and
`DrawerView` may remain public derived read-model names, but write-owner atoms
must store explicit graph/cursor/presentation state. Legacy JSON uses explicit
`Legacy*Payload` DTOs, and future SQL repositories use explicit `*Row`
projections. Do not let one type name mean all four roles.

Terminology:

```text
cursor
  -> persisted focus/selection state that should survive relaunch
  -> active tab, active arrangement, active pane, active drawer child

presentation
  -> runtime-only display override
  -> zoomed pane and similar transient view state
```

Existing and planned derived readers should absorb the compatibility cost:

```text
WorkspacePaneGraphAtom
WorkspaceDrawerCursorAtom
  -> WorkspacePaneDerived
     -> rich Pane values for UI, validators, and command snapshots
     -> observes WorkspaceRepositoryTopologyAtom and RepoEnrichmentCacheAtom
        when rendering derived repo/worktree/display facets

WorkspaceTabShellAtom
WorkspaceTabCursorAtom
WorkspaceTabGraphAtom
WorkspaceArrangementCursorAtom
WorkspacePanePresentationAtom
  -> WorkspaceTabLayoutDerived
     -> rich Tab / PaneArrangement values for UI, validators, and command
        snapshots

WorkspaceSidebarMemoryAtom
SidebarFocusRuntimeAtom
SidebarExpandedGroupAtom
SidebarCheckoutColorAtom
  -> sidebar view models / command visibility readers
```

Derived readers are allowed to expose rich UI/domain shapes, but those names
must disclose that they are read models. A mixed value may be convenient for UI
and validators; it must not be mistaken for the storage contract.

The tab read side has one composed reader: `WorkspaceTabLayoutDerived`. The
current `WorkspaceTabLayoutAtom` wrapper should be removed or renamed during
Step 0 because it is not a write-owner atom after shell, cursor, graph,
arrangement cursor, and presentation state are split. `WorkspaceTabDerived`
should be renamed into `WorkspaceTabLayoutDerived` unless it has a separate
documented responsibility.

`WorkspaceMutationCoordinator` remains the semantic mutation sequencer after
Step 0, but its constructor dependencies change from the old mixed atoms to the
new write-owner atoms. It should receive the graph, cursor, presentation,
topology, and cache owners it needs rather than reaching through derived readers
to mutate state.

The `pane-shortcuts` and `command-bar-repo-worktree-actions` PRs are inputs to
Step 0. They merged to `main` through `54c99b91`, so Step 0 starts from a
codebase with `CommandBarSurfaceAtom`, `TransientKeyboardSurfaceAtom`,
`ArrangementPanelPresentationAtom` with placement, `KeyboardRoutingContext`,
`ActiveKeyboardSurface`, `PaneOrdinalMap`, pane-note runtime presentation,
`PaneMetadata.note`, `WorkspaceActivitySequence`, the expanded
`ActionStateSnapshot` validation shape, and RepoCacheStore autosave observation.
Shortcut/presentation facts remain runtime or derived read inputs; they do not
acquire SQLite write ownership. `PaneMetadata.note` is the exception: it is
durable pane metadata and belongs to the pane graph. Validators should receive
rich pane/tab validation facts from derived readers rather than reaching
separately into graph/cursor atoms.

The same split applies to domain models decoded from legacy JSON:

```text
Pane.drawer
  core   -> drawer identity and drawer_pane membership
  local  -> drawer.isExpanded

PaneMetadata.facets
  core   -> source repo/worktree ids, launch directory, cwd, checkout ref, tags
  derived/cache
         -> repoName, worktreeName, parentFolder, organizationName, origin,
            upstream

PaneMetadata.note
  core   -> pane note column owned by WorkspacePaneGraphAtom
  runtime
         -> PaneNotePresentation / popover draft state is not persisted

Tab
  core   -> id, name, allPaneIds, arrangements
  local  -> activeArrangementId
  none   -> zoomedPaneId

PaneArrangement
  core   -> layout, minimizedPaneIds, showsMinimizedPanes, drawerViews layout
  local  -> activePaneId, drawerViews.activeChildId
```

When one user action touches core and local state, core commits first and the
local write follows in the same coordinator task. The two databases cannot share
one ACID transaction, but the UI can apply a single composed atom projection
from the committed core result plus the intended local cursor result. If the app
crashes between the two writes, the durable graph survives and local cursor
state may be stale on relaunch.

Core deletes and topology prunes must synchronously repair in-memory cursor
atoms before the coordinator returns control to the UI. The local SQLite
reconciliation write may be part of the same async task, but the MainActor atoms
must not temporarily expose `active_pane_id`, `active_child_id`, tab membership,
or drawer expansion state that points at deleted core ids.

The Step 0 implementation must satisfy this matrix. Each row is a reviewable
write-boundary contract, not a suggestion:

| Semantic command | Write owners | Synchronous repair / projection rule | Forbidden implementation |
| --- | --- | --- | --- |
| Select tab | `WorkspaceTabCursorAtom` | selected id exists in shell; derived tab layout updates immediately | writing active tab through tab shell or tab graph |
| Create tab | `WorkspaceTabShellAtom`, `WorkspaceTabGraphAtom`, optional `WorkspaceTabCursorAtom` | shell identity, default arrangement graph, membership, and active selection project as one composed layout | merging shell identity into tab graph for command convenience |
| Rename/reorder tab | `WorkspaceTabShellAtom` | graph and cursor owners do not mutate | routing shell edits through arrangement graph |
| Insert pane | `WorkspacePaneGraphAtom`, `WorkspaceTabGraphAtom`, `WorkspaceArrangementCursorAtom`, `WorkspacePanePresentationAtom` | pane graph, layout membership, active pane cursor, and zoom reset project together | storing rich `Pane`/`Tab` directly in graph atoms, letting validators read owners separately, or leaving stale zoom |
| Reactivate pane | `WorkspacePaneGraphAtom`, `WorkspaceTabGraphAtom`, `WorkspaceArrangementCursorAtom`, `WorkspacePanePresentationAtom` | backgrounded pane residency, layout membership, active pane cursor, and zoom reset project together | treating residency as unrelated to insertion or leaving stale zoom |
| Background pane | `WorkspacePaneGraphAtom`, `WorkspaceTabGraphAtom`, `WorkspaceArrangementCursorAtom`, sometimes `WorkspaceDrawerCursorAtom`, sometimes `WorkspaceTabShellAtom`, sometimes `WorkspaceTabCursorAtom` | pane residency changes to backgrounded, layout references are removed, affected cursors repair, and empty-tab shell/cursor cleanup happens before observation | modeling this as pane-only residency or relying on local reconciliation for cursor/tab cleanup |
| Close pane | `WorkspacePaneGraphAtom`, `WorkspaceTabGraphAtom`, `WorkspaceArrangementCursorAtom`, sometimes `WorkspaceDrawerCursorAtom`, sometimes `WorkspaceTabShellAtom`, sometimes `WorkspaceTabCursorAtom` | active pane, active drawer child, drawer expansion, membership, and last-pane tab shell/cursor cleanup repair before deleted ids are observable | relying only on local DB reconciliation after a core delete or forgetting the last-pane tab cleanup path |
| Close tab | `WorkspacePaneGraphAtom`, `WorkspaceTabShellAtom`, `WorkspaceTabGraphAtom`, `WorkspaceTabCursorAtom`, `WorkspaceArrangementCursorAtom`, `WorkspaceDrawerCursorAtom`, `WorkspacePanePresentationAtom` | all panes and drawer cursors for the tab are removed, active tab moves to next/default/nil, arrangement cursor and zoom state clear before observation | shell-only tab removal or leaving pane/cursor/presentation state behind |
| Move pane across tabs | `WorkspaceTabGraphAtom`, `WorkspaceArrangementCursorAtom`, `WorkspacePanePresentationAtom` | source/destination graphs update together; both affected cursors repair synchronously; source/destination zoom clears as needed | separate visible source/destination projections or stale zoom |
| Attach drawer pane | `WorkspacePaneGraphAtom`, `WorkspaceTabGraphAtom`, `WorkspaceArrangementCursorAtom` | drawer membership/layout and active child project together | separate drawer membership table-shaped atom |
| Detach last drawer pane | `WorkspacePaneGraphAtom`, `WorkspaceTabGraphAtom`, `WorkspaceDrawerCursorAtom`, `WorkspaceArrangementCursorAtom` | drawer-view graph removes the child, reconstituted drawer preserves expansion, and active child clears synchronously | losing expansion because drawer cursor is treated as core graph state, or forgetting drawer-view graph cleanup |
| Expand drawer | `WorkspaceDrawerCursorAtom` | one atom method collapses every other drawer and toggles target before observation; `WorkspacePaneDerived` reflects the new values in the same MainActor tick | single-row writes that allow two expanded drawers in memory, or cursor changes not reflected by the derived pane value |
| Switch arrangement | `WorkspaceArrangementCursorAtom` | new arrangement's remembered active pane and active child are exposed, or deterministic defaults; derived `Tab.activeArrangement` switches immediately | storing active arrangement on `TabGraphState` or leaving old arrangement cursor values visible |
| Toggle zoom/presentation | `WorkspacePanePresentationAtom` | runtime presentation does not mutate graph/cursor/local persistence | persisting `zoomedPaneId` or placing it in arrangement cursor |
| Topology prune / hard delete | topology, affected graph owners, affected cursor owners | dangling repo/worktree/pane ids are removed or cleared before the coordinator returns | waiting for next boot/local reconciliation to clear invalid ids |
| Repo reassociation | `WorkspaceRepositoryTopologyAtom`, `WorkspacePaneGraphAtom` | topology update and orphaned-pane residency restoration project together before the command returns | updating repo/worktree topology while leaving pane residency visibly orphaned |
| Restore tab/pane from undo snapshot | `WorkspacePaneGraphAtom`, `WorkspaceTabShellAtom`, `WorkspaceTabGraphAtom`, `WorkspaceTabCursorAtom`, `WorkspaceArrangementCursorAtom`, `WorkspaceDrawerCursorAtom`, `WorkspacePanePresentationAtom` as applicable | undo restore follows the same atomicity contract as create tab, insert/reactivate pane, and drawer attach | restoring rich snapshot values into mixed atoms or showing restored shell without pane/arrangement graph |
| Build validation snapshot | derived readers only | snapshot reads composed pane/tab/topology/runtime facts from derived readers at every production call site | snapshot constructors at any call site reach into graph/cursor atoms directly instead of derived readers |

Examples:

```text
insert pane into arrangement
  -> core: arrangement layout rows + tab_pane membership
  -> local: active_pane_id for the arrangement
  -> runtime: clear zoom for the affected tab/arrangement
  -> projection: atom shows pane inserted, focused, and unzoomed

create new tab
  -> core: tab shell identity/order
  -> core: tab membership + default arrangement graph
  -> local: active_tab_id when the command selects the new tab
  -> projection: one composed Tab appears selected without merging shell
     ownership into the graph atom

detach last drawer child
  -> core: parent drawer structure and detached pane structure
  -> core: arrangement drawer-view graph removes the drawer child
  -> local: preserve prior is_expanded for the reconstituted drawer;
            repair active_child_id to NULL/default
  -> projection: atom shows detached pane and preserved drawer presentation

expand drawer
  -> local only: in one local transaction, set every other drawer in the
     workspace to is_expanded = 0, then set the target drawer to the requested
     value
  -> projection: atom preserves the existing mutual-exclusion behavior
```

## Settings Flow

Settings are small and intentional. They can update atom state immediately and
flush through a settings store with debouncing or explicit save, depending on
the owning control.

```text
preference change
  -> @MainActor atom update
  -> WorkspaceSettingsStore schedules file write
  -> sorted schema-versioned JSON writes atomically
```

## Local UX Flow

Local UX writes should prefer responsiveness over synchronous durability.

```text
interaction
  -> @MainActor atom update immediately
  -> WorkspaceLocalStore coalesces by workspace/key
  -> local.sqlite write happens off MainActor
```

If the app crashes before the latest local UX write lands, the result is stale
relaunch memory, not damaged workspace truth.

Examples:

```text
user selects a tab
  -> WorkspaceTabCursorAtom.activeTabId updates immediately
  -> WorkspaceLocalStore writes local_workspace_cursor.active_tab_id

user focuses a pane
  -> WorkspaceArrangementCursorAtom active pane state updates immediately
  -> WorkspaceLocalStore writes local_arrangement_cursor.active_pane_id

user focuses a drawer child
  -> WorkspaceArrangementCursorAtom drawer view active child updates immediately
  -> WorkspaceLocalStore writes local_arrangement_drawer_cursor.active_child_id

user expands a drawer
  -> WorkspaceDrawerCursorAtom expansion state updates immediately
  -> WorkspaceLocalStore writes local_drawer_cursor.is_expanded
```

Local UX writes coalesce for 500 ms by workspace/key, matching the existing
store debounce posture. App backgrounding, app termination, and explicit
workspace close flush pending local/settings writes before teardown.

Drawer expansion is the exception to "single row" local cursor intuition. The
current behavior allows at most one expanded drawer at a time, so expanding a
drawer is a multi-row local transaction:

```sql
UPDATE local_drawer_cursor
SET is_expanded = 0, updated_at = :now
WHERE workspace_id = :workspace_id
  AND drawer_id != :target_drawer_id;

INSERT INTO local_drawer_cursor (...)
VALUES (...)
ON CONFLICT(drawer_id) DO UPDATE SET
    is_expanded = :target_is_expanded,
    updated_at = :now;
```

The exact SQL can change, but the transactional behavior must not: there is no
relaunch state where two drawers are marked expanded because one row flushed and
the other did not.

The same atomicity applies in memory. `WorkspaceDrawerCursorAtom` exposes one
semantic method for drawer expansion; that method collapses every other drawer
cursor in the workspace and then updates the requested drawer before observers
see the new state.

## Cache Flow

Cache writes are rebuildable and should not block core UI interactions.

```text
runtime/git/provider fact
  -> event bus fact
  -> WorkspaceCacheCoordinator updates cache atom
  -> WorkspaceLocalStore writes cache_* row(s)
  -> failed write reports and can rebuild later
```

Cache payload decode failures are table-level rebuild events, not local database
corruption. A bad `cache_repo_enrichment.payload_json` row can be deleted and
rebuilt from runtime/git/provider facts without touching `local_*` UX rows.

## Notification Inbox Flow

Notification history is local UX data, but it has domain behavior that must move
with the live persistence owner after `InboxNotificationStore` dissolves.

```text
append notification
  -> compute claim coalescence using the same rules as InboxNotificationAtom
  -> upsert/replace the matched local_notification_inbox_item row
  -> enforce AppPolicies.InboxNotification.maxRetained in the same local
     transaction by deleting the oldest overflow rows
  -> project the resulting rows/outcome into InboxNotificationAtom

mark read / dismiss / clear
  -> update affected local_notification_inbox_item rows
  -> project the resulting atom state
```

The claim columns in `local_notification_inbox_item` are lookup columns for the
repository; they are not a simple unique key because the current coalescence rule
also depends on lane merge policy, activity session, and read/dismiss state.
Repository tests own the equivalence between SQLite upsert behavior and
`InboxNotificationAtom.upsertByClaim`.

## Code Placement

Common SQLite mechanics belong in Infrastructure. Product schemas and
repositories do not.

```text
Sources/AgentStudio/Infrastructure/SQLite/
  SQLiteDatabaseFactory
  SQLiteMigrationRunner
  SQLiteSidecarQuarantine
  SQLiteErrorClassifier
  test helpers with in-memory / temporary-file databases

Sources/AgentStudio/Core/State/MainActor/Persistence/
  WorkspaceCoreStore
  WorkspaceCoreRepository
  WorkspaceSettingsStore
  WorkspaceLocalStore
  WorkspaceLocalRepository
  legacy JSON importers

Sources/AgentStudio/Features/<Feature>/State/MainActor/Persistence/
  feature-specific adapters when a feature owns a local/settings slice
```

Infrastructure should not know about `Pane`, `Tab`, `Repo`, `InboxNotification`,
or `RecentWorkspaceTarget`. It should know how to open a database, apply
migrations, set pragmas, and quarantine SQLite sidecars.

Existing persistence wrappers get explicit dispositions:

```text
WorkspaceStore
  -> stops owning whole-workspace JSON snapshots
  -> becomes boot/flush orchestration over core/settings/local stores

WorkspacePersistor
  -> legacy importer/quarantine helper during cutover
  -> removed as the live workspace persistence owner after hard cutover

WorkspacePersistor+Payloads
  -> legacy import DTOs during cutover
  -> removed or narrowed once JSON import code is deleted

WorkspacePersistenceTransformer
  -> split into legacy importer and boot composer responsibilities
  -> no longer performs whole-state prune-on-save

RepoCacheStore
  -> routes current cache rows through WorkspaceLocalStore / Repository
  -> current code now observes RepoCacheAtom directly with debounce; Step 0 must
     split that observer so cache enrichment and recent targets can route to
     their own local write owners without reintroducing a mixed cache atom

UIStateStore
  -> splits editor preference to settings and sidebar memory to local.sqlite
  -> current dual observation of UIStateAtom plus EditorChooserAtom is split
     into separate local/settings flush paths
  -> EditorChooserAtom observation moves to WorkspaceSettingsStore

SidebarCacheStore
  -> absorbed by WorkspaceSettingsStore + WorkspaceLocalStore
     checkoutColors       -> settings.json
     expandedGroups       -> local_sidebar_expanded_group

InboxNotificationStore
  -> importer for current v3 payload
     prefs                -> settings.json
     notifications        -> local_notification_inbox_item
     collapsedGroups      -> local_notification_inbox_collapsed_group
  -> ceases to be the live persistence owner after cutover; live writes route
     through WorkspaceSettingsStore and WorkspaceLocalStore

CommandBarState
  -> keeps existing UserDefaults recents in Step 1
  -> when migrated, direct UserDefaults writes move behind a root local store

URLHistoryService
  -> keeps existing UserDefaults history/favorites in Step 1
  -> future migration must preserve cap/retention/dedup semantics

WebviewPaneController / WKWebsiteDataStore.default()
  -> keeps WebKit website data framework-managed in Step 1
  -> future webview audit decides reset/export controls and whether an
     app-owned website data boundary is needed

SurfaceManager
  -> keeps surface-checkpoint.json as rebuildable runtime checkpoint in Step 1
  -> decode failure remains log-and-ignore unless a future runtime checkpoint
     migration gives the file a schema version

MainWindowController
  -> stops writing legacy global windowFrame UserDefaults after local window
     state is live for the active workspace
```

## GRDB Usage Rules

Use GRDB primitives deliberately:

```text
DatabaseMigrator
  owns migration identifiers and schema evolution

DatabasePool
  preferred for file-backed app databases
  enables concurrent reads with serialized writes using WAL

DatabaseQueue
  useful for tests, in-memory stores, and very small single-connection cases

DatabaseWriter.write
  write API for transactions
  the core/local repositories call this from non-MainActor contexts

ValueObservation
  read-side query observation only
  not a write API
```

Do not drive core workspace UI through `ValueObservation` in Step 1. The app
already has observable atoms as the UI read model.

Good future `ValueObservation` uses:

- visible session search results
- active session summaries
- recent sessions for a selected worktree
- cost/token aggregates
- cache-backed count rollups if a surface becomes database-query-backed

Not a Step 1 pattern:

```text
SQLite row changed
  -> ValueObservation
  -> rewrite WorkspacePaneDerived / WorkspaceTabLayoutDerived
```

Step 1 pattern:

```text
domain mutation
  -> explicit GRDB transaction
  -> explicit atom projection update
```

## SQLite Capability Contract

Step 1 must be explicit about which SQLite extensions are required.

```text
Required for Step 1 core/local:
  foreign keys
  WAL for file-backed databases
  transactions
  ordinary indexes / unique constraints
  busy_timeout=2000 ms for short writer contention
  synchronous=NORMAL for WAL-backed app databases

Allowed but opaque in Step 1:
  JSON stored as TEXT payload columns

Required later for session search:
  FTS5

Not required by Step 1:
  JSON1 queries such as json_extract(...)
```

JSON policy:

```text
payload_json / window_frame_json
  -> may store Codable payloads as TEXT
  -> may round-trip through Swift Codable
  -> must not be queried for product behavior in Step 1

if a JSON field becomes queryable
  -> promote it to a real column in a migration
  -> or explicitly require JSON1 and add capability tests
```

Search policy:

```text
core/local current-data migration
  -> no FTS tables

future session-index migration
  -> FTS5 virtual table
  -> capability smoke test creates and queries fts5
```

The migration test harness must verify capabilities against the same SQLite
library used by GRDB, not only the shell `sqlite3` binary.

`auto_vacuum` and `page_size` are not Step 1 behavioral requirements. If a
future migration pins them, it must do so before tables are created and add a
file-backed migration test.
