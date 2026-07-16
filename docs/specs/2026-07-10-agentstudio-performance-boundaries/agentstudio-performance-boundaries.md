# AgentStudio Performance Boundaries

Date: 2026-07-10
Status: accepted technical contract; dataflow/atom boundary revised 2026-07-16
Scope: parent pre-plan contract for filesystem pressure and terminal interaction
Baseline: `ghostty-performance` at `cd47c511`

## Product Intent

AgentStudio is an interactive terminal workspace first. Background discovery,
filesystem churn, Git projection, semantic event delivery, persistence, Bridge
refresh, and terminal intelligence must not make typing, cursor movement, pane
switching, or current terminal presentation feel frozen.

Responsiveness cannot be purchased by silently losing correctness. Under
pressure, source hints and presentation samples may contract, but exact semantic
facts, recovery obligations, canonical topology, secure-input protection, and
terminal lifecycle must remain correct and eventually converge.

This parent contract exists so a planner does not have to infer shared rules by
comparing two long sibling specs. It owns cross-domain vocabulary, dependency
direction, safe defaults, and the combined proof boundary. The child specs own
their domain-specific requirements:

- [Watched-Folder Admission and MainActor Fairness](../2026-07-09-watched-folder-admission-mainactor-fairness/watched-folder-admission-mainactor-fairness.md)
- [Ghostty Host Boundary and Terminal Interaction Fairness](../2026-07-09-ghostty-terminal-interaction-fairness/ghostty-terminal-interaction-fairness.md)

## Shared Mental Model

```text
A. direct terminal interaction
   AppKit input [MainActor] -> synchronous libghostty call
   -> Ghostty PTY / VT / renderer -> frame-layer publication

B. Ghostty action admission
   synchronous copy/classification -> pane-local latest state
   | bounded activity projection | targeted command owner | exact fact owner

C. watched filesystem
   O(1) callback offer -> bounded gather/recovery -> off-main scan/project
   -> fair Git scheduling -> compact typed canonical change

D. durable canonical mutation
   pure domain decision -> typed persistence gateway
   -> exact preimage capture -> narrow atom assignment + one revision
   -> bounded pager -> off-main assembly -> SQLite actor

startup domain lifecycles
   composition prepare/install -> immediate terminal activation
   topology prepare/install -> independent repository/filesystem reconciliation

telemetry sidecar
   bounded, content-safe, drop-accounted, and fail-open; never blocks A-D
```

These are pressure-flow classifications over existing owners, not four new
runtimes or a universal pipeline. Composition and topology have independent
preinstall/install authority while sharing one persistence runtime, revision
owner, and adapter graph. Telemetry is a cross-cutting sidecar, never a product
state or correctness edge.

### Acyclic Workload And Bounded Feedback

The dependency graph and each causal processing attempt are acyclic. Runtime
repair and reconfiguration may recur only by advancing a checked generation,
revision, or bounded scheduler attempt. A reverse control edge may acknowledge
custody or request that later attempt; it cannot carry new payload, synchronously
re-enter admission, repost the same authority/source fact, or mutate from atom
observation.

Every pressure-bearing path proves three independent bounds:

- admission: at most one pending drain/apply turn per declared gate or key set;
- service: bounded synchronous MainActor work with no await, I/O, serialization,
  fleet scan, or hidden domain planning;
- expansion: raw input contracts to declared keys/recovery debt, and one accepted
  semantic mutation produces one outer transaction, revision, and effect record.

A fixed changed-key workload must not grow with total repository, worktree,
pane, subscriber, or diagnostic fleet size. Static owner/route proof covers
declared edges; deterministic count tests and runtime ledgers falsify hidden
task, message, invalidation, replay, telemetry, or same-generation expansion.

Actor isolation is necessary for data-race safety but insufficient for
performance. Every pressure-bearing boundary must also declare admission,
capacity, contraction, ordering, recovery, generation, consumers, sensitivity,
and telemetry.

## Boundary / Separability Map

```text
filesystem source boundary
  owns: FSEvent callback capture, repair debt, scan scheduling
  exposes: generation-bearing observations, repairs, semantic facts

                    typed semantic topics
                              |
                              v
shared runtime transport ----------------------> named projectors/coordinators
  owns: topic interest, replay, fanout, lag       own: domain joins/scheduling
  does not own: raw samples, joins, UI mutation   expose: typed apply batches

                              |
                              v
MainActor last mile
  owns: canonical observable state and direct AppKit calls
  accepts: changed-key mutations and bounded current-state samples
  rejects: scans, fleet joins, retry queues, serialization, Bridge builds

Ghostty host boundary
  owns: callback lifetime, tick/action admission, surface host truth
  exposes: pane-local samples, snapshots, targeted intents, semantic facts
  does not own: VT parsing, Metal rendering, global raw-event processing

startup composition boundary
  owns: workspace identity, pane descriptors, drawers, tab containers,
        arrangements/layouts, local cursors, and window/sidebar UI memory
  exposes: one accepted composition revision and terminal activation input
  does not own: Ghostty readiness, repository topology, Git, or path matching

terminal activation boundary
  owns: prioritized surface creation, zmx attachment, host mounting, focus,
        per-pane runtime readiness, retry, and cancellation
  exposes: active-terminal typing readiness and all-restorable readiness
  does not own: canonical pane structure or repository availability

external reconciliation boundary
  owns: watched roots, filesystem discovery, repository/worktree topology,
        Git currentness, and CWD-derived pane location projection
  exposes: compact topology and display-context mutations
  does not own: pane residency, tab membership, terminal lifetime, or startup
        interaction readiness

durable-state boundary
  owns: exact preimage custody, one canonical revision, bounded paging, SQLite I/O
  exposes: domain-specific installed mutation gateways and startup-only appliers
  does not own: domain decisions, source admission, observation feedback, UI reads

diagnostic export sidecar
  owns: bounded content-safe evidence export, drops, gaps, and final run validity
  does not own: product state, correctness custody, source wakeups, or backpressure

shared performance harness
  owns: one run identity, clocks/correlation, scenario manifest, evidence
  combines: watched pressure factors + terminal interaction stages
```

## Shared Pressure Stream Contract

Every high-cardinality or latency-sensitive path has an inspectable declaration
with these fields. The type and owner names introduced by this spec are
normative architecture vocabulary. Planning maps them to files and existing
symbols; it does not replace them with a different ownership model.

| Field | Contract |
| --- | --- |
| owner | one component mutates queue state and acknowledges recovery |
| input | typed observation, sample, fact, intent, mutation, or diagnostic |
| isolation | callback thread, actor, MainActor, or synchronous caller |
| capacity | maximum items, keys, and/or bytes; hard versus diagnostic |
| admission | exact, latest-by-key, accumulated, debounced, sampled, or rejected |
| overflow | contracted data and the durable recovery obligation replacing it |
| ordering | per source, key, generation, semantic stream, or intentionally none |
| replay | none, current snapshot, bounded fact history, or authoritative rebuild |
| consumers | named owners/topics requiring the value |
| contraction | expected input-to-output ratio and expansion rationale |
| generation | token/revision making stale work rejectable at every boundary |
| sensitivity | path, identity, content, secret, retention, and export policy |
| telemetry | counts, depth/age, service, outputs, drops, and repair state |

Domain manifests conform to this vocabulary:

- filesystem observation and repair descriptors add FSEvent/source-kind and
  authoritative-recovery fields;
- Ghostty action descriptors add callback origin, synchronous handled
  disposition, default-host behavior, and surface/app generation;
- diagnostic streams add evidence-loss accounting and run-validity behavior.

### Reusable Admission Primitive Families

The architecture uses three semantic primitive families rather than one
universal event queue. Shared code may reuse synchronization and wake/drain
mechanics beneath these types, but there is no payload-erased universal queue
and no caller-selected drop policy:

| Primitive family | Admission/overflow contract | Intended inputs |
| --- | --- | --- |
| latest-value mailbox | one bounded slot per declared key, bounded delivery/auxiliary/cleanup limits, latest-among-admitted replacement, and an explicit lossy-or-resample wrapper policy | scrollbar/search/cursor/viewport/current presentation samples |
| bounded gather mailbox | bounded declared keys, contributions, items, and bytes with distinct global, per-key, and lease-quantum limits; it retains opaque value contributions without domain computation; overflow advances exact per-key recovery custody rather than silently losing detail | filesystem observations, Bridge dirty IDs, source invalidations |
| ordered fact journal | synchronous sequence/current-state commit before transport; bounded history with an explicit non-evictable gap marker when exact retention is impossible; lag and authoritative recovery are explicit | lifecycle, command completion, health/security, agent-state transitions |

Producer-side admission occurs before allocating one task/message per raw
sample. `Task { await actor.ingest(sample) }` for every callback is not a
mailbox: it merely moves an unbounded task backlog in front of the actor. A
gate schedules at most one drain, and the drain takes a bounded snapshot/batch
or exact fact sequence according to its primitive family. UI samples and exact
facts cannot share one dropping buffer.

## Normative Shared Interfaces

The following contracts close the architecture boundary. Their internal lock,
atomic, storage, and wake primitive is implementation detail only when the
observable state machine below is preserved.

Type safety is a normative architecture requirement, not an implementation
style preference. Every behavioral alternative is a closed enum case and every
value required by that alternative is carried by that case. A struct containing
a discriminator plus optional companion fields, or a result that uses `nil`, an
empty collection, a Boolean, or another result case as a sentinel, is forbidden
when those values select different transition meanings. `Optional` remains
valid only for genuinely independent absence, such as an empty queue link, no
current snapshot, or no age because the measured custody set is empty. Public
contracts and private post-lock transition captures obey the same rule.

