# Bridge Comm-Worker Admission And Backpressure — Program Design

Date: 2026-08-23

Requirements:
[2026-08-23-requirements.md](./2026-08-23-requirements.md).

Specification:
[2026-08-23-specification.md](./2026-08-23-specification.md).

Current foundations:

- [Demand-Driven Derived-State Refresh](../../../architecture/state/demand_driven_derived_state_refresh.md)
- [Local-First Comm Worker Architecture](../../bridge-viewer-transport/local-first-comm-worker-architecture.md)
- [Bridge Review Refresh Classification Program Design](../2026-08-21-bridge-review-refresh-classification/2026-08-21-program-design.md)
- [Observability And Traceability](../../../architecture/observability/observability_and_traceability.md)

## Structural crux

The browser main runtime and comm worker already have the right singular
transport and truth owners. The first correction fixed one direction only:
acknowledgement-paced receipt batches reduced maximum main-to-worker queue wait
from 52,932.7 ms to 2,083.7 ms, with no wait at or above the five-second lease.
The same 1,699-item run then falsified the assumption that this also bounded the
independent worker-to-main FIFO. Worker handling remained cheap at 28.3 ms,
while eight correlated acknowledgements timed out, pending receipts reached
6,144, and three worker replacements repeated the loop.

The cause is upstream of that reverse FIFO. Review currently releases its three
reserved and nine dynamic demand positions as soon as preparation completes
and posts. Those positions can cycle through all 1,699 items while the already
published render jobs, content-ready patches, and correlated outcomes serialize
worker-to-main. File has one current selected operation, but rapid selection can
replace its identity while an older publication remains physically outstanding.

The correction therefore bounds the publication transition, not the port:

```text
existing ranked/current demand and preparation
  -> existing per-surface fulfillment registry acquires publication credit
  -> lease starts; render job then content-ready patch post individually
  -> Main returns ordered disposition batches
  -> exact first queued | terminal rejected | terminal superseded settles credit
     independently from whether current fulfillment accepts the stale meaning
  -> credit becomes release-pending-ACK
  -> correlated ready/degraded ACK posts with the next release generation
  -> all FIFO predecessor releases commit; credit becomes available
  -> existing Review/File reconcile and preparation drain resume
```

The registry is the shallowest owner because it already mints the exact attempt
identity, validates every disposition, and starts the five-second lease. Review
keeps its existing logical positions occupied through this transition; the
registry keeps File's publication tombstone separate from replaceable latest
selection.
There is no second job queue, render batch, generic scheduler, handshake, route,
worker, native call, timer, or new timeout.

## Workload classification

This instance applies the generic demand-refresh selection rule:

```text
urgent annotation/publication action
  class: exact ordered action
  mechanism: direct typed RPC admission and exact terminal outcome

viewport/selection/interest/invalidation input
  class: latest-state or scope-preserving demand
  mechanism: existing producer-owned equality/coalescing/admission

render disposition
  class: ordered fact plus burst of small samples
  mechanism: ordered delivery, bounded batch aggregation, acknowledgement
             backpressure, and stale identity validation
```

Batching retains every admitted receipt. Demand contraction may remove an
obsolete unsent value only through its separate owner and proof. These
mechanisms are not interchangeable.

## Components and ownership

```text
BridgeMainRenderFulfillmentCoordinator                 existing
  owns: observation of queued/applied/painted/rejected/superseded
  emits: one strict receipt transition with complete attempt identity
  does not own: transport admission, retry, worker state

BridgeMainRenderDispositionAdmission                   existing first-correction owner
  scope: one instance per Review or File surface client
  owns: ordered pending receipts, one in-flight batch identity,
        batch release from RPC lifecycle, bounded admission telemetry
  does not own: render fulfillment, demand, user-action priority queue,
                worker replacement, product calls

BridgeWorkerRpcClient + BridgeWorkerRpcLifecycleStore  existing
  owns: request identity, post, timeout, typed terminal lifecycle
  supplies: request id for one dispatched batch and its terminal state

BridgePaneCommWorkerSession                            existing
  owns: one product MessageChannel, issued timestamp, bootstrap,
        replacement, disposal, and Main-side receive-order observation
  rule: urgent actions continue posting directly; it does not become a
        generalized semantic scheduler; the first replacement-required signal
        uses its existing worker-failure ingress and idempotent replacement latch

comm-worker renderDisposition handler                  changed batch consumer
  owns: strict batch validation, in-array application order, one immediate
        ready/degraded response, and one ephemeral application result containing
        immediate messages plus exact release candidates
  delegates: every receipt to the surface fulfillment registry

BridgeWorkerRenderFulfillmentRegistry                  changed existing owner
  owns: accepted/duplicate/rejected receipt semantics, lease expiry,
        retry readiness, per-item fulfillment state, per-surface publication
        credit identities, ordered release-pending predecessors,
        replacement-required state, and publication-release generation
  contract: `beginPublication` consumes credit before starting the lease;
            an exact first queued or terminal rejected/superseded receipt may
            settle its physical tombstone without making stale fulfillment
            current; only the runtime's explicit post-ACK commit makes credit
            available

BridgeCommWorkerReviewDemandLedger                     changed existing owner
  owns: reserved/dynamic ranked positions, latest membership, and the lifecycle
        of unposted, attached-posted, and detached-posted Review records
  change: a position that has published remains held until its exact registry
          credit commits after ACK; invalidation removes obsolete intent but
          cannot erase its detached posted record or free its position

BridgeCommWorkerSelectedFileContentOperationController changed existing owner
  owns: only the latest selected intent/request and its unposted preparation
  change: rapid selection replaces only unposted latest intent; an older posted
          attempt is represented only by the registry's physical tombstone

Bridge comm-worker preparation pump                    existing
  owns: ranked, currentness-aware preparation slices
  rule: it stores no publication-window queue and is resumed only after the
        runtime commits ACK-gated credit release

Bridge telemetry producer/worker                       existing
  owns: compact source-scrubbed samples and export
  rule: product admission never awaits telemetry

bridgeRenderDispositionAdmissionPolicy                 existing main-side policy
  owns: batch maximum 64, pending maximum 6,144, one recovery probe
  derivation: 2,048 retained Review content entries * three required
              queued/applied/painted transitions

bridgeContentDemandExecutionPolicy                     changed existing policy owner
  owns: Review reserved-position count and dynamic-position count used by both
        the Review ledger and the registry publication-capacity derivation
```

