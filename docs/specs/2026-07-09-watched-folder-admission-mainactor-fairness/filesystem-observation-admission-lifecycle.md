# Filesystem Observation Admission Lifecycle

Date: 2026-07-12
Status: accepted focused technical contract
Parent: [Watched-Folder Admission and MainActor Fairness](watched-folder-admission-mainactor-fairness.md)

## Purpose

This slice owns the callback-authority, fixed-slot mailbox, per-source
replacement, retirement-fence, and native-context lifetime contract. The parent
spec owns product intent, source repair semantics, actor reduction, topology,
MainActor fairness, and end-to-end proof.

One source replacement must not rebuild or seal a fleet mailbox containing
hundreds of unrelated registrations. The selected design keeps one fixed fleet
mailbox, one payload-free doorbell, one long-lived actor drain, and one global
capacity/fairness owner. Per-source generations bind to opaque predeclared
physical slots and retire through ordered fence contributions.

## Boundary Map

```text
Darwin callback generation
  owns: stream, control block, callback leases, exact registration token
  exposes: one bound callback admission port and native lease-drain receipt

                    bounded credentialed observation
                                  |
                                  v
FilesystemObservationMailbox
  owns: domain facade and paired callback/native port request surface
                                  |
                                  v
FilesystemObservationMailboxCore + FilesystemObservationSlotRegistry
  core owns: one lexical coordination lock + State; sole custody of the slot
             registry, fixed recovery register, fleet gather mailbox, and doorbell
  registry owns: fixed slot pool, exact UUIDv7 binding currentness, per-slot
                 lifecycle, and pending retirement-fence intents
  together own: bounded semantic-transfer identities and exact recovery evidence
  expose: closed facade operations, one actor consumer, and source-slot
          retirement requests/receipts

                                  |
                                  v
BoundedGatherMailbox<FilesystemObservationPhysicalSlotID,
                     FilesystemObservationMailboxContribution>
  owns: fixed keys, per-key FIFO, bounded global/per-key custody,
        whole-lease retry/ack, fair ready-key rotation
  does not own: registrations, UUIDv7 binding identity, callback authority,
                retirement

                                  |
                                  v
FilesystemActor + FilesystemSourceGate
  own: bounded semantic transfer, exact recovery acceptance,
       retirement-fence completion, idempotent retirement receipt

Global mailbox seal is whole-fleet shutdown only.
```

## Rejected Grouping Models

### Fleet cohort rollover

Replacing one registration would stop/recreate every control block, stream,
token, and callback port in the cohort. Replacement cost becomes O(fleet),
temporarily duplicates unchanged native observations, and turns ordinary
repository discovery/removal into fleet-wide pressure. Rejected.

### One mailbox per source

Per-source retirement becomes simple, but global contribution/item/byte
capacity, fair ready-key rotation, and one long-lived drain disappear. Restoring
them requires a second permit ledger plus a wake multiplexer or one task per
source, recreating the fleet mailbox with more cross-lock state. Rejected.

## Fixed Slot Identity

The generic mailbox key is not `FSEventRegistrationToken`. It is an immutable
opaque physical slot declared when the fleet mailbox is constructed:

```text
FilesystemObservationPhysicalSlotID
  fixed pool-local slot identity

FilesystemObservationFleetMailboxIdentity
  host-minted UUIDv7

FilesystemObservationSlotBinding
  fleetMailboxIdentity
  physicalSlotID
  bindingIdentity: host-minted UUIDv7
  exact FSEventRegistrationToken
  controlBlockIdentity: host-minted UUIDv7
```

Physical-slot equality never authorizes an operation. Every callback port,
observation contribution, retirement fence, domain drain lease, recovery
snapshot/revision, SourceGate acceptance, retirement request/receipt, and
context-release acknowledgement carries or opaquely binds the complete slot
binding.

Fleet, binding, and control-block identities use the repo-owned RFC 9562 UUIDv7
generator. Callback paths and untrusted filesystem input cannot select them.
UUIDv7 provides opaque, time-sortable lifecycle identity; it is not FIFO or
currentness authority. The fixed-slot owner stores the exact current binding and
validates equality. Mailbox order and FSEvent watermarks remain the ordering
sources. Raw observations do not allocate UUIDs.

A generic recovery revision remains opaque generic-custody metadata. The domain
register retains the complete `GatherRecoveryRevision` for equality without
extracting or interpreting its private stamp. Generic revision equality never
authorizes a domain operation across bindings. Cross-reuse ABA authority is the
complete slot binding plus a domain recovery-custody identity.

The domain register has one fixed shell per physical slot:

```text
FilesystemRecoverySlotState
  = vacant
  | boundClear(binding)
  | boundRetained(binding, evidence, domainRecoveryCustodyIdentity,
                  genericRecoveryRevision)

bind(binding)
record(binding, evidence)
snapshot(binding)
acknowledge(exactSnapshot)
retire(binding)
```

