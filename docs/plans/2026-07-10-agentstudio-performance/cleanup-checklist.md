# AgentStudio Performance Branch Cleanup Checklist

## Purpose

Remove the unreachable fixed-revision persistence, dormant mutation, and
filesystem-admission architectures without losing the production-reachable
performance and correctness work on `ghostty-performance`.

This checklist is deletion-first. It does not implement incremental-row
persistence, a new EventBus, a replacement mailbox, or new Ghostty scheduling.
Those resume only after the cleaned application builds, launches, restores, and
persists correctly.

Research source:
`tmp/research-workflows/2026-07-17-performance-branch-cleanup/research-ledger.md`

Recovery anchor: `ff5984da`

## Non-negotiable boundaries

- [x] Work on a cleanup branch created from `ff5984da`; do not reset, rebase,
      squash, or rewrite the existing branch.
- [ ] Never touch the user-owned untracked `.agents/` directory.
- [ ] Keep atoms limited to current state, simple accepted assignments, local
      indexes, equality suppression, and pure derivation.
- [ ] Do not add persistence revisions, leases, participants, paging,
      historical preimages, transaction planning, I/O, or orchestration to
      atoms.
- [ ] Do not introduce startup repair, ZMX identity inference, path-derived
      identity, compatibility shims, or legacy workspace-composition fallback.
- [ ] Do not implement the eventual incremental-row persistence replacement
      during cleanup.
- [ ] Preserve existing IDs exactly; new durable IDs continue to use UUIDv7.
- [ ] Commit only after the checkpoint's focused proof, build, lint, and diff
      checks pass.

## Keep fence

The following behavior must survive every checkpoint:

- [ ] Production `WatchedFolderScanScheduler` with bounded concurrency,
      same-root coalescing, FIFO fairness, and current-generation result checks.
- [ ] Source-authorized filesystem roots and volume-aware canonicalization.
- [ ] Bounded Git discovery/status timeout used by watched-folder scanning.
- [ ] Strict SQLite current-schema loading and ordered datastore saves.
- [ ] Off-main exhaustive workspace-composition validation.
- [ ] Opaque `ZmxSessionID`, UUIDv7 generation for new sessions, and exact
      restoration of stored nonblank identities.
- [ ] Bounded visible-first terminal and nonterminal content mounting.
- [ ] Topology-free prepared Bridge mounting.
- [ ] Repository/worktree/tab/arrangement keyed indexes and equal-write
      suppression.
- [ ] Duplicate repository/worktree identity rejection and the consumed-ID
      invariant preventing duplicate live worktree UUIDs.
- [ ] Atom-persistence architecture enforcement.

## Execution DAG

```text
gate 0: create cleanup branch and re-anchor ff5984da
  |
  v
C1: lean initial composition installation
  |
  v
C2: remove dormant semantic mutation families
  |
  v
C3: remove revision/pager/participant runtime
  |
  v
C4: prune atom support and restore topology boundary
  |
  v
C5: remove dormant admission/observation/repair/diagnostics
  |
  v
C6: reconcile tests, lint, specs, plans, and workflow state
  |
  v
C7: full build/test + isolated debug app + SQLite restore/save proof
```

The sequence is intentionally serial. C1 must replace the only live use of the
persistence runtime before C3 deletes it. Atom helpers cannot be safely pruned
until C2 and C3 remove their callers.

## Gate 0 — Branch and baseline

- [x] Confirm `git status --short` contains only `.agents/` and the untracked
      reopen draft.
- [x] Record `git rev-parse HEAD`; expected recovery anchor is `ff5984da`.
- [x] Create `ghostty-performance-cleanup` from that exact commit.
- [x] Delete the untracked
      `WorkspaceReopenFinalPaneAndRestoreTabTransition.swift` draft.
- [x] Confirm `.agents/` is unchanged.
- [ ] Record baseline focused build/test failures, if any, without repairing
      unrelated infrastructure.

Checkpoint proof:

- [ ] `git diff --check`
- [ ] branch and HEAD recorded in the cleanup receipt

## C1 — Lean initial composition installation

### Preserve

- [ ] `WorkspaceCompositionPreparer` and its off-main strict validation.
- [ ] Prepared pane/tab/drawer projections and terminal/nonterminal mount input.
- [ ] One bounded MainActor installation of already-validated composition.
- [ ] Strict load failure with zero partial atom installation.

### Rework

- [ ] Replace `WorkspacePreparedCompositionApplier` adapter/revision application
      with a lean initial installer holding the exact canonical atom owners.
- [ ] Replace `WorkspaceContentMountGeneration` persistence revision/process
      generation with a standalone composition-generation token.