```swift
enum PressureStreamID: UInt8, CaseIterable, Sendable {
    case filesystemObservation
    case filesystemRepair
    case filesystemGitInvalidation
    case terminalViewport
    case terminalActivity
    case runtimeFacts
    case bridgeInvalidation
    case performanceEvidence

    var telemetryName: StaticString {
        switch self {
        case .filesystemObservation: "filesystem_observation"
        case .filesystemRepair: "filesystem_repair"
        case .filesystemGitInvalidation: "filesystem_git_invalidation"
        case .terminalViewport: "terminal_viewport"
        case .terminalActivity: "terminal_activity"
        case .runtimeFacts: "runtime_facts"
        case .bridgeInvalidation: "bridge_invalidation"
        case .performanceEvidence: "performance_evidence"
        }
    }
}

struct AdmissionGeneration: Hashable, Sendable {
    let owner: PressureStreamID
    let value: UInt64
}

enum LatestValueOfferResult: Sendable, Equatable {
    case admitted(wake: AdmissionWakeDirective)
    case replacedPrevious(wake: AdmissionWakeDirective)
    case physicalCapacityExceeded
    case staleGeneration
    case undeclaredKey
    case closed
}

struct GatherFootprint: Sendable, Equatable {
    let itemCount: Int
    let byteCount: Int
}

struct GatherMailboxLimits: Sendable, Equatable {
    let maximumDeclaredKeys: Int
    let maximumRetainedContributions: Int
    let maximumRetainedItems: Int
    let maximumRetainedBytes: Int
    let maximumRetainedContributionsPerKey: Int
    let maximumRetainedItemsPerKey: Int
    let maximumRetainedBytesPerKey: Int
    let maximumContributionsPerLease: Int
    let maximumItemsPerLease: Int
    let maximumBytesPerLease: Int
    let cleanupQuantum: AdmissionCleanupQuantum
}

enum GatherRecoverySignal: Sendable, Equatable {
    case ordinary
    case authoritativeRecoveryRequired
}

struct GatherContribution<Key, Payload>: Sendable
where Key: Hashable & Sendable, Payload: Sendable {
    let key: Key
    let payload: Payload
    let footprint: GatherFootprint
    let recoverySignal: GatherRecoverySignal
}

enum GatherRecoveryStamp: Hashable, Sendable {
    case sequenced(UInt64)
    case authorityExhausted
}

struct GatherRecoveryRevision<Key>: Hashable, Sendable
where Key: Hashable & Sendable {
    let generation: AdmissionGeneration
    let key: Key
    private let stamp: GatherRecoveryStamp
}

enum GatherAdmissionDisposition<Key>: Sendable
where Key: Hashable & Sendable {
    case retained
    case retainedWithRecovery(GatherRecoveryRevision<Key>)
    case contractedToRecovery(GatherRecoveryRevision<Key>)
}

enum GatherOfferResult<Key>: Sendable where Key: Hashable & Sendable {
    case admitted(GatherAdmissionDisposition<Key>, wake: AdmissionWakeDirective)
    case staleGeneration
    case undeclaredKey
    case invalidFootprint
    case closed
}

enum AdmissionWakeDirective: Sendable, Equatable {
    case noWake
    case scheduleDrain
}

enum AdmissionDoorbellResult: Sendable, Equatable {
    case signaled
    case finished
}

enum AdmissionDoorbellStateSnapshot: Sendable, Equatable {
    case idle
    case signalPending
    case consumerWaiting
    case finished
}

protocol AdmissionDoorbellSignaler: Sendable {
    func signal()
}

protocol AdmissionDoorbellConsumer: Sendable {
    func nextSignal() async -> AdmissionDoorbellResult
}

protocol AdmissionDoorbellOwner: AdmissionDoorbellSignaler,
    AdmissionDoorbellConsumer
{
    func finish()
}

struct AdmissionOpaqueIdentity: Hashable, Sendable {
    private let rawValue: UUID
}

struct AdmissionConsumerBinding: Hashable, Sendable {
    private let mailboxIdentity: AdmissionOpaqueIdentity
    private let bindingEpoch: AdmissionOpaqueIdentity
    private let bindingSequence: UInt64
}

struct AdmissionConsumerBindResult: Sendable, Equatable {
    let binding: AdmissionConsumerBinding
    let wake: AdmissionWakeDirective
}

struct AdmissionDrainToken: Hashable, Sendable {
    let generation: AdmissionGeneration
    private let mailboxIdentity: AdmissionOpaqueIdentity
    private let bindingEpoch: AdmissionOpaqueIdentity
    private let bindingSequence: UInt64
    private let leaseEpoch: AdmissionOpaqueIdentity
    private let leaseSequence: UInt64
}

struct NonEmptyAdmissionBatch<Element: Sendable>: Sendable {
    let first: Element
    let remaining: [Element]
}

enum GatherDrainPayload<Key, Payload>: Sendable
where Key: Hashable & Sendable, Payload: Sendable {
    case contributions(NonEmptyAdmissionBatch<GatherContribution<Key, Payload>>)
    case contributionsWithRecovery(
        NonEmptyAdmissionBatch<GatherContribution<Key, Payload>>,
        GatherRecoveryRevision<Key>
    )
    case recovery(GatherRecoveryRevision<Key>)
}

struct GatherDrainLease<Key, Payload>: Sendable
where Key: Hashable & Sendable, Payload: Sendable {
    let token: AdmissionDrainToken
    let key: Key
    let payload: GatherDrainPayload<Key, Payload>
}

enum GatherTakeDrainResult<Key, Payload>: Sendable
where Key: Hashable & Sendable, Payload: Sendable {
    case lease(GatherDrainLease<Key, Payload>)
    case cleanupRequired
    case empty
    case alreadyLeased
    case staleGeneration
    case closed
}

enum LatestValueDrainResult<Key, Value>: Sendable
where Key: Hashable & Sendable, Value: Sendable {
    case drain(LatestValueDrain<Key, Value>)
    case cleanupRequired
    case empty
    case alreadyDraining
    case staleGeneration
    case closed
}

struct LatestValueEntry<Key, Value>: Sendable
where Key: Hashable & Sendable, Value: Sendable {
    let key: Key
    let value: Value
}

struct LatestValueDrain<Key, Value>: Sendable
where Key: Hashable & Sendable, Value: Sendable {
    let token: AdmissionDrainToken
    let values: NonEmptyAdmissionBatch<LatestValueEntry<Key, Value>>
    let oldestRetainedAge: ExactAdmissionAge
}

enum OrderedFactTakeDrainResult<Fact>: Sendable where Fact: Sendable {
    case drain(OrderedFactDrain<Fact>)
    case cleanupRequired
    case empty
    case alreadyDraining
    case staleGeneration
    case closed
}

enum OrderedFactDrainPayload<Fact: Sendable>: Sendable {
    case facts(NonEmptyAdmissionBatch<SequencedFact<Fact>>)
    case gap(FactGap)
}

struct OrderedFactDrain<Fact: Sendable>: Sendable {
    let token: AdmissionDrainToken
    let payload: OrderedFactDrainPayload<Fact>
    let oldestRetainedAge: ExactAdmissionAge
}

enum AdmissionDrainDisposition: Sendable, Equatable {
    case transferred
    case retry
}

enum AdmissionDrainAcknowledgement: Sendable, Equatable {
    case accepted(wake: AdmissionWakeDirective)
    case staleGeneration
    case invalidToken
    case closed
}

enum AdmissionCleanupQuantum: Sendable, Equatable {
    case entries(maximumEntries: Int)
    case entriesAndBytes(maximumEntries: Int, maximumBytes: Int)

    var maximumEntries: Int {
        switch self {
        case .entries(let maximumEntries),
            .entriesAndBytes(let maximumEntries, _): maximumEntries
        }
    }
}

enum AdmissionCleanupRelease: Sendable, Equatable {
    case entries(count: Int)
    case entriesAndBytes(count: Int, bytes: Int)
}

struct AdmissionCleanupTurn: Sendable, Equatable {
    let release: AdmissionCleanupRelease
    let wake: AdmissionWakeDirective
}

enum AdmissionCleanupTurnResult: Sendable, Equatable {
    case performed(AdmissionCleanupTurn)
    case alreadyCleaning
    case blockedByReplayReader
    case empty
    case staleGeneration
}

protocol AdmissionCleanupConsumer: Sendable {
    func performCleanup(
        generation: AdmissionGeneration
    ) -> AdmissionCleanupTurnResult
}

enum AdmissionAgeMeasurement: Sendable, Equatable {
    case exact(Duration)
    case pressureConservative(Duration)
}

struct ExactAdmissionAge: Sendable, Equatable {
    let duration: Duration
}

struct AdmissionDiagnostics: Sendable, Equatable {
    let offered: UInt64
    let admitted: UInt64
    let contracted: UInt64
    let rejectedStale: UInt64
    let rejectedUndeclared: UInt64
    let rejectedInvalid: UInt64
    let rejectedCapacity: UInt64
    let rejectedClosed: UInt64
    let repairEscalations: UInt64
    let pendingKeyCount: Int
    let pendingKeyHighWater: Int
    let oldestPendingAge: AdmissionAgeMeasurement?
}

struct LatestValueAdmissionDiagnostics: Sendable, Equatable {
    let admission: AdmissionDiagnostics
    let semanticRetainedValueCount: Int
    let semanticRetainedValueHighWater: Int
    let pendingValueCount: Int
    let leasedValueCount: Int
    let cleanupValueCount: Int
    let cleanupValueHighWater: Int
    let physicalRetainedValueCount: Int
    let physicalRetainedValueHighWater: Int
    let oldestCleanupAge: AdmissionAgeMeasurement?
    let outstandingLeaseCount: Int
    let outstandingCleanupTurnCount: Int
    let isQuiescent: Bool
}

struct GatherAdmissionDiagnostics: Sendable, Equatable {
    let admission: AdmissionDiagnostics
    let retainedContributionCount: Int
    let retainedContributionHighWater: Int
    let retainedItemCount: Int
    let retainedItemHighWater: Int
    let retainedByteCount: Int
    let retainedByteHighWater: Int
    let pendingContributionCount: Int
    let pendingItemCount: Int
    let pendingByteCount: Int
    let leasedContributionCount: Int
    let leasedItemCount: Int
    let leasedByteCount: Int
    let cleanupContributionCount: Int
    let cleanupContributionHighWater: Int
    let cleanupItemCount: Int
    let cleanupItemHighWater: Int
    let cleanupByteCount: Int
    let cleanupByteHighWater: Int
    let cleanupMetadataEntryCount: Int
    let cleanupMetadataEntryHighWater: Int
    let physicalRetainedContributionCount: Int
    let physicalRetainedContributionHighWater: Int
    let physicalRetainedItemCount: Int
    let physicalRetainedItemHighWater: Int
    let physicalRetainedByteCount: Int
    let physicalRetainedByteHighWater: Int
    let oldestCleanupAge: AdmissionAgeMeasurement?
    let recoverySlotCount: Int
    let recoverySlotHighWater: Int
    let oldestRecoveryAge: AdmissionAgeMeasurement?
    let outstandingLeaseCount: Int
    let outstandingCleanupTurnCount: Int
    let isQuiescent: Bool
}
```

`AdmissionAgeMeasurement` makes diagnostic precision structural. `nil` means
the corresponding custody set is empty. `.exact(value)` equals the literal
oldest retained age. `.pressureConservative(value)` is an upper bound on the
literal oldest age and must never understate pressure: `value >=
actualOldestAge`. State retains a mailbox-clock timestamp plus precision, not a
cached duration; every diagnostic read computes `max(.zero, now - timestamp)`
and wraps that duration in the retained precision case. A bounded mutation that
may remove the exact oldest stamp may retain the prior timestamp as
pressure-conservative instead of scanning or maintaining an ordered fleet
index. The measurement resets to `nil` exactly when its custody set reaches
zero. Diagnostic reads never traverse or repair the watermark.

The custody sets are explicit. For every primitive,
`admission.oldestPendingAge` covers all serviceable semantic custody represented
by `pendingKeyCount`: pending plus leased values/contributions/facts and any
recovery or persistent-gap custody that keeps the key/stream serviceable.
Gather `oldestRecoveryAge` covers recovery slots only. Primitive-specific
`oldestCleanupAge` covers physical cleanup payload custody only. A single known
stamp entering an empty set starts exact. An O(1) bulk transfer into an empty set
inherits the source watermark and precision. Combining non-empty sets chooses
the older retained timestamp; it is exact only when a known literal custody
owns that chosen timestamp and no input has an earlier conservative watermark,
otherwise it is pressure-conservative. Latest-value and ordered-journal owners
may continue to report `.exact` whenever their bounded ownership makes the
literal oldest stamp known. Telemetry exports the bounded precision case
separately and never presents a pressure-conservative measurement as exact
latency.

Physical custody means every primitive-owned strong reference to a previously
accepted payload plus every nontrivial dynamic metadata owner required to
release that payload, recovery, lease, replay, or cleanup state. A consumer's
independently retained copy after acknowledged transfer is outside primitive
custody. Immutable declared-key configuration and empty default slot shells are
also outside dynamic cleanup custody. A configuration-lifetime slot-index shell may point
to its current dynamic custody node only through a `weak` stored edge; it
contains no accepted payload, recovery, or strong reference-bearing dynamic
state. A strong shell/index edge or another strong dynamic-node alias outside
the declared live head/tail or bounded cleanup owner is physical custody and is
a structural lint failure.

