# Bridge Comm-Worker Admission And Backpressure — Program Design

Date: 2026-08-23

Requirements:
[2026-08-23-requirements.md](./2026-08-23-requirements.md).

Specification:
[2026-08-23-specification.md](./2026-08-23-specification.md).

Current foundations:

- [Demand-Driven Derived-State Refresh](../../../architecture/state/demand_driven_derived_state_refresh.md)
- [Local-First Comm Worker Architecture](../../bridge-viewer-transport/local-first-comm-worker-architecture.md)
- [Observability And Traceability](../../../architecture/observability/observability_and_traceability.md)

## What changes and what stays authoritative

Bridge keeps one pane-owned comm worker and one product `MessageChannel`.
Urgent actions continue to post directly. Demand remains with its current
producer and contracts only under that producer's equality, currentness, and
scope rules. Main batches ordered render dispositions per surface and keeps at
most one such batch in flight for that surface.

The remaining change is worker-to-main admission. Review currently frees its
three reserved and nine dynamic demand positions when preparation finishes.
Those positions can cycle through a 1,699-item comparison while earlier render
jobs, content-ready patches, and correlated outcomes remain in the shared
worker-to-main FIFO. File can similarly start work for a newer selection while
the already-published selected operation is still awaiting settlement.

The correction uses those existing owners as the bound:

```text
Review publishes from one of its existing 3 + 9 positions
  -> that position remains occupied after publication
  -> Main returns its existing ordered disposition batch
  -> worker applies the batch and constructs the correlated response
  -> worker synchronously posts that response
  -> first exact queued or terminal rejected/superseded releases only
     matching Review positions
  -> existing Review reconcile/drain may publish later work

File publishes its one selected operation
  -> a newer selection remains the latest waiting intent
  -> Main returns its existing ordered disposition batch
  -> worker applies the batch and constructs the correlated response
  -> queued or applied keeps the published File operation current
  -> worker synchronously posts that response
  -> painted or terminal rejected/superseded settles the File operation
     only after that correlated response posts successfully
  -> existing File preparation/drain may then start the latest intent
```

This call order is sufficient because `postMessage` and the later render posts
use the same worker-to-main FIFO. A render publication made eligible by a
settlement cannot be posted until after the correlated response has been
posted. No new port, scheduler, job queue, render batch, registry, handshake,
timer, persistence, native interface, security boundary, or UI behavior is
introduced.

The measured first correction remains authoritative. Ordered receipt batching
reduced maximum main-to-worker queue wait from 52,932.7 ms to 2,083.7 ms, with
no wait at or above the five-second lease. The same run showed that the reverse
FIFO was still unbounded: worker handling remained 28.3 ms at maximum, eight
correlated responses timed out, pending receipts reached 6,144, and three
worker replacements repeated the loop. The design therefore retains receipt
batching and fixes only the existing-owner effect timing that produced the
reverse backlog.

## Semantic admission model

| Input class | Meaning | Admission behavior |
| --- | --- | --- |
| Urgent action or correctness control | Exact non-replaceable intent | Post directly through the existing typed RPC path; preserve identity, validation, order, and terminal outcome. |
| Demand | Current desired state | Keep the current producer owner; replace, suppress, or merge only when its equality, generation, and scope rules allow it. |
| Render disposition | Ordered feedback about delivered work | Preserve attempt order, batch at most 64 per surface, and keep one batch in flight per surface until its existing typed lifecycle settles. |
| Render publication | Work delivered from worker to Main | Admit through the existing Review positions or File selected operation. Release Review after the correlated response containing first exact queued or terminal rejected/superseded posts; keep File current through queued and applied, then settle it only after the correlated response containing painted or terminal rejected/superseded posts. |

RPC remains the envelope rather than an admission class. The single
`MessageChannel` remains the final FIFO in each direction; ordering in one
direction does not itself bound the other direction.

## Existing owners and their bounded changes

### Main render-disposition admission

`BridgeMainRenderDispositionAdmission` remains one instance per Review or File
surface. It owns:

- the ordered pending disposition list;
- exact duplicate suppression;
- one in-flight batch identity;
- the 64-receipt batch maximum and 6,144-receipt pending ceiling;
- terminal lifecycle settlement, unknown-delivery debt, and one recovery probe;
- pending count, age, high-water mark, and batch telemetry.

It does not classify or queue urgent annotation actions. Those continue through
`BridgeWorkerRpcClient` and `BridgePaneCommWorkerSession` immediately. It does
not own worker render admission or replacement.

