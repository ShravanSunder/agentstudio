# Core Topology And Atomic Persistence Plan

Status: reviewed and ready for `implementation-execute-plan`

Accepted source: `../2026-07-21-persistence-ownership-hard-cut.md`

Accepted source SHA-256: `ab9d72bade8f5d5fbbb0ea5d55321c93f99bb60cbbc85347fa6b77a3e07b6204`

Source coverage: `912/912` lines

## Worker contract

Execute with `implementation-execute-plan`. Re-read the accepted spec and live
owner files before each checkpoint. Use medium reasoning for bounded schema and
repository tasks and high reasoning for transaction, concurrency, and
integration tasks. Stop and return to design before adding a second
migration, compatibility path, repair/reconciliation framework, receipt/replay
system, or persistence logic in atoms.

This plan owns the only data migration in this persistence hard cut: one forward
migration of the existing authoritative `core.sqlite`. The new application-level
`local.sqlite` is created clean by the companion local plan and is never
migrated from old local databases or JSON.

Companion plans:

- [Application Local SQLite And Legacy Hard Cut](2026-07-22-application-local-sqlite-and-legacy-hard-cut.md)

## Outcome

Make repository topology globally owned and make each authoritative core load
or save one SQLite transaction. Workspace composition references global repo
and worktree IDs but never captures, mutates, or cascade-deletes topology.

## Fixed scope

In scope:

- One forward `core.sqlite` migration rebuilding exactly the five topology
  tables and dropping the obsolete pane workspace-matching facet triggers.
- Drop `workspace_sqlite_snapshot_status` and
  `legacy_workspace_import_status`.
- Global typed topology repository reads and mutations.
- Composition snapshots and writes with no topology payload.
- One-transaction core reads and one-transaction core writes.
- Bounded MainActor capture/apply; SQLite, validation, mapping, and collection
  work remain off-main.

Out of scope:

- Any migration of `local.sqlite`, per-workspace local sidecars, or JSON.
- Identity merge, deduplication, repair, replay, staged commits, recovery
  receipts, or backward-compatible read paths.
- Atom-owned persistence, transaction planning, or asynchronous work.
- EventBus, Ghostty, filesystem-event, or Git redesign.

## Execution DAG

```text
Gate 0: current HEAD + accepted spec + red tests
  |
  v
A1 one forward core migration + schema proof
  |
  +--------------------------+
  |                          |
  v                          v
A2 global topology API    B1 clean local schema/repositories
  |                          |
  v                          |
A3 composition excludes      |
   topology                  |
  |                          |
  +-------------+------------+
                v
A4 serial shared datastore/core integration
  |
  +--------------------------> B2 serial local boot/store integration
  v
A5 focused core proof + checkpoint commit
  |
  v
cross-plan integration -> lint -> full tests -> debug smoke
```

Only one worker at a time edits `WorkspaceSQLiteDatastore*`,
`WorkspaceSQLiteStoreBackend*`, shared boot wiring, or shared snapshot codecs.
A1/B1 parallelism is logical only: in one shared checkout, execute edits
serially or let one integration owner create path-scoped commits after all
editing workers are idle. Before each checkpoint, verify a clean staged index,
inventory the intended paths, and inspect `git show --stat --name-only` after
commit.

## A0 — Re-anchor and install failing proof

1. Confirm branch and preserve unrelated untracked files.
2. Re-read spec R1-R3, R6-R7, exact target DDL, startup/save contracts, and
   proof rows 1-7 plus 11-13.
3. Inspect live migration registration, topology repositories, composition
   snapshot/capture, datastore save/load, and their existing tests.
4. Add the smallest red tests for the target schema, global uniqueness,
   workspace-delete preservation, topology-free composition type, and atomic
   core read/write behavior. Run them and record expected failures.

Split/replan trigger: existing persisted data cannot be copied 1:1 into the
accepted target constraints without inventing a merge or repair policy.

## A1 — Apply the single forward core migration

Likely owners:

- `WorkspaceCoreMigrations.swift`
- `WorkspaceCoreMigrations+RepositoryTopology.swift`
- `WorkspaceCoreRepository*.swift`
- relevant core migration and topology tests

Actions:

1. Register one new forward migration; never edit shipped migration bodies or
   identifiers.
2. In that one transaction, rebuild `watched_path`, `repo`, `worktree`,
   `repo_tag`, and `unavailable_repo` to the accepted DDL.
3. Copy existing topology IDs and values 1:1.
4. Leave the `pane` table, rows, residency/lifecycle columns, and content rows
   unchanged; drop only its four obsolete workspace-matching facet triggers.
5. Drop the two obsolete core status tables.
6. Let any target uniqueness conflict abort and roll back the whole migration.

Local proof:

- exact `sqlite_master`, FK, index, PK, UNIQUE, and CHECK contract;
- 1:1 ID/value preservation;
- global uniqueness conflict leaves the old schema/data unchanged;
- workspace deletion leaves ordered topology rows byte-for-byte unchanged;
- two workspaces may reference the same repo/worktree.

Checkpoint commit: core schema migration and focused green tests.

## A2 — Give topology one global repository boundary

Actions:

1. Remove `workspace_id` from topology repository APIs and predicates.
2. Expose typed global reads and mutations for watched paths, repositories,
   worktrees, tags, and availability.
