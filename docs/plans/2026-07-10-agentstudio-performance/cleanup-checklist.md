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

- [x] `WorkspaceCompositionPreparer` and its off-main strict validation.
- [x] Prepared pane/tab/drawer projections and terminal/nonterminal mount input.
- [x] One bounded MainActor installation of already-validated composition.
- [x] Strict load failure with zero partial atom installation.

### Rework

- [x] Replace `WorkspacePreparedCompositionApplier` adapter/revision application
      with a lean initial installer holding the exact canonical atom owners.
- [x] Replace `WorkspaceContentMountGeneration` persistence revision/process
      generation with a standalone composition-generation token.
- [x] Keep composition generation separate from topology readiness and
      persistence acknowledgement.
- [x] Make `WorkspaceStore.loadCanonicalComposition()` use the lean installer.
- [x] Keep `WorkspaceSQLiteSaveCoordinator` strict validation and datastore
      save behavior without importing revision/participant result types.
- [x] Simplify prepared terminal descriptors so each value has one
      authoritative representation.

### Remove from boot/store

- [x] `WorkspacePersistenceRuntimeBootState`.
- [x] `AppDelegate.workspacePersistenceRuntimeBootState`.
- [x] `AppDelegate.workspacePersistenceRuntime`.
- [x] `AppDelegate.installWorkspacePersistenceRuntime`.
- [x] Runtime construction in `AppDelegate+WorkspaceBoot`.
- [x] Runtime constructor parameters and identity checks in `WorkspaceStore`.
- [x] Preview-only runtime construction in `CustomTabBar` and `DrawerPanel`.

Focused proof:

- [x] Composition-preparer tests pass.
- [x] Lean installer tests prove one complete installation and zero partial
      mutation on rejection.
- [x] Strict SQLite startup tests pass.
- [x] Terminal/nonterminal prepared cohort tests pass.
- [x] `mise run build` passes.
- [x] `mise run lint` passes.
- [x] `git diff --check` passes.
- [x] Commit C1.

Split/replan trigger: stop if the lean installer requires persistence revision,
lease, or participant concepts to express initial state installation.

## C2 — Delete dormant semantic mutation families

Delete each production source and its matching transition/applier/gateway tests.
Do not retain a generic compatibility wrapper.

- [x] Window-memory persistence mutation methods.
- [x] `WorkspacePaneTransition` pane title/context/webview family.
- [x] New-pane/new-tab transition and `WorkspacePaneCreationGateway` family.
- [x] `WorkspaceTabLeafTransition` family.
- [x] `WorkspaceDrawerToggleTransition` family.
- [x] `WorkspaceTabGraphLeafTransition` family.
- [x] `WorkspaceActiveArrangementVisibilityTransition` family.
- [x] `WorkspaceKeyboardResizeCheckpointPlanner` family.
- [x] Pane-residency lifecycle planners, applier, owner, and gateway.
- [x] Arrangement-selection transition/applier/gateway.
- [x] Layout-resize transition/applier/checkpoint owner/gateway.
- [x] Arrangement create/remove transition/applier/gateway.
- [x] Create-pane-in-existing-tab transition/applier/gateway.
- [x] Cross-tab pane-move transition/applier/gateway.
- [x] Retained-tab pane-close transition/applier/gateway.
- [x] Final-pane tab-removal transition/applier/gateway.
- [x] `WorkspacePersistenceMutationCoordinator` after all family fields and
      callers are gone.
- [x] `LatestValueSettleGate` after its final dormant consumer is gone.

Required zero-reference scan:

- [x] `WorkspacePersistenceMutationCoordinator`
- [x] `WorkspacePaneCreationGateway`
- [x] `WorkspacePaneResidencyLifecycleOwner`
- [x] every deleted transition/applier/gateway symbol

Focused proof:

- [x] Existing production pane/tab/drawer action tests pass.
- [x] Existing undo/close behavior tests pass through the real production path.
- [x] UUIDv7 creation tests for live pane/ZMX/layout paths pass.
- [x] `mise run build` passes.
- [x] `mise run lint` passes.
- [x] `git diff --check` passes.
- [x] Commit C2.

