# Bridge Reliability Implementation Review — 2026-08-20 (validated)

- Scope: implemented fixes for the Bridge latest-generation-operations correction on branch `bridge-review-design-2026-08-14`, commit range `581d79276..bbaba693c` (13 fix/test commits) plus the uncommitted working tree (current truth).
- Governing basis: ready canonical [implementation plan](../../tmp/plan-workflows/2026-08-19-pr1-bridge-lifecycle-reliability-v5.md) + remediated [specification](../specs/2026-08-18-bridge-latest-generation-operations/2026-08-18-specification.md) + [program design](../specs/2026-08-18-bridge-latest-generation-operations/2026-08-18-program-design.md) (both remediated 2026-08-19) + [design review closure](./2026-08-18-bridge-latest-generation-operations-review-comments.md).
- Method: four independent fresh-context review lanes (native refresh; annotation communication plane; web File/Review/Markdown lifecycle; terminals/queues/custody) + one evidence scout (test inventory, TS unit run, implementer receipts) + parent verification of every finding marked ✅ below against working-tree source. Read-only review; nothing was changed.
- Result: **findings — 1 critical, 7 high, 10 medium, several low.** Convergence machinery landed well and is genuinely tested; **recovery paths and two wire cutovers did not land**, one web-side epoch defect actively breaks render receipts in production, and worker replacement does not re-anchor surviving main-display freshness or replay current surface intent.

## Direct answers to the owner's three questions

**"File view / Review files / Markdown keep loading reliably?" — NOT YET.** Three verified defects each independently produce "loads at first, then stops loading":
- C1 (critical): render receipts are compared against the wrong epoch domain and get rejected as stale after the first couple of user commands — killing the painted-residency re-serve path, so a re-preparation with unchanged identity posts nothing → stuck "Loading file"; on the Review side, receipt leases expire every ~5s → infinite re-render loop for the selected item.
- H2: a File item whose current metadata pass settles without supplying its descriptor has NO failure terminal — indefinite Loading (the F1 blocker was only half-implemented).
- H6: switching File→Review (or backgrounding) while a file load is in flight cancels it AND nulls the request that resume replays — return to File view shows "Loading file" forever until the user re-clicks.

**"Branch switching doesn't get stuck?" — MOSTLY, with two important holes.** Rapid source/comparison changes converge correctly (per-lane authority, dirty-aggregate re-coverage, bounded git-scheduler waits — all verified with tests). But: a failed File pass silently freezes the tree/status with no retry and no unavailable state (M1); and a superseded Review refresh can leave a sticky spurious "unavailable / refreshCancelled" chip that a later successful refresh cannot repair (M2).

**"New generations idempotent, old generations cannot apply?" — LARGELY YES natively, NO on the web receipt path.** Review commits are atomically fenced with no await between fence check and commit; duplicate/late terminals are identity-guarded; dirty merges are idempotent; the F9 authorityGeneration/earliestUnappliedGeneration split is implemented exactly as remediated (all verified). Remaining holes: File-lane emissions never revalidate their fence — an actor-reentrancy interleaving lets an older manifest read overwrite fresher rows (M4); and C1 means valid *current* receipts are wrongly treated as old.

## Was each accepted design finding implemented?

