# Persistence Ownership and Pane Lifecycle Hard Cut

Date: 2026-07-21
Status: Draft

## Read this first

This change fixes three customer-impacting problems:

1. Deleting a workspace can currently delete application-level repositories,
   worktrees, watched paths, tags, and availability rows because the SQLite
   schema incorrectly makes them children of the workspace.
2. A local preference/cache write can currently make a valid core snapshot look
   incomplete and prevent AgentStudio from opening.
3. Closing panes and tabs does not implement one coherent 15-minute undo
   lifecycle. Pane records, Ghostty surfaces, runtime state, and ZMX sessions can
   outlive one another, and worktree disappearance incorrectly marks live panes
   as orphaned.

The target ownership is intentionally small:

```text
core.sqlite
  authoritative global repository topology
  authoritative workspace composition
  pane close state during the 15-minute undo window

local.sqlite
  one clean application-level database
  non-authoritative cursors, window/sidebar state, preferences,
  notifications, recent targets, and rebuildable caches

preferences.global.json
  the only supported standalone JSON preference file
```

`core.sqlite` must be internally atomic and sufficient to open the app.
`local.sqlite` may be missing or unusable; the app then uses deterministic
defaults without changing core.

## Customer problems and required outcomes

### 1. Workspace deletion destroys data it does not own

The domain model already treats repositories and worktrees as application-level
entities. The current database does not. It stores `workspace_id` on topology
tables and uses workspace-delete cascades.

Required outcome:

- workspace deletion removes only that workspace's pane/tab/layout composition;
- watched paths, repositories, worktrees, tags, notes, favorite state, and
  availability remain unchanged;
- the same repository or worktree can be referenced by multiple workspace
  compositions;
- only an explicit topology mutation may delete a repository or worktree.

### 2. Local state can brick startup

Core composition is authoritative. Window geometry, cursors, sidebar state,
notifications, preferences, and caches are not. The current staged-core,
local-write, core-completion protocol makes core validity depend on local I/O.

Required outcome:

- one core save is one SQLite transaction;
- one core load is one consistent SQLite read transaction;
- core completion never depends on a local token or write;
- one clean application-level `local.sqlite` replaces per-workspace local
  sidecars;
- missing, corrupt, or unavailable local state never blocks valid core startup.

### 3. Closed and orphaned panes accumulate

The model contains `pendingUndo`, but production close paths do not consistently
set it. The coordinator keeps an in-memory stack capped by entry count rather
than a 15-minute deadline. `SurfaceManager` separately uses a five-minute TTL
and destroys only its Ghostty surface. The ZMX destroy API has no production
expiry caller. Worktree removal also changes pane residency even though pane
runtime is CWD-backed and does not belong to a worktree.

Required outcome:

- closing a pane or tab starts one 15-minute undo deadline;
- during that window, the pane record, terminal identity, and runtime resources
  remain available for undo;
- expiry removes the pane and all owned content from core, retires the Ghostty
  surface and runtime state, and destroys the stored ZMX session;
- worktree/repository disappearance clears optional topology facets only; it
  does not close the pane or change pane residency;
- the obsolete worktree-derived `orphaned` residency is removed;
- a pane outside tab/drawer membership is valid only when deliberately
  `backgrounded` or `pendingUndo`; any other membership orphan is rejected or
  removed by the defined cutover, not silently retained forever.

## Current evidence

The design is grounded in these current source boundaries:

- `WorkspaceCoreMigrations.swift` defines workspace ownership and cascades on
  `watched_path`, `repo`, `worktree`, and `unavailable_repo`.
- `WorkspaceCoreMigrations+RepositoryTopology.swift` repeats workspace ownership
  in `repo_tag`.
- `WorkspaceCoreRepository+Topology.swift` still requires workspace identity for
  topology reads and writes.
- `WorkspaceSQLiteDatastore.swift` and the store backend coordinate separate
  core/local completion state instead of treating core as independently atomic.
- `WorkspaceSQLiteSaveCoordinator.swift` captures composition and topology in
  one bundle before an off-main suspension. A later-arriving older capture can
  therefore replace newer accepted topology.
- `WorkspaceLocalMigrations.swift` defines one schema per workspace-local
  sidecar and repeats `workspace_id` on global cache rows.
- `WorkspaceSurfaceCoordinator+ActionExecution.swift` closes tabs/panes through
  an in-memory undo stack and has no working time-based `expireUndoEntry` path.
- `WorkspaceCompositionPreparation.swift` rejects every pane outside tab
  membership, while the product intentionally retains `backgrounded` panes and
  must retain `pendingUndo` panes. Direct tab close therefore creates a state
  that current autosave cannot commit.
- `SurfaceManager.swift` has an independent five-minute surface-only undo TTL.
- `WorkspacePaneGraphAtom.purgeOrphanedPane` accepts only `backgrounded` even
  though its facade also routes worktree-derived `orphaned` panes there.
- `ZmxBackend.destroySessionByID` exists, but pane/tab expiry does not call it.

A read-only production aggregate check on 2026-07-21 found:

```text
core quick_check             ok
foreign-key violations       0
workspaces                    1
repositories                 157
worktrees                    244
panes                         47
tabs                          8

pane residency
  active                     14  (14 in composition)
  backgrounded                4  (4 outside composition, intentional pool)
  orphaned                   29  (25 in composition, 4 outside composition)
  pendingUndo                 0
```

