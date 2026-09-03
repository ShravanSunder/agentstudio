# Bridge transport system — implementation review comments

Date: 2026-08-25
Reviewer basis: session-local reads of every cited file; nothing below is asserted
from the handoff alone. Range reviewed: `8c5cbdd43~1..4d1062472` (11 transport
commits, 74 files, +7,674/−1,004). Comm-worker transport files are unchanged from
`4d1062472` to current HEAD (`d4108afc6`) except annotation-contract files, and
`git status` shows no dirty comm-worker files, so working-tree reads equal the
reviewed checkpoint.

Handoff under review:
`tmp/review-handoffs/2026-08-25-agent-studio-bridge-transport-system/implementation-handoff.md`

Method: personal full reads of the admission owner, Review ledger, File operation
controller, fulfillment registry, disposition application, post-response owner
effects, runtime protocol dispatch path, RPC client/lifecycle store, session
replacement wiring, and telemetry files; two sonnet-5 delegates ran the claimed
test lanes and analyzed test coverage (receipts below). Working notes with the
full claim ledger: session scratchpad `transport-review/working-notes.md`.

## Verdict: needs-revision

Review identity: CWA-IMPL-REVIEW-02 (complete implementation review over
`4cc5cb409..4d1062472`, fresh-context Opus complete-reviewer + five toolkit
analysis lanes + two test-verification delegates, all candidates parent-verified
against source in this session). This result also closes the prior coverage gap:
the ten transport commits before `9630378a2` now have a recorded complete
review.

Blockers (must be resolved before the `pr-ready-unmerged` terminal):

1. **F16 — cross-clock receipt-lease guard.** Main-thread and worker
   `performance.now()` are compared directly; any worker replacement in a page
   older than ~5 s makes every first disposition fail the lease and enters an
   unbounded reject/republish loop on the designed recovery path. Route:
   program-design (clock contract) → implement-plan.
2. **F1 — `stalled` has no recovery owner.** Probe timeout pauses dispatch
   "until worker replacement", but nothing requests replacement below the
   6,144 ceiling and late acknowledgements are dropped; recovery is 15-45 min
   (Review) to hours (File), or never for a receipt-quiet worker. F16 breaks
   even that eventual replacement. Route: spec-design (choose the recovery
   owner: probe-timeout-requests-replacement, or late-ack resume) →
   program-design.
3. **CWA-IR2-F01 — the flagship proof harness is not in the repository.** The
   1,699-item journey (900 lines) is untracked; the named runtime gate for
   R-CWA-011 cannot run from the committed tree. Route: implement-plan (commit
   the three e2e files).
4. **CWA-IR2-F02 — the acceptance-layer proof has never passed.** Every
   recorded S5 run fails at a Reply-2 boundary; reload durability, five-reply
   completion, and post-quiescence drain are unobserved; the R-CWA-010
   after-comparison uses partial-run telemetry against a full-load baseline.
   Route: proof (run the committed journey at final HEAD).

Important: F11 (requestId-less degraded events are dead letters; post-commit
scheduling failures — the stuck-placeholder shape — reduce to them), F12
(rejected preparations die as unhandled worker rejections), CWA-IR2-F03 (open,
unclassified live Save failure at 07:40 on the exact obligation surface —
likely product-control/native attribution, must be classified either way), F2
(handoff evidence framing; coverage now closed by this review), G1-G3 test
gaps (stall recovery, replacement resume, lease race).

The structural core is sound and was independently confirmed twice: one
transport route, real response-before-owner-effect ordering, genuine
existing-owner bounds, honest lease/residency separation, clean typing, scrubbed
telemetry, and a net-simplifying diff. The blockers are concentrated in exactly
one place — what happens when delivery degrades — plus the unfinished
acceptance proof. First required revision: commit the journey harness, fix the
clock contract (F16), give the stall a recovery owner (F1), then run the
journey to completion and classify the 07:40 failure.

## What held — verified in code this session

Each row was checked against current source, not the handoff text.

- **Response-before-owner-effect ordering is real.** `renderDisposition` maps to
  no product control (`bridge-comm-worker-runtime-command-routing.ts:110-113`),
  so its ready/degraded response is posted synchronously in the immediate-message
  loop (`bridge-comm-worker-runtime-product-control-dispatch.ts:72`) before
  `applyBridgeCommWorkerPostResponseOwnerEffects` runs
  (`bridge-comm-worker-runtime-protocol.ts:883-912`). A throw while posting skips
  the owner-effect block entirely, and the uncaught listener exception surfaces as
  a worker `error` event that the session converts to replacement
  (`bridge-pane-comm-worker-session.ts:247-248,327-332`).
- **Batching bounds are enforced where claimed.** 64-receipt wire maximum and
  batch>pending guard (`bridge-main-render-disposition-admission.ts:68-80`), one
  unacknowledged batch (`:133-143` — dispatch refuses while `inFlightBatch`
  non-null), 6,144 ceiling = 3 × 2,048 registry entries
  (`BridgeWeb/src/core/demand/bridge-content-demand-policy.ts:43-49`), ceiling →
  close admission → request replacement exactly once
  (`bridge-main-render-disposition-admission.ts:244-253` plus the session's
  `#isRestartRequested` guard, `bridge-pane-comm-worker-session.ts:130-135`).