## C3 — Delete fixed-revision persistence architecture

### Revision, journal, and adapter ownership

- [x] Delete `WorkspacePersistenceRevisionOwner.swift`.
- [x] Delete `WorkspacePersistenceChangeJournal.swift`.
- [x] Delete `WorkspacePersistenceAdapterBundle.swift`.
- [x] Delete `WorkspacePersistenceRuntime.swift`.
- [x] Delete all files under
      `Persistence/SnapshotParticipants/` introduced for live-atom paging.
- [x] Delete `WorkspacePreparedTopologyApplier.swift`.
- [x] Delete `WorkspaceTopologyPreparation.swift` if no non-paging caller
      remains.

### Lease, pager, and assembly

- [x] Delete `WorkspaceStateSnapshotLease.swift`.
- [x] Delete `WorkspaceStateSnapshotLeaseContracts.swift`.
- [x] Delete `WorkspaceStateSnapshotPager.swift`.
- [x] Delete `WorkspaceStateSnapshotPagerContracts.swift`.
- [x] Delete `WorkspaceStateSnapshotPagerItemValidation.swift`.
- [x] Delete `WorkspaceStateSnapshotPageCaptureEngine.swift`.
- [x] Delete `WorkspaceStateSnapshotPageCaptureRequest.swift`.
- [x] Delete `WorkspaceStateSnapshotParticipantPreparationCustody.swift`.
- [x] Delete `WorkspaceStateSnapshotPreparedMutationPlanner.swift`.
- [x] Delete `WorkspacePersistenceSnapshotItem.swift`.
- [x] Delete `WorkspacePersistenceSnapshotAssembler.swift`.
- [x] Delete `WorkspacePersistenceSnapshotFinalizer.swift`.
- [x] Delete `WorkspacePersistenceSnapshotValidation.swift`.
- [x] Delete `WorkspacePersistenceSnapshotPageAccumulator.swift`.
- [x] Delete `WorkspacePersistenceSnapshotParticipantFactory.swift`.
- [x] Delete snapshot key/byte/page constants from `AppPolicies` while retaining
      unrelated autosave damping policy.

### Tests

- [x] Delete revision-owner tests.
- [x] Delete lease/pager/page-capture tests and support.
- [x] Delete participant/adaptor/capture-only tests.
- [x] Delete journal/assembly/finalizer tests.
- [x] Delete runtime installation tests tied only to removed ownership.

Required zero-reference scan:

- [x] `WorkspacePersistenceRuntime`
- [x] `WorkspacePersistenceRevisionOwner`
- [x] `WorkspacePersistenceProcessGeneration`
- [x] `WorkspaceStateSnapshot`
- [x] `SnapshotParticipant`
- [x] `capturePersistencePreimages`
- [x] `WorkspacePersistenceChangeJournal`

Focused proof:

- [x] Workspace autosave tests pass through `WorkspaceSQLiteSaveCoordinator`.
- [x] SQLite save ordering tests pass.
- [x] Flush/termination persistence tests pass.
- [x] `mise run build` passes.
- [x] `mise run lint` passes.
- [x] `git diff --check` passes.
- [x] Commit C3.

## C4 — Restore atom and topology boundaries

### Atom pruning

- [x] Remove atom mutation helpers whose last caller was a deleted applier.
- [x] Keep keyed entity/reverse indexes used by real UI, coordinators, derived
      readers, SQLite projection, or startup installation.
- [x] Keep equal-write suppression and index maintenance.
- [x] Confirm no atom imports or names persistence revision, lease, pager,
      participant, transaction, SQLite, repository I/O, or preparation custody.

### `RepositoryTopologyAtom`

- [x] Move worktree reconciliation planning outside the atom.
- [x] Move repository/worktree UUID generation outside the atom.
- [x] Move performance trace recording outside the atom.
- [x] Move topology validation/preparation types outside the atom folder.
- [x] Leave the atom with accepted state replacement, keyed lookup, index
      maintenance, equal-write suppression, and pure derivation.
- [x] Preserve consumed-existing-ID uniqueness.
- [x] Preserve duplicate repo/worktree/watched-path rejection before assignment.
- [x] Preserve the production duplicate-worktree crash regression test.

