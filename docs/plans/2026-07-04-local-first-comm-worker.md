# Local-First Comm Worker Implementation Plan

Date: 2026-07-04
goal_id: 2026-07-04-bridge-scroll-demand-queue
source_spec: `docs/specs/bridge-viewer-transport/local-first-comm-worker-architecture.md`
source_commit: `4c899983`

> For agentic workers: REQUIRED SUB-SKILL: Use
> `superpowers:subagent-driven-development` or `superpowers:executing-plans`
> task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. Before any
> implementation, validate this plan against the current repo, then preserve
> red/green evidence per slice.

## Goal

Operationalize R41-R48 by moving BridgeViewer toward a local-first split:
the FE owns only synchronous render slices and frame-budgeted DOM apply, the
comm worker owns protocol/cache/demand/telemetry truth, and Swift remains the
metadata/content server. This increment is intentionally split into multiple
PR-sized cutover units because the spec requires compile-enforced deletion per
viewer/protocol surface, not one broad dual-path migration.

## Architecture

The first PRs remove current interaction choke points while preserving the
existing server contract: telemetry leaves the interactive RPC lane, Pierre
scroll work is coalesced/deferred, FE subscriptions become O(selected + visible
delta), DOM apply becomes a selected-first pump, and File View gets the same
frame contract. Only after the native WKWebView worker-fetch gate passes does
the plan cut protocol/cache/queue/telemetry ownership into the comm worker.

## Tech Stack

- BridgeWeb React + TypeScript + Zustand + Vitest/browser Vitest.
- Pierre/Shiki workers under `BridgeWeb/src/review-viewer/workers/`.
- Swift 6 `Testing`, WebKit `WKURLSchemeHandler`, AgentStudio telemetry
  validator/ingestor, and debug observability/Victoria proof.

## Source Coverage

- `docs/specs/bridge-viewer-transport/local-first-comm-worker-architecture.md`
  read in full: 482 lines, R41-R48 and migration constraints, committed at
  `4c899983`.
- `docs/plans/2026-07-04-unified-content-demand-queue.md` read in full: 688
  lines, used for Gate 0 shape, slice proof shape, deletion checklist, matrix,
  live gates, and contradiction handling.
- `tmp/debug-workflows/2026-07-04-agent-studio-luna338-scroll-placeholder-survivor/debug-investigation.md`
  PHASE 2 and PHASE 2b read: lines 156-232, used for verified defect anchors.
- `docs/specs/bridge-viewer-transport/performance-demand-lanes.md` Constants
  Annex read: lines 307-345, used for policy-class/cap discipline.

Planning-lane note: no subagents were spawned because the available subagent
tool requires explicit delegation permission. Lane analysis is embedded here.
Reasoning-effort policy for execution lanes: use high effort for A, C, F, and
G because they cross transport/protocol/proof boundaries; use high effort for
B/D/E when browser scroll proof or File View parity touches large files; use
medium effort only for narrow test-only or source-scan closeout tasks.

Security context: applicable, bounded. This plan touches WebKit custom scheme
routes, telemetry ingestion, worker/server protocols, byte caches, and content
fetching. New telemetry must not export raw paths, raw URLs, payload text,
prompts, tokens, raw errors, or raw content. New scheme routes must validate
method, path, byte count, content type, and admission before decode or expensive
work.

## Execution DAG

```text
gate 0: re-anchor repo, source docs, current line counts, and command surfaces
  |
PR 1 / slice A: telemetry channel divorce and native admission cleanup
  |
PR 2 / slice B: Pierre scroll cures and browser scroll proof
  |
PR 3 / slice C: FE render-store slicing and O(selected + visible delta) proof
  |
PR 4 / slice D: frame-budgeted main-thread apply pump
  |
PR 5 / slice E: File View parity, chunked frame/projection, O(N^2) prune fix
  |
PR 6 / slice F: native WKWebView worker-fetch proof gate
  |
PR 7+ / slice G: comm-worker cutover units, one viewer/protocol surface at a time
  |
full live gates: both smokes, momentum probe, VictoriaMetrics improvement,
user UX confirmation, plan-review/implementation-review before merge
```

Parallelization is intentionally limited. A can run before B because it removes
transport contention shared by all later performance proof. B, C, and D must
serialize around Review render/apply surfaces. E can branch after D's pump
policy is stable but must merge before full live proof. F is blocking for G.
G is multiple compile-enforced PRs, one cutover unit at a time.

## Gate 0 - Planning Re-Anchor

Objective:

Reconfirm this plan's assumptions before any implementation branch starts. This
gate is read-only except for normal test/build artifacts produced by commands.

Required checks:

```bash
git status --short
git show --stat --oneline --decorate=short 4c899983 -- docs/specs/bridge-viewer-transport/local-first-comm-worker-architecture.md
wc -l docs/specs/bridge-viewer-transport/local-first-comm-worker-architecture.md docs/plans/2026-07-04-unified-content-demand-queue.md tmp/debug-workflows/2026-07-04-agent-studio-luna338-scroll-placeholder-survivor/debug-investigation.md docs/specs/bridge-viewer-transport/performance-demand-lanes.md
wc -l BridgeWeb/src/review-viewer/content/visible-review-content-hydration.ts BridgeWeb/src/review-viewer/trees/bridge-trees-panel.tsx BridgeWeb/src/file-viewer/bridge-file-viewer-state.ts Sources/AgentStudio/Features/Bridge/Transport/RPCRouter.swift
```

Expected current anchors:

- `git status --short` is clean or every dirty path has a named owner before
  execution starts.
- `4c899983` is the current local source for the comm-worker spec.
- `visible-review-content-hydration.ts` is 985 lines. The first slice that
  touches it owns split/dissolution work; do not grow it past the cap.
- `bridge-trees-panel.tsx` lives at
  `BridgeWeb/src/review-viewer/trees/bridge-trees-panel.tsx`, not directly
  under `review-viewer/`.
- `RPCRouter.swift` remains the current telemetry RPC intake path until A.

Stop conditions:

- Any source file named above has drifted enough that its defect anchor no
  longer exists.
- The worker-fetch proof from F already exists and contradicts this sequence.
- A test/lint/build failure outside the agreed slice appears; report it instead
  of editing harnesses, lint config, CI, or observability infrastructure.

## PR Boundary Proposal

1. PR 1: `bridge-telemetry-scheme-transport` implements A only.
2. PR 2: `bridge-review-pierre-scroll-cures` implements B only.
3. PR 3: `bridge-review-render-store-slicing` implements C only.
4. PR 4: `bridge-review-apply-pump` implements D only.
5. PR 5: `bridge-file-view-frame-parity` implements E only.
6. PR 6: `bridge-worker-fetch-proof-gate` implements F only; if it fails,
   record the fallback/redesign decision and stop before G.
7. PR 7a: `bridge-comm-worker-protocol-core` starts G with protocol truth,
   cache, queue/executor, telemetry worker shell, and no viewer cutover.
8. PR 7b: `bridge-comm-worker-review-cutover` converts Review content protocol.
9. PR 7c: `bridge-comm-worker-file-view-cutover` converts File View content
   protocol.
10. PR 7d: `bridge-comm-worker-cleanup-live-proof` deletes remaining old
    protocol/demand/telemetry state and runs full live gates.

## Slice A - Telemetry Channel Divorce

Objective:

Move telemetry off interactive RPC and onto a dedicated `WKURLSchemeHandler`
POST endpoint. Remove force-flush from `sendCommand`, add browser encoded-byte
cap and drop-oldest aggregate counters, enforce monotonic batch sequence
integrity, and make native telemetry decode/admission single-pass and
admission-first.

Files touched:

- `BridgeWeb/src/bridge/bridge-rpc-client.ts`
- `BridgeWeb/src/bridge/bridge-rpc-client.unit.test.ts`
- `BridgeWeb/src/bridge/bridge-telemetry-event-sink.ts`
- `BridgeWeb/src/bridge/bridge-telemetry-event-sink.unit.test.ts`
- `BridgeWeb/src/foundation/telemetry/bridge-telemetry-buffer.ts`
- `BridgeWeb/src/foundation/telemetry/bridge-telemetry-buffer.unit.test.ts`
- `BridgeWeb/src/foundation/telemetry/bridge-telemetry-recorder.ts`
- `BridgeWeb/src/foundation/telemetry/bridge-telemetry-recorder.unit.test.ts`
- `BridgeWeb/src/foundation/telemetry/bridge-telemetry-event.ts`
- `BridgeWeb/src/foundation/telemetry/bridge-telemetry-bootstrap-config.ts`
- `BridgeWeb/src/foundation/telemetry/bridge-telemetry-bootstrap-config.unit.test.ts`
- `Sources/AgentStudio/Features/Bridge/Transport/BridgeSchemeHandler.swift`
- `Sources/AgentStudio/Features/Bridge/Transport/RPCRouter.swift`
- `Sources/AgentStudio/Features/Bridge/Models/Telemetry/BridgeTelemetryBatch.swift`
- `Sources/AgentStudio/Features/Bridge/Models/Telemetry/BridgeTelemetryLimits.swift`
- `Sources/AgentStudio/Features/Bridge/Runtime/Telemetry/BridgeTelemetryBatchValidator.swift`
- `Sources/AgentStudio/Features/Bridge/Runtime/Telemetry/BridgeTelemetryIngestor.swift`
- `Sources/AgentStudio/Features/Bridge/Runtime/Telemetry/BridgeTelemetryAdmissionController.swift`
- `Tests/AgentStudioTests/Features/Bridge/RPCRouterTelemetryTests.swift`
- `Tests/AgentStudioTests/Features/Bridge/BridgeSchemeHandlerTests.swift`
- `Tests/AgentStudioTests/Features/Bridge/BridgeTelemetryBatchValidatorTests.swift`
- `Tests/AgentStudioTests/Features/Bridge/BridgeTelemetryIngestorTests.swift`

Red-first proof:

```bash
pnpm --dir BridgeWeb exec vitest run src/bridge/bridge-rpc-client.unit.test.ts src/bridge/bridge-telemetry-event-sink.unit.test.ts src/foundation/telemetry/bridge-telemetry-buffer.unit.test.ts src/foundation/telemetry/bridge-telemetry-recorder.unit.test.ts
mise run test -- --filter "RPCRouterTelemetryTests|BridgeSchemeHandlerTests|BridgeTelemetryBatchValidatorTests|BridgeTelemetryIngestorTests"
```

Expected failure before implementation:

- `bridge-rpc-client` still calls `telemetryRecorder.flush({ force: true })`
  from `sendCommand`.
- Telemetry sink still emits `system.bridgeTelemetry` through RPC.
- Browser buffer still uses sample-count-only admission and drop-newest-ish
  behavior, not encoded-byte cap plus drop-oldest aggregate counters keyed by
  event, lane, result, and drop reason.
- Native RPC path still decodes telemetry more than once: envelope parse,
  params re-encode, priority decode, validator decode.
- Native scheme handler has no telemetry POST route.

Green proof:

```bash
pnpm --dir BridgeWeb exec vitest run src/bridge/bridge-rpc-client.unit.test.ts src/bridge/bridge-telemetry-event-sink.unit.test.ts src/foundation/telemetry/bridge-telemetry-buffer.unit.test.ts src/foundation/telemetry/bridge-telemetry-recorder.unit.test.ts src/foundation/telemetry/bridge-telemetry-bootstrap-config.unit.test.ts
pnpm --dir BridgeWeb exec tsc --noEmit
mise run test -- --filter "RPCRouterTelemetryTests|BridgeSchemeHandlerTests|BridgeTelemetryBatchValidatorTests|BridgeTelemetryIngestorTests|AgentStudioOTLP"
```

Required test scenarios:

- Interactive command records `rpc_send` without flushing telemetry and without
  queueing telemetry before command work.
- Telemetry sink uses the dedicated scheme POST endpoint and cannot call
  `BridgeRPCClient.sendCommand`.
- Encoded-byte cap triggers drop-oldest and emits lossless aggregate counters.
- Required event streams fail proof if shed; optional/debug event shedding is
  allowed only with counters and lossy-run annotation.
- Batch sequence gap fails proof unless paired with a matching drop counter and
  the run is explicitly exploratory.
- Native admission rejects over-budget payloads before expensive decode.
- Native validator/ingestor records rejection/drop facts without unsafe raw
  paths, URLs, payload text, prompts, tokens, or raw errors.
- No-interactive-contention test: saturating telemetry cannot delay a synthetic
  interactive command dispatch or command trace marker.

Deletes:

- `telemetryRecorder?.flush({ force: true })` from
  `BridgeWeb/src/bridge/bridge-rpc-client.ts`.
- `system.bridgeTelemetry` from the interactive RPC command union once no
  production caller remains; if a temporary test fixture still needs it, make it
  compile-dead for production before closing the slice.
- Priority sniffing decode in `RPCRouter.bridgeTelemetryBatchAdmissionPriority`.
- Any telemetry queue path that can run ahead of command/content/paint-critical
  work.

Dependencies:

- Depends only on Gate 0.
- Must finish before performance proof in B/C/D/G so percentile samples are
  trustworthy.

Lane boundary:

- Browser telemetry writer owns `BridgeWeb/src/foundation/telemetry/` and
  `BridgeWeb/src/bridge/bridge-telemetry-event-sink*`.
- Browser RPC writer owns `BridgeWeb/src/bridge/bridge-rpc-client*` only.
- Swift transport writer owns `BridgeSchemeHandler`, `RPCRouter`, telemetry
  validator/ingestor/admission files, and matching Swift tests.

## Slice B - Pierre Scroll Cures

Objective:

Fix the four PHASE 2b Pierre integration misuses without forking Pierre:
rAF-coalesced rendered-window capture, deferred non-selected CodeView apply
while scroll-active with immediate cache landing, append/patch item stream
instead of full `setItems` rebuild for non-reset changes, and loading state
that preserves placeholder height.

Files touched:

- `BridgeWeb/src/review-viewer/trees/bridge-trees-panel.tsx`
- `BridgeWeb/src/review-viewer/trees/bridge-trees-panel.unit.test.ts`
- `BridgeWeb/src/review-viewer/trees/bridge-trees-panel.browser.test.ts`
- `BridgeWeb/src/app/bridge-pierre-tree-adapter.ts`
- `BridgeWeb/src/app/bridge-pierre-tree-adapter.unit.test.ts`
- `BridgeWeb/src/review-viewer/content/visible-review-content-hydration.ts`
- `BridgeWeb/src/review-viewer/content/visible-review-content-hydration-support.ts`
- `BridgeWeb/src/review-viewer/content/visible-review-content-hydration.unit.test.ts`
- `BridgeWeb/src/review-viewer/content/visible-review-content-hydration.browser.test.tsx`
- `BridgeWeb/src/review-viewer/code-view/bridge-code-view-materialization.ts`
- `BridgeWeb/src/review-viewer/code-view/bridge-code-view-materialization.unit.test.ts`
- `BridgeWeb/src/review-viewer/code-view/bridge-code-view-materialization.hydration.unit.test.ts`
- `BridgeWeb/src/review-viewer/test-support/bridge-viewer-browser.integration-scroll.browser.test.tsx`
- `BridgeWeb/src/review-viewer/test-support/bridge-viewer-browser.virtualizer.browser.test.tsx`

Line-cap warning:

`visible-review-content-hydration.ts` is 985 lines. This slice is the first
listed slice that touches it, so it must extract scroll/apply/cache-policy
helpers or dissolve logic into focused support modules before adding behavior.
Do not grow it past 1000 lines.

Red-first proof:

```bash
pnpm --dir BridgeWeb exec vitest run src/review-viewer/trees/bridge-trees-panel.unit.test.ts src/app/bridge-pierre-tree-adapter.unit.test.ts src/review-viewer/code-view/bridge-code-view-materialization.unit.test.ts src/review-viewer/code-view/bridge-code-view-materialization.hydration.unit.test.ts src/review-viewer/content/visible-review-content-hydration.unit.test.ts
pnpm --dir BridgeWeb exec vitest --config vitest.browser.config.ts run --project integration-browser src/review-viewer/test-support/bridge-viewer-browser.integration-scroll.browser.test.tsx src/review-viewer/test-support/bridge-viewer-browser.virtualizer.browser.test.tsx src/review-viewer/content/visible-review-content-hydration.browser.test.tsx
```

Expected failure before implementation:

- Scroll event path still walks rendered rows/publishes per event instead of
  one rAF-coalesced capture.
- Non-selected ready CodeView results apply immediately during scroll-active
  momentum instead of landing cache immediately and batching UI apply at idle or
  rAF budget.
- Projection/selection changes still rebuild a full Pierre item set for
  append/update-shaped changes rather than append/patching items and reserving
  full rebuild for source reset.
- Loading item materialization still changes body/version/line count in a way
  that collapses placeholder height before re-expansion.

Green proof:

```bash
wc -l BridgeWeb/src/review-viewer/content/visible-review-content-hydration.ts
pnpm --dir BridgeWeb exec vitest run src/review-viewer/trees/bridge-trees-panel.unit.test.ts src/app/bridge-pierre-tree-adapter.unit.test.ts src/review-viewer/code-view/bridge-code-view-materialization.unit.test.ts src/review-viewer/code-view/bridge-code-view-materialization.hydration.unit.test.ts src/review-viewer/content/visible-review-content-hydration.unit.test.ts
pnpm --dir BridgeWeb exec vitest --config vitest.browser.config.ts run --project integration-browser src/review-viewer/trees/bridge-trees-panel.browser.test.ts src/review-viewer/test-support/bridge-viewer-browser.integration-scroll.browser.test.tsx src/review-viewer/test-support/bridge-viewer-browser.virtualizer.browser.test.tsx src/review-viewer/content/visible-review-content-hydration.browser.test.tsx
pnpm --dir BridgeWeb exec tsc --noEmit
wc -l BridgeWeb/src/review-viewer/content/visible-review-content-hydration.ts
```

Required test scenarios:

- One scroll burst produces at most one rendered-window publication per frame.
- Scroll-active non-selected completions update cache/registry immediately but
  defer DOM/Pierre apply until idle/rAF budget; selected/current apply remains
  first.
- Append/patch update test spies on Pierre adapter calls and proves `setItems`
  is source-reset-only.
- Loading state keeps placeholder height or uses chrome-only loading without
  body/version churn.
- Browser momentum scroll test proves no stuck placeholders and no scroll-jump
  regression.

Deletes:

- Per-scroll-event rendered-row publication.
- Timer churn that races rAF publication for visible item ids.
- Non-selected immediate apply during scroll-active state.
- Full `setItems` rebuild for append/update/projection deltas that are not
  source resets.
- Loading content that collapses placeholder height.

Dependencies:

- Depends on A if the proof uses telemetry percentiles.
- Can land before worker migration; cache landing remains R36-compatible.

Lane boundary:

- Tree/Pierre writer owns `review-viewer/trees/` and `bridge-pierre-tree-adapter*`.
- Hydration writer owns extracted helpers plus the minimum hook edits.
- CodeView materialization writer owns `review-viewer/code-view/` loading and
  hydration tests.

## Slice C - FE Render Store Slicing

Objective:

Implement R45 allowed interaction slice shapes and ban whole-package
interaction subscribers. Proof must show click invalidation is
O(selected + visible delta), not O(package), targeting the verified 560ms flat
commit floor.

Files touched:

- `BridgeWeb/src/review-viewer/state/review-viewer-store.ts`
- `BridgeWeb/src/review-viewer/state/review-viewer-store.unit.test.ts`
- New or extracted slice modules under `BridgeWeb/src/review-viewer/state/`,
  named by ownership, for example:
  `review-selection-slice.ts`, `review-viewport-slice.ts`,
  `review-row-paint-slice.ts`, `review-content-availability-slice.ts`,
  `review-panel-chrome-slice.ts`
- `BridgeWeb/src/app/bridge-app-review-viewer-mode.tsx`
- `BridgeWeb/src/app/bridge-app-review-selection-controller.ts`
- `BridgeWeb/src/app/bridge-app-review-selected-content-controller.ts`
- `BridgeWeb/src/app/bridge-app-review-visible-content-controller.ts`
- `BridgeWeb/src/app/bridge-app-review-runtime.ts`
- `BridgeWeb/src/app/bridge-app-review-descriptors.ts`
- `BridgeWeb/src/app/bridge-app-review-viewer-mode.tsx`
- `BridgeWeb/src/app/bridge-app-review-metadata-package.scaling.unit.test.ts`
- `BridgeWeb/src/review-viewer/test-support/bridge-viewer-browser.integration-large.browser.test.tsx`
- `BridgeWeb/src/review-viewer/test-support/bridge-viewer-browser.integration.browser.test.tsx`

Allowed slice shapes:

- `selectionSlice`: selected identity and local action state.
- `viewportSlice`: visible range plus bounded delta.
- `rowPaintSlice(id)`: one keyed row/item paint model.
- `contentAvailabilitySlice(id)`: one keyed availability fact.
- `panelChromeSlice`: active mode, health, counts, toolbar affordances.

Red-first proof:

```bash
pnpm --dir BridgeWeb exec vitest run src/review-viewer/state/review-viewer-store.unit.test.ts src/app/bridge-app-review-metadata-package.scaling.unit.test.ts src/app/bridge-app-review-selection-controller.unit.test.ts src/app/bridge-app.unit.test.ts
pnpm --dir BridgeWeb exec vitest --config vitest.browser.config.ts run --project integration-browser src/review-viewer/test-support/bridge-viewer-browser.integration-large.browser.test.tsx
```

Expected failure before implementation:

- `bridge-app-review-viewer-mode.tsx` still subscribes to `projection` and
  `selectBridgeReviewViewerRootSnapshot` in interaction paths.
- Selecting one item invalidates package-shaped state and O(package)
  subscribers.
