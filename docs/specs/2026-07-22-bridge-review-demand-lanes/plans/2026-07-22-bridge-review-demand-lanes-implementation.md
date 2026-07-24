# Bridge Review Demand Lanes Implementation Plan

Status: accepted after adversarial plan review
Source: `../2026-07-22-bridge-review-demand-lanes.md`
Required worktree: `/Users/shravansunder/Documents/dev/project-dev/agent-studio.bridge-review-demand-lane-completion`
Required branch: `bridge-review-demand-lane-completion`
Planning baseline: `756b87d0f18aadd859ad052e2b49328f1c3b099d`

## Goal

Complete the accepted five-lane Review contract through existing owners, prove
it with observable tests and real Review data, and leave the branch PR-ready.
One persistent native GPT-5.6 Sol medium Sidekick executes the reviewed plan;
the parent owns scope, checkpoints, proof, review, and readiness.

## Scope guard

- Target five production checkpoints plus integrated acceptance within 2–3
  hours.
- Target at most one new Review-specific production module and about 20 touched
  implementation/test files. More than 24 files is a stop-and-reduce signal,
  not permission to hide required correctness.
- Extend the current Review reducer, scheduler, preparation/fetch path, body
  registry, render fulfillment, Pierre adapter, product response admission, and
  native pane admission owners.
- Do not add a generic scheduler, worker, cache, wire type/version, error
  service, native admission scheduler, proof app, global coordinator, adaptive
  policy, batching, persistent traversal, or File View demand-policy change.
- Remove obsolete role-owned caps and role-change cancellation paths in the
  same cutover; no compatibility branch.
- The three older dirty demand artifacts are not implementation authority and
  remain untouched unless separately assigned.

## Current source anchors

- Highest-role projection: `BridgeWeb/src/core/comm-worker/bridge-comm-worker-reconciler.ts`
- Fragmented scheduling owner: `BridgeWeb/src/core/comm-worker/bridge-comm-worker-review-demand-scheduling.ts`
- Current per-pass start policy: `BridgeWeb/src/core/comm-worker/bridge-comm-worker-executor.ts`
- Review preparation/fetch: `bridge-comm-worker-review-preparation.ts`,
  `bridge-comm-worker-review-runtime.ts`, and
  `bridge-worker-review-content-fetch.ts`
- Existing resident-body primitive: `BridgeWeb/src/core/demand/bridge-body-registry.ts`
- Existing render reuse: `bridge-worker-render-fulfillment-registry.ts`
- Existing physical response gate:
  `BridgeWeb/src/core/comm-worker/bridge-product-content-response-admission.ts`
- Real Pierre queue: `BridgeWeb/src/review-viewer/workers/pierre/bridge-pierre-worker-pool.tsx`
- Native continuation owners:
  `BridgePaneRefreshAdmissionCoordinator.swift` and
  `BridgePaneProductSchemeProvider.swift`
- Existing real Vite product fixture and E2E:
  `tests/e2e/bridge-viewer-vite-product-fixture.ts` and
  `tests/e2e/bridge-viewer-vite-product.e2e.test.tsx`
- Existing packaged/current-worktree proof:
  `run-bridge-packaged-product-journey.sh` and
  `verify-bridge-product-paint-correlation.sh`
- Existing capacity/runtime diagnostic surfaces:
  `bridge-product-content-response-admission.ts`,
  `BridgePaneController+IPCProjection.swift`, and the existing journey
  verifiers and their contract tests

## Execution DAG

