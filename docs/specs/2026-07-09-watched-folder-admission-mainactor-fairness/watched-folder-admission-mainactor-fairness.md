# Watched-Folder Admission and MainActor Fairness

Date: 2026-07-09
Revised: 2026-07-17 after performance-branch cleanup
Status: accepted cleaned current-state contract
Source baseline: `ghostty-performance-cleanup` at `ea1402ad`

Parent contract: [AgentStudio Performance Boundaries](../2026-07-10-agentstudio-performance-boundaries/agentstudio-performance-boundaries.md)

## Product Intent

AgentStudio must remain interactive while it watches and scans large repository
fleets. Adding a watched parent, reopening a workspace containing one, or
running tools that continuously mutate repositories must not create unbounded
MainActor work or silently corrupt repository/worktree topology.

This spec describes the retained filesystem path after dormant observation,
admission, source-gate, and content-repair systems were removed. It names
current limitations honestly and leaves their replacement to later design.

## Current Retained Path

```text
native FSEvent stream per registered worktree or watched-parent source
  -> DarwinFSEventStreamClient callback copies paths
  -> AsyncStream<FSEventBatch>
  -> FilesystemActor
       -> deepest-root ownership routing and path filtering
       -> debounced filesChanged runtime envelopes
       -> WatchedFolderScanScheduler for watched-parent discovery
            -> bounded traversal quanta
            -> bounded Git discovery validation
            -> current-generation result lease
       -> WatchedFolderInventoryReducer
       -> current EventBus<RuntimeEnvelope> consumers
```

The production constructors are direct: `FilesystemActor` defaults to
`DarwinFSEventStreamClient()` and `WatchedFolderScanScheduler.production()`.
There is no production fixed-slot mailbox, observation fleet, native-generation
owner, source gate, repair projector, content-repair registry, or generic
admission/journal layer.

## Current Owners

### `DarwinFSEventStreamClient`

Owns:

- native stream creation, start, stop, invalidation, and release;
- one serial dispatch queue and callback context per registration;
- callback path copying into `FSEventBatch`;
- registration replacement and shutdown teardown.

Does not own scanning, topology, root authorization, Git, canonical state, or
MainActor mutation.

Current limitation: the callback ignores native flags and event IDs and yields
into an unbounded `AsyncStream`. Therefore the current implementation cannot
claim bounded callback admission or explicit FSEvent-loss repair.

### `FilesystemActor`

Owns:

- worktree registration state and source-to-root association;
- canonical root preparation through the current root-ownership helpers;
- deepest-root routing, ignore-policy filtering, `.git` classification, debounce,
  priority-aware flush, and bounded event chunking;
- watched-folder scan submission and scan-result application;
- the current runtime-envelope emission path.

It must not move filesystem traversal, Git reads, or fleet reconstruction onto
MainActor. Raw paths do not authorize a root outside the registered source.

### `WatchedFolderScanScheduler`

Owns:

- the production concurrency limit from `AppPolicies.WatchedFolderScanning`;
- per-source queued/running/awaiting-validation/result states;
- same-root coalescing and one dirty follow-up;
- FIFO ready ordering and bounded traversal dispatch;
- checked demand and scan-run generations;
- validation completion custody, result leasing, retry/transfer, retirement, and
  stale-result rejection.

The scheduler is a keep boundary. Cleanup must not replace it with an unbounded
task-per-scan path or remove its current-generation checks.

### Scanner And Validation

`RepoScanner` owns resumable traversal and structured completeness evidence.
`RepoScannerValidationExecutor` and `RepoScannerGitDiscoveryClient` own bounded
Git discovery reads. Discovery and status timeouts remain explicit and cannot be
silently widened by a filesystem callback path.

### Inventory Application And Runtime Transport

`FilesystemActor` consumes leased scheduled results and revalidates the exact
registered root before applying them. `WatchedFolderInventoryReducer` may
authoritatively replace negative space only when the scheduled result proves the
current complete evidence required by the live reducer; otherwise it preserves
existing truth and applies positive/additive evidence only.

The global publication path remains the current `EventBus<RuntimeEnvelope>`.
This spec does not claim a semantic topic bus, repair acknowledgement protocol,
or content-consumer registry exists.

## Current Requirements

### Source And Authority

WF-C1. A registration is selected by its host-owned worktree/source identity and
canonical root. Raw callback strings, relative traversal, symlinks, case
variation, `.git` metadata, or scanner results cannot widen watcher authority.

WF-C2. Registration replacement and shutdown must stop/invalidate/release the
native stream and release its callback context exactly once.

WF-C3. The current callback must copy only the paths supplied by the native
batch shape it can safely inspect. It must not perform scanning, Git work,
MainActor mutation, or per-path product routing in the callback.

WF-C4. Because flags/event IDs and bounded callback admission are not currently
implemented, no current correctness claim may depend on observing an explicit
drop/discontinuity state.

### Scan Scheduling