Publication capacity is not added to that main-side receipt policy. It is
derived from existing worker admission owners:

| Surface | Existing source limit | Publication capacity | Why this is not arbitrary |
| --- | --- | --- | --- |
| Review | the shared demand policy's three reserved plus nine dynamic active positions | derived 12 | The ledger and registry consume the same policy values; no independent numeric 12 may drift from the logical position count. |
| File | one selected-content operation at a time | 1 | The registry tombstone prevents rapid selection from replacing the identity that still occupies the physical FIFO; newest selection remains in the File owner upstream. |

During a Review/File mode transition, already-posted work from the retiring
surface may coexist with current work, so the worker-wide physical bound is at
most 13 publication attempts. Review suspension starts no new Review work.
Source render budgets remain authoritative: Review publications retain the
existing 512 KiB/400-line interactive envelope and File retains its existing
2 MiB/10,000-line selected envelope. Runtime evidence, not a larger invented
credit count, decides whether these existing budgets satisfy the five-second
outcome and lease obligations.

### Behavioral interfaces

`BridgeWorkerRenderFulfillmentRegistry.beginPublication` remains the only
publication-attempt entry. For a current job it returns the existing
published/duplicate/retry-wait meanings plus a bounded-window-unavailable
result. Window unavailable performs no fulfillment transition, mints no
attempt, and starts no lease. Callers retain work in Review's active position
or File's latest selected request; the registry never accepts a job payload.

Receipt application continues to return one fulfillment result per input in
array order and separately tests the exact physical credit tombstone. The first
exact `queued`, `rejected`, or `superseded` receipt for an occupied tombstone
adds that surface/item/attempt identity to the ordered release candidates even
when source churn, reset, or invalidation makes the fulfillment result stale or
degraded. This physical match does not mutate current fulfillment into an
accepted state. A foreign or mismatched identity can do neither.

The `renderDisposition` branch of the existing command-handler result becomes
one discriminated ephemeral `BridgeWorkerRenderDispositionApplicationResult`:

```text
immediateMessages    existing correlated ready/degraded messages
releaseCandidates    exact internal surface/item/attempt identities, in FIFO order
```

It is a return value carried through the existing handler/runtime interface, not
a component, scheduler, queue, or durable owner. Other command results keep
their existing message-only meaning. The handler never commits candidates and
release identities never enter telemetry.

The runtime passes `immediateMessages` through
`dispatchBridgeCommWorkerRuntimeProductControl`. After that existing function
synchronously posts the correlated ACK and returns, the runtime passes the
current candidates to the registry's commit operation and obtains committed
releases. A successful post commits every
exact FIFO predecessor still release-pending from an earlier failed ACK plus
the current candidates, advances the publication-release generation once, and
returns the committed releases. Commit is idempotent and ignores stale,
foreign, or already-cleared identities. The runtime applies those releases to
Review/File owners and then requests the existing preparation drain. No
promise, task, microtask, or second waiting queue is the ordering contract;
direct call order is.

For Review, posting binds the active record to the exact render attempt and
preparation completion no longer releases its logical position. Unposted
preparation may cancel and free its position. Invalidation after post removes
the obsolete intent but retains a detached posted record in the same position;
only its matching committed release deletes that record. Stale/foreign commits
are ignored, and a valid deletion invokes the existing ranked reconcile.

For File, the controller and `latestSelectedFilePreparationRequest` remain the
singular owner of newest selection intent. Capacity-unavailable work stays in
that existing latest request, mints no attempt, starts no lease, and resumes
only from the one committed-release wake. The registry alone retains any older
posted physical tombstone. There is no polling, task loop, or waiting-job queue.

### Review and File handoff lifecycles

| Existing owner | State and transition | Guard and effect |
| --- | --- | --- |
| Review ledger/ticket | active-unposted -> cancelled/cleared | Invalidation, teardown, or stale preparation may cancel before any post and then run ranked reconcile. |
| Review ledger/ticket | active-unposted -> attached-posted | Both ordered job/patch posts succeed; bind the record and its logical position to the exact render attempt. Preparation completion alone does not clear it. |
| Review ledger/ticket | attached-posted -> detached-posted | Invalidation/source churn removes obsolete membership intent and aborts remaining upstream work, but retains the posted record and position. |
| Review ledger/ticket | attached-posted or detached-posted -> cleared | Only a matching committed release clears the record; stale/foreign commit is ignored; clearing invokes existing ranked reconcile and one drain request. |
| File latest request | latest-unposted -> latest-unposted | Capacity unavailable changes nothing; a newer selection replaces this unposted intent under existing currentness checks. |
| File latest request + registry | latest-unposted -> no submitted latest request + occupied tombstone | Successful ordered job/patch publication consumes the submitted intent; the registry alone retains its physical identity. A later selection creates a new latest-unposted intent. |
| File latest request | committed release wake | The runtime wakes the existing latest request once; it rechecks currentness and capacity before publication. It never receives or owns the old tombstone. |
| Both owners | replacement/disposal -> cleared | Clear all old-lifetime held records/requests before new demand/bootstrap re-derives current intent. |