Focused proof:

- [x] Atom persistence-boundary architecture test passes.
- [x] Topology identity/reconciliation tests pass.
- [x] Duplicate-worktree live-state regression passes.
- [x] Keyed lookup and owner-index tests pass.
- [x] `mise run build` passes.
- [x] `mise run lint` passes.
- [x] `git diff --check` passes.
- [x] Commit C4.

## C5 — Delete dormant admission and diagnostic systems

### Generic admission

- [x] Delete unused `Admission/Admission*` types.
- [x] Delete unused `BoundedGatherMailbox*`.
- [x] Delete unused `LatestValueMailbox.swift`.
- [x] Delete unused `OrderedFactJournal*`.
- [x] Delete unused `AdmissionDoorbell.swift` if no live consumer remains.

### Fixed-slot filesystem observation

- [x] Delete dormant Darwin observation adapter and native-owner files.
- [x] Delete `FSEventRegistrationControlBlock.swift`.
- [x] Delete `FilesystemObservationMailbox*`.
- [x] Delete `FilesystemObservationSlot*`.
- [x] Delete filesystem lease-transfer and semantic-replay files.
- [x] Delete filesystem fleet/shutdown/retirement files.
- [x] Delete `FilesystemSourceGate*` and recovery evidence register.
- [x] Keep production `DarwinFSEventStreamClient` temporarily unchanged; its
      eventual bounded replacement is post-cleanup work.

### Dormant repair and diagnostics

- [x] Delete `WorktreeContentRepairConsumerRegistry*`.
- [x] Delete `FilesystemContentRepairProjector*`.
- [x] Delete unconstructed `MainActorResponsivenessHeartbeat`.
- [x] Delete `PerformanceProbeSink`.
- [x] Delete `PerformanceRunEvidenceLedger`.
- [x] Delete `MainActorWorkLedger` after pager removal unless a real production
      producer is found.
- [x] Remove OTLP metric vocabulary that has no remaining producer.

### Tests and lint

- [x] Delete compiler fixtures and tests whose only subject was removed
      admission/type-state architecture.
- [x] Delete filesystem observation lifecycle tests for removed code.
- [x] Delete dormant repair and diagnostic tests.
- [x] Delete SwiftSyntax rules enforcing only removed journal/slot/native-owner
      structures.
- [x] Keep generic AtomLib and pure-atom architecture rules.

Focused proof:

- [x] Production watched-folder scheduler tests pass.
- [x] Production Darwin FSEvent client tests pass.
- [x] Filesystem/Git pipeline integration tests pass.
- [x] Architecture-lint inventory and parity tests pass.
- [x] `mise run build` passes.
- [x] `mise run lint` passes.
- [x] `git diff --check` passes.
- [x] Commit C5.

## C6 — Correct durable contracts

- [x] Update the performance spec to remove global atom-persistence revisions,
      live-atom paging, participant adapters, and historical preimage custody.
- [x] State the retained persistence direction: semantic changed-row/table
      transactions owned by persistence, with atoms remaining current state.
- [x] Replace W4.5p in the watched-folder plan with this cleanup boundary and a
      later incremental-row persistence task.
- [x] Correct implementation-plan DAG and proof matrix.
- [x] Supersede, do not rewrite, historical workflow events for removed
      checkpoints.
- [x] Replace the active resume pointer with post-cleanup production work:
      bounded Darwin admission, persistent root index, semantic EventBus,
      Ghostty action contraction, and live MainActor measurement.
- [x] Update architecture docs only where current source ownership changed.
- [x] Record the supported SQLite/ZMX compatibility floor without adding repair.

Proof:

- [x] Documentation links resolve.
- [x] No current contract requires deleted symbols or architecture.
- [x] `mise run lint` passes.
- [x] `git diff --check` passes.
- [x] Commit C6.

## C7 — Full cleanup proof

### Static and automated

- [x] `mise run build`
- [x] focused atom/topology tests
- [x] focused strict SQLite/startup tests
- [x] focused prepared content-mount tests
- [x] focused watched-folder scheduler tests
- [x] focused filesystem/Git integration tests
- [ ] `mise run test-fast`
- [ ] `mise run test-large`
- [x] `mise run test-webkit`
- [ ] `mise run test`
- [x] `mise run lint`
- [x] `git diff --check`

