# W1b/W2 Fixed-Slot Filesystem Lifecycle Plan

Status: accepted after focused adversarial review
Date: 2026-07-13

Parent plan:
[Watched-Folder Admission And Shared Runtime Implementation Plan](watched-folder-and-shared-runtime-plan.md)

Accepted sources:

- `watched-folder-admission-mainactor-fairness.md`, 1,785 lines,
  SHA-256 `10e93247c58fd03b9adaef007f8cdc0106ac3887aeeb71379c4873b24ec89050`
- `filesystem-observation-admission-lifecycle.md`, 813 lines,
  SHA-256 `2eb62ae2c5797c4577d98710d3481ebf8d414360d3675fb6815f78b70aa2f535`
- live planning anchor: `03e667c5a048767629238e5483a0bbbe43b596a8`

## 1. Outcome

Replace the dormant registration-keyed filesystem observation assembly with the
accepted fixed fleet substrate while keeping production wholly legacy until the
later atomic W2b cut.

The immediate implementation ends with two independently verifiable gates:

```text
W1b dormant ready
  real bounded Darwin callback
  -> lease-credentialed paired port
  -> fixed physical slot
  -> isolated actor/SourceGate transfer
  -> ordered fence and release-once context teardown

W2a mechanics complete
  W1b gate
  + deterministic replacement/currentness state
  + repair-participant registry/projector mechanics
  + exact cancellation-safe fleet shutdown debt
```

Neither gate claims production reachability, MainActor improvement, terminal
interaction improvement, large-root stability, or Victoria performance gain.
Those require W2b and the later workload gates.

## 2. Hard Scope

In scope:

- the minimal generic `GatherContractionCause` result;
- fixed physical-slot and UUIDv7 lifecycle identities minted only by the owner
  that performs the causal transition they identify;
- fixed recovery and semantic-replay shells;
- deterministic desired FIFO, reservation, withdrawal, prior-authority, and
  derived-currentness state;
- a decomposed slot-registry owner whose immutable contracts/projections cannot
  hold mutation capability and whose sole binding construction transition is
  protected by focused SwiftSyntax ownership proof;
- one-shot callback lease authority and one mailbox-created paired port;
- per-binding FIFO retirement fence, pending retry, cleanup gate, predecessor
  ordering, SourceGate acceptance, receipt, release-once, tombstone, and fleet
  shutdown debt;
- dormant Darwin adapter migration and isolated real-stream proof;
- W2a repair-participant registry/projector mechanics;
- a later, explicitly deferred W2b atomic production cut.

Out of scope:

- production ingress changes before W2b;
- dynamic generic keys, generic per-key seal/retirement, per-source mailbox/task,
  a second product bus, or persisted shutdown debt;
- W3-W12 behavior, broad lint expansion, Victoria workload changes, Ghostty
  vendor work, or app-level performance claims;
- compatibility shims or a dual old/new callback route.

## 3. Live Mismatch To Remove

Current W1b/W2a code and the dormant adapter prototype still assume:

```text
FSEventRegistrationToken as generic key
separately injectable producer and signaler
reusable callback lease admission
per-generation mailbox seal/invalidate/finish
registration-keyed recovery evidence
one transferring/sealed mailbox generation
```

The implementation must hard-cut those dormant interfaces to:

```text
fixed FilesystemObservationPhysicalSlotID keys
complete UUIDv7-identified FilesystemObservationSlotBinding
one-shot held lease + mailbox-created paired port
per-binding FIFO retirement fence
fixed binding-aware recovery/replay shells
two started bindings + one newest desired identity
shutdown-only fleet seal
```

At the atomic E/F1/G1 checkpoint and every later checkpoint, the hard-cut
structural negative criteria are exact: generic custody is keyed
only by fixed physical slot and carries stable contribution identities; no
registration-keyed declared/recovery map remains; no raw producer or separately
pairable signaler escapes; no per-binding lifecycle operation can seal,
invalidate, or finish the fleet mailbox/doorbell; and every callback
contribution carries the complete binding plus contribution identity.

The untracked dormant adapter and its tests are adopted input, not disposable
scratch. Rewrite them through the planned interface cut; do not recreate or
silently overwrite their bounded native-capture work.

## 4. Vertical Slice WF-A — Credentialed Fixed-Slot Admission

### A — Typed generic contraction cause

Requirements: child Fixed Slot Identity and proof item 10.

Modify:

- `Sources/AgentStudio/Core/RuntimeEventSystem/Admission/AdmissionContracts.swift`
- `Sources/AgentStudio/Core/RuntimeEventSystem/Admission/BoundedGatherMailbox.swift`
- generic gather test support and exhaustive pattern matches
- `BoundedGatherMailboxTests.swift`
- `BoundedGatherMailboxAuthorityLifecycleTests.swift`

Hard cut:

```text
GatherContractionCause
  capacityPressure
  recoveryAuthorityExhaustedTransition
  ordinaryAdmissionAlreadySealed

contractedToRecovery(revision, cause)
```

The exact state-flipping offer returns the transition case; later offers return
already sealed. No other generic key, retry, cleanup, fairness, payload, or
lifecycle behavior changes.

RED: capacity contraction and authority exhaustion are indistinguishable.

GREEN: exhaustive cause table, transition/already-sealed seed tests, switch
migration, focused generic suite, scoped lint.

Split/replan: any implementation requires exposing private stamps or changing
generic retirement/key semantics.

### B — Owner-scoped identity placement rule

There is no standalone authority framework, no constructible `*Authority`
helper per binding, and no Task-B compiler suite for surrogate issuers. Identity
construction lands with the state transition that owns it:

| Identity or proof | Sole causal owner |
| --- | --- |
| fleet and physical-slot declaration | D1 slot registry |
| desired intent and slot reservation | D1 slot registry |
| binding, control block, and native-lifetime commitment | D2a slot registry plus native-generation owner |
| contribution | atomic F1 mailbox coordination owner |
| recovery custody | C fixed recovery register |
| retirement fence and receipt | F2/H2 retirement and transfer owner |
| context-release acknowledgement | D3 native generation |
| fleet shutdown completion | F3 fleet lifecycle owner |

The repo-owned RFC 9562 UUIDv7 generator supplies opaque lifecycle identity.
Exact stored equality supplies currentness; mailbox/list order supplies FIFO;
FSEvent event IDs supply source continuity. UUID sorting is never an ordering or
authorization rule, and raw observations do not allocate UUIDs.

