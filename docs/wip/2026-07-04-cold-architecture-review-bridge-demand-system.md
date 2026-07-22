# Cold Architecture Review — Bridge Demand System (2026-07-04)

Independent zero-context Fable review of the production pipeline (tests/mocks
excluded by design). Derived from code; spec skimmed only afterward for
divergence notes. Companion to the same-night warm audit (fault lines F1-F3).

## Wedge classes (ranked)

- **W1 — no WebContent-process-termination handling** anywhere in
  Features/Bridge. `isBridgeReady` stays true (BridgePaneController.swift:555),
  push dedup `lastPushed` survives (+PushTransport.swift:38-44), connection
  epoch is 0 forever (:765). Review recovers via re-announce; the push plane
  (diffStatus/acks/viewedFiles/connection) never does. Fix class: page identity
  in the transport — epoch bump on provisional-nav/termination clears dedup,
  resets ready, re-handshakes.
- **W2 — push plane fire-and-forget** while intake retries in-order
  (scheduler :252-265 vs +PushTransport.swift:122-127). One transient JS-eval
  failure permanently loses a control update. Fix: evict slice's lastPushed on
  failure + one re-emit.
- **W3 — announce→reload loop, no breaker + frame-cap asymmetry**: browser
  enforces 1MB (bridge-intake-carrier.ts:74-79); producer has NO byte cap
  (80-item windows, +DiffCommands.swift:5-6, can breach with long paths).
  Persistent oversized/invalid frame ⇒ infinite full-rebuild loop; the 30-retry
  cap never engages because each cycle "succeeds". Fix: producer-side cap
  (split windows) + per-generation reload counter with backoff.
- **W4 — mode-gate suppression is invisible to the wedge detector**: suppressed
  jobs consume WITHOUT sequence use (+ReviewProtocolResources.swift:139-146,
  +WorktreeFileSurface.swift:269-275) ⇒ no gap ⇒ reactivation announce stays
  silent ⇒ silently stale review after review→file→review round-trip under
  churn. Fix: droppedWhileSuppressed bit per protocol; on mode flip, emit
  invalidation/refresh. (Spec recovery contract cannot see this hole.)
- **W5 — closed gate reopens only on browser announcements** (:619, :660);
  256/lane overflow is the only relief. Fix: native reopen probe after N sec
  closed with queued work.
- **W6 — TS executor starves non-foreground; deferred items parked forever**
  (bridge-resource-executor.ts:652-654; visible-review-content-hydration.ts:64
  one retry then retryAfterVersion=MAX_SAFE_INTEGER). Fix: re-arm on
  capacity-available signal. (Abort-path half fixed same night; this is the
  retry-parking half.)

## Load ceilings (5k files / 1M lines / 500 worktrees / 4 panes)

1. Browser main thread first: FULL-PACKAGE zod re-parse per frame
   (bridge-app-review-metadata-package.ts:153,223,269,438) ⇒ ~12.4M cumulative
   item validations for a 5k-file review (quadratic). Delta path: per-item
   `{...itemsById}` spread + `orderedItemIds.includes` (:326-336,:355-364).
   `pruneEmptyReviewTreeDirectories` O(rows²) (:115-128).
2. Swift MainActor second: payload/envelope/JS-literal encodes inline in drain
   (+ReviewProtocolResources.swift:97-106, BridgePaneController.swift:866-872);
   ONE bridgeDeliveryTail for pushes+intake across both planes and all panes.
3. Watch churn eager+duplicated: full read+SHA256 per changed file per pane
   (BridgeWorktreeFileMaterializer.swift:819-866, unbounded file size), re-read
   + re-hash at serve (BridgeWorktreeFileResourceStore.swift:80-113). Demand
   defers delivery, never production.
4. Unbounded within generation: resource store entryByCanonicalURL (:156-163),
   leasesByCanonicalURL (BridgeTransportResourceLeaseRegistry.swift:254).
   Mis-bounded: TS registry 96 entries no byte cap; Swift content cache
   50MB == per-item max (one max item evicts world, AppPolicies.swift:19-20).
   Set-only leaks: preloadDispositionByBodyKey, resetSourceIds.
5. Zero cross-pane sharing: same worktree in 2 panes doubles everything.

## Efficiency wins (ranked)

1. Kill full-package zod re-parse per frame (trust schema-validated frames +
   merge) — O(n²)→O(window).
2. Batch delta merges: one mutable map/frame + Set membership.
3. Defer watch materialization to demand (stat facts + lazy hash; serve-time
   already re-reads) — halves I/O; churn on undisplayed files ~free.
4. One file's journey: ~8 byte copies + 3 full hash passes + 7
   serialize/validate passes. JS-string-literal escape of whole frames
   (BridgePaneController.swift:866) + TextEncoder size-measure pass
   (bridge-intake-carrier.ts:138-140) are pure waste; MessageChannel host-port
   path drops 2 full-frame copies.
5. Interest lane: full visible set re-sent, full windows re-served, no
   served-at-revision filter, no scheduler dedupe key (+ReviewMetadataInterest).
6. Startup speculative windows ship the whole package (~62 frames @5k); cap
   prefill ~5 windows, interest pulls the rest.
7. estimatedBytes=0 for 'selected' — the largest loads invisible to the byte
   budget (review-content-demand-policy.ts:112-114).

## Extra signal

- TS "demand scheduler" is a staging buffer, not a scheduler: every caller
  enqueues+dequeues its own intents synchronously; only cross-caller effect is
  destructive byte-pressure eviction (missing-role mystery failures).
- Intake frames bypass the bridge world entirely (page-world CustomEvent,
  BridgePaneController.swift:849-864); bootstrap intake replay buffer + host
  intake ports are dead code ritual; push nonce is page-world readable.
- Staleness models: review receiver adopts first-seen generation
  (bridge-app-review-intake-receiver.ts:40-43) vs generic receiver's
  higher-generation re-key; Swift worktree plane has THREE manually-synced
  generation authorities. (Feeds ContentIdentity authority work.)
- worktreeFileMetadataScheduler owns the review protocol too — the name lies.
- Review deltas are pseudo-deltas: fabricated fromRevision (max(rev-1,0),
  +DiffCommands.swift:571); browser's strict check silently no-ops on drift
  with no lost-update telemetry.

## Spec divergences

- Retry redelivers already-accepted frames of rolled-back blocks → duplicate
  drops pollute the wedge-signal telemetry.
- Recovery contract assumes gap-detection is always possible; W4 breaks that.
- Reset frames bypass the scheduler (undocumented exception to single-ordering
  authority).
- Spec treats native + TS schedulers as siblings; they are different species.
- Transport contract written as if the browser endpoint is immortal (W1/W2).