Every accepted retirement path—including latest-value replacement—moves its
previously accepted value into capacity-charged cleanup custody. No transition
stops counting custody merely because a reference detached from a queue. One
synchronous cleanup turn has exclusive opaque authority and uses three phases:

```text
locked detach: queued cleanup -> in-flight cleanup; physical charge unchanged
unlocked release: destroy at most one cleanup quantum
locked finalize: decrement finalized custody; clear authority; compute wake
```

Diagnostics count queued plus in-flight cleanup until release finishes.
Temporary conservative overcount between destruction and finalization is legal;
undercount is not. A concurrent or destructor-reentrant cleanup call returns
`.alreadyCleaning` without mutation. Journal cleanup that exists but is pinned
by the active replay reader returns `.blockedByReplayReader`; `.empty` means no
cleanup custody exists. Invalidation, rebind, seal, and authority rollover never
revoke or alias the incumbent cleanup turn.

The private detach capture is also a discriminated union. Successful detachment
is one `.detached(authority:custody:)` case whose family-specific custody type
is structurally nonempty. Homogeneous custody carries `first` plus bounded
`remaining`; journal custody is one of nonempty facts, nonempty snapshots, or
both. Unavailable outcomes are exhaustive
cases such as `.staleGeneration`, `.alreadyCleaning`,
`.blockedByReplayReader`, and `.empty`; no unavailable case carries authority or
custody, and `.detached` cannot contain empty custody. The unlock-release step
changes the private execution value from detached custody to released authority
before protected state is entered again; no optional payload slot or empty
collection represents that phase change. `.empty` is never reused as a
successful-detachment sentinel. Likewise,
an ordered replay capture is either `.immediate(result)` or
`.registered(readerIdentity:history:)`, and a latest offer capture is either an
accepted transition or a rejected transition carrying the incoming value that
must be released after unlocking. Impossible cross-products must not be
representable even in private owner code.

Doorbell storage uses the same four closed cases as its state snapshot; pending,
waiting, and finished are not independent Booleans/optionals. Latest active-
drain storage likewise combines absence and presentation in one union carrying
the `ActiveDrain` only in presented, awaiting-initial-presentation, or awaiting-
rebind-presentation cases.

Every producer path that does not retain its incoming generic payload makes
unlock-time destruction explicit. This includes latest rejection, gather
rejection or contraction to recovery, and ordered fact/snapshot rejection.
Those inputs remain alive through protected-state exit and are released before
any later protected-state entry; they never become cleanup custody because the
primitive did not accept them. Destructor-reentrant proof covers each family.

Spec boundary / separability map:

```text
producer port
  owns: offer capability only
       |
       v
private synchronous custody owner <---- typed ports ----> service/lifecycle
  owns: raw lock/state, semantic custody, queued cleanup,
        one in-flight cleanup turn, exact capacity and authority
  exposes: typed transition results and immutable post-lock captures
       |
       +---- bounded detached batch ----> destructor release outside lock

forbidden: raw lock/state escape, domain callbacks, tasks, actors,
           product routing, unquantified protected-state traversal
```

`PressureStreamID` is one closed compile-time manifest with an exhaustive
`StaticString` telemetry-name mapping. Adding a stream requires adding a manifest case and its
pressure contract. There is no raw-string initializer. User input, paths,
pane/surface/root/registration identifiers, terminal content, UUIDs, and
payload values cannot construct telemetry-facing stream dimensions. The
architecture linter rejects parallel declarations, dynamic construction, and
telemetry stream dimensions derived from runtime identity or content.

`LatestValueMailbox<Key, Value>` has one bounded current-generation pending slot
per declared key and three explicit limits:

```swift
struct LatestValueLimits: Sendable, Equatable {
    let maximumValuesPerLease: Int
    let maximumAuxiliaryRetainedValues: Int
    let cleanupQuantum: AdmissionCleanupQuantum
}
```

Let `D` be `maximumValuesPerLease`, `R` be
`maximumAuxiliaryRetainedValues`, and `C` be
`cleanupQuantum.maximumEntries`. Configuration requires `D >= 1`, `C >= 1`,
`cleanupQuantum == .entries(maximumEntries: C)`, checked `R >= 2 * D`, and checked
`K + R` without overflow. For a cleanup-free full lease, `R >= 2D` guarantees
one complete refill-and-replace wave before acknowledgement; it does not claim
rejection-free service for an arbitrary producer burst. A pre-presented lease
formed while cleanup remains prioritizes delivery progress and may have less
replacement headroom; no complete replacement-wave guarantee applies to that
lease unless its residual cleanup also satisfies the component bound.

For declared-key count `K`, the serviceable open/sealed state obeys:

```text
pendingValueCount <= K
leasedValueCount <= D
leasedValueCount + cleanupValueCount <= R
physicalRetainedValueCount
  == pendingValueCount + leasedValueCount + cleanupValueCount
  <= K + R
```

`cleanupValueCount` includes queued and in-flight release custody. Moving a
lease to cleanup on transferred acknowledgement preserves `leased + cleanup`.
On latest-specific retry, an unsuperseded leased value returns identically to
the replaceable pending slot and becomes subject to cleanup-first service; a
later same-key offer may replace it through the ordinary charged-cleanup path.
When a newer same-key value is already pending, the older leased value contracts
to cleanup and the newer pending value survives. Neither path increases physical
or auxiliary custody. Gather and journal retry instead retain and re-present the
identical lease.

One service cycle performs at most one cleanup turn followed by at most one
delivery lease. If no cleanup exists, `takeDrain` may create and present a lease
of at most `D`. If cleanup exists and no lease is already pre-presented,
`takeDrain` returns `.cleanupRequired`. Cleanup releases at most `C` entries.
During locked cleanup finalization, before producers can consume the freed
auxiliary reserve, the mailbox atomically moves pending values into one
pre-presented active lease only when the lifecycle is open or sealed, no active
lease already exists, pending is nonempty, and the computed lease size is
positive. Its size is at most:

```text
min(D, pendingValueCount, R - remainingCleanupValueCount)
```

That lease counts immediately against `leasedValueCount`; `takeDrain` presents
it even when queued cleanup remains. This reservation-by-real-custody prevents
producer refill from indefinitely stealing every cleanup-freed slot without a
task, callback, actor, second payload queue, or uncharged reservation.
Finalization that creates an unpresented active lease reconstructs the wake
level and returns exactly one `.scheduleDrain` even when residual cleanup is
zero; a lifecycle cleanup caller is not required to execute delivery directly.
If cleanup finalizes while a lease is already outstanding, it preserves that
exact lease/token, creates no second lease, and leaves newer pending values
pending. The incumbent lease already guarantees delivery progress; its later
acknowledgement and the next cleanup-first cycle create the next opportunity.

Invalidation is the explicit terminal exception to the serviceable-state
auxiliary bound. It atomically sets pending and leased semantic custody to zero
and may move the complete valid `K + R` state
into terminal cleanup:

```text
pendingValueCount == 0
leasedValueCount == 0
cleanupValueCount <= K + R
physicalRetainedValueCount == cleanupValueCount <= K + R
```

No producer can add custody after invalidation. Each terminal cleanup turn
still releases at most `C`, so the universal physical bound remains `K + R`
without fleet-sized invalidation or final-turn destruction.

`offer` is synchronous and nonblocking. An empty declared pending slot may
accept one value without consuming auxiliary reserve. Replacing an occupied
pending slot projects `leased + queuedCleanup + inFlightCleanup + 1`. It is
accepted only when that component value is at most `R`; the previous accepted
value then enters charged cleanup and is never destroyed outside accounting.
If the component bound would be exceeded, the existing accepted pending value
and all retention/wake state remain unchanged, the incoming value is not
retained, and the offer returns `.physicalCapacityExceeded`, advancing only
`offered` and `rejectedCapacity`. The rejection case explicitly means a
projected violation of a physical-custody component bound even when total
physical custody remains below `K + R`.

The primitive promises the latest value among admitted offers, not among every
attempted offer. Every domain wrapper fixes one overload policy at compile time:

- `lossyPresentation`: rejection is an explicitly tolerated presentation loss;
  this path cannot claim authoritative currentness.
- `authoritativeResample`: before returning from a rejected offer, the wrapper
  records one generation-scoped, coalesced dirty revision per declared key at
  its source-owned recovery owner. It rereads and reoffers current authoritative
  state after delivery/cleanup progress, keeps the obligation on another
  rejection, and clears it only through the recovery owner's atomic predicate
  `dirtyRevision == transferredRevision == currentSourceRevision`. Source
  advance, rejection recording, and transfer clearing serialize at that owner;
  any newer generation or revision survives an older transfer completion.

The resample owner is bounded by the declared-key manifest, participates in
doorbell reconstruction and fair service, and creates no per-rejection task or
payload queue. A domain that cannot tolerate loss and cannot resample current
state may not use this primitive; it uses bounded gather/recovery instead. An
undeclared key remains typed rejection, and a dynamic callback race never
becomes a precondition failure.

Fleet invalidation performs O(1) protected ownership transfer and reclaims
accepted value custody through bounded turns; it does not synchronously destroy
the pending or leased fleet. Product configuration calibrates `D`, `R`, and `C`
against delivery service time, accepted replacement burst, cleanup age, memory,
and resample frequency; it does not collapse them back into one constant.

`LatestValueAdmissionDiagnostics` is the latest-value public diagnostic surface.
Its semantic, pending, leased, queued-plus-in-flight cleanup, physical, oldest-cleanup,
outstanding-lease, and quiescence fields are maintained incrementally and
contain no key or value.

Every primitive consumer's `bindConsumer()` returns
`AdmissionConsumerBindResult`, never a bare binding. The returned wake is
`.scheduleDrain` exactly when the newly authoritative consumer must service
semantic, recovery/gap, outstanding-lease, or cleanup custody without waiting
for another producer offer; otherwise it is `.noWake`.

`BoundedGatherMailbox<Key, Payload>` is a synchronous lock-backed contribution
custodian, not an actor and not a semantic coalescer. Its immutable declared-key
set and `GatherMailboxLimits` bound retained pending-plus-leased custody globally
and per key. Physically retained cleanup custody remains charged to those same
hard global and per-key limits until bounded reclamation releases the payload;
moving a payload from semantic custody to cleanup never creates capacity. The
independent per-lease and cleanup-quantum fields bound one consumer/lifecycle
turn; they do not enlarge retained capacity. `offer` receives an already-created opaque payload,
checked `GatherFootprint` and recovery signal. The mailbox stamps monotonic
retention time from its injected clock; domain capture time remains inside the
opaque payload and cannot control queue-age diagnostics. Shared code may
validate, retain, move, lease, release, and count those values; it cannot inspect
payload meaning or accept/invoke merge, repair-join, footprint, path, regex,
projection, or other domain callbacks.

Producer admission is expected O(1) for a fixed contribution shape. It touches
only the addressed declared-key slot, maintained global/per-key counters,
current lease metadata, recovery revision, lifecycle, and one wake bit. It does
not copy or scan retained collections or registered keys. Detached or
invalidated payload storage is transferred in O(1) to capacity-accounted cleanup
custody under the lock. No producer operation releases an unbounded payload
chain after unlocking. A producer call may relinquish only its one incoming
payload when admission cannot retain it without exceeding physical capacity;
all pre-existing custody is released only through a bounded consumer/lifecycle
cleanup turn. Invalid/negative footprint
values and checked-arithmetic overflow receive typed rejection or conservative
recovery; they never become zero-cost admission.