Old-binding operations return typed mismatch without mutation. The domain
recovery register mints one UUIDv7 custody identity when it creates new retained
custody. Opaque generic recovery revisions are current-custody metadata and
never authorize across bindings.

Integer exhaustion is not a product workload, performance target, or acceptance
gate. Existing checked integer arithmetic remains defensive implementation
hygiene where a generic primitive requires it, but the filesystem lifecycle does
not add surrogate authority objects, shutdown states, benchmarks, or compiler
fixtures for astronomically unreachable counter exhaustion.

The generic mailbox adds only the minimal public contraction-cause result needed
to expose its existing state transition atomically:

```text
GatherContractionCause
  = capacityPressure
  | recoveryAuthorityExhaustedTransition
  | ordinaryAdmissionAlreadySealed

GatherAdmissionDisposition.contractedToRecovery(revision, cause)
```

The exact offer that flips `ordinaryAdmissionSealed` returns
`recoveryAuthorityExhaustedTransition`; later contracted offers return
`ordinaryAdmissionAlreadySealed`. The wrapper records the fleet transition once
under its existing lock. This adds no dynamic key, per-key seal, retirement,
retry, or payload-inspection API and exposes no private recovery stamp.

## Capacity Contract

Let:

```text
S = maximum simultaneously registered sources
R = replacement reserve slots
P = fixed physical slot count = S + R
```

`P`, `S`, and `R` are compile-time/AppPolicies constants selected by the
calibration manifest; they do not reuse the legacy 128-envelope or downstream
256-path chunk constants. The pool declares all `P` generic keys and recovery
slots once. Callback traffic cannot allocate keys.

Let each generic per-physical-slot ordinary bound be `Bcontribution`, `Bitem`,
and `Bbyte`. The closed lifecycle permits at most two started bindings and one
predecessor-free pending fence intent for one logical source. Its static
derived maximum is therefore:

```text
logicalSourceOrdinaryMaximum = 2 * perPhysicalSlotOrdinaryMaximum
logicalSourceLifecycleMaximum = logicalSourceOrdinaryMaximum
                              + one fixed PendingRetirementFence
                              + one newest desired identity

fleetSemanticReplayIdentityMaximum =
  P * maximumContributionsPerGenericLease
```

This is a proof over existing slot state, not a mirrored wrapper counter. The
generic mailbox remains the sole owner of ordinary custody counts. Exact-bound
and bound-plus-one calibration must cover both bindings together.

- New sources consume active-source capacity, not replacement reserve.
- A replacement reserves a distinct vacant slot before publishing N+1 callback
  authority whenever reserve capacity exists.
- Guaranteeing simultaneous immediate replacement for all S sources requires
  `P >= 2S`.
- When `R < S`, at most R replacements may have overlapping current/retiring
  generations. Additional replacements retain one newest non-started desired
  identity per source and return one of the exhaustive replacement results:

```text
FilesystemObservationReplacementResult
  = installed(binding)
  | installedAwaitingContinuityRepair(binding, repairHandoffAuthority)
  | deferredRetainingCurrent(existingBinding, desiredIdentity, reason)
  | deferredNonCurrent(desiredIdentity, reason)
  | failedRetainingCurrent(existingBinding, desiredIdentity, stage)
  | failedNonCurrent(desiredIdentity, stage)

reason = replacementSlotCapacity | predecessorRetirement
stage = reserve | create | start
```

  Only `deferredRetainingCurrent` and `failedRetainingCurrent` preserve old
  authority/currentness; unsafe or absent N uses the non-current cases.
  `installedAwaitingContinuityRepair` proves native installation and accepting
  publication but derives non-current retry membership until the exact repair
  generation and every participant acknowledgement complete.
- Deferred desired state and reservation results are closed:

```text
FilesystemObservationDesiredSlotState
  = none
  | deferred(desiredIdentity, intentAuthority,
             uniqueQueueNode, firstDeferredOrder)
  | selected(desiredIdentity, intentAuthority, slotReservation)
  | starting(desiredIdentity, intentAuthority,
             reservedBinding, unpublishedNativeGeneration)

FilesystemObservationSlotReservation
  = exact fleet mailbox identity
  + exact physical slot identity
  + exact desired identity
  + opaque slot-reservation authority

FilesystemObservationSlotReservationResult
  = reserved(slotReservation)
  | deferredBehindSlotCapacity
  | activeSourceCapacityExhausted
  | sourceAlreadyHasCurrentAndRetiring
  | fleetAdmissionExhausted
  | shuttingDown

FilesystemObservationDesiredWithdrawalResult
  = withdrewDeferred
  | releasedSelectedReservation
  | retiringUnpublishedGeneration
  | alreadyAbsent
  | staleDesiredIdentity
```

- Deferred sources occupy one unique FIFO node. N+3/N+4 overwrite the desired
  identity in place without changing queue rank. Removal withdraws the node
  before returning. A pop validates the exact current desired identity; stale
  nodes cannot accumulate.