Each owner uses closed discriminated results for real alternatives and keeps
its minting operation non-public. Physical-slot equality, registration equality,
and caller-selected dispositions cannot produce a binding, custody identity,
receipt, acknowledgement, or shutdown completion. These properties are proven
in the owning task's unit/integration tests and with focused compiler proof only
where Swift access control is actually the boundary. Integer exhaustion is not
a product workload or acceptance gate.

Integrate A before filesystem call sites compile against the new two-argument
contracted case. D1 freezes the complete binding value contract and owns desired
reservation, but D2a is the first causal binding issuer. C and later gates
consume only bindings minted by D2a's atomic native-lifetime commitment.

### C — Isolated binding-aware fixed recovery shells

Add:

- `FixedFilesystemRecoveryEvidenceRegister.swift`
- `FixedFilesystemRecoveryEvidenceRegisterTests.swift`

After D2a and D2b freeze the binding-commitment transition, add an independently
testable register
with exactly P physical-slot shells. Bound states carry the complete slot
binding, retained evidence, one owner-minted UUIDv7 recovery-custody identity,
and the complete opaque generic recovery revision as non-authorizing metadata.
Old binding or custody acknowledgement is a typed no-op.

This component remains deliberately uncomposed until the atomic E/F1/G1 gate.
It exposes no registration-shaped initializer, overload, adapter, callback
route, or legacy compatibility surface. The existing registration-keyed
`FilesystemRecoveryEvidenceRegister` remains solely for the pre-gate dormant
mailbox and receives no new behavior.

RED/GREEN covers initial bind, record, join, snapshot, exact acknowledge,
retire, foreign fleet, undeclared slot, wrong current binding, equal generic
stamps on distinct bindings, and stale operations. Same-physical-slot binding
reuse and old-binding acknowledgement after reuse are deferred to D3. Releasing
a selected reservation is not binding reuse because a selected reservation has
no binding or native lifetime.

### D1 — Desired FIFO, reservation, and configuration contracts

Add/modify:

- `FilesystemObservationSlotRegistry.swift`
- `FilesystemObservationSlotRegistryContracts.swift` for immutable identities,
  registrations, closed results, and read-only projections
- `FilesystemObservationSlotRegistryTests.swift`
- `FilesystemSourceConfigurationReceiptTests.swift`
- focused compiler fixtures/verifier for impossible receipt combinations

Implement the fixed P=S+R pool and its host-minted UUIDv7 fleet plus physical-
slot identities, unique desired-source FIFO, selected reservation identity,
in-place desired overwrite, pre-native reservation release/failure rotation,
and withdrawal revalidation at pop/reserve. Selection reserves one exact
physical slot but does not mint a binding or control-block identity.

Strict results distinguish:

```text
deferredRetainingCurrent
deferredNonCurrent
failedRetainingCurrent
failedNonCurrent
```

Aggregate currentness derives only from those cases. D1 defines and proves the
typed configuration identities, closed disposition shapes, receipt validation,
and derived currentness/retry projection. It does not classify or retain a live
prior authority because the dormant registry has no `accepting` state yet.

D1 also enforces active-source capacity independently from physical-slot
capacity. Active-source cardinality counts each logical source owning selected,
starting, accepting, or retiring state exactly once. A deferred desired identity
does not own active-source or physical-slot capacity; it remains one bounded FIFO
node per source until reservation is eligible. The deferred-to-selected
reservation transition returns the closed `activeSourceCapacityExhausted` result
when a previously inactive source would exceed S. An already-active source may
reserve replacement overlap from only the R reserve admitted by the fixed P=S+R
pool.

Before D1 can checkpoint, aggregate receipt validation and currentness projection
are GREEN for the full closed-disposition matrix. Retry membership and the
public currentness projection must be derived from the same disposition rather
than stored as independently mutable facts. D2c owns the prior-authority
classifier and full safe/unsafe runtime matrix once its atomic gate supplies an
actual published `accepting` authority; unpublished `starting` custody must not
substitute for current product authority.

Proof uses successful vacancy-selection counts, never time. Run active-source
capacity S/S+1 independently from reserve 0/1/R/S, N+3/N+4 overwrite,
pre-commit failure rotation, withdrawal at pop/reserve, and the configuration-
receipt/currentness matrix. D2a owns the atomic native-lifetime commitment;
D2c owns safe/unsafe prior-authority classification and retain/close behavior;
D2a/D2c/D3 integration owns create/start withdrawal and failure proof.

### D2a — Sole binding commitment and unpublished native lifetime

Extend the same registry under one integration owner, but keep a separate RED/
GREEN receipt for:

- vacant, selected, starting, and retiring-unpublished states only;
- one lock-linearized `selected(reservation) -> starting(binding,
  unpublishedNativeGeneration)` transition that consumes exact reservation
  authority, mints the complete binding/control-block identities, and commits
  native-generation custody before any native create call;
- stale or withdrawn reservation rejection before commitment and total
  post-commit create/start failure routing into native retirement;
- the committed-unpublished portion of the two-started-plus-one-desired bound,
  including rejection of any third started lifetime for one source.

D1 owns the complete binding value contract but cannot mint a binding. D2a
production registry edits follow D1 under the same registry owner and are the
first causal binding issuer. Accepting, lease-drain closing, predecessor,
retirement-fence, transfer, and final-receipt states are deliberately not D2a:
they require the later native/mailbox/SourceGate authorities and land through
D2c. C begins only after D2a and D2b freeze the sole binding-commitment
transition, then remains uncomposed and production-file-disjoint until the
atomic gate. The integration gate re-reads one exhaustive D1+D2a registry
transition table and C's fixed-shell contract without composing either into the
mailbox.

D2a's committed native custody is consumed only through one fixed per-slot
native owner. Its closed `NativeCreationState` owns create-or-abandon; after
creation, its closed `NativeStartRight` owns start-or-abandon-after-create. No
copyable binding/lifetime value may call native create or start directly. The
owner survives cancellation and lost responses; cleanup values return evidence
and expose no callback-context release operation. Deinit cannot release retained
context.

`FilesystemObservationSlotRegistry` is a non-locking mutable state owner accessed
only while `FilesystemObservationMailboxCore` holds the mailbox coordination lock.
It never owns a second lock. Native create/start/stop/invalidate/barrier and
context release always execute with wrapper, recovery, and generic locks
released; only opaque reservations, drain receipts, retirement receipts, and
release acknowledgements cross that boundary.