Ordinary capacity overflow contracts replaceable pending detail only for the
affected key and advances one exact, non-evictable
`GatherRecoveryRevision<Key>`. Recovery slots are outside ordinary capacity and
bounded by the immutable declared-key set. Each marker means only that the key's
current generation requires authoritative recovery. The generic primitive does
not choose a scan/rebuild, retain a domain `RepairGeneration`, or join domain
repair payloads.

`takeDrain` creates one generation-bearing, single-key logical lease over a
bounded contribution/item/byte quantum and the captured recovery revision; no
lock remains held while the consumer
processes it. The mailbox retains correctness custody until acknowledgement.
`transferred` means the domain owner synchronously accepted every captured
contribution into domain-owned reduction state and every captured recovery
revision into its authoritative recovery owner—not that recovery completed.
It clears only identical captured custody; a newer recovery revision survives
and produces the single follow-up wake. `retry` re-presents the identical
immutable lease before newer same-key contributions and never calls domain merge
code. Cancellation without acknowledgement, stale/double/foreign tokens, and a
closed doorbell cannot clear or strand custody.

The mailbox maintains a mechanical O(1) ready-key queue without inspecting key
or payload meaning. A first pending contribution makes that key ready once.
`takeDrain` selects one ready key and one bounded quantum. A retry remains ahead
of newer contributions for the same key but rotates behind unrelated keys that
were already ready, so one failing source cannot block bounded service to quiet
sources. This is custody scheduling only; actor-owned semantic priority,
debounce, routing, and coalescing remain outside the mailbox.

Producer and consumer capabilities are structurally separate. Callback owners
receive only a generation-scoped `GatherProducerPort` plus an
`AdmissionDoorbellSignaler`. The one domain drain owner receives a
`GatherConsumerPort` plus `AdmissionDoorbellConsumer`; lifecycle composition
alone retains `AdmissionDoorbellOwner`. A callback cannot wait, finish, drain,
acknowledge, seal, or invalidate; a consumer cannot bypass producer admission.

`GatherConsumerPort.bindConsumer()` returns one current
`AdmissionConsumerBindResult`. Binding a replacement atomically revokes the prior
binding's acknowledgement authority, observes retained custody, and reconstructs
a level signal in the returned wake directive. Lifecycle-owned composition
applies `.scheduleDrain` to the payload-free doorbell only after `bindConsumer()`
has returned and the mailbox lock is no longer held. If a prior binding held a lease, the replacement `takeDrain`
re-presents the identical immutable key/contributions/recovery capture under a
new binding-scoped token; the abandoned token becomes invalid. The same binding
cannot take a second lease while one is outstanding.

The split doorbell capabilities form one payload-free, capacity-one,
level-triggered liveness
hint owned beside the mailbox. The primitive mutates custody first and returns
`scheduleDrain`; signaling occurs only after unlocking. Duplicate signals may
collapse because the mailbox—not the doorbell—owns data. Consumer bind/rebind
atomically observes semantic or cleanup custody and returns the signal level to
be applied after unlocking; doorbell
completion closes waiting only. One long-lived consumer wait is permitted, but
no per-offer task or payload-bearing transport queue is.

Cleanup is a third physical-custody state, not a semantic delivery state. Each
primitive exposes the same bounded cleanup operation through its consumer and
lifecycle capabilities; the producer capability cannot invoke it. One signaled
consumer service cycle performs cleanup first and may perform at most one
declared cleanup quantum followed by at most one declared delivery lease.
`takeDrain` returns typed `.cleanupRequired` while cleanup remains or a release
turn is in flight, except that latest-value cleanup finalization may already
have pre-presented one capacity-supported active lease for the delivery half of
that same service cycle. A delivery acknowledgement that creates cleanup
custody reconstructs one level for the next cleanup-first cycle even when no
semantic work remains.

Cleanup references move from queued to in-flight under the lock without
reducing any physical count, release after unlocking, then finalize counters and
wake under the lock before the cleanup call returns. If cleanup remains, the
call returns exactly one `.scheduleDrain`. Latest cleanup finalization also
returns exactly one `.scheduleDrain` when it creates an unpresented active lease,
including after the final cleanup batch; lifecycle composition may instead
continue bounded cleanup turns directly during invalidation/teardown.
Doorbell completion is legal only after semantic custody, recovery/gap debt,
outstanding leases, replay-reader custody, queued cleanup, and in-flight cleanup
are all quiescent.

Each concrete consumer and lifecycle port conforms to
`AdmissionCleanupConsumer` and implements exactly
`performCleanup(generation:) -> AdmissionCleanupTurnResult`. The result uses the
shared `AdmissionCleanupTurn` payload above; domains do not invent a second
cleanup enum or callable name.

Cleanup configuration must permit forward progress: its entry quantum is at
least one. A byte-accounted family supplies a non-optional byte quantum at least
as large as the maximum byte footprint of one admissible retained entry; the
entry-only latest-value family uses `.entries(maximumEntries:)`.
Byte-accounted families use
`.entriesAndBytes(maximumEntries:maximumBytes:)`. Cleanup results mirror that
choice with `.entries(count:)` or `.entriesAndBytes(count:bytes:)` so a caller
cannot observe a missing or meaningless byte count. Configuration that cannot
release one entry is rejected before the primitive becomes usable.

The wake/lease state machine is normative:

| State | Operation | Next state and result |
| --- | --- | --- |
| `idle` | first accepted offer | `wakePending`; exactly one `scheduleDrain` |
| `wakePending` | additional offer | remains `wakePending`; `.noWake` |
| `wakePending` | `takeDrain` | `draining(token)`; pending wake is consumed |
| `draining(token)` | additional offer | `drainingAndDirty(token)`; `.noWake` |
| `draining*` | matching `acknowledge(transferred)` | move identical captured custody to cleanup; if pending/newer recovery or cleanup remains, `wakePending` plus exactly one `scheduleDrain`, otherwise `idle`/drained-sealed plus `.noWake` |
| gather/journal `draining*` | matching `acknowledge(retry)` | retain and re-present the identical lease ahead of newer same-key contributions; requeue that key behind already-ready unrelated keys; `wakePending` plus exactly one `scheduleDrain` |
| latest `draining*`, no newer same-key pending value | matching `acknowledge(retry)` | return the identical leased value to the replaceable pending slot; cleanup-first service applies and a later same-key offer may replace it through charged cleanup; revoke the acknowledged token; `wakePending` plus exactly one `scheduleDrain` |
| latest `draining*`, newer same-key pending value exists | matching `acknowledge(retry)` | move the older leased value to charged cleanup and preserve the newer pending value; physical and auxiliary custody do not increase; `wakePending` plus exactly one `scheduleDrain` |
| `draining*` | consumer cancellation/rebind | revoke the old binding token; custody remains authoritative; replacement binding re-presents the identical lease with a new token without another source offer |
| cleanup queued or in flight | `takeDrain` | no lease; typed `.cleanupRequired`; custody unchanged |
| latest cleanup finalized with a pre-presented active lease | bounded cleanup turn / next `takeDrain` | finalization returns exactly one `scheduleDrain` whether or not cleanup remains; the next authorized take presents that bounded lease, forms no second lease, and leaves auxiliary custody unchanged |
| latest cleanup finalizes while a lease is already outstanding | bounded cleanup turn | preserve the incumbent lease/token, create no second lease, leave newer values pending, and compute the next wake from incumbent/pending/cleanup custody |
| semantic work absent; cleanup retained | bounded cleanup turn | release at most the declared entry/byte quantum after unlocking; if cleanup remains, return exactly one `scheduleDrain` |
| cleanup turn in flight | concurrent/reentrant cleanup | typed `.alreadyCleaning`; this precedence holds even when a replay reader is also active; no mutation |
| queued journal cleanup exists, no cleanup turn is in flight, and a replay reader is active | bounded cleanup turn | typed `.blockedByReplayReader`; new cleanup detachment is pinned and reader completion owns the eligibility wake |
| any | stale, duplicate, or foreign acknowledgement | no mutation; typed rejection |
| open state | `seal` | reject new offers; retain and drain accepted work |
| any non-invalidated state | `invalidate` | discard generic state, revoke token, terminally reject; domain transfer precondition applies |

Concrete `takeDrain` precedence is normative. It validates generation,
terminal lifecycle, and consumer/binding authority first; it re-presents or
rejects an already-outstanding lease next. For an otherwise authorized call,
`.cleanupRequired` precedes creation of a new lease and precedes an
empty/sealed result. Presenting the latest-value lease atomically created by a
completed cleanup finalization is re-presentation, not creation of a second
lease. An invalidated primitive returns `.closed`; lifecycle cleanup remains
available through its cleanup-capable port.

Shared counter algebra is explicit. `offered` counts every attempt before
generation/lifecycle/key/footprint/capacity validation. `admitted` counts attempts for
which the primitive retained ordinary payload or an exact substitute custody
obligation. Rejection reasons are mutually exclusive and, before saturation,
`offered = admitted + rejectedStale + rejectedUndeclared + rejectedInvalid +
rejectedCapacity + rejectedClosed`. `contracted` is the subset of admitted attempts whose payload
does not remain independently drainable because it was replaced or represented
by recovery/gap custody; therefore `contracted <= admitted`.
`repairEscalations` is the orthogonal admitted subset that creates or advances
an exact recovery/gap revision. Actor-owned semantic coalescing input/output is
a later pipeline stage and never inferred from mailbox depth.

Gather admission preserves the same semantic combinations as distinct union
cases; it does not expose independently combinable payload and recovery fields:

| Offer condition | Payload disposition | Recovery revision | Counters |
| --- | --- | --- | --- |
| ordinary and within capacity | `.retained` | structurally absent | offered + admitted |
| explicit recovery signal, payload within capacity | `.retainedWithRecovery(revision)` | associated with case | offered + admitted + repair escalation |
| global/per-key capacity contraction | `.contractedToRecovery(revision)` | associated with case | offered + admitted + contracted + repair escalation |
| already exhausted recovery authority | `.contractedToRecovery(revision)` | revision carries `authorityExhausted` | offered + admitted + contracted; escalation only on first transition |
| stale/undeclared/invalid/closed | no admission receipt | none | offered + exactly one rejection |

A consumer switches exhaustively over the disposition or drain-payload case. It
never infers retained payload from an optional revision or an empty contribution
array.

`AdmissionDiagnostics` reports current retained-key depth and high-water.
Gather diagnostics additionally report current pending, leased, and cleanup
contribution/item/byte custody; queued-plus-in-flight cleanup metadata entry
count/high-water; semantic retained and physical retained current
values/high-waters; cleanup high-waters and typed oldest-age measurement;
recovery-slot count/high-water/typed age measurement; and outstanding lease
count. The equations are
`semanticRetained = pending + leased` and
`physicalRetained = semanticRetained + cleanupRetained` for every custody
dimension. `maximumRetained*` limits apply to physical retained custody globally
and per key. Lease and cleanup quanta are bounded service-turn subsets, never
additive capacity. Taking a lease or retiring a payload cannot make memory
disappear from diagnostics. A stream is quiescent only when physical retained
custody is zero and no recovery slot, persistent gap, outstanding lease, or
replay-reader debt remains. Diagnostic snapshots never contain keys or payloads.

