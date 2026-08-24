# Bridge Comm-Worker Admission And Backpressure — Specification

Date: 2026-08-23

Governing requirements:
[2026-08-23-requirements.md](./2026-08-23-requirements.md).

Program realization:
[2026-08-23-program-design.md](./2026-08-23-program-design.md).

## Observable model

Bridge classifies main-to-comm-worker input by semantic obligation before
choosing a contraction or backpressure mechanism, and it separately bounds
worker-to-main progress for render publication and correlated control outcomes:

```text
urgent action/control
  exact intent -> prompt ordered admission -> exact terminal outcome

demand
  current desired state -> equality/scope-aware contraction -> current work

delivery settlement
  ordered attempt feedback -> bounded batch -> worker acknowledgement

worker-to-main render publication and control outcomes
  render work -> bounded published-but-unsettled predecessor work
  correlated outcome -> before newly released render work -> existing timeout/lease bounds
```

The classes share one existing product `MessageChannel`. FIFO ordering applies
within each direction; a message in one direction does not by itself bound work
already published in the other. A class does not gain a second worker, route,
source of truth, or independent cross-class ordering domain.

## Normative requirements

### R-CWA-001 — One product route

Main-to-worker product commands MUST continue through the one pane-owned
product `MessageChannel` and comm-worker instance. Admission work MUST NOT add
another physical product port or bypass the typed RPC contracts, worker
generation fences, or pane-session lifecycle.

Telemetry MAY continue using its existing separate optional producer port and
MUST remain outside product admission and product correctness.

Basis: U-CWA-004, U-CWA-007.

### R-CWA-002 — Semantic input classes

Bridge MUST distinguish:

- urgent actions and correctness controls whose exact effects and outcomes are
  non-replaceable;
- demand whose unsent intermediate values may contract only under an owning
  latest-state, equality, generation, or scope-preservation rule; and
- render-settlement receipts whose admitted transitions and per-attempt order
  remain required.

RPC is an envelope and lifecycle, not an admission class. An outer
`annotationCommand` MUST be classified from its operation kind: durable
mutations such as `draft.flush`, `draft.save`, `root.create`, and
`reply.create` are urgent actions, while `demand.acquire`, `demand.release`,
and `source.refresh` retain their existing demand/currentness semantics.

Basis: U-CWA-001, U-CWA-002, U-CWA-003.

### R-CWA-003 — Urgent-action non-starvation

An urgent action or correctness control MUST be posted without waiting for
unsent demand contraction or pending render-receipt batches. Already-posted
main-to-worker work may finish first because that direction is FIFO, but render
admission MUST bound that predecessor work to at most the one receipt batch
already in-flight for the action's surface. The action's correlated worker
control or terminal outcome MUST NOT then wait behind an unbounded
worker-to-main render-publication backlog and remains subject to the existing
timeout and duplex-progress obligation in R-CWA-013.

No later receipt batch may enter the port before an urgent action already
present at the main admission boundary. Urgent action ordering, revision/source
validation, product-control serialization, and exact terminal outcomes MUST
remain unchanged.

The real workload MUST report every exact comment-action queue wait separately
from demand and settlement, and MUST prove that each action already present at
main admission begins worker handling before any later receipt batch and that
its correlated outcome is not delayed by unbounded worker-to-main render
predecessors. An isolated slower authoritative product call is reported at its
own stage and MUST NOT be attributed to either transport direction. This
increment does not invent a numeric comment-action percentile SLO from the
separate selected/click cohort.

Basis: U-CWA-001, U-CWA-004.

### R-CWA-004 — Demand contraction

Demand MUST NOT be converted into a generic FIFO batch merely because it is
frequent. Each current producer MUST retain its existing owner and fitting
mechanism:

- latest-state inputs suppress obsolete unsent values only after equality and
  generation validation;
- scope-bearing invalidations retain the union or escalation required by the
  newest admitted work;
- acquire/release facts preserve their per-key ordering; and
- finite requests keep request identity, cancellation, and one terminal result.

This increment MUST measure command counts and queue wait before changing a
demand producer. A general demand register or scheduler is not authorized by
render-receipt evidence alone.

Basis: U-CWA-002, U-CWA-005.

### R-CWA-005 — Ordered receipt batching

Main MUST preserve every required render disposition in the order generated
for one render attempt. It MAY place several receipts into one
`renderDisposition` command when:

- the batch targets one surface and current worker instance;
- receipt identities remain complete and independently validated;
- batch order is the generation order; and
- the batch contains no more than 64 receipts.

Batching MUST NOT merge identities, skip queued/applied transitions needed by a
later painted transition, reinterpret a terminal rejection, or use one receipt
as evidence for another attempt.

Basis: U-CWA-003, U-CWA-004, U-CWA-007.

### R-CWA-006 — Acknowledgement-paced backpressure

