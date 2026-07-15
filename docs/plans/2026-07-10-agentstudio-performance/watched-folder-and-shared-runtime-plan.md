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
| `RepoScanner` | retain resumable traversal provider; yield validation requests and return exhaustive evidence rather than awaiting Git or producing absence-capable best effort |
| `RepoScannerValidationExecutor` | add one bounded actor with root-fair validation FIFO and two physical read-only native-task slots |
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
  callback leases, but no optional or temporary mailbox. The W2a substrate
  supplies the fixed fleet mailbox, binding-aware recovery shells, and paired-
  port factory. W1b composes those substrate slices into the dormant retained
  callback userdata before the W2a mechanics-complete receipt.
- W1a tests cover value invariants and lifecycle/lease transitions. Native
  array inspection and exact flag classification remain W1b callback-adapter
  proof because W1a does not cut production ingress.

### W1b — Dormant real callback adapter over the W2a substrate

The normative task decomposition, file edits, proof matrix, checkpoint gates,
and W2b deferral live in
[W1b/W2 Fixed-Slot Filesystem Lifecycle Plan](w1b-fixed-slot-lifecycle-plan.md).
This section is only the parent slice summary.

Runs over the W2a substrate slices for the fixed fleet
`FilesystemObservationMailbox`, binding-aware recovery shells,
`FilesystemSourceGate`, slot registry, and exact per-binding recovery custody.
W1b precedes, and is required by, the W2a mechanics-complete receipt.
W1b is a dormant isolated assembly, not the production protocol cut. The live
`FSEventStreamClient -> FSEventBatch -> FilesystemActor` contract and current
`DarwinFSEventStreamClient` remain unchanged until W2b because they are the one
complete legacy production path. Add:

- `Sources/AgentStudio/Core/RuntimeEventSystem/Filesystem/DarwinFSEventObservationAdapter.swift`
  - Own the future native callback capture and stream lifecycle behind a
    retained `FSEventRegistrationControlBlock` without conforming to or
    publishing through the legacy `FSEventStreamClient` protocol.
  - Carry one mailbox-created, binding-specific paired callback admission port
    in the retained control-block assembly. No raw producer or independently
    pairable signaler escapes. `FSEventObservation` derives source kind from the
    token and carries monotonic capture time, unioned flags, first/last event-ID
    watermarks, copied-record count/bytes, total event count, and truncation.
  - Enforce distinct inspected-native-record, copied-record, copied-byte, and
    maximum-single-path-byte limits before materializing any complete Swift path array.
  - Acquire the exact callback lease before native pointer inspection. Its
    one-shot admission authority remains held through mailbox offer and paired
    wake application.
  - Join bounded flag/truncation evidence into the exact binding-aware recovery
    shell before the observation can be contracted. Capacity pressure and
    retirement-fence contraction have distinct typed evidence.
  - Teardown sequence: close new lease acquisition, stop/invalidate the stream,
    execute the callback-queue barrier, drain leases, mint the exact drain
    receipt, append or retain the binding-specific FIFO retirement fence,
    transfer observation/recovery custody into actor/SourceGate ownership, wait
    for cleanup, mint the final receipt, release callback context once, apply
    the context-release acknowledgement, and only then recycle the slot. One
    source never seals or finishes the fleet mailbox/doorbell.

W2b owns the atomic production cut: replace `FSEventBatch` and the legacy
`FSEventStreamClient` methods with generation-bearing observation registration,
install this adapter inside the production Darwin client/source composition,
switch `FilesystemActor` to the mailbox consumer, update the controllable fake,
and delete `CallbackContext` plus the legacy batch stream in the same commit.

Do not call an actor, schedule one task per path, access MainActor state, scan, canonicalize every path, or clear repair state in the callback.

W1b prepares the production callback adapter and proves the real Darwin lifecycle in an isolated assembly, but does not switch production `FilesystemActor` ingress. Production keeps the complete legacy callback/source path until W2b atomically installs the callback adapter, source gate, mailbox drain, and the exact live repair-participant set. W3–W10 develop against the W2a fake/isolated ingress seam. There is no accepted product checkpoint where real registered-worktree repair debt can be captured before its mandatory participants exist.

### Test proof

Create/modify:

- new `Tests/AgentStudioTests/Core/PaneRuntime/Sources/DarwinFSEventObservationAdapterTests.swift`
- `Tests/AgentStudioTests/Core/PaneRuntime/Sources/DarwinFSEventObservationAdmissionTests.swift`
- `Tests/AgentStudioTests/Core/PaneRuntime/Sources/FSEventRegistrationControlBlockTests.swift`
- `Tests/AgentStudioTests/Core/PaneRuntime/Sources/DarwinFSEventStreamClientTests.swift`
  only for the structural pre-W2b proof that production remains wholly legacy.

Boundary/seam: C callback capture and registration close.

Invariants: bounded capture; all discontinuity flags survive; N never becomes
N+1; closing rejects callbacks without a valid held/unused lease; a leased
callback admits at most one exact binding contribution and paired wake; userdata
and binding authority remain alive through barrier, lease drain, semantic/
recovery transfer, final receipt, release-once, and context acknowledgement.

Illegal-state/guards: exhaustive flag disposition, explicit open/closing/closed state, item/byte cap before allocation, generation match on lease.

Valid/invalid IO: ordinary create/rename/delete, must-scan, user/kernel drop, wrapped IDs, root change, unknown flags, nil/malformed counts, oversized batch, unregister/re-register, callback-close race.

Independent oracle: literal flag/observation table and control-block counters, not production classification.

RED/GREEN: required. RED covers raw producer/signaler escape, loose or reusable
lease admission, lost flag/ID/truncation, unbounded copied records, early fence/
receipt/context release, and stale binding effects. GREEN includes the atomic
lease + paired-port + dormant-adapter interface cut, deterministic held-lease/
wake ordering, and a real temporary Darwin lifecycle through fixed slot,
isolated actor/SourceGate transfer, fence, cleanup, final receipt, release-once,
and context acknowledgement. A structural pre-W2b test proves production
callback/source composition is still wholly legacy; the legacy fake is not
changed until W2b.

Split/replan trigger: queue barrier plus leases cannot establish teardown quiescence on the supported Darwin callback model.

## 4. Task W2 — Source Gate, Observation Mailbox, And Repair Registry

Requirements: WF2–WF5, WF9–WF10.

### W2a — Gate/mailbox/registry mechanics

Add:

- `Sources/AgentStudio/Core/RuntimeEventSystem/Filesystem/FilesystemObservationMailbox.swift`
  - Domain wrapper over value-only `BoundedGatherMailbox` with a short wrapper
    lock coupling generic custody to fixed binding-aware
    `FilesystemRecoveryEvidenceRegister` shells.
  - Use predeclared `FilesystemObservationPhysicalSlotID` generic keys. Complete
    exact UUIDv7 bindings live inside domain contributions and authority.
  - Retain opaque bounded observation/fence contributions and checked footprints;
    perform no path/flag merge, dedupe, normalization, routing, or repair join
    under generic mailbox state.
  - Enforce calibrated retained pending-plus-leased contribution/item/byte
    limits globally and per physical binding, the static two-binding logical-
    source maximum, and distinct one-key lease quanta.
  - Register exact monotonic continuity/root-identity/truncation/overflow/
    unsupported/fence-contraction evidence before a recovery revision becomes
    visible. Generic stamps are not cross-binding authority.
  - Expose one callback-lease-credentialed paired admission/doorbell port plus
    actor consumer/waiter ports. No raw producer or separate signaler escapes;
    only whole-fleet lifecycle composition can finish the doorbell.
  - Lease one source key at a time. Cancellation/rebind re-presents identical
    custody with a new binding token; retry stays ahead of newer same-key work
    but rotates behind already-ready unrelated keys.
  - Reject unknown keys without trapping. Lease, rather than destructively
    remove, captured recovery state until `FilesystemActor` transfers it into
    `FilesystemSourceGate`; newer evidence/revision survives an older ack.
- `Sources/AgentStudio/Core/RuntimeEventSystem/Filesystem/FilesystemObservationSlotRegistry.swift`
  - Own the fixed slot pool, exact UUIDv7 bindings, desired FIFO/reservation/
    withdrawal, safe-old versus unsafe-old currentness, predecessor ordering,
    pending fence, final receipt, release acknowledgement, and bounded tombstone.
    Selected reservation owns no binding; one lock-linearized native-lifetime
    commitment consumes the reservation and mints the binding plus committed
    unpublished-native-generation custody before any native create call.
- `Sources/AgentStudio/Core/RuntimeEventSystem/Filesystem/FilesystemObservationFleetLifecycle.swift`
  - Own typed completed/incomplete in-memory shutdown debt and deterministic
    cancellation-safe resume. Global seal remains shutdown-only.