- A source at zero-based rank `q` is selected within `q + 1` successful vacant-
  slot selections, conditional on slots actually becoming reusable. A selected
  source owns one reservation but no slot binding or native lifetime. Withdrawal
  or failure before native-lifetime commitment releases that reservation and
  rotates an otherwise eligible source to the FIFO tail; one failed source
  cannot monopolize a vacancy. Once native-lifetime commitment begins, create or
  start failure rotates the desired source but the physical slot remains
  unavailable until the unpublished native generation retires and D3 applies
  its exact context-release acknowledgement. Each actor turn performs at most
  one selection. Fairness is counted in selections, never elapsed time.
- FIFO pop transitions `deferred -> selected` under the registry lock and keeps
  one exact intent authority through reserve and native-lifetime commitment.
  Withdrawal before commitment invalidates the authority. The registry consumes
  the exact selected reservation and, in one
  lock-linearized transition before any native create call, mints the complete
  binding/control-block identities and commits exact unpublished-native-
  generation custody. The fixed per-slot native owner is materialized only from
  that non-forgeable committed custody and consumes one-shot create-or-abandon
  and start-or-abandon rights. A copied completion cannot create or start after
  abandonment, acknowledgement, or reuse. Every committed but unpublished
  native generation follows its exact D3 route even when
  `FSEventStreamCreate` returns no stream. Failure requeues only if the same
  desired identity remains requested; withdrawn work never rotates back into
  the FIFO.
- Global contribution/item/byte capacity remains independent from slot
  cardinality and is enforced by the one generic mailbox.

Before reservation, the lifecycle classifies old authority:

```text
FilesystemObservationPriorAuthorityDisposition
  = retainUntilReplacementStarts
  | closeBeforeReplacementRetry(reason)
```

`retainUntilReplacementStarts` is legal only when accepted topology still
requests the same canonical root, source kind, authorization scope, and event
coverage and the old generation has no discontinuity. Same-root regeneration
may retain N. Removal, canonical-root change, source-kind/authorization change,
or invalidated/discontinuous N must close before retry and remain visibly
non-current.

For retainable N, reserve/create/start N+1 occurs before N closes; reserve,
create, or start failure leaves N authoritative and returns a typed deferred or
failure disposition. Successful start always publishes N+1 authority before
pending removal or supersession closes N+1, then closes N when required. For
unsafe N, close/barrier/lease drain linearizes before deferred replacement; no
failure may resurrect it. Removal closes N without creating desired state.

`replace` requires the exact prior binding and desired configuration to have the
same `FilesystemSourceID`. Because source kind is part of that identity, a
cross-kind topology revision is exact `remove(oldSourceID)` plus exact
`install(newSourceID)`. The existing source-ID-keyed configuration receipt
contains `removalComplete` for the old source and the exact new-source
installed/deferred/failed disposition under one accepted topology revision. No
cross-source operation identity or inferred logical source key exists.

### Native owner, successful-start publication, and unpublished retirement

Native-lifetime commitment installs one fixed per-slot owner with closed rights:

```text
NativeCreationState
  = available(exact binding and generation)
  | abandoned(exact abandonment completion)
  | rejected(exact create rejection completion)
  | created(exact stream, NativeStartRight)

NativeStartRight
  = available(exact created stream)
  | attempted(exact start completion)
  | abandonedAfterCreate(exact created-never-started quiescence)
```

The owner survives caller cancellation and lost responses. Cleanup values expose
evidence, never callback-context release. Deinitialization cannot release a
retained context. Missing causal evidence remains fixed slot-held shutdown debt.

Darwin begins callbacks only after successful `FSEventStreamStart`. Successful
start may admit bounded callback custody before the registry publishes
`accepting`; failed start admits none. Semantic transfer while `starting` returns
`awaitingAcceptingPublication` and retries without a semantic sink or SourceGate
clear. Exact-owner accepting publication must win after successful start and
atomically retains:

```text
FilesystemObservationPostStartDisposition
  = current
  | closePredecessor(exact N)
  | closePublished(exact N+1)
  | closePredecessorAndPublished(exact N, exact N+1)
```

Pending removal or supersession cannot convert successful start into
unpublished cleanup. Lost responses replay every exact close obligation and
predecessor N remains oldest.

Unpublished retirement is limited to terminal paths that prove zero callback
admission, generic leases, semantic activity, and unpublished replay:

```text
UnpublishedNativeQuiescence
  = creationAbandoned(exact consumed create right; no context existed)
  | createRejected(exact create completion; retained context, no stream)
  | createdNeverStartedClosed(exact consumed start right;
      invalidate/barrier/zero-lease/stream-release completion)
  | startRejectedAfterDrain(exact invalidate/barrier/zero-lease/
      stream-release completion)

UnpublishedContinuityDisposition
  = retainedPriorRemainsAuthoritative(exact prior accepting binding)
  | desiredRetryRequiresNoRepair(exact desired identity and configuration)
  | withdrawnSourceRequiresNoRepair(exact withdrawal or removal authority)
  | pendingRepairRetained(exact PendingContinuityRepairAuthority)
```

