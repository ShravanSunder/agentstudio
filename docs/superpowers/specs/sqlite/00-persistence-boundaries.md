# SQLite Persistence Boundaries

## Status

Checkpoint C1 for the AgentStudio SQLite cutover.

This file owns the mental model only: what belongs in `core.sqlite`, what stays
as editable settings JSON, and what belongs in each workspace's local SQLite
database.

## Target Files

```text
<AppDataPaths.rootDirectory()>/core.sqlite
<AppDataPaths.workspacesDirectory()>/<workspace-id>.settings.json
<AppDataPaths.workspacesDirectory()>/<workspace-id>.local.sqlite
```

Step 1 uses exactly two SQLite database shapes: one global `core.sqlite` and
one `<workspace-id>.local.sqlite` per workspace. There is no app-level local
SQLite database in Step 1.

## Decision

Use SQLite through GRDB.swift for durable app data and per-workspace local data.
Keep user-editable settings in a small workspace settings file.

```text
┌──────────────────────────────────────────────────────────────────┐
│ core.sqlite                                                       │
│                                                                  │
│ location: <AppDataPaths.rootDirectory()>/core.sqlite             │
│ scope:    global app database, rows keyed by workspace_id        │
│ owns:     durable product truth                                  │
│ loses:    destructive; recover, quarantine, or report loudly     │
└──────────────────────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────────────────────┐
│ <workspace-id>.settings.json                                      │
│                                                                  │
│ location: <AppDataPaths.workspacesDirectory()>/...                │
│ scope:    one editable file per workspace                         │
│ owns:     intentional user preferences                            │
│ loses:    annoying, not workspace-destructive                     │
└──────────────────────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────────────────────┐
│ <workspace-id>.local.sqlite                                       │
│                                                                  │
│ location: <AppDataPaths.workspacesDirectory()>/...                │
│ scope:    one local database per workspace                        │
│ owns:     local UX memory + rebuildable cache/index tables        │
│ loses:    annoying or rebuildable, never core-destructive         │
└──────────────────────────────────────────────────────────────────┘
```

Use one SQLite library in Step 1:

- GRDB.swift for SQLite access, migrations, transactions, and FTS.
- No DuckDB in Step 1.

DuckDB has an official Swift client, but this first workload is app state:
small transactions, migrations, key/range lookups, and FTS. DuckDB remains a
future analytics option if AgentStudio later needs columnar historical scans,
Parquet export, or large aggregate reports across many session histories.

## Boundary Model

The persistence boundary is not "core vs UX vs cache" as three equal databases.
The split is:

```text
core
  durable product truth
  normalized enough for migrations and row-scoped writes
  source of truth for workspace identity, repos, worktrees, panes,
  tabs, arrangements, active workspace selection, workflows,
  workers, and durable session pointers

settings
  intentional user preferences
  small, editable, schema-versioned file
  not queried relationally

local
  relaunch memory and rebuildable facts
  one database per workspace
  may contain both non-rebuildable-but-low-criticality local UX
  memory and rebuildable cache/index tables
```

The local database must not become a junk drawer. It uses table prefixes:

```text
local_*   lower-criticality local UX memory and cursor state
cache_*   rebuildable current cache data
index_*   future provider/session/search index data
```

## Active State Rule

`active_workspace_id` is the only active selector in core.

```text
active_workspace_id
  -> core.sqlite
  -> global app boot/selection concern
  -> chooses which workspace graph to open
  -> owned by ActiveWorkspaceSelectionAtom, not by per-workspace identity atoms

active_tab_id
active_arrangement_id
active_pane_id
active_drawer_child_id
drawer_expanded
selected_sidebar_surface
  -> <workspace-id>.local.sqlite
  -> workspace cursor / attention memory
  -> stale value is acceptable after crash or local reset

zoomed_pane_id
  -> not persisted
  -> current code treats this as display-only transient state
  -> reset to nil on hydrate
```

This is the key split:

```text
core graph
  validated mutation
    -> SQLite transaction
    -> atom projection

workspace cursor
  atom changes immediately for UI
    -> coalesced local.sqlite write
    -> reconciled against current core ids on next load
```

Core should not own `workspace_active_tab`, `tab_state.active_arrangement_id`,
`tab_arrangement.active_pane_id`, `drawer.is_expanded`, or
`arrangement_drawer_view.active_child_id`, or `zoomed_pane_id`.