### Worker disposition application and response

The existing `renderDisposition` handler continues to validate the batch and
apply its receipts in array order through the owning surface fulfillment
registry. `BridgeWorkerRenderFulfillmentRegistry` remains authoritative for
attempt identity, accepted/duplicate/rejected receipt meaning, source and
currentness validation, lease expiry, and retry eligibility.

Disposition application returns the existing ready or degraded correlated
response plus only the lifecycle-eligible existing-owner effects derived from
valid attempt identities. Review becomes eligible on first exact queued or
terminal rejected/superseded. File becomes eligible only on painted or terminal
rejected/superseded; queued and applied preserve its current operation. These
effects are ephemeral results of applying the current batch; they are not stored
as another queue or ownership system.

`dispatchBridgeCommWorkerRuntimeProductControl` synchronously posts the
correlated response. Only after that call succeeds does the runtime apply any
lifecycle-eligible matching Review/File effects and request the corresponding
existing preparation drain. If the post throws, it applies none of those
effects.

### Review demand positions

`BridgeCommWorkerReviewDemandLedger` remains the sole owner of the three
reserved and nine dynamic ranked positions. Fetch, rank, currentness,
invalidation, cancellation, and reconcile behavior remain there.

Before publication, stale or cancelled work may release its position under the
existing rules. After both ordered render posts succeed, the position retains
the exact attempt association until the correlated response containing first
exact queued or terminal rejected/superseded is posted successfully.
If the underlying demand becomes obsolete while published, the record remains
only long enough to prevent reuse of that position; releasing it must not
revive stale demand. A mismatched or foreign attempt cannot release it.

The maximum Review render work published without its correlated response is
therefore derived from the existing policy: three reserved plus nine dynamic
positions. There is no independent numeric owner for twelve.

### File selected operation

The existing File selected-operation controller and latest selected preparation
request remain the sole owners of File intent. Once a selected operation has
published, a newer selection replaces only the waiting latest intent. It does
not allow another File publication while the published operation remains
current through queued and applied. The existing operation settles only after
the correlated response containing exact painted or terminal
rejected/superseded posts successfully.

This preserves the selected operation's existing ownership of install, render,
paint, file-content, and worker-application lifecycle telemetry. Admission is
not split from that lifecycle, and no second File operation owner or waiting-job
queue is introduced.

The worker then runs the existing currentness checks and preparation drain for
the latest intent. No waiting-job queue or polling loop is added.

### Pane session and replacement

`BridgePaneCommWorkerSession` continues to own the product port, worker
lifetime, RPC lifecycle, disposal, and replacement. It observes failures and
timeouts but does not become a semantic scheduler. Worker replacement and
surface/document retirement clear the existing receipt admission,
fulfillment, Review positions, File operation/request state, preparation work,
and RPC lifecycle before fresh demand is derived.

### Telemetry

The existing asynchronous telemetry producer records compact counts,
durations, phases, and closed result values. Product behavior never waits for
telemetry, and exporter failure remains fail-open. No path, payload, comment
body, selection, raw identity, raw error, capability, or secret is exported.

## Call-path correction

The current source-grounded path is:

```text
Legend: [=] unchanged  [-] removed edge  [+] added edge

CURRENT FAILURE

Review/File demand owner
  -> fulfillment registry begins exact attempt and lease                 [=]
  -> worker posts render job then content-ready patch                    [=]
  -> Review position or File operation becomes reusable immediately     [-]
  -> existing drain publishes more work into worker-to-main FIFO        [=]

Main render owner
  -> per-surface admission queues dispositions                          [=]
  -> one ordered batch crosses main-to-worker FIFO                      [=]
  -> worker applies batch through fulfillment registry                  [=]
  -> existing Review/File effect runs before correlated response post   [-]
  -> runtime posts ready/degraded response                              [=]

Result: correlated responses wait behind render work made eligible too
early; urgent comment outcomes can then wait behind that reverse backlog.

PROPOSED REVIEW FLOW

Review demand owner
  -> fulfillment registry begins exact attempt and lease                 [=]
  -> worker posts render job then content-ready patch                    [=]
  -> published Review position remains held                              [+]

Main render owner
  -> per-surface admission queues dispositions                          [=]
  -> one ordered batch crosses main-to-worker FIFO                      [=]
  -> worker applies batch and constructs ready/degraded response        [=]
  -> runtime synchronously posts correlated response                    [=]
  -> on first exact queued or terminal rejected/superseded,
     runtime releases matching Review position                          [+]
  -> existing Review reconcile/drain resumes                            [=]
  -> later render publication posts behind the response on same FIFO    [+]

PROPOSED FILE FLOW

File selected-operation owner
  -> fulfillment registry begins exact attempt and lease                 [=]
  -> worker posts render job then content-ready patch                    [=]
  -> published File operation remains current                           [+]
  -> newer selection replaces only existing latest waiting intent       [+]

Main render owner
  -> queued response posts; File operation remains current              [+]
  -> applied response posts; File operation remains current             [+]
  -> painted or terminal rejected/superseded response posts             [=]
  -> runtime then settles the matching File operation                   [+]
  -> existing File preparation drain starts latest waiting intent       [=]
  -> later File publication posts behind terminal response on same FIFO [+]

ERROR RETURN

response post throws
  -> runtime applies no lifecycle-eligible Review/File owner effect     [+]
  -> existing worker error and replacement containment receives failure [=]
```

