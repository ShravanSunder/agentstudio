# Explicit Application Database Bootstrap

Status: Accepted for implementation
Date: 2026-07-27
Baseline: `6d13f6445524ec81536f75b1ed4ef7917d1c1b85`

## Decision

Agent Studio prepares both SQLite databases explicitly at boot, before any
persistence store hydrates:

```text
App boot
  → construct WorkspaceSQLiteDatastore
  → prepare core.sqlite and local.sqlite
  → hydrate canonical core composition
  → hydrate independent local slices
  → arm persistence observation
```

`core.sqlite` remains authoritative and strict. If it cannot be prepared, boot
stops.

`local.sqlite` remains non-authoritative. If it is corrupt, or a sidecar exists
without the main database, Agent Studio moves the old SQLite file set to
timestamped quarantine names, creates a fresh `local.sqlite`, and hydrates
local defaults. If local preparation still cannot succeed, core boot continues
and all local values use deterministic defaults.

In this spec, local recovery means exactly:

```text
quarantine the present local.sqlite / WAL / SHM file set
  → create and migrate a new local.sqlite
```

There is no recovery subsystem beyond that backup-and-recreate branch.

## Current Problem

The app constructs `WorkspaceSQLiteDatastore` at boot, but database opening is
demand-driven.

Canonical composition currently attempts the first local open:

```text
WorkspaceStore.loadCanonicalComposition
  → WorkspaceSQLiteDatastore.loadAuthoritativeCoreSnapshot
  → WorkspaceSQLiteStoreBackend.loadCompletedSnapshot
  → localRepositoryForRestore(active workspace)
```

That local repository open and the cursor/window reads are hidden behind
`try?`. Later stores can then retry the open while restoring cache, settings,
recency, UI, or inbox state.

The consequences are:

- successful canonical hydration does not prove that `local.sqlite` opened;
- store order determines which consumer retries or observes recovery;
- a physical application database event can be attributed to one workspace;
- application-global recency depends on a workspace-shaped repository bundle.

The correction is to make preparation boot-owned and make every later database
operation consume the retained result.

## Required Contract

### R1. Preparation is a boot prerequisite

`WorkspaceBootSequence` exposes database preparation as the first presentation
prerequisite.

Boot constructs the datastore and prepares both databases before canonical
composition or any local store restore.

A persistence operation invoked before preparation returns a typed programmer
error. It must not lazily open a database.

### R2. The datastore owns physical database lifecycle

`WorkspaceSQLiteDatastore` is the sole product owner of:

- database opening and migration;
- strict core startup acceptance;
- local corruption classification and quarantine;
- one retained writable owner for each available database;
- the immutable preparation result;
- application-scoped preparation diagnostics.

`WorkspaceSQLiteDatastoreFactory` remains construction-only.

Store wrappers and row repositories continue to own typed row reads and writes.
They do not open, migrate, quarantine, recreate, or retry a physical database.

The current `localRepositoryForSave` and `localRepositoryForRestore` physical
openers collapse to one prepared-local accessor. It returns the prepared local
capability or the retained unavailable failure. Restore and save remain
operation labels for diagnostics; they are not different physical open modes.

### R3. Core preparation is strict

Core preparation returns:

```text
ready(coreSnapshot)
ready(uninitialized)
failed(failure)
```

`ready(coreSnapshot)` contains a strictly accepted core-only canonical
snapshot.

`ready(uninitialized)` applies only to a new empty core database created during
the current startup. The existing default-workspace initialization contract
then applies.

A rejected preexisting core database is `failed`, including a database with no
workspace rows or no active workspace selection.

Required supported-schema migration runs before strict snapshot acceptance.
After schema preparation:

- current-schema rejected input remains byte-identical across database, WAL,
  and SHM;
- older supported input may contain the required migration writes, but
  rejection performs no further mutation and creates no quarantine artifact.

A transient writable migration pool may open before acceptance. The one
retained writable core owner opens only after strict acceptance.

Core corruption is never quarantined, reset, defaulted, or recovered from JSON.

### R4. Local preparation has two outcomes

Local preparation returns:

```text
available(recovery?)
unavailable(failure)
```

Successful replacement is ordinary `available` behavior with recovery
provenance. It is not a third state.

The preparation algorithm is:

```text
local file set absent
  → create and migrate local.sqlite
  → available

local file set opens and migrates
  → available

main database absent, with WAL or SHM present
  → before any SQLite open, treat as an incomplete local file set
  → move every present sidecar to timestamped quarantine
  → create and migrate fresh local.sqlite
  → available(recovery)

main database present
  → attempt open and migration
  → never classify by missing WAL or SHM

open reports SQLITE_CORRUPT or SQLITE_NOTADB
  → move every present component to timestamped quarantine
  → create and migrate fresh local.sqlite
  → available(recovery)

recovery fails at either step:
  1. quarantining the present file set, or
  2. creating and migrating the fresh local.sqlite
  → unavailable

permission, disk, unsupported schema, or other unclassified failure
  → preserve the existing live file set
  → unavailable
```