### D2b — Registry decomposition and lexical ownership closure

This is a required structural checkpoint after D2a behavior is GREEN and before
C consumes the frozen binding contract or the atomic interface gate integrates
the registry.

Modify/add exactly:

- `Sources/AgentStudio/Core/RuntimeEventSystem/Filesystem/FilesystemObservationSlotRegistry.swift`
- `Sources/AgentStudio/Core/RuntimeEventSystem/Filesystem/FilesystemObservationSlotRegistryContracts.swift`
- `Tests/AgentStudioTests/Core/PaneRuntime/Sources/FilesystemObservationSlotRegistryTests.swift`
- `Tools/AgentStudioArchitectureLint/Sources/AgentStudioArchitectureLintCore/Rules/FilesystemObservationSlotRegistryOwnershipRule.swift`
- `Tools/AgentStudioArchitectureLint/Tests/AgentStudioArchitectureLintTests/FilesystemObservationSlotRegistryOwnershipRuleTests.swift`
- the rule registration/inventory files required by the existing architecture-
  lint framework; no app-package SwiftSyntax dependency

Execute in this order:

1. Preserve the identical D1/D2a behavior suite as the GREEN baseline.
2. Move immutable identities, registrations, closed result types, and read-only
   projections into `FilesystemObservationSlotRegistryContracts.swift`.
   `FilesystemObservationSlotRegistry.swift` retains the one primary mutable
   owner declaration, slot/FIFO/lifecycle storage, and transitions. It has no
   production extension.
3. Remove every reusable construction/issuance key, issuer, or factory. Keep
   opaque mutation capability lexical to the narrow primary declaration. The
   concrete binding, control-block identity, and native-generation identity
   constructors each have exactly one production call site inside the
   lock-linearized `selected -> starting` transition.
4. Add the focused SwiftSyntax ownership rule. It rejects mutation-owner
   extensions and construction outside the approved transition, including a
   plain same-file helper and a same-file extension. It accepts the primary
   owner with the sole approved transition and read-only contracts/projections.
5. Re-run the unchanged D1/D2a behavior suite, focused architecture-lint rule
   tests, scoped lint, and the full architecture lint before integration.

The SwiftSyntax tests include explicit source probes for: approved
`selected -> starting` construction, a plain helper bypass, a same-file
extension bypass, a second issuer/factory, and a contracts/projection mutation
attempt. Each forbidden probe must produce the expected diagnostic. This rule
is compile-time/source enforcement only; D2b adds no lock, actor, runtime key,
event path, currentness owner, or second authority.

Split/replan if construction cannot be reduced to one call site without moving
state mutation outside the registry's lock-linearized transition. Do not retain
a reusable key as a workaround.

### Atomic interface gate E/F1/G1 — Lease + paired port + dormant adapter

This is one compile-complete checkpoint, not three commits.

Modify together:

- `FSEventRegistrationControlBlock.swift`
- `DarwinFSEventRegistrationGeneration.swift` (new dormant native owner)
- `FilesystemObservationMailboxContracts.swift`
- `FilesystemObservationMailbox.swift`
- `FilesystemObservationMailboxCore.swift` (new lexical mutable storage owner)
- `FilesystemObservationSlotRegistry.swift` for serial mailbox integration
- `FilesystemObservationSlotRegistryContracts.swift` as the read-only contract
  consumed by mailbox/native integration
- `FilesystemSourceGate.swift` only for the minimal fixed-binding recovery
  value-signature migration required to keep this hard cut compile-complete;
  H2 retains sole ownership of transfer and retirement semantics
- `FilesystemRecoveryEvidenceRegister.swift` to delete the legacy
  registration-keyed implementation
- `FixedFilesystemRecoveryEvidenceRegister.swift` to promote the fixed
  implementation as the sole canonical register
- `DarwinFSEventObservationAdapter.swift`
- their focused tests and compiler fixtures

File ownership remains split without weakening authority closure:

- `FilesystemObservationMailbox.swift` remains the domain facade and paired
  callback/native port request surface; it owns no raw mutable
  coordination storage;
- `FilesystemObservationMailboxCore.swift` is the single lexical owner of the
  one coordination lock, `State`, slot registry, generic gather mailbox, fixed
  recovery register, fleet doorbell, lock-linearized paired-port construction,
  authority minting, and every mutation or dependency-calling coordination
  operation over those values;
- value contracts remain in `FilesystemObservationMailboxContracts.swift`;
- pure value-in/value-out transition planners may move to sidecar files, but
  they cannot retain mutable state, call core dependencies, mint authority,
  decide currentness, or become another coordination owner;
- slot registry, semantic replay, and fleet lifecycle remain separate owners;
- production `FilesystemActor.swift` remains untouched before W2b, and W2b adds
  the drain in `FilesystemActor+ObservationIngress.swift`.

Keep the facade below 600 lines. Extract immutable contracts, projections, and
pure planners from the core where that preserves the lexical storage boundary;
do not split the one mutable coordination owner, widen access control, or
duplicate custody merely to satisfy a line-count target. If the production actor
main file exceeds 900 lines at W2b, split it by the owners above before
checkpointing.

The gate:

0. composes the completed D1/D2a/D2b slot registry and C fixed recovery register
   under the mailbox coordination lock, cuts generic custody from registration
   keys to physical-slot keys, deletes the legacy registration-keyed register,
   and migrates every dormant caller without an overload or adapter;
1. makes a callback lease one-shot: admission available, admission consumed, or
   released;
2. adds the private nonescaping lease operation that verifies exact control
   block, registration, held/unused authority, and binding;
3. makes the mailbox factory create one paired admission port containing the
   exact doorbell operation;
4. removes the raw producer and independently pairable signaler surface;
5. keeps the lease held through offer and requested wake application, while
   releasing mailbox locks before signaling;
6. migrates the dormant adapter and all focused tests to the paired port;
7. migrates dormant SourceGate recovery value signatures from legacy
   registration-keyed snapshots to exact binding-bearing fixed snapshots without
   adding transfer, fence, retirement, or actor behavior;
8. begins D2c only where this gate now supplies real authority: successful
   native start publishes `accepting`, and close enters callback-lease-drain
   waiting through the exact native generation. It does not fabricate
   predecessor, fence, SourceGate, transfer, or final-receipt authority that
   belongs to F2/H2.