Forbidden edges:

- the receipt admission owner does not classify or queue annotation actions;
- the session does not inspect comment bodies or annotation operation payloads;
- the comm worker does not infer priority from React component provenance;
- publication credit does not own jobs, demand rank, fetch, preparation, or
  currentness; those remain with Review demand scheduling and File selection;
- invalidation, selection change, source replacement, or preparation completion
  cannot free credit for an attempt already posted to Main;
- receipt batching does not alter the product-control mux or SQLite ordering;
- telemetry does not release a batch or determine product success;
- demand and receipts do not gain physical ports;
- visual animation frames do not schedule protocol delivery.

## Current and proposed call-path delta

```text
Legend: [=] unchanged  [~] changed  [+] added
Actors: D=Review/File demand owner, F=fulfillment registry/window,
        W2M=worker-to-main FIFO, M=Main render owner,
        M2W=main-to-worker FIFO, H=worker message handler

CURRENT CORRECTED-RUN FAILURE

 D        F             W2M                 M             M2W          H
 |        |              |                  |              |           |
 |-[=] prepare job------>|                  |              |           |
 |        |-[=] beginPublication + 5s lease |              |           |
 |        |-[=] render job----------------->|------------->|           |
 |        |-[=] content-ready patch-------->|------------->|           |
 |-[~] release position immediately         |              |           |
 |-[~] repeat through 1,699 items---------->| backlog      |           |
 |        |              |---- job/patch -->|              |           |
 |        |              |                  |-[=] receipts>|---------->|
 |        |              |                  |              | [=] apply in order
 |        |              |<----------------- correlated ready/degraded-|
 |        |              | ACK waits behind older jobs/patches         |
 |        |              | (8 timeouts; pending 6,144; 3 replacements) |

PROPOSED DUPLEX-BOUNDED FLOW

 D        F             W2M                 M             M2W          H
 |        |              |                  |              |           |
 |-[=] prepare job------>|                  |              |           |
 |        |-[+] acquire exact surface credit               |           |
 |        |-[~] begin attempt + lease only after credit     |           |
 |        |-[~] post render job, then content-ready patch-->|           |
 |-[+] hold Review posted record; File keeps latest intent |           |
 |        |     registry alone holds physical tombstone     |           |
 |        |              |---- job/patch -->|              |           |
 |        |              |                  |-[=] ordered receipt batch>|
 |        |              |                  |              |-[=] apply each
 |        |              |                  |              |-[+] exact first queued
 |        |              |                  |              |    or terminal matches
 |        |<-[+] mark exact attempt release-pending-ACK ---|           |
 |        |              |<-[~] post ACK(next release generation) ------|
 |        |<-[+] commit FIFO predecessors + current candidates --------|
 |<-[+] resume existing ledger/File latest-request owner   |           |
 |-[+] released job+patch carry committed generation------>|           |
 |        |              | Main observes ACK generation first          |

RESULT / ERROR EDGES

 [=] any rejected receipt makes the batch response typed degraded; valid
     receipts in the same batch still apply in array order.
 [+] exact tombstone matching is separate from fulfillment disposition. A first
     queued | rejected | superseded receipt may settle physical credit while
     current fulfillment remains stale/degraded; stale work never becomes current.
 [+] foreign/mismatched identity, applied, or painted cannot release credit.
 [+] a job/patch post throw, occupied-credit lease expiry, or second/probe ACK
     timeout enters replacement-required and requests replacement exactly once.
 [+] an ACK post throw retains every pending release. The next successful
     receipt/probe ACK commits all exact FIFO predecessors and current releases.
```

The current path is anchored by `createBridgeCommWorkerReviewDemandLedger`
releasing from preparation completion,
`BridgeWorkerRenderFulfillmentRegistry.beginPublication`, Review/File runtime
posting a render job followed by a content-ready patch through two fallible
ordered calls,
`applyBridgeWorkerRenderDispositionCommand`, and
`dispatchBridgeCommWorkerRuntimeProductControl` synchronously posting immediate
messages before the final preparation-drain request. The proposed delta changes
their result edges: disposition application returns release candidates; after
runtime dispatch posts the ACK, the runtime commits candidates and obtains
committed releases; existing Review/File owners consume the wake. A bounded publication-release generation on the ACK
and released job/patch messages lets Main ingress observe this order. Annotation,
product-control, Swift, SQLite, Review presentation, Pierre observation, the
one product port, and main-to-worker receipt batching remain unchanged.

## Worker publication-credit state machine

The registry owns this non-persisted state for each surface and worker
lifetime. `occupied` begins only at the publication transition, after all fetch
and job preparation. Review logical positions and File latest intent wait on
its availability but do not own or mirror the physical tombstone.