Each surface MUST have at most one unacknowledged `renderDisposition` batch on
the product port. The worker MUST apply its receipts in array order and return
one existing typed ready or degraded RPC outcome for that batch. Only a
terminal lifecycle outcome for the in-flight batch may release the next batch.

This one-in-flight rule bounds receipt commands admitted main-to-worker only.
It does not by itself bound worker-to-main render publications that can precede
the correlated outcome; reverse-direction progress MUST also satisfy
R-CWA-013.

The sender MUST NOT pace protocol settlement by animation frame, periodic
timer, polling, or a chain of unacknowledged message tasks. A backgrounded or
occluded document must not suspend receipt progress merely because visual
frames stop.

An acknowledged or typed-degraded batch is settled for transport admission;
individual accepted, duplicate, or rejected receipts remain owned by the
existing fulfillment state machine.

An acknowledgement timeout is an unknown delivery outcome. The sender MUST
retain one unknown-delivery debt latch and MUST NOT replay the mixed batch. It
MAY admit exactly one later receipt batch as a recovery probe. A correlated
ready or degraded outcome for that probe proves that the worker handled both
main-to-worker predecessors and that their outcomes reached main, but it does
not by itself prove that worker-to-main render predecessor work stayed bounded.
If the probe also times out, receipt dispatch MUST pause until worker
replacement clears the debt. Urgent actions remain direct and are not held by
the receipt latch. Existing lease expiry, retry, and worker-replacement owners
remain authoritative.

Basis: U-CWA-003, U-CWA-004, U-CWA-007.

### R-CWA-007 — Bounded pending state

The receipt owner MUST retain pending work only for receipts emitted by the
current pane/surface worker lifetime, suppress exact duplicate dispositions,
and release pending and in-flight state on terminal batch outcome, worker
replacement, surface disposal, and document teardown. Initial policy MUST cap
pending receipts at 6,144 per surface: the existing 2,048-entry Review content
registry ceiling multiplied by the three required positive transitions per
attempt. The cap belongs to the Bridge behavioral-policy owner.

Pending count, oldest pending age, and high-water mark MUST be observable. A
required workload that grows pending state monotonically, crosses the receipt
lease, or relies on repeated lease retries is a failed gate, not permission to
increase capacity or timeout. Reaching capacity MUST close receipt admission
for the current worker, emit a typed source-scrubbed overload outcome, and
request the existing worker-replacement lifecycle exactly once. Replacement
clears old receipt state before the new worker can derive demand. Ordered facts
MUST NOT be silently dropped while the old worker remains authoritative.

The 6,144-receipt cap is an overload containment boundary, not evidence of
bounded progress. Reaching it, or repeatedly replacing workers because
worker-to-main render predecessors delay correlated outcomes, fails the
required workload.

Basis: U-CWA-003, U-CWA-005, U-CWA-007.

### R-CWA-008 — Exact comment outcome

Comment Save, reply, root creation, editing, resolution, and output actions MUST
continue through the current typed annotation command and authoritative Swift
and SQLite owners. The UI may settle the corresponding user interaction from
the exact committed command outcome; it MUST NOT wait for an unrelated render
receipt backlog or fabricate success before that outcome.

Annotation projection remains a background reconciliation of durable truth.
This specification does not authorize UI changes, but runtime proof MUST
distinguish command commitment from later projection and paint.

Basis: U-CWA-001, U-CWA-004, U-CWA-006.

### R-CWA-009 — Source-scrubbed measurement

Fresh marker-scoped evidence MUST provide bounded dimensions and values for:

- command and semantic class counts, with `annotationCommand` classified from
  its validated inner operation kind;
- main-to-worker queue wait and worker handler duration;
- receipt batch size, terminal outcome, acknowledgement duration, pending
  count, pending high-water mark, and oldest pending age;
- worker-to-main render publications published but not yet settled by main,
  including current count, high-water mark, and oldest unsettled age;
- correlated worker control and acknowledgement delivery relative to render
  publications already pending and render publications newly released by the
  corresponding settlement;
- render lease expiration and retry counts;
- annotation lifecycle stage and duration; and
- product-control duration where a user action crosses that owner.

Instrumentation MUST use existing asynchronous telemetry producers and MUST
NOT stringify or size arbitrary product payloads on an interactive path.
Telemetry ingestion time is not application event time. Raw identities,
payloads, paths, bodies, selections, errors, capabilities, and secrets are
prohibited.

Basis: U-CWA-005, U-CWA-007.

### R-CWA-010 — Measurement-first comparison

Before accepting batching, Bridge MUST record a baseline against the unchanged
real workload and then repeat that exact workload after the correction. Both
runs MUST identify the exact code state, target comparison, worker lifetime,
and observation boundary.