The callback entry validates exact control-block, registration, complete slot
binding, and held/unused one-shot lease authority before it invokes a
nonescaping bounded-native-capture closure. Rejected authority must not inspect
the CFArray, path pointers, flags, event IDs, or any other native callback
memory.

The same native generation/control-block assembly owns the unforgeable
`FSEventRegistrationLeaseDrainReceipt`. Its close state performs:

```text
close new lease acquisition
-> stop/invalidate stream
-> callback-queue barrier
-> zero active callback leases
-> mint exact binding-specific lease-drain receipt
```

The receipt cannot mint before any phase, cannot be constructed by registry or
test code, and is the only authority F2 accepts for a fence request. A paused
paired signal keeps its lease active and prevents receipt minting. Atomic-gate
unit proof uses an injected barrier/native-generation fake; G2 later proves the
same order against a real Darwin stream.

`DarwinFSEventRegistrationGeneration` owns the real dormant stream, retained
`Unmanaged` callback context, control block, adapter/paired port, stop/invalidate,
callback-queue barrier, lease-drain receipt, and release-once operation. It does
not conform to `FSEventStreamClient`, publish `FSEventBatch`, or modify the
production Darwin client. W2b later makes `DarwinFSEventStreamClient` compose
this proven owner while deleting legacy `CallbackContext`.

F1 mints exactly one UUIDv7 contribution identity under the core-owned mailbox
coordination lock for each accepted observation or fence immediately before the
generic offer. FIFO comes from the mailbox contribution order. A later binding
is disjoint by exact binding identity. No contribution-exhaustion state, issuer
hierarchy, or raw-event UUID allocation is introduced.

Separately, F1 consumes A's generic fleet-terminal
`recoveryAuthorityExhaustedTransition`. The exact flipping offer atomically
closes ordinary callback admission for the whole fleet in O(1), records one
fleet transition and one recovery wake, and admits no contribution payload.
Concurrent or later `ordinaryAdmissionAlreadySealed` offers create no new
custody or wake. D1 expands that fleet state into exact per-source non-current
results in bounded actor turns rather than in the callback; F3 retains the same
typed fleet-exhaustion debt through cancellation and deterministic resume.
`FilesystemObservationFleetExhaustionIntegrationTests` owns the cross-slice
oracle.

Required lock order is lease → wrapper → domain recovery/generic. Doorbell
application occurs after mailbox locks and cannot call back into lease, wrapper,
or control-block code.

Internal RED substeps are retained as receipts, but no checkpoint may expose both
raw and paired authority or leave the dormant adapter unable to compile.

GREEN:

- released/foreign/consumed/mismatched/fenced/closed cases produce no payload,
  evidence, wake, or native-reader inspection;
- an injected native-inspection ledger proves every rejected authority case
  performs zero CFArray/path/flag/event-ID reads, while accepted authority reads
  only the configured bounded prefix;
- generic fleet exhaustion proves exactly one transition/wake, zero callback
  fleet scan, zero later custody/wake, D1 non-current expansion for every bound
  source in bounded actor turns, and exact F3 incomplete/completed debt;
- deterministic pauses after authority consumption and after offer prove
  release/drain/fence/recycle cannot pass the paired signal;
- raw producer/signaler and opaque authority construction fail compiler proof;
- structural proof shows `FilesystemObservationMailboxCore` is the sole lexical
  owner of the coordination lock, `State`, slot registry, generic gather
  mailbox, fixed recovery register, fleet doorbell, and their
  mutations/dependency calls; the facade exposes only the paired-port request
  surface, and pure sidecars cannot acquire raw custody;
- bounded capture behavior from the existing adapter remains green;
- `FilesystemObservationCallbackScaleTests` proves the exact independent
  counter vector is identical at 1/100/300 slots and at the configured bound
  plus one: one bound-slot lookup/offer, the fixed recovery/generic operations,
  one immediate synchronization pass, at most one doorbell application, zero
  slot allocation, zero unrelated-slot reads/copies, and zero actor/task/domain
  calls. Elapsed time is diagnostic only; sentinel counters on unrelated slots
  remain zero;
- receipt proof rejects missing phase, duplicate, foreign binding, and early
  minting; the paired-signal pause prevents zero-lease receipt;
- contribution proof covers concurrent uniqueness, observation FIFO, exact
  binding association, and disjoint later-binding identity; F2 owns fence
  admission authority and the observation/fence ordering proof;
- generic custody is exactly
  `BoundedGatherMailbox<FilesystemObservationPhysicalSlotID,
  FilesystemObservationMailboxContribution>`; the fixed recovery register is
  the sole recovery-register implementation; no registration-keyed declared or
  recovery type, map, initializer, overload, adapter, diagnostic store, or
  legacy test helper remains;
- callback contributions carry complete binding and contribution identity, and
  no per-binding teardown can seal/invalidate/finish the fleet mailbox/doorbell;
- production remains structurally wholly legacy.

Checkpoint: credentialed fixed-slot callback admission is dormant and green.

## 5. Vertical Slice WF-B — Retirement, Replay, Lifetime, Shutdown

### H1 — Fixed per-slot semantic replay shells

Add a focused owner such as:

- `FilesystemObservationSemanticReplay.swift`
- `FilesystemObservationSemanticReplayTests.swift`

One fixed shell per physical slot retains at most one generic lease quantum of
contribution identities and accepted-prefix dispositions. It matches exact
binding plus ordered identity vector across generic retry rotation and consumer
rebind, rejects stale consumer completion, and clears only after exact whole-
lease transfer.

RED/GREEN injects failure after every strict prefix for multiple slots
concurrently. Final semantic state equals one application, unrelated slots retain
fairness, and high-water never exceeds P × maximum contributions per lease.

### F2 — Retirement fence, contraction, cleanup, predecessor

Serial integration owner modifies the registry/mailbox/lifecycle files and adds:

- `FilesystemObservationRetirementFenceTests.swift`
- `FilesystemObservationMailboxLifecycleTests.swift`

Implement observation/fence FIFO, final-fence validation, distinct
`retirementFenceAdmissionContraction` evidence, one retained pending intent,
one eligible retry per acknowledgement/cleanup turn, and cleanup-before-semantic
lease/receipt. Integrate the corresponding D2c registry transitions for
`closingAwaitingPredecessor`, `retirementFencePending`, and
`retirementFenceInstalled`; only F2 may supply the exact predecessor/fence
authority consumed by those transitions. Pending intent never stands in for
discarded observation repair.