- **Exact duplicate suppression uses the full identity.** The admission key is
  every identity field plus disposition plus reason
  (`bridge-main-render-disposition-admission.ts:278-296`); keys persist while a
  receipt is pending or in flight and are released at batch settle (`:178`).
- **Timed-out batches are not replayed.** Entries are spliced out at dispatch and
  restored only on a synchronous dispatch throw (`:144-154`); the probe state
  machine matches the spec (`:145-146,183-187` vs
  `docs/specs/2026-08-23-bridge-comm-worker-admission-backpressure/2026-08-23-specification.md:154-163`).
- **Review 3+9 ownership and receipt-gated release are implemented.** Position
  budgets (`bridge-comm-worker-review-demand-ledger.ts:192-199`); a published
  record survives every release path except teardown until its exact
  first-disposition receipt (`:294-297`), and `releasePublished` requires a
  strict 11-field identity match (`:321-344,361-378`).
- **queued ends the delivery lease without fabricating paint.** Lease expiry only
  fires while `highestDisposition === null`
  (`bridge-worker-render-fulfillment-registry.ts:206-210`), and a non-`desired`
  fulfillment refuses republication (`:116-123`) — the 96e255b40 offscreen
  retry-loop fix is present.
- **Per-receipt results gate owner effects.** `accepted | duplicate | rejected`
  per receipt (`bridge-comm-worker-render-disposition-application.ts:32-46`);
  rejected receipts are excluded from Review release and File settlement
  (`bridge-comm-worker-post-response-owner-effects.ts:22`).
- **Source-churn retention/retirement (4d1062472) is implemented as described.**
  Awaiting-first-disposition items are marked `retain`/`retire` and skipped by
  lease expiry (`bridge-worker-render-fulfillment-registry.ts:249-258,280-291,206`),
  the mark is consumed at the exact receipt (`:190-197`), and a replacement File
  source — only a replacement, not first acceptance — cancels the prior selected
  operation and clears its store (`bridge-comm-worker-runtime-protocol.ts:644-651`,
  `hasAcceptedFileSource` flag added in 4d1062472).
- **Replacement lifecycle is fully wired on Main.** Prepare on replacement request
  (`bridge-pane-runtime.ts:376,174-188`), resume on accepted replacement
  bootstrap (`:342-346`).
- **renderDisposition is deliberately exempt from intent-epoch admission** —
  per-receipt identity validation replaces it
  (`bridge-comm-worker-command-admission.ts:54-58`), so the batch-level
  `epoch: receipts[0].workerDerivationEpoch` (`bridge-pane-runtime.ts:255`) is
  informational and mixed-epoch batches are safe. The fixed
  `requestId: 'bridge-main-render-fulfillment'` passed at dispatch is dead
  weight: the RPC client overrides it (`bridge-worker-rpc-client.ts:104-110`).
- **Telemetry scrubbing holds for the new surfaces.**
  `bridge-render-disposition-telemetry.ts` exports only counts, ages, phases,
  outcomes, and a surface label; the Swift allowlist additions are closed
  enumerations sourced from a typed contract
  (`Sources/AgentStudio/Infrastructure/Diagnostics/BridgeTelemetryWireSchema+Allowlists.swift`,
  transport-range diff). Worker-side observation hooks are try/catch fail-open
  (`bridge-comm-worker-review-demand-ledger.ts:115-128`,
  `bridge-comm-worker-selected-file-content-operation.ts:205-219`).
- **The Swift durability test is committed and real.** Root plus five replies,
  ordinal assertion `0..<6`, real runtime restart against the same data root
  (`Tests/AgentStudioBridgeDevelopmentServerTests/BridgeDevelopmentAnnotationDurabilityHTTPRoutingTests.swift:13,47-58,323-327`).

## Findings

### F16 — BLOCKER: the receipt-lease guard compares two different clocks across the worker boundary; worker replacement breaks it outright (credit: toolkit code-review lane; independently re-verified end-to-end this session)

The first-disposition lease guard rejects a receipt when
`receivedAtMilliseconds > receiptLeaseExpiresAtMilliseconds`
(`bridge-worker-render-fulfillment.ts:529-538`, read verbatim). Those numbers
come from different time origins, verified at every production wiring site:

- Lease expiry is computed on the **worker's** relative clock: the worker entry
  passes no clock (`bridge-comm-worker-entry.ts:333-348`), the runtime protocol
  forwards none (`bridge-comm-worker-runtime-protocol.ts:428` — only when
  `props.now` exists, and production never sets it), so the registry defaults to
  worker `performance.now` (`bridge-worker-render-fulfillment-registry.ts:87`),
  and `receiptLeaseExpiresAtMilliseconds = workerNow + 5000` (`:146-152`).
- `receivedAtMilliseconds` is stamped on the **main thread's** relative clock:
  pane-runtime constructs the coordinator with only `sendDisposition`
  (`bridge-pane-runtime.ts:274-275`), so `nowMilliseconds` defaults to main
  `performance.now()` (`bridge-main-render-fulfillment-coordinator.ts:113`),
  used at both stamping sites (`:171,197-205`).

A dedicated worker's `performance.timeOrigin` is its creation time, so the main
clock reads ahead of the worker clock by the page's age at worker creation.
Effective lease budget = 5000 ms − that skew. Consequences:

- Initial workers spawn at page load → skew is small → everything works, which
  is why every green proof lane passed: unit tests inject one consistent fake
  clock, the duplex integration test runs the worker runtime same-thread (same
  time origin), and the S5 browser journey spawns its worker immediately.