```text
                         beginPublication(exact attempt)
  ┌───────────┐  capacity available + current source/identity  ┌──────────┐
  │ available │ ──────────────────────────────────────────────► │ occupied │
  └───────────┘                                                 └────┬─────┘
       ▲                                                               │
       │ commit FIFO predecessors after successful ACK post            │
       │                                                               │ exact first queued
       │                                                               │ or terminal match
       │                  ┌─────────────────────┐                       │
       └──────────────────│ release-pending-ACK │◄──────────────────────┘
                          └──────────┬──────────┘
                                     │ lease expiry, ordered post failure,
                                     │ second/probe ACK timeout, or overload
                                     ▼
                          ┌──────────────────────┐
                          │ replacement-required │
                          └──────────┬───────────┘

  any state ── existing worker replacement / disposal / teardown ──> cleared
```

| Current state | Input and guard | Next state | Side effect |
| --- | --- | --- | --- |
| available | current publication passes existing registry/currentness checks and capacity remains | occupied | Mint attempt identity, start lease, then post job and patch as two ordered fallible calls. |
| available | capacity unavailable | available | Do not mint an attempt or start a lease; keep Review/File work with its existing upstream owner. |
| occupied | exact first `queued`, terminal `rejected`, or terminal `superseded` matches tombstone | release-pending-ACK | Add exact identity to ordered pending releases, independently from accepted/stale/degraded fulfillment semantics. |
| occupied | stale/duplicate fulfillment result but exact first queued/rejected/superseded matches tombstone | release-pending-ACK | Settle physical credit only; never make obsolete fulfillment current. |
| occupied | foreign/mismatched identity, `applied`, or `painted` | occupied | Apply or reject under existing fulfillment semantics; never release credit. |
| occupied | receipt lease expires, or any synchronous failure occurs after acquisition and before both ordered posts complete | replacement-required | Close old-lifetime admission, block retry publication, retain tombstone, and signal the session's existing worker-failure/replacement ingress exactly once. No rollback is assumed. |
| release-pending-ACK | correlated ready/degraded message posts successfully | available | Commit all exact FIFO predecessors plus current candidates, advance release generation, return committed releases, reconcile Review/File, then request existing drain. |
| release-pending-ACK | ACK post throws or port closes | release-pending-ACK | Retain every exact pending release; a later receipt/probe ACK may commit the whole prefix. |
| release-pending-ACK | second/probe outcome times out | replacement-required | Main closes receipt admission and requests existing replacement exactly once. |
| replacement-required | old callback, retry wake, reconcile, or publication request | replacement-required | Ignore it; old-lifetime work cannot mint or post. |
| any old-lifetime state | replacement/disposal/teardown | cleared | Abort upstream work, clear exact attempt identities and pending releases, and prevent old callbacks from publishing. |

An exact first `queued` matching the tombstone is the earliest proof that Main admitted the publication
from the worker-to-main FIFO. `applied` and `painted` occur later and therefore
cannot be necessary to release this transport credit. A terminal rejection or
supersession proves that Main consumed the attempt without queueing it. Exact
duplicates are idempotent fulfillment facts, not extra credits.

The physical tombstone outlives source churn, source reset, selection change,
and Review invalidation. Those events may supersede current fulfillment intent
but cannot erase already-posted port debt. Replacement is the only lifecycle
operation that clears the whole worker lifetime. A late exact receipt can
therefore settle physical debt without reviving obsolete content.

## Main-to-worker receipt admission remains authoritative

```text
idle
  receipt arrives -------------------------------> pending

pending
  no in-flight batch -> take ordered <=64 ------> inFlight(request, batch)
  more receipts ---------------------------------> pending + inFlight

inFlight
  acked -----------------------------------------> idle | next inFlight
  typed degraded/failed -------------------------> idle | next inFlight
  timed out -------------------------------------> unknownDebt(probeAvailable)
  worker replacement/dispose --------------------> cleared

unknownDebt(probeAvailable)
  do not replay the mixed batch blindly
  dispatch at most one later receipt batch as a FIFO recovery probe
  keep urgent actions direct

unknownDebt(probeInFlight)
  probe ready/degraded --------------------------> debt cleared | next inFlight
  probe timeout ---------------------------------> replacementRequired
  worker replacement/dispose --------------------> cleared

replacementRequired
  dispatch no receipt batch
  request existing worker replacement exactly once
  worker replacement/dispose --------------------> cleared

pending capacity reached
  mark admission closing
  request existing worker replacement once ------> cleared
```

`acked` means the worker handled the complete command. `degraded` means the
worker handled the command but at least one receipt was stale or invalid; valid
receipts in the same batch may already have applied. Both settle transport
admission, while the fulfillment registry remains authoritative per receipt.

A timeout cannot establish whether the worker applied none, some, or all of a
mixed batch. Blind replay is therefore unnecessary and may create conflicting
transitions. The one recovery probe is posted after the timed-out message on
the same worker port; its correlated ready or degraded response proves FIFO
progress beyond both messages and clears the unknown debt. A second timeout
closes old-lifetime receipt admission and requests the existing replacement
lifecycle exactly once. A successful ordinary or probe ACK commits all exact
release-pending predecessors plus current releases before new publication;
worker replacement clears the latch when no ACK succeeds. Repeated timeouts
fail the workload gate rather than widening physical debt.

## Ordering and identity

- One admission owner serves one surface RPC client, so a batch never mixes
  Review and File receipts.
