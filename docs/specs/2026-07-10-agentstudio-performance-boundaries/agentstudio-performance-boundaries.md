# AgentStudio Performance Boundaries

Date: 2026-07-10
Revised: 2026-07-17 after performance-branch cleanup
Status: accepted current-state contract
Scope: performance and correctness boundaries retained after removal of dormant architectures
Source baseline: `ghostty-performance-cleanup` at `ea1402ad`

## Product Intent

AgentStudio is an interactive terminal workspace first. Background filesystem
observation, repository discovery, Git projection, persistence, Bridge refresh,
and terminal output must not make typing, cursor movement, pane switching, or
current terminal presentation feel frozen.

Responsiveness cannot be purchased by corrupting canonical state or inventing
recovery. Work may be coalesced only where the live owner defines that behavior.
Strict SQLite loading, exact stored terminal-session identity, source-authorized
filesystem roots, and stale-result rejection remain correctness boundaries.

This document describes the cleaned implementation and the constraints on later
performance work. It does not make deleted experimental types normative.

Domain detail:

- [Watched-Folder Admission and MainActor Fairness](../2026-07-09-watched-folder-admission-mainactor-fairness/watched-folder-admission-mainactor-fairness.md)
- [Ghostty Host Boundary and Terminal Interaction Fairness](../2026-07-09-ghostty-terminal-interaction-fairness/ghostty-terminal-interaction-fairness.md)

## Current System Model

```text
DarwinFSEventStreamClient
  -> AsyncStream<FSEventBatch>
  -> FilesystemActor
       +-> bounded/coalescing WatchedFolderScanScheduler
       +-> existing EventBus<RuntimeEnvelope>
       +-> filesystem and Git projection paths

SQLite repositories
  -> WorkspaceSQLiteDatastore strict load
  -> off-main WorkspaceCompositionPreparer validation
  -> one MainActor prepared-composition apply
  -> visible-first terminal and nonterminal mounting

canonical atoms
  -> current state, local indexes, equal-write suppression, pure derivation
  -> WorkspaceSQLiteSaveCoordinator capture
  -> ordered WorkspaceSQLiteDatastore save

terminal restoration
  -> nonblank stored ZmxSessionID restored verbatim
  -> exact identity passed to zmx attachment
```

The current paths are deliberately ordinary. They do not contain a generic
admission framework, fixed-slot observation fleet, source-repair state machine,
live-atom persistence pager, or acceptance-grade MainActor diagnostic ledger.

## Retained Ownership Boundaries

### Filesystem

`DarwinFSEventStreamClient` owns native stream registration, callback-context
lifetime, callback path copying, and stream teardown. `FilesystemActor` owns
registration state, deepest-root routing, path filtering, debounce/flush
ordering, watched-folder scan submission, scan-result application, and existing
runtime-envelope publication.

`WatchedFolderScanScheduler` remains production-reachable. It owns bounded scan
concurrency, same-root coalescing, FIFO fairness, checked demand/run generations,
validation custody, result leasing, and stale-result rejection. `RepoScanner`
and its validation executor own traversal and bounded Git discovery reads.

The current Darwin callback path does not preserve native FSEvent flags or event
IDs and feeds an unbounded `AsyncStream`. Those are known limitations, not
contracts to conceal and not proof that a replacement has been implemented.

### MainActor And Atoms

MainActor owns AppKit interaction and canonical observable atoms. Atoms own
current state, simple accepted assignments/transforms, local keyed indexes,
equal-write suppression, and pure derivation. They do not own persistence
revisions, leases, participants, preimages, pagers, transaction planning,
hydration workflow, retries, I/O, or cross-atom persistence orchestration.

Off-main work should produce immutable, already-validated input for a narrow
MainActor mutation. Fixed changed-key work must not grow with the total
repository, worktree, pane, or subscriber fleet unless the product operation is
intrinsically fleet-wide and measured as such.

### Persistence

The current implementation strictly loads completed core/local SQLite state,
prepares and validates composition off-main, applies accepted composition once,
captures save bundles on MainActor, and serializes datastore saves in order.
This cleanup does not introduce a second persistence path.

The retained direction for later persistence performance work is semantic
changed-row/table transactions owned by the persistence layer. A canonical
mutation should eventually hand persistence the exact semantic rows/tables that
changed; persistence should transact those changes without asking atoms to own
revisions, historical preimages, participants, leases, or paging. This direction
is not implemented by the cleanup and does not authorize an incremental-row API
or schema design in this spec.

### Runtime Transport

