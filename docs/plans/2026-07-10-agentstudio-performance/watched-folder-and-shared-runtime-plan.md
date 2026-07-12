# Watched-Folder Admission And Shared Runtime Implementation Plan

Parent plan: [AgentStudio Performance Boundaries Implementation Plan](implementation-plan.md)

Source contract: `docs/specs/2026-07-09-watched-folder-admission-mainactor-fairness/watched-folder-admission-mainactor-fairness.md`

## 1. Outcome

Implement WF1–WF10, WS1–WS9, FI1–FI7, TA1–TA11, EV1–EV12, BR1–BR6, NR1, and PF1–PF9 using the owners selected by the accepted spec. A huge watched folder may increase background work, but it must not expand into unbounded callback allocation, false topology removal, fleet-sized MainActor computation, competing persistence writers, global filesystem-to-Git fanout, or blocking Bridge refresh work.

The final path is:

```text
Darwin callback
  -> bounded generation-bearing observation + exact repair debt
  -> fair scan/root/content owners
  -> immutable topology/Git/Bridge projections off-main
  -> one typed changed-key MainActor apply
  -> revisioned downstream effects and sole persistence coordinator
  -> semantic facts only where a named product consumer exists
```

## 2. Existing Owners To Preserve Or Replace

| Current owner | Planned disposition |
| --- | --- |
| `DarwinFSEventStreamClient` | retain vendor boundary; replace unbounded/unversioned capture with control block, observation, and mailbox |
| `FilesystemActor` | retain domain actor; remove callback backlog, scan-loop, per-batch root rebuild, and global FS→Git responsibilities |
| `RepoScanner` | retain traversal provider; return exhaustive completion/validation result rather than absence-capable best effort |
| `FilesystemRootOwnership` | replace hot-path root scan with persistent immutable `FilesystemRootIndexSnapshot` |
| `FilesystemProjectionIndex` | preserve as pane/worktree projection owner |
| `WorkspaceCacheCoordinator` | stop receiving all global topics and stop building topology on MainActor; consume typed accepted effects only where still needed |
| `RepositoryTopologyAtom` and pane/tab atoms | preserve canonical MainActor ownership; expose keyed typed apply/change-set seams |
| `WorkspaceSQLiteSaveCoordinator`, `RepositoryTopologyStore`, `WorkspaceStore` write paths | hard-cut to one `WorkspacePersistenceCoordinator` |
| `WorkspaceSQLiteDatastore` | preserve actor/SQLite I/O ownership; add revision rejection and change-set/checkpoint APIs |
| `GitWorkingDirectoryProjector` | preserve status/coalescing compute; replace global FS event subscription with internal `WorktreeGitInvalidationMailbox` |
| `BridgePaneController`/review pipeline | preserve Bridge ownership; introduce bounded invalidation/currentness owner; do not perform deep render redesign |

## 3. Task W1 — FSEvent Observation And Callback Lifetime

Requirements: WF1–WF3, WF6–WF8.

### W1a — Observation and callback control-block types

Add these dormant types and focused tests before callback integration:

- `Sources/AgentStudio/Core/RuntimeEventSystem/Filesystem/FSEventRegistrationControlBlock.swift`
- `Sources/AgentStudio/Core/RuntimeEventSystem/Filesystem/FilesystemSourceTypes.swift`
  - Normative `FilesystemSourceKind`, `FilesystemSourceID`, `FSEventRegistrationToken`, `FSEventRecord`, `FSEventObservation`, `FSEventFlagDisposition`, and `WatchRoot` types.

W1a does not invent a temporary repair owner and does not yet switch the Darwin callback.

Execution clarification discovered at the W1a RED seam:

- The normative observation uses closed `FSEventRecordCount`,
  `FSEventIDWatermark`, and `FSEventCaptureCompleteness` states rather than
  correlated optional IDs and a truncation Boolean. Its validating constructor
  owns the copied-count/record-count/byte-count invariants.
- `FSEventCaptureLimits` has four independent positive hard bounds: inspected
  native records, copied records, copied UTF-8 bytes, and maximum single-path
  UTF-8 bytes. No downstream 128/256 envelope constant is reused here.
- `FSEventFlagDisposition` is a joining typed product so ordinary hints,
  continuity repair, root revalidation, provenance, and unknown-bit evidence
  can coexist.
- W1a's dormant control block owns a closed lifecycle and generation-bound
  callback leases, but no optional or temporary mailbox. W2a supplies the
  required synchronous producer/recovery capability; W1b composes it into the
  live retained callback userdata.
- W1a tests cover value invariants and lifecycle/lease transitions. Native
  array inspection and exact flag classification remain W1b callback-adapter
  proof because W1a does not cut production ingress.

### W1b — Dormant real callback adapter after W2a

Depends on W2a's real `FilesystemObservationMailbox`, recovery-evidence
register, `FilesystemSourceGate`, and exact per-registration recovery custody.
Modify:

- `Sources/AgentStudio/Core/RuntimeEventSystem/Filesystem/FSEventStreamClient.swift`
  - Replace `FSEventBatch` as the callback contract with `FSEventObservation`.
  - Carry `registrationID`, `AdmissionGeneration`, monotonic capture time, unioned flags, first/last event-ID watermarks, copied-record count/bytes, total event count, truncation, and source kind.
  - Keep `FSEventStreamClient` protocol methods generation-bearing.
- `Sources/AgentStudio/Core/RuntimeEventSystem/Filesystem/DarwinFSEventStreamClient.swift`
  - Replace `CallbackContext`/unretained teardown with a retained `FSEventRegistrationControlBlock`.
  - Enforce distinct inspected-native-record, copied-record, copied-byte, and
    maximum-single-path-byte limits before materializing any complete Swift path array.
  - Acquire a callback lease before touching registration state.
  - Join bounded flag/truncation evidence into the W2a recovery-evidence
    register before the observation can be contracted; capacity overflow adds
    callback-admission-overflow evidence before signaling the doorbell.
  - Teardown sequence: mark closing, seal the old mailbox generation,
    stop/invalidate stream, execute callback-queue barrier, drain callback
    leases, transfer/disposition exact recovery evidence into `FilesystemSourceGate`,
    invalidate the old mailbox generation, then release context.

Do not call an actor, schedule one task per path, access MainActor state, scan, canonicalize every path, or clear repair state in the callback.

W1b prepares the production callback adapter and proves the real Darwin lifecycle in an isolated assembly, but does not switch production `FilesystemActor` ingress. Production keeps the complete legacy callback/source path until W2b atomically installs the callback adapter, source gate, mailbox drain, and the exact live repair-participant set. W3–W10 develop against the W2a fake/isolated ingress seam. There is no accepted product checkpoint where real registered-worktree repair debt can be captured before its mandatory participants exist.

### Test proof