- **Any worker replacement in a page older than ~5 s** creates a fresh worker
  whose clock restarts while Main keeps stamping page-age values: every first
  disposition then fails the lease guard, receipts return `rejected`, owner
  effects are skipped, positions stay held, the worker's (correctly intra-clock)
  5 s lease expires and republishes, and the new attempt is rejected again — an
  unbounded reject/republish loop on the exact path that is the designed
  recovery for the stall (F1) and the ceiling. The ceiling then fires again and
  the next replacement inherits a bigger skew. The pre-fix observation of
  "three worker replacements repeated the cycle" is consistent with this shape.
- Compounding: accepted terminal receipts carry main-stamped
  `retryAtMilliseconds` (`coordinator.ts:198-205`) which the registry compares
  against the worker clock (`registry.ts:330-335`), so legitimate retries are
  silently deferred by the skew.

The repo already owns the correct primitive —
`readBridgeCommWorkerAbsoluteNowMilliseconds` (`bridge-comm-worker-telemetry.ts:163-167`,
`timeOrigin + now()`) exists precisely to make cross-boundary timestamps
comparable, and the lease path is the one cross-boundary comparison that does
not use it. Smallest correction: stamp and compute both sides with the absolute
clock (or carry the lease as a duration and let the worker apply its own clock
on receipt). Route: program-design (name the clock contract) → implement-plan.
Confirmation evidence: a registry/protocol test with two offset clocks, plus a
replacement-in-aged-page integration case.


### F1 — The `stalled` delivery state has no recovery owner (important; blocker-candidate for the required workload)

**What happens.** An ordinary batch acknowledgement timeout moves the admission to
`probe_available`; a probe timeout moves it to `stalled`
(`bridge-main-render-disposition-admission.ts:179-187`). In `stalled`,
`dispatchNextBatch` refuses forever (`:136-141`). The design and spec say this
pause lasts "until worker replacement clears the debt"
(`2026-08-23-specification.md:160-163`) — but nothing requests that replacement:

- `requestWorkerReplacement` is invoked only by the 6,144 ceiling
  (`bridge-main-render-disposition-admission.ts:251`) and by session-level worker
  `error`/`messageerror`/bootstrap-timeout
  (`bridge-pane-comm-worker-session.ts:247-248,261-263`). A repo-wide grep finds
  no other caller and no consumer of the `stalled` state outside the admission
  module and its tests.
- An RPC `timed_out` transition never escalates
  (`bridge-worker-rpc-lifecycle-store.ts:195-202` only flips state).
- **Late acknowledgements are dropped.** `settleBridgeWorkerRpcLifecycleFromMessage`
  requires `state === 'pending'` (`bridge-worker-rpc-client.ts:279`). If the
  worker was merely slow and both acks arrive right after the probe timeout, the
  admission still stays `stalled` for the rest of the worker lifetime.

**Concrete failure path.** The batch RPC timeout is 5,000 ms
(`bridge-worker-rpc-client.ts:49`). A worker busy for >~10 s across two
consecutive batch windows — a long diff/preparation task on exactly the large
worktrees this PR targets — permanently stalls settlement for that worker
lifetime even after the worker recovers. Recovery then depends on receipt
inflation reaching the ceiling: each of ≤12 held Review positions lease-expires
every 5 s (lease 5,000 ms, backoff 25 ms,
`bridge-comm-worker-store.ts:240-241`), is restarted
(`bridge-comm-worker-review-demand-scheduling.ts:425` →
`restartPublished`), republished with a new `attemptId`, re-rendered by Main, and
enqueued as ~1-3 new receipts. At ≤36 receipts per 5 s the 6,144 ceiling takes
roughly 15-45 minutes for Review; the File surface has one operation (~3 receipts
per cycle), so its own admission instance needs hours. During that window Review
stops rendering new items, the File selected operation cannot settle, and there is
no user-visible degradation signal — while Main silently re-renders the same
windows every 5 s (bounded, but exactly the churn this work set out to kill).

**Why this is a design gap, not just an implementation bug.** The specification
delegates stall recovery to "existing lease expiry, retry, and worker-replacement
owners" (`2026-08-23-specification.md:162-163`), but none of those owners
observes the stall. The smallest correction is an owner decision, not more
machinery: either (a) a probe-timeout (or N consecutive batch timeouts) requests
the existing worker-replacement lifecycle directly — symmetric with the ceiling
path and consistent with "replacement clears the debt"; or (b) late
acknowledgements for `timed_out` requests are allowed to settle the latch and
resume `ordinary`. Route: spec-design (choose the recovery owner) →
program-design.

Test evidence (delegate-verified, parent-confirmed): no test exercises life
after `stalled` — the only test reaching it ends at the state assertion
(`bridge-main-render-disposition-admission.unit.test.ts:28-37`), and
`resumeAfterWorkerReplacement` is invoked by no test anywhere (two independent
greps; sole production caller `bridge-pane-runtime.ts:344`). The recovery leg of
both the ceiling and the stall is entirely unproven.

### F2 — Recorded independent-review coverage is one commit, not the transport subsystem (important, evidence honesty)

