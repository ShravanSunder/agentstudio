# Core Workspace Schema

## Status

Checkpoint C2 for the AgentStudio SQLite cutover.

This file owns durable core rows only. Cursor/attention state is specified in
`02-local-ux-and-cache-schema.md`.

## Scope

`core.sqlite` is global and durable. It stores the workspace catalog and the
workspace graph:

```text
<AppDataPaths.rootDirectory()>/core.sqlite
```

Core owns:

- workspace identity
- the app-level active workspace selector
- watched paths
- repos and worktrees
- panes, content, metadata, residency, drawer membership
- tabs, pane membership, arrangements, layouts, minimized layout membership
- future workflow/worker/session pointer rows

Core does not own:

- active tab
- active arrangement
- active pane
- drawer expansion
- active drawer child
- zoomed pane
- selected sidebar surface
- window frame or sidebar width
- cache/index/session facts

## Core Schema Sketch

This is design DDL, not final executable migration text.

```sql
CREATE TABLE workspace (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    created_at REAL NOT NULL,
    updated_at REAL NOT NULL
);

CREATE TABLE app_workspace_selection (
    singleton_id INTEGER PRIMARY KEY CHECK (singleton_id = 1),
    active_workspace_id TEXT REFERENCES workspace(id) ON DELETE SET NULL,
    updated_at REAL NOT NULL
);

CREATE TABLE legacy_workspace_import_status (
    workspace_id TEXT PRIMARY KEY REFERENCES workspace(id) ON DELETE CASCADE,
    source_state_path TEXT NOT NULL,
    core_imported_at REAL,
    settings_imported_at REAL,
    local_imported_at REAL,
    cache_imported_at REAL,
    archived_at REAL,
    last_error TEXT
);

CREATE TABLE workspace_sqlite_snapshot_status (
    workspace_id TEXT PRIMARY KEY REFERENCES workspace(id) ON DELETE CASCADE,
    completed_at REAL NOT NULL
);

CREATE TABLE watched_path (
    id TEXT PRIMARY KEY,
    workspace_id TEXT NOT NULL REFERENCES workspace(id) ON DELETE CASCADE,
    path TEXT NOT NULL,
    stable_key TEXT NOT NULL,
    added_at REAL NOT NULL,
    UNIQUE(workspace_id, stable_key)
);

CREATE TABLE repo (
    id TEXT PRIMARY KEY,
    workspace_id TEXT NOT NULL REFERENCES workspace(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    repo_path TEXT NOT NULL,
    stable_key TEXT NOT NULL,
    created_at REAL NOT NULL,
    UNIQUE(workspace_id, stable_key),
    UNIQUE(id, workspace_id)
);

CREATE TABLE worktree (
    id TEXT PRIMARY KEY,
    workspace_id TEXT NOT NULL REFERENCES workspace(id) ON DELETE CASCADE,
    repo_id TEXT NOT NULL,
    name TEXT NOT NULL,
    path TEXT NOT NULL,
    stable_key TEXT NOT NULL,
    is_main_worktree INTEGER NOT NULL,
    UNIQUE(workspace_id, stable_key),
    UNIQUE(repo_id, stable_key),
    FOREIGN KEY(repo_id, workspace_id)
        REFERENCES repo(id, workspace_id)
        ON DELETE CASCADE
);

CREATE TABLE unavailable_repo (
    workspace_id TEXT NOT NULL REFERENCES workspace(id) ON DELETE CASCADE,
    repo_id TEXT NOT NULL,
    PRIMARY KEY(workspace_id, repo_id),
    FOREIGN KEY(repo_id, workspace_id)
        REFERENCES repo(id, workspace_id)
        ON DELETE CASCADE
);

CREATE TABLE pane (
    id TEXT PRIMARY KEY,
    workspace_id TEXT NOT NULL REFERENCES workspace(id) ON DELETE CASCADE,
    content_type TEXT NOT NULL CHECK (
        content_type IN (
            'terminal',
            'browser',
            'diff',
            'editor',
            'review',
            'agent',
            'codeViewer'
        )
        OR content_type GLOB 'plugin:?*'
    ),
    execution_backend TEXT NOT NULL,
    source_kind TEXT NOT NULL,
    source_repo_id TEXT REFERENCES repo(id) ON DELETE SET NULL,
    source_worktree_id TEXT REFERENCES worktree(id) ON DELETE SET NULL,
    launch_directory TEXT,
    title TEXT NOT NULL,
    note TEXT,
    cwd TEXT,
    checkout_ref TEXT,
    residency_kind TEXT NOT NULL,
    pending_undo_expires_at REAL,
    orphan_reason_kind TEXT,
    orphan_worktree_path TEXT,
    kind TEXT NOT NULL,
    parent_pane_id TEXT REFERENCES pane(id) ON DELETE CASCADE,
    created_at REAL NOT NULL,
    updated_at REAL NOT NULL
);

CREATE TABLE pane_content_terminal (
    pane_id TEXT PRIMARY KEY REFERENCES pane(id) ON DELETE CASCADE,
    provider TEXT NOT NULL,
    lifetime TEXT NOT NULL
);

CREATE TABLE pane_content_webview (
    pane_id TEXT PRIMARY KEY REFERENCES pane(id) ON DELETE CASCADE,
    url TEXT NOT NULL,
    title TEXT NOT NULL,
    show_navigation INTEGER NOT NULL
);

CREATE TABLE pane_content_code_viewer (
    pane_id TEXT PRIMARY KEY REFERENCES pane(id) ON DELETE CASCADE,
    file_path TEXT NOT NULL,
    scroll_to_line INTEGER
);

CREATE TABLE pane_content_payload (
    pane_id TEXT PRIMARY KEY REFERENCES pane(id) ON DELETE CASCADE,
    payload_kind TEXT NOT NULL,
    payload_json TEXT NOT NULL
);

CREATE TABLE pane_tag (
    pane_id TEXT NOT NULL REFERENCES pane(id) ON DELETE CASCADE,
    tag TEXT NOT NULL,
    PRIMARY KEY(pane_id, tag)
);

CREATE TABLE drawer (
    id TEXT PRIMARY KEY,
    parent_pane_id TEXT NOT NULL REFERENCES pane(id) ON DELETE CASCADE,
    UNIQUE(parent_pane_id)
);

CREATE TABLE drawer_pane (
    drawer_id TEXT NOT NULL REFERENCES drawer(id) ON DELETE CASCADE,
    pane_id TEXT NOT NULL REFERENCES pane(id) ON DELETE CASCADE,
    sort_index INTEGER NOT NULL,
    PRIMARY KEY(drawer_id, pane_id),
    UNIQUE(pane_id),
    UNIQUE(drawer_id, sort_index)
);

CREATE TABLE tab_shell (
    id TEXT PRIMARY KEY,
    workspace_id TEXT NOT NULL REFERENCES workspace(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    sort_index INTEGER NOT NULL,
    UNIQUE(workspace_id, sort_index)
);

CREATE TABLE tab_pane (
    tab_id TEXT NOT NULL REFERENCES tab_shell(id) ON DELETE CASCADE,
    pane_id TEXT NOT NULL REFERENCES pane(id) ON DELETE CASCADE,
    sort_index INTEGER NOT NULL,
    PRIMARY KEY(tab_id, pane_id),
    UNIQUE(pane_id),
    UNIQUE(tab_id, sort_index)
);

CREATE TABLE tab_arrangement (
    id TEXT PRIMARY KEY,
    tab_id TEXT NOT NULL REFERENCES tab_shell(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    is_default INTEGER NOT NULL CHECK (is_default IN (0, 1)),
    shows_minimized_panes INTEGER NOT NULL CHECK (shows_minimized_panes IN (0, 1)),
    sort_index INTEGER NOT NULL,
    UNIQUE(tab_id, sort_index)
);

CREATE UNIQUE INDEX idx_tab_arrangement_one_default
ON tab_arrangement(tab_id)
WHERE is_default = 1;

CREATE TABLE arrangement_layout_pane (
    arrangement_id TEXT NOT NULL REFERENCES tab_arrangement(id) ON DELETE CASCADE,
    pane_id TEXT NOT NULL REFERENCES pane(id) ON DELETE CASCADE,
    sort_index INTEGER NOT NULL,
    ratio REAL NOT NULL,
    PRIMARY KEY(arrangement_id, pane_id),
    UNIQUE(arrangement_id, sort_index)
);

CREATE TABLE arrangement_layout_divider (
    arrangement_id TEXT NOT NULL REFERENCES tab_arrangement(id) ON DELETE CASCADE,
    divider_id TEXT NOT NULL,
    sort_index INTEGER NOT NULL,
    PRIMARY KEY(arrangement_id, divider_id),
    UNIQUE(arrangement_id, sort_index)
);

CREATE TABLE arrangement_minimized_pane (
    arrangement_id TEXT NOT NULL REFERENCES tab_arrangement(id) ON DELETE CASCADE,
    pane_id TEXT NOT NULL REFERENCES pane(id) ON DELETE CASCADE,
    PRIMARY KEY(arrangement_id, pane_id)
);

CREATE TABLE arrangement_drawer_view (
    arrangement_id TEXT NOT NULL REFERENCES tab_arrangement(id) ON DELETE CASCADE,
    drawer_id TEXT NOT NULL REFERENCES drawer(id) ON DELETE CASCADE,
    row_split_ratio REAL NOT NULL,
    PRIMARY KEY(arrangement_id, drawer_id)
);

CREATE TABLE drawer_view_layout_pane (
    arrangement_id TEXT NOT NULL,
    drawer_id TEXT NOT NULL,
    row_kind TEXT NOT NULL,
    pane_id TEXT NOT NULL REFERENCES pane(id) ON DELETE CASCADE,
    sort_index INTEGER NOT NULL,
    ratio REAL NOT NULL,
    PRIMARY KEY(arrangement_id, drawer_id, pane_id),
    UNIQUE(arrangement_id, drawer_id, row_kind, sort_index),
    FOREIGN KEY(arrangement_id, drawer_id)
        REFERENCES arrangement_drawer_view(arrangement_id, drawer_id)
        ON DELETE CASCADE
);

CREATE TABLE drawer_view_layout_divider (
    arrangement_id TEXT NOT NULL,
    drawer_id TEXT NOT NULL,
    row_kind TEXT NOT NULL,
    divider_id TEXT NOT NULL,
    sort_index INTEGER NOT NULL,
    PRIMARY KEY(arrangement_id, drawer_id, row_kind, divider_id),
    UNIQUE(arrangement_id, drawer_id, row_kind, sort_index),
    FOREIGN KEY(arrangement_id, drawer_id)
        REFERENCES arrangement_drawer_view(arrangement_id, drawer_id)
        ON DELETE CASCADE
);

CREATE TABLE drawer_view_minimized_pane (
    arrangement_id TEXT NOT NULL,
    drawer_id TEXT NOT NULL,
    pane_id TEXT NOT NULL REFERENCES pane(id) ON DELETE CASCADE,
    PRIMARY KEY(arrangement_id, drawer_id, pane_id),
    FOREIGN KEY(arrangement_id, drawer_id)
        REFERENCES arrangement_drawer_view(arrangement_id, drawer_id)
        ON DELETE CASCADE
);
```

