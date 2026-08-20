# Explicit Application Database Bootstrap — Implementation Plan

Status: Accepted for implementation
Date: 2026-07-27
Goal id: `2026-07-27-database-bootstrap-resilience`
Baseline HEAD: `6d13f6445524ec81536f75b1ed4ef7917d1c1b85`

## Source Coverage

Primary source:

- `docs/specs/2026-07-27-explicit-database-bootstrap/2026-07-27-explicit-database-bootstrap.md`
- read in full: 478 / 478 lines
- SHA-256:
  `9e17f30a0c900f0dadf6e25777c90e5d5d4d7feca285d7b726416a1f4ce1ea60`

Goal and review sources were also read in full:

- `tmp/workflow-state/2026-07-27-database-bootstrap-resilience/details.md`
- `tmp/workflow-state/2026-07-27-database-bootstrap-resilience/events.jsonl`
- `tmp/spec-workflows/2026-07-27-explicit-database-bootstrap/swarm-ledger.md`
- the two required simplified-state Opus review packets.

Live source was rechecked at the baseline HEAD. It confirms:

- boot begins with canonical hydration, not database preparation;
- datastore consumer methods still open and recover databases lazily;
- canonical local cursor/window failures are hidden with `try?`;
- physical recovery is still queued through store load payloads;
- application recency depends on a preceding workspace-shaped local open;
- settings restore still couples all three preferences;
- `WorkspaceSQLiteDatastore.swift` is exactly 1,000 lines.

## Outcome

Boot prepares `core.sqlite` and `local.sqlite` before any persistence
hydration. Core remains strict. Local recovery remains exactly:

```text
quarantine present local.sqlite / WAL / SHM
  → create and migrate fresh local.sqlite
```

Both steps succeeding yields available local storage with recovery metadata.
Either step failing yields sticky local unavailability for the launch,
deterministic defaults for every local slice, and continued presentation from
accepted core state.

## Hard Scope Boundary

The implementation may add only the concrete preparation receipt/outcomes,
private three-case datastore state, one boot preparation API, prepared access,
and the minimum test seam needed for deterministic failure proof.

It must not add:

- a public repository hierarchy or prepared-datastore wrapper;
- a fourth stored state such as preparing, recovering, or degraded;
- a generalized filesystem, lifecycle, health, retry, recovery, or shutdown
  framework;
- rollback, repair queue, same-process reopen, or cross-process locking;
- per-slice health/dirty state or a settings transaction;
- another database, writer, or compatibility lifecycle path.

If current source makes any excluded item necessary, stop implementation and
return to the user before writing further code.

## Requirements / Proof Matrix

| Requirement | Owning checkpoint | Proof and layer | Evidence source | Freshness guard | Red / green |
| --- | --- | --- | --- | --- | --- |
| Preparation is the first boot prerequisite | 1 | boot sequence unit test | parent-run focused test | current test binary and source | required |
| Pre-preparation access is typed and performs no open | 1 | datastore unit/open-count test | preparation suite | new datastore per test | required |
| Strict core acceptance runs once while default-workspace readback remains a real post-write read | 1 | acceptance-count and readback integration | preparation and boot suites | fresh core root per test | required |
| One retained writable core owner exists after strict acceptance | 1 | core open-count and write-through integration | preparation and strict-read suites | fresh core root and open counters | required |
| Strict core migration and acceptance remain intact | 1 | file-backed integration and subprocess | strict-read and startup subprocess suites | fresh roots and byte inventories | required |
| Clean missing/valid local storage prepares once | 1 | file-backed integration | preparation and migration suites | fresh roots and open counts | required |
| Recovery is quarantine then fresh create/migrate | 1 | file-backed transition matrix | preparation suite | exact initial/final DB/WAL/SHM inventory | required |
| Either recovery-step failure becomes unavailable | 1 | deterministic failure integration | preparation suite | fresh root and attempt counts | required |
| Unclassified failure preserves bytes and does not quarantine | 1 | file-backed byte/inventory proof | preparation and classifier suites | sentinel bytes and closed handles | required |
| One retained local writer serves global and workspace rows | 2 | actor/open-count integration | datastore actor and recency suites | one datastore and two workspace IDs | required |
| No consumer can open/retry or receive physical recovery payloads | 2 | boundary/source tests | boundary and store suites | current diff readback | required |
| Physical unavailable defaults all local state without blocking core | 2 | canonical/store integration | strict-read and store suites | one retained unavailable receipt | required |
| Available local defaults only the failed logical slice | 2 | malformed-row integration | local repository and store suites | fixtures created in current run | required |
| Settings load independently and repair only on next real save | 2 | file-backed store integration | settings suite | write-count/order recorder | required |
| Preparation diagnostics are once-only and source-scrubbed | 3 | recorder and OTLP unit/integration | trace suites | current trace output and explicit drain | required |
| Docs match implemented ownership and boot flow | 3 | stale-symbol/path search and diff review | parent source inspection | post-implementation symbols | not applicable |
| Real debug app boots through preparation | terminal | marker-scoped smoke | standard debug observability verifier | new marker and debug app identity | not applicable |
| Repository and PR are ready | terminal | lint/test/build, implementation review, CI/PR state | parent and exact Opus reviewer | pushed HEAD equals PR head OID | not applicable |