- `Sources/AgentStudio/Core/RuntimeEventSystem/Filesystem/FilesystemSourceGate.swift`
  - Exact states: `healthy`, `dirty`, `reconciling`, `reconcilingAndDirty`, `awaitingAcknowledgements`, `repairFailed`, `shuttingDown`.
  - Own `RepairGeneration`, current registration, scan state, and acknowledgement set.
- `Sources/AgentStudio/Core/RuntimeEventSystem/Filesystem/WorktreeContentRepairConsumerRegistry.swift`
  - Generation-bearing participant registration.
  - Captured participant set per repair generation.
  - Sole owner of exhaustive unregister/replacement transfer,
    late-registration currentness, active/pending/completed/superseded repair
    lifecycle, temporal projection eligibility, acknowledgement/retry custody,
    and exact debt-free source-registration retirement receipts. It does not
    own the observation-slot binding.
- `Sources/AgentStudio/Core/RuntimeEventSystem/Filesystem/FilesystemContentRepairProjector.swift`
  - Convert coarse registered-worktree repair into bounded serial
    consumer-specific rebuild requests, own resumable acknowledgement/SourceGate
    forwarding plus bounded exact replay, and never fabricate a full file
    inventory or decide consumer membership/currentness.

Prepare the actor-owned isolated fixed-slot drain as the sole mailbox consumer
in the W1b/W2a assembly. The actor owns fixed per-slot semantic replay shells,
exact contribution identity acceptance, equality
dedupe, flag/reason reduction, routing, latest/OR/count aggregation, subtree/root
collapse, debounce, and the post-transfer semantic fair-root queue. The generic
mailbox alone owns the mechanical unique ready-key queue used for one-key lease
selection and retry rotation. W2b installs that drain in production. At most one
wake and one active generic lease are present; retry buckets/replay shells may
exist for multiple slots within the static P × lease-quantum bound. The configured
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

The registry and projector remain separate off-main actors. A registry-issued
activation proves origin authenticity, not permanent temporal eligibility. For
new work, the projector reserves per-source admission before awaiting the
registry's exhaustive classification of the full activation. Only the exact
current active generation or an exact capture-ledger `.completed` entry may
enter delivery. Pending, superseded, older/evicted completed, retired, and
mismatched activations reject without consumer effects. Exact completed entries
remain eligible so zero-consumer or final-consumer registry terminalization can
precede the projector acknowledgement without deadlocking completion.

External accepted-acknowledgement forwarding receives equivalent bounded
currentness classification before it creates or resumes forwarding custody.
Source retirement crosses the boundary only as an exact typed registry receipt:
the registry first proves zero consumer/retry/acknowledgement/capture debt for
the exact `FSEventRegistrationToken`. The projector matches that registration
against its exact SourceGate acceptance and observation-slot binding, then
proves zero delivery/forwarding debt for the same registration before clearing
bounded replay and source state. This adds no actor, EventBus,
MainActor work, source identity, or UUID ordering.

### W2b — Atomic production admission and participant cut after W10

Depends on W5's pane/filesystem projection owner, W9's Git mailbox/projector integration, and W10's generation-bearing Bridge owner. In one production composition cut, wire the pane/filesystem projection, Git projector, and applicable Bridge refresh owners into the registry; install the W1b callback adapter and W2a source gate/mailbox drain; then run the full participant matrix. W3–W10 may depend on W2a mechanics and isolated ingress; W12 repair-health acceptance depends on W2b. No source may return to `healthy` before W2b records the exact matching disposition for every captured participant. Pre-cut production is wholly legacy; post-cut production has the complete captured participant set and no callback path bypasses the gate.

### Test proof

Add:

- `FilesystemObservationMailboxTests.swift`
- `FilesystemSourceGateTests.swift`
- `FilesystemRepairRegistryTests.swift`
- `RegisteredWorktreeRepairIntegrationTests.swift`

Extend `FilesystemActorTests.swift`.

Invariants: ordinary pressure contracts only after exact binding recovery
custody exists; native joined evidence survives payload contraction;
starting/completing scan does not clear repair; every captured current
participant acknowledges the same generation; disappearing UI state cannot
acknowledge; replacement transfers or explicitly withdraws retained authority.
N→N+1→N+2 retains at most two started physical bindings, one predecessor-free
pending fence intent, and one newest not-yet-authoritative desired identity.
Configuration receipts use strict deferred/failed retaining-current versus non-
current cases; retry membership is derived and cannot contradict the cases.