`pane.content_type` uses the live pane-graph vocabulary, not the legacy
`PaneContent` JSON discriminator:

```text
PaneContentType.terminal       -> "terminal"   -> pane_content_terminal
PaneContentType.browser        -> "browser"    -> pane_content_webview
PaneContentType.codeViewer     -> "codeViewer" -> pane_content_code_viewer
PaneContentType.diff/editor/
  review/agent/plugin(...)     -> payload-backed pane_content_payload
```

The table name `pane_content_webview` remains because the browser pane payload
stores URL/navigation facts, but its discriminator is `browser`. The SQLite
repository must use the same storage tokens as `SQLitePaneContentTypeStorage`.

The executable migration adds triggers that keep the content tables aligned with
`pane.content_type`:

```text
unsupported pane.content_type tokens are rejected on insert
pane.content_type is immutable after insert
pane_content_terminal rows require "terminal"
pane_content_webview rows require "browser"
pane_content_code_viewer rows require "codeViewer"
pane_content_payload rows require any other payload-backed token
```

Those triggers run on insert and on updates that would move a content row to a
different pane. The repository still owns higher-level payload validation.

The executable migration also adds workspace-ownership triggers for pane links
that cannot use simple single-column foreign keys:

```text
pane.parent_pane_id must belong to the same workspace as the child pane
drawer_pane.pane_id must belong to the drawer parent pane's workspace
tab_pane.pane_id must belong to the tab workspace
arrangement_layout_pane.pane_id must belong to the arrangement tab workspace
arrangement_minimized_pane.pane_id must belong to the arrangement tab workspace
arrangement_drawer_view.drawer_id must belong to the arrangement tab workspace
drawer_view_layout_pane.pane_id must belong to the arrangement tab workspace
drawer_view_minimized_pane.pane_id must belong to the arrangement tab workspace
```

