# Workspace-Local Feature Preferences In SQLite

Date: 2026-07-17
Status: Draft for review
Scope: Repo Explorer and Inbox workspace-local preference persistence

## Product Intent

Repo Explorer and Inbox preferences describe how one workspace is presented.
They should live with the rest of that workspace's local UX state in
`<workspace-id>.local.sqlite`, not in the mixed
`<workspace-id>.settings.json` file.

The user-visible behavior does not change. Grouping, sorting, visibility, bell,
and Inbox display filters still update immediately through their canonical
`@MainActor` atoms and restore per workspace after relaunch. This change moves
only their persistence projection and makes the I/O path conform to the existing
SQLite actor boundary.

Success means:

- Repo Explorer and Inbox preferences restore from local SQLite for the active
  workspace.
- SQLite and filesystem work do not run on `MainActor`.
- feature atoms remain the only canonical live UI state;
- legacy settings values are imported once without creating dual authority;
- local SQLite loss resets these low-criticality preferences to deterministic
  defaults and never replays stale archived JSON;
- `WorkspaceSettingsStore` remains responsible only for settings that still
  belong in settings JSON, beginning with the bookmarked editor preference.

## Current State

After PR #190, `WorkspaceSettingsStore` is a `@MainActor` object that directly
reads and writes JSON while observing three independent preference owners:

```text
RepoExplorerSidebarPrefsAtom
  groupingMode          repo | pane | tab                  default repo
  sortOrder             ascending | descending            default ascending
  repoVisibilityMode    all | favoritesOnly               default all

InboxNotificationPrefsAtom
  grouping              byTab | byRepo | byPane | none     default byTab
  sort                  newestFirst | oldestFirst          default newestFirst
  bellEnabled           Bool                               default false
  globalContentMode     rollUpAlerts | activity | all      default rollUpAlerts
  globalRowStateFilter  unreadOnly | all                   default unreadOnly
  paneContentMode       rollUpAlerts | activity | all      default rollUpAlerts
  paneRowStateFilter    unreadOnly | all                   default unreadOnly

EditorPreferenceAtom
  bookmarkedEditorId                                       default nil
```

The Repo Explorer and Inbox values are workspace-local UX memory. The editor
bookmark remains settings-bound user intent. The current implementation mixes
these three owners into one JSON payload and performs file I/O from its
MainActor-isolated store.

The existing SQLite boundary is:

```text
@MainActor atom and persistence orchestration
  -> immutable Sendable snapshot
  -> WorkspaceSQLiteDatastore actor
  -> repository issued through that datastore
  -> GRDB
  -> core.sqlite or <workspace-id>.local.sqlite
```

`WorkspaceSQLiteDatastore` already owns database opening, repository caching,
operation serialization, recovery classification, and local DB/WAL/SHM
quarantine. This spec extends that boundary; it does not create another SQLite
owner.

## Requirements

### R1. Exact Persistence Scope

The following values move to `<workspace-id>.local.sqlite`:

- Repo Explorer grouping mode, sort order, and repo visibility mode;
- Inbox grouping, sort order, bell enabled state, global content mode, global
  row-state filter, pane-default content mode, and pane-default row-state
  filter.

The pane Inbox fields are workspace-level defaults for pane Inbox surfaces.
They are not per-pane records. Runtime-only keyed presentation such as
`PaneInboxPresentationAtom.filterModesByParentPaneId` remains unpersisted.

### R2. Canonical Live State Remains In Feature Atoms

`RepoExplorerSidebarPrefsAtom` and `InboxNotificationPrefsAtom` remain the
canonical live state observed by UI and command handlers.

Persistence stores may observe, snapshot, hydrate, reset, and flush those atoms.
Repositories and datastore adapters must not own atoms, expose observable state,
or become UI read models. UI and atoms must not import GRDB or open databases.

### R3. Feature Ownership Is Preserved In SQLite

Repo Explorer and Inbox use separate typed records, repositories, and singleton
workspace rows:

```text
local_repo_explorer_preferences
local_inbox_notification_preferences
```

The tables share one local database and one datastore actor, but they do not
share a generic key/value preference bag, a Codable JSON blob, or one mixed
cross-feature row.

Each feature owns its enum codecs, defaults, row validation, and row-level
recovery policy. Central `WorkspaceLocalMigrations` remains the sole registry of
local migration identifiers and historical DDL.

### R4. All SQLite And Proportional Persistence Work Is Off MainActor

Feature-owned `@MainActor` persistence stores are limited to:

- observing canonical atom fields;
- capturing compact immutable `Sendable` snapshots;
- suppressing saves while hydrating;
- applying loaded values or defaults to atoms;
- scheduling, canceling, and awaiting persistence operations;
- reporting compact recovery outcomes.

Database opening, migration, reads, writes, row decoding, constraint handling,
quarantine, and other proportional work execute behind
`WorkspaceSQLiteDatastore`. A queued write carries its workspace ID, immutable
preference snapshot, and generation or revision. It must not read shared atoms
after leaving the MainActor, and a stale generation must not overwrite a newer
workspace restore or save.

### R5. Schema Uses Typed Columns And Frozen Tokens

The Repo Explorer table represents:

```text
workspace_id          TEXT PRIMARY KEY
grouping_mode         TEXT NOT NULL CHECK repo | pane | tab
sort_order            TEXT NOT NULL CHECK ascending | descending
visibility_mode       TEXT NOT NULL CHECK all | favoritesOnly
initialized_at        REAL NOT NULL
legacy_materialized_at REAL
updated_at            REAL NOT NULL
```

The Inbox table represents:

```text
workspace_id             TEXT PRIMARY KEY
grouping                  TEXT NOT NULL CHECK byTab | byRepo | byPane | none
sort_order                TEXT NOT NULL CHECK newestFirst | oldestFirst
bell_enabled              INTEGER NOT NULL CHECK 0 | 1
global_content_mode       TEXT NOT NULL CHECK rollUpAlerts | activity | all
global_row_state_filter   TEXT NOT NULL CHECK unreadOnly | all
pane_content_mode         TEXT NOT NULL CHECK rollUpAlerts | activity | all
pane_row_state_filter     TEXT NOT NULL CHECK unreadOnly | all
initialized_at            REAL NOT NULL
legacy_materialized_at    REAL
updated_at                REAL NOT NULL
```

Historical migrations freeze accepted token literals locally. They do not call
mutable presentation helpers to determine historical schema vocabulary.

The repository contract distinguishes:

- no record;
- an initialized record containing defaults;
- an initialized record containing non-default values;
- a record materialized from the legacy settings source.

Persisted defaults are real state and must not be confused with absence.

### R6. Settings JSON Becomes Editor-Only

After cutover, the live settings payload contains only the settings-owned schema
and the bookmarked editor preference. It contains no Repo Explorer, Inbox,
checkout-color, tag, note, repo, or worktree fields.

`WorkspaceSettingsStore` stops observing, hydrating, and saving Repo Explorer
and Inbox atoms. It retains workspace-ID and schema validation, primary/backup
handling, corruption reporting, and editor preference persistence.

This is a hard cutover. Migrated values are never dual-written to JSON, and no
permanent compatibility reader merges JSON and SQLite on normal boot.

### R7. Cutover Authority Survives Local SQLite Loss

Local row markers alone are insufficient because quarantining
`<workspace-id>.local.sqlite` also removes those markers. A durable cutover
receipt outside the local database must prevent stale JSON replay.

The receipt lives in `core.sqlite`, is keyed by workspace ID, and records:

- the identity or fingerprint of the legacy settings source;
- that Repo Explorer materialization started and completed;
- that Inbox materialization started and completed;
- that the editor-only settings primary and backup were materialized;
- that the immutable pre-cutover settings artifact was created and verified;
- finalization time and the last migration error, when any.

The receipt stores migration facts only, never preference values. It must use a
dedicated schema contract for this later cutover rather than overloading the
meaning of the older broad `settings_imported_at` or `local_imported_at`
timestamps.

Once the durable receipt says a feature slice completed, legacy values for that
slice are never automatically replayed, even when its local row is subsequently
missing because of quarantine or reset.

### R8. Legacy Import Is One-Time, Resumable, And Crash-Safe

Legacy import is a state machine, not a fallback read path:

```text
validated settings v1 source
  -> verified immutable pre-cutover artifact
  -> durable cutover receipt with source fingerprint
  -> feature row plus local materialization marker
  -> durable per-feature completion receipt
  -> editor-only settings primary and backup
  -> finalized cutover receipt
```

The SQLite commit and JSON rewrite are separate durability boundaries. The
design must not claim cross-file atomicity.

Required authority rules:

