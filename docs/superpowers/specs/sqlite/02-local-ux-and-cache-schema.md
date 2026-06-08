# Local UX And Cache Schema

## Status

Checkpoint C3 for the AgentStudio SQLite cutover.

This file owns the per-workspace local database:

```text
<AppDataPaths.workspacesDirectory()>/<workspace-id>.local.sqlite
```

## Scope

The local database is lower criticality than core. It stores:

- workspace cursor/attention state
- window/sidebar relaunch memory
- local notification inbox history
- recent target history
- rebuildable repo/worktree cache summaries
- future provider/session/search index rows

Deleting the local database must never delete durable core workspace rows or
settings.

`zoomedPaneId` is not part of local persistence. The current `Tab` model marks it
as display-only transient state; hydrate should reset it to nil.

This database is single-workspace even though local tables carry `workspace_id`.
Those columns are guard rails, import checks, and query keys, not tenant keys.

## Prefix Rules

```text
local_*   lower-criticality local UX memory and cursor state
cache_*   rebuildable current cache data
index_*   future provider/session/search index data
```

Reset rules:

```text
delete cache_* rows
  -> preserves local_* and index_* rows unless explicitly doing a full index reset

delete index_* rows
  -> preserves local_* and cache_* rows

delete local.sqlite
  -> loses local UX memory, cache, and index
  -> never changes core.sqlite or settings.json
```

## Executable Migration Identifiers

The executable migrator is `WorkspaceLocalMigrations` and currently registers:

```text
001_create_local_cursors
002_create_local_workspace_memory
003_create_local_notifications
004_create_cache_tables
```

The DDL below is mirrored by tests in `WorkspaceLocalMigrationTests`.

## Local UX Schema

```sql
CREATE TABLE local_workspace_cursor (
    workspace_id TEXT PRIMARY KEY,
    active_tab_id TEXT,
    updated_at REAL NOT NULL
);

CREATE TABLE local_tab_cursor (
    tab_id TEXT PRIMARY KEY,
    workspace_id TEXT NOT NULL,
    active_arrangement_id TEXT,
    updated_at REAL NOT NULL
);

CREATE TABLE local_arrangement_cursor (
    arrangement_id TEXT PRIMARY KEY,
    workspace_id TEXT NOT NULL,
    active_pane_id TEXT,
    updated_at REAL NOT NULL
);

CREATE TABLE local_drawer_cursor (
    drawer_id TEXT PRIMARY KEY,
    workspace_id TEXT NOT NULL,
    is_expanded INTEGER NOT NULL CHECK (is_expanded IN (0, 1)),
    updated_at REAL NOT NULL
);

CREATE UNIQUE INDEX idx_local_drawer_cursor_one_expanded_per_workspace
ON local_drawer_cursor(workspace_id)
WHERE is_expanded = 1;

CREATE TABLE local_arrangement_drawer_cursor (
    arrangement_id TEXT NOT NULL,
    drawer_id TEXT NOT NULL,
    workspace_id TEXT NOT NULL,
    active_child_id TEXT,
    updated_at REAL NOT NULL,
    PRIMARY KEY(arrangement_id, drawer_id)
);

CREATE TABLE local_workspace_window_state (
    workspace_id TEXT PRIMARY KEY,
    sidebar_width REAL NOT NULL,
    window_frame_json TEXT,
    updated_at REAL NOT NULL
);

CREATE TABLE local_sidebar_state (
    workspace_id TEXT PRIMARY KEY,
    filter_text TEXT NOT NULL,
    is_filter_visible INTEGER NOT NULL CHECK (is_filter_visible IN (0, 1)),
    sidebar_collapsed INTEGER NOT NULL CHECK (sidebar_collapsed IN (0, 1)),
    sidebar_surface TEXT NOT NULL CHECK (sidebar_surface IN ('repos', 'inbox')),
    updated_at REAL NOT NULL
);

CREATE TABLE local_sidebar_expanded_group (
    workspace_id TEXT NOT NULL,
    group_key TEXT NOT NULL,
    PRIMARY KEY(workspace_id, group_key)
);

CREATE TABLE local_recent_workspace_target (
    id TEXT PRIMARY KEY,
    workspace_id TEXT NOT NULL,
    path TEXT NOT NULL,
    display_title TEXT NOT NULL,
    subtitle TEXT NOT NULL,
    repo_id TEXT,
    worktree_id TEXT,
    kind TEXT NOT NULL CHECK (kind IN ('worktree', 'cwdOnly')),
    last_opened_at REAL NOT NULL,
    CHECK (
        (kind = 'worktree' AND repo_id IS NOT NULL AND worktree_id IS NOT NULL)
        OR (kind = 'cwdOnly' AND repo_id IS NULL AND worktree_id IS NULL)
    )
);

CREATE TABLE local_notification_inbox_collapsed_group (
    workspace_id TEXT NOT NULL,
    group_key TEXT NOT NULL,
    PRIMARY KEY(workspace_id, group_key)
);

CREATE TABLE local_notification_inbox_item (
    id TEXT PRIMARY KEY,
    workspace_id TEXT NOT NULL,
    timestamp REAL NOT NULL,
    kind TEXT NOT NULL,
    title TEXT NOT NULL,
    body TEXT,
    source_kind TEXT NOT NULL,
    pane_id TEXT,
    tab_id TEXT,
    tab_display_label TEXT,
    tab_ordinal INTEGER,
    repo_id TEXT,
    repo_name TEXT,
    worktree_id TEXT,
    worktree_name TEXT,
    branch_name TEXT,
    pane_display_label TEXT,
    pane_ordinal INTEGER,
    pane_role TEXT,
    parent_pane_id TEXT,
    parent_pane_display_label TEXT,
    parent_pane_ordinal INTEGER,
    drawer_ordinal INTEGER,
    runtime_display_label TEXT,
    activity_burst_window_id TEXT,
    activity_session_id TEXT,
    activity_event_count INTEGER,
    activity_rows_added INTEGER,
    activity_threshold_rows INTEGER,
    activity_latest_rows INTEGER,
    claim_pane_id TEXT,
    claim_lane TEXT,
    claim_semantic TEXT,
    claim_session_id TEXT,
    is_read INTEGER NOT NULL CHECK (is_read IN (0, 1)),
    is_dismissed_from_pane_inbox INTEGER NOT NULL CHECK (is_dismissed_from_pane_inbox IN (0, 1)),
    CHECK (
        (
            claim_pane_id IS NULL
            AND claim_lane IS NULL
            AND claim_semantic IS NULL
            AND claim_session_id IS NULL
        )
        OR (
            claim_pane_id IS NOT NULL
            AND claim_lane IS NOT NULL
            AND claim_lane IN ('activity', 'actionNeeded', 'safety')
            AND claim_semantic IS NOT NULL
        )
    )
);
```