RED/GREEN proves A→B→fence across lease quanta, contracted fence under queued
detail, cleanup custody, wake-after-unlock, and N/N+1 predecessor ordering.

### H2 — Exact SourceGate transfer and retirement receipt

Modify:

- `FilesystemSourceGate.swift`
- `FilesystemObservationLeaseTransfer.swift` (new task-free, non-actor semantic
  transfer component)
- a test-only `FilesystemObservationDrainHarnessActor` under the focused source
  test support directory
- SourceGate/actor/fence integration tests

The test harness actor owns the dormant assembly's one consumer/waiter and calls
the task-free transfer component. The transfer component preflights the whole
lease, uses H1 for idempotent semantic acceptance, synchronously obtains exact
binding-bearing SourceGate acceptance, and returns the complete transfer/retry
result. It owns no task, doorbell, actor, or second consumer.

Production `FilesystemActor.swift` remains structurally unchanged and wholly
legacy before W2b. At W2b, `FilesystemActor+ObservationIngress.swift` adds the
actor-isolated long-lived drain to the existing actor, making that production
actor the sole consumer atomically while deleting legacy ingress. No instance
can own both routes.

The atomic E/F1/G1 gate owns only the minimal exact-binding recovery value
signature migration required to delete the legacy registration-keyed recovery
types atomically. H2 remains the sole owner of `FilesystemSourceGate` semantic
transfer, repair admission, retirement, and receipt behavior. WF-C consumes the
frozen API and does not edit `FilesystemSourceGate.swift`; any newly discovered
semantic SourceGate change returns through the H2 integration owner.

H2 also supplies the exact transfer/acceptance authority consumed by D2c's
`retirementFenceTransferredAwaitingCleanup` and
`retiredAwaitingContextRelease` transitions. The registry records those closed
states but cannot mint SourceGate acceptance, final transfer, or retirement
receipt authority.

Neither the harness actor nor the eventual production actor awaits scans, Git,
Bridge, MainActor, or filesystem I/O while holding a generic lease.

Only exact whole-lease transfer + semantic acceptance + SourceGate acceptance +
zero binding retry/cleanup debt can mint the final retirement receipt.

### D2c — Authority-backed accepting, closing, predecessor, and fence integration

D2c is a serial registry-integration slice distributed across the owners that
make its transitions legitimate; it is not a pre-interface registry task and
is not a prerequisite for C or D2b.

Modify together for this focused hard cut:

- `FilesystemObservationSlotRegistryContracts.swift` for same-source
  `install | replace(exact prior binding) | remove(exact prior binding)`, strict
  post-start/unpublished/repair-handoff unions, and
  `installedAwaitingContinuityRepair`;
- `FilesystemObservationSlotRegistry.swift` for exact prior classification,
  successful-start publication, retained close obligations, desired-record
  repair custody, and handoff acknowledgement;
- `FilesystemObservationMailboxCore.swift` and mailbox contracts for
  `awaitingAcceptingPublication`, exact unpublished final receipt, and the typed
  D3 permit join;
- `DarwinFSEventRegistrationGeneration.swift` for the persistent native owner,
  one-shot create/start rights, zero-callback unpublished quiescence, and removal
  of direct/deinit context release;
- `FilesystemSourceGate.swift` for one exact idempotent
  `ContinuityRepairHandoffAuthority` admission that replays the same acceptance
  and repair generation after cancellation/lost response;
- focused lifecycle, receipt/currentness, SourceGate, compiler, and controlled-
  start tests. Production `FilesystemActor` remains unchanged until W2b.

- Atomic E/F1/G1 supplies the real native generation, paired callback port,
  start publication, callback-close, and exact lease-drain receipt required for
  `starting -> accepting -> closingAwaitingCallbackLeaseDrain`.
- F2 supplies the predecessor decision, one predecessor-free pending fence
  identity, contraction evidence, installation, and cleanup custody required
  for `closingAwaitingCallbackLeaseDrain -> closingAwaitingPredecessor ->
  retirementFencePending -> retirementFenceInstalled`.
- H2 supplies exact semantic/SourceGate acceptance, whole-lease transfer, final
  cleanup predicate, and retirement receipt required for
  `retirementFenceInstalled -> retirementFenceTransferredAwaitingCleanup ->
  retiredAwaitingContextRelease`.

Configuration intent remains source-ID keyed. `replace` rejects a prior binding
whose source ID differs from the desired configuration. A cross-kind accepted
topology revision is old-source `remove` plus new-source `install`, producing two
existing source-ID-keyed receipt entries; no configuration-operation UUID or
receipt redesign is permitted.

Successful `FSEventStreamStart` always reaches exact-owner accepting publication
before pending removal/supersession closes anything. Publication atomically
retains `current | closePredecessor | closePublished | closePredecessorAndPublished`.
Semantic transfer while merely `starting` returns
`awaitingAcceptingPublication`. Failed/abandoned create/start routes prove zero
callback/generic/semantic custody and never enter H2.

When no continuous prior exists, retain one `PendingContinuityRepairState` on
the existing desired record:

```text
pending(authority)
handoffInFlight(acceptingBinding, UUIDv7 handoffAuthority,
                desiredIdentity, topologyRevision,
                sameDesired | superseded(newAuthority) | removed(authority))
```

The registry installs `handoffInFlight` before SourceGate admission. SourceGate
must return the same acceptance and repair generation for the same exact handoff
authority. Registry acknowledgement transfers custody once and resolves the
closed successor; stale results cannot clear/recreate newer desired custody.
Pending removal consumes without a scan. Removal/supersession after handoff
starts cannot cancel or duplicate binding-local repair.

Publishing an accepting binding with this repair emits
`installedAwaitingContinuityRepair`, which represents one source ID and derives
non-current retry membership. Exact SourceGate repair completion and every
participant acknowledgement publish the compact product-current transition;
`.installed` cannot be emitted while that repair remains pending or in flight.

The registry remains the sole mutable slot-state owner and lock-linearization
point, but consumes those opaque authorities instead of minting or simulating
them. Once `accepting` exists, the registry classifies prior authority internally:
only an exact binding with identical canonical resolved root, source kind,
authorization scope, event coverage, and no exact-binding discontinuity may
retain N until N+1 starts. Removed, absent, withdrawn, discontinuous, or
configuration-incompatible N closes before retry and cannot resurrect. The GREEN
matrix covers every individual mismatch plus stale/foreign discontinuity
evidence and derives retaining/non-current results from that one classification.