Create/modify:

- `Tests/AgentStudioTests/Core/PaneRuntime/Sources/DarwinFSEventStreamClientTests.swift`
- `Tests/AgentStudioTests/Helpers/ControllableFSEventStreamClient.swift`
- new `Tests/AgentStudioTests/Core/PaneRuntime/Sources/DarwinFSEventObservationAdmissionTests.swift`
- new `Tests/AgentStudioTests/Core/PaneRuntime/Sources/FSEventRegistrationControlBlockTests.swift`

Boundary/seam: C callback capture and registration close.

Invariants: bounded capture; all discontinuity flags survive; N never becomes
N+1; closing rejects callbacks without a valid lease; a leased callback either
enters the sealed old generation or installs conservative old-generation debt;
userdata and the declared key remain alive until callback lease drain and
repair-authority transfer.

Illegal-state/guards: exhaustive flag disposition, explicit open/closing/closed state, item/byte cap before allocation, generation match on lease.

Valid/invalid IO: ordinary create/rename/delete, must-scan, user/kernel drop, wrapped IDs, root change, unknown flags, nil/malformed counts, oversized batch, unregister/re-register, callback-close race.

Independent oracle: literal flag/observation table and control-block counters, not production classification.

RED/GREEN: required. RED must demonstrate lost flag/ID/truncation or unbounded
copied records in the current seam. GREEN includes a real temporary Darwin
stream lifecycle integration in which an oversized/discontinuous callback
installs debt in the actual W2a source gate before returning; a deterministic
replacement race acquires an old callback lease, seals/replaces the registration,
installs loss, crosses the callback barrier, and proves debt survives transfer
without becoming N+1. The fake client remains unit proof. A structural pre-W2b
test proves production callback/source composition is still wholly legacy.

Split/replan trigger: queue barrier plus leases cannot establish teardown quiescence on the supported Darwin callback model.

## 4. Task W2 — Source Gate, Observation Mailbox, And Repair Registry

Requirements: WF2–WF5, WF9–WF10.

### W2a — Gate/mailbox/registry mechanics

Add:

- `Sources/AgentStudio/Core/RuntimeEventSystem/Filesystem/FilesystemObservationMailbox.swift`
  - Domain wrapper over value-only `BoundedGatherMailbox` with a short wrapper
    lock coupling generic custody to a fixed-size monotonic
    `FilesystemRecoveryEvidenceRegister`.
  - Key by source/registration generation.
  - Retain opaque bounded `FSEventObservation` values and checked footprints;
    perform no path/flag merge, dedupe, normalization, routing, or repair join
    under generic mailbox state.
  - Enforce calibrated retained pending-plus-leased contribution/item/byte
    limits globally and per source, plus distinct one-key lease quanta.
  - Register exact monotonic continuity/root-identity/truncation/overflow/
    unsupported-flag evidence before a recovery revision becomes visible.
  - Expose capability-separated callback producer/signaler and actor consumer/
    waiter ports; only lifecycle composition can finish the doorbell.
  - Lease one source key at a time. Cancellation/rebind re-presents identical
    custody with a new binding token; retry stays ahead of newer same-key work
    but rotates behind already-ready unrelated keys.
  - Reject unknown keys without trapping. Lease, rather than destructively
    remove, captured recovery state until `FilesystemActor` transfers it into
    `FilesystemSourceGate`; newer evidence/revision survives an older ack.
- `Sources/AgentStudio/Core/RuntimeEventSystem/Filesystem/FilesystemSourceGate.swift`
  - Exact states: `healthy`, `dirty`, `reconciling`, `reconcilingAndDirty`, `awaitingAcknowledgements`, `repairFailed`, `shuttingDown`.
  - Own `RepairGeneration`, current registration, scan state, and acknowledgement set.
- `Sources/AgentStudio/Core/RuntimeEventSystem/Filesystem/WorktreeContentRepairConsumerRegistry.swift`
  - Generation-bearing participant registration.
  - Captured participant set per repair generation.
  - Exhaustive unregister/replacement transfer, late-registration currentness, acknowledgement, retry, and shutdown behavior.
- `Sources/AgentStudio/Core/RuntimeEventSystem/Filesystem/FilesystemContentRepairProjector.swift`
  - Convert coarse registered-worktree repair into bounded consumer-specific rebuild requests; never fabricate a full file inventory.

Prepare `FilesystemActor.startIngressTaskIfNeeded` and `ingestRawPaths` as the
sole mailbox drain loop in the isolated W1b/W2a assembly. The actor owns equality
dedupe, flag/reason reduction, routing, latest/OR/count aggregation, subtree/root
collapse, debounce, and the post-transfer semantic fair-root queue. The generic
mailbox alone owns the mechanical unique ready-key queue used for one-key lease
selection and retry rotation. W2b installs that drain in production. At most one
wake is pending and one lease is outstanding. The configured
`maximumAttendedPriorityBurst = P` and actor-owned round-robin semantic
ready-root queue must satisfy the spec's `(R + 1) * (P + 1)` root-turn bound.
`FilesystemSourceGate` owns semantic repair/currentness only; it does not wait on
the doorbell or drain/acknowledge generic custody.

The initial registered-worktree repair participant matrix is fixed before implementation:

| Participant | Applicability | Successful receipt | Non-success disposition |
| --- | --- | --- | --- |
| pane/filesystem projection owner (`FilesystemProjectionIndex` plus `PaneFilesystemProjectionAtom` apply) | mandatory for a registered worktree generation | `rebuiltCurrent(repairGeneration, projectionRevision)` | `markedNonCurrent(retry:)`; withdrawal transfers retained retry to the registry |
| `GitWorkingDirectoryProjector` | mandatory | `rebuiltCurrent(repairGeneration, gitSnapshotGeneration)` after a full snapshot commit | `markedNonCurrent(retry:)`; unregister/replacement rejects stale completion |
| live `BridgeRefreshCoordinator` state | conditional when retained Bridge content references the worktree | `rebuiltCurrent(repairGeneration, bridgeRefreshGeneration)` only after native currentness apply | `markedNonCurrent(retry:)` or typed `notApplicable`; pane close transfers/withdraws explicitly |
| later content consumer | not applicable until it registers a typed generation token before presenting current content | same typed current/non-current/not-applicable receipt vocabulary | absence from UI is never acknowledgement |

The W2a protocol-level registry test table owns applicability, captured participant generation, success receipt, `markedNonCurrent(retry:)`, `notApplicable`, withdrawal/transfer, and independent currentness oracle for every row. The executor may discover additional current consumers, but may not redefine these baseline participants or receipt semantics.

### W2b — Atomic production admission and participant cut after W10