Oracle: independent participant/repair ledger and final source-state model.

RED/GREEN: required for typed generic exhaustion, overflow without recovery,
mixed loss/root/fence evidence under contraction, pending-plus-leased bound-plus-
one, multi-slot partial replay, one noisy/299 quiet root fairness, cancellation/
rebind/late-old-ack, N→N+1→N+2 replacement, reservation-only withdrawal at
pop/reserve, atomic native-lifetime commitment, post-commit withdrawal at
create/start, safe/unsafe prior authority, cleanup-gated retirement, release-once/
tombstone replay, exact shutdown debt, Git-only acknowledgement, unregister/
replacement, and late/stale acknowledgement. WF-C also proves stale activation
rejection after the 256-record completed-replay window evicts it, exact
capture-ledger rejection of a superseded latest-completed slot, zero-consumer
and final-consumer completion, actor reentry while eligibility is suspended,
debt-blocked and receipt-authorized retirement, stale/mismatched retirement
receipt rejection, and equivalent currentness for external acknowledgement
forwarding.

W2a completion proves mechanics only. W2b is the production repair/admission gate and tests visible, background, closed, replaced, failed, and not-applicable Bridge states against an independent captured-participant ledger. Its integration proof injects oversized/drop input through the real production callback composition, captures the exact live participant generations, and reaches `healthy` only after every matching receipt.

## 5. Task W3 — Fair Scan Scheduler And Exhaustive Scanner Results

Requirements: WS1–WS9.

Depends on W4a's source-authorized `RegisteredRootDescriptor` construction
contract. W3 does not accept a raw `URL` as scheduler authority and does not
wait for W4b's persistent lookup index.

### Production changes

Add:

- `Sources/AgentStudio/Core/RuntimeEventSystem/Filesystem/WatchedFolderScanScheduler.swift`
  - One running scan per watched folder.
  - Running-plus-newest-dirty collapse.
  - One immediate follow-up maximum.
  - Explicit global concurrency and oldest-ready/fair scheduling of bounded
    scanner quanta, not complete recursive scans.
  - A suspended logical run requeues at the tail without changing its checked
    scan-run generation. A new generation is minted only for a new logical
    scan after final completion, cancellation, or replacement.
  - A traversal credit covers one bounded synchronous traversal quantum only.
    `validationRequired` releases it before enqueueing validation, so saturated
    or draining Git work cannot stop unrelated-root traversal. Final-result
    custody remains separately bounded and leased until an identical result is
    acknowledged; a slow result consumer reduces finalization throughput
    without creating an inventory queue.
- `Sources/AgentStudio/Core/RuntimeEventSystem/Filesystem/WatchedFolderScanResult.swift`
  - Normative `WatchedFolderScanRequest`, strict `WatchedFolderScanCause`,
    non-empty `WatchedFolderRepairObligation`,
    `ScheduledWatchedFolderScanResult`, and
    `WatchedFolderScanSchedulingMetrics`.
  - The request obtains authority only from one `RegisteredRootDescriptor`
    carrying the exact `FSEventRegistrationToken`; it does not duplicate token
    fields. The cause union represents initial, callback, manual, fallback, or
    repair with exact generation and non-empty obligations, never nil or
    correlated independent fields.
  - Bind that exact registration token and a checked per-root `UInt64` scan-run
    generation to scanner evidence. UUIDv7 source identity stays opaque and
    never determines ordering; the scanner mints no authority.
  - Scheduling metrics own queue wait, stale drops, and follow-ups.
- `Sources/AgentStudio/Infrastructure/RepoScannerResult.swift`
  - Normative strict `RepoScannerResult` associated-value union with exactly
    `completeAuthoritative`, `partial`, `unavailable`, `cancelled`, and `failed`
    cases plus case-specific payloads, exhaustive `ScanFailureReason`, and
    traversal/validation counts.
  - Counts own directories, candidates, validation
    success/authoritative-negative/timeout/cancel/failure, and scanner service.
  - No correlated optionals, source/root authority, scheduler metrics, prior
    topology, or removal candidates.