Those triggers run on insert and on updates that would move either side of the
link. Without them, a multi-workspace `core.sqlite` could let workspace A's tab
or drawer claim workspace B's pane.

## Atom Mapping

```text
WorkspaceIdentityAtom
  -> workspace.id
  -> workspace.name
  -> workspace.created_at

WorkspaceCoreRepository
  -> workspace.updated_at
  -> legacy_workspace_import_status
  -> workspace_sqlite_snapshot_status

ActiveWorkspaceSelectionAtom
  -> app_workspace_selection.active_workspace_id

WorkspaceRepositoryTopologyAtom
  -> watched_path
  -> repo
  -> worktree
  -> unavailable_repo

WorkspacePaneGraphAtom
  -> pane
  -> pane_content_*
  -> pane_tag
  -> drawer
  -> drawer_pane
  -> durable PaneMetadata source/cwd/title/note/tag fields only

WorkspaceTabShellAtom
  -> tab_shell

WorkspaceTabGraphAtom
  -> tab_pane
  -> tab_arrangement
  -> arrangement_layout_pane
  -> arrangement_layout_divider
  -> arrangement_minimized_pane
  -> arrangement_drawer_view
  -> drawer_view_layout_pane
  -> drawer_view_layout_divider
  -> drawer_view_minimized_pane

WorkspaceTabLayoutDerived
  -> composed read model, not its own persistence owner
```