- Large-package fixture instrumentation reports invalidated keys/subscribers
  scaling with package size rather than selected plus visible delta.

Green proof:

```bash
pnpm --dir BridgeWeb exec vitest run src/review-viewer/state/review-viewer-store.unit.test.ts src/app/bridge-app-review-metadata-package.scaling.unit.test.ts src/app/bridge-app-review-selection-controller.unit.test.ts src/app/bridge-app.unit.test.ts
pnpm --dir BridgeWeb exec vitest --config vitest.browser.config.ts run --project integration-browser src/review-viewer/test-support/bridge-viewer-browser.integration-large.browser.test.tsx src/review-viewer/test-support/bridge-viewer-browser.integration.browser.test.tsx
pnpm --dir BridgeWeb exec tsc --noEmit
```

Required test scenarios:

- Whole-package/root snapshot selector cannot be used by click/selection
  interaction subscribers.
- Large fixture selection emits subscriber count and invalidated-key count
  bounded by selected plus visible delta.
- File View's narrower selector style remains a reference, not a direct copy:
  no new root snapshot dependency is introduced in Review.
- FE keeps zero protocol state: no stream, generation, sequence, staleness,
  cache-membership, retry, or demand-membership writer in Review FE slices.

Deletes:

- `selectBridgeReviewViewerRootSnapshot` use from interaction-rendered Review
  mode surfaces.
- Whole ordered arrays, whole maps, and package-shaped view models from
  click/selection subscribers.
- FE protocol state fields that migrated into worker/server-owned rows.

Dependencies:

- Depends on B if the same Review mode surfaces are touched.
- Must finish before D/G so apply pump and worker slices have narrow local
  publish targets.

Lane boundary:

- Store writer owns `review-viewer/state/`.
- Review mode writer owns `bridge-app-review-viewer-mode.tsx` and controller
  subscription rewiring.
- Benchmark/browser writer owns only instrumentation in test support.

## Slice D - Main-Thread Apply Pump

Objective:

Implement R46: a selected-first, frame-budgeted, input-yielding,
resumable/stale-safe apply pump with AppPolicies-backed constants and
no-starvation proof counters.

Files touched:

- New BridgeWeb policy mirror module if not already present, for example
  `BridgeWeb/src/core/policies/bridge-app-policies.ts`
- New apply pump module under a shared BridgeWeb rendering boundary, for
  example `BridgeWeb/src/core/rendering/bridge-frame-apply-pump.ts`
- Unit tests for the pump and policy mirror.
- `BridgeWeb/src/review-viewer/content/visible-review-content-hydration.ts`
  or extracted apply helper from B.
- `BridgeWeb/src/review-viewer/code-view/bridge-code-view-materialization.ts`
- `BridgeWeb/src/review-viewer/code-view/bridge-code-view-materialization.unit.test.ts`
- `BridgeWeb/src/review-viewer/content/visible-review-content-hydration.unit.test.ts`
- `BridgeWeb/src/review-viewer/test-support/bridge-viewer-browser.integration-scroll.browser.test.tsx`
- `Sources/AgentStudio/Infrastructure/AppPolicies.swift`
- `Tests/AgentStudioTests/Features/Bridge/AppPoliciesBridgeTests.swift`

Red-first proof:

```bash
pnpm --dir BridgeWeb exec vitest run src/review-viewer/code-view/bridge-code-view-materialization.unit.test.ts src/review-viewer/content/visible-review-content-hydration.unit.test.ts
mise run test -- --filter AppPoliciesBridgeTests
```

Expected failure before implementation:

- Apply work is not bounded by policy-owned frame time/unit caps.
- Selected/current apply does not have a reserved first slot.
- Visible non-selected work can starve under selected churn.
- Stale pending units are not cleared under a bounded stale-drop scan cap.
- Policy constants are duplicated literals or missing from AppPolicies/mirror.

Green proof:

```bash
pnpm --dir BridgeWeb exec vitest run src/review-viewer/code-view/bridge-code-view-materialization.unit.test.ts src/review-viewer/content/visible-review-content-hydration.unit.test.ts
pnpm --dir BridgeWeb exec vitest --config vitest.browser.config.ts run --project integration-browser src/review-viewer/test-support/bridge-viewer-browser.integration-scroll.browser.test.tsx
pnpm --dir BridgeWeb exec tsc --noEmit
mise run test -- --filter AppPoliciesBridgeTests
```

Required counters:

- Selected apply time and applied-unit histogram.
- Visible non-selected progress counter under selected churn.
- Stale-drop scan count and stale units cleared.
- No-starvation bound: at least one visible non-selected batch completes within
  N selected batches, where N is policy-owned.

Deletes:

- Any "apply all ready entries" microtask or synchronous package-shaped apply
  path for Review CodeView.
- Duplicated budget literals outside the BridgeWeb policy mirror/AppPolicies.
- Any test-only constants that can drift from policy-owned caps.

Dependencies:

- Depends on C for narrow render slice targets.
- Feeds E and G because File View and worker slices must publish into the same
  bounded apply contract.

Lane boundary:

- Policy writer owns AppPolicies and the BridgeWeb policy mirror.
- Pump writer owns the generic apply pump.
- Review writer only wires extracted Review apply units into the pump.

## Slice E - File View Parity

Objective:

Make File View obey the same R41-R46 frame contract: chunk/yield frame
application and projection, and replace the O(N^2) directory prune at
`bridge-file-viewer-state.ts:511`.

Files touched:

- `BridgeWeb/src/file-viewer/bridge-file-viewer-state.ts`
- `BridgeWeb/src/file-viewer/bridge-file-viewer-source-structure.unit.test.ts`
- `BridgeWeb/src/file-viewer/bridge-file-viewer-app.unit.test.ts`
- `BridgeWeb/src/file-viewer/bridge-file-viewer-app.browser.test.tsx`
- `BridgeWeb/src/file-viewer/use-bridge-file-viewer-frame-intake-controller.ts`
- `BridgeWeb/src/file-viewer/use-bridge-file-viewer-store-bindings.ts`
- `BridgeWeb/src/file-viewer/state/bridge-file-viewer-store.ts`
- `BridgeWeb/src/file-viewer/state/bridge-file-viewer-store.unit.test.ts`
- `BridgeWeb/src/worktree-file-surface/worktree-file-surface-runtime.demand.integration-suite.ts`
- Shared apply pump/policy files from D.

Red-first proof:

```bash
pnpm --dir BridgeWeb exec vitest run src/file-viewer/bridge-file-viewer-source-structure.unit.test.ts src/file-viewer/bridge-file-viewer-app.unit.test.ts src/file-viewer/state/bridge-file-viewer-store.unit.test.ts src/worktree-file-surface/worktree-file-surface-runtime.demand.integration-suite.ts
pnpm --dir BridgeWeb exec vitest --config vitest.browser.config.ts run --project integration-browser src/file-viewer/bridge-file-viewer-app.browser.test.tsx
```

Expected failure before implementation:

- Large synthetic directory prune still scales as O(directory count * row
  count) and fails an operation-count or duration-bound test.
- `use-bridge-file-viewer-frame-intake-controller.ts` still applies frames,
  projection, replay, and open-file reconciliation synchronously in one call.
- File View root snapshot subscriptions still include interaction subscribers
  that do not need root state.

Green proof:

```bash
wc -l BridgeWeb/src/file-viewer/bridge-file-viewer-state.ts
pnpm --dir BridgeWeb exec vitest run src/file-viewer/bridge-file-viewer-source-structure.unit.test.ts src/file-viewer/bridge-file-viewer-app.unit.test.ts src/file-viewer/state/bridge-file-viewer-store.unit.test.ts src/worktree-file-surface/worktree-file-surface-runtime.demand.integration-suite.ts
pnpm --dir BridgeWeb exec vitest --config vitest.browser.config.ts run --project integration-browser src/file-viewer/bridge-file-viewer-app.browser.test.tsx
pnpm --dir BridgeWeb exec tsc --noEmit
wc -l BridgeWeb/src/file-viewer/bridge-file-viewer-state.ts
```

Deletes:

- Nested full-scan directory prune.
- Synchronous unbounded File View frame apply/projection/replay loops.
- Any File View exemption from the D apply-pump policy classes.

Dependencies:

- Depends on D's pump and policy constants.
- Must finish before final live `bridge-review-to-file-view` smoke.

Lane boundary:

- File View writer owns `BridgeWeb/src/file-viewer/`.
- Worktree-file runtime writer owns only demand integration tests and minimal
  adapter changes.
- Shared pump/policy files remain owned by D's writer.

## Slice F - Worker Fetch Native Proof Gate

Objective:

Prove in a real debug app that a Web Worker can `fetch()` through the
registered content `WKURLSchemeHandler`. This is a blocking gate for G. If it
fails, record a fallback decision: page-fetch-and-transfer while preserving R44
worker byte/cache/retry ownership, or stop and revise R44.

Files touched:

- `BridgeWeb/src/bridge/bridge-resource-url.ts`
- `BridgeWeb/src/bridge/bridge-resource-url.unit.test.ts`
- Existing or new worker probe under `BridgeWeb/src/review-viewer/workers/`
  or `BridgeWeb/src/core/bridge-host/`.
- `Sources/AgentStudio/Features/Bridge/Transport/BridgeSchemeHandler.swift`
- `Tests/AgentStudioTests/Features/Bridge/BridgeSchemeHandlerTests.swift`
- `Tests/AgentStudioTests/Features/Bridge/BridgeWebKitSpikeTests.swift`
- `Tests/AgentStudioTests/Features/Bridge/WebKitSerializedTests.swift`
- Startup diagnostic hook files under `Sources/AgentStudio/App/Boot/`.
- New verifier script, for example
  `scripts/verify-bridge-worker-fetch-scheme-smoke.sh`.

Red-first proof:

```bash
CI=true mise run test -- --filter "WebKitSerializedTests|BridgeWebKitSpikeTests|BridgeSchemeHandlerTests"
AGENTSTUDIO_IPC_UNSAFE_NO_AUTH=1 AGENTSTUDIO_IPC_DEBUG_TOKEN_ESCROW=1 AGENTSTUDIO_STARTUP_DIAGNOSTIC_ACTION=bridge-worker-fetch-scheme-smoke mise run run-debug-observability -- --detach
bash scripts/verify-bridge-worker-fetch-scheme-smoke.sh
```

Expected failure before implementation:

- No native debug-app startup diagnostic exists for worker custom-scheme fetch.
- No verifier can prove worker-originated `fetch(agentstudio://resource/...)`
  reaches `BridgeSchemeHandler` and returns bytes.
- If the debug proof exists but fails with WebKit delivery/registration error,
  G must remain blocked.

Green proof:

```bash
CI=true mise run test -- --filter "WebKitSerializedTests|BridgeWebKitSpikeTests|BridgeSchemeHandlerTests"
mise run observability:up
AGENTSTUDIO_IPC_UNSAFE_NO_AUTH=1 AGENTSTUDIO_IPC_DEBUG_TOKEN_ESCROW=1 AGENTSTUDIO_STARTUP_DIAGNOSTIC_ACTION=bridge-worker-fetch-scheme-smoke AGENTSTUDIO_TRACE_TAGS="app.startup,performance,bridge.performance.*" mise run run-debug-observability -- --detach
mise run verify-debug-observability
bash scripts/verify-bridge-worker-fetch-scheme-smoke.sh
```

Required proof facts:

- Worker-originated request uses the content scheme, not page fetch.
- `BridgeSchemeHandler` serves the request with content admission intact.
- Returned bytes are observed inside the worker.
- The proof records worker URL, resource kind, byte count, result, and marker
  without raw path/content leakage.
- Run-loop starvation remains separate: this gate proves worker custom-scheme
  delivery, not all click/scroll budgets.

Deletes:

- None unless this slice replaces an exploratory spike. Do not delete existing
  content scheme paths.

Dependencies:

- Depends on A only if verifier telemetry uses the dedicated endpoint.
- Blocks all G content-byte streaming cutovers.

Lane boundary:

- Native WebKit proof writer owns Swift tests/diagnostic/verifier script.
- BridgeWeb worker-probe writer owns only probe code and unit tests.

## Slice G - Comm-Worker Migration Units

Objective:

Move protocol truth, cache truth, queue/executor truth, telemetry batching, and
Swift synchronization into a comm worker. FE keeps zero protocol state. This is
not one PR unless a reviewer accepts the blast radius; use per-viewer/protocol
compile-enforced cutover units.

Files touched by the shared worker core:

- New comm-worker modules under `BridgeWeb/src/core/comm-worker/`, for example:
  `bridge-comm-worker-entry.ts`, `bridge-comm-worker-client.ts`,
  `bridge-comm-worker-protocol.ts`, `bridge-comm-worker-cache.ts`,
  `bridge-comm-worker-reconciler.ts`, `bridge-comm-worker-executor.ts`,
  `bridge-comm-worker-telemetry.ts`, and hostile server test support.
- `BridgeWeb/src/core/demand/bridge-content-demand-reconciler.ts`
- `BridgeWeb/src/core/demand/bridge-resource-executor.ts`
- `BridgeWeb/src/core/models/bridge-demand-models.ts`
- `BridgeWeb/src/core/resources/bridge-resource-stream.ts`
- `BridgeWeb/src/core/resources/bridge-resource-registry.ts`
- `BridgeWeb/src/bridge/bridge-resource-url.ts`
- `BridgeWeb/src/foundation/telemetry/bridge-telemetry-*`
- `BridgeWeb/src/review-viewer/workers/projection/*` as reference only unless
  shared worker transport helpers are intentionally extracted.

Review cutover files:

- `BridgeWeb/src/app/bridge-app-review-viewer-mode.tsx`
- `BridgeWeb/src/app/bridge-app-review-runtime.ts`
- `BridgeWeb/src/app/bridge-app-review-controller.ts`
- `BridgeWeb/src/app/bridge-app-review-descriptors.ts`
- `BridgeWeb/src/app/bridge-app-review-intake-controller.ts`
- `BridgeWeb/src/app/bridge-app-review-selection-controller.ts`
- `BridgeWeb/src/app/bridge-app-review-selected-content-controller.ts`
- `BridgeWeb/src/app/bridge-app-review-visible-content-controller.ts`
- `BridgeWeb/src/review-viewer/content/review-content-demand-loader.ts`
- `BridgeWeb/src/review-viewer/content/review-content-registry.ts`
- `BridgeWeb/src/review-viewer/content/visible-review-content-hydration.ts`
- `BridgeWeb/src/review-viewer/state/*`
- Review browser/unit/integration suites named in B/C/D.