- `Sources/AgentStudio/Infrastructure/RepoScannerValidationExecutor.swift`
  - One actor owns a bounded root-fair FIFO, a compile-time logical queue cap
    `Q`, and physical validation capacity `V`, initially two task slots.
  - Permit at most one outstanding candidate per logical scanner session.
    Select requests round-robin by canonical watched-root identity; UUIDv7
    request/session IDs establish identity/currentness only and never ordering.
  - A deadline or cancellation ends logical waiting but does not release a
    physical slot still executing synchronous libgit2. Keep that slot in an
    explicit `draining` state until the native call actually exits. When both
    slots drain, reject/defer new requests as typed partial/dirty evidence; do
    not create replacement tasks, grow the queue, or block unrelated traversal.
  - Do not process-isolate the first cut. Add a telemetry-backed escalation
    gate for persistent helpers only if sustained non-cooperative native-task
    debt remains after the bounded executor lands.
- `Sources/AgentStudio/Infrastructure/RepoScannerGitDiscoveryClient.swift`
  - Expose only discovery identity/validation reads. Production construction
    must not accept or retain `AgentStudioGitLocalClient`, a writer registry, or
    any remote/network client.
- `Sources/AgentStudio/Infrastructure/AppPolicies.swift`
  - Add a strict Git operation-class/budget vocabulary for discovery read,
    status read, network fetch/pull, worktree lifecycle/checkout, and other
    mutations. Each class binds to its own executor/capacity/deadline type; no
    generic optional timeout or shared slot pool represents the union. Preserve
    the current compile-time discovery/status defaults of two seconds and one
    second. Do not invent network/lifecycle/mutation values; calibrate and
    freeze each separately when its executor is implemented.

Land the matching `agentstudio-git` dependency change before production W3
integration, then update `Package.swift`/`Package.resolved` to its immutable
revision. The dependency adds a narrow discovery-read implementation that opens
only the exact candidate with `GIT_REPOSITORY_OPEN_NO_SEARCH` and may read
identity, worktree registration/lock state, and HEAD. It must never create,
remove, wait on, or hold lockfiles; refresh/write an index; mutate repository,
worktree, or common-directory content; or borrow writer/remote executors.
Access-time changes caused by reads are excluded from the absolute immutability
claim. Status, network, lifecycle/checkout, and mutation executors keep separate
capacity and deadlines; discovery cannot borrow their slots.

Modify:

- `Sources/AgentStudio/Core/RuntimeEventSystem/Filesystem/FilesystemActor.swift`
  - Replace `handleWatchedFolderFSEvent`, `rescanAllWatchedFolders`, `refreshWatchedFolder`, and `startFallbackRescan` ownership with scheduler submission/drain.
  - Initial, callback, manual, fallback, and repair triggers use the same scheduler.
- `Sources/AgentStudio/Infrastructure/RepoScanner.swift`
  - Replace `try?` suppression that converts traversal/metadata errors into absence-capable results.
  - Return only exhaustive `RepoScannerResult` traversal/validation evidence,
    with authoritative negative distinct from timeout/cancellation/failure.
  - Add one opaque resumable scanner-session port. Each session owns its lazy
    `FileManager.DirectoryEnumerator`, accumulated evidence, traversal/error
    state, and cumulative active service duration behind synchronous protected
    state.
  - `advanceOneQuantum` has the strict union `suspended(usage:)`,
    `validationRequired(request)`, or `finished(RepoScannerResult)`. A session
    preserves one pending candidate across validation and resumes only from the
    exact current request completion. Suspension exposes usage only and never
    repository inventory; only the session constructs a final result.
  - Bound a quantum by calibrated positive item, path-byte, candidate, failure,
    and active-service limits. Reaching a quantum cap suspends the session;
    reaching an absolute scan/failure cap finishes with non-authoritative
    evidence and retained repair debt, never a truncated
    `completeAuthoritative` result.
  - Express production limits as one typed compile-time watched-folder scan
    policy with independently named fields. Tests inject smaller policies. Do
    not reuse callback, EventBus, replay, or envelope capacities as scan limits;
    calibration may change one pressure surface without coupling the others.
  - Hold the synchronous scanner-state lock only while advancing or reading the
    enumerator/state. Never await Git inside the quantum or under that lock. One
    strict quantum lease prevents concurrent advancement of the same enumerator.

The scheduler accepts a suspension, validation request/completion, or final
result only from the exact session it created for the exact current
`FSEventRegistrationToken`, UUIDv7 session/request identity, and checked
scan-run generation. Replacement, cancellation, and stale completion reject
exactly without advancing another session. Completion ingestion remains
private. The scheduler never derives removals. Partial positives retain
dirty/repair state, and an ordinary trigger never erases repair. In the target
architecture W5 alone derives removals from current complete evidence.

