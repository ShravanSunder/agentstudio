# Persistence Ownership Hard Cut

Date: 2026-07-21
Status: Draft

## Read this first

AgentStudio has three different kinds of state that are currently mixed together:

1. Global repositories and worktrees that exist independently of any workspace.
2. Workspace composition: panes, tabs, arrangements, and drawers.
3. Local presentation and cache state that may be missing without making the workspace invalid.

The current SQLite schema still says that a workspace owns repositories and worktrees. The current save protocol also makes a valid core workspace depend on a matching local preference database. Both relationships are wrong.

This spec makes the ownership explicit:

```text
core.sqlite
  global repository topology
  durable workspace compositions

local.sqlite
  workspace-local continuation state
  window-keyed presentation state
  repository/worktree caches
  local feature state
```

`core.sqlite` is authoritative and internally consistent. `local.sqlite` is non-authoritative and always allowed to fall back to deterministic defaults.

## Current evidence

- `CanonicalRepo` and `Worktree` already have no workspace identity; `Worktree` refers only to its repository.
- `WorkspaceCoreMigrations` still places `workspace_id` foreign keys and workspace-delete cascades on watched paths, repositories, worktrees, tags, and availability.
- `WorkspaceSQLiteSaveCoordinator` still captures repository topology, workspace composition, cursors, and window state into one save bundle.
- `WorkspaceSQLiteStoreBackend` and `WorkspaceSQLiteDatastore` still require matching core/local completion state.
- `WorkspaceSQLiteDatastoreConfiguration` still chooses a local database URL from a workspace UUID.

These source anchors make this a persistence ownership correction, not a new domain-model invention.

## Critical defect: workspace deletion destroys global topology

This is a release-blocking ownership bug, not ordinary schema cleanup.

The current schema attaches application-level topology to `workspace(id)` through cascading foreign keys:

```text
DELETE workspace W
  │
  ├── ON DELETE CASCADE ──► watched_path.workspace_id
  ├── ON DELETE CASCADE ──► repo.workspace_id
  │                            │
  │                            ├──► worktree(repo_id, workspace_id)
  │                            ├──► repo_tag(repo_id, workspace_id)
  │                            └──► unavailable_repo(repo_id, workspace_id)
  └── intended cascade ─────► panes, tabs, arrangements, and drawers owned by W
```

`WorkspaceCoreRepository.deleteWorkspace` issues a plain `DELETE FROM workspace`. SQLite therefore removes both the intended workspace composition and the unrelated watched paths, repositories, worktrees, tags, and availability rows. The live domain model already treats repository topology as application-global, so the database delete boundary contradicts the product ownership boundary.

The hard-cut invariant is:

```text
delete workspace
  = delete that workspace's composition
  + update active-workspace selection when necessary
  + zero mutation to global repository topology
```

Only an explicit repository-topology mutation may delete a repository or worktree. The migration, repository API, destructive-path tests, and foreign-key inspection must all prove this invariant; a passing ordinary workspace-delete test that checks only workspace rows is insufficient.

## Customer problem

The current design can turn unrelated local state into destructive or startup-blocking behavior:

- A failed local cursor or window-state write can leave the matching core snapshot incomplete and prevent the app from opening on every later launch.
- Deleting a workspace can cascade through SQLite into watched paths, repositories, and worktrees even though repositories are application-level resources.
- The same repository cannot be referenced naturally by multiple workspace compositions because persistence still scopes the repository to one workspace.
- Per-workspace local database files encode the obsolete assumption that one workspace equals one macOS window.
- Window presentation, workspace continuation, global repository caches, and notification state share an unclear ownership convention.

## Product intent

AgentStudio must preserve durable workspace composition without allowing preferences or caches to control whether the application can open. Repositories and worktrees must remain available independently of which compositions or windows reference them.

Success means:

- deleting or switching a workspace cannot delete global repository topology;
- one repository or worktree can be referenced by multiple compositions;
- a missing, stale, invalid, corrupt, or unavailable `local.sqlite` cannot invalidate `core.sqlite` or block startup;
- only one application `local.sqlite` is used;
- each local row reveals its actual owner through an explicit key;
- the current single-window UI retains its presentation memory without pretending that a window is a workspace.

## Domain vocabulary

### Repository topology

Application-level watched paths, repositories, worktrees, repository metadata, and topology availability. A worktree belongs to a repository. Neither belongs to a workspace.

### Workspace composition

A durable composition of panes, tabs, arrangements, and drawers. A composition may reference global repository and worktree IDs, but it does not own those entities.