| Design finding | Landed in code? | Evidence |
| --- | --- | --- |
| F1 descriptor-wait operation | **PARTIAL** — operation admitted at selection ✅ (`bridge-comm-worker-runtime-protocol.ts:341-369`), event-driven continuation ✅, but the "metadata settles without usable descriptor → failed/unavailable" terminal is missing (H2), and suspension drops the resume request (H6) |
| F2 stale-fence = stale, not failure | **YES** ✅ — native maps `staleSourceGeneration → stale_source, retryable:false` (`BridgePaneProductSchemeProvider+AnnotationProjection.swift:177-185`); worker excludes `stale_source` from unavailable (`…projection-query-controller.ts:341-343`); successor triggers real on both lanes; direct unit test (`…query-controller.unit.test.ts:70`). BUT the same stale-as-failure shape survives in the native Review refresh path (M2) |
| F4 progressive-File completeness | **PARTIAL** — File publishes progressively, dirty re-coverage on failure/stale ✅, but incremental emissions don't revalidate the fence the PD promises (M4) |
| F6 retryable classification | **PARTIAL** — wire families classified ✅ (`+AnnotationProjection.swift:159-201`), no hopeless auto-retry ✅; but no automatic retry of retryable failures exists anywhere, and the explicit-retry path is dead code with no UI affordance (M5, M1) |
| F7 overflow terminal | **YES** ✅ — both builders now emit `.metadataStreamError(.resyncRequired, retryable:true)` (`BridgePaneProductMetadataCoordinator.swift:493-503, 593-603`); reserved terminal capacity enforced; retained presentation replayed on reopen. Residue: navigation intent not replayed (M6); queueReset still trace-recorded `result: .success` (L1) |
| F8 contract-vocabulary registry | **NO** ✅-verified-absent — `productMemberVocabulary` survives as a hand-maintained flat allowlist (`Models/Transport/BridgeProductStrictJSON.swift`), zero test cross-checks |
| F9 authorityGeneration fence | **YES** ✅ — fence everywhere is the admission-captured authority generation; `dirtyGeneration` never compared as fence (grep-verified by lane) |
| F13 all producers supervised | **PARTIAL** — native annotation producer supervision fixed ✅ (task-terminal settlement, terminal reset frames, observer removal); worker side cannot reopen a dead subscription (H3) |
| R-BLO-011 timestamps | **NO** ✅ — Swift still `createdAt: Date` via default encoder (2001-epoch seconds), while TS accepts an unlabelled finite number. Thread-relative time compensates for Apple-reference seconds, but output-history/candidate consumers treat values as JavaScript milliseconds. The explicit Unix-millisecond contract did not land. |
| R-BLO-013 scoped vocabulary | **NO** — wire is still `snapshot.required(sourceGeneration)` only; no sessionChanged/discoveryChanged/recoveryChanged, no notificationRevision rename. Mitigation: it is not used as a query fence (worker fences on demand generation) |
| R-BLO-014 stage telemetry | **NO** — none of the named stage/terminal events exist (grep-verified by lane) |
| PD snapshot-keyed reservations | **NO** — single mutable `logicalReservation` retained (`BridgePaneProductWorktreeAnnotationProjectionSource.swift:78`); behaviorally masked, but PD cutover step 4 shipped neither half |

## Findings (severity-ordered; ✅ = parent-verified against source)

### C1 — Render dispositions admitted against the wrong epoch domain; production receipts rejected as stale ✅ CRITICAL

- Sender stamps `epoch: receipt.workerDerivationEpoch` — `BridgeWeb/src/core/comm-worker/bridge-pane-runtime.ts:179-186` (verified). Derivation epochs bump only on source re-establishment.
- Admission routes `renderDisposition` into the fileView/review **intent-epoch** domain — `bridge-comm-worker-command-admission.ts:41-42` (verified) — where main increments the epoch on EVERY command (`nextBridgeFileViewerWorkerEpoch`, `bridge-file-viewer-render-snapshot-controller.ts:531-534`, verified) and rejection is `message.epoch < currentEpoch` (`command-admission.ts:60-65`, verified).
- Interleaving: mount → resync epoch 1 → select A → epoch 2 → render job under derivationEpoch 1 → disposition epoch 1 < 2 → rejected "stale epoch". After the first couple of commands, essentially every disposition is rejected. Unit tests mask it by hand-picking intent epochs for dispositions (`comm-runtime-protocol.render-fulfillment.unit.test.ts:38`).
- Consequences: (1) file publications never reach `painted` → painted-residency re-serve dead → re-preparation with unchanged windowKey+epoch posts NOTHING → stuck "Loading file" (windowKey omits path, so rename-of-selected-file is a concrete stuck case); (2) F1's settle for accepted dispositions unreachable; (3) review receipt leases expire (5s) → retry → re-publish → re-render → rejected → **infinite ~5s re-render loop for the selected review item** (R-BLO-006 no-loop violation; plausible jank source).
- Fix direction: admit `renderDisposition` by receipt identity (the fulfillment registry already rejects mismatches safely) or carry the current intent epoch at the sender; convert tests to production-shaped epochs.
- Concepts: exact terminals; correlation; File/Review/Markdown lifecycle; ordering.