Current anchors:

- `BridgeWeb/src/core/comm-worker/bridge-worker-rpc-client.ts:96`
- `BridgeWeb/src/core/comm-worker/bridge-pane-comm-worker-session.ts:157`
- `BridgeWeb/src/core/comm-worker/bridge-main-render-disposition-admission.ts:82`
- `BridgeWeb/src/core/comm-worker/bridge-comm-worker-runtime-protocol.ts:744`
- `BridgeWeb/src/core/comm-worker/bridge-comm-worker-runtime-protocol.ts:761`
- `BridgeWeb/src/core/comm-worker/bridge-comm-worker-runtime-protocol.ts:855`
- `BridgeWeb/src/core/comm-worker/bridge-comm-worker-render-disposition-application.ts:21`
- `BridgeWeb/src/core/comm-worker/bridge-comm-worker-render-publication-release.ts:8`

The extracted publication-effect seam is retained only as a post-response
existing-owner operation. Its name and call placement must describe that job;
it does not own admission state or recovery.

## State and ordering

### Main-to-worker receipt admission

| State | Event | Next state and effect |
| --- | --- | --- |
| idle or pending | no batch is in flight and receipts are pending | Dispatch the next ordered batch of at most 64 and retain its request identity. |
| in flight | more receipts arrive | Append in order to pending state; do not dispatch a second batch for that surface. |
| in flight | typed ready or degraded lifecycle settles | Release the batch lifecycle and dispatch the next pending batch, if any. |
| in flight | timeout | Retain one unknown-delivery debt latch; do not replay the mixed batch; permit at most one later batch as the existing recovery probe. |
| unknown debt | probe returns ready or degraded | Clear the debt and resume ordered dispatch. |
| unknown debt | probe also times out | Pause receipt dispatch and request existing worker replacement. |
| any | replacement, disposal, or document teardown | Clear old-lifetime pending and in-flight state before fresh bootstrap. |
| pending ceiling reached | first overload | Close old-lifetime receipt admission, emit one scrubbed overload outcome, and request existing worker replacement once. |

Urgent actions bypass this state machine. A later receipt batch cannot enter
the port before an urgent action already present at Main admission.

### Review publication position

| State | Event and guard | Next state and effect |
| --- | --- | --- |
| active, not published | preparation cancels or becomes stale | Clear under existing rules and reconcile. |
| active, not published | job and patch post successfully | Retain the position with the exact attempt association. |
| published | demand invalidates or becomes stale | Remove obsolete intent but keep the position held; do not revive it later. |
| published | correlated response containing first exact queued or terminal rejected/superseded posts successfully | Clear the exact association, release the position, and run existing reconcile/drain. |
| published | foreign or mismatched settlement | Ignore it and keep the position held. |
| any | worker replacement, disposal, or teardown | Clear old-lifetime state and make old callbacks inert. |

### File selected operation

| State | Event and guard | Next state and effect |
| --- | --- | --- |
| latest intent, not published | newer selection arrives | Replace the waiting intent under existing currentness rules. |
| latest intent, not published | operation publishes | Mark that operation as published; no second File operation may publish. |
| published operation | newer selection arrives | Store it only as latest waiting intent. |
| published operation | correlated response contains exact queued or applied and posts successfully | Keep the selected operation current; do not start the waiting intent. |
| published operation | correlated response contains exact painted or terminal rejected/superseded and posts successfully | Settle the operation, then recheck and drain the latest waiting intent. |
| published operation | foreign or mismatched settlement | Ignore it and keep the operation held. |
| any | worker replacement, disposal, or teardown | Clear old-lifetime state and make old callbacks inert. |