Production integration prerequisite: before the scheduler can feed the legacy
topology path, repair the current double-reconciliation regression at the
canonical live mutation boundary. In the transitional pre-W5 product path,
`RepositoryTopologyAtom` owns the single identity-preserving merge and exposes
strict `RepositoryWorktreeReconciliationResult` and
`RepositoryReassociationResult` unions. It consumes each existing worktree
identity at most once, validates global UUID/stable-key uniqueness and repo
ownership before assignment, uses UUIDv7 for newly issued identities without
using UUID ordering as authority, and leaves live state unchanged on rejection.
Reassociation prepares and validates repo metadata, availability, and worktrees
before one commit; rejection also preserves path-index generation and produces
no pane/cache/persistence/trace effect, while acceptance schedules no duplicate
index rebuild. `WorkspaceCacheCoordinator` exhaustively handles rejection and
must not interpret persistence failure as mutation rejection or recovery. This
is an immediate correctness guard for the pre-W5 product path; W5 later replaces
the transitional result types with separate canonical reconciliation/apply
contracts and removes the identity-preserving merge from the atom.

### Test proof

Create/modify:

- `WatchedFolderScanSchedulerTests.swift`
- `RepoScannerValidationExecutorTests.swift`
- `RepoScannerGitDiscoveryReadOnlyIntegrationTests.swift`
- `RepoScannerCompletenessTests.swift`
- `FilesystemActorWatchedFolderTests.swift`
- `FilesystemActorShellGitIntegrationTests.swift`
- `WatchedFolderScanRecoveryIntegrationTests.swift`

Use real temporary filesystem/Git fixtures for the integration layer. Scanner
cases: permission denial, unreadable child, validation timeout/failure,
cancellation, missing/replaced root, malformed `.git`, symlink loop, and exact
completion/count classification. Executor cases: bounded `Q`/`V`, two physical
slots, one outstanding candidate per session, root-fair FIFO selection, both
slots draining, no synthetic reuse before actual exit, stale/replaced request
rejection, saturation-to-partial conversion, and unrelated traversal progress.
Scheduler cases: hot/cold folder fairness,
one-running, trigger during running scan, newest-dirty collapse, exact-current
generation rejection, cancellation-aware result leasing, all-waiter shutdown,
and separated queue/service/follow-up metrics. Deterministic fairness proof uses
10/100/300 ready roots plus one continuously yielding root and asserts every
quiet root receives a quantum within the independent WS4 selection bound. A
slow result consumer proves the final-result custody invariant, zero silent
loss, bounded high-water, and resumed progress without sleeps.

Independent oracle: literal generated directory/repository manifest. Do not derive expected absence from scanner output.

Read-only discovery proof uses a disposable repository and linked worktree made
non-writable after setup. Capture a metadata/content manifest before and after,
monitor transient filesystem writes during validation, and prove a pre-existing
lock fixture remains byte-identical. A nested-repository fixture proves exact
candidate open with no parent search. The oracle permits access-time changes but
rejects any created/removed/changed lockfile, index, ref, config, worktree
registration, repository content, or common-directory content. Dependency-level
tests exercise the concrete libgit2 implementation; AgentStudio integration
tests prove only the narrow capability is constructible by `RepoScanner`.

RED/GREEN: required for suppressed traversal/validation errors producing a
partial non-authoritative result that cannot express absence, and for
starvation/running-plus-dirty behavior. The W3 `FilesystemActor` integration
also proves that a partial/stale result cannot remove its prior observed group
and retains dirty/repair state. Until W5, that actor retains only the legacy
observed-group comparison and gates destructive URL emission on complete-current
scanner/scheduler evidence; it does not construct canonical identity removals.
W5 hard-cuts that transitional comparison and re-proves the invariant at the
final topology-projector owner against canonical truth. W3 does not move
removal derivation into the scanner or scheduler.

The production-integration RED case reproduces the historical duplicate-ID
failure: existing worktree `X`, then same-name discovered entries at the
original and renamed paths. Guarded reconciliation followed by canonical apply
must produce `[X, Y]`, never `[X, X]`; atom state, autosave input, and Repo
Explorer projection remain valid. Malformed duplicate-ID/stable-key input is a
typed rejection with byte-for-byte unchanged live state and zero downstream
effects. A reassociation rejection additionally proves unchanged repository
name/path, availability, worktrees, path-index generation, pane residency,
cache state, persistence input, and trace/effect counts. Acceptance proves one
index-generation advance. Repo Explorer's nontrapping duplicate handling is a
fault-containment test, never the canonical invariant oracle. The scheduler
remains dormant until this proof is GREEN.

