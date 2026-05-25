# Test Checkpoints

## Status

Checkpoint C6 for the AgentStudio SQLite cutover.

This file owns the TDD gates for the migration and repository work.

## Migration TDD Contract

SQLite implementation starts with migration tests, not app UI tests.

```text
test target
  -> open temporary SQLite database
  -> run DatabaseMigrator
  -> assert expected tables, indexes, FKs, virtual tables, and pragmas
  -> insert invalid rows to prove constraints reject impossible state
  -> insert valid rows to prove round-trip mapping
```

Use in-memory `DatabaseQueue` for pure schema/constraint tests when possible.
Use temporary file-backed `DatabasePool` for WAL, sidecar quarantine, and
concurrent read/write behavior.

Every migration that creates or changes tables needs a focused test before its
repository code lands.

## Step 0 Atom Boundary Tests

- ActiveWorkspaceSelectionAtom can update active_workspace_id without hydrating
  or mutating a WorkspaceIdentityAtom
- workspace identity can mutate without scheduling local window/sidebar writes
- sidebar width and window frame can mutate without scheduling core workspace
  writes
- sidebar filter/surface/collapse memory can mutate without changing runtime
  sidebar focus
- checkout color settings can mutate without rewriting local expanded groups
- editor bookmark persists through the settings path while editor chooser
  open-pane and available-target state remains runtime-only
- inbox collapsed groups persist through the local path while pendingFilter
  remains runtime-only
- active tab cursor can be tested independently from tab shell ordering if
  `WorkspaceCursorAtom` lands before SQLite
- pane graph mutations can run without writing drawer expansion cursor state
- pane metadata display facets can be derived from topology/cache without
  requiring the pane graph atom to own repo/worktree names or remote labels
- drawer expansion cursor mutations can run without writing pane/drawer
  membership graph state
- arrangement graph mutations can run without writing active arrangement,
  active pane, or active drawer child cursor state unless the same semantic
  command explicitly changes focus
- zoom/presentation state resets independently from persisted arrangement graph
  and local arrangement cursor state
- repo enrichment cache can reset without deleting recent workspace targets
- pane/tab arrangement composed read models still expose the same command
  validation inputs after graph/cursor/runtime atom splits
- mixed domain structs are classified as write-owner state, derived read model,
  row projection, or legacy import DTO before SQLite repositories land
- any renamed/split Pane, Drawer, Tab, PaneArrangement, or DrawerView role keeps
  explicit tests proving old UI/validator behavior still reads through the
  derived read model
- lifecycle-grouped atoms are preserved: creating a pane may project pane,
  content, tag, drawer, and drawer membership changes through one pane graph
  write owner instead of table-shaped atoms
- WorkspaceTabGraphAtom owns tab_pane plus arrangement/layout rows, while
  WorkspaceTabShellAtom owns shell identity/order only

## Core Tests

- fresh core database runs all migrations
- migration identifiers are stable and run once
- foreign keys are enabled
- WAL mode is enabled for file-backed databases
- existing workspace state JSON imports once into core rows
- multiple legacy workspace state JSON files import when the core database is
  empty, without adding a workspace picker in Step 1
- legacy import routes embedded cursor fields to local rows:
  activeTabId, activeArrangementId, activePaneId, activeChildId, drawer
  isExpanded
- legacy import tolerates pre-DrawerView JSON where Drawer.activePaneId exists
  and routes the value to local drawer-child cursor state when resolvable
- unsupported legacy JSON schemaVersion values are reported and quarantined as
  unsupported legacy data, not silently interpreted as v1
- partial legacy import resumes if the app crashes after core rows commit but
  before settings/local/cache companion files import
- legacy import sets deterministic active workspace selection from the newest
  valid canonical JSON mtime
- legacy import breaks active-workspace mtime ties by lexicographic workspace UUID
- NULL or invalid active workspace selection falls back to newest workspace row
- existing JSON is not re-imported over existing core rows
- successfully imported legacy JSON files move to `legacy-imported/`
- legacy JSON files move only after core/settings/local imports for that
  workspace all succeed
- corrupt JSON is quarantined and does not overwrite valid SQLite state
- workspace metadata round trips
- app workspace selection round trips
- watched paths round trip
- repos and worktrees round trip with stable UUIDs and stable keys
- unavailable repo ids round trip
- panes round trip through decomposed pane/content/drawer/tag rows
- PaneMetadata durable source/cwd/tag fields round trip without storing
  repoName, worktreeName, origin, upstream, organizationName, or parentFolder as
  core pane columns
- tabs round trip through shell, membership, arrangement, layout, and
  drawer-view rows
- every arrangement layout/drawer-view pane row has matching tab_pane
  membership for the owning tab
- drawer-view row layout rejects the same pane appearing in both top and bottom
  rows
- drawer view `row_split_ratio` round trips
- drawer grid layout is treated as the Step 1 two-row top/bottom model
- schema rejects multiple drawers for one parent pane and one child pane in
  multiple drawers
- validators reject the same pane appearing in both the main arrangement layout
  and a drawer view for that arrangement
- one pane title change writes only pane-related rows
- one tab arrangement change writes only that tab's arrangement subtree
- tab/pane/layout reorders do not violate `UNIQUE(..., sort_index)` midway
- repo/worktree reassociation reconciles changed worktree rows in one
  transaction without transient stable-key uniqueness failures