No IDs, paths, titles, notes, terminal content, or notification content were
read. The result demonstrates that `orphaned` is not a reliable synonym for
"closed pane": most such panes are still members of live compositions.

## Ownership boundaries

### Current core ownership: incorrect

```mermaid
erDiagram
    WORKSPACE ||--o{ WATCHED_PATH : "CASCADE owns (wrong)"
    WORKSPACE ||--o{ REPO : "CASCADE owns (wrong)"
    WORKSPACE ||--o{ WORKTREE : "CASCADE owns (wrong)"
    WORKSPACE ||--o{ REPO_TAG : "CASCADE owns (wrong)"
    WORKSPACE ||--o{ UNAVAILABLE_REPO : "CASCADE owns (wrong)"
    WORKSPACE ||--o{ PANE : "owns composition"
    WORKSPACE ||--o{ TAB_SHELL : "owns composition"
    REPO ||--o{ WORKTREE : owns
    PANE o|--o| REPO : "workspace-matched facet"
    PANE o|--o| WORKTREE : "workspace-matched facet"
```

### Target core ownership

```mermaid
erDiagram
    WORKSPACE ||--o{ PANE : "CASCADE owns"
    WORKSPACE ||--o{ TAB_SHELL : "CASCADE owns"
    TAB_SHELL ||--o{ TAB_ARRANGEMENT : owns
    REPO ||--o{ WORKTREE : "CASCADE owns"
    REPO ||--o{ REPO_TAG : "CASCADE owns"
    REPO ||--o| UNAVAILABLE_REPO : "CASCADE owns"
    PANE o|--o| REPO : "optional global facet; SET NULL"
    PANE o|--o| WORKTREE : "optional global facet; SET NULL"
```

There is no edge from `workspace` to repository topology.

### Target database responsibility

```mermaid
flowchart LR
    Core["core.sqlite<br/>authoritative"]
    Local["local.sqlite<br/>non-authoritative"]
    Atoms["MainActor live atoms"]
    Runtime["Ghostty / runtime / ZMX"]

    Core -->|"strict atomic load"| Atoms
    Local -->|"typed values or defaults"| Atoms
    Atoms -->|"coordinator commands"| Runtime
    Atoms -->|"atomic core save"| Core
    Atoms -->|"independent lane writes"| Local

    Local -. "never validates or completes" .-> Core
```

Atoms remain state owners and pure derived-state owners. Persistence and
subprocess cleanup remain in repositories, stores, and coordinators.

## Requirements

### R1. Global topology in `core.sqlite`

- `watched_path`, `repo`, `worktree`, `repo_tag`, and `unavailable_repo` have no
  `workspace_id` column, workspace foreign key, or workspace-delete cascade.
- `worktree.repo_id` is the only ownership edge for worktrees.
- Repository APIs fetch and mutate one application-level topology without a
  workspace parameter.
- Workspace composition saves do not carry or replace topology.
- An older captured composition save can never replace newer accepted topology;
  removing topology from composition bundles is the required ownership boundary,
  not a timestamp-based whole-state overwrite from multiple stores.
- Existing identifiers and values are copied unchanged during the schema
  migration. No UUID merge, deduplication, reconciliation, or metadata synthesis
  is performed.
- Newly generated identifiers use UUIDv7. Existing stored identifiers are used
  as-is.

`id` and `stable_key` are different concepts:

```text
id          durable entity identity and foreign-key target
            UUID; newly generated values use UUIDv7

stable_key  discovery fingerprint derived from canonical filesystem path
            16 hexadecimal characters: the first 64 bits of SHA-256
            not a UUID, not a foreign-key identity, and not merge authority
```

Moving a canonical path may change `stable_key` while the entity UUID remains
stable. Equal stable keys reject invalid duplicate topology; they never authorize
combining two stored UUID identities.

### R2. Workspace composition references global topology

- Pane, tab, arrangement, and drawer rows remain owned by `workspace_id`.
- `pane.facet_repo_id` and `pane.facet_worktree_id` reference global topology
  and use `ON DELETE SET NULL`.
- If both pane facets are present, the worktree must belong to the selected
  repository.
- Removing a repository/worktree facet does not change pane residency, CWD,
  terminal lifetime, or ZMX identity.

### R3. Atomic core persistence

- Every authoritative core mutation commits in one SQLite transaction.
- Every core hydration reads workspace selection, workspace metadata,
  composition, and global topology inside one SQLite read transaction.
- A crash before commit leaves the previous core state; a crash after commit
  leaves the new core state.
- `workspace_sqlite_snapshot_status` is removed. A committed SQLite transaction
  is complete by definition.
- `legacy_workspace_import_status` is removed. This hard cut has no JSON import
  or replay authority.

### R4. One clean application `local.sqlite`

- The application opens one local database at the app data root. Its path is not
  derived from a workspace UUID.
- The database is created from the target schema and starts empty.
- Old `<workspace-id>.local.sqlite` files are not read, merged, copied, or
  imported.
- Workspace JSON cache/UI/sidebar/inbox/settings files are not read, replayed,
  or imported. Their runtime readers and writers are removed.
- `preferences.global.json` remains supported and is not moved into SQLite.
- Missing local rows use deterministic defaults. Failure to open the entire
  local database defaults all local state and does not change the core result.
- Local writes are independent transactions. A local write failure does not
  roll back or invalidate core.

This intentionally resets notification history, cursors, recent targets,
window/sidebar memory, workspace-scoped settings, and rebuildable caches once at
cutover. The accepted cost is loss of non-authoritative local state; the gain is
removing all import/replay/compatibility machinery and eliminating local state
as a boot dependency.