```text
gate 0: exact worktree/HEAD + focused red witnesses
  │
  ▼
C1 one five-role membership and 12/3/9 active ledger
  │  checkpoint: focused reducer/scheduler green + no obsolete caps/aborts
  ▼
C2 active/body/render reuse + composite diff + typed outcomes
  │  checkpoint: exact opens/bytes/publications and terminal table green
  ▼
C3a real Pierre rank and queued promotion
  │  checkpoint: real file/diff queue behavior green
  ▼
C3b physical 12 + started-response hidden continuation
  │  checkpoint: TS 12/13 admission, focused Swift lifecycle, diagnostics green
  ▼
C4 real-worker ≥100-file browser integration
  │  checkpoint: browser route, scroll, promotion, background, reuse green
  ▼
integration gate: parent diff/scope review
  │
  ▼
full BridgeWeb + Swift + WebKit + lint gates
  │
  ▼
actual-worktree debug proof + packaged 257-diff journey
  │
  ▼
implementation-review-swarm → PR readiness
```

Execution is serial because all checkpoints share preparation identity,
logical-position release, and the same 866-line scheduler. Parallel edits would
create incompatible lifecycle models. Tests stay inside each checkpoint.

## Requirements/proof matrix

| Requirement | Owner checkpoint | Proof modality and layer | Evidence source | Freshness guard | Red/green |
| --- | --- | --- | --- | --- | --- |
| selected > visible > nearby > speculative > background | C1 | exhaustive unit plus scheduler integration | admitted item/role order from existing scheduler seam | current source/generation/order | required |
| real nearby direction and margins | C1/C4 | pure order tests plus forward/backward browser scroll | requested item identities mapped from exact rendered IDs | current ordered Review generation | required |
| twelve active, three interactive-reserved, nine dynamic | C1 | held-fetch integration across repeated reconcile/release | open/start/settlement sequence, not private map shape | exact implementation HEAD | required |
| no role-change cancellation | C1/C2 | held request promoted/demoted before first byte | one request identity, continued first bytes, zero cancel/second response | unchanged preparation identity | required |
| active, resident, and front-end reuse | C2 | unit/integration at all three gates | native opens, second-response bytes, worker-main publications, Pierre tasks | exact body/render identity | required |
| partial diff reuse without mixed sides | C2 | deterministic interleaving integration | base/head request identities and final content hashes | one captured composite identity | required |
| complete lazy background | C1 | add/remove/reorder/retry/eviction integration | full opportunity order and terminal/retry receipts | current generation; higher work quiescent | required |
| distinct typed outcomes | C2 | exhaustive terminal/local-failure table | preserved discriminant/code/retryability/reason and disposition | current transport union | required |
| real file and diff rank plus queued promotion | C3a | actual Pierre request/queue tests | dequeue order and exactly one queued task | current role at materialization/promotion | required |
| physical response maximum twelve | C3b/native | TS admission test plus native WebKit/product evidence | peak 12, thirteenth waiting, zero rejection, named final-zero categories, queue limits, role-separated waits | exact built bundle/HEAD | required |
| hidden continuation without hidden starts | C3b | TS/native held-response and pre-fetch-waiter integration | started response completes; waiter produces zero hidden native opens and resumes from the same logical record; one deferred render | same current identity; pane not closed | required |
| MainActor remains bounded | C3b/native | source and native integration/trace evidence | handler delegation and off-main Git/body/decode work | exact native implementation | required |
| real Review data | C4/acceptance | ≥100-file real-worker Browser integration and actual-worktree packaged app | DOM paint, request/publication counts, scroll and mode switching | fixture digest and current worktree/HEAD | required |
| PR-ready branch | acceptance | full local gates, implementation review, GitHub checks | exact pushed SHA, CI, threads, mergeability | pushed SHA equals tested SHA | required |

## Gate 0 — Re-anchor and red witnesses

1. Verify `pwd`, branch, HEAD, and `git status` from the required worktree.
2. Read the accepted spec, this plan, and the current implementations named in
   the source anchors. Treat concurrent worktree changes as external input.
3. Add the smallest failing observable test for each checkpoint before its
   production edit. Do not add test-only production hooks or wall-clock waits.
4. Keep the old three dirty docs out of staging and implementation decisions.
5. Enumerate the exact expected write manifest before the first code edit. If
   it exceeds 24 implementation/direct-proof files, reduce overlap or split at
   the checkpoint boundary; do not compress unrelated proofs into giant files.