Gather diagnostics are O(1) protected-state reads. Current counts/high-waters
are maintained incrementally. Oldest pending, recovery, and cleanup ages use
incrementally maintained mailbox-clock timestamp and precision watermarks; the
public `AdmissionAgeMeasurement` duration is computed at read time. A
measurement is exact while the literal oldest stamp is known; after an
interleaved removal
would require a fleet scan or ordered priority index to discover the next
literal minimum, the existing watermark becomes `.pressureConservative` and
cannot become younger until an exact bounded transition proves it or the
custody class becomes empty. This deliberately prefers possible over-alerting
to understated pressure or producer-side fleet work. Invalidation performs an
O(1) terminal state/storage ownership swap under the lock; it neither allocates
nor rebuilds the declared-key fleet there. Every detached slot with nontrivial
dynamic state—including recovery-only and zero-payload state—becomes exact
cleanup metadata custody. Its storage is intrusive, paged, or otherwise shaped
so one turn and the final cursor destruction retire at most the shared cleanup
entry quantum. No terminal `[KeyState]` fleet may fall out of scope in one
invalidation or final cleanup call. Immutable declared-key indexing and empty
default shells remain fixed configuration outside dynamic cleanup custody.
Their only dynamic lookup edge is weak. Because that private metadata identity
is not runtime-observable without exposing raw state, structural lint rejects a
weak-to-strong replacement, an additional strong shell property, and a strong
dynamic-node alias stored outside the declared live head/tail or bounded
cleanup owner.

`OrderedFactJournal<Fact, Snapshot>` synchronously validates generation,
assigns a monotonic per-stream sequence, and commits either the fact/current
state or an explicit `FactGap` before the producer reports success. A fact that
fits the declared history is never silently evicted before its required product
owner commits. When bounded retention is impossible, the journal commits a
non-evictable range-bearing gap, marks the stream non-current, and makes waits
and replay fail or resynchronize from the named snapshot. It never pretends the
missing occurrence was delivered. `FactGap` is shared sequence-range and opaque
gap-token mechanics, not a domain `RepairGeneration`; the domain fact owner maps
the gap to its authoritative recovery policy.

Journal configuration declares maximum retained fact count/bytes, one
`OrderedFactSnapshotLimits`, maximum facts per delivery lease, and one
`AdmissionCleanupQuantum`:

```swift
struct OrderedFactSnapshotLimits: Sendable, Equatable {
    let maximumSnapshotBytes: Int
    let maximumPhysicalSnapshotCount: Int
    let maximumPhysicalSnapshotBytes: Int
}

struct OrderedFactSnapshotReplacement<Snapshot: Sendable>: Sendable {
    let snapshot: Snapshot
    let estimatedBytes: Int
}
```

`maximumSnapshotBytes` is the individual semantic snapshot limit. Physical
count/bytes cover the current snapshot plus queued and in-flight cleanup
snapshots. Count is independently mandatory because zero-byte snapshots retain
objects and metadata. Valid configuration guarantees one maximum-size atomic
replacement overlap: physical count is at least two and physical bytes are at
least the checked product `2 * maximumSnapshotBytes`. Larger explicit budgets
permit a bounded replacement burst. The cleanup quantum bounds reclamation
work only; it does not enlarge either fact-history or snapshot capacity and its
byte quantum can release one maximum-size snapshot.

Initial snapshot configuration accepts one
`OrderedFactSnapshotReplacement<Snapshot>?`, not separate optional snapshot and
byte-count parameters. `nil` therefore means that no initial snapshot exists;
when a snapshot exists, its estimated footprint is structurally inseparable
from it. Atomic replacement and authoritative recovery use the same bundled
value. A snapshot payload and its size cannot disagree about whether the
snapshot exists.

Fact-history count/bytes and physical-snapshot count/bytes have independent
limits; total retained payload memory is bounded by their declared sum plus
bounded metadata. A required initial or atomic replacement snapshot that
exceeds its individual snapshot budget receives typed configuration/offer
rejection. An atomic
fact-plus-snapshot offer assigns no sequence and reports no partial admission
when its snapshot is rejected. Oversize is never silently ignored and never
creates an artificial occurrence gap for a fact the journal did not accept.
An individually valid snapshot whose projected current plus queued/in-flight
cleanup custody would exceed either physical snapshot limit returns
`.snapshotPhysicalCapacityExceeded`. Offer rejection occurs before sequence
assignment, fact/history mutation, gap/currentness change, snapshot replacement,
admission counters, or wake scheduling; it advances only `offered` and
`rejectedCapacity`. Authoritative recovery returns the same typed pressure
result without changing the existing gap or admission counters.
`.snapshotTooLarge` remains reserved for an input that alone exceeds
`maximumSnapshotBytes`.

The journal result algebras include the pressure cases directly:

```swift
enum OrderedFactOfferResult: Sendable {
    case admitted(sequence: UInt64, wake: AdmissionWakeDirective)
    case gapCommitted(FactGap, wake: AdmissionWakeDirective)
    case snapshotTooLarge
    case snapshotPhysicalCapacityExceeded
    case invalidSize
    case authorityExhausted
    case staleGeneration
    case closed
}

enum OrderedFactRecoveryResult: Sendable, Equatable {
    case recovered
    case staleGeneration
    case staleGapToken
    case incorrectSequence
    case snapshotTooLarge
    case snapshotPhysicalCapacityExceeded
    case invalidSize
    case notNonCurrent
    case closed
}
```

Every fact or snapshot byte estimate below zero receives a distinct typed
`invalidSize` rejection before sequence allocation, gap/currentness change,
snapshot replacement, history mutation, or wake scheduling. Initial
configuration distinguishes `initialSnapshotInvalidSize` from
`initialSnapshotTooLarge`; offer and atomic replacement use
`OrderedFactOfferResult.invalidSize`; authoritative resynchronization uses
`OrderedFactRecoveryResult.invalidSize`. Exactly one invalid-admission counter
advances for a rejected producer operation.

Ordinary eviction of already-acknowledged bounded replay history does not mark a
healthy stream globally non-current. A request older than retained acknowledged
history receives an explicit query-local `ReplayHistoryGap`, or a typed current
snapshot resynchronization when the caller requested and the snapshot covers
that cursor. Only inability to retain unacknowledged or leased exact facts
commits the persistent `FactGap`. Delivery acknowledgement never clears that
gap; only matching current-generation authoritative resynchronization carrying
the gap token and a snapshot through the gap's upper sequence may clear it.
While a persistent gap exists, every subsequent offered exact fact is assigned
the next sequence and atomically widens the gap before the offer reports
accepted-as-gap; its payload is not retained as if delivered. Widening advances
the opaque gap token, so recovery for an older range is stale. A domain without
an authoritative snapshot/rebuild capable of covering the latest upper
sequence remains explicitly non-current; it cannot acknowledge occurrence loss
away.

The journal separately retains `historyUnavailableThrough`, initialized from a
nonzero initial sequence without retained occurrences and advanced by
acknowledged-history eviction and successful persistent-gap recovery. Clearing
product non-currentness therefore does not pretend exact occurrence history was
recreated. Even when the retained fact array is empty, an exact-history cursor
at or below this watermark receives `ReplayHistoryGap`; a covering current
snapshot is returned only for explicit current-snapshot recovery.

The journal exposes distinct typed offer/replay results. An admitted offer
returns its sequence and wake directive; an overflow offer returns
`gapCommitted(FactGap, wake:)`, never ordinary admission. A replay result is one
of exact retained facts, current-snapshot resynchronization, persistent product
gap, query-local replay-history gap, invalid cursor, replay contention, stale
generation, or invalidated. Persistent product currentness has precedence over
every cursor validation/result, including a future cursor:

```swift
enum OrderedFactImmediateReplayResult: Sendable {
    case factGap(FactGap)
    case invalidCursor(latestSequence: UInt64)
    case replayInProgress
    case staleGeneration
    case invalidated
}

enum OrderedFactRegisteredReplayResult<Fact: Sendable, Snapshot: Sendable>: Sendable {
    case facts([SequencedFact<Fact>], nextSequence: UInt64)
    case snapshot(
        SequencedSnapshot<Snapshot>,
        followingFacts: [SequencedFact<Fact>],
        nextSequence: UInt64
    )
    case historyGap(ReplayHistoryGap<Fact>)
}

enum OrderedFactReplayCompletion<Fact: Sendable, Snapshot: Sendable>: Sendable {
    case immediate(OrderedFactImmediateReplayResult)
    case registered(
        OrderedFactRegisteredReplayResult<Fact, Snapshot>,
        wake: AdmissionWakeDirective
    )
}
```

`replay(after:generation:recovery:)` returns
`OrderedFactReplayCompletion`. A registered result linearizes at the bounded protected
capture: facts offered after the captured stop tail are excluded. Exactly one
replay reader may own capture authority. Immediate stale-generation,
invalidated, persistent-gap, and invalid-cursor results require no reader and
retain their stated precedence. A request that would otherwise register a
history capture while the reader is occupied returns
`.immediate(.replayInProgress)` and performs no mutation. Immediate cases carry
no wake field; only `.registered(result, wake:)` can return the cleanup-
eligibility wake. It never reports false invalidation, blocks
a caller, queues a replay, or allocates another reader.

Invalidation rejects a replay that has not captured reader authority; a replay
registered before invalidation may finish and return its captured result. Any
active reader conservatively pins all queued journal cleanup, regardless of
whether its particular recovery mode will return facts or a snapshot. A cleanup
turn that detached its batch before reader acquisition is not reachable from
the later capture; its incumbent authority continues unlocked destruction and
finalization normally. While that incumbent turn exists, another cleanup call
returns `.alreadyCleaning` even if the reader is active. After it finalizes,
`performCleanup` returns `.blockedByReplayReader` exactly when queued cleanup
exists and the reader remains active; it returns `.empty` only when neither
queued nor in-flight cleanup exists. This global queued-custody policy avoids a
cleanup-queue scan or per-entry pin graph. Its accepted cost is temporary fact/
snapshot capacity pressure during the one bounded replay materialization.

Releasing reader authority at completion returns `.scheduleDrain` exactly when
it makes retained cleanup eligible and no equivalent level is already pending.
Lifecycle composition applies that wake only after replay returns and the
journal lock is not held.

| Journal state | Replay request | Result |
| --- | --- | --- |
| current; cursor retained | any supported recovery mode | exact facts |
| current; acknowledged cursor evicted; covering current snapshot requested | state resynchronization | snapshot plus following retained facts |
| current; acknowledged cursor evicted; exact occurrence requested or no covering snapshot | any | `ReplayHistoryGap` |
| persistent `FactGap` | any cursor or recovery mode | persistent `FactGap`; optional snapshot may be offered only as a recovery candidate |
| persistent `FactGap` plus later offer | offer | widen range/token synchronously; return `gapCommitted` |
| persistent `FactGap` plus stale token/range recovery | resynchronize | typed stale/mismatch; gap unchanged |
| persistent `FactGap` plus matching latest token, generation, upper sequence, and authoritative bounded snapshot/rebuild | resynchronize | current at the supplied sequence; later sequence allocation continues monotonically |
| current capture required; another reader active | replay | `.replayInProgress` plus `.noWake`; no mutation |

The journal retains pending/leased facts until one required product drain owner
acknowledges transfer into the downstream fact owner. Multiple subscriber
acknowledgements are downstream transport policy and do not enlarge the generic
journal. A journal drain acknowledgement is therefore mechanical transfer, not
proof that every eventual subscriber consumed the fact.

Journal replay does not traverse, filter, reserve, or materialize retained
history while holding the producer admission lock. Under the lock it captures
only bounded scalar currentness/watermark/snapshot metadata plus immutable
start/stop history references and registers one replay-reader authority. It
then materializes through the captured stop tail outside the lock and releases
that reader authority in a bounded protected-state operation that produces the
completion wake above. Concurrent offers
after the stop tail are excluded from that replay result. Detached history or
snapshots that may still be referenced by a replay reader remain in queued
capacity-accounted cleanup custody. Their physical counters do not decrement
until the reader completes and a later bounded cleanup turn releases the
primitive's references. An earlier in-flight batch is absent from the captured
semantic view and finalizes under its incumbent authority.