The live global transport remains the existing `EventBus<RuntimeEnvelope>` and
its current producers/consumers. This cleanup does not claim a topic-aware
semantic replacement bus exists. Domain owners should avoid unnecessary global
fanout and same-bus amplification, but a semantic EventBus hard cut requires a
later design and implementation contract.

### Terminal And Ghostty

The existing Ghostty host, surface manager, callback router, and terminal runtime
remain production owners. Direct input and presentation behavior stay on their
current host path. This cleanup does not implement Ghostty action contraction,
a gather thread, a new callback mailbox, or a new terminal fact plane.

## Compatibility Floor

### SQLite

- A database already at the current schema is read without a cleanup migration.
- Established historical GRDB migrations already present in the repository may
  run only to bring an older supported database to the current schema.
- The cleanup adds no migration, backfill, quarantine, reconstruction, startup
  repair, compatibility shim, or legacy composition fallback.
- After schema preparation, a missing, incomplete, inconsistent, corrupt, or
  otherwise invalid completed snapshot fails strict loading. It is not repaired
  into a different workspace.
- A genuinely uninitialized database may create the normal default workspace;
  that bootstrap is not recovery of an invalid existing database.

### ZMX Session Identity

- Every terminal session identity is an opaque `ZmxSessionID`.
- New identities use UUIDv7.
- Any existing nonblank stored identity, including historical UUIDv4 or `as-*`
  values, is restored and used exactly as stored.
- Blank stored identity is invalid.
- No pane, path, repository, worktree, launch directory, or live-session scan may
  infer or rewrite the stored identity.
- The cleanup adds no identity migration, adoption, backfill, repair, or
  compatibility alias.

## Current Performance Requirements

1. Watched-folder scans retain bounded concurrency, same-root coalescing, FIFO
   fairness, and current-generation result checks.
2. Root authority comes from registered user-authorized roots. Canonicalization
   and routing must not let raw callback paths widen authority.
3. Git discovery/status reads retain their explicit timeouts and bounded
   execution owners.
4. Partial or stale scan evidence cannot authorize destructive absence. Only the
   live reducer's complete/current evidence path may replace negative space.
5. MainActor work must stay proportional to the intended mutation. Filesystem
   traversal, Git reads, large serialization, and package construction remain
   off-main.
6. Startup composition validation remains exhaustive and off-main; rejection
   performs no partial canonical installation.
7. Terminal and nonterminal mounting remains bounded and visible-first. Topology
   work does not gate composition or active terminal readiness.
8. Persistence saves remain ordered and strict-validation failures remain
   explicit.
9. Telemetry remains content-safe, bounded, fail-open, and separate from product
   correctness. Raw paths, terminal content, prompts, payloads, and secrets do
   not become exported dimensions.
10. A performance claim requires a reproducible workload, an independent final
    state oracle, latency distributions rather than event presence, and current
    build/run identity.

## Post-Cleanup Work, Not Yet Implemented

The following are valid future problem areas, not current architecture:

- bounded Darwin callback admission that preserves loss/discontinuity evidence;
- a persistent generation-bearing root ownership index;
- a semantic EventBus contract and hard cut from broad runtime envelopes;
- Ghostty callback/action contraction based on measured pressure;
- semantic changed-row/table persistence transactions;
- live MainActor availability/occupancy measurement with calibrated overhead.

Each item requires a fresh current-source design, explicit tradeoffs, focused
proof, and a hard cut. Deleted mailbox, journal, fixed-slot, source-gate, repair,
pager, participant, or diagnostic types are not presumed starting points.

## Superseded Architecture

Historical revisions of this spec proposed the following systems: generic
admission primitives, `RuntimeFactBus`, fixed persistence
revisions and snapshot paging, `MainActorWorkLedger`, responsiveness heartbeat,
performance evidence ledgers, and content-repair registries/projectors. Those
proposals were removed during cleanup because they were dormant or unreachable.
They are retained only in Git history and define no current requirement.

## Proof Boundary

Current cleanup and later performance work must preserve these proof layers:

- focused scheduler, Darwin client, filesystem/Git, strict SQLite, composition,
  mounting, and exact-ZMX restoration tests;
- build and architecture lint;
- isolated debug-app launch and marker-scoped observability when runtime behavior
  changes;
- SQLite restore/save/relaunch proof for persistence changes;
- native interaction proof when a terminal or AppKit path changes.

Unit or synthetic workload success does not substitute for a required runtime
gate, and telemetry presence alone is not a latency or correctness result.

## Non-Goals

- No replacement API or detailed design for the future work above.
- No compatibility layer for deleted experimental architectures.
- No new SQLite or ZMX migration/repair path.
- No claim that cleanup alone fixes the dominant live performance issue.
- No claim that layer publication is physical display scanout.