- [ ] Keep composition generation separate from topology readiness and
      persistence acknowledgement.
- [ ] Make `WorkspaceStore.loadCanonicalComposition()` use the lean installer.
- [ ] Keep `WorkspaceSQLiteSaveCoordinator` strict validation and datastore
      save behavior without importing revision/participant result types.
- [ ] Simplify prepared terminal descriptors so each value has one
      authoritative representation.

### Remove from boot/store

- [ ] `WorkspacePersistenceRuntimeBootState`.
- [ ] `AppDelegate.workspacePersistenceRuntimeBootState`.
- [ ] `AppDelegate.workspacePersistenceRuntime`.
- [ ] `AppDelegate.installWorkspacePersistenceRuntime`.
- [ ] Runtime construction in `AppDelegate+WorkspaceBoot`.
- [ ] Runtime constructor parameters and identity checks in `WorkspaceStore`.
- [ ] Preview-only runtime construction in `CustomTabBar` and `DrawerPanel`.

Focused proof:

- [ ] Composition-preparer tests pass.
- [ ] Lean installer tests prove one complete installation and zero partial
      mutation on rejection.
- [ ] Strict SQLite startup tests pass.
- [ ] Terminal/nonterminal prepared cohort tests pass.
- [ ] `mise run build` passes.
- [ ] `mise run lint` passes.
- [ ] `git diff --check` passes.
- [ ] Commit C1.

Split/replan trigger: stop if the lean installer requires persistence revision,
lease, or participant concepts to express initial state installation.

## C2 — Delete dormant semantic mutation families

Delete each production source and its matching transition/applier/gateway tests.
Do not retain a generic compatibility wrapper.

- [ ] Window-memory persistence mutation methods.
- [ ] `WorkspacePaneTransition` pane title/context/webview family.
- [ ] New-pane/new-tab transition and `WorkspacePaneCreationGateway` family.
- [ ] `WorkspaceTabLeafTransition` family.
- [ ] `WorkspaceDrawerToggleTransition` family.
- [ ] `WorkspaceTabGraphLeafTransition` family.
- [ ] `WorkspaceActiveArrangementVisibilityTransition` family.
- [ ] `WorkspaceKeyboardResizeCheckpointPlanner` family.
- [ ] Pane-residency lifecycle planners, applier, owner, and gateway.
- [ ] Arrangement-selection transition/applier/gateway.
- [ ] Layout-resize transition/applier/checkpoint owner/gateway.
- [ ] Arrangement create/remove transition/applier/gateway.
- [ ] Create-pane-in-existing-tab transition/applier/gateway.
- [ ] Cross-tab pane-move transition/applier/gateway.
- [ ] Retained-tab pane-close transition/applier/gateway.
- [ ] Final-pane tab-removal transition/applier/gateway.
- [ ] `WorkspacePersistenceMutationCoordinator` after all family fields and
      callers are gone.
- [ ] `LatestValueSettleGate` after its final dormant consumer is gone.

Required zero-reference scan:

- [ ] `WorkspacePersistenceMutationCoordinator`
- [ ] `WorkspacePaneCreationGateway`
- [ ] `WorkspacePaneResidencyLifecycleOwner`
- [ ] every deleted transition/applier/gateway symbol

Focused proof:

- [ ] Existing production pane/tab/drawer action tests pass.
- [ ] Existing undo/close behavior tests pass through the real production path.
- [ ] UUIDv7 creation tests for live pane/ZMX/layout paths pass.
- [ ] `mise run build` passes.
- [ ] `mise run lint` passes.
- [ ] `git diff --check` passes.
- [ ] Commit C2.

## C3 — Delete fixed-revision persistence architecture

### Revision, journal, and adapter ownership

- [ ] Delete `WorkspacePersistenceRevisionOwner.swift`.
- [ ] Delete `WorkspacePersistenceChangeJournal.swift`.
- [ ] Delete `WorkspacePersistenceAdapterBundle.swift`.
- [ ] Delete `WorkspacePersistenceRuntime.swift`.
- [ ] Delete all files under
      `Persistence/SnapshotParticipants/` introduced for live-atom paging.
- [ ] Delete `WorkspacePreparedTopologyApplier.swift`.
- [ ] Delete `WorkspaceTopologyPreparation.swift` if no non-paging caller
      remains.

### Lease, pager, and assembly