### R5. Explicit local ownership

- Workspace continuation and workspace-scoped feature rows include
  `workspace_id` in their primary key.
- Window frame and sidebar presentation are keyed by durable `window_id`, not a
  workspace.
- The current single-window product persists one row with `window_role =
  'main'`. On first use it generates a UUIDv7 `window_id`; later launches find
  the same row by the stable role.
- Repository/worktree/PR caches are keyed globally by repo/worktree identity and
  have no workspace owner.
- Cross-database references are validated in code after core loads because
  SQLite cannot enforce foreign keys across separate files. Stale local rows
  default or disappear without changing core.

### R6. Pane and tab close lifecycle

Close undo is process-local. The durable pane row records the deadline so a
crash cannot turn a closed pane into an immortal one; the layout restoration
snapshot remains in memory and is not promoted into a new persistence system.

```mermaid
stateDiagram-v2
    [*] --> Active
    Active --> Backgrounded: explicit remove-from-layout without close
    Backgrounded --> Active: explicit reactivate
    Active --> PendingUndo: close pane or tab
    Backgrounded --> PendingUndo: close backgrounded pane
    PendingUndo --> Active: undo before deadline in same process
    PendingUndo --> Destroyed: 15-minute deadline
    PendingUndo --> Destroyed: next startup after process ended
    Destroyed --> [*]
```

Normative behavior:

- The TTL is one compile-time product policy: 15 minutes. The coordinator and
  `SurfaceManager` do not own different deadlines.
- Closing a tab gives every pane and owned drawer child in that tab the same
  deadline.
- Closing a pane gives that pane and its owned drawer children the same
  deadline.
- Closing removes layout membership immediately but keeps the pane record and
  terminal ZMX identity while undo remains possible.
- Core persistence treats `backgrounded` and `pendingUndo` panes as an explicit
  off-layout pane pool. Composition validation permits those two residencies
  outside tab/drawer membership and rejects `active` panes outside membership.
  A close and its resulting pool membership persist atomically, so restart can
  never resurrect the pre-close tab merely because autosave rejected the pane.
- Undo before the deadline cancels finalization, restores composition from the
  process-local close snapshot, and returns the pane to `active`.
- Expiry is one coordinator-owned finalization command. It removes the undo
  entry, destroys/retire the Ghostty surface, clears runtime state, invokes
  `ZmxBackend.destroySessionByID` for terminal panes, removes the pane plus owned
  content/drawer rows from live state, and commits the resulting core deletion.
- ZMX "already absent" is successful idempotent cleanup. Other backend failures
  are diagnosed; they do not resurrect the pane or invalidate core.
- On next startup, any persisted `pendingUndo` pane is finalized immediately
  because the process-local layout snapshot no longer exists.
- Capacity limits may evict the oldest undo entry early only if eviction runs
  the same complete finalization path. Capacity eviction must never discard only
  the snapshot while retaining the pane/session.
- Every other permanent pane deletion, including explicit purge of a
  `backgrounded` pane, uses the same subtree finalizer. Parent panes and all
  owned drawer children retire their model, view slot, surface, runtime state,
  and terminal ZMX session together.

### R7. Orphan semantics are narrow

The target pane lifecycle has no worktree-derived `orphaned` residency.

- A pane in a tab/drawer remains active when its repo/worktree disappears. Its
  optional facet clears; its CWD and terminal continue.
- `backgrounded` means an intentional recoverable pane outside layout
  membership. It is not an error and is not subject to the close TTL.
- `pendingUndo` means an intentional close outside layout membership and is
  subject to the 15-minute deadline.
- An `active` pane outside tab/drawer membership is invalid.
- A pane with a worktree-derived `orphaned` value is converted once during the
  core schema cutover:
  - if it still has tab/drawer membership, it becomes `active` and remains open;
  - if it has no membership, its pane/content rows are deleted as stale state.
- No ongoing startup repair engine, orphan receipt, or topology-driven pane
  collector is introduced.

### R8. Failure containment and observability

Existing diagnostics must distinguish:

- core open/migration/validation/commit failure;
- local database unavailable and local lane read/write failure;
- local stale-reference defaulting;
- pane undo started, undone, expired, finalized, and backend cleanup failed.

OTLP output must not include raw paths, pane titles, notes, notification bodies,
terminal content, or session IDs.

### R9. MainActor remains a bounded UI-state boundary

This persistence correction must reduce or preserve MainActor work. It must not
move database, lifecycle, or collection computation onto MainActor merely
because a coordinator or atom is MainActor-isolated.

MainActor may perform only:

- shallow capture of immutable `Sendable` state needed by an off-main worker;
- bounded identity lookup and validation required to start a transition;
- direct mutation of canonical UI atoms;
- application of an already-prepared result;
- AppKit, SwiftUI observation, and embedded Ghostty calls that require
  MainActor ownership.

MainActor must not perform:

- SQLite open, migration, query, encoding, transaction, or quarantine work;
- filesystem, repository, subprocess, or ZMX operations;
- composition preparation or schema validation;
- collection-wide sorting, filtering, grouping, diffing, reconciliation,
  aggregation, or cache rebuilding;
- timer waiting, retry loops, or cleanup polling;
- rebuilding large persistence payloads from observable state on every save.