### Ordering invariants

- Each receipt retains its complete pane, worker, surface, item, submission,
  publication, attempt, derivation, window, and operation-correlation identity.
- One disposition batch contains one surface and current worker lifetime.
- Positive receipts retain queued -> applied -> painted order per attempt;
  rejection and supersession remain terminal; exact duplicates are idempotent.
- Receipt application remains in array order. A stale or invalid receipt may
  degrade the batch without changing current fulfillment truth.
- Review release uses only first exact queued or terminal
  rejected/superseded for the matching attempt whose correlated response was
  successfully posted.
- File remains current through exact queued and applied. File settlement uses
  only exact painted or terminal rejected/superseded for the matching attempt
  whose correlated response was successfully posted.
- Review and File do not need a new shared ordering owner: JavaScript executes
  the response post and matching owner effects synchronously in one command
  handler turn, and every later render post enters the same worker-to-main FIFO.
- Work already in the worker-to-main FIFO may remain ahead of the correlated
  response. Existing Review/File limits bound that predecessor work, and the
  workload must prove count, age, and quiescent drain rather than assume it.
- No frame clock, timer, polling loop, or chained unacknowledged task controls
  protocol progress.

## Failure and recovery

### Response post throws

The synchronous post is the guard for the owner effect relevant to that
disposition. If it throws, no matching Review position is released, no File
operation is settled, and no preparation drain is requested. A File queued or
applied disposition has no settlement effect even after a successful post. The
error propagates through the existing worker failure path. Existing replacement
clears the old worker lifetime and lets fresh demand derive from authoritative
state. The worker does not attempt a second response or locally infer whether
Main received it.

### Peer closes without a synchronous error

`MessagePort.postMessage` does not provide an immediate, reliable peer-close
receipt at this boundary. The design therefore does not invent a close detector.
Main's existing RPC timeout records an unknown delivery outcome; the existing
single recovery probe, pending ceiling, lease behavior, and replacement path
contain the failure. Because published Review positions remain bounded until
their queued or terminal response and the File operation remains bounded until
its painted or terminal response, silent loss cannot reopen unlimited render
production in the worker.

### Stale, duplicate, or mixed batch entries

The fulfillment registry remains authoritative for each receipt. Valid entries
apply in array order even when another entry makes the typed batch outcome
degraded. Exact duplicates remain idempotent. A stale, foreign, or mismatched
attempt cannot release a Review position or settle the File operation. No batch
entry is treated as evidence for another attempt.

### Partial render publication

Job and content-ready patch posts remain two ordered fallible calls. If either
throws, existing worker error/replacement containment owns recovery; the design
does not assume rollback and does not add a retrying publication queue. Any
position or operation held in that old lifetime is cleared by replacement.

### Timeout, lease expiry, overload, and retirement

- A receipt-batch timeout remains unknown delivery, not permission to replay a
  mixed batch.
- A second/probe timeout requests existing replacement exactly once.
- Receipt pending overflow closes old-lifetime admission and requests existing
  replacement; it does not drop ordered facts or increase the ceiling.
- Existing fulfillment lease expiry and retry policy remain authoritative.
- Owner-initiated worker replacement, surface disposal, and document teardown
  clear all old-lifetime admission and preparation state before new work.
- Optional telemetry failure never changes product behavior.

## Bounded state and measurement

Main receipt admission retains only current-worker strict receipt DTOs. It
suppresses exact duplicates, holds at most one in-flight batch per surface, and
caps a batch at 64 and pending receipts at 6,144. The timeout path may retain
one unknown predecessor while its single recovery probe is in flight.

Worker render production is bounded by the existing owners:

- Review retains at most three reserved plus nine dynamic published positions;
- File retains at most one published selected operation;
- a Review/File mode transition may temporarily include already-published
  Review positions and the one File operation;
- no owner stores an additional list of waiting render jobs; waiting intent
  remains in the Review ledger or File latest request.

Fresh source-scrubbed observations must distinguish:

```text
main-to-worker
  command count by closed semantic class
  queue wait and worker handler duration
  disposition batch size and terminal outcome
  pending count, high-water mark, and oldest age
  acknowledgement duration, timeout, probe, and overload

worker-to-main
  render publications posted but not yet settled by Main
  current count, high-water mark, and oldest age per surface
  correlated response post before later work released by that response
  render lease expiry and retry count

comment path
  annotation lifecycle stages
  product-control duration
  authoritative Swift/SQLite outcome
  later projection and paint
```