Depends on W5's pane/filesystem projection owner, W9's Git mailbox/projector integration, and W10's generation-bearing Bridge owner. In one production composition cut, wire the pane/filesystem projection, Git projector, and applicable Bridge refresh owners into the registry; install the W1b callback adapter and W2a source gate/mailbox drain; then run the full participant matrix. W3–W10 may depend on W2a mechanics and isolated ingress; W12 repair-health acceptance depends on W2b. No source may return to `healthy` before W2b records the exact matching disposition for every captured participant. Pre-cut production is wholly legacy; post-cut production has the complete captured participant set and no callback path bypasses the gate.

### Test proof

Add:

- `FilesystemObservationMailboxTests.swift`
- `FilesystemSourceGateTests.swift`
- `FilesystemRepairRegistryTests.swift`
- `RegisteredWorktreeRepairIntegrationTests.swift`

Extend `FilesystemActorTests.swift`.

Invariants: ordinary pressure contracts only the affected source after exact
recovery custody exists; native joined evidence survives payload contraction;
starting/completing scan does not clear repair; every captured current
participant acknowledges the same generation; disappearing UI state cannot
acknowledge; replacement transfers or explicitly withdraws retained authority.
N→N+1→N+2 retains at most one transferring mailbox, one sealed/current-slot
mailbox, and one newest not-yet-authoritative desired identity. Configuration
receipts give every requested source an exhaustive installed/unchanged/removed/
deferred/capacity/create/start disposition and explicit current/non-current
retry state.

Oracle: independent participant/repair ledger and final source-state model.

RED/GREEN: required for overflow without recovery, mixed loss/root evidence
under contraction, pending-plus-leased bound-plus-one, one noisy/299 quiet root
fairness, cancellation/rebind/late-old-ack, N→N+1→N+2 replacement, partial
configuration/start failure, Git-only acknowledgement, unregister/replacement,
and late/stale acknowledgement.

W2a completion proves mechanics only. W2b is the production repair/admission gate and tests visible, background, closed, replaced, failed, and not-applicable Bridge states against an independent captured-participant ledger. Its integration proof injects oversized/drop input through the real production callback composition, captures the exact live participant generations, and reaches `healthy` only after every matching receipt.

## 5. Task W3 — Fair Scan Scheduler And Exhaustive Scanner Results

Requirements: WS1–WS9.

### Production changes

Add:

- `Sources/AgentStudio/Core/RuntimeEventSystem/Filesystem/WatchedFolderScanScheduler.swift`
  - One running scan per watched folder.
  - Running-plus-newest-dirty collapse.
  - One immediate follow-up maximum.
  - Explicit global concurrency and oldest-ready/fair scheduling.
- `Sources/AgentStudio/Core/RuntimeEventSystem/Filesystem/WatchedFolderScanResult.swift`
  - Normative `WatchedFolderScanRequest`, `WatchedFolderScanTrigger`, `ScanCompletionClass`, `ScanFailureReason`, `ScanResultCounts`, and `WatchedFolderScanResult`.
  - `ScanCompletionClass` is exactly `completeAuthoritative`, `partial`, `unavailable`, `cancelled`, or `failed`; detailed traversal/validation/permission/root reasons remain exhaustive in `failures` and counts.
  - Counts: directories, candidates, validation success/negative/timeout/cancel/failure, queue wait, service, stale drops, follow-ups.

Modify:

- `Sources/AgentStudio/Core/RuntimeEventSystem/Filesystem/FilesystemActor.swift`
  - Replace `handleWatchedFolderFSEvent`, `rescanAllWatchedFolders`, `refreshWatchedFolder`, and `startFallbackRescan` ownership with scheduler submission/drain.
  - Initial, callback, manual, fallback, and repair triggers use the same scheduler.
- `Sources/AgentStudio/Infrastructure/RepoScanner.swift`
  - Replace `try?` suppression that converts traversal/metadata errors into absence-capable results.
  - Return the exhaustive `WatchedFolderScanResult` with authoritative negative distinct from failure.

Only `completeAuthoritative` for the same current root generation may produce removal candidates. Partial results may add verified positives and must retain dirty/repair state.

### Test proof

Create/modify:

- `WatchedFolderScanSchedulerTests.swift`
- `RepoScannerCompletenessTests.swift`
- `FilesystemActorWatchedFolderTests.swift`
- `FilesystemActorShellGitIntegrationTests.swift`
- `WatchedFolderScanRecoveryIntegrationTests.swift`

Use real temporary filesystem/Git fixtures for the integration layer. Cases: permission denial, unreadable child, validation timeout/failure, cancellation, missing/replaced root, malformed `.git`, symlink loop, hot/cold folder fairness, trigger during running scan.

Independent oracle: literal generated directory/repository manifest. Do not derive expected absence from scanner output.

RED/GREEN: required for false removal caused by suppressed traversal/validation error and for starvation/running-plus-dirty behavior.

Split trigger: the validation provider cannot distinguish authoritative negative from timeout/failure.

## 6. Task W4 — Persistent Root Index And Batched Source Configuration

Requirements: FI1–FI7.

### Production changes

Add:

- `Sources/AgentStudio/Core/RuntimeEventSystem/Filesystem/FilesystemRootIndexSnapshot.swift`
  - Immutable, generation-bearing path-component index with deepest canonical match.
  - Build from user-authorized canonical roots when topology changes.
- `Sources/AgentStudio/Core/RuntimeEventSystem/Filesystem/FilesystemSourceConfiguration.swift`
  - Normative `FilesystemSourceConfigurationBatch` and `FilesystemSourceConfigurationReceipt` for one typed register/unregister/activity/filter change.
  - Canonicalize roots once; preserve lexical/resolved forms only as the accepted security policy permits.
- `Sources/AgentStudio/Core/RuntimeEventSystem/Filesystem/FilesystemPathCanonicalizer.swift`
  - Source-verified volume/case/Unicode/component policy shared by `RegisteredRootDescriptor` construction and lookup.

Modify:

- `FilesystemRootOwnership.swift` to become construction/compatibility support or remove it after all call sites use `FilesystemRootIndexSnapshot`.
- `FilesystemActor` to install one configuration/root-index generation and route observations against that snapshot.
- `FilesystemPathFilter.swift` call order so ownership resolution precedes ignore/policy classification and deduplication.

Do not resolve symlinks per event by default. Raw/relative/`..`/case-varied/stale paths cannot select a different worktree by string prefix. Git metadata outside the authorized root may inform identity but cannot register a watcher.

### Test proof

Extend:

- `FilesystemRootOwnershipTests.swift`
- `FilesystemPathFilterTests.swift`
- `FilesystemProjectionIndexTests.swift`

Add `FilesystemRootIndexGenerationTests.swift` and `FilesystemOwnershipSecurityTests.swift`.

Oracle: independent canonical fixture table across nested roots, sibling-prefix collisions, `..`, symlinks, case variants, outside-root Git metadata, root replacement, unavailable/non-local root.