D2c completes only after H2. Its GREEN receipt re-runs one exhaustive
D1/D2a/D2c lifecycle table proving the two-started-plus-one-desired bound,
oldest-first retirement, exactly one predecessor-free pending fence per source,
and that transferred-awaiting-cleanup remains retiring, slot-occupying,
predecessor-ordering, and non-reusable. No placeholder port, receipt, fence,
SourceGate acceptance, or surrogate issuer is permitted to make D2c earlier.

The D2c proof matrix adds deterministic pauses at: before native create, before
native start, after successful start/before publication, after desired-record
handoff retention, after SourceGate mutation/before registry acknowledgement,
and before D3 acknowledgement apply. It proves create/start abandonment,
create/start rejection, created-never-started closure, safe-prior retention,
repair-required absence, same-source replace rejection, cross-kind remove plus
install receipts, exact handoff replay, supersession/removal during handoff,
non-current installed-repairing receipts, and lost-response replay without
`Task.sleep`.

### D3 — Release-once, acknowledgement, tombstone, binding reuse

Extend the native generation/control block and slot registry after H2 freezes the
receipt authority and D2c completes the authority-backed lifecycle table.

The native owner consumes exactly one strict permit:

```text
NativeRetirementPermit
  = fenceBacked(existing H2 final receipt)
  | unpublished(exact unpublished final receipt)
```

The native owner releases retained callback context once or records exact
never-materialized finalization, then mints and retains the exact UUIDv7 release
acknowledgement with the same permit-lineage discriminant.
No other owner can construct it. The registry applies it once, installs one
fixed completion tombstone, returns `alreadyApplied` for lost/repeated response
while vacant, and returns typed stale after reuse. D3 is the only owner allowed
to recycle a physical slot after a binding/native lifetime exists. A selected
reservation can release directly because no binding exists. Only the
acknowledged vacant state can later participate in another native-lifetime
commitment, issue a new UUIDv7 binding, and rebind the corresponding fixed
recovery shell.

RED/GREEN proves neither H2 nor unpublished receipt alone can recycle;
acknowledgement cannot mint before native release-once/finalization; matching
acknowledgement applies once; foreign binding, permit lineage, fence, or release
identity does nothing; pending desired-record repair survives unpublished D3;
no rebind occurs before acknowledgement; rebind installs a new exact binding;
old binding/custody/receipt/acknowledgement is stale; and native context release
remains exactly once. Deinit is not the oracle.

### F3 — Fleet shutdown debt and deterministic resume

Add:

- `FilesystemObservationFleetLifecycle.swift`
- `FilesystemObservationFleetLifecycleTests.swift`

Own typed completed/incomplete shutdown results. The snapshot references existing
slot/native/generic/replay/SourceGate/receipt owners and never duplicates payload
custody. Requester cancellation cannot cancel the internal drain. Explicit
resume and custody-completion events progress without a timer or new source
event. Only completed authorizes global seal, invalidation, and doorbell finish.

Parameterized RED/GREEN covers every debt class, including fleet generic
exhaustion. Persistence and silent invalidation are forbidden.

### G2 — Real dormant Darwin lifecycle integration

Add/extend:

- `DarwinFSEventObservationLifecycleIntegrationTests.swift`
- Darwin stream tests only as needed for the isolated assembly

Use a unique temporary local root and bounded event/state waits. Prove real
create/start, bounded native capture, close lease acquisition, stop/invalidate,
callback queue barrier, zero lease receipt, fence, SourceGate acceptance,
cleanup, final receipt, release-once acknowledgement, and context release.

The test uses no `Task.sleep`. If deterministic FSEvents delivery cannot pass in
the focused runner, the authoritative required native lane is:

```bash
mise run test-large -- --filter 'DarwinFSEventObservationLifecycleIntegrationTests'
```

W1b dormant readiness is blocked until that real Darwin proof passes. Do not
substitute simulation, a sleep-based test, or a discretionary skip.

W1b dormant ready requires A, B, C, D1, D2a, D2b, atomic E/F1/G1, H1, F2,
H2, D2c, D3, and G2, plus structural proof that production remains wholly
legacy. Adapter unit tests alone are insufficient. F3 fleet shutdown is W2a
mechanics, not W1b readiness.

## 6. Vertical Slice WF-C — W2a Replacement And Repair Mechanics

Complete the isolated W2a system after WF-B:

- finish D1/D2a/D2c/D3 configuration/replacement integration against the real
  recycle receipts;
- add `WorktreeContentRepairConsumerRegistry.swift` and
  `FilesystemContentRepairProjector.swift`;
- consume the frozen exact binding-bearing `FilesystemSourceGate` acceptance
  API; WF-C does not edit the SourceGate owner;
- add participant registry/projector/integration tests.

The independent participant table covers pane/filesystem projection, Git, and
conditionally retained Bridge content. Applicability, late registration,
current, non-current-with-retry, not-applicable, withdrawal, replacement
transfer, rejection, and stale completion are exhaustive. UI disappearance is
never an acknowledgement; Git-only repair never returns a registered worktree
to healthy.

W2a mechanics complete requires the exact W1b dormant-ready gate plus F3 fleet
shutdown and WF-C participant registry/projector integration. Production still
uses only the legacy callback protocol.

Planned exact suites:

- `WorktreeContentRepairConsumerRegistryTests`
- `FilesystemContentRepairProjectorTests`
- `RegisteredWorktreeRepairIntegrationTests`

Each exact filter must discover at least one named test and the integration
oracle must enumerate the captured participants independently from production.

## 7. Vertical Slice WF-D — Deferred Atomic W2b Cut

W2b waits for W5 pane projection, W9 Git, W10 Bridge, and WF-C.

One integration owner changes together:

- `FSEventStreamClient.swift`
- `DarwinFSEventStreamClient.swift`
- `FilesystemActor.swift`
- `FilesystemGitPipeline.swift`
- boot/runtime composition
- controllable/silent fakes
- production watched-folder/repair integration and architecture tests

The pre-cut RED proves production is wholly legacy. The post-cut GREEN deletes
`FSEventBatch`, legacy callback `AsyncStream`, `CallbackContext`, old actor
ingress, and every bypass while installing the fixed fleet mailbox, adapter,
one actor drain, SourceGate, and exact live participant set in the same commit.