The worker observations derive outstanding publication count and age from the
existing Review positions and File operation state. They do not export exact
attempt identities or create correctness state. Telemetry timestamps are
producer event times; Victoria ingestion time is never reported as application
latency.

## Baseline and real workload

The baseline and corrected run use the same permanent development-server
journey:

```text
seed a disposable real worktree
select the 1,699-item comparison
wait for exact Review readiness and the current visible surface
create one root comment and await its exact committed outcome
for replies 1 through 5:
  author the body
  request save
  await the exact command outcome
  verify the page remains semantically inspectable
reload the complete browser document
wait for installed Review and annotation projection
verify the root and five exact bodies from SQLite-backed projection
stop demand
wait for receipt pending and existing Review/File outstanding work to drain
```

All waits bind to protocol or product state with bounded harness timeouts; no
wall-clock sleep establishes readiness. The path crosses Vite, the production
comm worker, the actual product `MessageChannel`, Swift development backend, a
real Git worktree, and SQLite. A direct handler call or fake dispatcher cannot
prove FIFO ordering.

The comparison records exact code state, comparison identity, item count,
worker lifetime, semantic-class command counts, both FIFO directions, receipt
and publication lifecycles, annotation stages, product-control duration, and
durable SQLite/source evidence. Acceptance requires:

- every root/reply operation receives its exact committed outcome;
- urgent actions already present at Main admission precede later receipt
  batches;
- each correlated disposition response is observed before render work newly
  released by it;
- no action or correlated response times out behind render traffic;
- no admission-caused receipt lease expiry or worker replacement occurs;
- outstanding render count and oldest age remain bounded;
- receipt admission and Review/File outstanding work drain after quiescence;
- root and all five replies survive full reload.

The previously recorded corrected run remains intermediate failure evidence:

| Observation | Value |
| --- | ---: |
| Maximum main-to-worker receipt queue wait | 2,083.7 ms |
| Prior maximum queue wait | 52,932.7 ms |
| Waits at or above five seconds | 0 |
| Maximum worker handler duration | 28.3 ms |
| Correlated response timeouts | 8 |
| Pending receipt high-water mark | 6,144 |
| Worker replacements | 3 |
| Oldest pending receipt age | 18,518.4 ms |

Lower main-to-worker wait alone cannot pass the duplex workload.

## Alternatives and tradeoffs

### Selected: surface-lifecycle hold until the relevant correlated response

This is the only new ordering rule. It preserves the existing single port,
receipt batches, demand owners, exact attempt identity, and replacement path.
The cost is that a Review position remains busy through its queued response,
while the File selected operation remains busy through painted or terminal
rejection/supersession. A newer File selection therefore waits for the current
File lifecycle to finish. Reviewers pay that cost as bounded progressive
rendering and preserved File lifecycle evidence rather than a flood that
starves their actions or a second File owner that splits admission from paint.

Fresh evidence that the existing Review and File bounds still miss the current
RPC timeout or receipt lease would reopen the rendering budget or envelope
shape. It would not silently authorize another ownership system.

### Rejected: an additional admission ownership system

A separate identity/state machine for published work duplicates the Review
position and File selected-operation lifecycles. Additional global ordering
state solves no requirement once the existing response is posted before the
existing owners resume. Its deletion preserves every U-CWA need and removes
new failure, reset, and synchronization cases.

### Rejected: worker-to-main render batching

The evidence shows too much outstanding work, not excessive envelope cost.
Individual job and patch messages preserve current transfer, identity, and
settlement behavior. Only new envelope-cost evidence may reopen this choice.

### Rejected: visual-clock pacing or chained message tasks

Animation frames can pause in background documents, and 21,806 receipts at a
64-receipt maximum require more than the five-second lease at 60 Hz. Chained
tasks reduced queue wait but still admitted work without downstream settlement.
Neither mechanism owns protocol progress.

### Rejected: additional physical product ports or a global scheduler

More ports do not create worker parallelism and would require new ordering and
lifecycle contracts. A global scheduler would duplicate producer-owned demand
semantics. Current evidence does not justify either expansion.

## Proof architecture

### Unit

- Receipt batching preserves order, duplicate suppression, the 64 maximum,
  one in-flight batch, timeout/probe behavior, capacity containment, and
  disposal/replacement clearing.