6. Prove the named acceptance surfaces can observe TS active/waiter counts,
   native rejection and lifecycle state, acknowledgements, selected/visible
   logical and physical wait, and final-zero state. The existing verifiers do
   not yet expose all of these; C3b owns the minimal extensions. If this needs a
   new protocol or proof app, reconverge before implementation.

Gate: each red test fails for the contract gap it names, not compilation noise.

## C1 — One five-role membership and active ledger

Behavior:

- Generalize the pure reducer to five roles with exactly one highest role.
- Derive nearby from exact rendered IDs mapped through authoritative order;
  direction controls 2/1, 1/2, or 1/1 margins.
- Replace selected/visible/speculative active collections and per-pass
  `maxStartCount` behavior with one pane-local 12-position ledger.
- Reserved positions admit selected/visible only; dynamic positions use full
  priority order. Role changes update the same active record and signal.
- Keep complete background cursor/outcome/retry state in the Review scheduling
  owner. Add/remove/reorder do not reset terminal progress; eviction never
  rewinds it.
- Remove hover/selection/viewport cancellation. Identity invalidation and real
  teardown remain cancellation causes.

Likely writes:

- `bridge-comm-worker-reconciler.ts`
- `bridge-comm-worker-review-demand-scheduling.ts`
- `bridge-comm-worker-executor.ts` and its existing unit test; delete the
  obsolete executor if the new ledger leaves it with no production consumer,
  otherwise hard-cut it to the ledger contract
- `bridge-content-demand-policy.ts`
- `bridge-comm-worker-store.ts` only if authoritative direction state cannot
  remain scheduler-local
- at most one adjacent `bridge-comm-worker-review-demand-ledger.ts` extraction
- existing reducer/scheduler/executor/runtime-protocol tests

Local proof:

- every trigger/overlap/promotion/demotion;
- tree-only visibility produces no logical opportunity or body open;
- forward, backward, and unknown nearby geometry;
- twelve held logical opportunities, thirteenth wanted, 3/9 reservation eligibility;
- repeated reconciliation and every disposition release exactly once;
- one request/signal through promotion and demotion;
- full background traversal with mutation, retry, and eviction.

Checkpoint: focused tests and BridgeWeb typecheck pass; `rg` confirms obsolete
6/2/1/1 caps, 40-file/25%-cache stops, `maxStartCount`,
`planBridgeCommWorkerDemandExecution`, and demand-driven abort paths no longer
have production consumers. Parent reviews the diff, then commits only this
green slice.

## C2 — Exact browser reuse, composite safety, and typed outcomes

Behavior:

- Compose the existing `BridgeBodyRegistry` pane-locally with accepted 4 MB
  per-body validation and 128 MB total retention.
- The Review scheduling/preparation owner constructs the pane-local generic
  `BridgeBodyRegistry` and derives keys from validated descriptors. The body
  slot is package/source/generation/item/content-role/window; freshness is
  digest/declared-or-whole-length/UTF-8 contract. Descriptor, handle, and
  endpoint IDs authorize acquisition but never define resident bytes. Keep the
  registry domain-generic; edit it only for a demonstrated generic defect.
- Reuse in order: current active preparation, exact resident bodies, then exact
  preparing/painted render fulfillment. Fetch only missing bodies.
- Admit each validated diff side independently, but publish only when every
  side matches one captured composite identity. Retry only missing/retryable
  sides; never combine old and replacement sides.
- Replace generic thrown failures at the Review boundary with the closed local
  result preserving complete/error/reset correlation and typed fields.
- Release one logical position only after all bodies are resident or the
  opportunity reaches retry-wait, terminal, invalidation, or teardown.

Likely writes:

- `bridge-worker-review-content-fetch.ts`
- `bridge-comm-worker-review-preparation.ts`
- `bridge-comm-worker-review-runtime.ts`
- `bridge-body-registry.ts` only for a demonstrated generic defect; Review key
  authority remains in the Review preparation/scheduling boundary