`git log 9630378a2..4d1062472` contains exactly one commit (the source-churn
fix). The handoff's evidence list — "independent complete review of
`9630378a2..4d1062472` with no findings" — is accurate as written, but the same
document concludes "the transport subsystem is implemented, bounded, tested, and
independently accepted," and the copy-paste blurb repeats that framing. The ten
earlier transport commits (`8c5cbdd43..3b5bdb8e2`, including the whole admission
owner, ledger, duplex bounding, and lease/residency correction) have no complete
implementation-review record I could find in the repo: the coordination log
(`docs/wip/communications/2026-08-20-share-comments-backend-ui-coordination-log.md`)
contains no review entry for them, and the plan's S5 stage
(`tmp/plan-workflows/2026-08-23-bridge-comm-worker-admission-backpressure.md:307-321`)
still lists the bounded independent implementation review as a pending gate. A
review may have run in a session that left no repo record; if so, its receipt
should be attached. Until then, "independently accepted" should be scoped to the
one-commit remediation diff. Route: caller (handoff wording / attach the missing
receipt).

### F3 — A matched-identity `rejected` receipt marks a still-wanted item completed; safety currently depends on churn coupling (minor, fragility)

`releasePublished` adds the item to `completedItemIds` whenever intent is still
current — including for `rejected` receipts
(`bridge-comm-worker-review-demand-ledger.ts:338-340`) — and `completedItemIds`
blocks any restart of that item until an invalidate or generation change
(`:173-178`). Main can reject the worker's *current* attempt with
`stale_submission`: when the publication's identity matches neither candidate nor
active presentation (`bridge-main-review-publication-integration.ts:466-468`) or
the item is missing from the catalog (`:326-328`). Today every such rejection is
caused by a presentation/source change that subsequently reaches the worker and
clears `completedItemIds` (`invalidate` `:247`, `updateGeneration` `:287`), so
the item recovers. A second compensation also exists: Main's terminal
`rejected`/`superseded` receipts carry `retryAtMilliseconds`
(`bridge-main-render-fulfillment-coordinator.ts:198-205`), so the worker registry
moves the fulfillment to `retry_wait` and republishes without needing ledger
re-admission (pinned at `comm-runtime-protocol.render-fulfillment.unit.test.ts:316`).
So today the item is not stranded. The trap is latent: the ledger itself cannot
distinguish "completed because delivered" from "completed because rejected"
(`releasePublished` treats all three dispositions identically for
`completedItemIds`), the `rejected` variant of that path has zero test coverage
(no `releasePublished` call with `disposition: 'rejected'` in
`bridge-comm-worker-review-demand-ledger.unit.test.ts`), and a future refactor
routing retries through reconcile would silently deadlock rejected items. Route:
program-design (state the invariant) + implement-plan (pin the ledger contract
with a test).

### F4 — Batch dispatch failure propagates through the lifecycle-store notify loop (minor, robustness)

`observeLifecycle` calls `dispatchNextBatch` inside a lifecycle-store
subscription callback (`bridge-main-render-disposition-admission.ts:202,205-208`);
a synchronous `dispatchBatch` throw (`:148-153`) re-throws through the store's
plain `for (const listener of listeners) listener()` loop
(`bridge-worker-rpc-lifecycle-store.ts:112-114`), skipping the remaining
listeners for that publish and surfacing as an uncaught error in whatever
triggered the transition (including a `setTimeout` timeout callback,
`bridge-worker-rpc-client.ts:118-122`). The receipts themselves are safely
restored (`:151`), so this is contained, but one throwing admission can starve
other subscribers of a lifecycle notification. Route: program-design
(catch-and-report at the subscription boundary), low priority.

### F5 — `supersedeItem` is a dead production API (observation)

`BridgeMainRenderFulfillmentCoordinator.supersedeItem`
(`bridge-main-render-fulfillment-coordinator.ts:81`) has no production caller — a
repo-wide grep finds only tests. Superseded dispositions are produced internally
by `closePendingPublication`. Dead surface on a carefully-bounded contract
invites drift. Route: program-design cleanup or a comment naming its intended
future caller.

### F6 — The flagship acceptance journey exists only as uncommitted working-tree state (observation, disclosed)

The handoff discloses this; recording it because it is load-bearing:
`BridgeWeb/tests/e2e/bridge-viewer-vite-product-fixture.ts` and
`bridge-viewer-vite-product.e2e.test.tsx` are modified and
`bridge-viewer-vite-annotation-backpressure-journey.ts` is untracked
(`git status`). The vertical 1,699-item root-plus-five journey — the proof the
whole narrative leans on — is not yet in any commit. A worktree clean or checkout
loses it. Route: caller (commit the harness before further proof claims cite it).

### F17 — Overload path never runs `clearReceipts` and never emits its `cleared` telemetry (minor; parent-verified)

On ceiling overload, `enqueue` sets `deliveryState = 'closing'` before calling
`requestWorkerReplacement()` (`bridge-main-render-disposition-admission.ts:244-253`);
the replacement flow then calls `prepareForWorkerReplacement`, which
early-returns because the state is already `'closing'` (`:213`). So the receipts
are retained until `resumeAfterWorkerReplacement` (`:259`) and the
`render_disposition_admission_cleared` telemetry is never recorded for exactly
the scenario an operator most needs to reconstruct — the record shows
`overloaded`, then silence. Route: implement-plan.

### F18 — `superseded` batches are reported as `timed_out` in admission telemetry (minor; parent-verified)

The outcome mapping collapses the lifecycle store's distinct `superseded` state
into `'timed_out'` (`bridge-main-render-disposition-admission.ts:180-181`) even
though the delivery-state branch right below distinguishes them (`:184`).
Queries for slow workers will include supersessions. Route: implement-plan.