### Window shell

Presentation state belonging to a macOS window, such as its frame and sidebar presentation. Every persisted window row uses a durable `window_id`. AgentStudio currently creates one main-window row; the schema does not confuse that row with a workspace.

### Local lane

A logically independent group of non-authoritative rows. Failure in one lane falls back only that lane when the database remains readable. Failure to open the entire local database falls back every local lane without affecting core.

## Requirements

### R1. Global repository ownership

Watched paths, repositories, worktrees, and unavailable-repository state are application-level core data.

- Repository identity does not contain `workspace_id`.
- Worktree identity contains `repo_id` and does not contain `workspace_id`.
- Deleting a workspace must not delete or mutate repository topology.
- In particular, workspace deletion must leave watched paths, repositories, worktrees, repository tags, favorite/note metadata, and unavailable-repository state unchanged.
- Repository topology APIs must not require `workspaceId` to fetch or mutate global topology.
- Workspace composition saves must not carry or replace global topology.
- Global topology has one mutation authority; an older captured state must not overwrite newer accepted repository/worktree state.
- Deleting a global repository or worktree requires an explicit topology mutation. Automatic collection of unreferenced topology is outside this spec.
- Existing repository and worktree identities must remain stable across the hard cut when they are unambiguous.
- Newly generated identities use UUIDv7. Existing identifiers are accepted as stored.

### R2. Workspace composition references global topology

Workspace-owned pane, tab, arrangement, and drawer rows retain `workspace_id`.

- Pane repository/worktree references target global repository/worktree IDs.
- A pane and its referenced repository/worktree do not need a shared workspace owner.
- The same repository or worktree may be referenced from panes in multiple workspaces.
- Deleting a repository or worktree must follow an explicit reference policy; it must not be an accidental consequence of deleting a workspace.
- Optional pane references use global foreign keys with deletion behavior that leaves the composition valid, such as clearing the reference rather than deleting the pane.

### R3. One application-local database

AgentStudio uses one `local.sqlite` for all non-authoritative local persistence.

- No production path selects a local database file from a workspace UUID.
- Opening another workspace selects rows inside the same database; it does not open another database file.
- The local database remains a separate failure domain from `core.sqlite`.

### R4. Explicit local row ownership

Every local table uses the key of the thing that owns the state.

```text
Owner                          Required key
─────────────────────────────  ─────────────────────────
workspace composition         workspace_id
window shell                  window_id
repository cache              repo_id
worktree or PR cache           worktree_id, with repo_id when useful
notification                  notification ID plus its query/reference keys
```

Workspace/composition-local state includes active tab, arrangement, pane, drawer expansion, and active drawer-child cursors.

Workspace-owned tables use workspace-qualified keys even when their entity IDs are normally global:

```text
cursor family         (workspace_id, tab/arrangement/pane/drawer key)
recent target         (workspace_id, target_id)
notification          (workspace_id, notification_id)
notification group    (workspace_id, group_key)
```

Window state includes:

- window frame;
- sidebar width;
- sidebar collapsed state;
- selected sidebar surface;
- persisted sidebar filter presentation already supported by the product.
- Repo Explorer expanded groups.

Sidebar focus remains runtime-only. Newly created window IDs use UUIDv7. This spec persists the current window's identity and state but does not implement multi-window creation or restoration behavior.

Recent targets and notification rows may retain `workspace_id` where workspace filtering or continuation is part of their existing product meaning. Repository and worktree caches must not gain workspace ownership.

Global cache generation metadata uses an application singleton. It is not repeated for each workspace.

### R5. Core commit integrity

A core save is complete based only on `core.sqlite`.

- All authoritative changes for one core save commit in one SQLite transaction.
- One core load observes one consistent SQLite read transaction; it must not assemble authoritative state from independently changing reads.
- A process crash before commit leaves the previous valid core state.
- A process crash after commit leaves the new valid core state.
- Core completion must not wait for, compare against, or be cleared by a local write.
- The staged-core/local-write/core-completion protocol is removed from the runtime contract.

### R6. Local failure defaults

Local state is useful but never required to interpret valid core composition.

- Missing local rows use deterministic defaults.
- Stale local references are checked against loaded core state and defaulted when their targets no longer exist.
- Invalid values default only their logical lane when possible.
- Failure to query one local lane does not discard readable rows from unrelated lanes.
- Failure to open or migrate the entire local database defaults all local lanes.
- Local failure never changes the core load result and never reaches a startup `preconditionFailure`.
- A later ordinary local save may persist the current valid state; this does not require a general startup repair system.