Telemetry records logical queue age/high-water, per-root wait, physical running
and draining slots, deadline/cancellation outcome, native exit debt/age, and
discovery operation class without raw paths or repository UUIDs.

Split triggers: the validation provider cannot distinguish authoritative
negative from timeout/failure; the narrow dependency implementation cannot
prove exact no-search/read-only behavior; or bounded in-process draining debt
prevents the accepted root-fair progress invariant under calibrated workloads.

## 6. Task W4 — Source-Authorized Root Contract, Persistent Index, And Batched Configuration

Requirements: FI1–FI7.

### W4a — Source-authorized root descriptor prerequisite

Add:

- `Sources/AgentStudio/Core/RuntimeEventSystem/Filesystem/FilesystemSourceConfiguration.swift`
  - Normative source-owned `RegisteredRootDescriptor` construction from
    host-authorized input. The descriptor carries one exact
    `FSEventRegistrationToken` as its sole source/root/registration authority.
  - Scanner paths, Git metadata, and scan output cannot construct, select, or
    widen this authority.
- `Sources/AgentStudio/Core/RuntimeEventSystem/Filesystem/FilesystemPathCanonicalizer.swift`
  - Source-verified volume/case/Unicode/component policy used to construct the
    descriptor. No per-event canonicalization or root lookup lands in W4a.

W4a is the small prerequisite for W3 request authority. Its focused proof
rejects raw, relative, outside-root, mismatched-generation, and scanner-derived
construction attempts.

### W4b — Persistent root index and batched source configuration

### Production changes

Add:

- `Sources/AgentStudio/Core/RuntimeEventSystem/Filesystem/FilesystemRootIndexSnapshot.swift`
  - Immutable, generation-bearing path-component index with deepest canonical match.
  - Build from user-authorized canonical roots when topology changes.
- Extend `Sources/AgentStudio/Core/RuntimeEventSystem/Filesystem/FilesystemSourceConfiguration.swift`
  - Normative `FilesystemSourceConfigurationBatch` and `FilesystemSourceConfigurationReceipt` for one typed register/unregister/activity/filter change.
  - Canonicalize roots once; preserve lexical/resolved forms only as the accepted security policy permits.
- Extend `Sources/AgentStudio/Core/RuntimeEventSystem/Filesystem/FilesystemPathCanonicalizer.swift`
  - Share the W4a descriptor policy with immutable index lookup.

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

Set `AppPolicies.WorkspacePersistence.snapshotPageMaximumItems` to the
compile-time value 256. This caps one MainActor capture page; it does not cap the
workspace or borrow the legacy event/path transport constants. Keep raw-byte,
scanned-item, participant-inspection, synchronous-service, and cleanup limits as
separate validated policy values. Transfer each page into the off-main
accumulator before acknowledging `.transferred`, yield between capture turns,
and close/abort plus drain retained cleanup custody on every exit path.

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
  - Define `TopologyProjectionRequest` as the sole W5 binding of one accepted
    `ScheduledWatchedFolderScanResult` to the projector mirror's canonical base
    revision.
  - Accept exact current `TopologyProjectionRequest` values; resolve
    identities, joins, worktree reconciliation, pane/cache patches, and
    downstream effects off-main.
  - Derive removals only from `completeAuthoritative` inventory after exact
    `FSEventRegistrationToken`, checked scan-run generation, and compatible
    mirror/base-revision checks.

W5a modifies no atom. It proves mirror bootstrap/contiguous update/gap recovery,
field ownership, identity joins, stale scan rejection, complete-current removal
derivation, partial/stale no-removal with retained non-current debt, and literal
topology diff output against an independent generated manifest.

Identity projection consumes each existing repo/worktree UUID at most once per
transaction. Replace the duplicated coordinator/atom identity-preservation
algorithms with one projector-owned reconciliation contract; an already
reconciled result must never pass through a second identity-preserving merge.
The regression oracle starts with existing worktree `X`, projects two discovered
same-name entries at the original and renamed paths, and requires distinct
result identities `[X, Y]`, never `[X, X]`.

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