- Worker replacement resets pending and in-flight admission before a new
  worker instance can emit jobs. Old receipts cannot enter the new instance.
- Each receipt retains pane session, worker instance, surface, item,
  submission, publication, attempt, derivation epoch, window, and operation
  correlation identity.
- A batch may contain different derivation epochs from the same current worker
  because each receipt is validated independently and render dispositions are
  not intent-epoch admitted. Batch envelope epoch is not receipt authority.
- Positive transitions retain queued -> applied -> painted order for each
  attempt. Exact duplicates remain idempotent. Rejected and superseded remain
  terminal attempt facts.
- Main-to-worker FIFO remains the final cross-class order. Nothing already
  posted is overtaken.
- Worker-to-main FIFO remains the final order for jobs, patches, and correlated
  outcomes. Already-published work may precede an ACK; explicit release after
  the ACK post ensures newly eligible work cannot. The correlated
  `renderDisposition` ACK carries the publication-release generation that
  becomes active after its successful post. Each job and content-ready patch
  admitted by that commit carries the same generation; initial bootstrap work
  carries generation zero.
- `BridgePaneCommWorkerSession` starts with highest observed ACK generation zero
  for each worker lifetime. Before routing a health ACK or render job/patch to
  clients, it advances the observation from a correlated ACK and checks that no
  publication generation exceeds the highest observed value. A later generation
  arriving first records one bounded invariant violation and still follows the
  existing validated message route; observation is proof, not correctness.
- `beginPublication` starts the receipt lease only after credit acquisition.
  Fetching, planning, or waiting upstream consumes no lease.
- Review invalidation or role/currentness change may cancel unposted work, but
  a posted attempt becomes a detached record retaining its position until a
  matching committed release. File selection replacement updates only latest
  intent; the registry remains the sole owner of the occupied tombstone.
- Lease expiry for an occupied attempt is a physical-progress failure, not an
  old-lifetime retry opportunity. Fulfillment records the expiry, publication
  enters replacement-required, and retry callbacks remain inert until the new
  worker derives current demand.

## Bounded state in both directions

The admission owner stores only strict receipt DTOs for the current surface and
worker lifetime. Exact duplicate attempt/disposition pairs are suppressed
before pending insertion. One request holds at most 64 receipts and at most one
ordinary request is unacknowledged; the timeout state may retain one unknown
predecessor while its single recovery probe is in-flight.

Pending state is drained by worker outcomes and cleared on worker replacement
or disposal. Its count, oldest age, and high-water mark are mandatory evidence.
The required workload must show a bounded high-water mark that drains to zero
without lease amplification. If it grows monotonically or reaches lease age,
implementation stops for a measured capacity/admission correction; it does not
silently drop ordered facts or increase timeouts.

Initial `bridgeRenderDispositionAdmissionPolicy` caps pending receipts at
6,144 per surface. This is three required positive transitions for every entry
under the existing 2,048-entry Review content-registry ceiling; a terminal
rejection or supersession is an alternative terminal path rather than a fourth
positive transition. The same conservative ceiling serves File View.

Capacity is a health boundary, not a shedding policy. On the first overflow,
the admission owner enters `closing`, refuses further dispatch, records one
bounded overload outcome, and asks `BridgePaneRuntime` to invoke the existing
worker-replacement bootstrap path. Teardown then clears the old worker's
pending receipts. No old receipt is redirected to the new worker. A saturation
test binds this ceiling and recovery edge.

The worker registry additionally reports published-but-unsettled current count,
high-water mark, and oldest age for its current lifetime. `occupied` counts as
published but not settled by Main; `release-pending-ACK` is reported separately
as settled but not yet reusable credit; `replacement-required` closes the
window. Review capacity is derived from the same reserved/dynamic demand-policy
values consumed by its ledger, File capacity is one, and their transition
overlap cannot exceed the derived Review capacity plus one. Credit does not
retain render payloads. Review payload/work remains in its existing attached or
detached posted record, while File retains only latest selected intent upstream.
After demand quiesces, occupied plus release-pending credit and detached Review
records must drain to zero.

## Measurement system

### Existing observations retained

`BridgePaneCommWorkerSession` stamps `issuedAtMilliseconds` immediately before
posting. The comm worker records:

```text
queue wait = handler start - issued timestamp
handler duration = handler end - handler start
```

Those clocks remain the main-to-worker admission observation and are grouped by
closed command and lane vocabularies.

Existing annotation lifecycle and product-control telemetry remains the source
for projection and product-call stages. No duplicate end-to-end stopwatch is
added where existing correlated stages already answer the question.

### Receipt-admission observations added

The admission owner records compact samples at enqueue, dispatch, and terminal
settlement sufficient to derive:

```text
receipt produced count
exact duplicate suppressed count
batch count and receipt count per batch
pending count and high-water mark
oldest pending age at dispatch
one-in-flight invariant violations
batch terminal: acked | degraded | timed_out | cleared
acknowledgement duration
```

The worker records receipt count and accepted/duplicate/rejected counts for one
batch without exporting receipt identities.

The worker fulfillment registry records compact source-scrubbed publication
window samples at credit acquisition, release-pending, ACK-gated commit, and
lifetime clear:

```text
surface publication capacity
published-but-unsettled current count and high-water mark
oldest published-but-unsettled age
release-pending-ACK current count
release cause: queued | rejected | superseded | cleared
correlated ACK posted before committed release count
retained predecessor release count committed by a later ACK
publication post failure stage: job | content_ready_patch
replacement trigger: lease_expired | publication_post_failed |
                     probe_timed_out | receipt_overload
replacement-required transition and exactly-once request count
```