- legacy transformer prune-on-save behavior is replaced by FK cascades,
  validator rejection, and hydrate-time local cursor reconciliation
- core corruption quarantines DB, WAL, and SHM together

## Settings Tests

- missing settings file produces defaults
- existing UI/sidebar/inbox preference JSON imports into settings file
- settings file is pretty-printed and sorted
- settings unknown keys are stripped unless a future schema explicitly preserves
  opaque keys
- corrupt settings file is quarantined and reset without touching core/local
- checkout colors round trip
- notification preferences round trip
- editor bookmark round trips
- editor chooser open pane and available targets are not written to settings

## Local Tests

- fresh local database runs all migrations
- local UX state imports from current UI/sidebar/inbox JSON
- fresh local database seeds deterministic cursor defaults from the core graph
- active tab round trips through local cursor rows
- active arrangement round trips through local cursor rows
- active pane round trips through local cursor rows
- active drawer child round trips through local cursor rows
- active drawer child is scoped by arrangement id plus drawer id
- drawer expanded state round trips through local cursor rows
- legacy Drawer.isExpanded imports to local_drawer_cursor, not the core drawer
  row
- expanding a drawer writes the target drawer and collapses other drawer cursor
  rows in one local transaction
- expanding a drawer synchronously collapses other drawer cursor atoms in memory
  before observers see the mutation
- detaching the last drawer child preserves the drawer expansion cursor while
  repairing the active drawer child cursor
- zoomed pane state is not persisted and hydrates as nil
- insert-pane mutations that also focus the inserted pane commit core layout
  rows first, then local active-pane cursor state
- local UX writes are coalesced and do not block core writes
- local UX writes flush on app background, termination, and workspace close
- missing/corrupt local cursor rows fall back to deterministic first/default
  rows from the core graph
- recent workspace targets round trip
- notification inbox items round trip
- inbox sidebar pendingFilter is not persisted; collapsed groups are persisted
- notification claim coalescence in SQLite matches InboxNotificationAtom
  coalescence behavior
- notification retention cap deletes oldest overflow rows in the same local
  transaction as append/upsert
- sidebar expanded groups round trip
- repo enrichment round trips
- worktree enrichment round trips
- pull request counts round trip
- notification counts round trip
- deleting cache_* rows preserves local_* rows
- bad cache_* payload rows rebuild the affected cache table/row family without
  quarantining the whole local database
- local reconciliation prunes copied core ids after core topology deletes
- core deletes synchronously clear dangling in-memory cursor ids before the UI
  observes the completed user action
- local reconciliation runs after core delete/topology-prune mutations before
  the user action is considered settled
- deleting local.sqlite does not delete core rows or settings
- local corruption quarantines only local DB sidecars
- window frame restore has only one live source after cutover; local.sqlite
  replaces the existing UserDefaults path
- legacy global windowFrame UserDefaults is not written after local window state
  becomes live

## Deferred Persistence Surface Tests

These are not Step 1 SQLite migrations, but the spec pins their current loss
semantics so a later migration can write targeted tests.

- CommandBarState recents keep the current 8-item cap until a root local store
  replaces direct UserDefaults writes
- URLHistoryService keeps the current 14-day retention, 100-entry cap,
  URL de-duplication, and favorites behavior until a future audit moves it
- SurfaceManager checkpoint decode failure remains log-and-ignore while the file
  is classified as rebuildable runtime state
- WebKit website data remains framework-managed in Step 1 and is covered by a
  future webview persistence/reset audit rather than SQLite migration tests
- PaneInboxPresentationAtom filter modes are runtime-only in Step 1
- Bridge ReviewState.viewedFiles is runtime-only in Step 1

## Integration Tests

- app relaunch restores the same repos, worktrees, panes, and tabs from core
- app relaunch restores active workspace selection from core
- app relaunch restores active tab/pane/arrangement from local when present
- app relaunch restores settings and local UX memory when present
- app relaunch survives missing local database
- deleting the active workspace selects a deterministic remaining workspace or
  falls back to empty/welcome state when none remain
- workflow/session pointer rows survive cache rebuild once those tables exist
- runtime-only atoms are not persisted

## Documentation Checkpoints

- AGENTS.md component table reflects the implemented atom/store split
- architecture docs reflect write-owner atoms, derived readers, and the
  core/settings/local persistence boundaries
- SQLite checkpoint docs use the final atom/store names and migration ids
- no current docs describe atoms as one-to-one SQL table models

## Capability Tests

- GRDB-backed connection enables foreign keys
- file-backed GRDB database uses WAL where required
- FTS5 capability smoke test passes before session search migrations land
- JSON payload columns round-trip as text without relying on JSON1
- if JSON1 ever becomes required, the same GRDB-backed connection proves
  `json_extract(...)` works

## Non-Goals

- Do not store the whole workspace as one SQLite blob.
- Do not store all panes as one SQLite blob.
- Do not store all tabs as one SQLite blob.
- Do not keep JSON and SQLite as peer sources of truth.
- Do not store full Claude Code or Codex transcripts.
- Do not store large provider tool outputs.
- Do not introduce DuckDB in Step 1.
- Do not redesign the final session UI in this step.