- Review fills all three reserved plus nine dynamic positions, publishes them,
  and proves item thirteen waits until a correlated response containing first
  exact queued or terminal rejected/superseded posts.
- Review invalidation while published keeps the position occupied and does not
  revive stale demand after release.
- File publishes selection A, retains selection B as latest intent, keeps A
  current through queued and applied responses, and starts B only after A's
  painted or terminal rejected/superseded response posts and A settles.
- A thrown lifecycle-eligible response post releases no Review position,
  settles no File operation, and requests no drain from the failed command path.
- Telemetry projection exports every required closed count/duration/result and
  rejects prohibited payload and identity fields.

### Actual `MessageChannel` integration

- The worker receives twelve Review publications.
- Main sends an ordered disposition batch through the real channel.
- Main observes the correlated ready or degraded response before publication
  thirteen.
- An urgent annotation action present at Main admission is handled before a
  later receipt batch and its outcome is not starved by render predecessors.
- Injected synchronous response-post failure produces no thirteenth
  publication; existing replacement containment receives the failure.
- File selection B remains waiting behind published selection A through A's
  queued and applied responses; after A's painted or terminal
  rejected/superseded response, Main observes that response before B publishes.

### Browser, development backend, and packaged boundary

- A real 1,699-item Review proves responsiveness, exact root-plus-five-reply
  outcomes, reload durability, bounded outstanding work, no retry
  amplification, and quiescent drain.
- Marker-scoped telemetry proves both FIFO directions and attributes any
  remaining delay to the actual owner.
- The packaged WKWebView proof exercises the same product route, background or
  occluded lifecycle, worker replacement, comment settlement, and telemetry
  marker.

Focused proof precedes the complete BridgeWeb and repository gates. Unit or
fixture evidence is never labeled runtime proof.

## Requirement, design, and proof trace

| Requirement | Structural realization | Observable proof seam |
| --- | --- | --- |
| R-CWA-001, R-CWA-002, R-CWA-004 | One existing product `MessageChannel`; direct urgent actions; producer-owned demand; per-surface receipt admission. | Topology/static checks, semantic-class tests, and runtime worker identity prove no additional port, worker, scheduler, or demand register. |
| R-CWA-003 | Direct action posting, one in-flight receipt batch, and existing Review/File bounds on worker render production. | Actual-channel integration places an action before a later receipt batch and observes its exact outcome without an unbounded reverse backlog. |
| R-CWA-005, R-CWA-006, R-CWA-007 | Ordered batches of at most 64, one in flight per surface, bounded pending state, unknown-debt probe, and existing replacement. | Deterministic admission tests cover order, lifecycle, timeout, overload, clearing, and no replay of mixed unknown delivery. |
| R-CWA-008 | Existing annotation command, product-control, Swift, SQLite, and later projection owners. | Exact committed outcome is observed separately from projection/paint; reload reads durable bodies. |
| R-CWA-009, R-CWA-010 | Existing asynchronous telemetry plus receipt admission and Review/File outstanding-work observations. | Scrubbing tests and fresh marker-scoped baseline/after evidence expose both directions, ages, timeouts, retries, and drain. |
| R-CWA-011 | Existing Vite -> production comm worker -> actual `MessageChannel` -> Swift backend -> real worktree -> SQLite path. | Root and five replies remain responsive and survive reload while product state and telemetry reach quiescence. |
| R-CWA-012 | Stop line retains one port, existing demand owners, individual render messages, and existing recovery. | Diff and runtime evidence prove the correction did not introduce adjacent architecture. |
| R-CWA-013 | The relevant correlated response posts before its owner effect: first exact queued or terminal response before Review release; painted or terminal response before File settlement. Later render work enters the same FIFO afterward. | State tests plus actual-channel integration prove response-before-released-work, File continuity through queued/applied, and bounded predecessor count/age with quiescent drain. |

## Forbidden expansions

- no additional physical product port, worker, scheduler, waiting-job queue, or
  generalized priority framework;
- no new durable or cross-run state, persistence, schema, native interface, or
  trust boundary;
- no render payload batching, UI behavior, animation, security, authentication,
  or authorization work;
- no new timeout, longer receipt lease, polling, blanket debounce, or visual
  clock;
- no weakening of source/currentness fences, exact outcomes, receipt identity,
  ordered transitions, no-silent-drop behavior, or SQLite authority;
- no raw identity, payload, path, comment body, selection, edit token, error,
  capability, or secret in operational evidence.
