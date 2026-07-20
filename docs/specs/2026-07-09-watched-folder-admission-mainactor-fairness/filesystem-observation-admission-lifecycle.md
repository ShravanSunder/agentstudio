# Filesystem Observation Admission Lifecycle

Date: 2026-07-12
Superseded: 2026-07-17 by performance-branch cleanup
Status: superseded historical design; not a current implementation contract

Current parent:
[Watched-Folder Admission and MainActor Fairness](watched-folder-admission-mainactor-fairness.md)

## Disposition

The fixed-slot observation lifecycle described by the original revision was
dormant and was removed during cleanup. This document no longer defines required
types, owners, states, transitions, capacities, lints, tests, or implementation
work.

The deleted design included:

- `FilesystemObservationMailbox` and its core/facade split;
- `BoundedGatherMailbox` and `AdmissionDoorbell` coupling;
- fixed physical observation slots and binding identities;
- native registration-generation/control-block owners;
- callback leases, retirement fences, and context-release acknowledgements;
- recovery-evidence registers and `FilesystemSourceGate` handoff;
- observation fleet shutdown/debt machinery;
- SwiftSyntax rules and compiler fixtures specific to those structures.

None of those names is a compatibility surface or a required starting point for
future work.

## Current Retained Path

```text
DarwinFSEventStreamClient
  -> AsyncStream<FSEventBatch>
  -> FilesystemActor
  -> WatchedFolderScanScheduler where discovery is required
  -> existing EventBus<RuntimeEnvelope> and filesystem/Git consumers
```

`DarwinFSEventStreamClient` directly owns native stream/context lifecycle.
`FilesystemActor` directly owns current registration, routing, filtering,
debounce, scan orchestration, and envelope emission. `WatchedFolderScanScheduler`
owns bounded scan concurrency, same-root coalescing, FIFO fairness, validation
custody, result leasing, and stale-generation checks.

The current callback ignores native flags/event IDs and uses an unbounded
`AsyncStream`. Therefore bounded Darwin admission and explicit discontinuity
recovery are future work, not present behavior.

## Historical Rationale Worth Preserving

The superseded design investigated real constraints that remain useful as
problem statements:

- callback work should be bounded before it creates one task/message per raw
  event;
- replacing one source should not require fleet-wide teardown;
- stale callback authority must not mutate a replacement registration;
- native callback context must outlive in-flight callbacks and be released
  exactly once;
- correctness loss must not be hidden behind telemetry-only evidence;
- one noisy source should not starve unrelated roots.

These statements do not select a mailbox, slot pool, source gate, repair ledger,
or shutdown state machine. A future bounded-admission design must re-evaluate
them against current code and measured workloads.

## Future Boundary

Bounded Darwin admission remains post-cleanup work. A future spec may define:

- how flags and event IDs are captured;
- which discontinuities require authoritative rescan;
- callback memory/service limits and overload behavior;
- registration replacement and shutdown currentness;
- how admitted observations enter `FilesystemActor` without unbounded task or
  stream growth;
- proof that the new path preserves the production scan scheduler and source
  authorization boundaries.

This document intentionally defines no replacement API, detailed state machine,
capacity value, or migration path.

## Compatibility Boundary

Future filesystem work must not broaden cleanup into persistence or terminal
repair:

- SQLite remains strict current-schema state with no cleanup-specific migration,
  startup repair, or legacy composition fallback.
- Existing nonblank `ZmxSessionID` values remain opaque and are restored exactly
  as stored; no filesystem path or registration may derive or rewrite them.

## Proof Before Reactivation

Any future replacement must prove the live production path, including Darwin
client lifecycle, `FilesystemActor` integration, scheduler concurrency/fairness,
stale-result rejection, final inventory correctness, build, lint, and runtime
interaction under watched pressure. Old fixed-slot tests or compiler fixtures do
not satisfy that proof.