Missing WAL or SHM beside a present main database is normal and never triggers
replacement by file-set shape. Fresh creation must not begin until every
preexisting component has moved out of the live database, WAL, and SHM paths.
This prevents SQLite from creating a new main database beside old sidecars.

An unavailable result is retained for the launch. All local loads and saves
fail fast from it, and no ordinary consumer retries the open. The next app
launch runs the same preparation algorithm against the file set that exists
then.

There is no rollback coordinator, repair queue, health registry, or
same-process retry.

### R5. Local failure defaults by logical slice

Physical local unavailability defaults every local slice while strict core
hydration and workspace presentation continue.

When the physical local database is available, a query or decode failure
defaults only its owning logical slice. Healthy slices continue using the same
prepared database.

A logical slice is one independently meaningful consumer value or one coherent
group of rows:

```text
logical slice                    fallback
───────────────────────────────  ─────────────────────────────
cursor continuation              default navigation cursors
window continuation              default window memory
sidebar shell memory             default sidebar shell
sidebar expanded groups          empty expanded groups
application entity recency       empty application recency
workspace entity recency         empty workspace recency
editor preference                default editor preference
repo-explorer preferences        default repo preferences
inbox-notification preferences   default inbox preferences
repository cache                 empty/rebuildable cache
notification inbox               feature-owned empty/default
```

The five cursor tables remain one coherent cursor-continuation slice.
Repository enrichment, worktree enrichment, pull-request counts, and cache
metadata remain one coherent repository-cache slice.

Editor, repo-explorer, and inbox-notification preferences are independent
slices even though `WorkspaceSettingsStore` currently restores them together.
The datastore load result must represent those three outcomes independently.

Window continuation and sidebar shell memory remain independent reads even
though both use `local_window_state`.

A defaulted slice does not immediately write a replacement row. The next real
settings mutation retains the existing behavior: it writes the three current
in-memory preference values sequentially. This can repair a previously
unreadable preference with its deterministic default. This spec does not add
per-slice dirty tracking or a settings transaction.

A later operation-level filesystem or write failure does not mutate the boot
receipt or reopen the database. The receipt describes preparation, not live
database health.

### R6. One local writer serves two row scopes

```text
prepared local writer
  ├─ application-global rows
  │    repository cache
  │    repository/worktree recency
  │    other rows without workspace_id
  │
  └─ workspace-scoped views(workspaceId)
       cursor and window continuation
       pane recency
       workspace preferences and inbox rows
```

Application-global operations do not accept or ignore a workspace ID.
Workspace-scoped views bind a workspace ID over the same prepared writer.

The first implementation extends the existing private application-local bundle.
It does not add a public `ApplicationLocalRepository` hierarchy.

### R7. Preparation is idempotent and observable once

The datastore stores only:

```swift
private enum DatabasePreparationState {
    case unprepared
    case prepared(DatabasePreparationReceipt)
    case failed(CoreDatabasePreparationFailure)
}
```

Opening, migration, quarantine, and fresh local creation are one synchronous
actor-isolated preparation operation. The terminal state is cached before any
asynchronous diagnostic emission.

Repeated preparation calls return the cached result. They do not create more
pools, rerun migration, repeat quarantine, or emit duplicate startup
diagnostics.

Bootstrap emits one application-scoped structured diagnostic for every
preparation error:

```text
core preparation failure
  → error
  → boot stops

local storage replaced
  → warning
  → quarantined file set retained
  → fresh local database available with defaults

local open fails without permission to replace,
or quarantine/fresh database creation fails
  → error
  → local unavailable
  → every local slice uses its deterministic default
  → core boot continues
```

Diagnostics identify the database, preparation phase, classified failure,
SQLite result code when available, recovery attempt, and final disposition.
They contain no raw database paths or entity identifiers.

Existing logging and trace infrastructure owns these records. Individual stores
do not repeat the startup error or own physical recovery attribution.

Physical open, quarantine, and replacement outcomes move entirely to the
preparation receipt and startup diagnostic. The legacy pending physical
recovery queues and `recoveryEvents` load payloads are removed rather than left
as a second delivery path. Store-owned logical outcomes such as reset-to-default
and save-failed remain ordinary `PersistenceRecoveryEvent` values.

The configuration-driven datastore initializer starts `unprepared`. Test
fixtures that bypass file-backed configuration must inject genuinely prepared
core and local capabilities and start `prepared`; they must not mark the
existing lazy per-workspace repository closures as prepared. The closure-based
test initializer is reshaped or removed rather than exempted from R1.

## Boundary / Separability Map

```text
App boot
  owns: prerequisite order and fatal-versus-degraded policy
  exposes: prepare-databases prerequisite
                            │
                            ▼
WorkspaceSQLiteDatastore
  owns: preparation, migration, replacement, retained writers
  exposes: preparation receipt and typed row operations
                │                           │
                ▼                           ▼
prepared core capability           prepared local capability
  authoritative                      non-authoritative
  strict startup                     application-global rows
  canonical snapshot                 workspace-scoped views
                │                           │
                └───────────┬───────────────┘
                            ▼
persistence stores
  own: row mapping, atom hydration, logical-slice defaulting
  forbidden: physical open, migrate, quarantine, retry, raw pools
```

