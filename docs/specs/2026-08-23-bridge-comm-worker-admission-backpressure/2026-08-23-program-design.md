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
ownership and transport boundary. The failure is admission mismatch: ordered,
high-volume settlement feedback was posted as thousands of independent RPC
messages into the same main-to-worker FIFO used by exact comment actions.

The correction stays before the physical port and is specific to render
settlement:

```text
urgent actions and existing demand owners ────────────────┐
                                                          v
main render fulfillment -> receipt admission owner -> one MessagePort
                               ^
                               | one terminal RPC outcome releases next batch
                               +-------------------- comm worker
```

The worker's existing `renderDisposition` handler already applies receipt
transitions in order and emits one typed ready or degraded response for the
request. That response is the backpressure signal. No new handshake, route,
worker, native call, or timer is required.

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

BridgeMainRenderDispositionAdmission                   changed/new bounded owner
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
        replacement, disposal
  rule: urgent actions continue posting directly; it does not become a
        generalized semantic scheduler

comm-worker renderDisposition handler                  changed batch consumer
  owns: strict batch validation, in-array application order, one typed
        ready/degraded response
  delegates: every receipt to the existing fulfillment registry

BridgeWorkerRenderFulfillmentRegistry                  existing
  owns: accepted/duplicate/rejected receipt semantics, lease expiry,
        retry readiness, per-item fulfillment state

Bridge telemetry producer/worker                       existing
  owns: compact source-scrubbed samples and export
  rule: product admission never awaits telemetry

bridgeRenderDispositionAdmissionPolicy                 added behavioral policy
  owns: batch maximum 64, pending maximum 6,144, one recovery probe
  derivation: 2,048 retained Review content entries * three required
              queued/applied/painted transitions
```

Forbidden edges:

- the receipt admission owner does not classify or queue annotation actions;
- the session does not inspect comment bodies or annotation operation payloads;
- the comm worker does not infer priority from React component provenance;
- receipt batching does not alter the product-control mux or SQLite ordering;
- telemetry does not release a batch or determine product success;
- demand and receipts do not gain physical ports;
- visual animation frames do not schedule protocol delivery.

## Current and proposed call-path delta

```text
CURRENT FAILURE

Pierre/main render observation
  -> one receipt
  -> BridgeWorkerRpcClient.send
  -> one request row + one timeout
  -> MessagePort.postMessage
  -> comm-worker FIFO wait
  -> one receipt application
  -> one ready/degraded response

Repeated per receipt, allowing thousands of posted RPCs before draft.flush.

PROPOSED

Pierre/main render observation
  -> strict receipt
  -> per-surface BridgeMainRenderDispositionAdmission
  -> append in generation order
  -> if no batch is in-flight, take at most 64 receipts
  -> BridgeWorkerRpcClient.send one renderDisposition batch
  -> retain returned request id as in-flight
  -> comm worker validates and applies receipts in array order
  -> one ready/degraded response settles that request lifecycle
  -> lifecycle subscription releases the in-flight slot
  -> dispatch the next bounded batch, if any

URGENT ACTION WHILE A BATCH IS IN-FLIGHT

receipt batch 1 already posted
  -> annotationCommand(draft.flush) posts directly through its surface client
  -> receipt admission cannot post batch 2 until batch 1 is terminal
  -> physical FIFO order is batch 1, draft.flush, batch 2
```

Changed edges are confined to receipt command shape, per-surface receipt
admission, lifecycle settlement, telemetry, and their tests. Annotation,
demand, product-control, Swift, SQLite, Review presentation, and Pierre render
observation remain unchanged.

## Receipt admission state machine

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
  probe timeout ---------------------------------> stalled
  worker replacement/dispose --------------------> cleared

stalled
  dispatch no receipt batch
  individual worker fulfillment leases remain authoritative
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
stalls receipt dispatch. Existing lease/retry behavior repairs missing attempt
state, and worker replacement clears the latch. Repeated timeouts fail the
workload gate rather than widening physical debt.

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

## Pending-state boundedness

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
worker product dispatch -> result         product-control duration
Swift command start -> SQLite commit      native persistence duration
command outcome -> projection -> paint    reconciliation/presentation duration
```