The executable migration also creates lookup indexes for workspace-scoped cursor,
drawer-prune, recent-target, inbox, and cache-prune queries.
`local_sidebar_state.sidebar_surface`, `local_recent_workspace_target.kind`, and
the recent-target referent-shape `CHECK` are generated from
`SQLiteLocalUXStorage`, not duplicated freehand string lists.

`local_notification_inbox_item` deliberately uses non-unique claim lookup
indexes instead of a unique claim-key constraint. `InboxNotificationAtom`
coalescence depends on lane, session id, and read/dismissed state; for example,
safety-lane claims do not coalesce, while activity/action-needed claims can
coalesce by session even when lane or semantic changes. The SQLite repository
must query the indexed claim candidates and apply the same atom coalescence rule
before inserting or updating rows. Shipped migrations embed frozen literal claim
lane snapshots; they must not call live helper APIs whose values can change in a
future release. `WorkspaceLocalSchemaContractTests` keep the current runtime
storage helper vocabulary aligned with `InboxNotificationClaimLane`.
The claim-key `CHECK` requires claim columns to be either all absent, or a
coherent pane/lane/semantic tuple with an optional session id and a known lane.
`005_enforce_notification_claim_keys` rebuilds the pre-check notification table,
preserves notification rows, and normalizes malformed legacy claim tuples to an
absent claim key.

Inbox persistence uses two lane-marker meanings. `notification_inbox` means the
live SQLite inbox lane has been initialized, including valid empty snapshots.
`notification_inbox_legacy_import` means legacy inbox JSON has been replayed and
materialized into SQLite; archive readiness must use this legacy-import proof,
not generic row existence or the live empty-lane marker.

```sql
CREATE INDEX idx_local_notification_inbox_item_claim_exact
ON local_notification_inbox_item(
    workspace_id,
    claim_pane_id,
    claim_lane,
    claim_semantic,
    claim_session_id
)
WHERE claim_pane_id IS NOT NULL
    AND claim_lane IS NOT NULL
    AND claim_semantic IS NOT NULL;

CREATE INDEX idx_local_notification_inbox_item_claim_session
ON local_notification_inbox_item(
    workspace_id,
    claim_pane_id,
    claim_session_id
)
WHERE claim_pane_id IS NOT NULL
    AND claim_session_id IS NOT NULL
    AND claim_lane IN ('activity', 'actionNeeded');
```

## Cache Schema