Performance proof: fixed path query count across 10/100/300 roots must not execute a linear scan of all roots per path; record index build separately from lookup.

Expose an internal test diagnostic or injected comparison recorder at the `FilesystemRootIndexSnapshot` public test seam. The independent property oracle asserts lookup component/comparison work is bounded by canonical path depth/index structure and does not grow with registered-root count across 10/100/300 indexes. Elapsed time remains diagnostic only.

RED/GREEN: required for generation, authority, and complexity behavior.

## 6.5. Task W4.5 — Canonical Revision Owner And Fixed-Revision Page Lease

Requirements: TA1, TA9–TA11 and the normative mirror-bootstrap contract. This contract must exist before W5; it performs no datastore write and does not create a second persistence writer.

### W4.5a — Sole canonical persistence revision authority

Add `Sources/AgentStudio/Core/State/MainActor/Persistence/WorkspacePersistenceRevisionOwner.swift` as the one process-generation-scoped allocator for persistence-affecting canonical transactions. Modify `Sources/AgentStudio/AtomRegistry.swift` and `Sources/AgentStudio/Core/State/MainActor/Persistence/WorkspaceStore.swift` to inject the same owner into outer canonical mutation owners. Persisted atoms/facades participate in the fixed-revision pager but never mint revisions autonomously: the outer transaction allocates exactly one revision, passes it into every participating keyed mutation, and commits one causally complete change set only after the transaction succeeds. A rejected or failed transaction advances no revision. Defaults may not construct an alternate owner. Existing writers continue unchanged until W7, but they do not mint a competing revision.

### W4.5b — Fixed-revision raw page lease participation

Add `WorkspaceStateSnapshotLease.swift` and `WorkspaceStateSnapshotPager.swift`. Modify the persisted keyed owners/facades:

- `WorkspaceIdentityAtom.swift`
- `WorkspaceWindowMemoryAtom.swift`
- `RepositoryTopologyAtom.swift`
- `WorkspacePaneGraphAtom.swift` and `WorkspaceDrawerCursorAtom.swift`
- `WorkspaceTabShellAtom.swift`, `WorkspaceTabCursorAtom.swift`, `WorkspaceTabGraphAtom.swift`, and `WorkspaceArrangementCursorAtom.swift`
- `WorkspacePaneAtom.swift`/`WorkspaceTabLayoutAtom.swift` only as compatibility façades

Each owner exposes fixed-revision base membership/raw page reads and accepts an outer-transaction revision for keyed changes; it retains at most the first post-base value/tombstone for a changed key. MainActor page capture is bounded raw reading only and has one synchronous `MainActorWorkLedger` record. It performs no normalization/join/filter/serialization and never spans `await`.

### W4.5c — Lease stability and update-journal fixture proof

Add `WorkspacePersistenceRevisionOwnerTests.swift`, `WorkspaceStateSnapshotLeaseTests.swift`, `WorkspacePersistencePageCaptureTests.swift`, and a test-only contiguous update-journal fixture. Retain emitted pages while mutating the same/new/removed keys; prove no moving-state reread or fleet COW detachment. Assert one revision-owner object identity across `AtomRegistry`, `WorkspaceStore`, and every outer transaction owner. Prove a multi-atom canonical transaction advances exactly once, passes the same revision to every keyed mutation, and a failed transaction advances zero times. Inventory proof compares page participants with `WorkspaceSQLiteSnapshot`, `RepositoryTopologySQLiteSnapshot`, and repository persistence records; transient zoom/presentation state is a required negative case. No temporary revision owner or full fleet snapshot is permitted.

## 7. Task W5 — Off-Main Topology Projection And One MainActor Apply

Requirements: TA1–TA10, FI5.

This task is split into two independently provable subtasks.

### W5a — Mirror and projector

Depends explicitly on completed W4.5 revision/lease/pager APIs.

Add:

- `Sources/AgentStudio/Core/RuntimeEventSystem/Filesystem/WorkspaceTopologyProjectionMirror.swift`
  - Off-main immutable mirror bootstrapped/recovered from revisioned pages.
- `Sources/AgentStudio/Core/RuntimeEventSystem/Filesystem/FilesystemTopologyProjector.swift`
  - Resolve identities, joins, worktree reconciliation, removals, pane/cache patches, and downstream effects off-main.

W5a modifies no atom. It proves mirror bootstrap/contiguous update/gap recovery, field ownership, identity joins, stale scan rejection, and literal topology diff output against an independent model.

The W5a integration test uses the real `WorkspaceTopologyProjectionMirror`, W4.5 pager/lease, and contiguous `TopologyProjectionUpdate` stream. It proves pre-source-admission bootstrap, post-base replay, missing-update gap rejection, and bounded rebootstrap; W4.5's test journal fixture is not this proof.

### W5b — MainActor applier and effect record

Add:

- `Sources/AgentStudio/App/Coordination/WorkspaceTopologyApplier.swift`
  - Sole MainActor `MainActorMutationApplier<TopologyApplyBatch>`.
  - Validate source generation and canonical base revision.
  - Allocate one canonical/persistence revision, pass it into every field-scoped keyed patch, and apply the whole batch in one transaction.
  - Publish the accepted revision only after every participating mutation succeeds; rejection/failure publishes nothing and advances no revision.
  - Return `TopologyApplyReceipt`/accepted effect record.
- `Sources/AgentStudio/Core/State/MainActor/Atoms/WatchedFolderCurrentnessAtom.swift`
  - Runtime-only currentness keyed by watched-path identity, with exactly `discovering`, `current`, `repairing(lastKnownRevision:)`, `nonCurrentRetrying(lastKnownRevision:)`, `repairFailed(lastKnownRevision:)`, and `unavailable(lastKnownRevision:)`.

Modify:

- `WorkspaceCacheCoordinator.swift` to stop performing topology joins/mutations from broad bus delivery.
- `RepositoryTopologyAtom.swift`, `WorkspacePaneGraphAtom.swift`, and relevant cache atoms to expose small keyed batch mutation internals used only by `WorkspaceTopologyApplier`.
- `WorkspaceSurfaceCoordinator+FilesystemSource.swift` to capture one compact source snapshot, invoke projector, apply one batch, then dispatch accepted effects.
- `FilesystemProjectionIndex.swift` only where the accepted effect/currentness API changes; preserve its filtering/index ownership.
- `AtomRegistry.swift`, `Features/RepoExplorer/Models/RepoExplorerSnapshot.swift`, `Features/RepoExplorer/Models/RepoExplorerProjection.swift`, and `Features/RepoExplorer/RepoExplorerView.swift` to expose and visibly distinguish watched-root currentness without deriving it in `body`.