```text
durable feature completion receipt exists
  -> local SQLite row is authoritative when present
  -> missing row resolves to deterministic defaults
  -> JSON and archived sources are never replayed

cutover started, feature completion receipt absent
  -> resume only that incomplete feature from the verified source identity
  -> never overwrite a completed sibling feature

no cutover receipt and valid settings v1 exists
  -> begin one-time import

settings is already editor-only
  -> never infer legacy preference values
```

Each feature row and its local materialization marker commit in one local
transaction. Cross-feature atomicity is not required. A completed Repo Explorer
slice must not be replayed because Inbox import failed, and vice versa.

The normal rolling `.settings.backup.json` is not sufficient migration evidence
because ordinary persistence replaces it. Before migrated fields are removed,
the exact pre-cutover payload must be archived immutably and verified. During an
incomplete migration it may be used only to resume the source fingerprint
recorded by the cutover receipt. After finalization it is evidence for explicit
manual rollback or debugging, not an automatic recovery source.

### R9. Recovery Is Contained By Persistence Domain

Only errors classified by `WorkspaceSQLiteRecoveryClassifier` as SQLite
corruption or not-a-database may quarantine a database. Local quarantine moves
the DB, WAL, and SHM together.

Recovery behavior is:

```text
local SQLite corruption after cutover
  -> quarantine local DB/WAL/SHM
  -> recreate local database
  -> hydrate Repo Explorer and Inbox defaults
  -> emit recovery evidence
  -> do not replay settings or archive values

ordinary local open or permission failure
  -> report unavailable
  -> keep current atom values for the session
  -> do not quarantine
  -> do not write migrated values to JSON

one readable feature row contains an invalid token
  -> preserve valid sibling fields
  -> default and canonicalize the invalid field
  -> report row-level recovery
  -> do not quarantine unrelated local Inbox history or cache state

save failure
  -> atoms remain canonical for the running session
  -> report save failure
  -> retry only through the SQLite path
```

Core SQLite failure follows the existing core recovery policy. Because the
cutover receipt is a replay-safety boundary, implementation planning must prove
how core recovery avoids silently re-authorizing an old settings v1 file.

### R10. Restore, Workspace Switching, And Termination Are Ordered

On restore, atom hydration completes before autosave observation can persist the
currently loaded workspace's previous values. A workspace switch invalidates or
awaits pending writes from the prior workspace according to their captured
generation; no task may read workspace B atoms and write them under workspace A.

Termination flushes both feature persistence stores asynchronously and waits for
their bounded completion through the existing app termination contract. Tests
must use state/event completion and injected clocks, never wall-clock sleeps.

### R11. Observability Is Safe And Actionable

Load, save, import, finalization, unavailable, row repair, and quarantine paths
emit the existing persistence recovery and trace vocabulary or a reviewed typed
extension of it.

Telemetry may include safe operation names, outcome classes, schema/migration
identifiers, and deterministic workspace hashes. It must not include raw paths,
workspace UUIDs, editor IDs, repo names, notification content, or serialized
preference payloads.

## Technical Ownership Contract

```text
Repo Explorer UI and commands
  -> RepoExplorerSidebarPrefsAtom                 canonical live state
  -> RepoExplorerPreferencesStore                MainActor observation/hydration
  -> RepoExplorerPreferencesDatastoreAdapter      typed Sendable boundary
  -> WorkspaceSQLiteDatastore actor               routing/serialization/recovery
  -> RepoExplorerPreferencesRepository            row codecs and transactions
  -> local_repo_explorer_preferences              local SQLite values

Inbox UI and commands
  -> InboxNotificationPrefsAtom                   canonical live state
  -> InboxNotificationPreferencesStore            MainActor observation/hydration
  -> InboxNotificationPreferencesDatastoreAdapter typed Sendable boundary
  -> WorkspaceSQLiteDatastore actor               routing/serialization/recovery
  -> InboxNotificationPreferencesRepository       row codecs and transactions
  -> local_inbox_notification_preferences         local SQLite values

Cutover coordinator
  -> validated settings v1 migration source
  -> core SQLite cutover receipt                  replay-prevention authority
  -> feature datastore adapters                   per-feature materialization
  -> WorkspaceSettingsStore                       editor-only final payload

WorkspaceSettingsStore
  -> EditorPreferenceAtom                         canonical editor preference
  -> editor-only settings primary and backup      settings JSON
```

Allowed dependencies:

- feature store -> feature adapter -> named datastore operation;
- datastore -> feature repository factory/cache;
- repository -> migration-frozen storage tokens and GRDB;
- cutover coordinator -> typed feature migration snapshots and typed receipt
  operations.