Ordered-journal diagnostics separately report semantic retained fact/snapshot
custody, queued and in-flight cleanup fact/snapshot entry counts and bytes,
physical retained fact/snapshot counts and bytes, matching high-waters, cleanup
oldest age, active replay-reader count, and quiescence. Its directly assertable
snapshot equations are:

```text
cleanupSnapshot = queuedCleanupSnapshot + inFlightCleanupSnapshot
physicalSnapshot = semanticSnapshot + cleanupSnapshot
```

The same queued/in-flight physical equations apply to facts. Journal offer,
bind, acknowledgement, replay capture/completion,
diagnostics, seal, and invalidation perform bounded protected-state work;
replay materialization scales with the requested retained history only after
unlocking.

All three families:

- bind each mailbox/journal instance to one `AdmissionGeneration`; generation N
  cannot merge into N+1, and rotation creates a fresh instance;
- expose `offer`, `takeDrain`, drain acknowledgement, `seal`, `invalidate`, and
  `diagnostics` with the semantics above;
- return at most one `scheduleDrain` directive before a take; offers during a
  drain produce at most one follow-up directive after acknowledgement, and the
  primitive never creates a task or invokes domain code while holding state;
- return typed `.cleanupRequired` instead of creating another lease while
  queued or in-flight cleanup must be serviced;
- keep producer admission expected O(1) for a fixed input shape; consumer-side
  bounded lease formation may scale only with the declared lease quantum, not
  the full fleet;
- keep bind/rebind, diagnostics, replay capture/completion, cleanup detachment,
  and invalidation bounded independently of declared-key or retained-history
  fleet size; payload release scales only with the explicit cleanup quantum;
- keep diagnostic oldest-age fields typed as `AdmissionAgeMeasurement?` because
  their custody sets may be empty; latest and journal drains are structurally
  nonempty, so their `oldestRetainedAge` is a dedicated `ExactAdmissionAge`
  that cannot represent pressure-conservative precision;
- keep raw locks, mutable state, cleanup cursors, and authority lexically
  private to one storage owner; cross-file code receives only typed operations,
  immutable captures, or pure post-lock values and never a generic lock/state
  closure escape;
- define `seal` as graceful terminal admission closure that drains accepted
  work, and `invalidate` as immediate terminal revocation that discards pending
  work and makes outstanding tokens stale;
- require a domain wrapper to transfer any authoritative repair/fact-gap debt
  before invalidation; generic invalidation cannot be the last owner of
  correctness debt;
- keep diagnostic-record loss separate from product repair/fact gaps;
- have domain-specific wrappers that fix key/contribution types, actor-owned
  reduction, recovery mapping, capacity policy, and callback-return behavior at
  compile time.

Protected-state architecture enforcement is structural, not a helper-name
manifest. Each primitive enters its raw lock only through one
`withAdmissionProtectedState`-style owner that supplies an unforgeable
`AdmissionProtectedRegionToken`. Every helper accepting raw mutable state also
accepts that token, and every token-bearing body is inspected. Direct raw
`withLock` use elsewhere, raw state without the token, unresolved protected
helpers, and lock/state escape fail lint. Inside a protected region, loops,
eager materializers, fleet copies, and aliases of protected collections are
rejected unless a recognized typed delivery/lease/cleanup quantum structurally
dominates the work. Post-lock immutable replay or drain materialization carries
no token and remains legal. Renaming a helper cannot remove coverage.

The architecture linter remains SwiftParser/SwiftSyntax-only, so protected code
uses one deliberately restricted, syntax-resolvable grammar. The wrapper and
raw lock/state are lexically private to the same owner. Token-bearing helpers
are uniquely declared, non-overloaded `private` functions on that owner and are
invoked only by direct calls whose token argument is visible in the syntax
tree. The token cannot be constructed outside the wrapper, stored, returned,
captured by an escaping closure, converted to a function value, passed through
protocol/dynamic dispatch, or forwarded through an unresolved generic/higher-
order call. A direct-call target with zero or multiple matching declarations,
an indirect helper reference, or an unsupported alias/escape is a lint failure,
not a reason to guess or silently skip coverage. This restricted grammar lets
the rule build a closed syntactic protected-helper graph without adding compiler
semantic-resolution dependencies or returning to a manual name manifest.

The same fail-closed ownership grammar covers configuration-lifetime slot-index containers.
Their class-typed dynamic-custody edges must be `weak`, and raw state may not
retain another strong alias to those nodes outside its declared live head/tail
or bounded cleanup owner. Required restored-source mutations replace the weak
edge with strong storage, add another strong shell property, and add a strong
raw-state alias; each must fail lint while production passes. Runtime cleanup
tests continue to prove payload-bearing custody, turn bounds, counters, age,
and quiescence, but they do not claim to observe a private recovery-only
metadata identity.

Lease, recovery, gap, generation, and sequence authority tuples never alias
after counter exhaustion. For gather recovery, incrementing a sequenced stamp
at `UInt64.max` atomically installs the distinct `authorityExhausted` stamp,
seals further ordinary admission, returns an admitted receipt with
`contractedToRecovery` plus the typed exhausted revision,
and retains exact custody until the domain owner transfers it and rotates the
mailbox generation. An acknowledgement for `.sequenced(.max)` cannot clear the
exhausted marker. Other primitives equivalently rotate an opaque epoch/identity
only when safe or return a typed terminal/non-current result while retaining
accepted custody and exact debt. No counter resets within the same authority
epoch, and exhaustion never silently invalidates or discards accepted work. Invalidated
journal diagnostics report non-current even when no persistent product gap is
retained.

The shared admission module owns mechanics only. Terminal, filesystem, Git,
Bridge, and performance domains own their typed payloads and semantic policy.

### Runtime Fact Bus And Topic Taxonomy

`RuntimeFactBus` is the sole global product-fact transport. It is implemented by
the existing generic EventBus machinery, but its public product surface accepts
only a `RuntimeFactEnvelope`; raw runtime samples and commands cannot construct
one.

```swift
enum RuntimeTopic: CaseIterable, Sendable {
    case workspaceLifecycle
    case paneLifecycle
    case workspaceTopology
    case filesystemTopology
    case filesystemChange
    case gitState
    case forgeState
    case terminalMetadata
    case terminalLifecycle
    case terminalCommand
    case terminalActivity
    case userNotification
    case security
    case browserDomain
    case diffDomain
    case editorDomain
    case pluginDomain
    case artifact
    case runtimeError
    case bridgeDomain
}

struct RuntimeFactEnvelope: Sendable {
    let source: RuntimeSource
    let sourceGeneration: UInt64
    let sourceSequence: UInt64
    let emittedAt: ContinuousClock.Instant
    let fact: RuntimeDomainFact
}

func subscribe(
    topics: Set<RuntimeTopic>,
    delivery: BusSubscriberPolicy,
    replay: RuntimeFactReplayRequest,
    subscriberName: String
) -> RuntimeFactSubscription
```

`RuntimeDomainFact.topic` is one exhaustive mapping owned with the fact enum; a
publisher cannot supply an arbitrary topic. The bus filters topic interest
before replay lookup and before subscriber queue admission. A production
subscriber declares a nonempty topic set and explicit delivery policy.

Topic recovery is fixed as follows:

| Recovery shape | Topics |
| --- | --- |
| latest by source/consolidation key | `workspaceTopology`, `filesystemTopology`, `gitState`, `forgeState`, `terminalMetadata`, `terminalLifecycle`, `browserDomain`, `diffDomain`, `editorDomain`, `pluginDomain` |
| latest current invalidation/currentness; no raw path history | `filesystemChange` |
| bounded ordered history with explicit gap | `workspaceLifecycle`, `paneLifecycle`, `terminalCommand`, `terminalActivity`, `userNotification`, `security`, `artifact`, `runtimeError` |
| no product replay | `bridgeDomain` |

The global transport cutover is exhaustive. `PaneRuntimeEventBus` is removed as
a global transport. `RuntimeEnvelope` and `PaneRuntimeEventChannel` may remain
only as pane-local runtime subscription/replay machinery for nonterminal
runtimes; their outbound global stream and `EventBus<RuntimeEnvelope>` instance
do not survive. Terminal runtimes leave that channel entirely and expose
current snapshot plus ordered fact-journal queries from `TerminalFactOwner`.

Every former global `PaneRuntimeEvent` producer has one selected disposition:

| Existing family | Post-cutover disposition |
| --- | --- |
| pane lifecycle | `paneLifecycle` fact |
| terminal / terminal activity | terminal child's typed snapshot, fact, activity, and command planes |
| browser | local UI/console samples remain local; cross-feature semantic output uses `browserDomain` |
| diff / review / Bridge | local presentation remains local; semantic output uses `diffDomain` or `bridgeDomain` |
| editor | local presentation remains local; semantic output uses `editorDomain` |
| plugin | local presentation remains local; declared semantic output uses `pluginDomain` |
| agent notification | exact `userNotification` request |
| pane filesystem context | local pane snapshot; named cross-feature invalidation uses `filesystemChange` |
| filesystem / Git / Forge | split across the existing filesystem, Git, Forge, and diff topics by fact type |
| artifact | `artifact` |
| security | `security` |
| runtime error | `runtimeError` with content-safe error classification |

The generic `PaneRuntime` `subscribe`/`eventsSince` contract remains local to
the selected runtime. IPC subscriptions to a nonterminal pane attach to that
runtime directly. Terminal IPC status/wait attaches to `TerminalStateSnapshot`
and `TerminalFactOwner.facts(after:)`; it does not adapt facts back into legacy
terminal envelopes or read the global bus. A structural post-cutover inventory
must find exactly one global product bus and no production post to
`EventBus<RuntimeEnvelope>`.

`filesystemChange` is admitted only after source contraction and exists for
named product consumers. Its recovery snapshot carries current worktree/root
generation, content revision/currentness, and bounded invalidation state, not a
replay of every path occurrence. Internal filesystem-to-Git invalidation does
not use it. Commands, UI/activity samples, screen content, telemetry, and internal
repair messages never construct `RuntimeFactEnvelope`.

Ordering is per declared source generation and semantic stream. Accidental total
order across unrelated topics is not a product contract. Correctness-bearing
facts have a named authoritative owner outside transport so subscriber lag or a
visible replay gap does not silently erase canonical truth.

### Typed MainActor Apply Boundary

Every off-main projector produces a domain-specific immutable mutation and the
only MainActor entry is a named applier:

```swift
@MainActor
protocol MainActorMutationApplier<Mutation>: AnyObject {
    associatedtype Mutation: Sendable
    associatedtype Receipt: Sendable
    func apply(_ mutation: Mutation) -> Receipt
}
```

An applier may revalidate generation/base revision, mutate already-keyed
canonical state, advance revisions, and return a typed receipt. It may not
scan, normalize, join, serialize, schedule retries, publish derived same-bus
loops, or reread a fleet to discover what changed.

## Shared Architecture Decisions

### Semantic Transport

The selected cut preserves one generic EventBus implementation behind the
`RuntimeFactBus` contract above. It hard-cuts terminal and filesystem producers
and all other pane-runtime global producers to fact-only publication, while
retaining local-only runtime subscriptions where their pane protocol needs
them. It adds exhaustive typed topic interest before replay and subscriber
queue admission. The bus owns transport, fact-specific replay, fanout, and
lag/drop diagnostics. It does not own raw source observations, terminal or
nonterminal presentation samples, local runtime replay, domain joins, retry
loops, projection, commands, or UI mutation.