3. Require pane repo/worktree references to resolve against global topology.
4. Reject duplicate global stable keys and invalid references; never merge or
   reuse an ID to repair them.
5. Keep canonical atoms as state/derived-state owners only. Coordinators and
   persistence wrappers sequence mutations.

Local proof:

- global CRUD and reference validation;
- no workspace-qualified topology fetch/mutation remains;
- deletion of one workspace cannot mutate global topology;
- topology removal clears pane facets through `ON DELETE SET NULL` without
  changing pane residency, CWD, surface, runtime state, or stored ZMX identity;
- duplicate stable keys fail explicitly and atom state is not partially
  accepted.
- every new durable entity ID created by this cutover uses UUIDv7; existing
  stored IDs remain unchanged.

## A3 — Remove topology from composition

Likely owners:

- `WorkspaceSQLiteSaveCoordinator.swift`
- `WorkspaceSQLiteSnapshot.swift`
- `WorkspaceSQLiteStateBridge+Models.swift`
- `WorkspacePersistenceTransformer.swift`
- `WorkspaceStore.swift` and focused tests

Actions:

1. Define the composition save/load value so its type cannot carry topology.
2. Capture only workspace identity and pane/tab/arrangement/drawer composition
   on MainActor.
3. Validate, map, and prepare immutable rows off-main.
4. Apply loaded composition in one bounded MainActor mutation after validation;
   do not scale MainActor work with watched-path/repository count.

Local proof:

- compile-time/type-shape test shows topology is absent;
- barrier-controlled stale composition capture cannot overwrite topology;
- a focused Swift integration fixture compares small and production-shaped
  repository/watch-folder populations and proves the same fixed number of
  synchronous MainActor capture/apply operations. No timing assertion or new
  script is introduced.

## A4 — Replace staged commit with atomic core transactions

Likely owners:

- `WorkspaceSQLiteDatastore.swift`
- `WorkspaceSQLiteDatastoreTypes.swift`
- `WorkspaceSQLiteStoreBackend*.swift`
- `WorkspaceCoreRepository.swift`
- strict-read, commit-protocol, datastore-actor, and save-coordinator tests

Actions:

1. Delete stage/complete token APIs and their result types.
2. Save all authoritative core composition changes in one database transaction.
3. Load active selection, workspace metadata, composition, and global topology
   from one consistent read transaction.
4. Keep local persistence outside this transaction; local failure cannot roll
   back or invalidate core.
5. Preserve actor serialization and perform synchronous GRDB work only inside
   the datastore actor's existing boundary.

Local proof:

- forced failure before commit leaves the prior complete core state readable;
- concurrent writer hydration observes one consistent snapshot;
- no completion-token read/write remains;
- core save succeeds independently of local failure.

Checkpoint commit: atomic core read/write cutover with focused green tests.

## A5 — Core slice gate

Run focused tests first:

```bash
mise run test -- --filter 'WorkspaceCoreMigrationTests|WorkspaceCoreRepositoryTopologyTests|WorkspaceCoreRepositoryTopologyReferenceTests|WorkspaceCoreRepositoryTopologyRollbackTests|WorkspaceCoreRepositoryTopologyValidationTests|WorkspaceSQLiteSaveCoordinatorTests|WorkspaceSQLiteStrictReadTests|WorkspaceSQLiteCommitProtocolTests|WorkspaceSQLiteDatastoreActorTests|WorkspaceSQLiteDatastoreBoundaryTests|WorkspaceSQLiteSnapshotRoleTests'
```

Then run `mise run lint`. Do not widen into local or pane-lifecycle repairs when an
unrelated gate fails; report it under the validation scope guard.

## Requirements and proof matrix

| Requirement | Owning task | Proof | Layer | Freshness guard |
| --- | --- | --- | --- | --- |
| R1 global topology | A1-A2 | schema inspection, preservation, global CRUD, delete isolation | unit + SQLite integration | candidate HEAD and migrated fixture |
| R2 composition references topology | A2-A3 | invalid-reference tests and topology-free type | unit + compile-time | live type definitions |
| R3 atomic core persistence | A4 | failure rollback and concurrent snapshot barriers | SQLite integration | fresh database per test |
| R6 core failure containment | A1/A4 | migration rollback and prior state remains bootable | integration | forced pre-commit failure |
| R7 bounded MainActor | A3/A4 | actor-bound capture assertion and size-independent operation count | unit + integration | candidate executor and current actor annotations |
| UUID identity | A1/A2 | existing IDs preserved; newly generated IDs parse/version as UUIDv7 | unit + SQLite integration | migrated fixture and candidate generator |
| OTLP privacy | A1/A4 | existing projection tests reject sentinel path, UUID, content, and raw-error values | unit | candidate OTLP projection and sentinel payloads |

Every behavior row requires red/green evidence. If a proof cannot pass within
this slice, split the task or return to design; do not defer correctness to the
final full-suite gate.

## Risk and rollback

The single core migration is the irreversible product boundary. SQLite's
transaction rollback is the failure behavior: no partial target schema, no
automatic merge, and no runtime fallback. Before checkpointing, prove migration
failure preserves the original database. Source rollback is ordinary commit
revert before release; do not add a down-migration.

Security context: applicable. The OTLP projection remains scrubbed; no raw
paths, UUIDs, pane content, payloads, or raw errors enter OTLP. This does not
redesign richer local/JSONL developer diagnostics.