Identity matching remains control-plane state only. Telemetry carries bounded
counts, durations, surface, phase, and result literals; it never exports item,
attempt, publication, worker, pane, path, body, selection, or raw error values.

Main receive observation adds only source-scrubbed numeric counters and closed
phase/result literals:

```text
renderDisposition ACK generation observed count
render job/patch generation observed count by surface and message kind
later-generation-before-ACK invariant violation count
highest observed generation and publication generation as numeric event values,
  never metric labels or correctness keys
worker-lifetime observation reset count
```

The session/router observes these fields after wire-schema validation and before
fan-out to RPC/render consumers. It neither blocks, reorders, accepts, nor
releases product work. A violation records evidence through the existing
asynchronous telemetry producer and preserves the existing route, making this a
bounded proof observer rather than a second correctness owner.

At strict worker-message admission, one exhaustive pure projection assigns a
closed semantic class without inspecting free-form payload content:

```text
urgent_action
  root.create, reply.create, draft.flush, draft edit/save/revert,
  resolution, continuity, and output mutations

demand
  select, viewport, hover, metadata/projection/query/invalidation inputs,
  annotation discover/acquire/release/source refresh and finite reads

settlement
  renderDisposition

lifecycle_control
  publication install/admitted receipt, surface mode, retry/resync controls
```

The projection switches exhaustively over the validated top-level command and,
for `annotationCommand`, its closed operation union. Telemetry exports only the
four class literals. Tests prove representative operations and prohibited body,
path, edit-token, and identity absence.

No product payload is JSON-stringified merely to measure bytes. Arbitrary
message-size accounting on an interactive path is excluded by the existing
paint-path telemetry rule. Contract ceilings and receipt counts provide the
bounded payload evidence for this increment.

### Runtime attribution

```text
main issued -> worker handler start       main-to-worker queue wait
worker handler start -> handler end       worker command work
worker publication post -> first exact matching queued/terminal disposition
                                           published-but-unsettled age
receipt application -> correlated ACK post
                                           duplex outcome ordering
Main ACK observation -> later job/patch    receive-order invariant
worker product dispatch -> result         product-control duration
Swift command start -> SQLite commit      native persistence duration
command outcome -> projection -> paint    reconciliation/presentation duration
```

Telemetry export/ingestion timestamps never replace producer event timestamps.
Victoria queries use a fresh proof marker emitted for the current run, not only
an old timestamp, with bounded service/worktree labels and a marker-scoped Vite
query that joins the receipt, publication-window, receive-order, replacement,
annotation, and product-control observations.

## Baseline and comparative workload

The permanent development-server journey owns one identical workload function
that can run against the baseline and corrected product graph:

```text
seed a disposable real worktree
select the large ci-reliability comparison
wait for exact Review readiness and visible current surface
create one root comment and await exact committed outcome
for reply 1...5:
  author body
  request save
  await exact command outcome
  assert page remains semantically inspectable
reload the complete browser document
wait for exact installed Review and annotation projection
assert root and five exact bodies from SQLite-backed projection
stop demand and wait for receipt pending, occupied credit,
  release-pending credit, and detached Review records to drain to zero
```

All waits bind to protocol/state outcomes with bounded test timeouts. No
wall-clock sleep establishes readiness. The baseline and after run record exact
HEAD/diff identity, comparison identity, item count, worker lifetime, command
counts, both FIFO directions, receipt and publication-window lifecycles,
Main receive-order generations, annotation stages, and durable SQLite/source
evidence. The integration observation crosses the actual pane product
`MessageChannel`; an in-process direct handler call cannot prove FIFO receive
order. The run finishes only after marker-scoped telemetry and product state
both show the quiescent zero drain.

The already-recorded corrected run is an intermediate failure, not the after
result. It proves main-to-worker batching is retained and also fixes the target
for the next comparison:

```text
max main-to-worker receipt queue wait       2,083.7 ms (was 52,932.7 ms)
waits at or above five seconds                     0
max worker handler duration                    28.3 ms
correlated acknowledgement timeouts                 8
pending receipt high-water                       6,144
worker replacements                                   3
oldest pending receipt age                   18,518.4 ms
```

Acceptance additionally requires no acknowledgement or action outcome timeout
behind render predecessors, no admission-caused lease expiry or replacement,
published-but-unsettled counts within the derived bounds, and eventual drain to
zero after demand quiescence. Lower main-to-worker wait alone cannot pass.

## Failure and recovery