An `@MainActor` coordinator owns sequencing, not computation. It captures a
small typed request, calls an actor or `@concurrent nonisolated` worker, and
applies the prepared result. Atoms remain canonical state or pure derived state
with small selector-style transforms; they do not become persistence planners,
cleanup engines, or background-work substitutes.

For persistence, capture uses shallow value/COW snapshots or incrementally
maintained changed-row inputs. Mapping those values into SQL rows, validating
the aggregate, and performing I/O happens after leaving MainActor. Repository
or watch-folder count must not multiply synchronous MainActor work.

```mermaid
flowchart LR
    UI["MainActor atoms/UI"]
    Capture["bounded typed capture"]
    Worker["off-main preparation / actor I/O"]
    Apply["small MainActor apply"]

    UI --> Capture
    Capture --> Worker
    Worker --> Apply
    Apply --> UI
```

## Exact schema changes

### Core current-to-target delta

| Object | Current | Target |
| --- | --- | --- |
| `watched_path` | workspace-owned; unique within workspace | global; `stable_key` globally unique |
| `repo` | workspace-owned; unique within workspace | global; `stable_key` globally unique |
| `worktree` | composite repo/workspace FK | global; owned only by `repo_id` |
| `repo_tag` | workspace-qualified key/FK | `(repo_id, tag)` |
| `unavailable_repo` | workspace-qualified key/FK | one row per global `repo_id` |
| `pane` | topology facets must share workspace; supports worktree-derived orphan fields | global optional facets; no orphan fields; checked close residency |
| `workspace_sqlite_snapshot_status` | cross-database completion state | dropped |
| `legacy_workspace_import_status` | legacy import/replay state | dropped |

This is not a rebuild of all domain data. SQLite cannot alter the existing
topology foreign keys, primary keys, or uniqueness constraints in place, so the
five topology tables require replacement. AgentStudio uses system SQLite and
cannot assume SQLite 3.53; the current linked runtime is 3.51, which cannot add
the pane residency `CHECK` in place. The forward GRDB migration therefore
rebuilds those five topology tables and `pane` in one transaction.
Rows and identifiers are copied 1:1 except for the explicitly defined obsolete
orphan-state cutover above.

Previously shipped GRDB migration bodies and identifiers remain unchanged. One
new forward migration produces the target schema; this preserves upgradeability
without retaining any old runtime read/write path.

The migration does not merge duplicate entities. If the existing rows cannot
satisfy the target global uniqueness constraints, the transaction fails and
leaves the original schema/data unchanged.

### Target `core.sqlite` DDL: global topology

```sql
CREATE TABLE watched_path (
    id         TEXT PRIMARY KEY,
    path       TEXT NOT NULL,
    stable_key TEXT NOT NULL UNIQUE,
    added_at   REAL NOT NULL
);

CREATE TABLE repo (
    id          TEXT PRIMARY KEY,
    name        TEXT NOT NULL,
    repo_path   TEXT NOT NULL,
    stable_key  TEXT NOT NULL UNIQUE,
    created_at  REAL NOT NULL,
    is_favorite INTEGER NOT NULL DEFAULT 0
                CHECK (is_favorite IN (0, 1)),
    note        TEXT
);

CREATE TABLE worktree (
    id               TEXT PRIMARY KEY,
    repo_id          TEXT NOT NULL
                     REFERENCES repo(id) ON DELETE CASCADE,
    name             TEXT NOT NULL,
    path             TEXT NOT NULL,
    stable_key       TEXT NOT NULL UNIQUE,
    is_main_worktree INTEGER NOT NULL
                     CHECK (is_main_worktree IN (0, 1)),
    note             TEXT
);

CREATE INDEX idx_worktree_repo_id ON worktree(repo_id);

CREATE TABLE repo_tag (
    repo_id TEXT NOT NULL REFERENCES repo(id) ON DELETE CASCADE,
    tag     TEXT NOT NULL CHECK (
        tag = trim(tag) AND length(tag) BETWEEN 1 AND 64
    ),
    PRIMARY KEY (repo_id, tag)
);

CREATE INDEX idx_repo_tag_tag ON repo_tag(tag);

CREATE TABLE unavailable_repo (
    repo_id TEXT PRIMARY KEY REFERENCES repo(id) ON DELETE CASCADE
);
```

### Target `core.sqlite` DDL: touched pane table

The composition graph tables remain unchanged. The `pane` table is shown in
full because its topology references and lifecycle columns change.