- [ ] Delete `WorkspaceStateSnapshotLease.swift`.
- [ ] Delete `WorkspaceStateSnapshotLeaseContracts.swift`.
- [ ] Delete `WorkspaceStateSnapshotPager.swift`.
- [ ] Delete `WorkspaceStateSnapshotPagerContracts.swift`.
- [ ] Delete `WorkspaceStateSnapshotPagerItemValidation.swift`.
- [ ] Delete `WorkspaceStateSnapshotPageCaptureEngine.swift`.
- [ ] Delete `WorkspaceStateSnapshotPageCaptureRequest.swift`.
- [ ] Delete `WorkspaceStateSnapshotParticipantPreparationCustody.swift`.
- [ ] Delete `WorkspaceStateSnapshotPreparedMutationPlanner.swift`.
- [ ] Delete `WorkspacePersistenceSnapshotItem.swift`.
- [ ] Delete `WorkspacePersistenceSnapshotAssembler.swift`.
- [ ] Delete `WorkspacePersistenceSnapshotFinalizer.swift`.
- [ ] Delete `WorkspacePersistenceSnapshotValidation.swift`.
- [ ] Delete `WorkspacePersistenceSnapshotPageAccumulator.swift`.
- [ ] Delete `WorkspacePersistenceSnapshotParticipantFactory.swift`.
- [ ] Delete snapshot key/byte/page constants from `AppPolicies` while retaining
      unrelated autosave damping policy.

### Tests

- [ ] Delete revision-owner tests.
- [ ] Delete lease/pager/page-capture tests and support.
- [ ] Delete participant/adaptor/capture-only tests.
- [ ] Delete journal/assembly/finalizer tests.
- [ ] Delete runtime installation tests tied only to removed ownership.

Required zero-reference scan:

- [ ] `WorkspacePersistenceRuntime`
- [ ] `WorkspacePersistenceRevisionOwner`
- [ ] `WorkspacePersistenceProcessGeneration`
- [ ] `WorkspaceStateSnapshot`
- [ ] `SnapshotParticipant`
- [ ] `capturePersistencePreimages`
- [ ] `WorkspacePersistenceChangeJournal`

Focused proof:

- [ ] Workspace autosave tests pass through `WorkspaceSQLiteSaveCoordinator`.
- [ ] SQLite save ordering tests pass.
- [ ] Flush/termination persistence tests pass.
- [ ] `mise run build` passes.
- [ ] `mise run lint` passes.
- [ ] `git diff --check` passes.
- [ ] Commit C3.

## C4 — Restore atom and topology boundaries

### Atom pruning

- [ ] Remove atom mutation helpers whose last caller was a deleted applier.
- [ ] Keep keyed entity/reverse indexes used by real UI, coordinators, derived
      readers, SQLite projection, or startup installation.
- [ ] Keep equal-write suppression and index maintenance.
- [ ] Confirm no atom imports or names persistence revision, lease, pager,
      participant, transaction, SQLite, repository I/O, or preparation custody.

### `RepositoryTopologyAtom`

- [ ] Move worktree reconciliation planning outside the atom.
- [ ] Move repository/worktree UUID generation outside the atom.
- [ ] Move performance trace recording outside the atom.
- [ ] Move topology validation/preparation types outside the atom folder.
- [ ] Leave the atom with accepted state replacement, keyed lookup, index
      maintenance, equal-write suppression, and pure derivation.
- [ ] Preserve consumed-existing-ID uniqueness.
- [ ] Preserve duplicate repo/worktree/watched-path rejection before assignment.
- [ ] Preserve the production duplicate-worktree crash regression test.

Focused proof:

- [ ] Atom persistence-boundary architecture test passes.
- [ ] Topology identity/reconciliation tests pass.
- [ ] Duplicate-worktree live-state regression passes.
- [ ] Keyed lookup and owner-index tests pass.
- [ ] `mise run build` passes.
- [ ] `mise run lint` passes.
- [ ] `git diff --check` passes.
- [ ] Commit C4.

## C5 — Delete dormant admission and diagnostic systems

### Generic admission

- [ ] Delete unused `Admission/Admission*` types.
- [ ] Delete unused `BoundedGatherMailbox*`.
- [ ] Delete unused `LatestValueMailbox.swift`.
- [ ] Delete unused `OrderedFactJournal*`.
- [ ] Delete unused `AdmissionDoorbell.swift` if no live consumer remains.

### Fixed-slot filesystem observation

- [ ] Delete dormant Darwin observation adapter and native-owner files.
- [ ] Delete `FSEventRegistrationControlBlock.swift`.
- [ ] Delete `FilesystemObservationMailbox*`.
- [ ] Delete `FilesystemObservationSlot*`.
- [ ] Delete filesystem lease-transfer and semantic-replay files.
- [ ] Delete filesystem fleet/shutdown/retirement files.
- [ ] Delete `FilesystemSourceGate*` and recovery evidence register.
- [ ] Keep production `DarwinFSEventStreamClient` temporarily unchanged; its
      eventual bounded replacement is post-cleanup work.