### Real app

- [x] `mise run observability:up`
- [x] Launch through `mise run run-debug-observability -- --detach`.
- [x] Verify the exact PID through `mise run verify-debug-observability`.
- [x] Verify strict SQLite restore without composition repair or identity writes.
- [ ] Verify prepared terminal/nonterminal cohort settlement.
- [x] Verify terminal attachment uses the exact stored ZMX identity.
- [x] Make one ordinary persisted UI change, flush, relaunch, and verify it.
- [x] Add a watched folder and verify the retained scan scheduler completes.
- [x] Stop the exact debug PID without affecting other debug or stable processes.

### Review and integration

- [x] Run one implementation-review swarm over the cleanup diff.
- [x] Remediate accepted findings once.
- [x] Re-run affected proof plus full build/lint.
- [x] Confirm the cleanup branch contains no unrelated `.agents/` content.
- [ ] Stop at a reviewed clean baseline; do not merge from this cleanup goal.

### C7 proof receipt — 2026-07-17

- Build passed at `1bf73194`.
- Lint passed with zero SwiftLint violations across 1,376 files; architecture
  lint and release checks also passed.
- The focused startup, topology, strict SQLite, content-mount, Bridge boundary,
  and terminal-scheduler selection passed 86 tests across 17 reported suites.
- `WatchedFolderScanScheduler` passed 21 tests across two suites.
- `FilesystemGitPipelineIntegrationTests` passed four tests.
- `mise run test-webkit` passed 61 tests across all nine selected suites.
- `mise run test-fast` ran 4,371 tests across 549 suites and reported 17
  issues. The exact remaining failure set is still being classified against the
  recovery anchor; this gate remains open.
- `mise run test-large` ran 259 tests across 42 suites and reported one stale
  fixture missing the required stored `zmxSessionID`; this gate remains open.
- Full `mise run test` ran 4,659 tests across 592 suites and reported 19
  issues; this gate remains open.
- The isolated debug app passed marker-scoped Victoria startup verification,
  IPC terminal readiness, and a real terminal command completion with exit code
  zero. A persisted sidebar mutation survived relaunch. The same stored pane ID
  and exact opaque ZMX identity reattached to the original zmx process.
- Real watched-folder runtime completion and the single cleanup review cycle
  remained open at this receipt. No performance frontier was authorized by it.
- The single cleanup review cycle completed and accepted two atom-boundary
  findings. Remediation deleted `PaneFilesystemProjectionAtom`, retained
  `FilesystemProjectionIndex` as the off-main projection owner, made
  `AttendedPaneDerived` a pure synchronous read, and moved observation/stream
  lifecycle into `PaneFocusTracker`. It introduced no replacement actor,
  mailbox, framework, protocol, or durable state.
- Parent remediation proof passed 95 attended-pane/inbox/terminal-activity
  tests and 20 filesystem/index/coordinator/E2E/atom-architecture tests.
  `mise run build`, `mise run lint`, and `git diff --check` passed. The only
  untracked path remains the user-owned `.agents/` directory.
- Real watched-folder runtime completion and the pre-existing broad-suite
  failures remained open at the review-remediation checkpoint. Performance
  implementation was still unauthorized.
- Real watched-folder proof then completed against isolated debug PID `63181`
  and marker `debug-observability-yjy1-watch-1784320713`. The background UI
  path added `/Users/shravansunder/Documents/dev/open-source`; strict SQLite
  contained one watched path, 100 repositories, and 106 worktrees. Victoria
  recorded 118 Git status completions, a maximum pending count of 102, final
  pending count zero, and four bounded running slots. Three status reads reached
  their explicit one-second timeout. Across 94 coordinator-write records the
  maximum MainActor apply was 0.063 ms; maximum total coordinator time was
  189.957 ms. The exact debug PID was terminated afterward; stable AgentStudio
  and other worktree debug processes were untouched.
- The timeout and coordinator distributions are baseline evidence for a later
  narrow performance spec. They do not authorize implementation during cleanup.

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