## Invariants

Drawer invariants that are simple to express belong in the schema:

```text
one parent pane
  -> at most one drawer

one drawer child pane
  -> at most one drawer membership

one drawer view
  -> preserves DrawerGridLayout.rowSplitRatio for the fixed top/bottom drawer
     grid used in Step 1
```

`DrawerGridLayout` is a two-row top/bottom model in Step 1. The single
`row_split_ratio` column intentionally encodes that current model. If drawer
layout later grows to three or more rows, it requires a real schema migration
instead of overloading this column.

`drawer_view_layout_pane` makes `row_kind` non-key because a pane should appear
in at most one row for a drawer view. `row_kind` still participates in the
`sort_index` uniqueness rule because ordering is row-local.

`tab_pane.UNIQUE(pane_id)` encodes the live model invariant that a pane has one
owning tab. Cross-tab moves therefore delete membership from the source tab and
insert it into the destination tab in one transaction.

Every pane-link row is workspace-scoped. `tab_pane`, `drawer_pane`,
`arrangement_layout_pane`, `arrangement_minimized_pane`,
`arrangement_drawer_view`, `drawer_view_layout_pane`, and
`drawer_view_minimized_pane` reject cross-workspace links in the executable
migration. The schema therefore allows multiple workspace graphs to coexist in
one `core.sqlite` without a tab or drawer in one workspace claiming a pane from
another workspace.

`worktree` keeps `workspace_id` for workspace-scoped hydrate queries, but the
composite repo foreign key makes that denormalized workspace id agree with the
referenced repo. A worktree for workspace A cannot point at a repo from
workspace B. `unavailable_repo` uses the same workspace-scoped repo constraint.

`pane.source_repo_id` and `pane.source_worktree_id` remain nullable metadata
links with `ON DELETE SET NULL`, because panes survive missing repositories and
worktrees. Executable migrations enforce workspace scope with triggers: when a
source id is present, it must point at a repo/worktree in the same workspace as
the pane.

`idx_tab_arrangement_one_default` enforces the live tab model invariant that
each tab has exactly one default arrangement candidate. Repository/import code
still ensures at least one default exists during graph construction.

