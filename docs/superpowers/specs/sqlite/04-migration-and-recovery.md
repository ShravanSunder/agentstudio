# Migration And Recovery

## Status

Checkpoint C5 for the AgentStudio SQLite cutover.

This file owns boot, import, hard cutover, deletion, and corruption handling.

## Step Order

```text
Step 0
  atom boundary prep for lifecycle-mixed write owners

Step 1A
  core.sqlite migrations and current durable workspace rows

Step 1B
  per-workspace settings file

Step 1C
  per-workspace local.sqlite with local_* and cache_* tables

Later
  local.sqlite index_* tables for provider session discovery/search
  core.sqlite session_pointer/workflow/worker tables when the product surface
  needs durable curation
```

Schema references:

```text
core rows      -> 01-core-workspace-schema.md
local rows     -> 02-local-ux-and-cache-schema.md
settings file  -> 03-settings-json.md
write paths    -> 05-write-paths-and-actors.md
tests          -> 06-test-checkpoints.md
```

## Step 0: Atom Boundary Prep

Land this before SQLite repositories. Atoms should not mirror individual SQL
tables one-for-one, but write-owner atoms should mirror a cohesive table group
with one lifecycle and one write path. Derived atoms/readers compose those
write-owner atoms back into the richer UI/domain shapes.

```text
split first
  WorkspaceMetadataAtom
    -> WorkspaceIdentityAtom       core identity
    -> WorkspaceWindowMemoryAtom   local window/sidebar memory

  UIStateAtom
    -> WorkspaceSidebarMemoryAtom  local filter/surface/collapse memory
    -> SidebarFocusRuntimeAtom     runtime sidebar focus

  SidebarCacheAtom
    -> SidebarExpandedGroupAtom    local expanded group memory
    -> SidebarCheckoutColorAtom    settings checkout colors

  EditorChooserAtom
    -> EditorPreferenceAtom        settings bookmark
    -> EditorChooserRuntimeAtom    open pane + target discovery

  InboxSidebarStateAtom
    -> InboxSidebarMemoryAtom      collapsed groups
    -> InboxSidebarRuntimeAtom     pending filter handoff

split before SQLite repositories
  WorkspaceTabShellAtom
    -> WorkspaceTabShellAtom       core tab shells
    -> WorkspaceCursorAtom         active workspace/tab cursor

  WorkspacePaneAtom
    -> WorkspacePaneGraphAtom      core pane/drawer membership graph
    -> WorkspaceDrawerCursorAtom   local drawer expansion cursor

  WorkspaceTabArrangementAtom
    -> WorkspaceArrangementGraphAtom     core tab/arrangement/layout graph
    -> WorkspaceArrangementCursorAtom    local active arrangement/pane/child
    -> WorkspacePanePresentationAtom     runtime zoom/presentation state

  RepoCacheAtom
    -> RepoEnrichmentCacheAtom           cache_* rebuildable summaries
    -> RecentWorkspaceTargetAtom         local recent target history
```

Keep composed read models where they make the UI and command validation easier.
The Step 0 split should not delete the rich pane/tab values from the UI surface;
it should move graph, cursor, and runtime ownership into separate atoms while
retaining derived/composed readers for command validation and views. This keeps
the SQLite repository work honest: graph repositories do not need to special-case
local cursor fields, and local stores do not need to understand durable layout
membership.

Step 0 does not need to split atoms that already have one lifecycle:

```text
WorkspaceRepositoryTopologyAtom     core graph
InboxNotificationAtom               local notification rows + derived count
InboxNotificationPrefsAtom          settings
TerminalActivityAtom                runtime
WindowLifecycleAtom                 runtime
AppLifecycleAtom                    runtime
SessionRuntimeAtom                  runtime
ManagementLayerAtom                 runtime
CommandBarSurfaceAtom               runtime
TransientKeyboardSurfaceAtom        runtime
WorkspaceFocusOwnerAtom             runtime
AttendedPaneAtom                    runtime/derived
WelcomeAtom                         runtime
PaneFilesystemProjectionAtom        runtime projection
```

