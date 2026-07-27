# Explicit Application Database Bootstrap

Status: Draft for architecture approval
Date: 2026-07-27
Baseline: `00d5de078b94118b0ad00e862135068670278552`

## Decision Summary

Agent Studio boot explicitly prepares both application databases before any
persistence store hydrates:

```text
App boot
  → construct WorkspaceSQLiteDatastore
  → prepare core.sqlite and local.sqlite
  → retain one writable owner for each database
  → hydrate canonical core composition
  → hydrate independent local lanes
  → arm persistence observation
```

`WorkspaceSQLiteDatastore` remains the sole product owner of database opening,
migration, corruption classification, quarantine, and retained database
handles. Stores continue to depend on datastore row operations; they never
receive a pool or repository that can open a database.

Preparation has asymmetric outcomes:

```text
core.sqlite                         local.sqlite
────────────────────────────        ───────────────────────────────
ready(coreSnapshot)                 available
ready(uninitialized)                recoveredAndAvailable
failed                              unavailable

failed → startup stops              unavailable → core boot continues
```

The local outcome is process-wide and sticky for that launch. No cache,
settings, recency, UI, inbox, canonical-load, or shutdown path may implicitly
retry a failed local open.

This is a focused lifecycle correction. It does not introduce a second local
database, a public repository hierarchy, a typestate datastore wrapper, a
general database-health state machine, or a new retry system.

## Problem

The app creates a configured datastore at boot, but database preparation is
demand-driven. Canonical composition is currently the first caller to attempt
`local.sqlite`:

```text
WorkspaceStore.loadCanonicalComposition
  → WorkspaceSQLiteDatastore.loadAuthoritativeCoreSnapshot
  → WorkspaceSQLiteStoreBackend.loadCompletedSnapshot
  → localRepositoryForRestore(active workspace)
```

The local repository open and cursor/window reads are wrapped in `try?`.
Consequently:

- successful canonical hydration does not prove that `local.sqlite` opened;
- a later store can become an incidental retrying opener;
- boot order determines which lane observes recovery or unavailability;
- an application-root database event may be attributed to the active workspace;
- application-global recency depends on a workspace-shaped repository bundle.

The defect is not that the app lacks local persistence. It is that preparation,
availability, and recovery ownership are implicit.

## Product and Engineering Intent

Startup should have one inspectable answer to each question:

- Is authoritative core storage ready?
- Is non-authoritative local storage available, recovered, or unavailable?
- Which component owns the database connections?
- Can a later feature silently change that answer?

Success means boot behavior is independent of store-hydration order, strict
core startup remains intact, local failure cannot block canonical presentation,
and all consumers share the same prepared database state.

## Terminology

### Preparation

The boot-owned operation that performs the database-level work required before
row consumers run: schema preparation, opening, migration when required,
recovery classification, permitted quarantine/reset, and retained-handle
creation.

### Retained writable owner

The one process-lifetime writable database owner cached by the datastore for a
physical database. Bounded transient startup probes are permitted inside
preparation.

This distinction preserves the existing strict core contract: a preexisting
core database may be inspected through a temporary byte-preserving startup
reader before the retained writable pool opens. “One owner” does not mean one
SQLite handle total over the entire preparation algorithm.

### Database-level preparation failure

Failure to prepare and retain initial access to the physical database during
bootstrap. For `local.sqlite`, this makes every local lane unavailable for that
launch.

### Lane-level failure

A query, row, codec, or table-specific failure after the physical database was
prepared. It defaults or fails only that logical lane; it does not poison the
whole local database.

## Requirements

### R1. Explicit boot prerequisite

`WorkspaceBootSequence` exposes database preparation as the first presentation
prerequisite. It runs before canonical composition loading and before any local
store restore.

Boot constructs the datastore, prepares both databases, records the preparation
receipt, then constructs or activates persistence stores against that prepared
datastore.

Calling a persistence operation before preparation is a programmer error
represented by a typed datastore failure in testable APIs. It must not lazily
open a database.

### R2. Datastore ownership

`WorkspaceSQLiteDatastore` owns:

- preparation state;
- core and local opening;
- schema migration;
- corruption classification;
- local sidecar quarantine/reset;
- retained writable owners;
- preparation observability and recovery provenance.

`WorkspaceSQLiteDatastoreFactory` remains construction-only.

Store wrappers and row repositories own typed row reads/writes only. They do not
open, migrate, quarantine, retry, or close a physical database.

The existing `localRepositoryForSave` and `localRepositoryForRestore` paths must
become prepared-access resolvers: return the prepared writer or the retained
unavailable failure. They must no longer open, migrate, quarantine, or retry.

### R3. Core preparation

Core preparation returns one of:

- `ready(coreSnapshot)`: a strictly accepted, core-only preexisting canonical
  snapshot;
- `ready(uninitialized)`: a new empty core database eligible for the existing
  default-workspace initialization contract;
- `failed(failure)`: startup-critical failure.

Strict startup remains byte-preserving for rejected preexisting core input,
including database, WAL, and SHM state. The retained writable core owner opens
only after the byte-preserving acceptance point.

No core corruption quarantine, reset, JSON fallback, or fail-open behavior is
introduced.

Preparation does not build the completed core-plus-local workspace projection.
Canonical composition remains the owner of merging the prepared core snapshot
with cursor/window state from the prepared local capability.

### R4. Application-local preparation

Local preparation returns one of:

- `available`;
- `recoveredAndAvailable(recoveryProvenance)`;
- `unavailable(failure, recoveryProvenance?)`.

A missing local database is created and becomes `available`.

Recognized corruption may be quarantined once and reopened once. Successful
reset becomes `recoveredAndAvailable`. Quarantine failure, reopen failure, or an
unclassified open failure becomes `unavailable`.

An unavailable result is retained for the launch. Every local load and save
fails fast from that result. No ordinary consumer retries opening the database.
Retry occurs on the next app launch; an in-process retry is a separate future
product and lifecycle contract.

### R5. Fail-open local behavior

`local.sqlite` is non-authoritative. Its unavailability must not prevent:

- strict core snapshot acceptance;
- creation of the default core workspace;
- canonical workspace hydration;
- workspace shell presentation.

Canonical cursor and window projections use deterministic defaults when local
storage is unavailable. This defaulting must be driven by the typed preparation
outcome, not by `try?`. The existing canonical-composition assembly boundary
continues to own this merge.

After successful local preparation, lane-specific read failures retain their
existing isolated blast radius.

Post-preparation filesystem loss or write failure is an operation-level lane
failure for this focused correction. It does not mutate the preparation
disposition and does not trigger reopening. The receipt describes the bootstrap
outcome; it is not a live database-health monitor.

### R6. One local owner, two row scopes

One retained local writer serves both scopes:

```text
prepared local writer
  ├─ application-global operations
  │    repository cache
  │    repository/worktree recency
  │    other rows with no workspace_id
  │
  └─ workspace-scoped views(workspaceId)
       cursor/window continuation
       pane recency
       workspace preferences and inbox rows
```

Application-global operations do not accept, invent, or ignore a workspace ID.
Workspace-scoped views bind a workspace ID over the same prepared writer; they
do not own or open the database.

The first implementation should extend the existing private
application-local bundle rather than introduce a new public
`ApplicationLocalRepository` type. A public split requires a separate
architecture decision.

### R7. Recovery attribution and observability

Physical `local.sqlite` preparation and recovery are application-scoped events.
They are recorded once by bootstrap with no synthetic workspace owner.

The immutable preparation receipt is the source of truth for the bootstrap
disposition. Recovery notification delivery must not consume or transfer that
truth to the first feature store that restores.

Operation-level lane failures remain separately attributed to their lane.
Telemetry follows the existing source-scrubbing rules and does not add raw paths
or entity identifiers.

### R8. Idempotence and concurrency

Preparation is idempotent. Repeated or reentrant calls await or return the same
preparation result. Actor reentrancy must not create duplicate pools, migrations,
quarantines, or recovery events.

Once local preparation is unavailable, later load, save, flush, and termination
paths cannot reopen it.

## Boundary / Separability Map

```text
App boot
  owns: visible ordering, fatal-versus-degraded policy
  exposes: one explicit prepare-databases prerequisite
                            │
                            ▼
WorkspaceSQLiteDatastore
  owns: preparation state, migration, recovery, retained owners
  exposes: typed preparation receipt + row operations
                │                           │
                ▼                           ▼
prepared core capability           prepared local capability
  authoritative                      non-authoritative
  strict startup                     application-global operations
  canonical snapshot                 workspace-scoped views
                │                           │
                └───────────┬───────────────┘
                            ▼
persistence stores
  own: atom hydration, row mapping, lane-specific defaulting
  forbidden: open, migrate, quarantine, retry, raw-pool access
```

The explicit seam is the datastore preparation receipt. Core and local outcomes
remain independent within it.

## State Model

```text
unprepared
    │ prepareDatabasesForBoot
    ▼
preparing
    ├─ core failed ─────────────────────► failed [startup terminal]
    │
    ├─ core ready + local available ───► prepared(local: available)
    │
    ├─ core ready + local recovered ───► prepared(local: recovered)
    │
    └─ core ready + local failed ──────► prepared(local: unavailable)

prepared
    ├─ canonical hydration consumes prepared core result
    ├─ local lanes consume one retained local disposition
    └─ ordinary operations cannot transition availability
```