### F19 — Swift telemetry: contract keys hand-duplicated, and the catch-all contract file crossed the 900-line threshold (minor; parent-verified)

`AgentStudioOTLPPerformanceMetrics.swift:~647-657` hardcodes the
render-disposition/publication attribute keys as string literals instead of
unioning `BridgeRenderDispositionTelemetryContract.numericAttributeKeys` the way
`BridgeTelemetryWireSchema+Allowlists.swift` correctly does — the single-source
contract this range introduced will drift silently. And
`BridgeTelemetryWireSchema+AuxiliaryContracts.swift` is now exactly 933 lines
(past the repo's 900-line refactoring threshold) because the new matchers went
into the generic file rather than a `+Family.swift` extension like every other
contract family. Adjacent, out of range: the `worker.command` allowlist is
missing `'fileRefreshRetry'` (emitted by `bridge-comm-worker-telemetry.ts:44`
since 731e4cfc8), so those task samples are dropped — same defect class,
pre-existing. Route: implement-plan.

### Rejected candidate (recorded for honesty): "a main-rejected item can never re-arm"

A code-review lane claimed the ledger's `completedItemIds` permanently blocks a
rejected item because `markRetryReady` has no waiting token. Rejected with
evidence: the registry parks the fulfillment in `retry_wait`, and when
`releaseReadyRetries` frees it, the released ids are passed as
`forceExecutionItemIds` (`bridge-comm-worker-command-handler.ts:310-316`), and
the forced path calls `invalidate()` (`...scheduling.ts:423-438`) which deletes
the item from `completedItemIds` (`...ledger.ts:247`) before reconcile — the
item is re-admitted. This matches the independent test-analysis receipt. The
residual truth is only F3's latent-refactor framing plus the missing pinning
test (G-series).

### Deliberate-residency context for the lease design (recorded to prevent re-finding)

Two code-review candidates — "a `queued` item can never time out"
(`registry.ts:206-210,302-304`) and "the source-churn `retain` marker disables
lease and wake until its receipt arrives" (`registry.ts:249-258,206,296-299`) —
are true observations of deliberate design (96e255b40's delivery-vs-residency
split and 4d1062472's handoff freeze; the handoff states both). They are not
standalone bugs, but both make worker replacement the sole recovery owner for
their stuck cases, so they inherit F1's missing-replacement-trigger hole and
F16's broken-replacement hole. The nested-conditional at `registry.ts:249-258`
also earns a readability rewrite (the `activeAttempt === null` half of the outer
test falls through to a bare continue via an optional-chain re-test). Route:
program-design context note.

### Suggestions from the code-review lane (each spot-verified)

(a) No schema-level homogeneity check on batch surface — the worker re-derives
it from `receipts[0]` with no refine (`...command-contract.ts:9-18`,
`command-handler.ts:268`); Main's admission does enforce per-surface enqueue, so
this is hardening. (b) The dead `requestId` literal at `bridge-pane-runtime.ts:259`
plus double whole-batch Zod parse (encode then send) and per-receipt re-parse in
the reducer — measurable but unmeasured on a visible-lane path. (c) A stale
positive disposition (late `queued` after `applied`) is a hard batch-degrading
rejection rather than a duplicate no-op (`bridge-worker-render-fulfillment.ts:388-401`).
(d) `sendPositiveDisposition(entry, 'painted')` runs before its own bookkeeping
in the rAF callback (`coordinator.ts:247-255`) — a throw strands the entry at
`applied`. (e) The drain surfaces only the first rejected preparation
(`bridge-comm-worker-preparation-drain.ts:16-19`). (f) Two defensive checks the
types already rule out (`registry.ts:306-307`, `bridge-worker-rpc-client.ts:99-103`).
All route implement-plan, none blocking.

### F7 — Policy comment overstates what the 6,144 counter admits, and the cap silently governs File too (minor, comment accuracy; parent-verified)

`bridge-content-demand-policy.ts:44` says the cap "bounds current-worker receipt
debt to three positive transitions per retained Review item." Verified against
code: the arithmetic (3 × 2,048) holds and the counter is per-worker, but
`enqueue` counts every non-duplicate receipt — terminal `rejected`/`superseded`
receipts included (producer sends them through the same path,
`bridge-main-render-fulfillment-coordinator.ts:164,192` →
`bridge-pane-runtime.ts:275`) — and duplicates count again after their batch
settles (key eviction at `bridge-main-render-disposition-admission.ts:178`).
The same default also sizes the **fileView** admission
(`bridge-pane-runtime.ts:253-262` passes no override), so the "per retained
Review item" rationale silently governs File receipt debt. Smallest fix is a
wording correction. Route: implement-plan.

### F8 — `maximumUnknownDeliveryProbeCount` is a dead constant whose comment claims to govern behavior (minor; parent-verified)

`bridge-content-demand-policy.ts:47-48` — repo-wide grep finds only the
declaration. The one-probe behavior is hard-coded in the admission state machine
(`bridge-main-render-disposition-admission.ts:145-146,183-187`); changing the
constant to 2 changes nothing. Also, per code, `superseded` batches grant a probe
too, not just timeouts (`:184`), and it is one probe per episode (a probe that is
acked/failed returns to `ordinary`; a later timeout grants a fresh probe). Delete
the constant or wire it in; either way fix the comment. Route: implement-plan.

### F9 — Rejection reasons are erased at the batch boundary (suggestion, diagnosability)

The registry's typed rejection reason (window mismatch vs stale attempt vs
foreign context) is dropped when
`applyBridgeWorkerRenderDispositionCommand` flattens results to
`{receipt, status}` (`bridge-comm-worker-render-disposition-application.ts:37`),
so every degraded batch reports one generic message (`:48-54`) regardless of
cause. During an incident this is exactly the boundary where the reason matters.
Smallest fix: carry `reason` on the `rejected` member of the result union.
Route: implement-plan.

### F10 — Stateful owners hold their invariants by discipline where a union would hold them by shape (suggestion, type design)

Parent-verified highlights from the type-design lane: (a) the admission's
`deliveryState` × `inFlightBatch` pair makes
`probe_in_flight && inFlightBatch === null` representable — a state that would
deadlock dispatch (`bridge-main-render-disposition-admission.ts:85-88,137,171`),
and the throw-rollback at `:150-153` is a hand-maintained transition exactly
where this bites; (b) the ledger record's published sub-state
(`publishedReceiptIdentity`/`publishedAtMilliseconds`/`intentCurrent`,
`bridge-comm-worker-review-demand-ledger.ts:69-72`) already costs a dead
defensive branch (`:106-113`); (c) the File operation's public `advance()`
accepts `'preparingRender'` without a receipt identity
(`bridge-comm-worker-selected-file-content-operation.ts:122-129`) — the only
public-API door to an illegal state in the range; (d) the Review position caps
3/9 are inline magic numbers (`...ledger.ts:192-199`) rather than policy
constants beside `bridgeRenderDispositionAdmissionPolicy`; (e) `release()`'s
disposition branching has an untyped fall-through — a future settlement variant
silently means "completed" (`...ledger.ts:303-309`). None is a live bug (each
transition site was traced); all are one refactor from one. Route:
program-design/implement-plan, non-blocking.

### F11 — requestId-less degraded health events are dead letters; post-commit scheduling failures reduce to them (important; parent-verified)

`buildBridgeWorkerRuntimeDegradedHealthEvent()` takes no arguments and carries no
`requestId` (`bridge-comm-worker-runtime-health.ts:30-39`); the RPC lifecycle
settle path skips any message without one (`bridge-worker-rpc-client.ts:277`,
verified), Main's app-level health consumers match on requestId (delegate
anchors: `bridge-app.tsx:967`, `bridge-app-review-worker-health-resolvers.ts:8,41`),
and no telemetry sample is recorded for these events. Every requestId-less
degradation the worker reports — invalid inbound message, annotation-subscription
bootstrap failure, review-metadata post-commit failure — is invisible to both the
user and telemetry.