Several physical buses remain a future measured escape only if the contracted
workload shows material cross-topic bus service/queue delay or two topics prove
incompatible in ordering/backpressure/recovery. They are not an implementation-
plan option. The fact/topic types and recovery contracts remain stable if the
transport is later partitioned.

### MainActor Last Mile

MainActor owns canonical `@Observable` atoms, AppKit calls, and WebKit delivery.
It accepts typed changed-key mutations and bounded pane-local current-state
updates. It does not own source backlogs, scan scheduling, fleet joins,
canonicalization, Git reads, JSON/regex work over fleets, persistence snapshot
normalization, Bridge package construction, or same-bus derived loops.

Every asynchronous-to-MainActor boundary records separately:

- producer enqueue timestamp;
- MainActor start timestamp;
- synchronous service end;
- operation/domain and generation/revision;
- input and changed-key counts;
- safe run correlation.

`MainActorWorkLedger` is the sole acceptance-grade owner of those records. A
producer calls `enqueue` before the hop, then the MainActor entry executes one
synchronous `withMainActorWork` region. The region cannot span `await`.

```swift
struct MainActorWorkRecord: Sendable {
    let workID: OpaquePerformanceWorkID
    let parentWorkID: OpaquePerformanceWorkID?
    let runToken: OpaquePerformanceRunToken?
    let domain: MainActorWorkDomain
    let operation: MainActorWorkOperation
    let generationOrRevision: UInt64?
    let enqueuedAt: ContinuousClock.Instant
    let startedAt: ContinuousClock.Instant
    let synchronousEndedAt: ContinuousClock.Instant
    let inputCount: Int
    let changedKeyCount: Int
    let outcome: MainActorWorkOutcome
}
```

Mandatory coverage includes every typed canonical applier, Ghostty app tick,
workspace persistence page capture, Bridge immutable-input capture and WebKit
send, and any remaining critical `RuntimeFactBus` delivery that executes on
MainActor. Queue delay and synchronous occupancy are separate distributions.
Suspended time is never actor occupancy. Stack samples and signposts are
diagnostic corroboration, not substitutes for these records.

The calibration manifest precommits absolute synchronous-service ceilings and
fixed-changed-key scaling envelopes for topology apply, persistence page
capture, Bridge capture, WebKit send, and Ghostty tick. The same changed-key
work across 10/100/300-worktree fixtures must not grow with total fleet size.
An over-ceiling named span fails even when end-to-end interaction happens to
pass.

An independent responsiveness probe records run-loop starvation. A heartbeat
gap is evidence of starvation, not proof that the immediately preceding named
operation caused it. Stack samples/signposts and work-item spans provide causal
attribution.

### Startup Composition, Terminal Activation, And External Reconciliation

Startup has three independently owned readiness lanes. Composition is prepared,
validated, and deterministically repaired off-main, then installed in one
bounded MainActor transaction. The prepared composition includes pane identity,
content/provider, frozen zmx anchor, launch configuration, drawer/tab/layout
membership, local cursors, and window/sidebar presentation state. It excludes
repository/worktree identity, Git state, filesystem currentness, and derived
pane location context.

Canonical `Pane` exposes no `repoId` or `worktreeId` facet/accessor.
`SessionResidency` contains only repository-independent process/UI lifecycle
states; repository or worktree unavailability is never a residency case.

An accepted composition transaction emits one immutable
`TerminalActivationInput`. The terminal activation owner immediately schedules
restorable terminal panes by strict priority: active visible terminals, other
visible/expanded-drawer terminals, then hidden terminals with an already-live
zmx session. Active attachment never awaits hidden-session discovery. A hidden
pane with no live zmx session remains valid composition but dormant until user
selection; startup does not silently create a new hidden shell.

Nonterminal restoration has a separate `ViewCompositionRestoreOwner`. It owns
visible-first construction and MainActor mounting for webview, code-viewer,
Bridge, and other nonterminal content; it does not create, attach, or classify
terminal runtimes. The prepared composition exposes an exhaustive content union,
so each pane is routed to exactly one restoration owner and can mount at most
once for a composition generation. Expanded-drawer panes are visible priority.
Background nonterminal mounting does not delay active-content readiness.

`windowReady`, `activeContentReady`, `typingReady`,
`visibleContentSettled`, and `allRestorableTerminalsReady` are distinct
current-generation milestones. `windowReady` requires accepted composition and
the workspace shell; an empty workspace reaches `activeContentReady` when its
empty state is installed. An active nonterminal pane reaches
`activeContentReady` when its current-generation view mounts. For an active
terminal pane, `typingReady` implies `activeContentReady` and requires surface
creation, attachment, mount, focus, and runtime readiness. Mixed workspaces gate
active readiness only on the active pane. `visibleContentSettled` covers every
visible main/expanded-drawer pane reaching its content-specific ready, dormant,
or failed outcome; it does not gate active interaction. Terminal background
attachment gates neither window nor active-content readiness. Surface creation
and AppKit mounting remain MainActor-owned, but schedulers, inventory,
prioritization, retry, and currentness bookkeeping execute outside MainActor and
admit only bounded service quanta back to it.

Repository/filesystem startup is a separate non-blocking lane. Persisted
topology may provide last-known display state, but discovery, Git validation,
watched-root registration, and CWD-to-topology matching never gate window or
terminal readiness. Repository removal invalidates and recomputes derived pane
location projection only; it never changes pane residency, tab membership,
terminal lifecycle, or zmx attachment.

Coordinated SQLite checkpoints may share one persistence revision, but that
storage transaction does not merge composition and topology validation,
hydration, mutation, or runtime ownership. Steady-state composition and topology
writes enter the persistence coordinator as separate typed change sets.

### Atoms And Observables

Atoms own canonical state or pure derived state, Jotai-style. Narrow mutation
methods encapsulate writes; they do not confer business ownership. Atom methods
may assign caller-supplied values, suppress equal writes, perform simple local
transforms, and maintain storage indexes or observation invariants.

Atoms do not interpret commands/events/workflows, validate or normalize domain
input, prepare mutation plans/preimages/rejections/effects, coordinate other
owners, persist, perform I/O or async work, or publish/subscribe through runtime
transport. Pure domain types decide; coordinators sequence; persistence adapters
capture/restore; projectors compute off-main; atoms receive final state. A
`MainActorMutationApplier` is a coordinator/applier boundary, not an atom
protocol. Atom observation never initiates canonical mutation or fact delivery.

UI-memory persistence is checkpointed, not event-rate. Continuous window/sidebar
geometry renders locally and produces one settled canonical checkpoint; discrete
toggles/selections may commit once immediately; text-like or bursty UI memory
may update its UI owner immediately while the persistence pump coalesces the
latest committed revision. No pointer/key callback performs SQLite work, and
persistence acknowledgement never repairs or mutates installed canonical state.

### Safe Authority Defaults

- Local canonical watched roots are authoritative for complete-scan absence.
  Non-local, removable, disconnected, or permission-volatile roots remain
  non-destructive when unavailable until explicit product support exists.
- Git metadata may inform repository identity across paths, but it cannot create
  new watcher authority outside an already user-authorized canonical root.
- Screen-content capture remains a constraints-only future boundary until a
  requester, recipient, user action/consent surface, and result lifetime are
  accepted. Baseline agent or self-pane authority does not include it.
- Terminal-controlled metadata and agent reports are untrusted data and never
  grant command, filesystem, permission, or cross-pane authority.

## Shared Performance Harness Contract

One AgentStudio-owned harness extends the standard isolated debug-observability
runner. It owns the run marker, fixture manifest, build identity, monotonic clock
mapping, stage schema, correlation, final evidence drain, and acceptance report.

The owner and record contracts are normative:

```swift
struct PerformanceRunContext: Sendable {
    let runToken: OpaquePerformanceRunToken
    let scenario: PerformanceScenarioID
    let buildIdentity: PerformanceBuildIdentity
    let monotonicEpoch: MonotonicClockEpoch
}

struct PerformanceStageRecord: Sendable {
    let runToken: OpaquePerformanceRunToken
    let stream: PressureStreamID
    let sourceGeneration: UInt64
    let sourceSequence: UInt64
    let stage: PerformanceStage
    let monotonicNanoseconds: UInt64
    let inputCount: Int
    let outputCount: Int
}

struct PerformanceRunValidity: Sendable {
    let offered: UInt64
    let recorded: UInt64
    let lost: UInt64
    let sequenceGaps: UInt64
    let missingRequiredStages: Set<PerformanceStage>
    let allSourcesDrained: Bool
    let probePerturbationWithinAllowance: Bool
}

enum PerformanceRunOutcome: Sendable {
    case validPass
    case validFail
    case invalidEvidence
}
```

`PerformanceProbeSink.record` is synchronous, nonblocking, and behavior-free.
Product code cannot branch on probe presence or results. Loss is permitted only
when the independent validity owner records it; any missing required stage,
failed final drain, insufficient sample support, stale build/run identity,
unresolvable histogram precision, or over-budget probe perturbation produces
`invalidEvidence`, never zero or pass.

The watched-folder child supplies source/topology/Git/Bridge pressure factors.
The terminal child supplies deterministic echo/cursor fixtures, Ghostty host
stages, surface states, and version/host build factors. They do not create
separate runners or definitions of interaction latency.

The terminal child selects `frameLayerPublished`—successful assignment of the
rendered IOSurface to the Ghostty-owned layer—as the mandatory precision
endpoint through an equivalent benchmark-only hook in both vendor builds. It is
not physical scanout. Native PID-targeted proof establishes visible echo/caret/
focus behavior without relabeling automation time as key-to-present latency.

### Scenario Manifest

Every scenario declares:

- initial persisted/runtime state;
- trigger and writers;
- control work and variant work;
- measurement start;
- interaction-ready point;
- pressure-stop point;
- convergence/repair-complete predicate;
- independent expected-state oracle;
- required stage records and evidence-loss policy.

`interactionReady` has one shared meaning: the key window is active; the
selected current-generation terminal is mounted, input-eligible, render-
eligible, focused, and has valid geometry; and a deterministic interaction
probe has been admitted. It is independent of watched scan, Git, sidebar,
Bridge, or repair convergence.

Filesystem scenarios also record distinct `watchRequestAccepted`,
`firstUsefulTopology`, and `repairQuiescent` markers. Terminal scenarios record
the following causally joined distributions:

- event timestamp to AppKit handler entry;
- handler entry to Ghostty input-call return;
- fixture response mutation to qualifying current-generation
  `frameLayerPublished`;
- event timestamp to the same qualifying `frameLayerPublished`;
- maximum MainActor run-loop starvation gap.

The event-timestamp-to-layer-publication distribution is the product interaction
gate. Handler-only time cannot substitute for it. The child spec adds mandatory
cursor/mouse/reveal endpoints without calling layer publication physical
scanout.

Initial add, cold boot, and steady-state churn are distinct scenarios. Initial
add does not compare a full scan/import with a no-op control: it either uses an
equivalent one-shot scan/import control with watching disabled. Cold boot and
steady state use paired watched/no-watched fixtures where useful work is
otherwise equivalent.

### Evidence Integrity And Correlation

Cross-stage joins use trace/span linkage or ephemeral marker-scoped opaque
tokens unrelated to product IDs. OTLP receives bounded aggregate dimensions and
safe linkage only. Raw paths, pane/surface/root/registration IDs, terminal text,
payloads, prompts, commands, URLs, and errors remain excluded.

The high-rate trace queue is not its own proof of completeness. A bounded,
non-evictable or out-of-band run summary records expected stages, admitted,
recorded, dropped, sequence gaps, final drain result, and run validity. Missing
required stages or failed drain invalidates the run.