A still-desired source without a continuous prior retains exactly one pending
repair authority on its desired-configuration record; the failed binding owns no
SourceGate and may retire promptly. Pre-create retry and exact removal require no
repair. Removal consumes pending repair because no source remains to make
current.

Repair handoff is fixed-cardinality and replayable:

```text
PendingContinuityRepairState
  = pending(exact PendingContinuityRepairAuthority)
  | handoffInFlight(
      exact accepting binding,
      exact UUIDv7 ContinuityRepairHandoffAuthority,
      exact desired identity and accepted topology revision,
      ContinuityRepairSuccessorDisposition)

ContinuityRepairSuccessorDisposition
  = sameDesired
  | superseded(exact newer PendingContinuityRepairAuthority)
  | removed(exact removal authority)
```

The registry retains `handoffInFlight` before the actor calls SourceGate. The
SourceGate admits that exact handoff idempotently and replays the same repair
generation/acceptance after cancellation or lost response. Exact registry
acknowledgement transfers custody to the accepting binding and resolves the
closed successor. Stale results cannot clear or recreate newer desired custody.

The source-ID-keyed configuration disposition adds one honest installing state:

```text
installedAwaitingContinuityRepair(
  exact desired configuration,
  exact UUIDv7 ContinuityRepairHandoffAuthority)
```

It derives non-current retry membership. `.installed` cannot appear for that
source until no continuity repair is pending or in flight. Exact SourceGate
repair completion plus every participant acknowledgement publishes the compact
product-current transition; immutable historical receipts are not mutated.

The registry may mint an unpublished final receipt only after exact native
quiescence, exact continuity disposition, zero binding-local retry/cleanup debt,
and predecessor eligibility. Pending continuity repair may survive only in the
bounded desired-record state above.

```text
NativeRetirementPermit
  = fenceBacked(existing H2 final receipt)
  | unpublished(exact unpublished final receipt)
```

The persistent native owner consumes the exact permit and is the sole context-
release/finalization owner. It retains one exact UUIDv7 acknowledgement. Under
the mailbox-core lock, exact application preserves desired-record repair,
removes only the oldest eligible retirement, installs one fixed tombstone,
vacates the slot, and returns replayable `alreadyApplied`. A new binding makes
every old value typed stale. Unpublished retirement never satisfies or weakens
the H2 accepting-lineage/final-fence equivalence.

## Closed Slot Lifecycle

```text
vacant(lastCompletedRelease)
  -> selected(slotReservation)
  -> starting(binding, unpublishedNativeGeneration)
  -> accepting(binding, callbackAdmissionPort)
  -> closingAwaitingCallbackLeaseDrain(binding)
  -> closingAwaitingPredecessor(binding, leaseDrainReceipt)
  -> retirementFencePending(binding, leaseDrainReceipt, fenceIdentity)
  -> retirementFenceInstalled(binding, fenceIdentity)
  -> retirementFenceTransferredAwaitingCleanup(binding, finalTransfer)
  -> retiredAwaitingContextRelease(binding, retainedFinalReceipt)
  -> vacant

generic recovery-authority exhaustion
  -> fleetAdmissionExhausted(exact retained fleet debt)
```

A selected reservation may return directly to `vacant` because no binding or
native lifetime exists yet. There is no direct `starting -> vacant`,
`accepting -> vacant`, timeout expiry, or binding reuse before native
context-release acknowledgement. Reservation and native-lifetime-commitment
transitions occur under the wrapper lock. Old and new generations for one source
use distinct physical slots while both exist.

### Slot-registry ownership and construction closure

The slot registry is decomposed by authority rather than by lifecycle phase:

```text
FilesystemObservationSlotRegistryContracts.swift
  owns: immutable identities, registrations, closed result types,
        and read-only state projections
  cannot own: mutable slot/FIFO state, mutation capability, or identity minting

FilesystemObservationSlotRegistry.swift
  owns: mutable slot/FIFO/lifecycle state and every state transition
  exposes: closed transition methods and read-only projections only
```

The mutable owner is one narrow primary declaration in one file. Production
extensions of that owner are forbidden. Opaque mutation capability remains
lexically private to that declaration; it is not returned, injected, stored in
a reusable issuer, or shared with the contracts/projection file. A reusable
construction or issuance key is not part of the accepted architecture.

The lock-linearized `selected -> starting` transition is the only operation
that may mint the UUIDv7 binding, control-block, and native-generation
identities. The registry passes those identities in one closed typed bundle to
the stateless admission planner. The planner constructs the complete binding
and starting-lifetime product and returns it for atomic application by the
registry. It cannot mint UUIDs, retain snapshots, mutate registry state, accept
`inout` storage, or execute a caller-provided closure.

The same split applies to the other registry transitions: the registry captures
one synchronous operation-specific immutable snapshot and mints any required
UUIDv7 identity; a stateless planner returns a complete typed transition
product; the primary registry declaration performs every stored-property
write. Whole registry dictionaries are not retained across mutation because a
retained Swift copy-on-write snapshot could turn the next write into O(N) work.