### H1 — Worker crash/replacement orphans pending command resolvers → "Saving" forever ✅ HIGH

- `#retireCurrentWorker()` closes the port and terminates the worker with no synthetic terminal — `bridge-pane-comm-worker-session.ts` (verified: clears timeout/port/worker only). The annotation surface client observes only messages, never the RPC lifecycle store (`worktree-annotation-surface-client.ts:152-194`); the RPC 5s timeout only flips a lifecycle store the client doesn't read.
- Scenario: Save → worker crashes before `annotationCommandAccepted` → composer spins "Saving annotation", buttons disabled forever; resolver orphaned. Same for inspect/candidate queries. Violates R-BLO-002/004/012 (R-BLO-012 names "worker replacement" explicitly).
- Fix direction: worker retirement must reject every pending resolver with a correlated failure (or the surface client must subscribe to lifecycle transitions).

### H2 — No terminal when current metadata settles without a descriptor for the selected item — descriptor-wait can load forever ✅ HIGH (two lanes independently)

- Worker file-metadata vocabulary has no "pass settled" fact (`bridge-comm-worker-file-metadata-projection.ts:14-118`); `fileRefreshSettled` only calls `ensureFileSource()` and never audits the selected item (`bridge-comm-worker-runtime-protocol.ts:542-566`). The operation admitted in `preparingDescriptor` terminates only via descriptorReady/invalidated/deletion/selection-change/mode-switch/foreground-loss. If the refresh ends with the row present but no descriptor event, availability stays `loading` indefinitely — the remediated R-BLO-004 explicitly requires failure here.
- Fix direction: a "file metadata pass settled" audit (or native guarantee) that terminates descriptor-wait as non-retryable failure per the R-BLO-006 family table.

### H3 — Annotation subscription death has no reopen owner; a dead subscription can present a ready/current surface ✅ HIGH (two lanes independently)

- `ensureSubscription()` is called exactly once, at runtime install (`bridge-comm-worker-product-controller.ts:160-161`, verified); on failure the catch clears `#subscription` and publishes unavailable — and nothing ever re-subscribes. `retry()`/`retryAnnotationProjection()`/`disposeAnnotationProjections()` have **zero production callers** (verified). The PD's `Unavailable → Opening: explicit/current retry` edge and "Explicit retry and disposal have production owners" are unimplemented.
- Worse: a later `setDemand` still schedules queries; a success publishes `ready` while the subscription stays dead — future SQLite commits (e.g. from a second pane) never invalidate this surface. Exactly the dead-subscription-as-healthy state R-BLO-007 forbids.
- Scenario chain: metadata overflow → stream terminal → poison → annotation subscription fails → later file refresh advances demand → query succeeds → ready → user annotates in pane B → pane A never updates.

### H4 — R-BLO-011 timestamp cutover did not land ✅ HIGH

- Swift: `createdAt: Date` etc. via default JSON encoder = seconds since 2001 (`BridgeProductWorktreeAnnotationProjectionContracts.swift:23` …, encoder in `BridgeProductWorktreeAnnotationProjectionRecordCursor.swift:531-537`). TS: `annotationDateSchema = z.number().finite()` (`bridge-product-worktree-annotation-contracts.ts:10`, verified) consumed as `new Date(n)` = ms since 1970. Zero `…UnixMilliseconds` members in the annotation transport (verified) — the pattern exists in the File lane (`BridgeProductFileDescriptorValueContracts.swift:95`) but not here.
- Consequence: the wire has no explicit unit and consumers disagree. Thread-relative time currently compensates for Apple-reference seconds, while output-history/candidate timestamps can display near 1970.

### H5 — File-surface render-fulfillment lifecycle never driven HIGH