## Runtime-Only State

The cutover should name what is not persisted so future implementers do not
invent a destination table for transient UI/runtime facts.

```text
never persisted
  WindowLifecycleAtom
  AppLifecycleAtom
  SessionRuntimeAtom
  ManagementLayerAtom
  CommandBarSurfaceAtom
  TransientKeyboardSurfaceAtom
  WorkspaceFocusOwnerAtom
  AttendedPaneAtom
  WelcomeAtom
  PaneFilesystemProjectionAtom
  UIStateAtom.sidebarHasFocus
  WorkspacePaneFocus snapshots
  EditorChooserAtom.state.openForPaneId
  EditorChooserAtom.availableTargets
  InboxSidebarStateAtom.pendingFilter
  PaneInboxPresentationAtom.filterModesByParentPaneId
  TerminalActivityAtom snapshots
  Bridge PaneDomainState / ReviewState.viewedFiles
```

These values are runtime composition facts, derived focus/read models, or
runtime health/projection state. They may be recomputed after boot and must not
be imported from legacy workspace files. `PaneInboxPresentationAtom` and
Bridge review viewed-file markers are intentionally runtime-only in Step 1
because they are not persisted today; if product UX later requires relaunch
memory for those fields, they need explicit `local_*` tables and tests.

## Reset Semantics

```text
reset cache
  -> delete rows from cache_* and index_* tables
  -> keep local_* rows

reset local workspace memory
  -> may delete <workspace-id>.local.sqlite
  -> never touches core.sqlite or settings.json

delete workspace
  -> delete core workspace rows in one transaction
  -> delete workspace settings file
  -> close and delete workspace local database + sidecars
```

`local.sqlite` is per-workspace. `workspace_id` columns inside local tables are
guard rails and import/recovery checks, not a declaration that the local database
is multi-tenant. A reset operation must still filter by table prefix, because
`local_*` rows and `cache_*` / `index_*` rows have different loss semantics.

## Current Persistence Inventory

```text
WorkspacePersistor flat workspace files
────────────────────────────────────────────────────────────────────
<id>.workspace.state.json
<id>.workspace.cache.json
<id>.workspace.ui.json
<id>.workspace.sidebar-cache.json
<id>.notification-inbox.json

Root app files
────────────────────────────────────────────────────────────────────
surface-checkpoint.json

UserDefaults keys
────────────────────────────────────────────────────────────────────
windowFrame
drawerHeightRatio
CommandBarRecentItemIds
com.agentstudio.urlHistory
com.agentstudio.webviewFavorites

External framework stores
────────────────────────────────────────────────────────────────────
WKWebsiteDataStore.default()

Diagnostics / runtime-owned files
────────────────────────────────────────────────────────────────────
/tmp/agentstudio-<trace-name>-<pid>.jsonl
<AppDataPaths.rootDirectory()>/z/       zmx runtime directory
temporary Ghostty override config files
```

Target classification:

```text
Current source                         Target
────────────────────────────────────   ─────────────────────────────
workspace.state.json                   core.sqlite + local.sqlite
workspace.cache.json                   local.sqlite
workspace.ui.json                      settings.json + local.sqlite
workspace.sidebar-cache.json           settings.json + local.sqlite
notification-inbox.json                settings.json + local.sqlite
surface-checkpoint.json                keep as root local runtime file
UserDefaults windowFrame key           import once if needed; local.sqlite wins
UserDefaults command/web keys          later global/local audit
WebKit website data store              keep framework-managed; future audit
trace JSONL files                      keep diagnostics as files
zmx runtime directory                  keep runtime-owned
Ghostty temp override files            keep temporary runtime detail
```

## Current Data Mapping

### `WorkspacePersistor.PersistableState`

```swift
struct PersistableState {
    var schemaVersion: Int
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

Mapping:

```text
core.sqlite
  workspace.id
  workspace.name
  workspace.created_at
  workspace.updated_at
  watched_path
  repo
  worktree
  unavailable_repo
  pane and pane child tables
  tab and arrangement child tables

local.sqlite
  local_workspace_cursor.active_tab_id
  local_workspace_window_state.sidebar_width
  local_workspace_window_state.window_frame_json