`TopologyApplyBatch` contains field-scoped patches, exhaustive watched-root currentness transitions, and cache/orphan/reassociation effects. It never carries a fleet replacement. MainActor apply performs no path, regex, JSON, scan, Git, Bridge package, persistence normalization, or same-bus repost work. Last-known topology remains usable, but the Repo Explorer read model must not render `repairing`, `nonCurrentRetrying`, `repairFailed`, or `unavailable` indistinguishably from `current`.

Every accepted canonical transaction creates exactly one normative compact `TopologyProjectionUpdate` and one causally complete `WorkspacePersistenceChangeSet` carrying that same revision; atoms never allocate their own revisions. The mirror advances only across contiguous accepted revisions. A gap marks it non-current and reboots through the versioned pager plus post-base update journal.

Instrument the apply with `MainActorWorkLedger`; include input/changed-key count and revision, and no `await` inside the span. W5b has its own RED/GREEN for atomic stale-base rejection, pane/cache/orphan effects, observation/trace contraction, and fixed-changed-key scaling; W5a proof is not a substitute.

### Test proof

Add:

- `FilesystemTopologyProjectorTests.swift`
- `WorkspaceTopologyApplierTests.swift`
- `WorkspaceTopologyApplyScalingTests.swift`
- `WatchedFolderCurrentnessAtomTests.swift`

Extend:

- `WorkspaceCacheCoordinatorTests.swift`
- `WorkspaceCacheCoordinatorIntegrationTests.swift`
- `RepositoryTopologyAtomTests.swift`
- `TopologyEventPipelineIntegrationTests.swift`
- pane boundary/reassociation tests
- `FilesystemProjectionIndexTests.swift`
- `RepoExplorerReadModelTests.swift` and `RepoExplorerViewTests.swift` for visible currentness states

Invariants: stale base has no partial mutation or revision advance; one multi-atom apply advances the revision owner exactly once; every participating atom receives the same accepted revision; discovery-owned and user-owned fields merge only per spec; cache cleanup and orphaning are atomic with topology; at most one observation invalidation and trace refresh; accepted effect record exhaustively names source/Git/projection/Forge/persistence/trace/repair follow-ups and watched-root currentness. A non-current root retains last-known state but has a distinguishable Repo Explorer presentation.

Oracle: independent literal topology/pane/cache map. For 10/100/300 fleets with the same changed keys, MainActor service must remain within the calibrated fixed-change envelope.

RED/GREEN: required, including `unavailable`/repair-failure transitions that retain last-known topology while changing the canonical currentness read model and visible Repo Explorer presentation. Split if a merge conflict cannot be resolved off-main; reject/reproject rather than broadening MainActor logic.

## 8. Task W6 — Semantic Fact Endpoints And Cutover-Ready Scheduling

Requirements: EV1–EV11.

Depends on shared `RuntimeFactBus` task S2.

### Cutover-ready endpoint construction

Map filesystem topology/change and accepted downstream product facts to exhaustive `RuntimeDomainFact` endpoints. Configure the target subscribers with nonempty topics, explicit delivery, replay, attribution, pressure signal, and recovery. Preserve `EventBus` as transport only. Focused tests instantiate this target assembly; production global wiring stays completely legacy until IG1.

Modify:

- Prepare `FilesystemActor.swift` product fact publication.
- Prepare `WorkspaceCacheCoordinator.swift` topic subscriptions.
- Prepare `WorkspaceSurfaceCoordinator.swift` runtime fact consumer composition.
- Prepare removal of filesystem handling from `NotificationReducer`; typed projectors/schedulers/appliers own this path.
- Reserve all production wiring and runtime-envelope removal for IG1.

An internal pipeline uses a targeted call/mailbox unless a global fact has a named product consumer. Same-global-bus derivation must have a named contraction budget.

### Test proof

Add:

- `Tests/AgentStudioTests/Core/PaneRuntime/Events/FilesystemRuntimeFactEndpointTests.swift`
- `Tests/AgentStudioTests/App/Coordination/FilesystemRuntimeFactConsumerInventoryTests.swift`
- `Tests/AgentStudioTests/Architecture/FilesystemRuntimeFactCutoverArchitectureTests.swift`

Extend fact-bus and coordinator runtime-dispatch tests. The independent inventory fixture enumerates fact, topic, named consumer, replay/recovery, expected rate, pressure strategy, and legacy deletion gate; it does not call production topic mapping to derive expected values.

RED/GREEN: current legacy posts and ignored-topic deliveries form RED in the isolated target assembly. GREEN proves filtering before per-subscriber admission/accounting, no generic MainActor reducer, and no raw observation/path replay. A pre-IG1 structural test also proves the production composition has not wired a second fact bus; IG1 owns the atomic switch.

## 9. Task W7 — Sole Persistence Revision Owner And Writer

Requirements: TA10–TA11 and normative persistence contract.

This task is an ordered hard-cut sequence rather than one broad checkpoint.

### W7a — Datastore writer inventory and request classification

Inventory every mutating `WorkspaceSQLiteDatastore` API and production caller. The initial required caller list is:

- `WorkspaceSQLiteSaveCoordinator.swift`
- `RepositoryTopologyStore.swift`
- `WorkspaceStore.swift` and `WorkspaceStore+LegacySQLiteImport.swift`
- `RepoCacheStore.swift`
- `UIStateStore.swift`
- `SidebarCacheStore.swift`
- `Features/InboxNotification/State/MainActor/Persistence/InboxNotificationSQLiteDatastoreAdapter.swift`
- `App/Boot/WorkspaceLegacyArchiveCoordinator.swift`
- active workspace selection, import/archive status, and any other call found by the source inventory

Classify each write as canonical revisioned change, checkpoint/import, local coalesced autosave, or operational status. `WorkspacePersistenceCoordinator` is the sole product caller for all four classes; only canonical workspace mutations consume the canonical persistence revision stream. Read-only restore/status queries remain direct only when the inventory table explicitly marks them read-only.

The W7a architecture test compares the live caller/API inventory with the checked table and fails on an unclassified or direct writer.

### W7b — Revision/change-set protocol

Add:

- `Sources/AgentStudio/Core/State/SQLite/WorkspacePersistenceCoordinator.swift`
  - Off-main actor and sole product caller of the datastore write APIs.
  - Own queue/drain, retry/acknowledgement, per-lane ordering/idempotency, and checkpoint barriers for revisioned change sets, local mutations, and checkpoints.
  - Accept only bounded `Sendable` requests captured by MainActor mutation owners; return compact receipts for MainActor apply.
- `Sources/AgentStudio/Core/State/SQLite/WorkspacePersistenceChangeSet.swift`
  - Keyed changes, tombstones, previous/new revisions, process generation.
  - `WorkspacePersistenceCompactedRange` keyed by final entity state.
