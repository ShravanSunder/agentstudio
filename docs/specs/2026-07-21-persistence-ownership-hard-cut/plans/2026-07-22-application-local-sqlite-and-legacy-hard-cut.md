# Application Local SQLite And Legacy Hard Cut Plan

Status: reviewed and ready for `implementation-execute-plan`

Accepted source: `../2026-07-21-persistence-ownership-hard-cut.md`

Accepted source SHA-256: `ab9d72bade8f5d5fbbb0ea5d55321c93f99bb60cbbc85347fa6b77a3e07b6204`

Source coverage: `912/912` lines

## Worker contract

Execute with `implementation-execute-plan`. This slice creates one fresh
application-level `local.sqlite`; it performs no migration or import. Only the
companion core plan migrates data. Stop before adding backward compatibility,
legacy-file deletion, a recovery framework, replay/materialization receipts, or
new persistence authority in atoms.

Companion plans:

- [Core Topology And Atomic Persistence](2026-07-22-core-topology-and-atomic-persistence.md)

## Outcome

Open exactly one non-authoritative `local.sqlite` at the application data root.
Local rows are keyed by their real owner (`workspace_id`, `window_id`, or
global), and missing, corrupt, unavailable, or invalid local data defaults
without blocking authoritative core startup. Fully remove obsolete standalone
app-state JSON and old JSON-to-SQLite/per-workspace-sidecar code paths while
preserving `preferences.global.json`.

## Fixed scope

In scope:

- One clean `local.sqlite` with exactly the target DDL in spec R4-R5.
- Typed repositories for workspace continuation, window/sidebar presentation,
  recent targets, notification inbox, workspace preferences, and global caches.
- Deterministic defaults per invalid or unavailable local lane.
- Complete deletion of legacy JSON and per-workspace local persistence code.
- Dead legacy tests replaced with target-contract tests.

Out of scope:

- Any migration/import/copy from old JSON or `<workspace-id>.local.sqlite`.
- Deleting existing legacy files from the user's disk.
- `preferences.global.json`, IPC JSON, OTLP/JSONL, test fixtures, or SQLite
  `payload_json` columns.
- `WorkspaceSQLiteSnapshot`, which is the live typed SQLite bridge value.
- Pane retention, orphan residency, and `surface-checkpoint.json`; those belong
  to the separate pane-retention follow-up.
- Core migration, EventBus, Ghostty, or atom redesign.

## B0 — Install fresh-schema and no-legacy failing proof

1. Re-read spec R4-R7, target local DDL, startup/save contracts, and proof rows
   8-10 plus 12-13.
2. Inventory every production reference to `WorkspacePersistor`, legacy import
   decisions/markers, local completion tokens, per-workspace local paths, and
   standalone JSON app-state paths.
3. Add red tests for one local path/open, exact schema, typed round-trips,
   deterministic defaults, and zero legacy path access.
4. Use path/open probes inside existing test seams; do not add a new script or
   product-only test hook.

Split/replan trigger: a purported legacy file contains authoritative core data
not represented in `core.sqlite`. Do not silently import it.

## B1 — Create one clean application local database

Likely owners:

- `AppDataPaths.swift`
- `WorkspaceLocalMigrations.swift`
- `WorkspaceLocalRepository*.swift`
- `WorkspaceSQLiteDatastoreFactory.swift`
- local schema/migration/repository tests

Actions:

1. Replace the workspace-parameterized local URL with one app-root
   `local.sqlite` URL.
2. Replace the old local migration chain with the complete target schema as the
   initial schema for this new file. There is no forward local data migration,
   historical local migration execution, or import from any former database.
3. Key rows exactly by accepted ownership: workspace rows by `workspace_id`,
   window presentation by stable `window_id`, and truly shared caches globally.
4. Remove local completion/import/marker tables from the target schema.
5. Preserve foreign-key and validation constraints in the accepted DDL without
   adding speculative per-field policy tables or UUID-repair rules.

Local proof:

- exact tables, columns, indexes, CHECKs, and FKs;
- every typed table round-trips valid values and rejects invalid shapes;
- two workspace-owned row sets remain isolated in the same file;
- first use creates the one `window_role = 'main'` row with a UUIDv7
  `window_id`; reopening resolves the same ID by role, sidebar child rows remain
  attached to it, and the schema rejects a second `main` row;
- one app process opens one local database URL.

Checkpoint commit: clean target local schema and typed repository tests.

## B2 — Cut stores and boot to typed local repositories

This step waits for the core plan's shared datastore interface checkpoint.
Only one integration owner edits shared datastore/backend and boot files.

Likely owners:

- `WorkspaceSQLiteDatastore*.swift`
- `WorkspaceSQLiteStoreBackend*.swift`
- `RepoCacheStore.swift`
- `UIStateStore.swift`
- `SidebarCacheStore.swift`
- `WorkspaceSettingsStore.swift`
- `InboxNotificationStore.swift`
- `InboxNotificationSQLiteRepository.swift`
- `AppDelegate+WorkspaceBoot.swift`
- `AppDelegate+InboxNotificationBoot.swift`