- Lease expiry/ready-retries run only for the review store (`bridge-comm-worker-command-handler.ts:240-273`; wake only via `advanceReviewRenderFulfillmentLifecycle`). The file registry's only reset is a full runtime mutation. A file publication whose receipt is lost holds an active attempt forever; same-identity re-preparations return `duplicate` and post nothing. Removes the file surface's only self-healing and amplifies C1.

### H6 — Suspension nulls the request that resume replays; in-flight selected-file load dropped without terminal HIGH

- Mode switch file→review (`bridge-comm-worker-runtime-protocol.ts:815-819`) and leftForeground (`:552-556`) cancel the operation AND null `latestSelectedFilePreparationRequest`; resume (`:437-445`) replays only that variable. No terminal availability patch is posted; main never re-dispatches select while `selection !== null` (`bridge-file-viewer-app.tsx:299-338`).
- Scenario: select large file → switch to Review before ready → switch back → "Loading file" forever; rescue = re-click. Markdown files park on the placeholder the same way (markdown mode flip depends on `openFileState.status`).
- Fix direction: retain the request across suspension (the review demand scheduler already has the right pause/resume ledger pattern — `bridge-comm-worker-review-demand-scheduling.ts:104-119`) or post a cancelled-family terminal.

### M1 — Failed File pass: no retry, no unavailable, silent freeze ✅ MEDIUM (spec: R-BLO-006 violation)

- On `.failed` both lane loops skip rescheduling (`BridgePaneController+RefreshAdmission.swift:182-184, 219-221`, verified); no retry counter or AppPolicies constant exists (grep-verified). Review at least publishes an attempt `.unavailable(failureKind, retryable)`; the **File** lane publishes nothing — presentation carries only `refreshingLanes` + `reviewComparison`. A failed File pass silently freezes tree/status until an unrelated invalidation.
- Scenario: branch switch → File pass fails → loading clears, tree frozen pre-switch, no affordance.

### M2 — Superseded Review refresh flips a sticky spurious failure terminal ✅ MEDIUM

- Every stale path of the Review refresh routes through `failReviewComparisonRefresh(…, retryable: true)` — stale-classified-as-failure, the F2 shape in a corner the remediation missed. Reachable interleaving: comparison update begins attempt pending(13) → its rebuild is superseded (attempt stays pending) → successor catch-up at 14 cancelled → CancellationError → fail(14) → guard `pending(13) <= 14` PASSES (`BridgePaneRefreshAdmissionCoordinator.swift:225-232`, verified) → attempt flips `.unavailable("refreshCancelled")`, displayed snapshot demoted to stalePredecessor. The eventual successful successor cannot repair it: settle requires `.pending`; the non-pending commit branch keeps the attempt unchanged.
- Outcome: current data displayed alongside a persistent spurious "unavailable" comparison chip until the next comparison update.

### M3 — Gate-closed stale-reschedule busy loop ✅ MEDIUM

- `handleCommittedProductReviewComparisonUpdate` failure paths close `productAdmissionGate` but not the refresh coordinator. Dirty fact + closed gate → reserve → `.stale` (gate acquire nil) → restore dirty → `finalOutcome != .failed` → reschedule (`+RefreshAdmission.swift:182-184`, verified) → repeat forever, each cycle a fresh MainActor task. Only full teardown ends it.
- Fix direction: treat gate-closed as a non-rescheduling terminal, or close the coordinator with the gate.

### M4 — File-lane emissions never revalidate their fence; stale manifest overwrite window MEDIUM

- PD promises "Every incremental File emission revalidates its File operation fence." Implementation's File emissions rely on cooperative `Task.isCancelled` + activity-epoch admission only — `performFileCatchUp` never calls `isRefreshPassCurrent` (`+RefreshAdmission.swift:250-285`); the metadata source has no `checkCancellation` in its publish path; the manifest index is last-writer-wins (`BridgeWorktreeFileManifestIndex.swift:126-143`). Actor reentrancy lets superseded pass A's older disk read overwrite pass B's fresher rows after B completes; nothing re-covers until the next FS event.

### M5 — No automatic retry of retryable failures; explicit retry is dead code with no UI affordance ✅ MEDIUM