```sql
CREATE TABLE pane (
    id                      TEXT PRIMARY KEY,
    workspace_id            TEXT NOT NULL
                            REFERENCES workspace(id) ON DELETE CASCADE,
    content_type            TEXT NOT NULL CHECK (
        content_type IN (
            'terminal', 'browser', 'diff', 'editor',
            'review', 'agent', 'codeViewer'
        )
        OR content_type GLOB 'plugin:?*'
    ),
    execution_backend       TEXT NOT NULL,
    facet_repo_id           TEXT REFERENCES repo(id) ON DELETE SET NULL,
    facet_worktree_id       TEXT REFERENCES worktree(id) ON DELETE SET NULL,
    launch_directory        TEXT,
    title                   TEXT NOT NULL,
    note                    TEXT,
    cwd                     TEXT,
    checkout_ref            TEXT,
    residency_kind          TEXT NOT NULL,
    pending_undo_expires_at REAL,
    kind                    TEXT NOT NULL,
    parent_pane_id          TEXT REFERENCES pane(id) ON DELETE CASCADE,
    created_at              REAL NOT NULL,
    updated_at              REAL NOT NULL,
    CHECK (
        (
            residency_kind = 'pendingUndo'
            AND pending_undo_expires_at IS NOT NULL
        )
        OR (
            residency_kind IN ('active', 'backgrounded')
            AND pending_undo_expires_at IS NULL
        )
    )
);

CREATE INDEX idx_pane_workspace_id ON pane(workspace_id);

CREATE TRIGGER pane_parent_matches_workspace
BEFORE INSERT ON pane
WHEN NEW.parent_pane_id IS NOT NULL
AND (SELECT workspace_id FROM pane WHERE id = NEW.parent_pane_id)
    != NEW.workspace_id
BEGIN
    SELECT RAISE(ABORT, 'pane parent_pane_id must belong to pane workspace');
END;

CREATE TRIGGER pane_parent_update_matches_workspace
BEFORE UPDATE OF parent_pane_id, workspace_id ON pane
WHEN NEW.parent_pane_id IS NOT NULL
AND (SELECT workspace_id FROM pane WHERE id = NEW.parent_pane_id)
    != NEW.workspace_id
BEGIN
    SELECT RAISE(ABORT, 'pane parent_pane_id must belong to pane workspace');
END;

CREATE TRIGGER pane_facets_match_repository_insert
BEFORE INSERT ON pane
WHEN NEW.facet_repo_id IS NOT NULL
AND NEW.facet_worktree_id IS NOT NULL
AND (SELECT repo_id FROM worktree WHERE id = NEW.facet_worktree_id)
    != NEW.facet_repo_id
BEGIN
    SELECT RAISE(ABORT, 'pane worktree facet must belong to repo facet');
END;

CREATE TRIGGER pane_facets_match_repository_update
BEFORE UPDATE OF facet_repo_id, facet_worktree_id ON pane
WHEN NEW.facet_repo_id IS NOT NULL
AND NEW.facet_worktree_id IS NOT NULL
AND (SELECT repo_id FROM worktree WHERE id = NEW.facet_worktree_id)
    != NEW.facet_repo_id
BEGIN
    SELECT RAISE(ABORT, 'pane worktree facet must belong to repo facet');
END;
```

The existing content-type immutability and pane-content-family triggers remain
unchanged. These obsolete triggers are dropped:

```sql
DROP TRIGGER IF EXISTS pane_facet_repo_matches_workspace;
DROP TRIGGER IF EXISTS pane_facet_repo_update_matches_workspace;
DROP TRIGGER IF EXISTS pane_facet_worktree_matches_workspace;
DROP TRIGGER IF EXISTS pane_facet_worktree_update_matches_workspace;
```

These obsolete tables are dropped without replacement:

```sql
DROP TABLE workspace_sqlite_snapshot_status;
DROP TABLE legacy_workspace_import_status;
```

### New application `local.sqlite`: complete target DDL

This file is created clean. The following is its complete product schema; GRDB's
own migration table is implicit and is not a product table.

```mermaid
flowchart TB
    subgraph WorkspaceRows["workspace_id owned rows"]
        WC[workspace cursor]
        TC[tab cursor]
        AC[arrangement cursor]
        DC[drawer cursors]
        RT[recent targets]
        NI[notifications]
        FP[feature preferences]
    end

    subgraph WindowRows["window_id owned rows"]
        WS[window frame + sidebar state]
        WG[expanded sidebar groups]
        WS --> WG
    end

    subgraph GlobalRows["application-global rows"]
        CM[cache metadata singleton]
        RC[repo enrichment by repo_id]
        WTC[worktree enrichment by worktree_id]
        PR[PR count by worktree_id]
    end
```

#### Workspace continuation

```sql
CREATE TABLE local_workspace_cursor (
    workspace_id  TEXT PRIMARY KEY,
    active_tab_id TEXT,
    updated_at    REAL NOT NULL
);

CREATE TABLE local_tab_cursor (
    workspace_id          TEXT NOT NULL,
    tab_id                TEXT NOT NULL,
    active_arrangement_id TEXT,
    updated_at            REAL NOT NULL,
    PRIMARY KEY (workspace_id, tab_id)
);

CREATE INDEX idx_local_tab_cursor_workspace
ON local_tab_cursor(workspace_id);

CREATE TABLE local_arrangement_cursor (
    workspace_id   TEXT NOT NULL,
    arrangement_id TEXT NOT NULL,
    active_pane_id TEXT,
    updated_at     REAL NOT NULL,
    PRIMARY KEY (workspace_id, arrangement_id)
);

CREATE INDEX idx_local_arrangement_cursor_workspace
ON local_arrangement_cursor(workspace_id);

CREATE TABLE local_drawer_cursor (
    workspace_id TEXT NOT NULL,
    drawer_id    TEXT NOT NULL,
    is_expanded  INTEGER NOT NULL CHECK (is_expanded IN (0, 1)),
    updated_at   REAL NOT NULL,
    PRIMARY KEY (workspace_id, drawer_id)
);

CREATE INDEX idx_local_drawer_cursor_workspace
ON local_drawer_cursor(workspace_id);

CREATE UNIQUE INDEX idx_local_drawer_one_expanded_per_workspace
ON local_drawer_cursor(workspace_id)
WHERE is_expanded = 1;

CREATE TABLE local_arrangement_drawer_cursor (
    workspace_id    TEXT NOT NULL,
    arrangement_id  TEXT NOT NULL,
    drawer_id       TEXT NOT NULL,
    active_child_id TEXT,
    updated_at      REAL NOT NULL,
    PRIMARY KEY (workspace_id, arrangement_id, drawer_id)
);

CREATE INDEX idx_local_arrangement_drawer_cursor_workspace
ON local_arrangement_drawer_cursor(workspace_id);
```

