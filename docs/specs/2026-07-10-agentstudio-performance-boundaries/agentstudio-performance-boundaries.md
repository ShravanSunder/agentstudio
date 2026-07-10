# AgentStudio Performance Boundaries

Date: 2026-07-10
Status: accepted technical contract after adversarial review
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
untrusted/high-rate source
  -> bounded source-owned admission
  -> contraction plus exact recovery obligation
  -> off-main scheduling / scan / join / projection / serialization
  -> semantic fact or typed mutation
  -> small synchronous MainActor application
  -> local observable state and presentation

interactive input
  -> AppKit MainActor handler
  -> direct synchronous libghostty call
  -> Ghostty-owned PTY / VT / renderer work
  -> measured response / frame-layer-publication seam + native visible proof
```

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
| latest-value mailbox | one bounded slot per declared key plus at most one pending drain; replacement is the contract and is counted | scrollbar/search/cursor/viewport/current presentation samples |
| coalescing batcher | bounded keys/items/bytes with debounce and maximum latency; values merge by a typed accumulator; overflow creates explicit repair/invalidation rather than silent loss | filesystem paths, Bridge dirty IDs, source invalidations |
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

```swift
struct PressureStreamID: Hashable, Sendable {
    let rawValue: String
}

struct AdmissionGeneration: Hashable, Sendable {
    let owner: PressureStreamID
    let value: UInt64
}

enum AdmissionReceipt: Sendable, Equatable {
    case admitted
    case replacedPrevious
    case merged
    case staleGeneration
    case undeclaredKey
    case closed
}

enum CoalescingOfferReceipt<Repair: Sendable>: Sendable {
    case admission(AdmissionReceipt)
    case repairRequired(Repair)
}

enum AdmissionWakeDirective: Sendable, Equatable {
    case none
    case scheduleDrain
}