- A transient `retryable: true` annotation failure goes straight to unavailable; `retry()` has no callers (verified); the UI renders text-only "Updates unavailable" with no control (`worktree-annotation-composer.tsx:394-396`). R-BLO-006 requires one automatic retry + an explicit retry action. Recovery today needs an unrelated mutation or mode switch.

### M6 — Exact navigation intent discarded on queue overflow instead of replayed MEDIUM

- On `.queueReset`, `publishPaneSurfaceSelectionRequest` discards the retained request (`BridgePaneProductMetadataCoordinator.swift:441-444, 568-573, 607-617`); by the time reconnect replay runs, the intent is gone. R-BLO-008 requires replaying "any still-current exact navigation intent". Mitigated: the caller explicitly invalidates (loss-with-failure, not silent).

### M7 — Stale-await never settled when the successor producer dies MEDIUM

- The F2 design pairs a stale terminal with a guaranteed successor. If that successor's producer dies while the stale attempt awaits it (review metadata failure `bridge-comm-worker-runtime-protocol.ts:693-711`; file metadata failure `:651-682`), nothing settles the annotation store — "Refreshing" indefinitely with no live operation.

### M8 — Wire cutovers not landed: R-BLO-013 scoped vocabulary; PD snapshot-keyed reservations MEDIUM (spec fidelity)

- Wire event still `{eventKind:'snapshot.required', sourceGeneration, worktreeId}` (`bridge-product-worktree-annotation-contracts.ts:209-215`); every mutation is a full snapshotRequired. Native single `logicalReservation` retained rather than the PD's two-slot snapshot-keyed custody. Behaviorally masked today; either implement or amend the PD/spec — currently the artifacts and code disagree.

### M9 — Last-complete presentation hidden or dropped in two web paths MEDIUM

- File panel renders CodeView `invisible` with a "Loading file" overlay for ANY non-ready status (`bridge-file-viewer-code-panel.tsx:377, 425-429`) — last-complete is retained in memory but hidden during refresh, contradicting R-BLO-003 `refreshing(lastComplete)` and the repo's own optimistic-stale policy file. Review: a mid-session metadata failure with no active application replaces the whole presentation with an error page (`bridge-app-review-viewer-mode.tsx:580-582`). Markdown resets to `loading` on any intent change, blanking last-complete during refresh (`bridge-file-markdown-intent.ts:63`).

### M10 — Unbounded orphan maps in the annotation surface client MEDIUM

- `degradedFailureByWorkerRequestId`, `acceptedProductRequestIdByWorkerRequestId`, `outcomesByProductRequestId` accumulate on late/double messages until pane dispose (`worktree-annotation-surface-client.ts:84-133`); R-BLO-012 requires orphan bounds. Memory-only; long-lived-pane + autosave growth pattern.

### Low / notes

- L1: queueReset still trace-recorded `stage: .enqueued, result: .success` for the dropped frame (`BridgePaneProductMetadataCoordinator.swift:514-521`) — any stage evidence filtering on success counts a dropped frame as applied.
- L2: annotation page contract lacks pageCount/totalByteCount ceilings (R-BLO-009 partial; per-page 4MiB cap only).
- L3: `commitReviewPackageLoad`'s authority fence parameter is optional and always-true when nil — make it required (`+ReviewProductPublication.swift:57-61`).
- L4: fire-and-forget `demand.acquire` failure silently drops a session's demand (threads omitted, no indicator) (`worktree-annotation-surface-client.ts:284-319`).
- L5: `waitForSnapshot` waiters hang until dispose if the projection permanently stops converging.
- L6: actor capture race classified retryable-failure instead of stale — transient flash (`WorktreeAnnotationServiceActor.swift:163-167`).
- L7: control mux head-of-line blocking (one slow native control response delays subsequent opens/cancels; bounded, latency-only).
- L8: `fileContentPreparationGenerationByItemId` grows unbounded per distinct item (worktree-size-bounded in practice).
- H7: worker replacement restarts derivation epochs near 1 while main freshness and current intent survive. Replacement neither re-anchors the main display stores to the new worker instance nor replays already-accepted mode/selection/viewport/query intent. Lower-epoch replacement patches are rejected, and current render jobs cannot settle until unrelated derivation resets exceed the predecessor epoch.
- Observation for annotation lane owners: in review full-file items, a sourceRole:'file' thread passes the adapter's path check and renders file-anchored lines against review-head content with no placement re-validation — unreachable if the projection query is truly surface-filtered (commit 5cbc6985d); confirm.