WS-C1. Each source/root has at most one active scan quantum; triggers received
while work is queued, running, validating, or awaiting result transfer coalesce
into current per-source scheduler state.

WS-C2. A hot root reenters FIFO scheduling and cannot bypass the global
concurrency limit or permanently starve already-ready unrelated roots.

WS-C3. Every scheduled result carries checked registration coverage, demand
coverage, and scan-run generation. Stale registration or stale run results do
not mutate inventory.

WS-C4. Traversal and Git validation remain off-main. The validation executor
keeps its bounded physical concurrency and a timed-out/cancelled native read does
not create synthetic extra capacity.

WS-C5. Partial, failed, cancelled, unavailable, or stale evidence cannot
authorize destructive absence. Positive evidence may merge only through the
live reducer's non-destructive path.

### MainActor Fairness

MA-C1. Filesystem callbacks, traversal, validation, path canonicalization,
inventory reduction, and Git reads remain outside MainActor.

MA-C2. MainActor receives already-reduced mutations through existing owners.
Work for a fixed set of changed keys must not scale with the total fleet without
an explicit measured reason.

MA-C3. Filesystem/topology startup remains independent from accepted composition
installation and terminal attachment. Background discovery does not gate typing
readiness.

MA-C4. Native and Bridge presentation may consume filesystem-derived current
state, but a global filesystem consumer must not await package construction,
WebKit delivery, or rendering inline with source ingestion.

### Persistence Interaction

P-C1. Atoms remain current-state owners only. They do not acquire filesystem
repair state, persistence revisions, snapshot leases, participants, or paging.

P-C2. Current saves remain ordered through `WorkspaceSQLiteSaveCoordinator` and
`WorkspaceSQLiteDatastore`; strict composition validation precedes persistence.

P-C3. The retained future direction is semantic changed-row/table transactions
owned by persistence. It is not implemented here and this spec defines no new
change-set, revision, checkpoint, or pager API.

## Compatibility And Correctness Floor

- Strict SQLite current-schema loading and completed core/local snapshot matching
  remain required. Cleanup adds no startup repair, legacy composition fallback,
  quarantine, backfill, or new migration.
- Existing historical GRDB migrations may bring a supported older database to
  the current schema; no cleanup-specific migration is authorized.
- Terminal restore uses each nonblank stored `ZmxSessionID` exactly as stored.
  New IDs use UUIDv7; existing values are not rewritten or inferred.
- Duplicate repository/worktree identities and consumed-ID violations remain
  rejected before invalid topology becomes live.

## Performance Proof

Focused proof for changes to this path includes:

- production watched-folder scheduler tests for concurrency, same-root
  coalescing, FIFO fairness, dirty follow-up, validation, result leasing, and
  stale generations;
- Darwin stream-client lifecycle tests;
- `FilesystemActor` watched-folder and filesystem/Git integration tests;
- independent final inventory/Git oracle for a generated watched-root fixture;
- latency distributions for terminal interaction during watched pressure when a
  user-visible performance claim is made;
- build, architecture lint, and marker-scoped runtime observability for a
  production-path change.

Telemetry presence alone is not proof of bounded callback admission, fairness,
convergence, or interaction latency.

## Post-Cleanup Work, Not Yet Implemented

The following require new designs based on current source:

- bounded Darwin callback admission with native flag/event-ID capture and an
  explicit loss/currentness contract;
- a persistent generation-bearing root index that avoids repeated fleet routing;
- a semantic EventBus hard cut with explicit topic/replay/ordering ownership;
- calibrated live MainActor availability/occupancy measurement;
- semantic changed-row/table persistence transactions;
- Ghostty action/callback contraction when measured evidence justifies it.

No deleted mailbox, slot, source-gate, repair, journal, pager, or diagnostic API
is implicitly selected for that work.

## Superseded Design Record

Earlier revisions specified `Admission*`, `BoundedGatherMailbox`,
`LatestValueMailbox`, `OrderedFactJournal`, `AdmissionDoorbell`, fixed
observation slots, native registration owners, observation fleet shutdown,
`FilesystemSourceGate`, recovery-evidence registers,
`WorktreeContentRepairConsumerRegistry`, `FilesystemContentRepairProjector`,
`RuntimeFactBus`, persistence revision/pager participants, and diagnostic
ledgers. These were dormant experimental architectures removed by cleanup. They
remain historical context in Git only and impose no current requirement.

The former child lifecycle document is explicitly superseded:
[Filesystem Observation Admission Lifecycle](filesystem-observation-admission-lifecycle.md).

## Non-Goals

- No detailed replacement design for future Darwin admission, root indexing, or
  semantic transport.
- No content-repair acknowledgement state machine.
- No reintroduction of fixed-slot or generic admission infrastructure.
- No claim that cleanup proves the user's dominant performance root cause.
- No rewrite of the retained scan scheduler, Git provider, or filesystem
  projection path in this documentation change.