```text
LATE ACK OBSERVATION, POST FAILURE, AND REPLACEMENT

Participants:
  MR  Main receipt admission owner
  Q1  main-to-worker FIFO
  WH  worker handler + publication window
  Q2  worker-to-main FIFO
  MS  Main worker-message session/router
  RL  Main RPC lifecycle
  RM  Main render owner
  PR  pane runtime (replacement/bootstrap only)

SUCCESSFUL POST, LATE MAIN OBSERVATION

  MR -> Q1 -> WH : one renderDisposition batch
  WH -> WH       : apply in order; mark exact releases pending ACK
  WH -> Q2       : post ACK carrying next release generation G
  WH -> WH       : commit all pending predecessors + current releases; activate G
  WH -> Q2       : post newly released job/patch carrying G after the ACK
  Q2 -> MS -> RM : deliver older bounded publications ahead of the ACK
  RL -> RL       : existing 5s timer may mark the request timed out first
  RL -> MR       : unknown-delivery debt; at most one existing recovery probe
  Q2 -> MS       : observe ACK G before routing it
  Q2 -> MS -> RL -> MR : deliver late ACK before every G job/patch
  Q2 -> MS -> RM : validate observed G, then route G job/patch in FIFO order

ACK POST FAILURE, THEN SUCCESSFUL PROBE

  WH -> Q2       : ACK post throws or the port is already closed
  WH -> WH       : retain every exact predecessor release; activate no generation
  RL -> MR       : existing request timeout records unknown delivery
  MR -> Q1 -> WH : at most one existing recovery probe, if the port remains live
  WH -> Q2       : probe ACK posts with next generation G
  WH -> WH       : commit failed-ACK predecessors + probe releases, then activate G
  Q2 -> MS       : observe probe ACK G before any released G job/patch

PROBE TIMEOUT OR PARTIAL JOB/PATCH POST

  RL -> MR       : probe timeout closes receipt admission
  MR -> PR       : request existing worker replacement
                    exactly once

  WH -> WH       : acquire credit + start lease for attempt A
  WH -> Q2       : post job A
  WH -> Q2       : content-ready patch A post throws
  WH -> WH       : enter replacement-required; no rollback assumption,
                    no old-lifetime publication or retry
  WH -> PR       : signal existing worker-failure/replacement ingress once

  PR -> WH       : close receipt admission; abort preparation; clear Review
                    attached/detached records, File latest intent, occupied,
                    pending-release, replacement-required, and fulfillment state
  PR -> WH       : install a fresh worker with an empty publication window
  WH -> WH       : new demand/bootstrap begins only after the clear

A Main-side timeout never releases receipt admission by replaying the mixed
batch. A late old-lifetime callback never releases publication credit.
```

- Stale fulfillment and physical matching are independent. An exact first
  queued/rejected/superseded receipt may settle its tombstone while the batch
  reports stale/degraded; it cannot make stale fulfillment current. A foreign
  or mismatched identity cannot release. Other receipts still apply in order.
- Duplicate first queued or terminal receipt: fulfillment and credit settlement
  are idempotent; only the first exact physical match creates one pending release.
- Late ACK observation after a successful post: credit may commit because FIFO
  guarantees the ACK remains before every newly released job. Main retains its
  existing unknown-debt/probe policy until the correlated outcome arrives.
- ACK post failure: all predecessor releases stay pending and newly eligible work
  is not scheduled. The next successful receipt/probe ACK commits the exact FIFO
  prefix plus current releases; if the probe times out, replacement is requested
  exactly once.
- Receipt lease expiry: fulfillment records the timeout, publication enters
  replacement-required, and old-lifetime retry publication is blocked. The
  existing pane replacement lifecycle is requested exactly once.
- Job/patch partial publication: the two posts remain ordered, but failure of
  either after credit acquisition enters replacement-required. The design makes
  no platform rollback assumption, even when the first post may not have queued.
- Source/currentness change: unposted work is cancelled or replaced by the
  existing owner. Posted work retains its credit tombstone; latest Review/File
  intent waits upstream and cannot cross the old attempt.
- Worker replacement: pane runtime first closes receipt admission, then aborts
  worker preparation and clears Review attached/detached records, File latest
  intent, occupied/release-pending/replacement-required identities, fulfillment
  state, and Main's highest observed ACK generation. Only then may the new
  worker derive demand/bootstrap. Old callbacks are inert.
- Surface/pane disposal: the same teardown clears pending receipts, lifecycle
  subscriptions, publication window state, preparation work, coordinators, and
  RPC timers.
- Telemetry unavailable: product behavior remains fail-open; required proof is
  ineligible rather than product-failing.
- Product-control or SQLite delay after fast worker admission: report that
  owner explicitly. Publication and receipt backpressure do not redesign the
  serialized product-control mux.

## Alternatives

### Selected — registry-owned publication credit plus retained receipt batching

This keeps one port and both existing semantic admission systems. Main receipt
batching bounds main-to-worker predecessors. The existing per-surface
fulfillment registry adds the exact credit lifecycle, ACK-gated release, and
release generation,
while Review and File keep waiting work in their current owners. Cost moves to
slightly longer Review-position occupancy and latest-selected File work waiting
behind one old publication; those owners already pay the fetch/preparation and
currentness costs. Measurement that the shared-policy-derived Review and
one-File limits still miss the
existing timeout or lease would reopen the capacity/budget design, not justify
silently raising a number.

### Rejected — separate publication scheduler or waiting-job queue

A second owner could queue prepared jobs and meter them independently, but it
would duplicate Review rank/currentness and File latest-selection state. The
existing fulfillment registry already owns exact attempt identity and lease
start, and existing upstream owners can retain all waiting work. A separate
queue therefore adds synchronization and teardown races without satisfying an
additional requirement.

### Deferred — worker-to-main render batching

The failure proves excessive outstanding publications, not excessive envelope
or serialization overhead per individual job. Jobs and content-ready patches
remain individual so current transfer lists, identities, Main admission, and
per-attempt settlement remain unchanged. Only fresh measurement of per-envelope
cost after bounded publication could reopen batching.

### Rejected — one batch per animation frame