File View cutover files:

- `BridgeWeb/src/file-viewer/*`
- `BridgeWeb/src/file-viewer/state/*`
- `BridgeWeb/src/worktree-file-surface/worktree-file-surface-runtime.ts`
- `BridgeWeb/src/worktree-file-surface/worktree-file-surface-runtime-support.ts`
- `BridgeWeb/src/worktree-file-surface/worktree-file-surface-runtime.demand.integration-suite.ts`

Swift/server files:

- `Sources/AgentStudio/Features/Bridge/Transport/BridgeSchemeHandler.swift`
- `Sources/AgentStudio/Features/Bridge/Transport/RPCRouter.swift`
- `Sources/AgentStudio/Features/Bridge/Runtime/BridgePaneController+ReviewMetadataInterest.swift`
- `Sources/AgentStudio/Features/Bridge/Runtime/BridgePaneController+ReviewProtocolResources.swift`
- `Sources/AgentStudio/Features/Bridge/Runtime/WorktreeFileSurface/*`
- `Sources/AgentStudio/Features/Bridge/Transport/BridgeContentDemandAdmission.swift`
- Matching tests under `Tests/AgentStudioTests/Features/Bridge/`.

### G1 - Worker Protocol/Core Shell

Red-first proof:

```bash
pnpm --dir BridgeWeb exec vitest run src/core/comm-worker/bridge-comm-worker-protocol.unit.test.ts src/core/comm-worker/bridge-comm-worker-client.unit.test.ts src/core/comm-worker/bridge-comm-worker-hostile-server.unit.test.ts
pnpm --dir BridgeWeb exec tsc --noEmit
```

Expected failure before implementation: modules do not exist, and hostile
server scenarios cannot prove streamId, workerDerivationEpoch, sequence,
staleness, reconnect, duplicate/drop/reorder handling, and never-resolving
reply behavior.

Green proof:

```bash
pnpm --dir BridgeWeb exec vitest run src/core/comm-worker/bridge-comm-worker-protocol.unit.test.ts src/core/comm-worker/bridge-comm-worker-client.unit.test.ts src/core/comm-worker/bridge-comm-worker-hostile-server.unit.test.ts
pnpm --dir BridgeWeb exec tsc --noEmit
```

Deletes: none yet, but worker types must make FE protocol-state imports
unnecessary in later units.

### G2 - Worker Cache + Queue/Executor + Telemetry

Red-first proof:

```bash
pnpm --dir BridgeWeb exec vitest run src/core/comm-worker/bridge-comm-worker-cache.unit.test.ts src/core/comm-worker/bridge-comm-worker-reconciler.unit.test.ts src/core/comm-worker/bridge-comm-worker-executor.unit.test.ts src/core/comm-worker/bridge-comm-worker-telemetry.unit.test.ts src/core/demand/bridge-content-demand-reconciler.unit.test.ts src/core/demand/bridge-resource-executor.unit.test.ts
```

Expected failure before implementation: worker cannot own R32-R40 membership,
R34 backoff/pacing, R37 epoch reset, R39 rank into worker pools, R43 telemetry
batching/shedding, or R44 content streaming with worker-side byte cache.

Green proof:

```bash
pnpm --dir BridgeWeb exec vitest run src/core/comm-worker/bridge-comm-worker-cache.unit.test.ts src/core/comm-worker/bridge-comm-worker-reconciler.unit.test.ts src/core/comm-worker/bridge-comm-worker-executor.unit.test.ts src/core/comm-worker/bridge-comm-worker-telemetry.unit.test.ts src/core/demand/bridge-content-demand-reconciler.unit.test.ts src/core/demand/bridge-resource-executor.unit.test.ts src/review-viewer/workers/pierre/bridge-pierre-worker-pool.rank.unit.test.ts
pnpm --dir BridgeWeb exec tsc --noEmit
```

Deletes:

- Worker-side duplicate queue/cache/retry state that shadows another worker
  module.
- Any browser-main-thread byte cache for converted worker-owned resources.

### G3 - Review Content Protocol Cutover

Red-first proof:

```bash
pnpm --dir BridgeWeb exec tsc --noEmit
pnpm --dir BridgeWeb exec vitest run src/review-viewer/state/review-viewer-store.unit.test.ts src/app/bridge-app-review-selection-controller.unit.test.ts src/review-viewer/content/review-content-demand-loader.unit.test.ts src/review-viewer/content/visible-review-content-hydration.unit.test.ts
pnpm --dir BridgeWeb exec vitest --config vitest.browser.config.ts run --project integration-browser src/review-viewer/test-support/bridge-viewer-browser.integration.browser.test.tsx src/review-viewer/test-support/bridge-viewer-browser.integration-scroll.browser.test.tsx
```

Expected failure before implementation: Review still owns package-first body
loading, root-snapshot selection render path, prefetch/pump residue, FE
generation/sequence/staleness/cache membership, or FE content retry/parking.

Green proof:

```bash
pnpm --dir BridgeWeb exec vitest run src/review-viewer/state/review-viewer-store.unit.test.ts src/app/bridge-app-review-selection-controller.unit.test.ts src/review-viewer/content/review-content-demand-loader.unit.test.ts src/review-viewer/content/visible-review-content-hydration.unit.test.ts src/review-viewer/workers/pierre/bridge-pierre-worker-pool.rank.unit.test.ts
pnpm --dir BridgeWeb exec vitest --config vitest.browser.config.ts run --project integration-browser src/review-viewer/test-support/bridge-viewer-browser.integration.browser.test.tsx src/review-viewer/test-support/bridge-viewer-browser.integration-scroll.browser.test.tsx src/review-viewer/test-support/bridge-viewer-browser.integration-large.browser.test.tsx
pnpm --dir BridgeWeb exec tsc --noEmit
```

Compile-enforced deletion set:

- Review package-first body loading for converted surfaces.
- FE generation/sequence/staleness/cache-membership truth.
- FE demand retry/parking fields.
- Review prefetch pump and old cache-membership authority.
- Any compatibility shim or feature flag keeping old Review content protocol
  live beside the worker path.

### G4 - File Viewer Content Protocol Cutover

Red-first proof:

```bash
pnpm --dir BridgeWeb exec tsc --noEmit
pnpm --dir BridgeWeb exec vitest run src/file-viewer/bridge-file-viewer-app.unit.test.ts src/file-viewer/state/bridge-file-viewer-store.unit.test.ts src/worktree-file-surface/worktree-file-surface-runtime.demand.integration-suite.ts
pnpm --dir BridgeWeb exec vitest --config vitest.browser.config.ts run --project integration-browser src/file-viewer/bridge-file-viewer-app.browser.test.tsx
```

Expected failure before implementation: File View still owns raw body/frame
package intake, FE generation/sequence/staleness caches for content, FE demand
retry/parking, or synchronous unbounded frame/projection apply.

Green proof:

```bash
pnpm --dir BridgeWeb exec vitest run src/file-viewer/bridge-file-viewer-app.unit.test.ts src/file-viewer/state/bridge-file-viewer-store.unit.test.ts src/worktree-file-surface/worktree-file-surface-runtime.demand.integration-suite.ts
pnpm --dir BridgeWeb exec vitest --config vitest.browser.config.ts run --project integration-browser src/file-viewer/bridge-file-viewer-app.browser.test.tsx
pnpm --dir BridgeWeb exec tsc --noEmit
```