Every behavior row is small enough to prove inside its checkpoint. The
deterministic fresh-create/migration failure case is the only uncertain proof
seam. It may use one datastore-private injected failure at the create/migrate
call boundary. If that requires a generic filesystem abstraction or changes
production ownership, stop and replan.

## Checkpoint 1 — Prepare Once at Boot

### Red proof first

Add or reshape tests proving:

- `WorkspaceBootSequence` starts with database preparation;
- a configuration-backed datastore starts unprepared;
- persistence operations before preparation return a typed error and perform
  zero physical opens;
- repeated preparation returns the same receipt and performs one attempt;
- strict core behavior remains byte/migration correct;
- local clean/valid, corrupt/NOTADB, WAL-only, SHM-only, WAL+SHM, present-main
  without sidecars, quarantine-failure, fresh-create/migration-failure, and
  unclassified-failure branches match the matrix.

Primary test owner:

- new
  `Tests/AgentStudioTests/Core/Stores/WorkspaceSQLiteDatastorePreparationTests.swift`

Existing proof owners to reshape rather than duplicate:

- `AppBootSequenceTests.swift`
- `WorkspaceSQLiteStrictReadTests.swift`
- `WorkspaceStrictStartupSubprocessTests.swift`
- `WorkspaceSQLiteDatastoreActorTests.swift`
- `WorkspaceSQLiteDatastoreBoundaryTests.swift`
- `WorkspaceLocalMigrationTests.swift`
- `SQLiteRecoveryInfrastructureTests.swift`

Run the focused tests and confirm the new assertions fail for the expected
lazy-opening/ordering reasons before implementation.

### Implementation

In `WorkspaceSQLiteDatastoreTypes.swift`, add only concrete bootstrap
vocabulary:

- preparation receipt;
- strict core ready/uninitialized/failure outcome;
- local available-with-optional-recovery or unavailable outcome;
- typed pre-preparation error.

In `WorkspaceSQLiteDatastore`:

- add private state limited to
  `unprepared`, `prepared(receipt)`, and `failed(coreFailure)`;
- add `prepareDatabasesForBoot()`;
- reuse the existing database factory, core migration/strict acceptance,
  recovery classifier, and sidecar quarantine helper;
- after strict acceptance, release the transient byte-preserving startup reader
  and retain one writable core owner; later core reads and writes must not open
  another pool;
- inspect DB/WAL/SHM presence before any local SQLite open;
- on incomplete or classified-corrupt storage, quarantine every present
  component and create/migrate one fresh database;
- withhold fresh creation when quarantine reports any failure;
- retain local unavailable when fresh creation/migration or an unclassified
  open fails;
- cache terminal state before awaiting diagnostic delivery;
- make repeated preparation return the cached terminal result;
- reshape internal test construction to inject genuinely prepared core/local
  capabilities rather than lazy repository closures.