At the observed 21,806 receipts and a 64-receipt maximum, 341 frames are needed;
at 60 Hz that is about 5.7 seconds, already beyond the five-second lease.
Background documents may throttle or stop frames. A visual clock cannot own
protocol settlement.

### Rejected — chained MessageChannel tasks

Task yielding reduced the observed maximum wait from roughly 48 seconds to
roughly 5.6 seconds but still crossed the lease because it admitted work
without downstream acknowledgement.

### Rejected — three physical product ports

Separate ports isolate queues but provide neither worker parallelism nor
priority. They remove free global ordering and require cross-port sequencing,
bootstrap, replacement, replay, and failure contracts. Current evidence does
not show a disciplined single port is insufficient.

### Deferred — global semantic admission scheduler

Urgent actions, latest-state demand, and ordered settlement are useful semantic
classes, but only settlement is proven to flood the port. Existing demand
owners remain until per-command measurement identifies a concrete violation.

## Proof pyramid

```text
unit
  batch size/order; duplicate suppression; one-in-flight; lifecycle terminal;
  shared Review policy/one-File capacity; lease after credit; exact physical
  matching independent from stale fulfillment; retained predecessor releases;
  replacement-required and exactly-once request; two-post partial failure;
  Review detached record; File latest intent; scrubbed telemetry/generation

integration
  actual product MessageChannel request/ack; worker applies array in order;
  successful probe ACK commits failed-ACK predecessors; ACK generation observed
  before released job/patch generation; rapid File selection keeps latest intent
  while registry owns old tombstone; Review invalidation detaches posted record;
  lease/post/probe failures replace once; lifetime reset makes callbacks inert

browser with real worker
  large Review render settlement; page responsiveness; no retry amplification;
  bounded published-but-unsettled count/age; Main receive-order counter remains
  zero; exact annotation outcome independent of projection; quiescent zero drain

Vite + Swift development backend + real worktree
  baseline/after measurements; root plus five replies; reload durability;
  fresh marker-scoped query; source/SQLite evidence; ACK-before-generation
  ordering; no admission-caused timeout/lease/replacement; quiescent zero drain

packaged WKWebView cap
  same product route, background/occluded lifecycle, comment settlement,
  worker replacement, telemetry marker, and responsive interaction
```

Focused implementation proof runs before wider BridgeWeb gates. Exact-HEAD
`mise run test` and packaged proof remain required by the parent delivery goal;
unit or fixture evidence is never called runtime proof.

## Requirement, design, and proof trace

| Specification / Requirements basis | Structural realization | Observable proof seam |
| --- | --- | --- |
| R-CWA-001; U-CWA-004, U-CWA-007 | Existing pane session, one comm worker, one product `MessageChannel`; the window is worker-local registry state. | Topology/static contract and runtime worker-lifetime identity show no new route or worker. |
| R-CWA-002, R-CWA-004; U-CWA-001, U-CWA-002 | Existing exhaustive semantic classification and producer-owned demand/currentness; publication credit owns neither. | Classification tests and unchanged demand-owner behavior; no general scheduler or register. |
| R-CWA-003; U-CWA-001, U-CWA-004 | Existing direct action send plus one-in-flight receipt batch and bounded worker publications; correlated outcomes share the ACK-before-release ordering. | Integration injects an urgent annotation action between batches and under full publication capacity, then observes worker handling and its exact outcome before later receipt/new publication work. |
| R-CWA-005, R-CWA-006, R-CWA-007; U-CWA-003, U-CWA-004, U-CWA-007 | Existing ordered receipt admission plus registry credit states, independent physical matching, retained FIFO releases, replacement-required exits, and full lifetime reset. | Deterministic batch/probe/partial-post/lease/overload/replacement tests prove exact release, exactly-once replacement, inert old callbacks, and bounded drain. |
| R-CWA-008; U-CWA-001, U-CWA-004, U-CWA-006 | Existing annotation command, product-control mux, Swift authority, SQLite commit, and later projection. | Exact committed action outcome is observed separately from projection/paint; reload reads durable bodies. |
| R-CWA-009, R-CWA-010; U-CWA-005, U-CWA-007 | Existing telemetry worker/marker path plus compact receipt, publication-credit, replacement, and Main receive-generation observations. | Scrubbing tests and a fresh marker-scoped Vite query expose both FIFO directions, ACK/released-generation order, ages, partial failures, replacement, and quiescent drain without raw identities. |
| R-CWA-011; U-CWA-001, U-CWA-003, U-CWA-006 | Existing Vite -> production comm worker -> actual product MessageChannel -> Swift backend -> real worktree -> SQLite journey. | Root plus five replies remain inspectable and survive reload; actual-channel ordering and product/telemetry zero drain prove bounded duplex progress. |
| R-CWA-012; U-CWA-002, U-CWA-005, U-CWA-007 | Stop line retains one port, existing demand owners, and individual render jobs; expansion requires new evidence. | Diff/architecture boundary plus the comparative run establish whether any named producer or envelope cost remains. |
| R-CWA-013; U-CWA-001, U-CWA-003, U-CWA-004, U-CWA-005, U-CWA-007 | Shared-policy-derived Review credit and one File credit; handler application result; ACK-first commit of FIFO predecessors; Review detached records; File latest-intent wake; release generation; replacement-required cleanup. | State and actual-MessageChannel integration observe legal releases, successful-probe predecessor commit, ACK generation before released job/patch, partial-post recovery, and full quiescent zero drain. |