Forbidden dependencies:

- UI, command handler, atom, or MainActor store -> GRDB or `DatabaseWriter`;
- Core generic local repository -> Repo Explorer or Inbox UI types;
- Repo Explorer repository -> Inbox models, or the reverse;
- feature repository -> atoms or global registry;
- settings JSON and local SQLite both acting as live preference writers;
- a generic untyped preference dictionary or opaque JSON column.

## Spec Boundary / Separability Map

```text
Repo Explorer feature                 Inbox feature
owns enum/default contract            owns enum/default contract
owns atom and persistence store       owns atom and persistence store
owns typed row repository             owns typed row repository
          |                                      |
          +----------- typed operations ----------+
                             |
                             v
                  WorkspaceSQLiteDatastore
                  owns actor serialization,
                  local repository caching,
                  open/recovery/quarantine
                             |
                             v
                  <workspace-id>.local.sqlite

Migration/cutover domain              Settings domain
owns source fingerprint and           owns editor preference JSON,
durable replay-prevention receipt     validation, primary/backup
          |                                      |
          +------ explicit finalization contract--+
```

The feature slices are independently replaceable because neither imports the
other's model or repository. The datastore remains shared because database
opening and local sidecar recovery are workspace-wide concerns. The cutover
receipt is separate because replay prevention must survive loss of the local
database whose values it protects.

## Alternatives And Tradeoffs

### One Shared Wide Preference Row

Gain:

- one load and one save operation;
- less adapter and store plumbing.

Cost:

- Repo Explorer and Inbox acquire shared schema/versioning and replacement
  writes despite having no cross-feature invariant;
- one feature's decode or save failure affects the other;
- ownership remains a mixed settings bag with a different serialization format.

Decision: rejected. Shared workspace lifecycle does not justify shared domain
ownership.

### Generic Key/Value Preference Table

Gain:

- adding a preference may avoid a schema migration.

Cost:

- token and boolean constraints move out of SQLite;
- compile-time record shape and exhaustive migration tests weaken;
- ownership and defaults become string conventions;
- malformed or misspelled keys can silently coexist.

Decision: rejected. These are small, fixed, typed preference sets.

### Keep JSON And Move Its I/O Off MainActor

Gain:

- smallest persistence implementation change;
- avoids SQL migrations.

Cost:

- workspace-local UX state remains split across local SQLite and settings JSON;
- feature ownership remains mixed;
- the requested storage boundary is not achieved.

Decision: rejected.

### Local Markers Only

Gain:

- no core migration receipt.

Cost:

- local quarantine deletes both values and the only fact that JSON was already
  consumed;
- stale settings can become authoritative again.

Decision: rejected. Replay prevention must outlive the local database.

### Separate Feature Tables Behind One Datastore

Gain:

- ownership follows canonical atoms;
- focused schema, recovery, and tests;
- one feature can reset or evolve without rewriting the other;
- existing local database serialization and quarantine remain centralized.

Cost:

- two small stores, adapters, repositories, and operation families;
- observation/debounce mechanics may initially duplicate.

Decision: accepted. A shared observation helper should be introduced only if a
third feature proves identical lifecycle and failure semantics.

## Security And Privacy Context

This is not an authentication or network design. It does parse and move local
files, so the trust boundaries are legacy JSON validation, workspace identity,
SQLite constraints, archive paths, and telemetry scrubbing.

- A migration source must match the target workspace ID and supported schema.
- Source fingerprints bind resumable work to the exact archived payload.
- Archive paths are app-owned and derived from the validated workspace ID, not
  arbitrary payload strings.
- Malformed input cannot select another workspace database or archive target.
- Preference values and raw paths do not leave the process through telemetry.

## Proof Expectations

The implementation plan must map every requirement to authoritative proof. The
spec defines proof modalities, not command order.

### Schema And Repository Proof

- Stable migration identifiers and exact table/column names.
- Enum token and boolean `CHECK` constraints.
- Round-trip every field and every documented default.
- Distinguish absent rows from initialized rows containing defaults.
- Replacement writes preserve unrelated local tables and sibling feature rows.
- Invalid individual tokens produce documented field-level recovery without
  quarantining the whole local database.

### Actor And Lifecycle Proof

- Architecture checks prevent UI, atoms, and MainActor stores from opening GRDB.
- Every datastore request carries a workspace ID and immutable snapshot.
- Deterministic A-to-B workspace switching with an in-flight save proves no
  cross-workspace write.