```

Rationale:

- Repos, worktrees, panes, tabs, and watched paths are product truth.
- Active tab is cursor/attention state inside an already-known workspace.
- Window geometry and sidebar width are relaunch memory. Losing them should not
  damage workspace structure.

Implementation constraint:

- `WorkspaceMetadataAtom` currently owns both groups in one observable object:
  `workspaceId`, `workspaceName`, and `createdAt` are core; `sidebarWidth` and
  `windowFrame` are local UX memory. Step 0 splits this into an identity
  write-owner atom and a window-memory write-owner atom before SQLite
  repositories land. Silent whole-atom snapshot writes are not allowed.

### `WorkspacePersistor.PersistableCacheState`

```swift
struct PersistableCacheState {
    var schemaVersion: Int
    var workspaceId: UUID
    var repoEnrichmentByRepoId: [UUID: RepoEnrichment]
    var worktreeEnrichmentByWorktreeId: [UUID: WorktreeEnrichment]
    var pullRequestCountByWorktreeId: [UUID: Int]
    var notificationCountByWorktreeId: [UUID: Int]
    var recentTargets: [RecentWorkspaceTarget]
    var sourceRevision: UInt64
    var lastRebuiltAt: Date?
}
```

Mapping:

```text
local.sqlite cache_* tables
  cache_metadata.source_revision
  cache_metadata.last_rebuilt_at
  cache_repo_enrichment
  cache_worktree_enrichment
  cache_pull_request_count
  cache_notification_count

local.sqlite local_* tables
  local_recent_workspace_target
```

Rationale:

- Enrichment and counts are rebuildable from runtime/git/provider facts.
- Recent targets are user activity history. They are not core truth, but they
  are also not rebuildable cache, so they live in `local_*`, not `cache_*`.

### `WorkspacePersistor.PersistableUIState`

```swift
struct PersistableUIState {
    struct PersistedEditorChooserState {
        var bookmarkedEditorId: EditorTargetId?
    }

    var schemaVersion: Int
    var workspaceId: UUID
    var filterText: String
    var isFilterVisible: Bool
    var sidebarCollapsed: Bool
    var sidebarSurface: SidebarSurface
    var editorChooserState: PersistedEditorChooserState
}
```

Mapping:

```text
settings.json
  editorChooser.bookmarkedEditorId

local.sqlite local_* tables
  local_sidebar_state.filter_text
  local_sidebar_state.is_filter_visible
  local_sidebar_state.sidebar_collapsed
  local_sidebar_state.sidebar_surface
```

Rationale:

- The editor bookmark is an intentional preference.
- Filter text, selected sidebar surface, and collapsed state are live relaunch
  memory. They should restore, but they should not be treated as durable product
  truth.

### `WorkspacePersistor.PersistableSidebarCache`

```swift
struct PersistableSidebarCache {
    var schemaVersion: Int
    var workspaceId: UUID
    var expandedGroups: Set<SidebarGroupKey>
    var checkoutColors: [SidebarCheckoutColorKey: String]
}
```

Mapping:

```text
settings.json
  sidebar.checkoutColors

local.sqlite local_* tables
  local_sidebar_expanded_group
```

Rationale:

- Checkout colors are user choices and should be editable/reviewable.
- Expanded groups are navigation memory. They can be row-scoped in local SQLite
  and safely reset without changing the workspace.

### `InboxNotificationStore.Payload`

```swift
struct Payload {
    var schemaVersion: Int
    var notifications: [InboxNotification]
    var prefs: Prefs
    var sidebarState: SidebarState

    struct Prefs {
        var grouping: InboxNotificationGrouping
        var sort: InboxNotificationSort
        var bellEnabled: Bool
    }

    struct SidebarState {
        var collapsedGroups: Set<InboxNotificationGroupKey>
    }
}
```

Mapping:

```text
settings.json
  notifications.grouping
  notifications.sort
  notifications.bellEnabled

local.sqlite local_* tables
  local_notification_inbox_item
  local_notification_inbox_collapsed_group
```

Rationale:

- Notification preferences are intentional settings.
- Notification history and collapsed inbox groups are local UX memory. Losing
  them is annoying, not workspace-destructive.

### Root And UserDefaults State

These are real persistence surfaces, but they are not part of the workspace
Step 1 cutover unless explicitly pulled in later.

```text
surface-checkpoint.json
  owner: SurfaceManager
  role: runtime checkpoint for active/hidden Ghostty surfaces
  target: keep as root local runtime file for Step 1; decode failure may log and
          ignore the checkpoint because surfaces are rebuildable runtime state