Swift access control alone cannot prevent a deliberately added same-file
extension from reaching a `private` member of the owner. Architecture lint
therefore enforces the lexical boundary: the owner has no production extension;
UUIDv7 issuance for binding/control/native identity occurs only in the approved
`selected -> starting` transition; complete binding/lifetime construction
occurs only in the approved stateless completion planner; and plain-helper plus
same-file-extension mutation probes fail. This lint is a source-regression
guard over the structural design, not a runtime authority.

### Mailbox facade and lexical storage owner

`FilesystemObservationMailbox` remains the domain wrapper and coordination
facade. It exposes the paired callback/native port request surface and only
closed lifecycle, producer, consumer, waiter, and diagnostic operations. The
core performs the lock-linearized port construction and authority minting. The
facade does not own raw mutable coordination storage.

`FilesystemObservationMailboxCore` is the one lexical mutable storage and
coordination owner. Its primary declaration owns the single mailbox
coordination lock, `State`, slot registry, generic gather mailbox, fixed
recovery register, fleet doorbell, and every mutation or dependency-calling
coordination operation over those values. In the rest of this contract,
"wrapper lock" and "mailbox coordination lock" mean this core-owned lock.

Immutable contracts and projections may remain in sidecar files. Pure
transition planners may also be sidecars when they receive values and return
values only; they cannot retain mutable state, call the core's dependencies,
mint authority, decide currentness, or become a second coordination owner. The
facade-to-core call is an ordinary synchronous method call. This decomposition
adds no actor, queue, lock, event hop, lookup, currentness owner, or runtime
authority.

The source-level started-generation bound is:

```text
retiring = closingAwaitingCallbackLeaseDrain
         | closingAwaitingPredecessor
         | retirementFencePending
         | retirementFenceInstalled
         | retirementFenceTransferredAwaitingCleanup
         | retiredAwaitingContextRelease

current  = accepting
         | closingAwaitingCallbackLeaseDrain

desired  = one newest non-started registration identity
```

There are at most two started generations per source plus one desired identity.
Retirement is oldest-first. N+1 may close and drain callback leases while N is
retiring, but N+1's fence remains predecessor-gated until N's context-release
acknowledgement frees the retiring slot. A new UUIDv7 binding identity makes
every old request stale. Generic ready-key fairness does not provide this
cross-slot generation order; the wrapper does.

Only the predecessor-free oldest retiring binding may own a pending fence
intent. N+1 remains `closingAwaitingPredecessor` and cannot mint its fence
identity while N owns that intent. This is the structural reason one logical
source owns at most one pending fence.

`lastCompletedRelease` is a fixed per-slot tombstone:

```text
none
completed(oldBinding, fenceIdentity, retirementAuthority, releaseAuthority)
```

It supports idempotent replay while the slot is vacant. Rebinding may replace
the tombstone only after the new UUIDv7 binding identity makes every old request
typed stale. No unbounded completed-retirement ledger is permitted.

## One-Shot Callback Authority

`FSEventCallbackLease` has the closed state:

```text
held(controlBlockIdentity, registration, admissionAvailable)
held(controlBlockIdentity, registration, admissionConsumed)
released(registration)
```

A mailbox-created `FilesystemObservationCallbackAdmissionPort` binds the exact
slot binding and its fleet doorbell. The adapter owns the control block and
port; the control block does not retain the port; the port retains only opaque
non-authorizing identities plus the mailbox/doorbell operation.

The port's closed result is:

```text
FilesystemObservationCallbackAdmissionResult
  = admitted(disposition, wakeApplication)
  | authorityRejected(
      released | foreignControlBlock | registrationMismatch |
      slotBindingMismatch | alreadyConsumed)
  | mailboxRejected(
      undeclaredSlot | invalidFootprint | fenced |
      fleetOrdinaryAdmissionSealed | closed)

wakeApplication = notRequested | applied
```

The port calls a private nonescaping lease operation. The lease lock remains
held while it verifies exact control-block identity, registration, held state,
unused admission, and exact slot binding; consumes the one admission; and calls
the bound mailbox. Lock order is lease, wrapper, recovery register/generic
gather. Mailbox/generic locks release before the port applies a requested wake
to its paired fleet doorbell. The lease stays held through that signal so
release/lease drain cannot pass between retained custody and wake application.
The doorbell never calls into mailbox, lease, or control-block code.

No raw producer or separately pairable signaler escapes. Structural/compiler
proof, not a runtime unauthenticated call, proves this negative space.

Each accepted observation or retirement fence receives a UUIDv7 contribution
identity from the mailbox owner under its coordination lock. FIFO comes from the
mailbox contribution order, not from UUID sorting. A later binding has a
different binding identity, so its contributions remain disjoint.

The permanent non-authorizing synchronization seam has exactly two value-free
methods:

```text
afterAuthorityConsumedBeforeMailboxOffer()
afterMailboxOfferBeforeWakeApplication()
```