Do not create a public prepared type. Keep new result vocabulary in the types
file and use the repo's existing extension pattern if the 1,000-line datastore
needs a mechanical responsibility split.

In boot:

- add `.prepareDatabases` as the first presentation prerequisite;
- create and retain the datastore in that step;
- make canonical loading consume the receipt's accepted core snapshot instead
  of repeating strict acceptance;
- keep the `ready(uninitialized)` default-workspace verification as one real
  post-write read through the retained writable core owner without reading
  from or mutating the cached preparation receipt;
- stop boot on fatal core preparation failure;
- continue canonical hydration with deterministic local defaults when the
  receipt says local unavailable.

### Checkpoint proof

```bash
mise run test -- --filter \
'WorkspaceSQLiteDatastorePreparationTests|WorkspaceSQLiteStrictReadTests|WorkspaceStrictStartupSubprocessTests|AppBootSequenceTests|WorkspaceSQLiteDatastoreBoundaryTests|WorkspaceLocalMigrationTests|SQLiteRecoveryInfrastructureTests'
```

Checkpoint passes only when the transition matrix, strict core, boot order,
idempotence, and honest fixture contract are green.

## Checkpoint 2 — Remove Hidden Openers and Isolate Local Slices

### Red proof first

Reshape current demand-open and physical-event-delivery tests so they first
fail against the old behavior:

- application recency is the first local consumer and succeeds;
- application cache/recency operations accept no workspace ID;
- global plus two workspace scopes share one retained writer;
- unavailable local access through load/save/flush/termination never reopens;
- no store payload contains a physical `recoveryEvents` channel;
- malformed logical slices default independently;
- cursor and repository-cache multi-table groups default coherently;
- malformed window continuation defaults only window memory while sidebar
  shell memory still loads from the same table, and the inverse;
- each settings preference can fail independently;
- settings hydration writes nothing and the next real mutation preserves the
  existing sequential three-write behavior.

### Implementation

In the datastore:

- replace `localRepositoryForSave` and `localRepositoryForRestore` with one
  prepared-local accessor;
- move parameter-free application cache/recency operations onto the existing
  private application-local bundle;
- keep workspace repositories as ID-bound views over the same prepared writer;
- return the retained unavailable failure without opening;
- remove pending global/workspace physical recovery queues;
- remove physical `recoveryEvents` from all datastore load payloads;
- make canonical cursor and window fallback consume explicit prepared/slice
  outcomes instead of hiding physical preparation with `try?`;
- represent editor, repo-explorer, and inbox preference load outcomes
  independently with concrete fields.

In store/adaptor callers:

- remove physical recovery-event draining/reporting;
- retain store-owned logical reset/default/save-failed reporting;
- remove the RepoCache-before-application-recency warm-up dependency;
- preserve existing debounce, save ordering, and core-first commit semantics;
- do not add per-slice health state or change settings writes.

Likely callers:

- `RepoCacheStore.swift`
- `EntityRecencyStore.swift`
- `UIStateStore.swift`
- `SidebarCacheStore.swift`
- `WorkspaceSettingsStore.swift`
- `WorkspaceStore.swift`
- `WorkspaceSQLiteSaveCoordinator.swift`
- inbox SQLite adapter/store
- termination flush call sites.

### Checkpoint proof

```bash
mise run test -- --filter \
'WorkspaceSQLiteDatastorePreparationTests|WorkspaceSQLiteDatastoreActorTests|WorkspaceSQLiteDatastoreBoundaryTests|WorkspaceSQLiteStrictReadTests|WorkspaceSettingsStoreTests|RepoCacheStoreTests|EntityRecencyStoreTests|UIStateStoreTests|SidebarCacheStoreTests|InboxNotificationStoreTests'
```

Checkpoint passes only when no consumer lifecycle path remains, all local
slices follow the accepted fallback boundaries, and settings behavior is
unchanged except for independent loads.

## Checkpoint 3 — Once-Only Diagnostics and Current Documentation

### Implementation and proof

Use the existing workspace SQLite/startup trace infrastructure. Add the minimum
safe preparation record for:

- fatal core preparation failure;
- successful local replacement;
- local unavailable.

The record may contain database kind, preparation phase, classified failure,
SQLite result code when present, recovery attempt, and final disposition. It
must not contain raw paths, quarantine filenames, workspace/entity IDs, or
arbitrary error text. Trace failure must not alter the cached preparation
result.

Update only current sources of truth:

- `AGENTS.md`;
- `docs/architecture/state/workspace_data_architecture.md`;
- `docs/architecture/structure/component_architecture.md`;
- boot comments that say RepoCache opens the shared local database.

Remove the nonexistent `WorkspaceSQLiteStoreBackendFactory.swift` entry and
describe the implemented datastore/factory boundary. Do not rewrite historical
specs.

Focused proof:

```bash
mise run test -- --filter \
'WorkspaceSQLiteDatastorePreparationTests|WorkspaceSQLiteTraceRecorderTests|AgentStudioOTLPTraceProjectionTests|AppBootSequenceTests'

rg -n \
'localRepositoryFor(Save|Restore)|pendingGlobalRecoveryEvents|pendingRecoveryEventsByWorkspaceId|Repo-cache restore opens|WorkspaceSQLiteStoreBackendFactory' \
Sources/AgentStudio AGENTS.md docs/architecture
```

Any remaining match must be classified as a legitimate historical/test fixture
reference or removed before the checkpoint passes.

## Execution DAG

The central path is serial because every checkpoint changes or consumes the
same datastore contract:

```text
gate 0: recheck HEAD, spec SHA, and dirty worktree
  │
  ▼
checkpoint 1: boot-owned preparation + transition matrix
  │ focused red/green proof
  ▼
checkpoint 2: prepared-access cutover + slice isolation
  │ focused red/green proof
  ▼
checkpoint 3: diagnostics + current docs
  │ focused proof and stale-source search
  ▼
terminal repository proof
  │
  ▼
exact claude-opus-5 high implementation review
  │ parent validates and addresses or evidence-rejects findings
  ▼
PR 216 readiness proof; stop before merge
```

Bounded caller/test edits may be delegated after central types freeze, but no
parallel worker may edit `WorkspaceSQLiteDatastore.swift`,
`WorkspaceSQLiteDatastoreTypes.swift`, or `AppDelegate+WorkspaceBoot.swift`.

## Terminal Proof

Run from the repository root:

```bash
mise run lint
mise run test
mise run build

mise run observability:up
mise run run-debug-observability -- --detach
mise run verify-debug-observability
```

The debug verifier proves a real healthy boot through the new prerequisite and
source-scrubbed OTLP startup path. It does not replace the file-backed recovery
matrix.

Then:

1. run exact `claude-opus-5`, high, read-only implementation review with no
   inherited parent history;
2. parent-validate every finding against current source and proof;
3. fix accepted findings and rerun affected lower gates plus terminal gates;
4. commit and push only scoped changes;
5. confirm PR 216 head OID equals pushed HEAD;
6. use blocking `gh pr checks 216 --watch --interval 120`;
7. freshly inspect comments, review threads, review decision, merge state, and
   mergeability;
8. report readiness and do not merge.

## Recovery and Rollback During Development

No product rollback mechanism is added. Development changes are checkpointed
only after focused proof passes. If a checkpoint breaks strict core
preservation, requires excluded architecture, or encounters an unrelated
infrastructure failure, stop edits and report the scoped evidence rather than
expanding the task.

## Plan Completion Receipt

phase_result: complete

evidence:

- accepted 478-line spec and workflow state;
- live boot/datastore/store/test inspection at baseline HEAD;
- parent-reduced codebase, proof, reliability, and slice lanes;
- complete requirements/proof matrix, three checkpoints, execution DAG, and
  split triggers above.

recommended_next_workflow:
`shravan-dev-workflow:plan-review-swarm`

recommended_transition_reason:
The compact plan preserves every accepted requirement while limiting execution
to three serial proof-bearing checkpoints and explicitly forbidding broader
architecture.