`arrangement_minimized_pane` and `shows_minimized_panes` remain core for Step 1
because they shape the saved arrangement layout. If product behavior later
treats minimization as pure ephemeral attention state, that can move to local in
a dedicated migration.

`PaneMetadata.facets` is not stored as one JSON blob. Core stores durable routing
and workspace identity fields: source repo/worktree ids, launch directory, cwd,
checkout ref, title, note, and tags. Display/cache facets such as repo name,
worktree name, parent folder label, organization name, origin, and upstream are
composed by derived readers from core topology plus cache enrichment.

Reorders use delete-then-reinsert for the affected ordered child rows inside one
transaction in Step 1. This touches more rows than a staged-offset update, but it
is simpler, deterministic, and acceptable for realistic tab/pane/drawer counts
in AgentStudio.

A pane belongs to either the main arrangement layout or a single drawer view row
for that arrangement, never both. SQLite cannot express that cross-table
exclusion cleanly, so validators and repository tests own the invariant.

Every pane that appears in an arrangement layout table must also appear in
`tab_pane` for that arrangement's owning tab. This includes
`arrangement_layout_pane`, `drawer_view_layout_pane`, minimized rows, and drawer
view minimized rows. SQLite can enforce each table's immediate foreign keys, but
it cannot cheaply express this cross-table membership invariant without brittle
triggers. Step 1 keeps the invariant in repository transactions and tests.

Repo reassociation and worktree reconciliation are one core transaction. When a
discovered worktree set replaces existing rows, the repository uses the same
delete-then-reinsert strategy as layout reorders for the affected worktree set.
That avoids transient `UNIQUE(workspace_id, stable_key)` or
`UNIQUE(repo_id, stable_key)` conflicts when a key is removed and reused in the
same reconciliation.

The executable migration adds lookup indexes for common hydrate and selection
queries:

```text
idx_workspace_updated_at
idx_repo_workspace_id
idx_worktree_workspace_id
idx_worktree_repo_id
idx_pane_workspace_id
idx_tab_shell_workspace_id
```

## Future Workflow And Session Pointer Sketch

These are core rows because they are user-owned product state. Parsed provider
facts, token counts, tool histograms, and search text belong in local `index_*`
tables later.

```sql
CREATE TABLE workflow (
    id TEXT PRIMARY KEY,
    workspace_id TEXT NOT NULL REFERENCES workspace(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    created_at REAL NOT NULL,
    updated_at REAL NOT NULL,
    archived_at REAL
);

CREATE TABLE worker (
    id TEXT PRIMARY KEY,
    workspace_id TEXT NOT NULL REFERENCES workspace(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    primary_repo_id TEXT REFERENCES repo(id) ON DELETE SET NULL,
    primary_worktree_id TEXT REFERENCES worktree(id) ON DELETE SET NULL,
    created_at REAL NOT NULL,
    updated_at REAL NOT NULL,
    archived_at REAL
);

CREATE TABLE session_pointer (
    id TEXT PRIMARY KEY,
    workspace_id TEXT NOT NULL REFERENCES workspace(id) ON DELETE CASCADE,
    provider TEXT NOT NULL,
    provider_session_id TEXT NOT NULL,
    display_alias TEXT,
    user_note TEXT,
    preferred_restore_command TEXT,
    pinned INTEGER NOT NULL DEFAULT 0,
    archived_at REAL,
    created_at REAL NOT NULL,
    updated_at REAL NOT NULL,
    UNIQUE(workspace_id, provider, provider_session_id)
);

CREATE TABLE workflow_session (
    workflow_id TEXT NOT NULL REFERENCES workflow(id) ON DELETE CASCADE,
    session_pointer_id TEXT NOT NULL REFERENCES session_pointer(id) ON DELETE CASCADE,
    worker_id TEXT REFERENCES worker(id) ON DELETE SET NULL,
    relationship_kind TEXT NOT NULL,
    created_at REAL NOT NULL,
    PRIMARY KEY(workflow_id, session_pointer_id)
);
```

`ManagementLayerAtom` is not this schema today. It currently stores only runtime
active/inactive state. Workflow/worker/session-pointer rows are future durable
product concepts, not a persistence mapping for the current `ManagementLayerAtom`.
