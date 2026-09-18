# WebKit lane flake: "two hosted panes isolate native hidden admission and retain worker state"

Read-only root-cause investigation. No edits, no builds, no test runs.

## Verdict

**(a) TEST defect.** The extra metadata frame is a **protocol lifecycle acknowledgement** that
native is contractually obliged to emit in response to a web-originated subscription control
request. It carries no product data, admits no product work, and is correctly *not* gated on pane
activity. The test's proof counter (`nextMetadataStreamSequence`) is a transport-wide frame counter
that protocol acks advance, so it conflates "the protocol answered the page" with "the hidden pane
did product work". No product invariant is violated.

Confidence: high. The one discriminating observation that could still overturn it is named in
[§7](#7-what-would-discriminate-if-you-want-certainty).

---

## 1. The failure, across all five runs

| Run | Date | before → after | Δ | Test duration | Other issues in run |
| --- | --- | --- | --- | --- | --- |
| 34588581240 | 2026-09-11 | 30 → 31 | **+1** | 7.567s | none |
| 34596792476 | 2026-09-11 | 48 → 49 | **+1** | 8.318s | none |
| 34657945125 | 2026-09-12 | 51 → 52 | **+1** | 7.812s | none |
| 34755706566 | 2026-09-13 | 48 → 49 | **+1** | 8.767s | none |
| 34850913335 | 2026-09-14 | 81 → 82 | **+1** | 12.830s | none |

VERIFIED — logs at
`/private/tmp/claude-501/-Users-shravansunder-Documents-dev-project-dev-agent-studio-issues-perf-again/110176da-fb6d-4805-805f-ba5cd8438bbb/scratchpad/flake-inventory/real/`,
files `34588581240-103228380458.log`, `34596792476-103254312696.log`,
`34657945125-103454281698.log`, `34755706566-103727998220.log`, `34850913335-103998332003.log`.

Two things matter here:

- **The delta is always exactly +1.** Never +2, never +3.
- **The absolute "before" value varies from 30 to 81.** A native-deterministic sequence would not
  swing by 2.7x across runs of the same journey. The counter is dominated by something the *page*
  drives a variable number of times, and the slowest run (12.8s) has the highest count (81) —
  consistent with a slower machine producing more page-driven interest churn during the journey.
  VERIFIED (table above).

In every run the preceding three tests in the suite passed and the following test passed. No
ordering or neighbour correlation. VERIFIED (log greps).

### The decisive line

Run 34850913335 is the only one that carries the diagnostic comment added to the expectation
(`BridgeProductRealGitFileAndReviewWebKitTests.swift:161`):

```
hidden metadata storm: sequence=81->82, control=next:66->67/inFlight:nil->nil,
frames=queued:0->1/inFlight:0->1, pane=+0[], file=+0[], review=+0[]
```

VERIFIED — log `34850913335-103998332003.log`, line 28494.

Decoded against
[`BridgeProductWebKitMetadataStormDiagnostic.swift:21-32`](Tests/AgentStudioTests/App/WebKit/Bridge/TestSupport/BridgeProductWebKitMetadataStormDiagnostic.swift#L21):

| Field | Meaning | Observed |
| --- | --- | --- |
| `sequence` | `producerRegistry.nextMetadataStreamSequence` | +1 → exactly one metadata frame enqueued |
| `control=next` | `controlReplay.nextExpectedRequestSequence` | +1 → exactly one **web-originated control request completed** |
| `control=inFlight` | request currently executing | `nil → nil` → the request both started and finished inside the window |
| `frames=queued/inFlight` | registry queue depth / claimed receipts | `0→1 / 0→1` → **one** frame, claimed by the pump, not yet acknowledged |
| `pane=+0` | new `performance.bridge.swift.pane_presentation` samples | none |
| `file=+0` / `review=+0` | new File/Review metadata bootstrap phases | none |

`queued:1` + `inFlight:1` is **one frame, not two**: a claimed frame stays in `queuedFrames` until
the page acknowledges consumption —
[`BridgeProductProducerRegistryState.swift:186-208`](Sources/AgentStudio/Features/Bridge/Transport/BridgeProductProducerRegistryState.swift#L186)
removes it only in `acknowledgeFrameConsumed`. VERIFIED.

So the window contains: **one inbound control request, one outbound metadata frame, zero product
work.** That pairing is the whole diagnosis.

---

## 2. The test: sampling points and every wait between hide and sample

All line references in
[`BridgeProductWebKitTwoPaneJourneyTestSupport.swift`](Tests/AgentStudioTests/App/WebKit/Bridge/TestSupport/BridgeProductWebKitTwoPaneJourneyTestSupport.swift)
unless stated. VERIFIED by reading the file.

| Step | Line | What it does | Is it a barrier? |
| --- | --- | --- | --- |
| Hide the pane | `:340-341` | `applyBridgePaneActivity(.loadedHidden)`, `await transition?.value` | **Yes** — real task await |
| File retirement boundary | `:342` → `:715-726` | `awaitRetiringFileOperations()` then a `schedulePresentationTransition { _ in }` barrier awaited at `:725` | **Yes** — real awaits |
| DOM status settle | `:343` → `:769-781` | `requireNoUpdatingStatus` polls JS until `fileStatusText == nil && reviewStatusText == nil`, 10s deadline | Poll (see §5) |
| Stale-admission check | `:344-345` | `staleForegroundAdmission?.withValidAdmission { true } == nil` | Synchronous |
| Refresh snapshot **before** | `:346` | `refreshAdmissionCoordinator.diagnosticSnapshot` | — |
| **`hiddenMetadataSequenceBeforeStorm` sampled** | **`:347-348`** | `nativeSnapshot(paneOne)` → `producerRegistry.snapshot().nextMetadataStreamSequence` | — |
| Trace before | `:349` | `paneOneTrace.scrubbedTrace()` | — |
| Comparison count before | `:350-351` | provider actor snapshot | — |
| **The "storm"** | `:353-370` | two `handleWorktreeProductInvalidation(.filesChanged(...))`, batchSeq 702 / 703 | — |
| **`hiddenMetadataSequenceAfterStorm` sampled** | **`:371-373`** | `nativeSnapshot(paneOne)` | — |
| Assertion | `BridgeProductRealGitFileAndReviewWebKitTests.swift:158-162` | `after == before` | — |

Sampling plumbing: `nextMetadataStreamSequence` comes from
[`BridgeProductWebKitCarrierTestSupport.swift:910`](Tests/AgentStudioTests/App/WebKit/Bridge/TestSupport/BridgeProductWebKitCarrierTestSupport.swift#L910)
(`controlReplay.nextExpectedRequestSequence`) and the registry snapshot at
[`BridgeProductProducerRegistry.swift:412`](Sources/AgentStudio/Features/Bridge/Transport/BridgeProductProducerRegistry.swift#L412).

**The gap:** there is **no control-quiescence wait between the hide and the "before" sample.** The
test *does* use one earlier — `requireNativeControlQuiescence` at `:492-495`, right after the JS
`activateReviewMode()` click, precisely because a page click provokes a follow-up control request.
The identical hazard after the hide transition is unguarded. VERIFIED.

---

## 3. What is guaranteed when the hide returns, and what is not

### Synchronous, guaranteed the instant `applyActivity(.loadedHidden)` returns

[`BridgePaneRefreshAdmissionCoordinator.swift:335-349`](Sources/AgentStudio/Features/Bridge/Runtime/BridgePaneRefreshAdmissionCoordinator.swift#L335):

```swift
activity = nextActivity
workAdmissionGate.updateActivity(nextActivity)      // :344
if nextActivity != .foreground {
    restoreActiveReservationToDirtyFact()            // :346
}
```

`updateActivity` (`:789-802`) bumps `foregroundEpoch` under the lock and fires every invalidation
handler. From that moment:

- `acquire(validity:)` returns `nil` — `guard activity == .foreground` at `:753`. **No new
  foreground work can be admitted at all while hidden.** VERIFIED.
- Every outstanding `.foregroundOnly` token fails `isValid` (`:858`). VERIFIED — this is what the
  test's own `staleForegroundAdmissionWasRejected` assertion at `:344-345` proves.
- Active catch-up reservations are dropped back to dirty facts.

### Asynchronous, completed by `await hiddenTransition?.value`

[`BridgePaneController+RefreshAdmission.swift:82-95`](Sources/AgentStudio/Features/Bridge/Runtime/BridgePaneController+RefreshAdmission.swift#L82):

```swift
return worktreeRefreshDriver.schedulePresentationTransition { snapshot in
    if activity == .foreground { ... } else {
        await productSchemeProvider.publishPanePresentation(snapshot)   // :91
        await productSchemeProvider.suspendForegroundWork()             // :92
    }
}
```

So by the time the test's `await` at `:341` returns: the hidden presentation frame has been
**enqueued** (not necessarily delivered or applied), and `suspendForegroundWork`
([`BridgePaneProductMetadataCoordinator.swift:381-401`](Sources/AgentStudio/Features/Bridge/Transport/BridgePaneProductMetadataCoordinator.swift#L381))
has cancelled and drained every producer task and re-queued every subscription into the deferred
sets. VERIFIED.

### What is still unsettled — and has no native handle

1. **The page has not necessarily applied the presentation frame.** Delivery is pump-driven and
   asynchronous.
2. **The page's reaction to it is entirely outside native's knowledge.** When the React app
   re-renders for the hidden presentation (status chrome cleared, refreshing lanes emptied), its
   file/review interest signature can change, and the comm worker then issues a
   `subscriptionUpdateBatch` control request —
   [`bridge-comm-worker-product-controller.ts:664-717`](BridgeWeb/src/core/comm-worker/bridge-comm-worker-product-controller.ts#L664)
   (`#publishFileMetadataInterests` → `#performFileMetadataInterestUpdate` → `subscription.update`).
   Native cannot await a request it does not know is coming. VERIFIED (code read); the specific
   UI cause of the signature change in this journey is UNVERIFIED.

---

## 4. The production path: why exactly one metadata frame, and why it is correct

### 4a. The product-work path correctly refuses

When a `subscriptionUpdateBatch` commits,
[`BridgePaneProductMetadataCoordinator.applySubscriptionInterestsCommitted`](Sources/AgentStudio/Features/Bridge/Transport/BridgePaneProductMetadataCoordinator.swift#L297)
runs:

```swift
guard let foregroundWorkAdmission = refreshWorkAdmissionSource.acquire() else {   // :304
    deferSubscriptionInterestsCommitted(subscription, productAdmission: productAdmission)
    return
}
```

`acquire()` is `.foregroundOnly`; under `.loadedHidden` the gate returns `nil` at `:753`. The
interest update is **deferred**, not executed. No source open, no update, no git read, no
`enqueueSubscriptionData`. VERIFIED.

Product **data** frames are independently impossible while hidden:
[`BridgeProductSession+ProtocolLifecycle.swift:78`](Sources/AgentStudio/Features/Bridge/Transport/BridgeProductSession+ProtocolLifecycle.swift#L78)
wraps `enqueueSubscriptionData` in `foregroundWorkAdmission.withValidAdmission`, which fails for a
`.foregroundOnly` token while hidden. VERIFIED.

### 4b. The protocol path is obliged to answer — and does

[`BridgeProductSession.swift:574-596`](Sources/AgentStudio/Features/Bridge/Transport/BridgeProductSession.swift#L574):

```swift
let committedEffect = try pendingControl.productAdmission.withValidAdmission {
    ...
    if pendingControl.providerDispatchCompletion != nil {
        try admitRequiredProtocolLifecycleFrame(for: transition.effect)   // :584
    }
    try controlReplay.complete(token: token, exactResponseBytes: exactResponseBytes)  // :586
    ...
}
```

Line 584 and line 586 are **in the same critical section**. Line 586 is what advances
`nextExpectedRequestSequence`
([`BridgeProductControlReplayCache.swift:144`](Sources/AgentStudio/Features/Bridge/Transport/BridgeProductControlReplayCache.swift#L144)).
Line 584 dispatches to
[`admitSubscriptionInterestsCommittedFrame`](Sources/AgentStudio/Features/Bridge/Transport/BridgeProductSession+ProtocolLifecycle.swift#L201),
which calls `producerRegistry.enqueueNonterminalFrame` and therefore advances
`nextMetadataStreamSequence` via `commitNextSequence`
([`BridgeProductProducerRegistry.swift:491-507`](Sources/AgentStudio/Features/Bridge/Transport/BridgeProductProducerRegistry.swift#L491)).

**That is the +1/+1 pairing, atomically.**

The only gate on line 584 is `productAdmission` — and `BridgeProductAdmissionContext` is a
teardown/epoch claim, **not** pane activity:
[`BridgeProductAdmissionGate.swift:78-102`](Sources/AgentStudio/Features/Bridge/Transport/BridgeProductAdmissionGate.swift#L78)
checks only `isOpen` and epoch identity. VERIFIED.

This is deliberate and correct. `admitRequiredProtocolLifecycleFrame` is the request/response
protocol's obligation: the page's `subscription.update()` promise settles on that frame. Refusing it
would throw `lifecycleFrameAdmissionFailed`
([`BridgeProductSession+ProtocolLifecycle.swift:279`](Sources/AgentStudio/Features/Bridge/Transport/BridgeProductSession+ProtocolLifecycle.swift#L279))
and strand the worker. Note also that `.productCall` and `.resynced` return early at `:142` — they
advance control only — which is why the observed signature (`control +1` **and** `metadata +1`) pins
the request to `subscriptionOpen` / `subscriptionUpdateBatch` / `subscriptionCancel`.

### 4c. Paths ruled out

| Candidate metadata-frame source | Ruled out because | Status |
| --- | --- | --- |
| Pane-presentation frame from the storm | `advancePresentationRevisionIfNeeded` (`:594-603`) requires activity / refreshing-lanes / fileRefreshFailure to change — none do while hidden with no active lanes. And `recordPanePresentation` (`:609`) emits a `performance.bridge.swift.pane_presentation` sample on **every** publish attempt including skips; diagnostic shows `pane=+0`. | VERIFIED |
| File or Review subscription data | `enqueueSubscriptionData` requires a valid `.foregroundOnly` token (`ProtocolLifecycle.swift:78`); invalid while hidden. Diagnostic shows `file=+0, review=+0`. Provider `comparisonCount` guard at `:375-380` passed. `refreshPassCount` assertion at test `:157` passed. | VERIFIED |
| Review **content** continuation (`.foregroundOrLoadedHidden`, valid while hidden) | Drives a **content producer** with its own lease and `nextContentSequence` — [`BridgePaneProductSchemeProvider+CommittedEffects.swift:220-221`](Sources/AgentStudio/Features/Bridge/Transport/BridgePaneProductSchemeProvider+CommittedEffects.swift#L220). Content frames never touch `nextMetadataStreamSequence` ([`BridgeProductProducerRegistry.swift:504-506`](Sources/AgentStudio/Features/Bridge/Transport/BridgeProductProducerRegistry.swift#L504)). | VERIFIED |
| Annotation projection | Classified `.annotationProjection` → content producer, same as above (`CommittedEffects.swift:216-217`), and gated on `acquire()` which fails while hidden. | VERIFIED |
| `paneSurfaceSelectionRequested` | Nothing in the storm requests a surface selection; also would not pair with `control +1`. | VERIFIED (by absence) |

---

## 5. The interleaving

Actors/executors annotated. Steps 4-7 are the race.

| # | Step | Runs on |
| --- | --- | --- |
| 1 | `applyActivity(.loadedHidden)` — gate flips, epoch bumps, reservations restored | MainActor (lock-backed gate, synchronous) |
| 2 | `schedulePresentationTransition` body: `publishPanePresentation` then `suspendForegroundWork` | `BridgePaneProductMetadataCoordinator` actor |
| 3 | `await hiddenTransition?.value` returns; test does `requireHiddenFileRetirementBoundary` (real awaits) | MainActor |
| 4 | Frame pump delivers the hidden presentation frame to the page | scheme handler task → WebKit |
| 5 | Page applies it; React clears the "Updating files…" chrome. Test's `requireNoUpdatingStatus` (`:769`) observes nil and **returns** | WebKit content process / MainActor poll |
| 6 | Same render pass changes the file/review interest signature; comm worker issues `subscriptionUpdateBatch` | web worker → scheme handler |
| 7 | `BridgeProductSession.swift:584` admits the ack frame (**metadata +1**); `:586` completes the replay (**control +1**) | `BridgeProductSession` actor |
| 8 | Test samples `hiddenNativeBeforeStorm` at `:347-348` | MainActor |
| 9 | Storm: two invalidations — deferred, no work | MainActor |
| 10 | Test samples `hiddenNativeAfterStorm` at `:371-373` | MainActor |

**Pass:** step 7 completes before step 8 → before already includes the ack → delta 0.
**Fail:** step 7 lands between step 8 and step 10 → delta +1.

Step 5 is the trap. `requireNoUpdatingStatus` returns the moment the *DOM text* is nil, which is the
page's **first** render for the hidden presentation. The interest-update control request is dispatched
from the same render but travels a separate asynchronous path (worker → scheme → session actor).
The test unblocks on the visible half of the reaction and samples before the invisible half lands.
That is why this flakes frequently rather than rarely, and why the delta is capped at +1 (one
render pass, one signature change, one deduplicated request — see the signature guard at
`bridge-comm-worker-product-controller.ts:686-689`).

---

## 6. Available barriers, and the ones that don't exist

**Real awaitable barriers already used by this test** (all correct, none sufficient):

- `applyBridgePaneActivity(...)?.value` — `BridgePaneController+RefreshAdmission.swift:86`.
- `worktreeRefreshDriver.awaitRetiringFileOperations()` —
  [`BridgePaneRefreshAdmissionAssertionTestSupport.swift:65-71`](Tests/AgentStudioTests/App/WebKit/Bridge/TestSupport/BridgePaneRefreshAdmissionAssertionTestSupport.swift#L65).
  This one is a genuine await, not a poll.
- `schedulePresentationTransition { _ in }` used as an ordering barrier — TwoPaneJourney `:723-725`.

**A native barrier that exists but is not used here:** producer observation pacing
(`producerObservedSequenceHighWater`, `producerObservationPacingSequenceByWaiterToken`,
`resolveProducerObservationPacingCancellation` — `BridgeProductProducerRegistryState.swift:203`,
`BridgePaneProductMetadataCoordinator.swift:396`). This can prove *"the page has pulled frame N"*.
It would let the test chain deterministically behind delivery of the hidden presentation frame —
but it **still cannot prove the page will not then send a control request.** It closes steps 4-5,
not 6-7.

**The barrier that does not and cannot exist:** there is no native signal for *"the page has no
further control requests pending."* An inbound request is unannounced by construction. Any assertion
shaped as "this transport counter stops moving while hidden" is unprovable without a poll, and a
poll can only ever be wrong in one direction. This is the design fact the test collides with.

**Polling helpers in play and their budgets** (for the record, per the brief):

| Helper | File:line | Budget |
| --- | --- | --- |
| `BridgeProductWebKitCarrierTestSupport.waitUntil` | `BridgeProductWebKitCarrierTestSupport.swift:715-727` | wall-clock `Duration` deadline + `Task.yield()` spin |
| `requireNoUpdatingStatus` | TwoPaneJourney `:769-781` | `.seconds(10)` |
| `requireNativeControlQuiescence` | TwoPaneJourney `:684-700` | `.seconds(10)` |
| `requireHiddenRefreshSettled` | TwoPaneJourney `:702-713` | `.seconds(10)` |
| `requireRefreshIdle` | TwoPaneJourney `:728-737` | `.seconds(20)` |
| `requireReadyReview` | TwoPaneJourney `:649-672` | `.seconds(20)` |
| `waitForRefreshAdmissionQueuedMetadataFrame` | `BridgePaneRefreshAdmissionAssertionTestSupport.swift:24-35` | `maxTurns: 200` `Task.yield()` |
| `waitForStartedComparisonCount` | same file `:37-49` | `maxTurns: 2000` |
| `waitForRetiringReviewRefreshTasksToDrain` | same file `:51-63` | `maxTurns: 2000` |
| `waitForRefreshAdmissionIdle` | same file `:73-86` | `maxTurns: 2000` |
| `waitForActiveReviewRefreshTaskToFinish` | same file `:88-100` | `maxTurns: 2000` |
| `waitForActiveFileRefreshTaskToFinish` | same file `:102-112` | `maxTurns: 2000` |
| `waitForRefreshAdmissionSettledWhileHidden` | same file `:114-131` | `maxTurns: 2000` |
| `waitForRefreshAdmissionRequest...` | `BridgePaneRefreshAdmissionRequestTestSupport.swift:83-87` | `maxTurns` loop |
| teardown residue spin | TwoPaneJourney `:546-548` | fixed 80 `Task.yield()` |

Turn-count budgets are load-dependent, not causal — raising any of them is not a fix and is not
proposed.

---

## 7. What would discriminate, if you want certainty

I have not directly observed *which* control request arrived — CI output carries no per-request
line. The signature (`control +1` ∧ `metadata +1` ∧ `pane/file/review = +0` ∧ exactly one frame in
the queue) is consistent with one protocol lifecycle ack and inconsistent with every product path I
traced. To close it to observation rather than inference, extend the existing diagnostic
(`BridgeProductWebKitMetadataStormDiagnostic.message`) to carry, before and after:

1. `protocolSubscriptionDeliveryById[...].nextSequence` per subscription
   (`BridgeProductSession+ProtocolLifecycle.swift:226` bumps it on the ack), and
2. the metadata coordinator's `deferredUpdateSubscriptionIds` / `deferredOpenSubscriptionIds`
   (`BridgePaneProductMetadataCoordinator.swift:36-37`).

If the failing window shows a subscription's `nextSequence` advancing **and** its id newly present
in a deferred set, the ack diagnosis is observed, not inferred. If instead neither moves, the frame
came from somewhere I ruled out and this becomes a product question.

One honest caveat on `pane=+0`: it proves no presentation publish *only if* pane-presentation
telemetry reaches the test recorder in this configuration. It does —
[`BridgeProductMetadataLifecycleTraceRecorder.swift:506-539`](Sources/AgentStudio/Features/Bridge/Runtime/Telemetry/BridgeProductMetadataLifecycleTraceRecorder.swift#L506)
posts through the same `recorder.record(sample:)` as the review-publication samples that
`requireReadyReview` successfully asserts on earlier in the same run. VERIFIED by construction, not
by a direct sighting of a `pane_presentation` sample in these logs.

---

## 8. Smallest correct fix

### Product: no change

The invariant that should hold — and does — is:

> A pane in `.loadedHidden` admits **no product work**: no foreground work token may be acquired, no
> product source may be opened or updated, no subscription **data** frame may be enqueued. Protocol
> lifecycle acknowledgements are exempt; they are the transport's answer to a request the page
> already made, and withholding one strands the worker.

Enforced at
[`BridgePaneRefreshAdmissionCoordinator.swift:753`](Sources/AgentStudio/Features/Bridge/Runtime/BridgePaneRefreshAdmissionCoordinator.swift#L753)
(acquisition) and
[`BridgeProductSession+ProtocolLifecycle.swift:78`](Sources/AgentStudio/Features/Bridge/Transport/BridgeProductSession+ProtocolLifecycle.swift#L78)
(data emission). Owner: `BridgePaneRefreshWorkAdmissionGate` for admission,
`BridgeProductSession` for frame emission. Both already correct.

### Test: measure product work, not transport frames

Owner: `BridgeProductWebKitTwoPaneJourneyTestSupport` (proof construction) and
`BridgeProductRealGitFileAndReviewWebKitTests` (assertion).

**Change 1 — drop the contaminated counter.**
Remove `hiddenMetadataSequenceBeforeStorm` / `hiddenMetadataSequenceAfterStorm` from
`BridgeProductWebKitTwoPaneJourneyProof` (`:33-34`) and delete the expectation at
`BridgeProductRealGitFileAndReviewWebKitTests.swift:158-162`. `nextMetadataStreamSequence` counts
every frame on the metadata stream, protocol acks included; it cannot express the invariant the test
name claims.

**Change 2 — assert the invariant directly, from facts already captured.**
Both trace snapshots already exist at TwoPaneJourney `:349` and `:374`. Add to the proof the
before/after `fileMetadataPhases.count` and `reviewMetadataPhases.count`, and assert equality.
These are exactly the counters the diagnostic reports as `+0` **even in the failing runs** — they
are the true, uncontaminated measure of "the hidden pane did product work", and they are immune to
web-originated protocol traffic.

The existing companions stay as they are and already carry their weight:
`hiddenRefreshPassCountAfterStorm == ...BeforeStorm` (test `:157`),
`hiddenReviewPublicationCountAfterLateRelease == ...Before` (test `:163`), and the in-journey guard
that provider `comparisonCount` did not move (TwoPaneJourney `:375-380`).

**Change 3 (optional, stronger) — a real product-work frame counter.**
If a frame-level proof is wanted rather than a phase-level one, the right counter does not exist
yet and should be added at the emitting boundary: have `BridgeProductSession` count frames admitted
through `enqueueSubscriptionData` separately from those admitted through
`admitRequiredProtocolLifecycleFrame`, and surface the product count on
`BridgeProductProducerRegistrySnapshot`. The test then asserts the **product** frame count is
unchanged while hidden. Owner: `BridgeProductSession`
(`Sources/AgentStudio/Features/Bridge/Transport/BridgeProductSession+ProtocolLifecycle.swift`).
This is observability only — no behavior change — and it makes the invariant assertable at the
transport layer instead of the telemetry layer. It is strictly more work than Change 2 and is not
required to fix the flake.

**Explicitly not proposed:** no retries, no larger `waitUntil` budgets, no larger turn counts, no
loosened assertion (`<= before + 1` would be a lie — it would silently admit a second real frame).