## State Model

```text
unprepared
    │ prepareDatabasesForBoot()
    ▼
prepare core
    ├─ failed ───────────────────────────────► failed(coreFailure)
    │                                           boot stops
    ▼
prepare local
    ├─ open/create succeeds ────────────────┐
    ├─ corrupt/incomplete file set          │
    │    → recovery                          │
    │       1. quarantine present DB/WAL/SHM │
    │       2. create + migrate fresh local  │
    │       ├─ both succeed ────────────────┤
    │       └─ either fails                  │
    │            → unavailable              │
    │            → local defaults           │
    │            → core continues ──────────┤
    └─ unclassified open failure            │
         → preserve file set                │
         → unavailable ─────────────────────┤
                                            ▼
                                   prepared(receipt)
                                     core: ready
                                     local:
                                       available
                                       unavailable
```

Every `unavailable` local branch continues boot with accepted core state and
deterministic defaults for every local slice. Backup-and-recreate is an
internal preparation branch, not a stored state.
Logical-slice loaded/defaulted behavior is ordinary hydration, not another
state machine.

## Invariants

1. No persistence store is an incidental physical-database opener.
2. Exactly one retained writable owner exists for each available database.
3. Core failure stops boot; local failure never invalidates accepted core state.
4. After required supported-schema migration, strict rejection performs no
   additional core mutation; current-schema rejected input remains
   byte-identical.
5. Every local consumer observes the same preparation disposition.
6. Successful local replacement produces an available empty database and
   deterministic local defaults.
7. A fresh local database is never created beside a preexisting live sidecar.
8. Unclassified local failures do not authorize replacement.
9. A logical-slice failure does not poison unrelated local slices.
10. Application-global local operations require no workspace ID.
11. Later load, save, flush, and shutdown paths cannot reopen unavailable local
    storage.
12. Preparation errors are logged once at application scope.
13. Physical preparation outcomes never re-enter store-owned recovery-event
    payloads.

## Proof Expectations

The implementation plan must provide:

- boot-order proof that preparation precedes every persistence hydration;
- typed pre-preparation failure proof;
- strict core file-backed proof that current-schema rejected input preserves
  DB/WAL/SHM bytes and older supported input receives only required migration
  writes before rejection;
- local file-backed proof for clean creation, normal open, corrupt replacement,
  incomplete-file-set replacement, quarantine failure, fresh-creation failure,
  and unclassified failure;
- proof that a present main database with no WAL/SHM opens normally and is not
  classified as incomplete;
- proof that an unclassified local failure leaves DB/WAL/SHM byte-identical and
  creates no quarantine artifact;
- proof that replacement occurs once and the fresh database hydrates defaults;
- proof that unavailable local storage does not block core/default-workspace
  presentation and is never reopened during that launch;
- one-writer proof across application-global and multiple workspace scopes;
- proof that application recency restores without a preceding RepoCache
  restore;
- independent logical-slice failure proof, including the three settings
  preferences and the coherent cursor/repository-cache groups;
- proof that hydration itself does not repair a defaulted preference and the
  next real settings mutation retains the current sequential save behavior;
- diagnostic proof for fatal core, recovered local, and unavailable local
  outcomes with no duplicate store-owned startup records or physical recovery
  events in store load payloads;
- proof that production configuration begins unprepared while injected test
  fixtures supply genuinely prepared capabilities without lazy openers;
- boundary proof that stores cannot open, migrate, quarantine, retry, or access
  raw pools.

## Explicit Non-Goals

- no new schema or migration solely for bootstrap;
- no second local database or per-workspace database files;
- no public repository hierarchy redesign;
- no prepared-datastore typestate wrapper;
- no generalized health, retry, shutdown, or recovery framework;
- no same-process recovery UI;
- no rollback coordinator for quarantine;
- no per-slice health or dirty-state registry;
- no settings transaction redesign;
- no recency UX, File/Review pane, multi-window, or commit-protocol changes.

## Documentation Reconciliation

Implementation must update:

- `AGENTS.md` component ownership and boot contract;
- `docs/architecture/state/workspace_data_architecture.md` preparation order and
  core/local failure semantics;
- `docs/architecture/structure/component_architecture.md` datastore, factory, store, and
  repository boundaries;
- stale boot comments that imply RepoCache is the local bundle opener;
- stale global-versus-workspace local-row descriptions.

Historical specs remain historical evidence and are not silently rewritten as
current architecture.

## Architecture Approval Required

Implementation must not begin until the user approves:

- explicit preparation before hydration;
- strict core and backup-and-recreate local semantics;
- one retained writable owner per available database;
- application-scoped startup diagnostics;
- no implicit same-process retry.