Telemetry export/ingestion timestamps never replace producer event timestamps.
Victoria queries use a fresh proof marker or exact run start and bounded service
and worktree labels.

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
```

All waits bind to protocol/state outcomes with bounded test timeouts. No
wall-clock sleep establishes readiness. The baseline and after run record exact
HEAD/diff identity, comparison identity, item count, worker lifetime, command
counts, queue distributions, receipt lifecycle, annotation stages, and durable
SQLite/source evidence.

## Failure and recovery

- Stale or mismatched receipt: the worker applies other valid receipts in
  order, returns typed degraded, and the fulfillment registry retains or
  retries the affected attempt.
- Lost/late acknowledgement: one batch remains the maximum physical receipt
  debt; timeout records unknown delivery and no blind replay occurs.
- Receipt lease expiry: the existing registry re-demands the item. Any expiry
  caused by admission backlog fails this design's runtime gate.
- Worker replacement: pane runtime first marks every receipt admission owner
  `closing`, unsubscribes it from lifecycle settlement, and clears pending,
  in-flight, timeout debt, and probe state. Only then does it synthesize
  degraded terminals for other old RPC requests, retire fulfillment, and close
  the old port. A terminal callback observed while `closing` cannot dispatch.
  The new worker derives its own current demand and receives no old receipt.
- Surface/pane disposal: pending receipts, lifecycle subscription, in-flight
  identity, coordinator state, and RPC timers are released.
- Telemetry unavailable: product admission and comment actions continue;
  required proof becomes ineligible rather than product-failing.
- Product-control or SQLite delay after fast worker admission: report that
  owner explicitly. Receipt backpressure must not conceal or redesign the
  serialized product-control mux.

## Alternatives

### Selected — acknowledgement-paced batches on the existing route

This reuses the typed RPC outcome as true downstream progress, bounds physical
receipt debt to one batch, and allows urgent actions to enter before the next
batch without reconstructing cross-port ordering.

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
  timeout; reset/dispose; telemetry attributes; no frame/timer scheduling

integration
  RPC request/ack; worker applies array in order; urgent action between batches;
  stale receipt mixed with valid receipts; worker replacement; surface isolation

browser with real worker
  large Review render settlement; page responsiveness; no retry amplification;
  exact annotation command outcome independent of background projection

Vite + Swift development backend + real worktree
  baseline/after measurements; root plus five replies; reload durability;
  source identity and SQLite evidence

packaged WKWebView cap
  same product route, background/occluded lifecycle, comment settlement,
  worker replacement, telemetry marker, and responsive interaction
```

Focused implementation proof runs before wider BridgeWeb gates. Exact-HEAD
`mise run test` and packaged proof remain required by the parent delivery goal;
unit or fixture evidence is never called runtime proof.

## Requirement realization

- R-CWA-001/R-CWA-002: existing pane session and typed contracts plus semantic
  classification in design/tests; prove no new route and correct annotation
  operation classification.
- R-CWA-003: per-surface receipt admission plus direct surface-client action
  dispatch; prove one batch maximum ahead of an action and report the exact
  action cohort without borrowing the selected/click percentile budget.
- R-CWA-004: existing demand owners and measurement-first stop line; prove no
  generalized demand mutation in this increment.
- R-CWA-005/R-CWA-006/R-CWA-007: receipt schema, admission state machine, RPC
  lifecycle, reset/dispose, and telemetry; prove order, bounds, outcomes, and
  drain.
- R-CWA-008: existing annotation command, product mux, Swift SQLite owner, and
  lifecycle projection; prove exact committed outcome separately from
  reconciliation.
- R-CWA-009/R-CWA-010: existing telemetry worker and Victoria marker path plus
  new compact receipt counters; prove source scrubbing and identical workload.
- R-CWA-011: permanent real-worktree Vite E2E and SQLite/source verifier.
- R-CWA-012: review of comparative evidence before any demand or physical-route
  expansion.