## Verified-GOOD — do not re-litigate

1. **Per-lane authority is real** ✅: independent File/Review generations, active-pass supersession in the same MainActor turn, retiring task maps drained on teardown (`BridgePaneRefreshAdmissionCoordinator.swift:108-115, 246-285`; tests: "File reservation proceeds while a Review-only reservation remains active", "second File invalidation publishes while Review construction remains blocked").
2. **Atomic fenced Review commit** ✅: fence check and commit in one synchronous admission closure, no await between (`+ReviewProductPublication.swift:54-72`); late loads rejected; staged-uncommitted publication released on retire.
3. **F9 exactly as remediated** ✅: authorityGeneration is the only commit fence; earliest-unapplied never compared.
4. **Pre-fix silent dirty drop is GONE**: `.failed`/`.stale` restore the dirty fact (tests at coordinator :475, integration :701).
5. **F2 main path fixed with tests** ✅: stale_source consumed as stale, no retry burned, successor triggers real on both lanes (unit test line 70); 3+ page freeze fixed (test line 152); mixed-snapshot rejected.
6. **F7 overflow core fixed** ✅: both builders emit real terminals; reserved capacity enforced; retained presentation replayed; worker fails closed and reopens the stream on next subscription start.
7. **Normal explicit-disposal settlement is clean in the inspected owners**: Swift pump waiters resume before removal; session revoke asserts zero residue; surface-client dispose rejects registered pendings before clearing; worker queues settle waiters on close/fail. Worker replacement and unmatched late-message maps remain counterexamples to generalized rendezvous cleanliness (H1, M10).
8. **SQLite sole durable authority** with clean restart semantics: one supervised service actor, transaction-then-invalidation, no shadow store, client rebuilds purely from queried truth.
9. **Quadruple-fenced late installs** on the annotation read path (attempt generation, abort signal, snapshot header cross-check, store revision guard).
10. **Anchor isolation**: outdated/unavailable/foreign-surface threads skipped per-thread without poisoning siblings (`worktree-annotation-pierre-adapter.ts:374-379`).
11. **Bounded scheduler waits**: every git read carries a mandatory deadline; capacity timeout surfaces as an explicit failure rather than indefinite Loading.
12. **Viewer switching structure**: both viewers stay mounted (aria-hidden), so the historic blank-on-switch class is structurally fixed (modulo H6's in-flight drop).
13. **Deleted e2e proofs were moved, not dropped** (new `bridge-viewer-vite-annotation-save-journey.ts` + e2e test replace the deleted proof scripts).

## Proof state (scout-verified)

- **Current TS unit suite: 1865 passed / 0 failed (exit 0)** — refreshed with `pnpm --dir BridgeWeb run test:unit` after the inline-shell structural assertion was updated. This does not replace browser, E2E, Swift, packaged, or full-aggregate proof.
- Directly proven by tests: F2 stale-not-failure; 3+ page atomic install; cancellation-ignoring predecessor fenced; rapid generations coalesce (11→15); native overflow terminals (4 Swift tests).
- **Proof gaps (no fitting test found)**: save-during-projection-failure; worker replacement with main-display re-anchoring and current-intent replay; branch-switch lifecycle; descriptor-wait terminal matrix (F1); TS-side overflow reset; R-BLO-014 telemetry (entirely unimplemented, so unprovable). Swift development-server and Vite annotation journeys now cover durable reload/restart, but not worker replacement recovery.
- Not run in this review: Swift suites, browser/e2e lanes, `mise run test` (PR gate) — required before any readiness claim.

## 20-concept scorecard

| # | Concept | State |
| --- | --- | --- |
| 1 | Latest-generation authority | GOOD native ✅ / BROKEN web receipts (C1) |
| 2 | Idempotency & replay safety | GOOD ✅ (duplicate terminals guarded; dedup verified) |
| 3 | Supersession & cancellation | GOOD ✅ with M2 (sticky terminal) + M3 (busy loop) |
| 4 | Exact terminal outcomes | PARTIAL — C1/H1/H2/H6/M1/M7 are all missing-terminal defects |
| 5 | Command receipts vs projections | GOOD ✅ (Save decoupled) except H1 (crash orphan) |
| 6 | Structured typed communication | PARTIAL — correlation strong; H4 timestamps, F8 registry, M8 vocabulary not landed |
| 7 | Request/response vs pushed invalidation | GOOD (compact facts only; no bulk on metadata) |
| 8 | Correlation & traceability | GOOD identity binding ✅ / R-BLO-014 telemetry absent |
| 9 | Durable SQLite authority | GOOD ✅ |
| 10 | Restart & reload recovery | PARTIAL — durable truth and page reload are covered; H1 + H7 leave worker replacement broken |
| 11 | File/Review/Markdown lifecycle | **AT RISK** — C1, H2, H5, H6, M9 |
| 12 | Mixed File/Review sessions | GOOD ✅ (per-thread isolation) |
| 13 | Source anchoring & placement | GOOD (exact/relocated slotted; outdated/unavailable skipped safely) |
| 14 | Last-complete retention | PARTIAL — native GOOD ✅; web hides/drops it in three paths (M9) |
| 15 | Bounded queues/custody/backpressure | GOOD ✅ except M10 orphan maps + M6 intent drop |
| 16 | Failure isolation & retry classification | PARTIAL — classified on wire; no retry engine, dead retry paths (M5, M1) |
| 17 | Branch/source/viewer switching | MOSTLY GOOD — M1/M2 failure-path holes; H6 switch-back drop |
| 18 | Ordering/dedup/atomic install | GOOD ✅ (monotonic revisions; atomic content installs) with M4 File-manifest window |
| 19 | Resource cleanup / zero orphans | GOOD ✅ (idempotent, memoized retirement) except M10/L8 |
| 20 | Test-pyramid & real-runtime proof | INCOMPLETE — 1 red unit test; six named scenario gaps; e2e/browser/Swift not run here |

## Recommended remediation order

1. **C1 + H7** (epoch domains and worker replacement) — fix render-disposition admission, make replacement an explicit main-visible re-anchor boundary, and replay current surface intent. Include production-shaped epochs and old-worker-epoch-2 → replacement-epoch-1 proof.
2. **H1 + H6 + H2** — the three remaining "stuck Loading/Saving forever" owners (worker-crash settlement; suspension resume; descriptor-absent terminal).
3. **H3 + M5 + M7** — the recovery half: subscription reopen owner, wire the retry path + UI affordance, settle stale-awaits on producer death.
4. **H4** — timestamp cutover (small, mechanical, user-visible wrongness today).
5. **M1–M4** — native failure-path holes (File unavailable state + retry policy; sticky comparison terminal; gate-closed loop; File emission fence).
6. Reconcile or implement the deferred cutovers (F8 registry, R-BLO-013 vocabulary, snapshot-keyed reservations, R-BLO-014 telemetry) — either land them or amend the spec/PD so artifacts and code agree.
7. Close the proof gaps (save-during-projection-failure, worker replacement, branch switch, descriptor-wait matrix, restart) and get the full suite green before PR readiness.

## Coverage limits

- Read-only review; Swift suites, browser/e2e, and the `mise run test` PR gate were not executed.
- Native File/Review refresh exactly-one-terminal audited by one lane; worker-health→main reaction path traced only where findings required.
- Worker replacement epoch restart is source-validated as H7; exact runtime frequency and visual severity remain unmeasured.
- This branch remains mid-flight; findings are anchored to HEAD `bbaba693c` plus the inspected working-tree state on 2026-08-20. Current readiness requires fresh proof after the working tree is checkpointed.