- `Sources/AgentStudio/Core/State/SQLite/WorkspaceLocalPersistenceMutation.swift`
  - `WorkspaceLocalPersistenceLane`, closed/architecture-inventoried `WorkspaceLocalPersistenceMutation` protocol, affected repository/table family, retry-safety contract, and opaque `WorkspaceLocalPersistenceRequest` carrying workspace/process generation plus per-lane sequence/idempotency metadata.
- `Sources/AgentStudio/Features/InboxNotification/State/Persistence/InboxNotificationPersistenceMutation.swift`
  - feature-owned conformance/payload replacing the adapter's direct `performLocalSaveOperation` closure.

Features such as Inbox implement their mutation payload/operation in the feature directory; Core never imports an Inbox type. Conformances are closed by a checked architecture inventory and must declare lane, affected repository/table family, idempotency key, sequence, and retry safety. Mutation payloads store no closure and no repository/database handle escapes to feature code; the datastore invokes only inventoried typed conformances. `WorkspacePersistenceCoordinator` owns admission, per-lane FIFO/idempotency/retry, checkpoint barriers for the same local database, and the only `performLocalSaveOperation` call. Local/operational lanes do not consume the canonical entity revision stream, but they do pass through coordinator admission and cannot supply an unclassified arbitrary datastore closure.

`WorkspacePersistenceRevisionOwner` remains the small MainActor transaction authority from W4.5. The coordinator is not MainActor-isolated: revision allocation, bounded request/page capture, and compact receipt apply are the only MainActor persistence seams. Architecture proof rejects `@MainActor` queue/drain/retry/checkpoint arbitration or fleet preparation in the coordinator.

### W7c — Prepare every writer's cutover-ready typed request endpoint

Prepare modifications for all W7a callers and exercise them through isolated cutover assemblies:

- `RepositoryTopologyStore.observeTopology/schedulePersist/persistNow` to request through the coordinator or remove the independent write observer.
- `WorkspaceStore` full-save entry to request a checkpoint through the coordinator.
- `WorkspaceSQLiteSaveCoordinator` to be replaced/absorbed; it must no longer build an ordinary full bundle on MainActor.
- canonical atom/coordinator mutations to emit revisioned changed-key records.
- `WorkspaceSQLiteDatastore.swift`, `WorkspaceSQLiteDatastoreTypes.swift`, and `Core/State/MainActor/Persistence/WorkspaceSQLiteStoreBackend.swift` to accept/reject coordinator-owned typed writes atomically through existing repository mutations.

Operational import/archive/status and local-feature requests enter the same arbiter but do not pretend to be canonical entity revisions. Their ordering and failure receipts remain typed and are covered by the sole-caller inventory.

W7b/W7c do not change production construction or caller selection. Before W7d, every production write remains on the one complete legacy path and the new coordinator assembly is reachable only from focused tests. There is no feature flag, dual publication, or piecemeal caller migration.

### W7d — Atomic sole-writer cut

Depends on W8a–W8c proving checkpoint compaction/commit/starvation over the W4.5 pager. In one production integration diff, drain/cancel old scheduled saves, fence their process generation, switch every W7a caller to its W7c typed request endpoint, install `WorkspacePersistenceCoordinator`, remove/absorb `WorkspaceSQLiteSaveCoordinator` and every direct write path, and only then enable the direct-writer architecture rule. No intermediate product state has two writers, and the sole-writer cut cannot land before checkpoint recovery is operational.

No SQLite migration/schema redesign is authorized. A stale full/checkpoint write must be rejected before replacement.

### Test proof

Add:

- extend the W4.5 `WorkspacePersistenceRevisionOwnerTests.swift`
- `WorkspacePersistenceCoordinatorTests.swift`
- `WorkspacePersistenceCompactedRangeTests.swift`
- `WorkspaceRevisionedPersistenceIntegrationTests.swift`

Extend:

- `WorkspaceSQLiteCommitProtocolTests.swift`
- `WorkspaceSQLiteDatastoreActorTests.swift`
- `WorkspaceSQLiteDatastoreBoundaryTests.swift`
- `PersistenceChaosTests.swift`
- `WorkspacePersistenceTransformerTests.swift`

Cases: stale checkpoint after newer change set, revision gap, process-generation mismatch, repeated same-key change, create/remove net-zero, tombstone until acknowledgement, core/local failure and retry, cancellation/shutdown.

Independent oracle: query/reload SQLite through fresh repository/datastore read APIs and compare with a literal final entity map.

RED/GREEN: required for stale full-save overwrite, competing writer paths, and an unregistered/arbitrary feature mutation. Structural proof shows exactly one legacy production writer before W7d and exactly one coordinator production writer after W7d; the hard cut cannot land with two writers. A bad architecture fixture proves closure-backed, repository-handle-bearing, undeclared-table-family, or non-inventoried feature mutations are rejected.

## 10. Task W8 — Checkpoint Compaction, Commit, And Starvation Recovery

Requirements: TA11 checkpoint contract.

This task is split into three proof-sized subtasks.

W8 consumes the revision owner and pager already proven in W4.5. Before implementation it revalidates the exact persisted-owner inventory against `WorkspaceSQLiteSnapshot` and repository topology; another owner requires extending W4.5 participation rather than reading a moving fleet facade.

### W8a — Compacted post-base range

The revision owner opens a fixed base-revision lease. Concurrent mutations enter a contiguous `WorkspacePersistenceCompactedRange` bounded by unique final-state keys. A running checkpoint does not restart under mutation.

### W8b — Off-main checkpoint construction and coordinator/datastore commit

MainActor captures the W4.5 bounded raw keyed pages only; off-main code normalizes/encodes. After base commit, the coordinator applies the contiguous compacted range and acknowledges tombstones.

Modify `WorkspacePersistenceTransformer.swift` so ordinary writes no longer call `makeLiveSQLiteSnapshotResult` over the fleet. Keep full transform only behind boot/import/export/checkpoint paging where required.

### W8c — Starvation and retained-page memory proof

### Test proof

Add:

- `WorkspacePersistencePageCaptureTests.swift`
- `WorkspaceStateSnapshotLeaseTests.swift`
- `WorkspaceCheckpointStarvationTests.swift`

Retain emitted pages while mutating the same atoms to expose hidden fleet COW detachment. Run count-driven sustained mutation; prove checkpoint completion and retained memory bound by page plus unique final-state keys, not mutation count.

RED/GREEN: required. Replan if this cannot be achieved without retaining a fleet-sized COW snapshot.

## 11. Task W9 — Internal Filesystem-To-Git Invalidation

Requirements: EV12, FI4.

### Production changes

Add `Sources/AgentStudio/Core/RuntimeEventSystem/Git/WorktreeGitInvalidationMailbox.swift`, an accumulated newest-context per-worktree internal channel with bounded keys, one wake, retry/currentness, and diagnostics.