No feature flag, compatibility shim, partial migration, or fallback to legacy
delivery is allowed. If the cut fails, revert the complete W2b checkpoint.

W2b establishes product reachability and correctness eligibility only. Victoria
performance attribution remains a later W12/DQ1/IG2 gate.

## 8. Execution DAG And Write Ownership

The executor owns this plan's task decomposition and dependency order. The
executor may split, rename, or reorder tasks without reconvergence when the
accepted spec outcome, authority boundaries, hard-cut scope, safety invariants,
and proof gates remain unchanged. A change to any of those spec-level contracts
still requires reconvergence; plan maintenance by itself does not.

```text
gate 0: verify HEAD, accepted hashes, dirty adapter/test, first RED inventory
  |
  +-- A generic contraction cause ------------------+
  |                                                 |
  +-- B owner-placement rule (no implementation) ---+
                                                    |
integration gate 1: A GREEN + owner map audit ------+
  |
  +-- D1 reservation/desired/currentness ------------+
              |
              +-- D2a selected->starting commitment -+
                          |
                          +-- D2a behavior GREEN
                                  |
                          D2b decompose/remove key
                                  |
                          D2b ownership lint GREEN
                                  |
                          +-- C isolated fixed recovery shells
  |
integration gate 2: shared contract freeze; no composition
  |
atomic interface gate: integrate C + D1/D2a/D2b + E + F1 + G1;
                       begin D2c accepting/lease-drain closing;
                       delete legacy recovery register
  |
  +-- H1 semantic replay --------+
  +-- F2 retirement fence + D2c predecessor/fence
                                 |
                         H2 SourceGate/receipt + D2c transfer/final receipt
                                 |
                         D2c lifecycle table GREEN
                                 |
                         D3 release/tombstone
                                 |
  +-- G2 real Darwin proof -> W1b dormant-ready gate -> WF-C participants --+
  |                                                                          |
  +-- F3 fleet shutdown ------------------------------------------------------+
                                                                             |
                                                   W2a mechanics-complete gate
                                 |
             W5 + W9 + W10 -----+
                                 |
                         WF-D atomic W2b cut
```

Safe parallelism:

- A may proceed independently of the owner-placement documentation correction;
- after D1 freezes binding types, C test/oracle preparation may proceed beside
  D2a, but binding-dependent C implementation and executable proof wait for
  D2a's sole binding-commitment transition and D2b's lexical-ownership closure;
  no surrogate binding factory is allowed;
- H1 || F2 after the atomic interface gate;
- F3 || G2 after D3;
- participant-registry files may run beside actor work only after the exact
  SourceGate acceptance interface freezes and neither lane edits the other owner.

Serial choke points:

- generic contracted-case compile fanout;
- the E/F1/G1 authority interface cut;
- promotion of C, deletion of the legacy recovery register, and registry/mailbox
  lock-linearized composition inside that same atomic gate;
- D2c registry/mailbox/native/SourceGate lock-linearized integration through
  atomic E/F1/G1, F2, and H2;
- the single actor consumer/drain integration;
- W2b production cut.

No parallel lane edits `FilesystemObservationMailbox.swift`,
`FilesystemObservationMailboxCore.swift`, `FilesystemObservationSlotRegistry.swift`,
`FSEventRegistrationControlBlock.swift`, or `FilesystemActor.swift` through the
same integration gate.

## 9. Requirements / Proof Matrix

| Claim | Source | Owner | RED/GREEN proof | Layer / freshness |
| --- | --- | --- | --- | --- |
| typed fleet exhaustion reaches exact fleet debt | child Fixed Slot Identity | A + atomic F1 + D1 + F3 | A returns exact transition/already-sealed cause; F1 records one transition/wake and closes callback authority; D1 derives every source non-current; F3 retains exact exhaustion debt | unit/compiler/integration; current HEAD/hash |
| fixed binding rejects ABA | child Fixed Slot Identity | D2a + C + D3 | D2a exact UUIDv7 binding/stored-equality currentness; C binding-aware custody; D3 acknowledged same-slot reuse and old binding/custody/receipt/ack rejection | unit/compiler/integration |
| callback admission is O(1) and credentialed | child One-Shot Callback Authority | atomic E/F1/G1 | held/released/foreign/consumed race; 1/100/300 operation count | unit/compiler/microbenchmark |
| mailbox coordination has one lexical storage owner | child mailbox facade/core contract | atomic E/F1/G1 | behavior and callback counts unchanged; facade owns only the paired-port request surface; core alone owns one lock, state, dependencies, authority minting, construction, and mutations; sidecars are pure | unit/compiler/structural |
| desired replacement is fair and currentness strict | child Capacity Contract; parent configuration | D1 + D2a/D2c/D3 integration | active-source S/S+1 independent from reserve 0/1/R/S, q+1 selections, reservation-only withdrawal, atomic native-lifetime commitment, withdrawal at create/start, safe/unsafe currentness matrix | unit/native integration |
| slot mutation and binding construction have one lexical owner | child slot-registry ownership contract | D2b | unchanged D1/D2a behavior GREEN; contracts/projections separated; reusable key absent; approved-transition probe passes; plain-helper, same-file-extension, second-issuer, and projection-mutation probes fail | unit/SwiftSyntax architecture lint; before integration |
| binding lifecycle is bounded and ordered | child Closed Slot Lifecycle | D2c + atomic E/F1/G1 + F2/H2 | two started + desired, predecessor/pending fence, transferred-cleanup category, no authority before its owning gate | unit/integration |
| whole-lease retry is idempotent for many slots | child Contribution And FIFO Contract | H1 | strict-prefix failure, rotation/rebind, P×lease bound | integration |
| contracted fence preserves intent and repair | child Native Fence And Pending Intent | F2/H2 | capacity contraction, cleanup, SourceGate, final receipt | integration |
| native context release is causal and idempotent | child Closed Slot Lifecycle and Actor Transfer And Retirement Receipt | D3 | release count one, receipt/ack replay, stale after reuse | unit/native integration |
| shutdown never loses debt | child Fleet Shutdown | F3 | every debt class, cancellation, resume without event/timer | integration |
| real Darwin lifetime matches receipts | child callback/fence contract | G2 | temporary root and explicit teardown ledger | real-boundary integration |
| repair health requires exact participants | parent repair matrix | WF-C | participant applicability/withdrawal/transfer table | unit/integration |
| production has exactly one ingress | hard-cut rule | WF-D | pre-cut legacy-only RED; post-cut fixed-only GREEN | structural/integration/smoke |
| ingress owner graph is exclusive | child callback/consumer contract | H2/WF-D | pre-W2b production actor has legacy ingress only and dormant harness has exactly one fixed consumer/waiter; post-W2b production actor has fixed ingress only; no instance can own both routes | compiler/structural/integration |