Every report records trial/sample counts, warmup exclusion, paired-control
identity, histogram or raw-summary resolution around each ceiling, and every
excluded sample. There is no undeclared outlier trimming. Numeric ceilings and
capacity values become normative only through a human-approved calibration
manifest produced from baseline/control distributions before candidate
acceptance; the optimized result cannot choose its own threshold.

Before candidate measurement, that manifest also freezes minimum independent
trial count, minimum samples per reported percentile, stopping rule,
independence assumptions, histogram/raw resolution around each ceiling, and
the rule for excluded or retried trials. A run stopped early or lacking the
precommitted support is `invalidEvidence`; the candidate cannot choose sample
adequacy after observing results.

### Matrix Shape

The harness defines:

1. a 34-cell mandatory shared core per trial set: ten watched convergence cells
   (`WF-ADD-SCALE-V1`, `WF-COLD-BOOT-V1`, and `WF-HUGE-STEADY-V1`) plus the
   terminal child's 24 vendor/host factorial cells;
2. one-factor and pairwise diagnostic submatrices;
3. separate measurement-probe perturbation controls and profiler/sample runs
   that never substitute for core latency gates.

The watched child owns the exact ten-cell scenario manifests. The terminal
child owns the exact 24-cell build/workload table and reuses
`WF-HUGE-STEADY-V1` in its loaded rows. Dimensions listed elsewhere are
diagnostic coverage requirements, not an implicit full Cartesian product.
Every causal comparison differs only in the factor it claims to isolate and
records the exact app, vendor, compatibility adaptation, measurement probe,
fixture, and configuration identities.

The terminal loaded rows are composite stress gates, not watcher-factor
comparisons: they add the complete watched-plus-writer/noise workload. Watcher
attribution belongs only to the watched child's selected-product-build pair,
whose control executes the identical writer/noise trace with watching
disabled. This preserves the enumerable 34-cell core without making a
confounded causal claim.

## Requirements / Proof Ownership

| Requirement family | Contract owner | Required proof |
| --- | --- | --- |
| shared source admission custody | parent | literal latest/gather/journal state models; compile-time negative fixtures proving forbidden correlated/sentinel constructions do not typecheck; exhaustive public offer/gather/cleanup unions and private offer/replay/cleanup captures; paired bind/doorbell liveness; semantic/queued-cleanup/in-flight-cleanup/physical custody equations; bounded latest `D/R/C` delivery, replacement pressure, cleanup-finalization lease progress, and lossy-or-authoritative-resample wrapper disposition; zero-byte and maximum-size journal snapshot physical limits; deterministic destructor barriers; recovery-only gather metadata cleanup; typed negative-size/capacity rejection; bounded protected-state offer/replay-capture/diagnostics/invalidation proof across 1/100/300 and large fleets; private raw-state capability proof; rename/alias/helper-pass-through structural mutations; no domain closure/task/payload queue; cancellation/rebind, capacity, token-exhaustion, counter-algebra, and payload-free diagnostic proof |
| FSEvent loss and topology repair | watched-folder child | deterministic loss/repair plus independent final oracle |
| topology/MainActor/persistence fairness | watched-folder child | work-item spans, responsiveness probe, scaling workload |
| semantic topic transport | parent + watched-folder child | structural policy, queue admission, lag/recovery proof |
| Ghostty tick/action admission | terminal child | state/origin tables, races, sustained producer pressure |
| terminal sample contraction/activity parity | terminal child | sequence oracle, bounded flood, semantic parity |
| startup composition and terminal readiness | parent + terminal child | rejected/repaired/prepared composition states; active-before-hidden attachment; bounded MainActor activation service; distinct window/typing/all-restorable milestones; delayed repository-lane injection |
| secure input/screen boundary | terminal child | owner-state races, denied capture, export canaries |
| combined typing/cursor symptom | shared harness | correlated watched-pressure, input-to-frame-layer-publication tails, and native visible outcomes |

The shared ordered-journal proof is a mandatory red/green regression matrix,
not an inference from general sequencing tests. It covers: immediate exact
replay after successful persistent-gap recovery when retained fact history is
empty; oversized initial and atomic replacement snapshots with no sequence
assignment or partial commit; persistent-gap precedence over invalid and future
cursors; one-reader bound/bound-plus-one contention; global fact/snapshot
queued-cleanup pinning during the active reader; an incumbent pre-capture
in-flight cleanup turn continuing/finalizing while later cleanup returns
`.alreadyCleaning`; reader-completion cleanup wake;
invalidated diagnostics reporting non-current; and near-maximum
sequence/gap/lease authority without wrap, alias, lost custody, or an older
acknowledgement clearing newer debt. Each case asserts public offer/replay/
diagnostic results and history/currentness invariants against an independent
oracle, and each must fail against the rejected S1 implementation for the named
reason before the corrected implementation passes.

The shared protected-state proof is independently mutation-sensitive. It
discovers every Admission raw-lock closure and token-bearing reachable helper,
rejects raw state without the protected token, and rejects retained-history or
declared-key fleet traversal/materialization independent of collection/member
spelling. Production parity fails for a helper rename, unresolved protected
call, raw lock/state escape, or alias passed to an unclassified helper. It does
not trust production-maintained visit counters as its sole oracle. Preserved RED
receipts insert uncounted journal-history traversal, non-hash gather slot scan,
latest retention-order scan, helper rename, and aliased/pass-through scans and
prove that the independent structural rule fails before restored source passes.

Deterministic destructor barriers separately prove that queued cleanup becomes
in-flight without releasing physical capacity, diagnostics during destruction
still report the custody, concurrent offer/cleanup/rebind/invalidation cannot
alias or over-admit, and finalization releases at most the declared quantum.
Latest proof uses a cleanup-free full `D` lease, `D` refilled keys, `D` accepted
replacements, the next mutation-free component-bound rejection,
acknowledgement preserving the auxiliary sum, and a residual-cleanup case that
proves delivery reservation without overclaiming replacement headroom. It also
covers cleanup finalization during an incumbent lease, positive and zero-size
pre-presentation eligibility, lifecycle cleanup of the final batch returning a
wake for its newly created lease, and latest retry both with and without a newer
same-key pending value. The unsuperseded retry history includes residual cleanup
and a later same-key replacement of the returned pending value. A saturated-
cleanup producer-refill race proves cleanup
finalization pre-presents a lease before refill can steal the released reserve.
Wrapper proof separately shows that lossy presentation makes no currentness
claim and that source advance or rejection between recovery comparison and
clear preserves the newer authoritative-resample dirty revision until the
atomic `dirtyRevision == transferredRevision == currentSourceRevision`
predicate succeeds. Zero-byte/max-size snapshot
replacement and recovery-only gather invalidation prove entry and byte bounds
independently.
Gather runtime proof observes payload-bearing physical release through the
weak/deinit payload oracle and proves recovery-only metadata admission through
bounded turns, counters, age, and quiescence. A preserved payload-bearing
fleet-root or strong-tail mutation must fail the weak/deinit payload oracle.
Private recovery-only metadata lifetime is instead proved by the structural
weak-edge and no-extra-strong-alias mutations above. Restored-source runtime
proof covers recovery-only and mixed fleets at 1/100/10,000 slots; structural
proof establishes that terminal root/cursor destruction cannot retain
unaccounted metadata outside the shared cleanup quantum.

## Threat Model

Assets:

- interaction latency and MainActor availability;
- repository/worktree topology and user-owned metadata;
- terminal/session lifetime, pane attribution, and user intent;
- terminal content, clipboard/secure-input state, filesystem paths, and secrets;
- trustworthy local performance evidence.

Entry points and adversaries:

- local processes producing adversarial FSEvent and `.git` churn;
- unreadable, replaced, symlinked, non-local, or malicious directory trees;
- PTY processes emitting arbitrary output, OSC, titles, URLs, notifications,
  action traffic, and misleading agent reports;
- stale callbacks, registrations, sessions, and queued generations;
- instrumentation overload that hides the measured incident.

Privileged effects include topology removal, watcher registration, pane-location
projection invalidation, filesystem/Forge scope, clipboard/secure-input changes, screen reads,
notifications, open-URL requests, and workspace commands. Untrusted input may
request or inform these effects only through the typed owner and authorization
contract named by its child spec.

## Non-Goals

- No implementation sequence, worker allocation, or exact command list.
- No actor-per-pane mandate.
- No claim that static code shape establishes the runtime-dominant hotspot.
- No host-owned VT parser, renderer, or frame loop.
- No claim that layer publication is physical display scanout.
- No legacy JSON compatibility path. Forward SQLite migrations may remove
  topology-derived pane facets and repository-coupled residency encodings.
- No default-on screen capture or agent authority inferred from terminal data.
- No permanent old/new compatibility pipelines.

## Bridge Scope Decision And Adjacent Spec Boundary

This pair includes filesystem-triggered Bridge containment and currentness:

- the global fact consumer offers one generation-bearing invalidation and
  returns without awaiting refresh, package, WebKit, or React work;
- a per-pane/repository running-plus-dirty owner has bounded pending state and
  one dirty follow-up;
- previous content becomes explicitly non-current before repair acknowledgement;
- `BridgeFilesystemRefreshRequest` contains only pane/repository/worktree
  generation, source/package revision, bounded changed IDs or a coarse rebuild
  reason, and an off-main source-provider handle; it never contains or causes a
  MainActor package-sized copy;
- `BridgeRefreshInputProvider` owns repository/source reads and immutable
  package input off-main; package/delta and final JSON-envelope construction for
  this refresh path run off-main;
- MainActor performs only calibrated bounded request-state capture and the
  current-generation WebKit call;
- `BridgeCurrentnessPresentationState` owns a native, nonambiguous
  `refreshing`/`retrying`/`failed-last-known` overlay above the web content. The
  current-generation overlay apply is required before the refresh owner may
  acknowledge that stale content is no longer presented as current; JavaScript
  apply and React render completion are not source-repair acknowledgements;
- stage evidence distinguishes invalidation admission, package build, envelope
  build, WebKit delivery, JavaScript apply, and React commit where available.

This scope may claim critical-lane containment, Bridge currentness correctness,
and terminal interaction fairness with Bridge visible/background. It may not
claim Bridge rendering is fast, browser paint latency, large-list scalability,
or selected-content scalability.

Deep Bridge push/render redesign remains a separate maintained spec. It owns
the all-source changed-ID/mutation journal, normalized incremental React state,
memoization, list/content virtualization, and a Bridge-specific interaction
SLO. That adjacent spec becomes mandatory when a required Bridge-visible or
background cell fails the terminal/MainActor SLO after containment, when a
Bridge-owned MainActor span exceeds the compact-apply budget, or when a Bridge-
specific product claim is requested. Planning may not silently expand or claim
that work from the older audit's ranking alone.

## Planning Gate

The parent/child contract and focused latest-overload `D/R/C`, cleanup-
finalization delivery, latest-retry, and lossy-or-resample wrapper amendment are
accepted. Focused S1 planning may map these contracts to files and symbols,
sequence slices, and operationalize proof gates. Implementation remains frozen
until that translation and its focused plan review are ready. Planning may not
choose different actors, mailboxes, indexes, transports, state owners, failure
semantics, action Boolean semantics, source repair, MainActor ownership, signal
planes, security authority, Bridge scope, or evidence validity.

Final capacities, measurement perturbation allowance, and latency ceilings may
be calibrated by the measured plan where their owner is already named. A final
performance-done claim still requires explicit ceilings approved from baseline
distributions. Spec acceptance is not runtime root-cause proof or implementation
proof.