The comparison MUST report what was measured, what was derived, and what
remains unavailable. Old telemetry, stale screenshots, unit fixtures, and
telemetry export cadence MUST NOT satisfy a fresh runtime claim.

The corrected run MUST show bounded progress in both directions. Reduced
main-to-worker queue wait or receipt-command count alone is insufficient:
worker-to-main published-but-unsettled render count and age, correlated outcome
delivery, and acknowledgement-before-newly-released-render ordering MUST also
satisfy R-CWA-013.

Basis: U-CWA-005, U-CWA-006.

### R-CWA-011 — Real five-reply proof

The final development-server proof MUST execute:

```text
load the real large Review
create one root comment
save replies 1 through 5 sequentially
reload the browser document
verify the root and all five reply bodies from durable projection
```

Every `draft.flush`/`draft.save` and reply creation MUST receive its exact
terminal outcome, no receipt lease may expire through admission backlog, the
page must remain interactively inspectable, and reload must recover the exact
durable bodies. Correlated action, control, and receipt outcomes MUST NOT time
out behind render publication; worker-to-main published-but-unsettled render
count and age MUST remain bounded and drain after workload quiescence; and each
receipt acknowledgement MUST reach main before render work newly released by
that settlement. The proof must cross Vite, production comm worker, Swift
development backend, real Git worktree, and SQLite.

Basis: U-CWA-001, U-CWA-003, U-CWA-006.

### R-CWA-012 — Conditional expansion only

If ordered receipt batching and duplex bounded progress satisfy the real proof,
this increment MUST stop without adding a global admission scheduler, new
physical route, or required worker-to-main render-batch shape. If a named demand
producer still causes user-action starvation, its source evidence MUST return
to this design's demand rule before a keyed contraction owner is added. If
worker-to-main render publication still violates R-CWA-013, that evidence MUST
return to Program Design for a bounded realization that preserves existing
render identity, currentness, and settlement semantics; this Specification does
not preselect batching as that realization.

Separate physical ports require a new Program Design decision supported by
evidence that one disciplined port remains the transport bottleneck after
receipt backpressure, duplex bounded progress, and fitting demand contraction.
Port count MUST NOT be used as a substitute for worker scheduling or
product-control diagnosis.

Basis: U-CWA-002, U-CWA-005, U-CWA-007.

### R-CWA-013 — Duplex bounded progress

While render publications and correlated worker control or receipt outcomes
share the worker-to-main FIFO direction, render publication MUST NOT create an
unbounded predecessor backlog. Correlated outcomes MUST reach main before their
existing RPC timeout, and reverse-direction backlog MUST NOT age required
receipt settlement beyond its existing lease.

When applying a receipt batch makes additional render work eligible, main MUST
observe the correlated ready or degraded acknowledgement before any render
publication newly released by that settlement. Render publications already
published may remain ahead of the acknowledgement, but their
published-but-unsettled count and oldest unsettled age MUST stay bounded and
MUST drain after demand quiesces in the required real workload.

This obligation preserves current render identity, source and currentness
fences, per-attempt settlement, and no-silent-drop behavior. It specifies no
credit count, admission registry, module owner, render batch shape, second port,
new timeout, or new capacity.

Basis: U-CWA-001, U-CWA-003, U-CWA-004, U-CWA-005, U-CWA-007.

## Proof obligations

- V-CWA-001: deterministic receipt-batch order, size, one-in-flight,
  unknown-debt/probe timeout, capacity overload, disposal, and
  worker-replacement tests.
- V-CWA-002: integration proof that an urgent annotation action posted while a
  receipt batch is in-flight precedes every later receipt batch and its outcome
  is not held behind unbounded render predecessors; plus proof that each receipt
  acknowledgement reaches main before render work newly released by applying
  that batch.
- V-CWA-003: source/currentness tests for mixed current and stale receipt
  identities without cross-surface or cross-worker acceptance.
- V-CWA-004: source-scrubbed telemetry tests for every required bounded outcome,
  including worker-to-main published-but-unsettled render count and age plus
  correlated outcome/render ordering, and for prohibited payload/identity
  fields.
- V-CWA-005: identical baseline/after workload evidence with queue-wait,
  handler, receipt pending, worker-to-main published-but-unsettled render,
  acknowledgement, expiry, retry, and annotation stages.
- V-CWA-006: real root-plus-five-reply durability and reload journey with
  bounded duplex progress, no admission-caused timeout or lease expiry, and
  eventual drain after workload quiescence.
- V-CWA-007: focused BridgeWeb typecheck, format, lint, unit, integration, and
  browser gates followed by the repository aggregate and packaged boundary
  proof required by the parent goal.

## Negative space

This contract does not create transport parallelism, a second comm worker,
cross-port priority, generalized RPC priority, payload batching for user
actions, a required worker-to-main render-batch shape, a demand event history,
or a new comment persistence model.