Every behavior/type/lint change requires named RED and identical-command GREEN.
Each receipt records HEAD, current accepted hashes, exact test names/counts,
command/exit code, independent oracle, and higher layer deferred/not applicable.
Broad substring filters that discover zero tests are failure.

Add a manifest-driven proof runner:

- `scripts/verify-filesystem-observation-proof-suites.sh`
- `Tests/ProofManifests/FilesystemObservationSuites/manifest.txt`

The runner accepts `--gate pre-w2b` or `--gate w2b`, executes every manifest
task/selector including the real-Darwin `test-large` selector, parses the test
summary, and fails when a selector discovers or executes zero tests. Its
self-test substitutes one deliberately nonexistent selector and must fail.

The pre-W2b manifest includes
`FilesystemObservationIngressOwnershipArchitectureTests`, which proves live
production composition is legacy-only and the dormant harness owns exactly one
fixed consumer/waiter. The atomic-gate structural suite fails if the legacy
registration-keyed recovery type, initializer, diagnostic map, or test helper
remains, or if any callback or consumer can select between legacy and fixed
recovery implementations. At W2b, the ownership suite cuts to production fixed-
only and proves no instance can construct both routes.

## 10. Validation Gates

Per task:

1. exact focused unit/state/compiler RED then GREEN;
2. focused compiler/access-control proof only when an owning lifecycle API uses
   Swift access control as its construction boundary;
3. for D2a, preserve behavior GREEN before D2b decomposition; then remove the
   reusable key, pass the focused ownership-rule probes, and only then begin C
   or registry integration;
4. scoped lint using Swift files only;
5. exact touched-suite integration;
6. checkpoint commit only after compile-complete local proof.

Combined pre-W2b gate:

```bash
mise run test -- --filter 'BoundedGatherMailbox'
mise run test -- --filter 'FilesystemObservation'
mise run test -- --filter 'FilesystemSourceGate'
mise run test -- --filter 'FSEventRegistrationControlBlock'
mise run test -- --filter 'DarwinFSEventObservation'
mise run test -- --filter 'FilesystemObservationCallbackScaleTests'
mise run test -- --filter 'FilesystemObservationFleetExhaustionIntegrationTests'
mise run test -- --filter 'WorktreeContentRepairConsumerRegistryTests'
mise run test -- --filter 'FilesystemContentRepairProjectorTests'
mise run test -- --filter 'RegisteredWorktreeRepairIntegrationTests'
mise run test-large -- --filter 'DarwinFSEventObservationLifecycleIntegrationTests'
bash scripts/verify-filesystem-observation-proof-suites.sh --gate pre-w2b
mise run lint
mise run test-fast
```

The executor records actual discovered suite names and counts. Markdown spec/
plan files are validated with `git diff --check`; they are not passed to the
Swift-only scoped lint runner.

W2b additionally requires full focused integration, app smoke, current marker-
scoped observability, and structural legacy deletion. It still earns no final
performance claim.

No test uses `Task.sleep`. Ordering uses permanent value-free synchronization
seams, injected clocks, exact receipts, or event/state waits with bounded timeout
only for hang detection.

## 11. Security, Reliability, Rollback

- Untrusted FSEvent data never selects slot/binding/contribution authority.
- Exact lease/binding rejection occurs before native pointer inspection.
- Callback telemetry is aggregate and bounded; no raw paths, registrations,
  slot/binding IDs, errors, or payloads enter OTLP.
- Wrapper/lease lock order and signal-after-unlock are mandatory.
- `Unmanaged` context remains retained until final receipt and release-once.
- Fleet exhaustion is bounded actor work, not a callback fleet scan.
- A-I are dormant/isolated and may be reverted only as complete dependency-
  ordered checkpoints. Do not cherry-pick half of the interface or lifecycle
  integration gates.
- W2b rollback reverts the complete production hard-cut commit. A hybrid is
  never a recovery state.

Stop and return to planning/spec if:

- Darwin barrier + lease accounting cannot prove zero callback authority;
- paired authority requires raw escape, lock inversion, or a strong cycle;
- replay exceeds P × lease quantum or needs binding-lifetime history;
- generic FIFO/cleanup cannot prove fence finality without per-key lifecycle;
- SourceGate acceptance requires heavy await under generic lease;
- context acknowledgement cannot be minted after release-once;
- shutdown needs silent invalidation, persistence, or a second payload owner;
- W2b cannot delete every legacy bypass atomically.

## 12. Checkpoint And Review Rhythm

Allowed verified implementation checkpoints:

```text
A/D1/D2a     compile-complete owner-local behavior commits
D2b          registry decomposition + focused ownership-lint commit
C            fixed recovery-shell commit after D2b contract freeze
E/F1/G1      one atomic authority-interface commit; begin D2c accepting/closing
H1/F2/H2     proof-local commits with one D2c integration owner
D2c          exhaustive authority-backed lifecycle-table checkpoint after H2
D3           release/tombstone commit
F3/G2        shutdown and real-Darwin proof commits
W1b          dormant integration receipt checkpoint
WF-C         W2a mechanics receipt checkpoint
WF-D         later atomic W2b production checkpoint
```

Do not commit red-only trees. Preserve RED evidence in the task receipt. Run an
implementation review after the lifecycle interface gate, after W2a mechanics,
and after W2b. Broad lint codification remains last; small compiler/access-
control proof belongs only to a real owner boundary and never substitutes for
the owner's transition tests.

## 13. Completion Boundary

This focused plan is complete when:

- W1b dormant-ready and W2a mechanics-complete receipts are current and reviewed;
- all owned unit/compiler/real-boundary proof and scoped/full relevant lint pass;
- production is still structurally wholly legacy;
- no raw producer/signaler or old per-generation seal plan/code remains in the
  dormant assembly;
- W2b remains explicitly blocked on W5/W9/W10 rather than partially wired.

The broader performance goal remains open. Product reachability, Victoria
baseline/candidate comparison, real-root qualification, native typing/cursor
feel, full validation, implementation review, and PR readiness remain later
gates owned by the parent plan.