### Dormant repair and diagnostics

- [ ] Delete `WorktreeContentRepairConsumerRegistry*`.
- [ ] Delete `FilesystemContentRepairProjector*`.
- [ ] Delete unconstructed `MainActorResponsivenessHeartbeat`.
- [ ] Delete `PerformanceProbeSink`.
- [ ] Delete `PerformanceRunEvidenceLedger`.
- [ ] Delete `MainActorWorkLedger` after pager removal unless a real production
      producer is found.
- [ ] Remove OTLP metric vocabulary that has no remaining producer.

### Tests and lint

- [ ] Delete compiler fixtures and tests whose only subject was removed
      admission/type-state architecture.
- [ ] Delete filesystem observation lifecycle tests for removed code.
- [ ] Delete dormant repair and diagnostic tests.
- [ ] Delete SwiftSyntax rules enforcing only removed journal/slot/native-owner
      structures.
- [ ] Keep generic AtomLib and pure-atom architecture rules.

Focused proof:

- [ ] Production watched-folder scheduler tests pass.
- [ ] Production Darwin FSEvent client tests pass.
- [ ] Filesystem/Git pipeline integration tests pass.
- [ ] Architecture-lint inventory and parity tests pass.
- [ ] `mise run build` passes.
- [ ] `mise run lint` passes.
- [ ] `git diff --check` passes.
- [ ] Commit C5.

## C6 — Correct durable contracts

- [ ] Update the performance spec to remove global atom-persistence revisions,
      live-atom paging, participant adapters, and historical preimage custody.
- [ ] State the retained persistence direction: semantic changed-row/table
      transactions owned by persistence, with atoms remaining current state.
- [ ] Replace W4.5p in the watched-folder plan with this cleanup boundary and a
      later incremental-row persistence task.
- [ ] Correct implementation-plan DAG and proof matrix.
- [ ] Supersede, do not rewrite, historical workflow events for removed
      checkpoints.
- [ ] Replace the active resume pointer with post-cleanup production work:
      bounded Darwin admission, persistent root index, semantic EventBus,
      Ghostty action contraction, and live MainActor measurement.
- [ ] Update architecture docs only where current source ownership changed.
- [ ] Record the supported SQLite/ZMX compatibility floor without adding repair.

Proof:

- [ ] Documentation links resolve.
- [ ] No current contract requires deleted symbols or architecture.
- [ ] `mise run lint` passes.
- [ ] `git diff --check` passes.
- [ ] Commit C6.

## C7 — Full cleanup proof

### Static and automated

- [ ] `mise run build`
- [ ] focused atom/topology tests
- [ ] focused strict SQLite/startup tests
- [ ] focused prepared content-mount tests
- [ ] focused watched-folder scheduler tests
- [ ] focused filesystem/Git integration tests
- [ ] `mise run test-fast`
- [ ] `mise run test-large`
- [ ] `mise run test-webkit`
- [ ] `mise run test`
- [ ] `mise run lint`
- [ ] `git diff --check`

### Real app

- [ ] `mise run observability:up`
- [ ] Launch through `mise run run-debug-observability -- --detach`.
- [ ] Verify the exact PID through `mise run verify-debug-observability`.
- [ ] Verify strict SQLite restore without composition repair or identity writes.
- [ ] Verify prepared terminal/nonterminal cohort settlement.
- [ ] Verify terminal attachment uses the exact stored ZMX identity.
- [ ] Make one ordinary persisted UI change, flush, relaunch, and verify it.
- [ ] Add a watched folder and verify the retained scan scheduler completes.
- [ ] Stop the exact debug PID through the repo verifier/stop command.

### Review and integration

- [ ] Run one implementation-review swarm over the cleanup diff.
- [ ] Remediate accepted findings once.
- [ ] Re-run affected proof plus full build/lint.
- [ ] Confirm the cleanup branch contains no unrelated `.agents/` content.
- [ ] Merge normally; do not squash or rewrite history.

## Completion definition

Cleanup is complete only when:

- [ ] Every DELETE item is absent with zero references.
- [ ] Every KEEP-fence behavior is present and proven.
- [ ] Atoms contain no persistence/orchestration workflow.
- [ ] Startup no longer constructs `WorkspacePersistenceRuntime`.
- [ ] Production SQLite load/save and terminal restoration pass in the real app.
- [ ] The branch compiles, all required test layers pass, and lint is clean.
- [ ] Specs/plans describe the cleaned architecture rather than deleted code.
- [ ] The next implementation checkpoint is a real production performance
      boundary, not another dormant framework.