The port factory owns it. Production proceeds immediately; the controllable
test implementation supplies deterministic gates. It receives no authority or
payload and cannot call lease, control-block, mailbox, generic-admission,
recovery-register, or doorbell APIs. It is not conditional compilation and its
production cost remains part of callback benchmarks.

## Contribution And FIFO Contract

```text
FilesystemObservationContributionIdentity
  exact slot binding
  host-minted UUIDv7 identity

FilesystemObservationMailboxContribution
  = observation(contributionIdentity, FSEventObservation)
  | retirementFence(contributionIdentity,
                    FilesystemObservationSlotRetirementFence)
```

Callbacks can create only `.observation`. The slot lifecycle owner can request
only `.retirementFence` after the exact callback lease-drain receipt is accepted
and predecessor gating permits installation. The paired port or lifecycle owner
mints one checked binding-local identity under the wrapper lock before each
offer. The identity is part of the immutable filesystem payload; the generic
mailbox remains unaware of it.

The generic mailbox's maintained contract is:

- contributions append FIFO per physical slot;
- lease extraction removes an ordered prefix bounded by contribution/item/byte
  quantum;
- a retried whole lease is re-presented identically before newer same-slot
  contributions;
- acknowledgement transfers or retries the complete lease;
- unrelated slots rotate through the one fair ready-key queue.
- queued and in-flight cleanup custody is serviced before any semantic lease.
  Under the maintained generic behavior this priority is fleet-global.
- contracted admission returns the exhaustive public `GatherContractionCause`
  that atomically distinguishes ordinary pressure from fleet exhaustion.

No generic dynamic-key, per-key seal, or retirement API is added. The retirement
fence is the final contribution for its exact binding because callback authority
is already drained and wrapper admission is fenced. A lease may contain
observations followed by its fence. The actor processes that batch sequentially;
all earlier observations/recovery and the fence transfer together, or the
entire immutable lease retries. Actor semantic acceptance is idempotent by the
stable contribution identity, so a failure after accepting a prefix cannot
duplicate that prefix on replay. Fence completion is never acknowledged
independently from its generic lease.

## Native Fence And Pending Intent

The native order is:

```text
close new callback-lease acquisition
  -> stop/invalidate stream
  -> callback-queue barrier
  -> zero callback leases
  -> mint exact binding-specific lease-drain receipt
  -> request retirement fence
```

Receipt minting proves no callback offer or paired signal remains in flight.
The wrapper accepts only the current binding's unforgeable receipt and fences
all later callback offers before attempting the generic fence contribution.

Ordinary generic capacity may contract an incoming fence. Generic contraction
also retires any queued same-slot contributions into cleanup and exposes only
recovery custody, so the wrapper cannot infer that no observation detail was
discarded. Every contracted fence therefore records conservative
`retirementFenceAdmissionContraction` domain evidence and requires exact
SourceGate repair acceptance. This may conservatively repair a fence-only
contraction; it never claims that retained pending fence intent repairs lost
observation detail. The exact pending fence remains lifecycle intent, separate
from repair evidence.

Contracting the fence does not install or complete it. The wrapper retains one
non-evictable
`PendingRetirementFence` per retiring slot:

```text
binding
exact lease-drain receipt
opaque fence identity
```

After every generic acknowledgement or cleanup completion, while still holding
the wrapper lock that excludes callback offers, the wrapper attempts at most one
eligible pending fence before producers can consume newly freed capacity. A
fixed unique ready queue rotates pending fences fairly. Wake application occurs
after unlocking. This is bounded lifecycle intent, not a mirrored generic
custody counter or second payload queue.

N+1's fence cannot become eligible until the retained idempotent N retirement
receipt has been acknowledged after native context release. This predecessor
gate supplies cross-slot order absent from the generic ready queue.

## Actor Transfer And Retirement Receipt

`FilesystemActor` is the sole fleet mailbox consumer. It never awaits scans,
Git, Bridge, MainActor, filesystem I/O, or other heavy work while holding the
single generic drain lease. It owns one fixed semantic replay shell per physical
slot. Each shell holds at most one generic lease quantum of exact contribution
identities and their accepted-prefix dispositions for that slot's outstanding
retry bucket. Multiple slots may therefore retain replay state concurrently,
bounded by `P * maximumContributionsPerGenericLease`.

A shell survives generic retry rotation and consumer rebind. Rediscovery matches
the exact slot binding and full ordered contribution-identity vector; a stale
consumer cannot commit against a replaced shell. The shell clears only after
that exact whole lease transfers. The final fence identity then moves into the
fixed retirement receipt/tombstone; ordinary identities do not survive
successful whole-lease acknowledgement. This is neither a binding-lifetime
history nor an unbounded seen set.

In one calibrated actor turn it preflights the complete lease, then moves
observations into bounded binding-specific semantic custody and synchronously
obtains exact idempotent `FilesystemSourceGateRecoveryAcceptance` for matching
recovery evidence. If cancellation or failure occurs after a prefix enters
semantic custody, replay of the whole immutable lease observes those exact
identities as already accepted and produces no second semantic effect. Only
after every contribution and recovery revision has an accepted disposition does
the actor transfer the complete generic lease; otherwise it retries it.