```sql
CREATE TABLE cache_metadata (
    workspace_id TEXT PRIMARY KEY,
    source_revision INTEGER NOT NULL DEFAULT 0 CHECK (source_revision >= 0),
    last_rebuilt_at REAL
);

CREATE TABLE cache_repo_enrichment (
    repo_id TEXT PRIMARY KEY,
    workspace_id TEXT NOT NULL,
    state TEXT NOT NULL,
    origin TEXT,
    upstream TEXT,
    group_key TEXT,
    remote_slug TEXT,
    organization_name TEXT,
    display_name TEXT,
    updated_at REAL NOT NULL,
    payload_json TEXT
);

CREATE TABLE cache_worktree_enrichment (
    worktree_id TEXT PRIMARY KEY,
    workspace_id TEXT NOT NULL,
    repo_id TEXT NOT NULL,
    branch TEXT,
    is_main_worktree INTEGER NOT NULL CHECK (is_main_worktree IN (0, 1)),
    updated_at REAL NOT NULL,
    payload_json TEXT
);

CREATE TABLE cache_pull_request_count (
    worktree_id TEXT PRIMARY KEY,
    workspace_id TEXT NOT NULL,
    repo_id TEXT,
    count INTEGER NOT NULL CHECK (count >= 0),
    updated_at REAL NOT NULL
);

CREATE TABLE cache_notification_count (
    worktree_id TEXT PRIMARY KEY,
    workspace_id TEXT NOT NULL,
    repo_id TEXT,
    count INTEGER NOT NULL CHECK (count >= 0),
    updated_at REAL NOT NULL
);
```

`cache_metadata` is the one guard row for a per-workspace local database. The
`workspace_id` value must match the workspace that owns the file; it is not a
cross-workspace table design.

The executable migration creates workspace/repo/worktree lookup indexes for the
cache tables. These indexes are query aids only; copied core ids are reconciled
by local-store repair because SQLite cannot enforce foreign keys across
`core.sqlite` and the per-workspace local database file.

## Atom Mapping

```text
WorkspaceWindowMemoryAtom
  -> local_workspace_window_state.sidebar_width
  -> local_workspace_window_state.window_frame_json

WorkspaceTabCursorAtom
  -> local_workspace_cursor.active_tab_id

WorkspaceArrangementCursorAtom
  -> local_tab_cursor.active_arrangement_id
  -> local_arrangement_cursor.active_pane_id
  -> local_arrangement_drawer_cursor.active_child_id

WorkspaceDrawerCursorAtom
  -> local_drawer_cursor.is_expanded

WorkspaceSidebarMemoryAtom
  -> local_sidebar_state

SidebarExpandedGroupAtom
  -> local_sidebar_expanded_group

InboxSidebarMemoryAtom
  -> local_notification_inbox_collapsed_group

InboxSidebarRuntimeAtom
  -> pendingFilter is runtime-only and is not stored

PaneInboxPresentationAtom
  -> runtime-only in Step 1
  -> filterModesByParentPaneId is not stored unless a future UX decision makes
     pane inbox filter mode relaunch memory

RepoEnrichmentCacheAtom
  -> cache_metadata
  -> cache_repo_enrichment
  -> cache_worktree_enrichment
  -> cache_pull_request_count
  -> cache_notification_count

RecentWorkspaceTargetAtom
  -> local_recent_workspace_target

InboxNotificationAtom
  -> local_notification_inbox_item
```

## Cross-Database Reference Rules

`core.sqlite` is the only owner of workspace, repo, worktree, pane, tab,
workflow, worker, and session pointer identity. `local.sqlite` may copy those
ids for querying and filtering, but SQLite cannot enforce foreign keys across
separate database files.

```text
core delete / topology prune
  -> commit core transaction
  -> WorkspaceMutationCoordinator receives committed deleted ids
  -> MainActor cursor atoms synchronously clear or reset dangling ids before
     the UI observes the completed user action
  -> WorkspaceLocalStore runs reconciliation for the affected workspace
     in the same async task before the user action is considered settled
  -> delete local/cache/index rows whose copied core ids no longer resolve

local reset
  -> delete cache_* and index_* rows by prefix
  -> keep local_* rows
  -> never modify core rows

cache/index rebuild
  -> reads current core topology
  -> recreates copied repo_id/worktree_id/pane_id references from current truth
```

Dangling local rows are stale derived/local state, not core data loss. They are
still bugs if they remain visible in the UI, so reconciliation is part of the
write contract.

## Future Index Tables

Provider session discovery and transcript indexing belong in `index_*` tables
inside this same local database. See `07-session-index-brainstorm.md`.