Before mutating any atom, `WorkspaceTopologyApplier` validates global repo and
worktree UUID/stable-key uniqueness and the one-to-one identity-consumption
ledger produced by the projector. Duplicate identity is an exhaustive typed
rejection case: it publishes no atom revision, persistence revision, EventBus
fact, cache/pane effect, or repair acknowledgement. `RepositoryTopologyAtom`
must not retain an independent identity-preserving merge after this cutover.
Persistence retains its duplicate checks as defense in depth, and Repo Explorer
may use nontrapping defensive indexing only for fault containment; neither may
mask a rejected canonical transaction or count as the invariant proof.

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

Add a RED regression for the historical double reconciliation: guarded
projector output `[X, Y]` entering the canonical apply path must remain `[X, Y]`.
Add malformed-batch cases for duplicate IDs within one repo and across repos,
duplicate stable keys, and one existing identity claimed by path and name.
Every rejection proves byte-for-byte unchanged live topology, unchanged atom
and persistence revisions, zero autosave attempt, and zero downstream effects.

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

W11a is product performance work and may run after the W5 keyed topology/read
contracts stabilize. W11b is enforcement work and runs after W1–W10 product
behavior, focused proof, and applicable atomic cuts. This preserves the
user-approved performance-first sequencing: runtime hot paths are corrected
before the final SwiftSyntax guardrails validate settled APIs.

Requirements: NR1 plus enforcement contract.

### W11a — Keyed native pane-management and inbox display projection

Current PID evidence records approximately 148,000 topology lookups/minute with
the heaviest Swift stack in `PaneManagementContext`, inbox aggregation, and
SwiftUI pane rendering. Live source confirms `PaneLeafContainer.body` constructs
two management contexts per evaluation; each context may perform linear
`RepositoryTopologyAtom.repo`/`worktree` scans, a worktree-path prefix scan, and
an `InboxNotificationAtom.notifications.reduce` for one worktree.

Modify:

- `RepositoryTopologyAtom.swift` and/or its existing derived owner to maintain
  keyed repo/worktree lookup state atomically with canonical topology mutation.
  Hot `repo(id)` and `worktree(id)` reads must not flatten or scan the fleet.
- `InboxNotificationAtom.swift` to maintain exact keyed unread/roll-up counts
  for worktree, tab, and pane identities across append, coalescence, mutation,
  retention, hydration, removal, and empty-lane transitions. Hot count reads do
  not reduce the retained notification log.
- `PaneManagementContext.swift` and `PaneLeafContainer.swift` to consume one
  keyed/prederived snapshot per distinct pane identity and avoid projecting the
  same pane twice when the management and location targets are equal. SwiftUI
  `body` performs no fleet topology scan or inbox-log aggregation.

Preserve canonical MainActor ownership. This task adds no actor, EventBus route,
filesystem work, or second source of truth; indexes and counts are derived
state maintained by the existing canonical mutation owner. Add deterministic
correctness tests covering every inbox mutation/retention path and topology
replacement/reassociation, plus a 10/100/300-fleet fixed-pane proof whose
lookup/projection work is independent of fleet size. Instrument pane-management
projection count, topology keyed/fallback lookup count, inbox aggregation count,
SwiftUI invalidation count, and MainActor service.

Acceptance requires the final Victoria baseline-to-candidate report to show a
material reduction from the recorded 148,000 topology lookups/minute under the
same pane/workload manifest. Zero linear topology and inbox-log scans are
structural CI gates; elapsed CPU/footprint improvement remains runtime proof.

### W11b — Architecture guardrails

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
  -> W2a fixed-slot substrate slices
  -> G2 + legacy structural proof -> W1b dormant-ready
  -> F3 + WF-C participant registry/projector -> W2a mechanics-complete
  -> W4a source-authorized root descriptor
       +-> W3 scan scheduler/exhaustive scanner result
       +-> W4b root index/batched config
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

W4a lands first so neither scanner nor scheduler accepts raw path authority. W3
and W4b may then develop in parallel after the isolated W1b/W2a seams
stabilize. W7a–c/W8, W9, and W10 may develop in parallel after the
`TopologyApplyReceipt` contract stabilizes, but W7d waits for W8 and W2b waits
for W5/W9/W10. W12 depends on W2b, IG1, S6, and CG1 and contributes watched
proof to IG2; it does not own or precede IG2. All edits to
`FilesystemActor.swift`, `WorkspaceCacheCoordinator.swift`,
`WorkspaceSurfaceCoordinator*.swift`, canonical atoms, datastore integration,
`BridgePaneController.swift`, and `.mise.toml` use one integration owner per
gate.

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