`quiescentWithoutRecovery` means all ordinary observations before the fence
were accepted into bounded actor-owned semantic custody; it never means merely
that a generic slot appears empty.

When a transferred lease contains the final fence, the wrapper/actor verifies:

- the fence is final for the exact binding;
- generic whole-lease acknowledgement succeeded;
- every preceding ordinary contribution entered binding-specific actor custody;
- every preceding contribution identity has exactly one semantic acceptance;
- every matching recovery revision received SourceGate acceptance and cleared
  only its exact evidence custody;
- no domain retry evidence remains for the binding.
- no queued or in-flight generic cleanup can contain discarded detail for the
  binding. Under the maintained generic priority, fence leasing already proves
  fleet-global cleanup quiescence.

Successful fence transfer first enters
`retirementFenceTransferredAwaitingCleanup`. It mints one unforgeable final
receipt only after the cleanup predicate remains satisfied:

```text
FilesystemObservationSlotRetirementDisposition
  = quiescentWithoutRecovery
  | quiescentAfterRecovery(nonempty exact recovery revision set)

FilesystemObservationSlotRetirementReceipt
  exact slot binding
  fence identity
  disposition
  opaque retirement authority
```

The slot moves to `retiredAwaitingContextRelease` and retains the receipt.
Repeated matching retirement requests return the same receipt. Caller
cancellation or a lost response cannot discard it. Foreign, partial, stale-
binding, or conflicting requests return typed rejection without changing state.

The native generation owns one closed release operation. It consumes a matching
final receipt, performs nonthrowing release-once of its retained callback
context, transitions to `contextReleased`, and only then mints and retains:

```text
FilesystemObservationContextReleaseAcknowledgement
  exact slot binding
  fence identity
  opaque retirement authority
  opaque release authority
```

Matching acknowledgement is idempotent: first application advances the slot;
repeated application returns `alreadyApplied`. Foreign/stale-binding/partial
acknowledgements do nothing. Only accepted acknowledgement returns the slot to
`vacant`. A later native-lifetime commitment installs a new UUIDv7 binding
identity, so every request carrying the prior exact binding remains stale.

No public initializer or other owner can mint release authority. Repeating the
native release operation replays the same post-release acknowledgement without
releasing twice. The registry operations are closed:

```text
requestRetirementFence
  = pending | installed | retired(existingReceipt) | typedRejection

applyContextReleaseAcknowledgement
  = applied | alreadyApplied | bindingMismatch | fenceMismatch
  | retirementAuthorityMismatch | releaseAuthorityMismatch | staleBinding
```

## Fleet Shutdown

Per-source replacement/removal never seals the fleet generic mailbox. Whole
shutdown closes every callback authority, obtains every native lease-drain
receipt, installs or retains every retirement fence, transfers every binding's
ordinary/recovery custody, releases native contexts, and accepts every context
release acknowledgement. Only after no active, retiring, retrying, pending-fence,
retained-receipt, queued/in-flight cleanup, semantic-acceptance, or unreleased-
context state remains may lifecycle composition seal/invalidate the fleet
mailbox and finish its doorbell.

`FilesystemObservationFleetLifecycle` owns shutdown coordination and the
non-evictable in-memory result:

```text
FilesystemObservationFleetShutdownResult
  = completed(FilesystemObservationFleetShutdownReceipt)
  | incomplete(FilesystemObservationFleetShutdownDebtSnapshot)

FilesystemObservationFleetShutdownDebtSnapshot
  exact unresolved slot bindings
  callback lease/barrier/context states
  generic lease, retry, recovery, queued-cleanup and in-flight-cleanup custody
  pending retirement fences
  actor semantic-acceptance and SourceGate-repair custody
  retained retirement receipts and context-release acknowledgements
  admissionDisposition: FilesystemObservationFleetAdmissionDisposition

FilesystemObservationFleetAdmissionDisposition
  = ordinary
  | fleetAdmissionExhausted(exact FleetAdmissionExhaustionDebt)
```

The slot registry retains slot/native lifecycle debt and the actor retains its
existing generic/semantic custody; the snapshot references those owners and is
not a second payload queue. Requester cancellation cannot cancel the internal
drain or discard debt. Explicit `resumeShutdown` and each acknowledgement or
cleanup-completion event deterministically attempt the next eligible transition
until quiescent; there is no wall-clock retry. Only `completed` authorizes seal,
invalidation, and doorbell finish. Debt has process lifetime and is not a new
persistent store. Process termination may end memory lifetime but cannot be
reported as a clean shutdown.

## Proof Expectations

Deterministic proof uses injected clocks and event/barrier gates, never
wall-clock sleeps:

1. Callback admission remains O(1) at 1/100/300 active bindings and cannot
   allocate slots.
2. Equal registration token with foreign control block/binding epoch, released
   lease, consumed lease, and stale copied port produce zero payload, evidence,
   or wake.
3. Paused admission blocks release, native fence receipt, and slot recycle until
   the paired signal completes.