Modify:

- `FilesystemGitPipeline.swift` to wire the mailbox directly.
- `GitWorkingDirectoryProjector.swift` to remove `handleIncomingRuntimeEnvelope` and consume mailbox drains.
- `FilesystemActor` to offer owned worktree invalidations after safe ownership/filter/dedup.
- Git publication to emit only deduplicated `gitState` facts.

### Test proof

Add `WorktreeGitInvalidationMailboxTests.swift` and `FilesystemGitInvalidationIntegrationTests.swift`; repair `GitWorkingDirectoryProjectorTests.swift` and `FilesystemGitPipelineIntegrationTests.swift`.

Oracle: status-provider call ledger plus literal deduplicated snapshot transitions. Burst while compute runs must yield newest accumulated follow-up, max concurrency remains bounded, ignored/Git-only cases retain semantics, and global intermediate post count is zero.

RED/GREEN: legacy FS→global envelope→Git integration is RED; direct mailbox is GREEN.

## 12. Task W10 — Bounded Bridge Filesystem Refresh And Currentness

Requirements: BR1–BR6 and parent Bridge boundary.

### Production changes

Add:

- `Sources/AgentStudio/Features/Bridge/Models/ReviewFoundation/BridgeFilesystemRefreshRequest.swift`
- `Sources/AgentStudio/Features/Bridge/Runtime/ReviewFoundation/BridgeRefreshInputProvider.swift`
- `Sources/AgentStudio/Features/Bridge/Runtime/ReviewFoundation/BridgeRefreshCoordinator.swift`
- `Sources/AgentStudio/Features/Bridge/State/BridgeCurrentnessPresentationState.swift`
- `Sources/AgentStudio/Features/Bridge/State/Push/BridgeFilesystemRefreshPacket.swift`
  - typed generation/revision metadata plus the final already-encoded envelope string; no package object or raw source handle.
- `Sources/AgentStudio/Features/Bridge/State/Push/BridgeFilesystemRefreshPacketBuilder.swift`
  - pure off-main packet builder; it owns no WebKit call, delivery task, or publication scheduling.
- a native currentness overlay in `Features/Bridge/Views/` using existing design tokens.

Modify:

- `WorkspaceSurfaceCoordinator+FilesystemSource.swift`/fact consumer to offer one bounded generation-bearing invalidation and return.
- `BridgePaneController+DiffCommands.swift` (`handlePaneFilesystemContextEvent`) to delegate to the refresh coordinator.
- Bridge review source/provider/pipeline to build immutable input and package/delta off-main.
- Add one `PushPlan.publishPreparedFilesystemRefresh(packet:matchingStateMutation:)` seam on the existing push delivery owner. Off-main code builds the final typed JSON envelope exactly once. In one bounded MainActor critical section, the push owner validates pane/package/refresh revision, commits the matching Bridge state mutation, and registers that prepared packet as the sole publication for the exact revision. Its existing send loop performs the generation-checked WebKit call.

The existing `PushPlan` owner is the only publication scheduler. The refresh coordinator never calls WebKit and never owns a send task. For the exact committed revision, ordinary `Slice`/`EntitySlice` derivation observes the registered prepared publication and does not derive a second generic push. A stale/mismatched packet is rejected before state commit and cannot suppress a later unrelated push; a WebKit failure remains retryable by the same push owner without losing the committed currentness state. Do not overload generic `PushTransport`/`pushJSON` with optional filesystem provenance and do not silently move every Bridge push into this scope.

The request contains pane/repo/worktree generation, source/package revision, bounded changed IDs or coarse rebuild reason, and provider handle. It never contains a package-sized MainActor copy.

Native `refreshing`/`retrying`/`failed-last-known` currentness must apply before repair acknowledgement. JS apply/React commit is not canonical repair acknowledgement.

Instrument the bounded MainActor immutable-input capture and the generation-checked WebKit send as two distinct synchronous `MainActorWorkLedger` operations. Neither span crosses package build, JSON envelope construction, an `await`, JavaScript apply, or React commit.

### Test proof

Add:

- `BridgeRefreshCoordinatorTests.swift`
- `BridgeCurrentnessPresentationStateTests.swift`
- `BridgeRefreshMainActorContainmentTests.swift`

Extend:

- `WorkspaceSurfaceCoordinatorBridgeFilesystemRefreshTests.swift`
- `BridgePaneControllerTests.swift`
- `BridgeReviewPipelineTests.swift`
- `BridgeReviewPackageBuilderTests.swift`
- `PushPipelineIntegrationTests.swift`

Cases: overlap, running+dirty, stale completion, provider failure/retry, pane close, WebKit failure, visible/background, cold versus warm exactly once, and generic observer firing for the same state mutation. Oracle is provider-generation/prepared-publication ledger plus native presentation state and the existing push owner's send count, not JS acknowledgement. One refresh generation produces exactly one cold-or-warm publication; the refresh coordinator and packet builder produce zero WebKit sends.

RED/GREEN: required. If containment still misses SLO because package/React work is dominant, stop and route to the separate Bridge render spec; do not expand this task.

## 13. Task W11 — Native Projection And Architecture Guardrails

Sequencing note: under the user-approved performance-first amendment, W11 runs
after W1–W10 product behavior, focused proof, and applicable atomic cuts. It
must validate settled APIs and must not block initial performance implementation.

Requirements: NR1 plus enforcement contract.

Outside W5b's spec-required watched-root currentness integration, treat `RepoExplorerRowIndex.swift` and `RepoExplorerView.swift` as read-only unless runtime evidence proves another contract violation. Preserve/extend:

- `Tests/AgentStudioTests/Architecture/RepoExplorerHotPathArchitectureTests.swift`
- `Tests/AgentStudioTests/Features/RepoExplorer/RepoExplorerReadModelTests.swift`
- `Tests/AgentStudioTests/Features/RepoExplorer/RepoExplorerViewTests.swift`

Add source/SwiftSyntax guards for fleet maps/sorts/path normalization in SwiftUI body/row builders and for direct fleet dictionary reads where a keyed read model exists. Add one projection invocation/scaling test across 10/100/300 items with fixed changed rows.

Integrate the shared architecture rules from S5 for filesystem callback queues, MainActor forbidden work, direct persistence writers, legacy global posts, and unsafe watcher authority. Every rule has one good and one bad fixture plus inventory registration.

Add two mandatory SwiftSyntax rules with red-first bad fixtures: exactly one
closed `PressureStreamID` manifest with exhaustive static telemetry names and no
raw/runtime-derived construction; and no stored closures, domain algebra, or
filesystem/terminal/Bridge imports in shared admission custody types. These are
structural approximations only—S1/W2 runtime proofs still own O(1), fairness,
memory, and latency behavior.