#### Window and sidebar presentation

```sql
CREATE TABLE local_window_state (
    window_id         TEXT PRIMARY KEY,
    window_role       TEXT NOT NULL UNIQUE CHECK (window_role = 'main'),
    sidebar_width     REAL NOT NULL,
    window_frame_json TEXT,
    filter_text       TEXT NOT NULL,
    is_filter_visible INTEGER NOT NULL CHECK (is_filter_visible IN (0, 1)),
    sidebar_collapsed INTEGER NOT NULL CHECK (sidebar_collapsed IN (0, 1)),
    sidebar_surface   TEXT NOT NULL CHECK (sidebar_surface IN ('repos', 'inbox')),
    updated_at        REAL NOT NULL
);

CREATE TABLE local_window_sidebar_expanded_group (
    window_id TEXT NOT NULL
              REFERENCES local_window_state(window_id) ON DELETE CASCADE,
    group_key TEXT NOT NULL,
    PRIMARY KEY (window_id, group_key)
);
```

#### Recent targets

```sql
CREATE TABLE local_recent_workspace_target (
    workspace_id  TEXT NOT NULL,
    id            TEXT NOT NULL,
    path          TEXT NOT NULL,
    display_title TEXT NOT NULL,
    subtitle      TEXT NOT NULL,
    repo_id       TEXT,
    worktree_id   TEXT,
    kind          TEXT NOT NULL CHECK (kind IN ('worktree', 'cwdOnly')),
    last_opened_at REAL NOT NULL,
    PRIMARY KEY (workspace_id, id),
    CHECK (
        (
            kind = 'worktree'
            AND repo_id IS NOT NULL
            AND worktree_id IS NOT NULL
        )
        OR (
            kind = 'cwdOnly'
            AND repo_id IS NULL
            AND worktree_id IS NULL
        )
    )
);

CREATE INDEX idx_local_recent_target_workspace_time
ON local_recent_workspace_target(workspace_id, last_opened_at);
```

#### Notification inbox

```sql
CREATE TABLE local_notification_inbox_collapsed_group (
    workspace_id TEXT NOT NULL,
    group_key    TEXT NOT NULL,
    PRIMARY KEY (workspace_id, group_key)
);

CREATE TABLE local_notification_inbox_item (
    workspace_id                    TEXT NOT NULL,
    id                              TEXT NOT NULL,
    timestamp                       REAL NOT NULL,
    kind                            TEXT NOT NULL,
    title                           TEXT NOT NULL,
    body                            TEXT,
    source_kind                     TEXT NOT NULL,
    pane_id                         TEXT,
    tab_id                          TEXT,
    tab_display_label               TEXT,
    tab_ordinal                     INTEGER,
    repo_id                         TEXT,
    repo_name                       TEXT,
    worktree_id                     TEXT,
    worktree_name                   TEXT,
    branch_name                     TEXT,
    pane_display_label              TEXT,
    pane_ordinal                    INTEGER,
    pane_role                       TEXT,
    parent_pane_id                  TEXT,
    parent_pane_display_label       TEXT,
    parent_pane_ordinal             INTEGER,
    drawer_ordinal                  INTEGER,
    runtime_display_label           TEXT,
    activity_burst_window_id        TEXT,
    activity_session_id             TEXT,
    activity_event_count            INTEGER,
    activity_rows_added             INTEGER,
    activity_threshold_rows         INTEGER,
    activity_latest_rows            INTEGER,
    claim_pane_id                   TEXT,
    claim_lane                      TEXT,
    claim_semantic                  TEXT,
    claim_session_id                TEXT,
    is_read                         INTEGER NOT NULL
                                    CHECK (is_read IN (0, 1)),
    is_dismissed_from_pane_inbox    INTEGER NOT NULL
                                    CHECK (is_dismissed_from_pane_inbox IN (0, 1)),
    PRIMARY KEY (workspace_id, id),
    CHECK (
        (
            claim_pane_id IS NULL
            AND claim_lane IS NULL
            AND claim_semantic IS NULL
            AND claim_session_id IS NULL
        )
        OR (
            claim_pane_id IS NOT NULL
            AND claim_lane IN ('activity', 'actionNeeded', 'safety')
            AND claim_semantic IS NOT NULL
        )
    )
);

CREATE INDEX idx_notification_workspace_timestamp
ON local_notification_inbox_item(workspace_id, timestamp);

CREATE INDEX idx_notification_workspace_pane
ON local_notification_inbox_item(workspace_id, pane_id);

CREATE INDEX idx_notification_workspace_tab
ON local_notification_inbox_item(workspace_id, tab_id);

CREATE INDEX idx_notification_workspace_repo
ON local_notification_inbox_item(workspace_id, repo_id);

CREATE INDEX idx_notification_workspace_worktree
ON local_notification_inbox_item(workspace_id, worktree_id);

CREATE INDEX idx_notification_claim_exact
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

CREATE INDEX idx_notification_claim_session
ON local_notification_inbox_item(
    workspace_id,
    claim_pane_id,
    claim_session_id
)
WHERE claim_pane_id IS NOT NULL
  AND claim_session_id IS NOT NULL
  AND claim_lane IN ('activity', 'actionNeeded');
```