## Legacy Codable Import Contract

Legacy workspace files are decoded through the current Codable domain types, but
those Codable encoders are not the live persistence contract after cutover.

```text
legacy import only
  -> WorkspacePersistor.PersistableState
  -> Pane / Drawer / Tab / PaneArrangement / DrawerView Codable
  -> field-routed into core.sqlite + settings.json + local.sqlite

normal operation after cutover
  -> repository row reads/writes
  -> no whole-workspace Codable snapshot save
```

Cursor fields embedded inside legacy Codable structures must be extracted to
local rows during import, not folded into core rows:

```text
PersistableState.activeTabId
  -> local_workspace_cursor.active_tab_id

Tab.activeArrangementId
  -> local_tab_cursor.active_arrangement_id

PaneArrangement.activePaneId
  -> local_arrangement_cursor.active_pane_id

DrawerView.activeChildId
  -> local_arrangement_drawer_cursor.active_child_id

Drawer.isExpanded
  -> local_drawer_cursor.is_expanded

PaneMetadata.facets
  -> core pane source/cwd/tag fields where durable
  -> derived/cache display facets are not imported as core columns

Tab.zoomedPaneId
  -> not present in legacy JSON; hydrate as nil
```

## Step 1A: Core Migration System And Core Rows

Land this before session indexing work.

- add GRDB.swift dependency
- add shared SQLite infrastructure for opening databases and running migrations
- create `<AppDataPaths.rootDirectory()>/core.sqlite`
- run migrations through GRDB `DatabaseMigrator`
- enable foreign keys
- choose `DatabasePool` for file-backed databases so future observations and
  background reads do not block writes; `DatabaseQueue` remains useful for tests
  or tiny in-memory harnesses
- import every existing `*.workspace.state.json` when no core rows exist
- resume any incomplete legacy companion-file import recorded in
  `legacy_workspace_import_status`
- set `app_workspace_selection.active_workspace_id` during legacy import
- write core product mutations as row-scoped transactions
- do not serialize the whole workspace into one SQLite blob
- quarantine corrupt JSON instead of allowing it to overwrite valid SQLite rows
- prove relaunch restores repos, worktrees, panes, and tabs

Step 1 may store multiple `workspace` rows in `core.sqlite`, but it does not add
a multi-workspace picker or change product UX. The importer preserves every
legacy workspace file it can decode; the app may still choose a single active
workspace for boot until workspace-switching UI exists.

The active workspace is still a real data model concern. Step 1 must persist a
single active workspace id in `core.sqlite`; when bootstrapping from legacy JSON,
choose the most recently modified valid `*.workspace.state.json` file as the
initial active workspace. Ties break by lexicographic workspace UUID. Future
workspace-switching UI can update the same row.

If `app_workspace_selection.active_workspace_id` is NULL or points at a missing
workspace row, boot deterministically selects the most recently updated
workspace row, breaking ties by lexicographic workspace UUID. If no workspace
rows exist, the app shows the empty/welcome state.

Legacy JSON archival is not part of Step 1A alone. A workspace's legacy files can
move to `legacy-imported/` only after core rows, settings JSON, and local SQLite
rows for that same workspace have all imported successfully.

## Step 1B: Settings File Extraction

Create `<workspace-id>.settings.json` and move intentional user preferences out
of the old workspace JSON files.

- editor chooser bookmarked editor id
- sidebar checkout colors
- notification inbox grouping preference
- notification inbox sort preference
- notification inbox bell preference

The settings file is schema-versioned and sorted/pretty-printed. It should stay
small enough to edit by hand.

## Step 1C: Local Database For UX Memory And Current Cache

Create `<workspace-id>.local.sqlite` and move lower-criticality local state plus
current cache data.

Local UX memory:

- active tab, active arrangement, active pane, drawer active child
- drawer expanded state
- window frame and sidebar width
- sidebar filter text and visibility
- sidebar collapsed state
- selected sidebar surface
- expanded sidebar groups
- recent workspace targets
- notification inbox history
- notification inbox collapsed groups

Transient local runtime state:

- zoomed pane resets to nil on hydrate and is not imported

Current cache:

- repo enrichment
- worktree enrichment
- pull request counts
- notification counts
- cache source revision
- cache last rebuilt timestamp

## Loading Rule

Load the shell from core and settings/local summaries. Do not load all future
session history.

```text
boot
  -> open AppDataPaths.rootDirectory()/core.sqlite
  -> run core migrations
  -> if core has no workspace rows, run the one-time legacy import scan over
     non-archived workspace.state.json files
  -> resume incomplete legacy companion imports from legacy_workspace_import_status
  -> read or repair app_workspace_selection.active_workspace_id
  -> restore core workspace/repo/worktree/pane/tab rows for the active workspace
  -> open <workspace-id>.settings.json
  -> restore settings-backed atoms/preferences
  -> open <workspace-id>.local.sqlite
  -> run local migrations
  -> restore local UX memory, cursor rows, and current cache summaries
  -> compose Tab / PaneArrangement domain values:
       core tab_shell + tab_pane + tab_arrangement + layout rows
       local_workspace_cursor.active_tab_id
       local_tab_cursor.active_arrangement_id
       local_arrangement_cursor.active_pane_id
       local_arrangement_drawer_cursor.active_child_id
       local_drawer_cursor.is_expanded
       zoomedPaneId = nil
  -> if any local cursor id is unresolved against core ids,
     reset it to the deterministic local default
  -> start runtime actors and background cache/session index refresh
```

Normal boot after successful import does not scan legacy JSON files. Legacy
JSON scanning is only a migration/recovery path when `core.sqlite` has no
workspace rows or an incomplete import status says a companion import must
resume.

Load into memory:

- visible workspace metadata
- repo/worktree structure for the workspace
- visible panes/tabs/layouts
- current sidebar/UI state
- current notification inbox page
- current cache summaries needed by visible UI
- future visible workflow/worker/session pointer summaries

Query on demand:

- full notification history pages
- future session search results
- future all-session history
- future cost/token aggregates
- future provider transcript scan state

Never copy into AgentStudio storage wholesale:

- Claude/Codex transcript JSONL bodies
- command output bodies
- large tool results
- large diffs

## Workspace Deletion Order

Workspace deletion spans three files and cannot be one ACID transaction.

```text
1. close the workspace local DatabasePool
2. in core.sqlite, if deleting the active workspace, update
   app_workspace_selection.active_workspace_id to the newest remaining
   workspace row, or NULL if none remains
3. in the same core transaction, DELETE FROM workspace WHERE id = ? and commit
4. delete <workspace-id>.settings.json
5. delete <workspace-id>.local.sqlite, -wal, and -shm
6. report any orphaned settings/local files through PersistenceRecoveryReporter
   and log their absolute paths for later cleanup
```

After step 3 succeeds, core is authoritative that the workspace no longer
exists. If file deletion fails, the leftover settings/local files are orphans and
must not resurrect the workspace.

## Recovery Rules

### Core SQLite Corruption

```text
1. report through PersistenceRecoveryReporter
2. close the core DatabasePool
3. quarantine core.sqlite and sidecars together:
     core.sqlite
     core.sqlite-wal
     core.sqlite-shm
4. try one-time import from non-archived workspace.state.json files if present
5. if no import source exists, boot empty only after reporting destructive
   recovery
```

Core recovery must not delete settings files or local databases unless the user
deletes the workspace.

Core quarantine recovery does not scan `legacy-imported/`. After successful
archival, legacy files are no longer authoritative recovery sources.

### Settings Corruption

```text
1. quarantine <workspace-id>.settings.json
2. restore default settings
3. never modify core.sqlite
4. never delete local.sqlite
```

### Local SQLite Corruption