## 14. Task W12 — Watched Workload And Acceptance

Requirements: PF1–PF9 and shared harness contract.

Use the shared S6 verifier and standard debug runner. Add the fixed scenario manifests `WF-ADD-SCALE-V1`, `WF-COLD-BOOT-V1`, and `WF-HUGE-STEADY-V1`; extend rather than fork `verify-git-refresh-performance-workload.sh` where common fixture logic is reusable.

The workload includes 10/100/300 scale, real watched-enabled versus equivalent one-shot-import control, one/many writers, noise, sidebar/Bridge states, and idle/interactive/heavy attended terminal. Record request, first useful state, repair-quiescent state, topology/Git/content oracle, source/mailbox/scan/root/project/apply/persistence/Bridge stage ledgers, MainActor heartbeat, and typing/cursor/TUI mouse/layer endpoints.

W12 has two proof layers:

1. Reproducible blocking regression cells use generated fixtures and identical operation manifests. For watched attribution run `B0` (`cd47c511` + pinned Ghostty, one-shot/watch disabled), `B1` (same baseline build, watched), `C0` (implementation HEAD + pinned Ghostty, one-shot/watch disabled), and `C1` (same candidate host, watched). Report `C1` versus `B1`, no-watch `C0` versus `B0`, and the watcher effect difference `(C1-C0)` versus `(B1-B0)`. The candidate Ghostty watched cell is a separate terminal/vendor non-regression row, not evidence for host filesystem improvement.
2. DQ1 developer-environment qualification watches `/Users/shravansunder/Documents/dev/open-source` and `/Users/shravansunder/Documents/dev/project-dev` under `open_source` and `project_dev` aliases. Initial scan and settled observation are read-only. Controlled writes occur only under a canonical run-owned `.agentstudio-performance-soak/<run-token>` sentinel, with containment/token proof before cleanup. Run each root alone and both together; alternate baseline/candidate order and record aggregate pre/post root manifests so unrelated changes invalidate attribution rather than becoming an apparent improvement.

VictoriaMetrics is the percentile/count source and VictoriaLogs is the required-stage/validity/currentness source. For every cell report MainActor queue-age and synchronous-service p50/p95/p99/max, heartbeat gaps/overdue counts, interaction tails, source/mailbox/scan/repair age and high-water, event/fact expansion, persistence/Bridge service, memory slope/plateau, final source health, and independent topology/SQLite/content equality. Missing p99 support, missing marker stages, raw-path export, non-quiescence, or a mismatched root/build/operation manifest yields `invalidEvidence`.

Run outcome is `invalidEvidence` when the victim terminal is not ready, controls differ, stages/samples are missing, repair debt remains, an accepted generation is in flight, trace/probe loss occurs, or process/build markers are stale.

### Acceptance commands

Focused commands use exact suites as implemented:

```bash
mise run test -- --filter 'DarwinFSEvent'
mise run test -- --filter 'FilesystemSourceGate'
mise run test -- --filter 'WatchedFolderScanScheduler'
mise run test -- --filter 'FilesystemRoot'
mise run test -- --filter 'WorkspaceTopology'
mise run test -- --filter 'WorkspacePersistence'
mise run test -- --filter 'GitWorkingDirectoryProjector'
mise run test -- --filter 'BridgeRefresh'
mise run test -- --filter 'FilesystemSourceE2E'
mise run test -- --filter 'FilesystemGitPipelineIntegration'
```

Then:

```bash
mise run lint
mise run test-fast
mise run test-large
mise run test-webkit
mise run test
mise run observability:up
mise run run-debug-observability -- --detach
mise run verify-debug-observability
mise run stop-debug-observability
mise run verify-git-refresh-performance-workload
mise run verify-agentstudio-performance-workload
AGENTSTUDIO_PERF_REAL_ROOT_OPEN_SOURCE=/Users/shravansunder/Documents/dev/open-source \
AGENTSTUDIO_PERF_REAL_ROOT_PROJECT_DEV=/Users/shravansunder/Documents/dev/project-dev \
  mise run verify-agentstudio-real-root-qualification
```

`run-debug-observability` owns the manual launch; `verify-debug-observability` attaches; `stop-debug-observability` terminates and confirms exit for that exact PID/identity. All three performance workload/qualification tasks are independent launch owners and run serially only after the identity is idle; each preflights idle and guarantees exact-PID cleanup on every exit. The verifier records the exact command, exit code, run token, app PID/identity, HEAD, fixture/root/build/calibration digests, Victoria queries, and comparison report.

## 15. Watched Execution Order

```text
shared S1 admission
  -> W1a callback/observation types
  -> W2a source gate/mailbox/repair registry mechanics
  -> W1b dormant real callback adapter + isolated lifecycle proof
  -> W3 scan scheduler/result
  -> W4 root index/config
  -> W4.5 sole revision owner + fixed-revision pager
  -> W5 topology mirror/projector/apply --> W7a-c persistence protocol/migration
                 |                              -> W8 compaction/checkpoint proof
                 |                              -> W7d atomic sole-writer cut
                 +-> W6 cutover-ready semantic fact endpoints
                 +-> W9 FS→Git mailbox
                 +-> W10 Bridge refresh/currentness
                        -> W2b atomic callback/source/participant cut
  -> shared IG1 transport hard cut
  -> W11 lint/native projection guards
  -> shared S6/CG1 calibration
  -> W12 watched workload contribution to combined IG2
```

W3 and W4 may develop in parallel after the isolated W1b/W2a seams stabilize. W7a–c/W8, W9, and W10 may develop in parallel after the `TopologyApplyReceipt` contract stabilizes, but W7d waits for W8 and W2b waits for W5/W9/W10. W12 depends on W2b, IG1, S6, and CG1 and contributes watched proof to IG2; it does not own or precede IG2. All edits to `FilesystemActor.swift`, `WorkspaceCacheCoordinator.swift`, `WorkspaceSurfaceCoordinator*.swift`, canonical atoms, datastore integration, `BridgePaneController.swift`, and `.mise.toml` use one integration owner per gate.

## 16. Rollback And Blocking Gates

Task-local primitives may be removed before integration. After topology, persistence, fact, Git, or Bridge hard cuts, rollback reverts the complete integration commit.

Never restore false removal from partial scans, two persistence writers, stale checkpoint overwrite, raw FS→global→Git traffic, package-sized Bridge invalidations, or repair acknowledgement while visible content is falsely current.

Blocking gates:

- scanner cannot distinguish negative from failure;
- registered-worktree consumers cannot be exhaustively named;
- root policy cannot prevent authority expansion;
- fixed-change MainActor apply scales with fleet size;
- checkpoint cannot finish/bound memory under sustained mutation;
- native Bridge currentness cannot precede repair acknowledgement;
- paired watched control or final independent oracle is invalid.