4. Observation A/B/fence remains FIFO across every lease quantum; a fence is
   final when it shares a batch.
5. Failure after a strict prefix enters actor custody retries the identical
   whole lease; stable contribution identities make the prefix a semantic no-op
   and the final state equals one application of the lease. Partial retries for
   multiple slots rotate and survive consumer rebind simultaneously within the
   `P * maximumContributionsPerGenericLease` replay bound.
6. Recovery-bearing fence cannot retire before exact SourceGate acceptance.
7. A capacity-contracted fence retains one pending intent, records conservative
   `retirementFenceAdmissionContraction` evidence distinct from fence intent,
   cannot pass queued/in-flight cleanup or SourceGate acceptance, installs
   later, and performs at most one retry per ack/cleanup turn.
8. N+1 fence cannot install/complete before predecessor N context-release
   acknowledgement across different slots.
9. Old callback port, lease, drain token, recovery acceptance, fence, retirement
   receipt, and release acknowledgement fail after slot reuse by exact UUIDv7
   binding mismatch.
10. Equal opaque generic recovery revisions across slot reuse cannot authorize
    domain acknowledgement; exact binding plus domain custody identity prevents ABA.
    Integer exhaustion is not part of this product proof.
11. Lost retirement response, repeated request, context release, lost release
    acknowledgement, and repeated acknowledgement replay one receipt and recycle
    exactly once.
12. Reserve sizes 0/1/R/S under S simultaneous replacements produce exhaustive
    started/deferred dispositions, one desired identity and FIFO node per
    source, withdrawal without ghost start, in-place desired overwrite, and
    rank-`q` selection within `q + 1` successful vacancy selections. Injected
    pre-commit failure releases only the exact reservation; injected
    post-commit create/start failure rotates without wall-clock policy while its
    exact unpublished native generation retires through the unpublished D3
    permit. Same-root safe N is
    retained; changed/removed/unauthorized N closes and never resurrects.
    Deterministic withdrawal after FIFO pop, reservation, native-lifetime
    commitment and native create consumes the exact create/start right, releases
    or retires every unpublished resource, and publishes no callback authority.
    Withdrawal racing a successful native start instead publishes accepting and
    retains the exact post-start close disposition. Failed create/start without
    a retained prior preserves one desired-record repair authority across D3;
    exact handoff replay admits one SourceGate repair generation; removal consumes
    pending repair; and currentness remains non-current through
    `installedAwaitingContinuityRepair` until all repair acknowledgements finish.
13. N retiring + N+1 current/closing + N+2/N+3 desired while unrelated slots
    churn proves two started generations per source, one eligible pending fence,
    one desired identity, oldest-first retirement, fleet fairness, the static
    logical-source contribution/item/byte maximum, and global bounds at exact
    and bound-plus-one pressure. Exhaustive lifecycle categorization keeps
    `retirementFenceTransferredAwaitingCleanup` retiring, slot-occupying,
    predecessor-ordering, and non-reusable until final receipt/context release.
14. Consumer cancellation/rebind before/after take preserves the fence and
    unrelated-slot progress.
15. Cancellation/failure at every shutdown custody class returns the exact same
    typed incomplete debt on retry. Whole shutdown cannot seal while any
    callback lease, generic retry/recovery/queued or in-flight cleanup, pending
    fence, semantic acceptance, SourceGate repair, retained receipt, release
    acknowledgement, or native context remains; deterministic resume reaches
    one completed receipt when those owners quiesce.
16. Callback benchmarks include the immediate synchronization implementation
    and paired doorbell application.
17. Lost retirement and context-release responses replay from one bounded
    per-slot tombstone before reuse and return typed stale results after reuse;
    native context release occurs exactly once before acknowledgement minting.
18. Registry behavior remains identical after contracts/projections move out of
    the mutable owner and the reusable construction key is removed. Focused
    SwiftSyntax probes accept the sole `selected -> starting` construction site
    and reject a plain helper, same-file owner extension, second issuer/factory,
    and contracts/projection mutation attempt.
19. Mailbox behavior and callback operation counts remain identical after the
    facade/core decomposition. Structural proof shows the core primary
    declaration is the sole lexical owner of the one coordination lock,
    `State`, slot registry, generic gather mailbox, fixed recovery register,
    doorbell, and their mutations/dependency calls; the facade owns only the
    paired-port request surface, and contracts/projections/pure planners own no
    mutable custody or runtime authority.

## Non-Goals

- No dynamic generic-mailbox keys.
- No per-source mailbox or per-source drain task.
- No fleet mailbox rollover for ordinary source replacement.
- No generic per-key seal or retirement API.
- No generic API expansion beyond the typed contraction cause required to
  observe the existing fleet-wide ordinary-admission exhaustion transition.
- No mirrored wrapper copy of generic custody counters.
- No callback actor/task/MainActor call, path reduction, or semantic repair.
- No numeric capacity choice in this spec; calibration freezes `S`, `R`, and
  item/byte/lease limits in `AppPolicies`.