- `bridge-review-content-byte-budget.ts`
- the C1 scheduler/ledger only at its integration seam
- existing fetch/preparation/runtime/body/fulfillment tests

Local proof:

- active hit: one response identity and continued first-delivery bytes;
- resident hit: zero native opens; freshness/eviction: exactly one reopen;
- metadata-only authorization-ID churn with unchanged exact body/freshness:
  zero native opens and zero retransmitted bytes;
- render hit: zero duplicate payloads, publications, and Pierre tasks;
- base completes/head resets: retain base and reopen head only;
- changed head freshness retires the old composite; the new composite may
  reuse an unchanged exact resident base, but publication revalidates both
  sides against the newly captured composite identity;
- forged/stale keys and digest/length/window/binary/UTF-8 failures never reside
  or publish;
- exhaustive typed complete/error/reset/stale/teardown/validation/internal
  outcomes with exact release behavior.

Checkpoint: focused tests and BridgeWeb check pass. Parent verifies no second
cache, protocol, or error service, then commits the green slice.

## C3a — Real Pierre rank and queued promotion

Behavior:

- Carry the active record's current rank into both real Pierre `file` and
  `fileDiff` tasks. Promote an exact queued task in place; equal-rank order stays
  stable and running work is not preempted.

Likely writes:

- `bridge-worker-review-pierre-job-planner.ts`
- `bridge-worker-render-fulfillment-registry.ts`
- `bridge-pierre-worker-pool.tsx` and the existing materialization adapter only
  where the real request shape requires it
- existing render-job, fulfillment, materialization, and real Pierre queue tests

Local proof:

- real file and diff dequeue order for ranks zero through four;
- stable order for equal rank;
- same-key queued promotion updates rank in place with one task and no second
  content open; and
- exact preparing/painted fulfillment creates no second publication or task.

Checkpoint: focused rank/fulfillment tests and BridgeWeb check pass. Parent
reviews and commits this independently provable green slice.

## C3b — Physical twelve and hidden continuation

Behavior:

- Change the existing TypeScript
  `BRIDGE_PRODUCT_MAXIMUM_CONCURRENT_CONTENT_RESPONSES` from 4 to 12 and update
  its admission/transport tests. Do not add a second native admission scheduler.
- Preserve native hard lifecycle residue 16, frame acknowledgement, queue-byte
  limits, and capability checks.
- On Review foreground exit, block new logical opportunities while letting
  Review responses that already reached native continue under their existing
  producer lease. A logical record still waiting at TypeScript physical
  admission has not started `fetch`: pause or withdraw only that waiter, retain
  its logical record and position, and reacquire physical admission on resume.
  It must create zero hidden native opens. Close, revocation, invalidation, and
  integrity failure still retire the record. File View semantics stay unchanged.
- Defer resident render while hidden; resume rederives current facts, performs
  zero refetches, and publishes once.
- Keep WKURLSchemeHandler MainActor callbacks limited to bounded validation,
  registration, and delegation.
- Extend existing-owner diagnostics and IPC/telemetry projection just enough to
  report TS active/waiter counts, native capacity rejection, acknowledgement
  and lifecycle residue, and selected/visible logical and physical wait. Do not
  add a new protocol, diagnostics service, or proof app.

Likely writes:

- `bridge-product-content-response-admission.ts`
- `bridge-product-transport.ts` only at the existing acquire/fetch boundary
- `bridge-comm-worker-pane-presentation.ts` and C1/C2 integration seams
- `BridgePaneRefreshAdmissionCoordinator.swift`
- `BridgePaneProductSchemeProvider.swift`
- `BridgePaneController+IPCProjection.swift` and its existing diagnostics tests
- existing paint/packaged journey verifiers and their contract tests
- existing response-admission, pane-presentation, native admission,
  producer-capacity, lifecycle, and WebKit tests

Local proof:

- twelve held content responses and thirteenth waiting at the existing TS gate;
- zero native capacity rejection; final TS active-response/waiter state, native
  acknowledgements, and lifecycle residue all equal zero after terminal,
  cancel, and close;
- separately measured selected and visible logical wait and physical wait;
- held native Review response survives hidden state; a pre-fetch TS waiter
  produces zero hidden native opens and resumes from the same logical record;
  close/revoke/invalidate before resume produces no later registration and one
  settlement; deferred resident render produces zero refetches and one
  publication;
- unchanged File View foreground admission tests;
- source/trace evidence keeps Git, body assembly, hashing, and decode off
  MainActor.

Checkpoint: focused TS tests, focused Swift fast tests, native WebKit tests, and
red/green verifier-contract tests pass. A deliberately capped packaged run must
fail for missing peak twelve; the exact candidate must reach twelve, observe a
waiting thirteenth, and drain every named category to zero. Parent reviews the
native boundary and commits the green slice.

## C4 — Real Review fixture and browser integration

Extend `tests/e2e/bridge-viewer-vite-product-fixture.ts` and
`tests/e2e/bridge-viewer-vite-product.e2e.test.tsx`; do not create a harness.
The existing disposable Git fixture must contain at least 100 real changed
files with real descriptors and bodies and remain bound to its root, base, and
digest. It must cover:

- selection and same-item promotion;
- sustained forward and backward CodeView scrolling;
- nearby margins and complete background continuation;
- exact open/publication counts and no duplicate front-end payload;
- no blank paint, metadata wedge, or worker failure; and
- File → Review → File/Review switching with resident reuse.

Checkpoint: the focused Vite product E2E reports passed tests with zero skips
under normal Vitest file parallelism, and its evidence proves the real provider,
worker, descriptor/body, Pierre, and painted-DOM route. The existing skipped
Browser witness is not acceptance authority, and the mocked 3,420-file stress
witness and packaged 257-diff fixture remain separate. Parent commits the green
slice.

## Validation commands

Focused commands are refined to exact files by the implementor, from repo root:

```bash
mise run bridge-web-unit-test -- \
  src/core/comm-worker/bridge-comm-worker-reconciler.unit.test.ts \
  src/core/comm-worker/bridge-comm-worker-review-demand-scheduling.unit.test.ts \
  src/core/comm-worker/bridge-worker-review-content-fetch.unit.test.ts \
  src/core/demand/bridge-body-registry.unit.test.ts \
  src/core/comm-worker/bridge-worker-render-fulfillment-registry.unit.test.ts \
  src/core/comm-worker/bridge-worker-pierre-render-job.unit.test.ts \
  src/app/bridge-app-review-render-snapshot-controller.render-fulfillment.unit.test.ts \
  src/review-viewer/workers/pierre/bridge-pierre-worker-pool.rank.unit.test.ts

mise run bridge-web-e2e-test -- \
  tests/e2e/bridge-viewer-vite-product.e2e.test.tsx

mise run test-fast -- --filter \
  'BridgeProductProducerCapacityTests|BridgePaneProductContentActivityAdmissionTests|BridgePaneRefreshAdmissionCoordinatorTests|BridgeProductSchemeAdapterTests|BridgeReviewPipelineTests'

mise run test-webkit -- --filter \
  'WebKitSerializedTests.BridgeProductRealGitFileAndReviewWebKitTests|WebKitSerializedTests.BridgePaneControllerIPCProjectionTests'
```

Required scoped completion gates:

```bash
mise run bridge-web-check
mise run bridge-web-unit-test
mise run bridge-web-integration-test
mise run bridge-web-e2e-test
mise run test-fast
mise run test-webkit
mise run lint
```

Because C3b touches shared Swift transport/lifecycle code, run `mise run test`
before PR-ready status. Do not serialize Vitest or set max workers to one.

## Real-worktree and packaged acceptance

Do not enable `atoms` tracing.

1. Start the shared observability stack.
2. Launch the standard signed per-worktree debug app with IPC escrow and this
   exact worktree as the startup watch folder:

```bash
mise run observability:up
AGENTSTUDIO_IPC_UNSAFE_NO_AUTH=1 \
AGENTSTUDIO_IPC_DEBUG_TOKEN_ESCROW=1 \
AGENTSTUDIO_STARTUP_WATCH_FOLDER="$PWD" \
AGENTSTUDIO_STARTUP_DIAGNOSTIC_ACTION=bridge-product-paint-correlation \
  mise run run-debug-observability -- --detach
mise run verify-bridge-product-paint-correlation
```

3. Extend the existing paint-correlation diagnostic and verifier, plus their
   contract tests, to drive these actions through existing IPC/debug control:
   selection, sustained scroll, promotion, background continuation, and
   Review/File switching. The marker-bound receipt must include exact
   app/PID/HEAD identity, native-open and publication counts, TS active/waiter
   peak and final state, native rejection/acknowledgement/lifecycle state,
   selected and visible logical/physical wait, crash/wedge state, and final
   residue. No manual-only assertion satisfies this gate.
4. Quit the exact debug PID, then use the existing strict LaunchServices
   packaged journey and its 257-diff real Git fixture:

```bash
mise run run-bridge-packaged-product-journey
mise run verify-bridge-packaged-product-journey
```

Acceptance requires a one- and multi-pane observed peak of twelve with a
thirteenth waiting, zero native capacity rejections, native lifecycle residue
at most 16, existing frame/queued-byte bounds, responsive
selection/scroll/mode switching, and no metadata/control wedge or crash. Final
TS active responses and waiters, native acknowledgements, native lifecycle
residue, and scheme/producer tasks must each equal zero. Selected and visible
logical wait and physical wait are reported separately. A run that never
reaches twelve or omits any named category fails.

## Review, commits, and PR readiness

- After each green checkpoint, parent inspects the exact diff and commits only
  that slice. Prefer signed commits while the user is present; if the user is
  AFK, use an unsigned local commit rather than leaving work accumulated.
- Run `implementation-review-swarm` over the full branch diff after all local
  proof passes. Accept only source-backed findings; repair through the owning
  checkpoint without architecture expansion.
- Push the exact tested SHA, update/open the PR, then watch checks only with:

```bash
gh pr checks <pr> --watch --interval 120
```

- Route final GitHub proof through `shravan-dev-workflow:implementation-pr-wrapup`.
  Query `gh pr view <pr> --json headRefOid,mergeable,mergeStateStatus,reviewDecision,statusCheckRollup`
  and query review threads through `gh api graphql`; require the PR head OID to
  equal the locally tested SHA and zero unresolved actionable threads. Report
  check state, mergeability, review decision, tested SHA, and any blocked proof.
  Do not merge without separate authorization.

## Split or reconverge triggers

Stop implementation and return to the parent if:

- any change needs a new generic owner, wire protocol, proof app, File View
  policy, global coordinator, or Pierre modification;
- hidden continuation cannot be bound narrowly to already-admitted Review work
  without making stale foreground authority reusable;
- composite diff identity cannot prevent mixed sides while reusing a valid side;
- the existing Vite product E2E fixture cannot prove ≥100 real changes through
  the real provider/worker/body route without a separate harness;
- physical twelve is rejected by packaged WKWebView, residue exceeds 16, or
  final state does not drain to zero;
- the write set exceeds 24 files or the scheduler cannot remain readable with
  at most one Review-specific extraction; or
- a required proof cannot pass inside its checkpoint. Split at checkpoint
  boundaries; never weaken or delete the proof.

phase_result: complete
evidence: accepted spec, planning lane receipts, focused Vite E2E receipt, and `tmp/plan-review-workflows/2026-07-22-bridge-review-demand-lanes/review-report.md`
recommended_next_workflow: shravan-dev-workflow:implementation-execute-plan
recommended_transition_reason: whole-plan, spec-boundary, and proof re-review found the revised five-checkpoint plan ready for one persistent implementor