Notification meaning, coalescence, retention, and presentation are unchanged.
Only the shared-file key shape changes.

#### Typed workspace preferences

```sql
CREATE TABLE local_editor_preferences (
    workspace_id         TEXT PRIMARY KEY,
    bookmarked_editor_id TEXT,
    updated_at           REAL NOT NULL
);

CREATE TABLE local_repo_explorer_preferences (
    workspace_id    TEXT PRIMARY KEY,
    grouping_mode   TEXT NOT NULL
                    CHECK (grouping_mode IN ('repo', 'pane', 'tab')),
    sort_order      TEXT NOT NULL
                    CHECK (sort_order IN ('ascending', 'descending')),
    visibility_mode TEXT NOT NULL
                    CHECK (visibility_mode IN ('all', 'favoritesOnly')),
    updated_at      REAL NOT NULL
);

CREATE TABLE local_inbox_notification_preferences (
    workspace_id            TEXT PRIMARY KEY,
    grouping                 TEXT NOT NULL
                             CHECK (grouping IN ('byTab', 'byRepo', 'byPane', 'none')),
    sort_order               TEXT NOT NULL
                             CHECK (sort_order IN ('newestFirst', 'oldestFirst')),
    bell_enabled             INTEGER NOT NULL
                             CHECK (bell_enabled IN (0, 1)),
    global_content_mode      TEXT NOT NULL
                             CHECK (global_content_mode IN ('rollUpAlerts', 'activity', 'all')),
    global_row_state_filter  TEXT NOT NULL
                             CHECK (global_row_state_filter IN ('unreadOnly', 'all')),
    pane_content_mode        TEXT NOT NULL
                             CHECK (pane_content_mode IN ('rollUpAlerts', 'activity', 'all')),
    pane_row_state_filter    TEXT NOT NULL
                             CHECK (pane_row_state_filter IN ('unreadOnly', 'all')),
    updated_at               REAL NOT NULL
);
```

#### Global rebuildable caches

```sql
CREATE TABLE cache_metadata (
    singleton_id    INTEGER PRIMARY KEY CHECK (singleton_id = 1),
    source_revision INTEGER NOT NULL DEFAULT 0 CHECK (source_revision >= 0),
    last_rebuilt_at REAL
);

CREATE TABLE cache_repo_enrichment (
    repo_id           TEXT PRIMARY KEY,
    state             TEXT NOT NULL,
    origin            TEXT,
    upstream          TEXT,
    group_key         TEXT,
    remote_slug       TEXT,
    organization_name TEXT,
    display_name      TEXT,
    updated_at        REAL NOT NULL,
    payload_json      TEXT
);

CREATE TABLE cache_worktree_enrichment (
    worktree_id      TEXT PRIMARY KEY,
    repo_id          TEXT NOT NULL,
    branch           TEXT,
    is_main_worktree INTEGER NOT NULL CHECK (is_main_worktree IN (0, 1)),
    updated_at       REAL NOT NULL,
    payload_json     TEXT
);

CREATE INDEX idx_cache_worktree_repo
ON cache_worktree_enrichment(repo_id);

CREATE TABLE cache_pull_request_count (
    worktree_id TEXT PRIMARY KEY,
    repo_id     TEXT,
    count       INTEGER NOT NULL CHECK (count >= 0),
    updated_at  REAL NOT NULL
);

CREATE INDEX idx_cache_pull_request_repo
ON cache_pull_request_count(repo_id);
```

### Objects deliberately absent from the target

```text
core.sqlite
  legacy_workspace_import_status
  workspace_sqlite_snapshot_status
  topology workspace_id columns and workspace cascades
  pane orphan_reason_kind
  pane orphan_worktree_path
  pane/worktree same-workspace triggers

local.sqlite
  local_workspace_sqlite_snapshot_status
  local_persistence_lane_marker
  cache_notification_count
  workspace-owned repository/worktree cache columns
  workspace-owned window/sidebar tables

standalone persistence
  <workspace-id>.local.sqlite readers/writers
  workspace cache/UI/sidebar/inbox/settings JSON readers/writers
  surface-checkpoint.json dead APIs
```

## Startup and save contracts

### Startup

```mermaid
flowchart TD
    A[Open core.sqlite] --> B{Core migrate + validate}
    B -->|failure| C[Core integrity error]
    B -->|success| D[Install authoritative topology + composition]
    D --> E[Finalize persisted pendingUndo panes]
    E --> F[Open one local.sqlite independently]
    F -->|available| G[Load typed local lanes]
    F -->|unavailable| H[Use deterministic local defaults]
    G --> I[Default missing/invalid/stale lane values]
    H --> J[Present app]
    I --> J
```

No local result changes the already accepted core result.

### Save

```mermaid
flowchart LR
    CoreMutation[Authoritative mutation] --> CoreTx[One core.sqlite transaction]
    CoreTx -->|commit| CoreDone[Complete]
    CoreTx -->|failure| CoreRollback[Previous core remains]

    LocalMutation[Local presentation/cache mutation] --> LocalTx[Independent local.sqlite transaction]
    LocalTx -->|failure| LocalDefault[Keep live state; diagnose; default on next load]
```

There is no distributed transaction, matching completion token, receipt, replay
engine, or atom-owned persistence logic.

## Design tradeoffs

### Global topology requires a transactional table rebuild

Gain:

- the database finally matches the domain model;
- workspace deletion cannot destroy repositories;
- multiple compositions can reference the same topology.