Actions:

1. Replace per-workspace local repository caching with one repository bundle for
   the application local database.
2. Make each store load only its typed local lane.
3. Default a missing, corrupt, unavailable, or invalid lane independently;
   local state never validates or blocks core composition.
4. Persist settled UI/store values through the existing persistence wrappers;
   atoms remain canonical state or pure derived state, never I/O owners.
5. Keep database I/O, row mapping, and validation off-main. MainActor captures
   or applies only bounded immutable values.
6. Emit typed diagnostics that name lane/outcome. Existing OTLP projection
   tests must prove raw paths, UUIDs, pane contents, payloads, and raw errors
   are not exported; do not redesign local/JSONL diagnostics.

Local proof:

- each lane defaults independently;
- corrupt/unavailable local file does not prevent core hydration;
- local write failure cannot affect committed core;
- stale window/workspace IDs are rejected or ignored according to the accepted
  typed repository contract, without a repair workflow.

## B3 — Delete legacy persistence code completely

Delete production code, not existing user files.

Required removals:

- `WorkspacePersistor.swift` and `WorkspacePersistor+Payloads.swift`.
- `WorkspacePersistor.PersistableState` conversions and compatibility DTOs.
- JSON branches in repo cache, UI state, sidebar cache, settings, inbox, and
  workspace/inbox boot.
- `WorkspaceLocalSQLiteLegacyImportDecision` and related lane/import result
  payloads.
- `local_persistence_lane_marker`, local completion-token machinery, and their
  compatibility tests. Verify that the core plan already removed
  `legacy_workspace_import_status` and core completion-token machinery; do not
  reopen core-owned files in this checkpoint.
- Legacy materialization, archive/replay, corrupt/backup, reader, writer, and
  quarantine code used only by standalone app-state JSON.
- `LocalSQLiteRestoreOutcome.swift` if no target runtime reference remains.
- Tests whose sole purpose is legacy JSON import or per-workspace-sidecar
  compatibility; replace only tests needed to assert the target contract.

Explicitly preserve:

- `preferences.global.json` and its live owner;
- generic JSON codecs used by IPC, OTLP/JSONL, fixtures, or `payload_json`;
- generic SQLite corruption containment needed to default the new
  non-authoritative local database;
- all old files already on disk, untouched and never opened.

Local proof:

```bash
rg -n 'WorkspacePersistor|PersistableState|WorkspaceLocalSQLiteLegacyImportDecision|legacy_workspace_import_status|local_persistence_lane_marker' Sources Tests
```

Expected result: zero production compatibility-path matches; any retained test
fixture string must be justified as negative proof. Add open/path-spy tests that
plant legacy JSON and old sidecar sentinels, boot, and prove their bytes and
timestamps are unchanged.

Checkpoint commit: legacy code/tests deleted and all stores on typed local
repositories.

## B4 — Local slice gate

```bash
mise run test -- --filter 'AppDataPathsTests|WorkspaceLocalMigrationTests|WorkspaceLocalSchemaContractTests|WorkspaceLocalRepositoryTests|WorkspaceSQLiteDatastoreActorTests|WorkspaceSQLiteDatastoreBoundaryTests|WorkspaceSQLiteStoreRecoveryTests|WorkspaceStoreStrictSQLiteLoadTests|WorkspaceStrictStartupSubprocessTests|RepoCacheStoreTests|UIStateStoreTests|SidebarCacheStoreTests|WorkspaceSettingsStoreTests|InboxNotificationStoreTests|InboxNotificationSQLiteRepositoryTests'
mise run lint
```

Before freezing the filter, use the existing test-list command to confirm Swift
Testing discovery names; do not invent a harness or omit an affected owner.

## Requirements and proof matrix

| Requirement | Owning task | Proof | Layer | Freshness guard |
| --- | --- | --- | --- | --- |
| R4 one clean local DB | B1 | exact schema, one URL/open, multi-owner isolation | SQLite integration | fresh app-root database |
| R5 explicit local ownership | B1-B2 | typed round-trips and independent defaults | unit + integration | candidate schema and repositories |
| R6 failure containment | B2 | missing/corrupt/unavailable/default tests; core unchanged | integration | fresh failure fixture |
| R7 bounded MainActor | B2 | actor annotations and size-independent capture/apply | unit + integration | current executor annotations |
| Hard cut | B3 | source scan plus sentinel no-read/no-write boot proof | static + smoke | final candidate HEAD and fresh sentinels |

Every behavior row requires red/green evidence. The hard-cut scan is necessary
but not sufficient; boot/open probes must prove the old paths are unused.

## Risk and rollback

The accepted tradeoff is loss of non-authoritative local history on first
launch of this version. Deterministic defaults keep the app usable. Rollback is
source-level before release; do not create importers or compatibility readers
to make rollback easier.

Security context: applicable. Never export local file paths, UUIDs,
notification content, pane content, decoded payloads, or raw errors through the
OTLP projection. Local/JSONL developer diagnostics are not redesigned here.