This spec does not create a generalized shutdown state machine. Existing
termination paths must respect the prepared result and must not become a hidden
opening or retry path.

## Invariants

1. No persistence store is an incidental physical-database opener.
2. Exactly one retained writable owner exists for each available database.
3. Transient core startup probes are datastore-owned and close before ordinary
   store hydration.
4. Rejected preexisting core input remains byte-preserved.
5. Core failure blocks hydration; local failure never blocks canonical core
   presentation.
6. All local consumers observe the same preparation disposition.
7. A database-level local failure is sticky until process restart.
8. A lane-level local failure does not poison unrelated lanes.
9. Application-global local operations require no workspace ID.
10. Workspace-scoped views share the prepared local writer.
11. One physical local recovery produces one application-scoped provenance
    record.
12. No later load, save, flush, or shutdown operation opens an unavailable
    database.

## Proof Expectations

The implementation plan must operationalize these proof obligations:

- boot ordering proves preparation precedes canonical and local hydration;
- preparation-state tests prove idempotence and reentrant single ownership;
- file-backed integration proves one retained local writer serves application
  and multiple workspace scopes;
- application recency restores without a preceding RepoCache restore;
- missing local storage is created during preparation;
- corrupt local storage is quarantined/reset once and reported once;
- unrecoverable local storage remains unavailable without retries while core
  presentation succeeds;
- default-workspace core creation succeeds when local storage is unavailable;
- lane-specific malformed local data defaults only that lane;
- strict core tests preserve database/WAL/SHM bytes on rejected startup input;
- store-boundary tests prove consumers cannot invoke opening, migration,
  quarantine, or raw pool construction;

## Alternatives Considered

### Keep demand-driven opening and rely on boot order

Gain: no lifecycle change.

Cost: preserves incidental openers, swallowed local failure, order-dependent
retry, and false recovery ownership.

Decision: rejected.

### Prepare inside the first store restore

Gain: smaller visible boot diff.

Cost: preparation remains store-owned in practice and is not independently
observable or enforceable.

Decision: rejected.

### Return a distinct `PreparedWorkspaceSQLiteDatastore` type

Gain: compile-time exclusion of unprepared use.

Cost: broad signature and fixture churn across every store for a single boot
entry point.

Decision: rejected for this focused correction. Revisit if another production
boot entry point appears or pre-preparation misuse occurs.

### Split a public application-local repository from workspace repositories

Gain: the type system fully expresses row ownership.

Cost: broad repository and test-fixture churn even though one private bundle
already owns the shared writer.

Decision: rejected for now. Application-global operations move onto the private
application bundle; workspace repositories remain scoped views.

### Open one SQLite handle total per database

Gain: literal single-handle lifecycle.

Cost: conflicts with the existing byte-preserving strict-core startup reader
and migration probes.

Decision: rejected. The invariant is one retained writable owner, not one
temporary handle over the entire bootstrap algorithm.

## Security and Data-Integrity Context

This design touches filesystem-backed durable state and destructive recovery.
Core data remains authoritative and is never automatically reset. Local
quarantine remains limited to recognized SQLite corruption/not-a-database
classification and includes the database, WAL, and SHM sidecars.

No new secret, network, subprocess, authentication, or untrusted parsing surface
is introduced. Existing path and telemetry redaction rules remain unchanged.

## Non-Goals

- No schema changes or migrations solely for bootstrap.
- No second local database or per-workspace database files.
- No repo/worktree/pane recency UX changes.
- No File/Review pane behavior changes.
- No generalized persistence service locator.
- No public repository hierarchy redesign.
- No generic database-health or retry framework.
- No same-process recovery UI.
- No multi-window persistence redesign.
- No commit-protocol redesign.
- No broad shutdown lifecycle redesign.

## Documentation Reconciliation

Implementation must reconcile:

- `AGENTS.md`: component ownership and boot contract;
- `docs/architecture/workspace_data_architecture.md`: preparation order,
  core/local failure semantics, and recovery ownership;
- `docs/architecture/component_architecture.md`: datastore, factory, store, and
  repository boundaries;
- boot comments that currently imply RepoCache is the local bundle opener;
- component tables that describe application-global versus workspace-scoped
  local rows.

Historical specs remain historical evidence. They should be classified rather
than silently rewritten as current architecture.

## Architecture Approval Required

Implementation changes the boot lifecycle and datastore preparation boundary.
It must not begin until the user approves this spec, including:

- explicit preparation before hydration;
- one retained writable owner per database with bounded bootstrap probes;
- fatal core versus sticky fail-open local semantics;
- application-scoped local recovery attribution;
- no implicit same-process retry.