Cursor defaults must produce a usable composition rather than merely setting every optional ID to `nil`:

```text
active tab          first core tab by persisted order, or nil when no tabs exist
active arrangement  selected tab's core default arrangement
active pane         first valid pane by persisted layout order
drawer expansion    all collapsed
drawer child        unset unless the composition requires a valid child
```

Default selection must not depend on dictionary iteration order, wall-clock time, or a newly generated identifier.

One `local.sqlite` provides logical lane isolation, not separate physical fault domains. Corruption that prevents opening the shared file may make every local lane unavailable together. This is accepted because no local lane is authoritative; the resulting defaults and loss must be observable, and core must remain unchanged.

### R7. Local writes are independent

- Local write failure does not roll back or invalidate a committed core save.
- A failed local write does not mutate canonical atoms or repository topology.
- Each local store reports failure through existing diagnostics and continues with its valid in-memory/default state.
- Local persistence is not performed by atoms. Atoms remain state owners or pure derived state; repositories, stores, and coordinators own persistence work.
- Core composition preparation validates only authoritative composition. A separate local-overlay boundary sanitizes cursors and window/sidebar memory before applying them to live local atoms.
- The datastore owns one local database connection/repository. Returning a constant URL from the old workspace-to-URL closure while retaining multiple workspace-keyed pools is forbidden.

### R8. Existing data has an explicit hard-cut disposition

The hard cut distinguishes durable/user-visible local data from rebuildable data:

- Core workspace composition, repositories, worktrees, metadata, and references must be preserved.
- Workspace cursors, window/sidebar memory, recent targets, and notification history should be carried into the single `local.sqlite` when their rows are valid.
- Repository/worktree enrichment and pull-request counts are rebuildable and may be regenerated rather than migrated.
- Cross-database completion tokens, local lane migration markers whose only purpose was sidecar import, and obsolete workspace ownership columns are not retained as runtime compatibility mechanisms.
- The cutover is one-way. Production does not keep parallel old/new read or write paths after successful schema migration.
- `preferences.global.json` remains the only intentionally supported standalone JSON preference file.
- The currently live `<workspace-id>.settings.json` values are copied once into typed `local.sqlite` rows during cutover; the primary and backup files are not runtime authorities afterward.
- Legacy workspace cache, UI, sidebar, inbox, and terminal checkpoint JSON files are not migration fallbacks. Their current SQLite data or deterministic defaults are authoritative.
- Normal GRDB schema migration history remains. Runtime import decisions, replay markers, archive-readiness state, dual writers, compatibility decoders, and custom cutover receipt protocols do not.

The forward core migration preserves each existing topology row, identifier, metadata value, and pane reference as stored. It does not merge topology rows, select winner identities, or synthesize metadata. If removing obsolete workspace ownership exposes an actual uniqueness violation, the migration fails transactionally and leaves the pre-migration database unchanged.

The one-time settings copy is part of the forward cutover and writes its target rows transactionally. Normal GRDB migration state and the typed target rows are its only durable authority. It must not introduce a permanent import-status table or a second recovery state machine. Once the core hard-cut migration commits, later launches never consult legacy JSON or sidecars to hydrate, merge, repair, or default local state.

Local conversion is best-effort and cannot control the core result:

```text
local conversion succeeds  -> preserve the valid retained local/settings rows
local conversion fails     -> open the committed core with deterministic local defaults
                              never replay legacy JSON or sidecars on a later launch
```

### R9. Failure containment is observable

Existing persistence telemetry must distinguish:

- core open, migration, validation, and commit failures;
- whole-local-database unavailability;
- individual local-lane read/write failures;
- stale local references defaulted against core;
- one-time hard-cut migration outcomes.

Telemetry must not include raw paths, notification bodies, prompts, or other prohibited OTLP payloads.

## Technical contract

### Normative schema changes

This section defines the required resulting schema. Migration statement order and temporary rebuild-table names belong to the implementation plan; the final ownership, keys, foreign keys, and removed tables do not.

#### `core.sqlite`: global topology tables

Current ownership columns are removed:

```text
watched_path.workspace_id     remove
repo.workspace_id             remove
worktree.workspace_id         remove
repo_tag.workspace_id         remove
unavailable_repo.workspace_id remove
```

Target shapes:

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

Global `stable_key` uniqueness matches the existing in-memory topology invariant. `worktree.repo_id` is the only ownership edge between worktrees and repositories.

#### `core.sqlite`: workspace composition references

Workspace composition tables keep `workspace_id`. The `pane` table keeps its composition ownership while its optional repository facets point to global topology:

```sql
workspace_id      TEXT NOT NULL
                  REFERENCES workspace(id) ON DELETE CASCADE

facet_repo_id     TEXT
                  REFERENCES repo(id) ON DELETE SET NULL

facet_worktree_id TEXT
                  REFERENCES worktree(id) ON DELETE SET NULL
```

The same-workspace repo/worktree triggers are removed:

```text
pane_facet_repo_matches_workspace
pane_facet_repo_update_matches_workspace
pane_facet_worktree_matches_workspace
pane_facet_worktree_update_matches_workspace
```

A replacement constraint or trigger preserves only the real relationship:

```text
when facet_repo_id and facet_worktree_id are both present,
worktree.repo_id must equal facet_repo_id
```

Deleting a workspace cascades only through workspace composition tables. Deleting global topology clears optional pane facets through `ON DELETE SET NULL`; it does not delete panes.

#### `core.sqlite`: removed cross-database validity state

The following runtime validity table is removed:

```text
workspace_sqlite_snapshot_status
```

A committed core transaction is complete by definition. Normal GRDB schema migration state is the only hard-cut marker. No replacement completion token, cutover receipt, or product-level migration state machine is introduced.

#### `local.sqlite`: workspace continuation tables

All workspace-owned local keys become explicitly workspace-qualified:

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

CREATE TABLE local_arrangement_cursor (
    workspace_id   TEXT NOT NULL,
    arrangement_id TEXT NOT NULL,
    active_pane_id TEXT,
    updated_at     REAL NOT NULL,
    PRIMARY KEY (workspace_id, arrangement_id)
);

CREATE TABLE local_drawer_cursor (
    workspace_id TEXT NOT NULL,
    drawer_id    TEXT NOT NULL,
    is_expanded  INTEGER NOT NULL CHECK (is_expanded IN (0, 1)),
    updated_at   REAL NOT NULL,
    PRIMARY KEY (workspace_id, drawer_id)
);

CREATE UNIQUE INDEX idx_local_drawer_one_expanded_per_workspace
ON local_drawer_cursor(workspace_id)
WHERE is_expanded = 1;