```text
1. report through PersistenceRecoveryReporter
2. close the workspace local DatabasePool
3. quarantine <workspace-id>.local.sqlite and sidecars together
4. recreate migrations
5. restore local defaults:
     active_tab_id              -> first tab_shell by sort_index
     active_arrangement_id      -> is_default arrangement, else first by sort_index
     active_pane_id             -> first arrangement_layout_pane by sort_index
     active_child_id            -> first drawer_view_layout_pane by sort_index,
                                    else first drawer_pane by sort_index
     drawer is_expanded         -> false
     zoomedPaneId               -> nil
6. rebuild cache_* and future index_* rows progressively
```

Local recovery may lose relaunch memory, notification history, recent targets,
cache rows, and future session index rows. It must never reset core workspace
rows or settings.

Table-level cache/index rebuild is less severe than local database corruption.
If a `cache_*` or future `index_*` payload row cannot decode but the SQLite file
is otherwise readable, delete and rebuild only the affected rebuildable table or
row family. Do not quarantine the whole local database, and do not delete
`local_*` UX memory, recent targets, or notification history for a cache payload
decode failure.

### Legacy JSON Corruption During Import

Existing quarantine behavior remains the model:

```text
corrupt legacy JSON
  -> quarantine corrupt file
  -> do not import it over valid SQLite
  -> report recovery event
```

Once SQLite exists and has valid rows, legacy JSON is never authoritative again.

The old `WorkspacePersistenceTransformer` save-time pruning behavior disappears
with whole-snapshot saves. After cutover, pane/tab self-healing is split across:

```text
hydrate
  -> local cursor reconciliation resets stale copied ids to deterministic
     defaults

core mutation
  -> SQLite foreign keys cascade hard deletes
  -> command validators/repository transactions reject orphan inserts

cache/index rebuild
  -> copied core ids are pruned by local reconciliation after core topology
     changes
```

### Legacy JSON After Successful Import

Successful import is a hard cutover.

```text
<workspace-id>.workspace.state.json
<workspace-id>.workspace.cache.json
<workspace-id>.workspace.ui.json
<workspace-id>.workspace.sidebar-cache.json
<workspace-id>.notification-inbox.json
  -> workspaces/legacy-imported/<timestamp>/<same filename>
```

The old files must not remain beside live SQLite/settings files. This prevents
accidental stale re-import and makes manual debugging honest: after cutover, the
live sources are `core.sqlite`, `<workspace-id>.settings.json`, and
`<workspace-id>.local.sqlite`.

Archival is per-workspace and all-or-nothing across the current legacy file
family. Do not archive a workspace's companion JSON files after only core import.
The move happens only after:

```text
workspace.state.json
  -> core.sqlite rows committed
  -> legacy_workspace_import_status.core_imported_at set

workspace.ui.json + workspace.sidebar-cache.json + notification-inbox.json
  -> settings.json committed
  -> local.sqlite local_* rows committed
  -> legacy_workspace_import_status.settings_imported_at set
  -> legacy_workspace_import_status.local_imported_at set

workspace.cache.json
  -> local.sqlite cache_* rows committed
  -> legacy_workspace_import_status.cache_imported_at set

all companion files archived
  -> legacy_workspace_import_status.archived_at set
```

## Migration Rules

Migration support is the point of this cutover.

```text
Step 1 core migrations
  001_create_workspace
  002_create_repo_worktree_topology
  003_create_panes
  004_create_tabs_and_arrangements

Reserved future core migrations
  005_create_workflows_and_session_pointers

Step 1 local migrations
  001_create_local_ux_memory
  002_create_current_cache

Reserved future local migrations
  003_create_session_index
  004_create_session_search

settings file
  schemaVersion: 1
  migrated by Codable settings importer/exporter
```

Migration invariants:

- migrations run once and are identifier-stable
- future migration identifiers shown here are reserved names; either register
  them as no-op stubs immediately or do not include them in the shipped migrator
  until the schema lands
- foreign keys are enabled for every SQLite connection
- WAL sidecars are quarantined with their owning database
- migration failure reports through the existing recovery path
- no migration silently drops core rows
- cache/index migrations may choose to clear rebuildable tables, but not local
  UX memory unless the migration explicitly owns that table
- reorder migrations and write code must handle `UNIQUE(..., sort_index)` by
  deleting/reinserting the affected ordered child rows inside one transaction