struct AdmissionDrainToken: Hashable, Sendable {
    let generation: AdmissionGeneration
    private let mailboxIdentity: UInt64
    private let leaseSequence: UInt64
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

struct AdmissionDiagnostics: Sendable, Equatable {
    let offered: UInt64
    let admitted: UInt64
    let contracted: UInt64
    let rejectedStale: UInt64
    let rejectedUndeclared: UInt64
    let repairEscalations: UInt64
    let pendingKeyCount: Int
    let pendingKeyHighWater: Int
    let oldestPendingAge: Duration?
}

struct CoalescingAdmissionDiagnostics: Sendable, Equatable {
    let admission: AdmissionDiagnostics
    let pendingItemCount: Int
    let pendingByteCount: Int
    let pendingItemHighWater: Int
    let pendingByteHighWater: Int
    let repairSlotCount: Int
    let repairSlotHighWater: Int
    let oldestRepairAge: Duration?
    let outstandingDrainCount: Int
}
```

`PressureStreamID` values are bounded, content-free domain constants. User
input, paths, pane/surface/root identifiers, terminal content, and payload
values cannot construct telemetry-facing stream dimensions.

`LatestValueMailbox<Key, Value>` has one bounded current-generation slot per
declared key, a synchronous nonblocking `offer` that returns its receipt and
wake directive, at most one pending consumer wake, generation-consistent
`takeDrain`, acknowledgement, `seal`, `invalidate`, and diagnostics. Replacement
is its declared semantics and is counted. An undeclared key is rejected; a
dynamic callback race cannot become a precondition failure.

`CoalescingMailbox<Key, Accumulator, Repair>` has a domain-owned associative
merge algebra, bounded key/item/byte limits, one pending consumer wake, and a
separate exact typed repair slot per declared key. Ordinary overflow clears or
reduces replaceable hints for the affected key and atomically joins every
cleared hint's domain-supplied fallback into that repair slot; it cannot replace
or weaken repair debt. `CoalescingOfferReceipt<Repair>` keeps this payload typed
without importing a filesystem, terminal, or other domain repair type into the
shared module. Declared-key cardinality bounds exact repair-slot cardinality.

`takeDrain` creates one generation-bearing lease over the captured hint and
repair revisions; it does not destructively remove exact repair state. The
acknowledgement disposition is `transferred` or `retry`. `transferred` means the
domain owner synchronously accepted the captured repair obligation into its
authoritative state, not that domain recovery completed. It clears only the
exact captured revisions; a newer merge/escalation survives and produces the
single follow-up wake. `retry`, cancellation without acknowledgement, and a
stale/double/foreign token cannot clear repair. Acknowledgement atomically
returns the follow-up `AdmissionWakeDirective`. The domain gate—not the generic
mailbox—owns scan/rebuild completion and participant acknowledgement.

The wake/lease state machine is normative:

| State | Operation | Next state and result |
| --- | --- | --- |
| `idle` | first accepted offer | `wakePending`; exactly one `scheduleDrain` |
| `wakePending` | additional offer | remains `wakePending`; `.none` |
| `wakePending` | `takeDrain` | `draining(token)`; pending wake is consumed |
| `draining(token)` | additional offer | `drainingAndDirty(token)`; `.none` |
| `draining*` | matching `acknowledge(transferred/retry)` | atomically commit/requeue; if retained work remains, `wakePending` plus exactly one `scheduleDrain`, otherwise `idle`/drained-sealed plus `.none` |
| any | stale, duplicate, or foreign acknowledgement | no mutation; typed rejection |
| open state | `seal` | reject new offers; retain and drain accepted work |
| any non-invalidated state | `invalidate` | discard generic state, revoke token, terminally reject; domain transfer precondition applies |

`AdmissionDiagnostics` reports current pending-key depth as well as high-water;
coalescing diagnostics additionally report current and high-water item/byte
pressure, current/high-water repair-slot count, oldest repair age, and whether a
drain transfer remains outstanding. A stream is not quiescent while a repair
slot or drain lease remains. Diagnostic snapshots never contain keys or
payloads.

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

The journal exposes distinct typed offer/replay results. An admitted offer
returns its sequence and wake directive; an overflow offer returns
`gapCommitted(FactGap, wake:)`, never ordinary admission. A replay result is one
of exact retained facts, current-snapshot resynchronization, persistent product
gap, query-local replay-history gap, invalid cursor, stale generation, or
invalidated. Persistent product currentness has precedence over cursor history:

| Journal state | Replay request | Result |
| --- | --- | --- |
| current; cursor retained | any supported recovery mode | exact facts |
| current; acknowledged cursor evicted; covering current snapshot requested | state resynchronization | snapshot plus following retained facts |
| current; acknowledged cursor evicted; exact occurrence requested or no covering snapshot | any | `ReplayHistoryGap` |
| persistent `FactGap` | any cursor or recovery mode | persistent `FactGap`; optional snapshot may be offered only as a recovery candidate |
| persistent `FactGap` plus later offer | offer | widen range/token synchronously; return `gapCommitted` |
| persistent `FactGap` plus stale token/range recovery | resynchronize | typed stale/mismatch; gap unchanged |
| persistent `FactGap` plus matching latest token, generation, upper sequence, and authoritative bounded snapshot/rebuild | resynchronize | current at the supplied sequence; later sequence allocation continues monotonically |

The journal retains pending/leased facts until one required product drain owner
acknowledges transfer into the downstream fact owner. Multiple subscriber
acknowledgements are downstream transport policy and do not enlarge the generic
journal. A journal drain acknowledgement is therefore mechanical transfer, not
proof that every eventual subscriber consumed the fact.

All three families:

- bind each mailbox/journal instance to one `AdmissionGeneration`; generation N
  cannot merge into N+1, and rotation creates a fresh instance;
- expose `offer`, `takeDrain`, drain acknowledgement, `seal`, `invalidate`, and
  `diagnostics` with the semantics above;
- return at most one `scheduleDrain` directive before a take; offers during a
  drain produce at most one follow-up directive after acknowledgement, and the
  primitive never creates a task or invokes domain code while holding state;
- define `seal` as graceful terminal admission closure that drains accepted
  work, and `invalidate` as immediate terminal revocation that discards pending
  work and makes outstanding tokens stale;
- require a domain wrapper to transfer any authoritative repair/fact-gap debt
  before invalidation; generic invalidation cannot be the last owner of
  correctness debt;
- keep diagnostic-record loss separate from product repair/fact gaps;
- have domain-specific wrappers that fix key, merge, repair, and callback-return
  policy at compile time.

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

### Atoms And Observables

Atoms and observables are canonical state sinks and UI read surfaces. They do
not subscribe to the global bus, own high-rate queues, perform filesystem/Git/
serialization work, or derive and repost product facts. Coordinators/projectors
compute elsewhere and apply typed mutations.

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
| FSEvent loss and topology repair | watched-folder child | deterministic loss/repair plus independent final oracle |
| topology/MainActor/persistence fairness | watched-folder child | work-item spans, responsiveness probe, scaling workload |
| semantic topic transport | parent + watched-folder child | structural policy, queue admission, lag/recovery proof |
| Ghostty tick/action admission | terminal child | state/origin tables, races, sustained producer pressure |
| terminal sample contraction/activity parity | terminal child | sequence oracle, bounded flood, semantic parity |
| secure input/screen boundary | terminal child | owner-state races, denied capture, export canaries |
| combined typing/cursor symptom | shared harness | correlated watched-pressure, input-to-frame-layer-publication tails, and native visible outcomes |

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

Privileged effects include topology removal, watcher registration, pane
orphaning, filesystem/Forge scope, clipboard/secure-input changes, screen reads,
notifications, open-URL requests, and workspace commands. Untrusted input may
request or inform these effects only through the typed owner and authorization
contract named by its child spec.

## Non-Goals

- No implementation sequence, worker allocation, or exact command list.
- No actor-per-pane mandate.
- No claim that static code shape establishes the runtime-dominant hotspot.
- No host-owned VT parser, renderer, or frame loop.
- No claim that layer publication is physical display scanout.
- No new persistence schema requirement; snapshot preparation remains in scope.
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

The revised parent, child specs, and exhaustive action manifest passed fresh
`spec-review-swarm` after accepted findings were incorporated. Planning may now
map contracts to files and symbols, sequence slices, and
operationalize proof gates. It may not choose different actors, mailboxes,
indexes, transports, state owners, failure semantics, action Boolean semantics,
source repair, MainActor ownership, signal planes, security authority, Bridge
scope, or evidence validity.

Final capacities, measurement perturbation allowance, and latency ceilings may
be calibrated by the measured plan where their owner is already named. A final
performance-done claim still requires explicit ceilings approved from baseline
distributions. Spec acceptance is not runtime root-cause proof or implementation
proof.