CREATE TABLE local_arrangement_drawer_cursor (
    workspace_id   TEXT NOT NULL,
    arrangement_id TEXT NOT NULL,
    drawer_id      TEXT NOT NULL,
    active_child_id TEXT,
    updated_at     REAL NOT NULL,
    PRIMARY KEY (workspace_id, arrangement_id, drawer_id)
);
```

These are deliberately not foreign keys into `core.sqlite`; cross-database references are validated as a local overlay after core loads.

#### `local.sqlite`: window shell tables

The two workspace-owned tables `local_workspace_window_state` and `local_sidebar_state` are replaced by window-keyed state:

```sql
CREATE TABLE local_window_state (
    window_id         TEXT PRIMARY KEY,
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

There is no `workspace_id` in these tables. The current product writes one UUIDv7 `window_id`; future multi-window work may write additional rows without changing this ownership boundary.

#### `local.sqlite`: workspace-local feature tables

Recent targets and notification history remain workspace-scoped inside the shared file. Their primary keys become workspace-qualified:

```text
local_recent_workspace_target
  PRIMARY KEY (workspace_id, id)

local_notification_inbox_item
  PRIMARY KEY (workspace_id, id)

local_notification_inbox_collapsed_group
  PRIMARY KEY (workspace_id, group_key)
```

All supporting indexes begin with `workspace_id` when queries are workspace-scoped. Existing notification claim, pane, tab, repo, worktree, timestamp, and retention columns remain unchanged unless a key/index must change to support the shared file. Notification behavior is not redesigned.

The live values currently stored in `<workspace-id>.settings.json` move to separate typed, workspace-owned tables. They do not move into a generic key/value table or JSON blob:

```sql
CREATE TABLE local_editor_preferences (
    workspace_id         TEXT PRIMARY KEY,
    bookmarked_editor_id TEXT,
    updated_at           REAL NOT NULL
);

CREATE TABLE local_repo_explorer_preferences (
    workspace_id     TEXT PRIMARY KEY,
    grouping_mode    TEXT NOT NULL
                     CHECK (grouping_mode IN ('repo', 'pane', 'tab')),
    sort_order       TEXT NOT NULL
                     CHECK (sort_order IN ('ascending', 'descending')),
    visibility_mode  TEXT NOT NULL
                     CHECK (visibility_mode IN ('all', 'favoritesOnly')),
    updated_at       REAL NOT NULL
);

CREATE TABLE local_inbox_notification_preferences (
    workspace_id             TEXT PRIMARY KEY,
    grouping                  TEXT NOT NULL
                              CHECK (grouping IN ('byTab', 'byRepo', 'byPane', 'none')),
    sort_order                TEXT NOT NULL
                              CHECK (sort_order IN ('newestFirst', 'oldestFirst')),
    bell_enabled              INTEGER NOT NULL CHECK (bell_enabled IN (0, 1)),
    global_content_mode       TEXT NOT NULL
                              CHECK (global_content_mode IN ('rollUpAlerts', 'activity', 'all')),
    global_row_state_filter   TEXT NOT NULL
                              CHECK (global_row_state_filter IN ('unreadOnly', 'all')),
    pane_content_mode         TEXT NOT NULL
                              CHECK (pane_content_mode IN ('rollUpAlerts', 'activity', 'all')),
    pane_row_state_filter     TEXT NOT NULL
                              CHECK (pane_row_state_filter IN ('unreadOnly', 'all')),
    updated_at                REAL NOT NULL
);
```

These tables preserve the current feature-atom ownership split. The obsolete checkout-color compatibility field is discarded. Runtime-only pane inbox presentation remains unpersisted.

#### `local.sqlite`: global rebuildable cache tables

Repository caches lose `workspace_id` and use global entity identity:

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

CREATE INDEX idx_cache_worktree_repo_id
ON cache_worktree_enrichment(repo_id);

CREATE TABLE cache_pull_request_count (
    worktree_id TEXT PRIMARY KEY,
    repo_id     TEXT,
    count       INTEGER NOT NULL CHECK (count >= 0),
    updated_at  REAL NOT NULL
);
```

`cache_notification_count` is removed; notification unread state remains inbox-owned.

#### `local.sqlite`: removed sidecar-era tables

The shared target schema does not contain:

```text
legacy_workspace_import_status
workspace_sqlite_snapshot_status
local_workspace_sqlite_snapshot_status
local_persistence_lane_marker
cache_notification_count
local_workspace_window_state
local_sidebar_state
local_sidebar_expanded_group
```

The presentation tables are replaced by the window-keyed tables above. No production path reads or writes the old per-workspace sidecar schema after the hard cut. `legacy_workspace_import_status` and both snapshot-status tables have no replacement runtime receipt or completion-token protocol.

### Foreign-key diagrams

Legend:

```text
────►  SQLite foreign key
┄┄┄►  cross-database logical reference validated in code
[N]    many rows
[0..1] optional reference
```

#### `core.sqlite`

```text
                              ┌──────────────────────┐
                              │      workspace       │
                              │ id PK                │
                              └──────────┬───────────┘
                                         │ ON DELETE CASCADE
                     ┌───────────────────┼───────────────────┐
                     ▼                   ▼                   ▼
                  pane [N]          tab_shell [N]      drawer graph [N]
                  workspace_id FK   workspace_id FK    workspace-owned FKs
                     │
                     │ optional global references
                     ├──────────────► repo [0..1]
                     │                ON DELETE SET NULL
                     └──────────────► worktree [0..1]
                                      ON DELETE SET NULL

┌──────────────────────┐       ON DELETE CASCADE       ┌──────────────────────┐
│         repo         │◄──────────────────────────────│      worktree [N]    │
│ id PK                │       worktree.repo_id FK     │ id PK                │
│ stable_key UNIQUE    │                               │ stable_key UNIQUE    │
└──────────┬───────────┘                               └──────────────────────┘
           │
           ├────► repo_tag [N]          ON DELETE CASCADE
           └────► unavailable_repo      ON DELETE CASCADE

watched_path
  id PK
  stable_key UNIQUE
  no workspace foreign key
```

Forbidden edge:

```text
workspace ─X─► repo / worktree / watched_path / repo_tag / unavailable_repo
```

The pane remains owned by its workspace. Its optional repo/worktree facets refer to global entities. When both facets are present, a constraint verifies that `worktree.repo_id == facet_repo_id`.

#### `local.sqlite` and cross-database references

```text
┌─────────────────────────────┐
│ local_window_state          │
│ window_id PK                │
└──────────────┬──────────────┘
               │ ON DELETE CASCADE
               ▼
  local_window_sidebar_expanded_group [N]
  (window_id FK, group_key) PK

local_workspace_cursor                     core.workspace
local_tab_cursor                    ┄┄┄┄┄┄► core composition IDs
local_arrangement_cursor                    validated after core load
local_drawer_cursor
local_arrangement_drawer_cursor

local_recent_workspace_target       ┄┄┄┄┄┄► core.workspace/repo/worktree
local_notification_inbox_item       ┄┄┄┄┄┄► core workspace/pane/tab/topology

cache_repo_enrichment               ┄┄┄┄┄┄► core.repo
cache_worktree_enrichment           ┄┄┄┄┄┄► core.worktree/repo
cache_pull_request_count            ┄┄┄┄┄┄► core.worktree
```

SQLite cannot enforce foreign keys across two separate database files. These dashed references are optional local overlays: stale targets are defaulted, skipped, or rebuilt and never invalidate core.

### Database migration versus backward compatibility

Both databases receive a one-time, crash-safe migration. The migration is required; backward-compatible runtime paths are forbidden.

```text
before successful cutover              after successful cutover
──────────────────────────────          ──────────────────────────────
old core schema is migration input      only target core schema is used
workspace sidecars are import input     only one local.sqlite is used
existing IDs remain unchanged          all live references keep those IDs
                                        no old readers, dual writes, or shims
```

#### Core data that migrates

- Workspaces and their pane/tab/arrangement/drawer compositions remain durable.
- Watched paths, repositories, worktrees, tags, favorite state, notes, and unavailable state move from workspace-owned rows to global rows.
- Existing topology rows and IDs are preserved without reconciliation or metadata merging.
- Pane `facet_repo_id` and `facet_worktree_id` values retain their existing referenced IDs.
- Workspace selection remains intact.
- The old `workspace_sqlite_snapshot_status` table is dropped after its schema role ends; it is not copied into a replacement runtime protocol.

The core migration is transactional. Failure leaves the pre-migration core database unchanged and loadable by the same migration code on retry; it must not leave a partially globalized schema.

#### Local data that migrates

The one-time conversion reads the old `<workspace-id>.local.sqlite` files only during the first hard-cut launch.

Migrated into the one `local.sqlite`:

- workspace cursors for every valid workspace;
- recent workspace targets;
- notification inbox items, read/dismissed state, claims, and collapsed groups;
- the active/current window's frame, sidebar width, sidebar state, filter presentation, and expanded groups, assigned one new UUIDv7 `window_id`;
- other valid workspace-owned feature rows explicitly retained by the target schema.

The one-time cutover also reads the live `<workspace-id>.settings.json` and, when needed, its valid backup solely to populate the typed editor, Repo Explorer, and Inbox preference rows. This preserves current user preferences without retaining JSON as a runtime store. The obsolete checkout-color field is not copied.

Not migrated:

- repository/worktree enrichment caches;
- pull-request counts;
- deprecated notification-count cache rows;
- local completion tokens;
- legacy lane/import markers whose only purpose was the old sidecar or compatibility path;
- inactive workspace window/sidebar rows that cannot truthfully be associated with a real current window.

Rebuildable cache data starts empty and is repopulated by its existing owners. Missing local values use the defaults defined by R6.

#### Cutover rule

The core migration and local conversion have deliberately different failure behavior:

- Core migration failure rolls back the core transaction and leaves the pre-migration database unchanged.
- Core migration success is final and independent of local conversion.
- Successful local conversion preserves the valid retained local/settings rows.
- Failed or interrupted local conversion uses deterministic local defaults. It does not block core startup and is not retried from legacy inputs on a later launch.

After the core hard cut:

- production opens only the target `core.sqlite` and one `local.sqlite`;
- old sidecars are no longer read or written;
- `<workspace-id>.settings.json` and `<workspace-id>.settings.backup.json` are no longer read or written;
- no compatibility adapter, fallback reader, dual writer, alias table, or feature flag remains;

Normal GRDB migration identifiers remain the durable migration ledger. Historical migration bodies are not rewritten. Forward migrations rebuild or drop obsolete objects and leave only the target schema. The hard cut introduces no product-level receipt table, archive state machine, or replay policy.

### Legacy persistence code and artifact hard cut

The resulting production source has exactly one supported standalone JSON preference artifact:

```text
retain
  preferences.global.json

remove as live/import/fallback persistence
  <UUID>.workspace.cache.json
  <UUID>.workspace.ui.json
  <UUID>.workspace.sidebar-cache.json
  <UUID>.notification-inbox.json
  <UUID>.settings.json
  <UUID>.settings.backup.json
  matching *.corrupt-*.json quarantine paths
  surface-checkpoint.json
```

`surface-checkpoint.json` is included because its save/load/clear API has no production callers. Removing that dead persistence seam does not redesign Ghostty or terminal lifecycle behavior.

The following source contracts do not survive under another name:

- `WorkspacePersistor`, `WorkspacePersistor+Payloads`, and `WorkspacePersistor.PersistableState`;
- JSON fallback/import/quarantine branches in `RepoCacheStore`, `UIStateStore`, `SidebarCacheStore`, `InboxNotificationStore`, and `WorkspaceSettingsStore`;
- `allowLegacyFilePersistence`, `allowLegacyFileImport`, `canArchiveLegacy*`, `WorkspaceLocalSQLiteLegacyLane`, and `WorkspaceLocalSQLiteLegacyImportDecision`;
- datastore legacy-decision payloads and operations;
- inbox legacy-import materialization state and APIs;
- legacy preference decoder aliases whose only purpose is old JSON compatibility;
- `PaneMetadata.LegacySource` decoding compatibility when its remaining caller inventory confirms it serves only removed JSON payloads;
- the dead surface-checkpoint path helper and `SurfaceManager` checkpoint methods;
- SQLite conversion routes through legacy `WorkspacePersistor` DTOs. Current SQLite snapshots use current, explicitly named typed inputs.

This deletion list does not include JSON used as transport, Bridge RPC, drag/drop payloads, JSONL telemetry, or typed JSON columns inside SQLite. Those are not standalone legacy persistence authorities.

### Core ownership map

```text
core.sqlite

watched_path
repo
  └── worktree.repo_id ───────────────► repo.id
unavailable_repo.repo_id ─────────────► repo.id

workspace
  ├── pane.workspace_id ──────────────► workspace.id
  ├── tab_shell.workspace_id ─────────► workspace.id
  └── composition graph

pane.facet_repo_id ───────────────────► repo.id
pane.facet_worktree_id ───────────────► worktree.id
```

Forbidden core edges:

```text
repo.workspace_id
worktree.workspace_id
watched_path.workspace_id
workspace deletion ──cascade──► repo/worktree/watched_path
pane-to-repo validation based on equal workspace_id
```

The exact existing pane column names may differ by pane metadata family. The invariant is the same: every optional pane reference targets a global repository/worktree ID, and a topology deletion clears the optional reference rather than deleting the pane or workspace composition.

### Local ownership map

```text
local.sqlite

workspace cursor lane
  key: workspace_id
  values: active tab, arrangement, pane, drawer cursors

window-shell lane
  key: window_id
  values: frame and sidebar presentation memory

workspace-local feature lanes
  key: workspace_id plus feature/entity key
  values: recent targets, notification views/history where currently scoped

global cache lanes
  key: repo_id or worktree_id
  values: rebuildable enrichment and PR counts

global cache metadata
  key: one application singleton
  values: cache revision and rebuild timestamp
```

Forbidden local edges:

```text
local completion token ──validates──► core completion
repo cache ──owned by──► workspace_id
window state ──owned by──► workspace_id
local read failure ──causes──► fatal application startup
```

### Startup flow

```text
core.sqlite
  open + migrate + strictly validate authoritative state
  ├── valid   → install workspace composition and global topology
  └── invalid → core-integrity failure

local.sqlite
  open independently
  ├── available
  │     ├── load each logical lane
  │     ├── validate local references against core
  │     └── use defaults for missing/stale/invalid lanes
  └── unavailable → use defaults for all local lanes

present application
```

No local outcome changes the already-determined core outcome.

### Save flow

```text
authoritative mutation
  → one atomic core.sqlite transaction
  → success or rollback

local presentation/continuation mutation
  → independent local.sqlite transaction for its owning lane
  → success or diagnostic failure
```

There is no distributed transaction between the two databases.

## Spec boundary and separability map

```text
Repository topology owner
  owns: global watched paths, repos, worktrees, topology metadata
  exposes: global repository topology repository/API
                      │
                      │ stable repo/worktree IDs
                      ▼
Workspace composition owner
  owns: workspace, pane, tab, arrangement, drawer graph
  exposes: atomic core composition repository/API
                      │
                      │ immutable IDs for local validation
                      ▼
Local persistence owner
  owns: one local.sqlite and independent local lanes
  exposes: typed loaded/defaulted/unavailable results
                      │
                      │ validated values only
                      ▼
MainActor atoms
  own: live state and pure derived projections
  do not own: persistence, migration, recovery, or database coordination
```

The global-topology schema correction and the local-database consolidation are separable implementation slices, but the shipped contract must remove the cross-database core/local validity dependency. The application must never ship an intermediate state in which the new core schema still relies on an old per-workspace local completion token.

Workspace composition persistence is not a global-topology writer. This forbidden edge prevents an older composition save from reverting or deleting newer repository state.

The current global `RepositoryTopologyAtom` and entity-keyed cache atoms remain the live state owners. This is a persistence hard cut, not an atom redesign.

## Proof expectations

The implementation plan must operationalize proof for these behaviors:

1. Schema ownership: global topology tables have no workspace ownership or workspace-delete cascade; workspace composition tables retain workspace ownership. `PRAGMA foreign_key_check` returns no rows after migration and destructive-path tests.
2. Mandatory workspace-delete data-loss regression:
   - seed global watched path P, repo R, worktree T, tags/metadata/availability, and workspaces A and B whose panes reference the same R and T;
   - delete inactive workspace A and prove only A's composition disappears;
   - delete active/final workspace B and prove selection follows its existing contract while P, R, T, tags/metadata/availability remain unchanged;
   - explicitly delete T or R through the topology authority and prove optional pane facets clear without deleting panes or workspaces.
3. Topology currentness: an older captured composition save cannot overwrite a newer topology mutation.
4. Atomic core: injected failure during core persistence leaves the previous complete core state loadable.
5. Local independence: failure before, during, or after a local write cannot change the core load result.
6. Lane defaults: missing/stale/invalid cursor, window, sidebar, notification, and cache lanes default independently according to their contracts.
7. Whole-local failure: missing, corrupt, or migration-failed `local.sqlite` still permits core hydration and usable application startup.
8. Window ownership: two window IDs can hold different frame/sidebar state without workspace-key collisions.
9. Single local file: production opens one local database rather than selecting a path by workspace ID.
10. Data cutover: core rows and IDs survive unchanged; a real target-schema uniqueness violation rolls back the core migration without changing the original database; successful local conversion preserves valid retained local history; failed or interrupted local conversion uses defaults without later legacy replay; rebuildable caches regenerate cleanly.
11. Preference cutover: every current editor, Repo Explorer, and Inbox preference round-trips through its typed table; missing/invalid values default by feature; obsolete checkout colors do not return.
12. Legacy-source absence: production source contains no workspace settings/cache/UI/sidebar/inbox JSON persistence, `WorkspacePersistor`, legacy import decision, matching completion-token, or surface-checkpoint path. `preferences.global.json` and its validation tests remain.
13. Atom boundary: persistence and migration logic do not enter atoms or pure derived state.

Proof must use permanent schema, repository, datastore, startup-integration, and application smoke coverage. The later implementation plan owns exact commands and sequencing.

Tests that currently assert workspace-qualified topology, core/local completion-token matching, strict failure for missing/corrupt local state, legacy JSON replay/materialization/archive readiness, per-workspace local database pools, or live settings JSON must be removed or inverted to assert this contract. Existing active-workspace selection, pane/tab/drawer integrity, atom ownership, current SQLite round-trip, and database quarantine coverage remains and is adapted rather than discarded.

Current architecture docs must stop describing workspace-owned topology, per-workspace local databases, JSON cache/UI/settings stores, completion-token validity, or legacy archive/import behavior as live architecture. Historical specs and plans remain historical unless separately marked superseded; they are not rewritten into current truth.

## Non-goals

- Implement multiple macOS windows.
- Implement multiple-window creation, coordination, or restoration behavior.
- Change what a workspace composition contains.
- Redesign repository discovery, filesystem watching, Git enrichment, or their performance policy.
- Redesign notification meaning, retention, or presentation.
- Change Bridge, Ghostty, EventBus, IPC, terminal lifecycle, or pane runtime behavior.
- Add terminal checkpointing or replace the dead `surface-checkpoint.json` seam with another checkpoint system.
- Add a generic distributed transaction framework, recovery engine, compatibility layer, or new persistence logic to atoms.
- Preserve rebuildable caches at the cost of complicating the hard cut.

## Alternatives rejected

### Keep one local database per workspace

Rejected because it preserves the obsolete workspace/window equivalence, duplicates migrations/connections, and gives global repository caches no natural owner.

### Keep matching completion tokens across core and local

Rejected because local preferences and caches are non-authoritative. A distributed completion protocol lets local failure invalidate valid core state.

### Move all local state into core.sqlite

Rejected because it would let preferences, caches, and machine-local failures expand the authoritative core failure domain.

### Add local defaults but retain workspace-owned repositories

Rejected because it fixes only the startup symptom while preserving destructive repository ownership and blocking shared repository references.