The sharpest consequence: `runPostCommitEffects` swallows per-effect errors into
`reportReviewMetadataPostCommitFailure` (`bridge-comm-worker-command-handler.ts:246-256,159-165`,
verified — the reporter's own catch is empty and its outbound signal is the dead
letter above). The swallowed effects are exactly the machinery that loads content
after a committed publication (`scheduleDemandExecution` can genuinely throw —
`bridge-comm-worker-review-demand-scheduling.ts:236-239`). Failure shape:
publication committed, display patches shipped, no content preparation scheduled,
item stuck on a placeholder, zero signal — the recurring stuck-Loading bug class
this branch has been fighting. Smallest correction (per the failure-hunter,
endorsed): give requestId-less degraded producers one telemetry sample and/or one
generic Main-side degraded handler — a single seam un-silences all of these.
Route: program-design (name the seam) → implement-plan.

### F12 — Rejected preparation completions die as unhandled worker rejections (important; parent-verified)

`trackedCompletion`'s rejection handler releases the position and **rethrows**
(`bridge-comm-worker-review-demand-scheduling.ts:342-346`); the drain finds the
first rejected completion and rethrows it
(`bridge-comm-worker-preparation-drain.ts:15-21`, verified); the default
scheduler runs the drain as `queueMicrotask(() => { void drain(); })`
(`bridge-comm-worker-runtime-support.ts:23-28`, verified). A rejected promise
voided inside `queueMicrotask` becomes an unhandled rejection in the
WorkerGlobalScope — which does **not** fire the parent `Worker` `error` event, so
the session's `#handleWorkerFailure` never runs, no health event is emitted, and
no telemetry records it. The error classes landing there are invariant violations
(e.g. the `markPublished` mismatch throw, `...scheduling.ts:255-259`) — exactly
the bugs that should surface loudly. Smallest correction: catch in the drain
scheduler and emit a degraded health event / telemetry sample (which then also
needs F11's consumer seam). Route: implement-plan.

### F13 — Telemetry containment is inconsistent with the stated fail-open rule (minor; parent-verified)

The three observation hooks added in this range are try/catch-contained
(`...ledger.ts:115-128`, `...file-content-operation.ts:205-219`,
`bridge-render-disposition-telemetry.ts:71`), but the recorders on the hot paths
are not: `recordBridgeCommWorkerTaskTelemetry` runs bare at the end of every
worker message turn (`bridge-comm-worker-runtime-protocol.ts:~849`) and the
production producer's `record()` has no internal containment
(`bridge-telemetry-worker-event-adapter.ts:38-43`, verified — encoding +
`postMessage` both uncontained). A throwing recorder inside the worker message
listener escapes → parent `error` event → full worker replacement: telemetry can
kill the worker. Throw likelihood is low (samples are constructed plain objects),
but the rule inversion is real. Route: implement-plan (wrap the recorder seam).

### F14 — Assorted verified silent-failure notes (minor/observation)

Delegate-reported, spot-verified where load-bearing: (a) session dispatcher
`dropped_detached` discards silently and its diagnostic tracker covers only three
command kinds — a dropped `renderDisposition` leaves no trace
(`bridge-pane-comm-worker-session.ts:157-169,355-369`); `#queuedCommands` is
unbounded. (b) A degraded batch outcome is telemetry-visible but never reaches
the user; recovery is bounded via lease-expiry restart — acceptable, worth
knowing. (c) `fileQueryOutcome` is dropped at the session wire and its command
returns no ready ack, so any future `fileQueryUpdate` caller settles only by 5s
timeout; the outcome kind would hit `unreachableBridgeWorkerValue` if it ever got
through (latent, no production sender today). (d) One-item invariant throws in
timer callbacks (retry wake, fulfillment wake) cost total worker state via
replacement with no telemetry naming the item. Routes: implement-plan, none
blocking.

### F15 — Two failure vocabularies under one telemetry attribute key in the same new file (minor; parent-verified; credit: /code-review fork finder-c)

Within `bridge-render-disposition-telemetry.ts` (new in this range), the same
attribute `agentstudio.bridge.result` carries `'failure'` from the
outstanding-publication recorder (`:51-53`) and `'failed'` from the admission and
batch recorders (`:98,144,161-162`). A marker-scoped proof query filtering on one
value silently misses the other lane's failures — the proof instrument lies
about lane health. Smallest fix: one vocabulary. Route: implement-plan.

### X1 — Cross-reference (fork-owned, partially verified here): review publication epoch registry is not reset on worker replacement

A `/code-review` fork finder claims the replacement worker's re-exposed
publications get rejected against a stale `publicationEpochById`, freezing
review content/paint after replacement
(`bridge-main-review-publication-integration.ts:398`). Verified by me this
session: the only `publicationEpochById.clear()` is in the dispose path
(`:375`), `start()` subscribes worker replacement solely to
`installationGate.prepareForWorkerReplacement` (`:499-501`), and the monotonic
guard exists (`:397-399`). NOT verified by me: whether the integration instance
survives replacement, and the new worker's epoch numbering. This file is outside
the transport range, but the claim **interacts with F1**: worker replacement is
the transport's only stall/ceiling recovery — if replacement itself leaves the
review pane frozen, the recovery story degrades further. The fork's verification
pass should settle it; if confirmed, it inherits F1's severity context.

## Cross-reference: /code-review fork verified findings (2026-08-25)

The user's independent `/code-review` pipeline (10 capped findings from 17
confirmed) intersects this review in three places, verified against my own
session reads:

- **Corroborates F1 (third independent pipeline):** its finding at
  `bridge-worker-render-fulfillment-registry.ts:207` — churn-marked entries
  excluded from lease expiry and wake, timed-out batch receipts never requeued,
  `stalled` never triggering replacement — is the same defect chain as F1.
- **Extends the F1 family (sharpest wedge variant):** at
  `bridge-comm-worker-post-response-owner-effects.ts:22`, an *intent-stale*
  published record whose lease expires before its receipt arrives gets a
  registry-`rejected` late receipt, which skips ledger release; `restartPublished`
  refuses stale intent (`ledger.ts:350`), `invalidate`'s published branch only
  flips `intentCurrent`, so the position leaks until worker replacement.
  Consistent with my reading of all four release paths.
- **Corrects an earlier dismissal of mine:** `invalidate()`'s published branch
  (`ledger.ts:231-237`) returns before the `preserveIfPreparationIdentity`
  check (`:238-241`) ever runs — I had noted this ordering and judged it fine;
  the fork's consequence analysis is right that a benign same-identity metadata
  re-touch marks correct in-flight render work intent-stale, forcing a
  re-render of unchanged content (the churn class this branch exists to kill)
  and making the record wedge-eligible under the late-receipt path. Recorded
  here as **F20 (important)**; route: program-design (order the preserve check
  before the published branch, or preserve intent on identity match) →
  implement-plan. No test covers the preserve option against a published
  record.

The fork's remaining findings (single-slot install-admission latch,
failure-register restart block, never-called `retryInstalledReceipt`,
started-but-never-terminal candidate, Swift delta lineage gate, artifact-pin
leak, composer focus steal) target the RRC/coordinator/UI layers outside this
review's range — dispositioned in the fork's own report.

## Complete-reviewer receipt (CWA-IMPL-REVIEW-02, parent-verified)