- Hydration cannot trigger a save of pre-hydration values.
- Debounced writes and termination flushes complete or report bounded failure
  without wall-clock sleeps or leaked tasks.
- MainActor profiling shows no SQLite I/O or entity-proportional persistence work.

### Migration And Crash Proof

- Valid settings v1 import for both feature slices.
- Missing fields resolve to documented defaults; workspace mismatch and
  unsupported schema are rejected.
- One feature succeeds while the other fails, then only the incomplete feature
  resumes.
- Injected interruption at every receipt, row commit, archive, primary rewrite,
  backup rewrite, and finalization boundary.
- A crash after local commit but before JSON reduction never replays completed
  values.
- A local quarantine after completed cutover hydrates defaults and never consumes
  v1 settings or the immutable archive.
- The editor bookmark survives import, finalization, relaunch, and local database
  quarantine.
- Explicit rollback can use the immutable artifact, but ordinary boot cannot.

### Recovery And Integration Proof

- Local DB/WAL/SHM quarantine occurs only for classified corruption.
- Quarantine failure and ordinary open failure remain distinct outcomes.
- Row-level invalid data does not erase notification history, cache rows, or the
  valid sibling preference record.
- Relaunch restores both atoms before UI observation begins.
- Multiple workspaces retain independent values.
- Recovery and persistence traces appear through the existing reporter/trace
  path with scrubbed dimensions.

Manual screenshots and native UI automation are not required for this
persistence-only change. UI smoke becomes necessary only if implementation
changes visible control behavior, not merely the storage owner.

## Non-Goals

- No sidebar visual, interaction, command, grouping, sorting, or animation
  redesign.
- No shared-component changes.
- No Repo Explorer or Inbox projection-performance rewrite.
- No persistence of per-pane runtime Inbox presentation.
- No migration or addition of repo colors, worktree colors, pane colors,
  checkout colors, tags, notes, favorites, or repository/worktree metadata.
- No move of `EditorPreferenceAtom.bookmarkedEditorId` into SQLite in this slice.
- No generic preferences framework.
- No permanent dual-read, dual-write, compatibility shim, or feature flag.
- No exact implementation sequence, worker assignment, or validation command
  list; those belong in the implementation plan after spec approval.

## Open Questions For Review

1. Should the dedicated core cutover receipt be retained indefinitely as durable
   replay-prevention evidence, or may a future reviewed migration compact it
   after all supported v1 settings sources are impossible? This spec recommends
   retaining it until a separate data-lifecycle decision exists.
2. Should malformed row tokens default and canonicalize per field, as specified,
   or reject the entire feature row and reset all of that feature's preferences?
   This spec recommends per-field recovery because the database remains readable
   and sibling values are independently valid.
3. What exact immutable archive naming and retention policy should the plan use?
   The spec requires verified, non-authoritative evidence but does not prescribe
   a filename or retention duration.

## Source Anchors

The design is grounded in the current `main` state containing PR #190:

- `Sources/AgentStudio/Core/State/MainActor/Persistence/WorkspaceSettingsStore.swift`
- `Sources/AgentStudio/Core/State/MainActor/Persistence/WorkspaceLocalMigrations.swift`
- `Sources/AgentStudio/Core/State/MainActor/Persistence/WorkspaceCoreMigrations.swift`
- `Sources/AgentStudio/Core/State/MainActor/Persistence/WorkspaceSQLiteStoreBackendFactory.swift`
- `Sources/AgentStudio/Core/State/SQLite/WorkspaceSQLiteDatastore.swift`
- `Sources/AgentStudio/App/Boot/WorkspaceLegacyArchiveCoordinator.swift`
- `Sources/AgentStudio/Features/RepoExplorer/State/MainActor/Atoms/RepoExplorerSidebarState.swift`
- `Sources/AgentStudio/Features/InboxNotification/State/MainActor/Atoms/InboxNotificationPrefsAtom.swift`
- `Sources/AgentStudio/Features/InboxNotification/State/MainActor/Persistence/InboxNotificationSQLiteDatastoreAdapter.swift`
- `docs/architecture/atom_persistence_boundaries.md`
- `docs/architecture/workspace_data_architecture.md`
- `docs/superpowers/specs/sqlite/02-local-ux-and-cache-schema.md`
- `docs/superpowers/specs/sqlite/04-migration-and-recovery.md`
- `docs/superpowers/specs/sqlite/05-write-paths-and-actors.md`
- `docs/superpowers/specs/sqlite/06-test-checkpoints.md`