Cost:

- five topology tables are mechanically rebuilt because their foreign-key,
  primary-key, and uniqueness definitions change; `pane` is rebuilt in the
  same forward core migration because the supported SQLite runtime cannot add
  its residency `CHECK` in place;
- a real pre-existing global-key conflict fails the migration rather than being
  guessed away.

### Clean local database discards local history

Gain:

- no sidecar consolidation, JSON import, replay prevention, receipts, or
  compatibility readers;
- local failure can never make core invalid;
- one clear application-level owner for non-authoritative state.

Cost:

- one-time reset of notification history, local preferences, recent targets,
  cursors, window/sidebar memory, and caches;
- users re-establish preferences through ordinary use.

### Undo does not survive process restart

Gain:

- no durable tab-layout snapshot schema or recovery engine;
- closed panes cannot remain indefinitely because an app exited during the
  undo window;
- one process owns the undo experience and one coordinator owns finalization.

Cost:

- quitting or crashing during the 15-minute window forfeits undo;
- startup finalizes those panes instead of restoring them.

### One physical local database is one physical failure domain

Gain:

- one connection owner and one schema;
- correct global cache ownership;
- no workspace/window equivalence.

Cost:

- file-level corruption can reset every local lane at once, although each lane
  remains logically independent when the database is readable.

## Proof expectations

The implementation plan must turn these into permanent tests and product proof:

1. Core schema inspection shows no workspace FK/cascade in global topology and
   no obsolete completion/import tables.
2. Deleting inactive, active, and final workspaces removes only their
   composition; global topology and metadata remain byte-for-byte equivalent.
3. The same repo/worktree can be referenced from two workspace compositions.
4. A barrier-controlled save proves an older captured composition cannot replace
   newer topology after an off-main suspension.
5. A forward migration preserves topology UUIDs and values 1:1 and rolls back
   entirely on target uniqueness failure.
6. Core save interruption leaves either the previous complete state or the new
   complete state, never a staged incomplete state.
7. Core hydration reads one consistent generation while a concurrent writer
   commits.
8. Missing/corrupt/unavailable `local.sqlite` still opens valid core and presents
   usable deterministic tab/pane/sidebar defaults.
9. Production opens exactly one local database and never reads old local
   sidecars or workspace JSON persistence.
10. Every new local table round-trips its typed values and rejects invalid enum,
   boolean, claim, and key shapes.
11. Pane close and tab close both enter `pendingUndo` with one 15-minute policy;
    undo before expiry restores them.
12. Close-tab and background-pane intermediate states flush to SQLite and reload
    without `paneNotOwnedByTab`; a close that committed cannot reappear after
    restart.
13. Expiry and explicit backgrounded-pane purge remove the full parent/drawer
    subtree: pane/content/layout remnants, view slots, Ghostty surfaces, runtime
    state, and every terminal ZMX session. Capacity eviction uses the identical
    path.
14. Restart with persisted `pendingUndo` state finalizes it without attempting a
    durable undo restore.
15. Removing a repo/worktree clears pane facets but leaves the pane, CWD,
    surface, and ZMX session alive.
16. Core cutover converts in-composition legacy orphan rows to active and removes
    out-of-composition legacy orphan rows; no `orphaned` residency remains.
17. Atoms contain no persistence, subprocess, timer, or lifecycle-coordination
    logic.
18. MainActor proof shows persistence and lifecycle paths perform only bounded
    capture/transition/apply work there. Composition preparation, row mapping,
    SQLite, ZMX, filesystem, retries, timers, and collection-wide computation
    execute off MainActor. A production-shaped repository/watch-folder fixture
    does not increase synchronous MainActor work in proportion to topology size.

The later plan owns exact commands and sequencing. Proof should use the existing
Swift test suite, SQLite integration fixtures, ZMX E2E lane for real session
destruction, and a bounded debug-app smoke. No ad hoc proof scripts are required.

## Non-goals

- Multi-window creation or restoration.
- Repository discovery, filesystem watching, Git scheduling, EventBus, Ghostty
  callback admission, or terminal activity redesign.
- Notification meaning, retention, grouping, or coalescence redesign.
- Durable undo across app restarts.
- Automatic deletion of unreferenced repositories or worktrees.
- A generic recovery framework, reconciliation engine, receipt protocol,
  replay system, compatibility layer, or persistence logic in atoms.
- Preserving non-authoritative local data from the old sidecars/JSON files.

## Spec boundary and separability map

```text
Global topology repository
  owns: watched paths, repos, worktrees, tags, availability
  exposes: global typed reads/mutations

Workspace composition repository
  owns: workspace, pane, tab, arrangement, drawer graph
  references: global repo/worktree IDs
  guarantees: one atomic core transaction

Local persistence repository
  owns: one local.sqlite and typed non-authoritative lanes
  exposes: loaded value or deterministic default

Workspace surface coordinator
  owns: close/undo/finalize sequencing across live state,
        Ghostty surface, runtime state, and ZMX

Atoms
  own: live canonical state and pure derived projections
  do not own: persistence, timers, subprocess cleanup, migration,
              or lifecycle coordination

Off-main workers and actors
  own: validation, row mapping, collection computation, SQLite I/O,
       filesystem work, timers, retries, and ZMX subprocess operations
```

The core schema correction, clean local database, and pane lifecycle correction
are separable implementation slices. They share one hard boundary: local state
must never validate core, and topology loss must never become pane destruction.