windowFrame UserDefaults
  owner: MainWindowController
  role: legacy/global window frame memory
  target: Step 1 replaces this as a live source with local.sqlite; the
          UserDefaults value may be imported only when no local workspace window
          row exists; after a local row is committed, stop writing this key and
          remove it on the next successful workspace-local flush

drawerHeightRatio UserDefaults / AppStorage
  owner: Drawer presentation
  role: global user preference
  target: future global settings file or app settings table

CommandBarRecentItemIds UserDefaults
  owner: CommandBarState
  role: global local recents
  target: future root local store; preserve the current cap of 8 recent item ids
          and move direct UserDefaults writes out of CommandBarState when this
          migrates

URL history and favorites UserDefaults
  owner: URLHistoryService
  role: webview history and user favorites
  target: future global/local persistence audit; preserve history's 14-day
          retention window, 100-entry cap, URL de-duplication, and separate
          favorites collection when this migrates

WebKit website data store
  owner: WebviewPaneController / WKWebsiteDataStore.default()
  role: framework-managed cookies, local storage, and website data shared by
        webview panes
  target: keep framework-managed in Step 1; future webview audit must decide
          whether AgentStudio needs reset/export controls or an app-owned store

diagnostic JSONL traces
  owner: AgentStudioTraceRuntime
  role: diagnostics
  target: stay as files
```

## Target Entity Diagram

```text
                          core.sqlite
┌──────────────────────────────────────────────────────────────────┐
│                                                                  │
│ app_workspace_selection ──► workspace                            │
│                                                                  │
│ workspace                                                        │
│   ├─ watched_path                                                │
│   ├─ repo                                                        │
│   │   └─ worktree                                                │
│   ├─ unavailable_repo                                            │
│   ├─ pane                                                        │
│   │   ├─ pane_content_terminal                                   │
│   │   ├─ pane_content_webview                                    │
│   │   ├─ pane_content_code_viewer                                │
│   │   ├─ pane_content_payload                                    │
│   │   ├─ pane_tag                                                │
│   │   └─ drawer ── drawer_pane                                   │
│   ├─ tab_shell                                                   │
│   │   ├─ tab_pane                                                │
│   │   └─ tab_arrangement                                         │
│   │       ├─ arrangement_layout_pane                             │
│   │       ├─ arrangement_layout_divider                          │
│   │       ├─ arrangement_minimized_pane                          │
│   │       └─ arrangement_drawer_view                             │
│   │           ├─ drawer_view_layout_pane                         │
│   │           ├─ drawer_view_layout_divider                      │
│   │           └─ drawer_view_minimized_pane                      │
│   ├─ workflow                         future                     │
│   ├─ worker                           future                     │
│   ├─ session_pointer                  future                     │
│   └─ workflow_session                 future                     │
│                                                                  │
└──────────────────────────────────────────────────────────────────┘

                    per-workspace settings file
┌──────────────────────────────────────────────────────────────────┐
│ <workspace-id>.settings.json                                      │
│                                                                  │
│ editorChooser.bookmarkedEditorId                                 │
│ sidebar.checkoutColors                                           │
│ notifications.grouping                                           │
│ notifications.sort                                               │
│ notifications.bellEnabled                                        │
│                                                                  │
└──────────────────────────────────────────────────────────────────┘

                         local.sqlite
┌──────────────────────────────────────────────────────────────────┐
│                                                                  │
│ local_workspace_cursor                                           │
│ local_tab_cursor                                                 │
│ local_arrangement_cursor                                         │
│ local_drawer_cursor                                              │
│ local_arrangement_drawer_cursor                                  │
│ local_workspace_window_state                                     │
│ local_sidebar_state                                              │
│ local_sidebar_expanded_group                                     │
│ local_recent_workspace_target                                    │
│ local_notification_inbox_item                                    │
│ local_notification_inbox_collapsed_group                         │
│                                                                  │
│ cache_metadata                                                   │
│ cache_repo_enrichment                                            │
│ cache_worktree_enrichment                                        │
│ cache_pull_request_count                                         │
│ cache_notification_count                                         │
│                                                                  │
│ index_session_*                    future session/search index   │
│                                                                  │
└──────────────────────────────────────────────────────────────────┘
```