Compile-enforced deletion set:

- FE raw body/frame package intake for File View converted content.
- FE generation/sequence/staleness caches for File View content.
- FE retry/parking fields.
- Any dual reader for the converted File View protocol surface.

### G5 - Server Seam And Live Cutover Cleanup

Red-first proof:

```bash
mise run test -- --filter "BridgeSchemeHandler|BridgeContentDemandAdmission|BridgeReviewContentStreamTransport|BridgeWorktreeFileSurfaceDemandTransport|RPCRouterTelemetryTests|BridgeTelemetryBatchValidatorTests"
pnpm --dir BridgeWeb exec tsc --noEmit
```

Expected failure before implementation: Swift tests do not yet replay recorded
worker traffic for content scheme serving, telemetry POST admission,
`BridgeContentDemandAdmission`, reset/unhealthy responses, and source authority
for converted surfaces.

Green proof:

```bash
mise run test -- --filter "BridgeSchemeHandler|BridgeContentDemandAdmission|BridgeReviewContentStreamTransport|BridgeWorktreeFileSurfaceDemandTransport|RPCRouterTelemetryTests|BridgeTelemetryBatchValidatorTests|AgentStudioOTLP"
pnpm --dir BridgeWeb exec tsc --noEmit
```

Deletes:

- `system.bridgeTelemetry` production route if any remains.
- Handler-splitting comments or tests that claim WebKit IPC isolation.
- FE server lifetime/protocol state visible to the user.
- Any old content-demand path for converted surfaces.

Dependencies:

- F green proof is mandatory before any R44 worker-fetch cutover.
- G3 and G4 can be separate PRs only if each has its own compile-enforced old
  path deletion for that viewer/protocol.

Lane boundary:

- Comm-worker core writer owns `BridgeWeb/src/core/comm-worker/` and shared
  worker test support.
- Review writer owns Review cutover files.
- File View writer owns File View cutover files.
- Swift server writer owns scheme handler, admission, metadata/content serving,
  telemetry validator/ingestor, and Swift tests.

## Requirements / Proof Matrix

| Requirement | Slice(s) | Proof commands / evidence |
| --- | --- | --- |
| R41 paint paths do not await boundaries | A, B, C, D, G3/G4 | RPC no-force-flush tests; Review browser click/scroll tests; slice-store O(selected + visible delta) proof; apply pump tests; full live click-to-paint Victoria evidence |
| R42 every datum has one truth owner | C, G1-G5 | FE zero protocol state source scans; comm-worker hostile-server protocol tests; Review/File View compile-enforced deletion scans |
| R43 telemetry dedicated lane | A, G2/G5 | Browser telemetry sink/buffer/recorder tests; `BridgeSchemeHandler` telemetry POST tests; `RPCRouterTelemetryTests` proving old RPC route removed or production-dead |
| R44 content bytes stream to worker | F, G2-G4 | Native worker-fetch smoke; comm-worker cache/fetch tests; Review/File View browser tests showing FE gets paint-ready structures only |
| R45 FE render store sliced | C | Store unit tests; large browser fixture subscriber/invalidation counters bounded by selected + visible delta |
| R46 main-thread apply pump | D, B, E | Pump unit tests; policy tests; browser scroll proof; no-starvation/stale-drop counters |
| R47 File View projection/pruning parity | E, G4 | File View unit/browser tests; O(N^2) prune regression test; chunked/yielding apply counters |
| R48 proof seams match boundaries | A-G | FE hostile fake worker tests; worker hostile mock server tests; Swift recorded worker traffic tests; native WKWebView gates; Victoria proof |
| PHASE 2 telemetry shared-channel compounding | A | `bridge-rpc-client` no-force-flush test; dedicated scheme endpoint tests; no-interactive-contention test |
| PHASE 2 560ms click floor | C, D, live gates | O(selected + visible delta) invalidation proof; apply pump counters; VictoriaMetrics improvement vs 560ms baseline |
| PHASE 2 severe freezes | D, E, live gates | Apply pump tests; File View chunk/prune tests; Victoria/Momentum proof showing 1.5s choke gone and no severe apply stalls |
| PHASE 2 R32 dormant / multi-authority | G2-G5 | Comm-worker reconciler/executor tests; FE protocol-state deletion scans; source scans for old authorities |
| PHASE 2b cure 1 rendered-window capture | B | Tree panel unit/browser tests proving rAF-coalesced publication |
| PHASE 2b cure 2 defer non-selected CodeView apply while scroll-active | B, D | Hydration/materialization tests and scroll browser tests; cache lands immediately, UI apply deferred |
| PHASE 2b cure 3 append/patch item stream | B | Pierre adapter tests proving `setItems` source-reset-only and append/update path for deltas |
| PHASE 2b cure 4 loading keeps placeholder height | B | CodeView materialization tests and browser no-layout-shift scroll proof |
| Constants Annex cap classes | A, D, E, G | Policy tests proving execution/pacing/retention caps are separated and no membership caps are reintroduced |

Proof seam honesty:

- Unit tests do not prove WebKit run-loop delivery, real worker scheduling, or
  user-perceived click/scroll budgets.
- Browser Vitest proves DOM/browser behavior but not native WebKit custom
  scheme delivery inside the app.
- Swift tests prove server/admission behavior but not FE paint timing or worker
  cache policy.
- Percentiles are valid only from non-lossy required telemetry streams after A.
- Worker custom-scheme fetch is not assumed; F is a blocking live gate.

## Lane Boundaries

One writer per family:

- Telemetry lane owns browser telemetry files, dedicated scheme telemetry route,
  validator/ingestor/admission, and telemetry tests.
- Review tree/Pierre lane owns `review-viewer/trees/` and
  `bridge-pierre-tree-adapter*`.
- Review hydration/materialization lane owns extracted hydration/apply helpers
  and CodeView materialization files. It also owns the
  `visible-review-content-hydration.ts` split because that file is 985 lines.
- Review store lane owns `review-viewer/state/` and interaction subscription
  rewiring in Review mode/controllers.
- Apply pump lane owns shared BridgeWeb policy/pump files and AppPolicies
  mirror tests.
- File View lane owns `BridgeWeb/src/file-viewer/` and
  `BridgeWeb/src/worktree-file-surface/` demand integration.
- Comm-worker core lane owns `BridgeWeb/src/core/comm-worker/`.
- Swift server lane owns scheme handler, RPCRouter cleanup, admission,
  telemetry ingestion, and Bridge transport tests.

Line caps:

- BridgeWeb TS/TSX source cap is 1000 lines. Touched TS/TSX files over 800
  lines require pre/post `wc -l` proof and extraction before growth.
- Current high-risk files: `visible-review-content-hydration.ts` 985 lines,
  `bridge-file-viewer-state.ts` 867 lines, `bridge-resource-executor.ts` 762
  lines, `bridge-code-view-materialization.ts` 750 lines.
- SwiftLint caps remain authoritative for Swift.

Command discipline:

- Run commands from repo root unless the command explicitly uses `--dir`.
- Do not pipe gates through `tee` or `cat`; capture direct exit codes.
- Do not edit infrastructure, test harnesses, lint config, CI, or observability
  to make a slice pass. If a required gate fails outside the slice, stop and
  report scoped pass/fail plus blocker.

## Cutover Deletion Checklist

Before the final G cleanup PR is ready:

- `telemetryRecorder?.flush({ force: true })` is gone from interactive command
  paths.
- Browser telemetry no longer uses `system.bridgeTelemetry` over interactive
  RPC in production.
- Native telemetry does not decode the same payload for priority before
  validator decode.
- Browser telemetry cap is encoded-byte based, not sample-count only.
- Lossless aggregate drop counters exist for shed samples; required event
  shedding fails proof.
- Review FE has no generation/sequence/staleness/stream/cache-membership/retry
  truth for converted content.
- File View FE has no raw body/frame package intake or generation/sequence/
  staleness cache for converted content.
- Review prefetch/demand old paths are compile-dead for converted surfaces.
- Demand membership lives in the comm worker for converted surfaces.
- Main thread receives only paint-ready structures, availability facts, health
  facts, and apply units for converted content.
- `setItems` full rebuild is source-reset-only for Pierre deltas.
- Loading placeholders preserve height.
- File View O(N^2) directory prune is gone.
- No compatibility shim, feature flag, or dual reader keeps old and new paths
  live for one converted viewer/protocol surface.

Required source scans:

```bash
rg -n "flush\\(\\{ force: true \\}\\)|system\\.bridgeTelemetry|BridgeTelemetryEventSink|bridgeTelemetryBatchAdmissionPriority" BridgeWeb/src Sources/AgentStudio Tests
rg -n "streamId|sourceGeneration|generation|sequence|staleness|retryAfterVersion|cacheMembership|demandMembership" BridgeWeb/src/app BridgeWeb/src/review-viewer BridgeWeb/src/file-viewer
rg -n "setItems\\(|applyItemUpdate|getRenderedItems|visibleContentHydrationItemLimit|reviewContentPrefetch|useBridgeReviewContentPrefetchController" BridgeWeb/src
rg -n "pruneEmptyWorktreeFileTreeDirectories|for \\(const \\[path, treeRow\\].*treeRowsByPath\\)|for \\(const candidate of treeRowsByPath\\.values\\(\\)\\)" BridgeWeb/src/file-viewer
```

Expected green scan results:

- Matches are either deleted, production-dead tests asserting absence, or
  explicitly server/worker-owned vocabulary. FE converted surfaces must not
  own protocol truth.

## Explicit Non-Goals

Verbatim from the spec:

- No Pierre fork.
- No claim that DOM materialization moves off the main thread.
- No `SharedArrayBuffer` requirement.
- No merge of the native metadata plane into the comm worker.
- No new browser-side diff/repo authority.
- No server lifetime surfaced to FE as user-visible protocol state.
- No implementation phase plan in this document.

Plan-specific non-goals:

- No compatibility shims or dual live paths for one converted viewer/protocol.
- No handler-splitting claim of WebKit IPC isolation.
- No raw path/content/URL/error telemetry.
- No broad native metadata-plane rewrite.
- No release/beta promotion in this increment unless separately requested.

## Definition Of Done

The full increment is done only when all of these are reported with commands,
exit codes, and pass/fail counts where available:

1. Gate 0 re-anchor is current and every dirty file is owned.
2. Each slice's red-first proof fails for the expected reason before
   implementation.
3. Each slice's green proof passes after implementation.
4. `pnpm --dir BridgeWeb exec vitest run` passes.
5. `pnpm --dir BridgeWeb exec vitest --config vitest.browser.config.ts run --project integration-browser`
   passes, including Review scroll/browser and File View browser suites.
6. `pnpm --dir BridgeWeb exec tsc --noEmit` passes.
7. `pnpm --dir BridgeWeb exec oxlint --type-aware` passes.
8. `pnpm --dir BridgeWeb exec oxfmt --check .` passes.
9. `mise run lint` passes.
10. `mise run test` passes, or any out-of-scope failure is reported separately
    with scoped pass/fail evidence and no infrastructure edits.
11. Worker-fetch native proof passes:
    `AGENTSTUDIO_STARTUP_DIAGNOSTIC_ACTION=bridge-worker-fetch-scheme-smoke`
    plus `bash scripts/verify-bridge-worker-fetch-scheme-smoke.sh`.
12. Two diagnostic launches pass:

```bash
mise run observability:up
AGENTSTUDIO_IPC_UNSAFE_NO_AUTH=1 AGENTSTUDIO_IPC_DEBUG_TOKEN_ESCROW=1 AGENTSTUDIO_STARTUP_DIAGNOSTIC_ACTION=bridge-review-observability-smoke AGENTSTUDIO_TRACE_TAGS="app.startup,performance,bridge.performance.*" mise run run-debug-observability -- --detach
mise run verify-debug-observability
mise run verify-bridge-review-journey-smoke

# Quit the launched Agent Studio Debug app before the second launch.

AGENTSTUDIO_IPC_UNSAFE_NO_AUTH=1 AGENTSTUDIO_IPC_DEBUG_TOKEN_ESCROW=1 AGENTSTUDIO_STARTUP_DIAGNOSTIC_ACTION=bridge-review-to-file-view-observability-smoke AGENTSTUDIO_TRACE_TAGS="app.startup,performance,bridge.performance.*" mise run run-debug-observability -- --detach
mise run verify-debug-observability
mise run verify-bridge-mode-idle-smoke
```

13. Momentum-scroll probe runner passes. It must prove, on a live debug app,
    that `truncatedVisibleItemCount == 0` and `untrackedItemCount` drains to 0
    after bounded settle:

```bash
bash scripts/verify-bridge-review-momentum-scroll-state-probe.sh
```

14. VictoriaMetrics evidence compares against measured baselines and shows:
    the 560ms click commit floor is gone, the 1.5s RPC dispatch choke is gone,
    required telemetry streams are non-lossy, and click-to-paint improves
    against the baseline artifact.
15. User confirms the Review momentum-scroll UX no longer leaves visible items
    stuck as placeholders and click-to-visible-content feels responsive.
16. Source scans show old protocol/demand/telemetry paths are gone or
    compile-dead for converted surfaces.
17. Every touched TS/TSX file over 800 lines has pre/post `wc -l` proof, and no
    TS/TSX file exceeds 1000 lines.
18. If any telemetry attribute is added, OTLP projection and telemetry validator
    tests were red-first and then green, with unsafe data scrubbed.
19. `implementation-review-swarm` reviews the final diff before merge.

## Contradictions And Planning Resolutions

- PHASE 2 says workers can fetch `WKURLSchemeHandler` schemes, but the reviewed
  spec says that is source-grounded research, not closed production proof. This
  plan treats F as blocking for G and does not assume worker fetch.
- The request cites `bridge-rpc-client.ts:116`; the live file still contains
  `telemetryRecorder?.flush({ force: true })` in `sendCommand`, currently near
  line 116. A can target the live call site.
- The request cites `bridge-file-viewer-state.ts:511`; the live O(N^2) prune
  loop still exists in `pruneEmptyWorktreeFileTreeDirectories`.
- PHASE 2b shorthand cites `panel.tsx`, but the live file is
  `BridgeWeb/src/review-viewer/trees/bridge-trees-panel.tsx`.
- The old exemplar plan describes a one-PR hard cutover for R32-R40. R41-R48
  migration constraints require per-cutover-unit deletion sets, so this plan
  proposes multiple PRs and names the exact compile-enforced boundaries.
- `visible-review-content-hydration.ts` is 985 lines, not a safe edit target
  for additive behavior. The first touching slice must split/dissolve it.