The fresh-context complete reviewer returned `complete` with full obligation
coverage (R-CWA-001..013, V-CWA-001..007): ten obligations covered with fitting
proof; R-CWA-008 contradicted at runtime (open 07:40 failure), R-CWA-010
ambiguous (partial-run after-telemetry vs full-load baseline), R-CWA-011
missing (harness untracked, never passed), V-CWA-007 partial (aggregate/
packaged/current-head lanes unrun). Runtime reachability: **live** — every hop
wired by default, prototype batcher deleted, hard cutover with no second path.
Riskiest assumption (existing owners bound the reverse FIFO at 1,699 items):
material-risk-remains — structurally verified in source, encouraging partial
telemetry (outstanding HWM 7-9 vs bound 12, ages <2 ms, pending 0), but no
completed run observes the load-bearing "bounded AND drains after quiescence"
clause. Its four candidates were parent-verified: F01/F02/F03 accepted (see
verdict), F04 accepted and merged into F13 (the main-side admission telemetry
record at `bridge-render-disposition-telemetry.ts:89` is also uncontained;
traced latent — no throw site on the current production recorder chain).
Additional accepted observations: `restartPublished` is a seventh
Review-position transition absent from the Program Design's state table; a
replacement bootstrap that never installs leaves admissions permanently
`closing` with silent receipt discard (untested); the supplied diff range
contains four concurrent annotation-lane commits (including two files the plan
named as untouched concurrent-owner files) — excluded from this authority,
reviewable separately.

## Test evidence (delegate receipts, parent-verified)

**Claimed lane counts reproduce.** A sonnet-5 operator re-ran both lanes from
this worktree: `pnpm run -C BridgeWeb test:unit src/core/comm-worker` → 147
files, **953/953 passed, exit 0** (run twice, identical); the duplex
MessageChannel integration file via
`test:integration:node:prepared src/core/comm-worker/bridge-comm-worker-duplex-backpressure.integration.test.ts`
→ **3/3 passed, exit 0**. (Caveat: the operator used the `:prepared` script,
skipping the Swift dev-server build the full `test:integration:node` script
performs; the file has no Swift dependency, so the vitest result is equivalent.)

**What the ordering proofs actually prove** (sonnet-5 analyst, receipts spot-
verified by me):

- Urgent-before-settlement and response-before-publication-13 are genuine
  same-port FIFO proofs over a real `new MessageChannel()` with one collector
  indexing arrivals (`bridge-comm-worker-duplex-backpressure.integration.test.ts:145-278`,
  assertions at `:272-274`); File painted-response-before-B likewise
  (`:280-399`, assertion `:396`). These are single-shot ordering proofs, not
  fairness proofs under sustained load — one urgent action against one in-flight
  receipt.
- The ledger's `render_disposition_response_posted_before_owner_effect` phase in
  `bridge-comm-worker-review-demand-ledger.unit.test.ts:37-112` is **inferred
  from internal callback order**, not port order — the real-port proof of that
  invariant lives only in the duplex test.
- 13-behind-12 is proven at ledger level (`...ledger.unit.test.ts:114-141`) and
  cross-validated over the real channel (duplex `:187-191,255-258`). No test
  pins the reserved/dynamic caps against adversarial membership (e.g. 5 visible
  items), only the 3-visible/10-background construction.
- The 64-batch maximum is proven with the real constant (duplex `:54-143`,
  batches `[1, 64, 1]`); the 6,144 ceiling is proven only as a mechanism at
  `maximumPendingReceiptCount: 3`
  (`bridge-main-render-disposition-admission.unit.test.ts:50-68`) — the real
  threshold never runs under test (acceptable, but the number itself is
  arithmetic, not observation).

**Critical coverage gaps (verified against the suites):**

- **G1 — nothing tests life after `stalled`** (ties to F1): no late-ack test, no
  stalled→ceiling→replacement test, no consumer of the state outside the module.
- **G2 — `resumeAfterWorkerReplacement` untested**: the recovery leg for both
  ceiling overflow and stall has zero coverage — post-replacement return to
  `ordinary`, lifecycle re-subscription, and first new-worker dispatch are all
  unpinned. If resume silently broke, every overload event would permanently
  kill disposition delivery for the pane.
- **G3 — the 5s-lease race is untested**: no test delivers a late old-attempt
  receipt after lease expiry + retry republication. Production would route it
  through the conflicting-terminal branch to a `rejected` result and a degraded
  batch (`bridge-worker-render-fulfillment.ts` rejection error →
  `bridge-worker-render-fulfillment-registry.ts:174-186`); any non-RejectionError
  leaking on that path rethrows and kills the worker message loop (`:177-179`).
  This race is coupled to the feature's own degraded mode (admission holds
  receipts beyond 5s exactly when batches time out).
- **G4 — duplicate receipts never touch a real registry**: the mixed
  accepted/duplicate/rejected application test mocks `applyDisposition`
  (`bridge-comm-worker-render-disposition-application.unit.test.ts:11`); exact
  re-delivery across batches is reachable in production (admission evicts keys
  at batch settle, `bridge-main-render-disposition-admission.ts:178`) and no
  test pins that a re-delivered `queued` cannot double-release a position.
- **G5 — `restartPublished` (the lease-expiry restart of a published Review
  position, sole production caller
  `bridge-comm-worker-review-demand-scheduling.ts:425`) is invoked by zero
  tests** — I verified both the caller and the absence by grep.
- **G6 — the `probe_in_flight` dispatch guard
  (`bridge-main-render-disposition-admission.ts:137`) is unexercised**; no test
  enqueues during a probe, and no test asserts probe batch *contents* (so
  replay-vs-drop of timed-out receipts is pinned by code reading only).

**Suite quality:** dense and real-seamed on ordinary lifecycle and single-fault
scenarios (real state machines, real stores, real preparation pump, one genuine
MessageChannel test; the uncommitted 1,699-item journey asserts telemetry
oracles, not DOM text). Thin exactly where two degradation mechanisms interact —
stall recovery, replacement resume, lease-vs-late-delivery — the corner this
machinery exists for.
