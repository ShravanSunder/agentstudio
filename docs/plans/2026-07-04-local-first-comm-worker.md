# Local-First Comm Worker Implementation Plan

Date: 2026-07-04
goal_id: 2026-07-04-bridge-scroll-demand-queue
source_spec: `docs/specs/bridge-viewer-transport/local-first-comm-worker-architecture.md`
source_commit: `64ec1f67`

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
  read in full from committed `64ec1f67`: 741 lines. Normative anchors include
  R41-R48 and native live gates; `Channel Topology And Typed Contracts` lines
  419-502; `Action And Event Sequence Contracts` lines 503-665; migration
  constraints and compile-enforced deletion sets lines 667-704. Channel
  Topology is the source contract for G: exactly three runtime channels,
  `BridgeWorkerContracts` as the typed main/server-worker schema source,
  scheme-fetch request/response RPC plus long-lived streamed-fetch push for all
  Swift communication, Pierre API only on the Pierre edge, and forbidden edges
  banning main->Swift script-message ordinary traffic, worker->DOM/render,
  Pierre initiator roles, and untyped messages. The single network boundary
  amendment in `64ec1f67` also makes page-load bootstrap the only one-shot
  script-message exemption, deprecates the `WKScriptMessage` /
  `__bridge_command` RPC plane, and requires that script-message plane to be
  compile-deleted in the final cutover unit.
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

Hotfix integration note:

A concurrent hotfix is landing on `HEAD` for CodeView panel/hydration identity
stability, skip-before-materialize, and time-sliced materialization. B and D
must build on those committed primitives after they land. Do not duplicate the
hotfix in this plan. The hotfix's time-sliced materialization budget becomes
the seed for the R46 apply-pump budget; B and D may only extract or wire
through those primitives, then move the policy-owned pump boundary forward.

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
PR 6a / slice F0: diagnostic enum/action, verifier script, static tests
  |
PR 6b / slice F1: observability-up native WKWebView worker-fetch proof
  |
PR 7+ / slice G: inert typed shell, then one live cutover unit at a time
  |
full live gates: both smokes, momentum probe, VictoriaMetrics improvement,
user UX confirmation, plan-review/implementation-review before merge
```

Parallelization is intentionally limited. A can run before B because it removes
transport contention shared by all later performance proof. B, C, and D must
serialize around Review render/apply surfaces. E can branch after D's pump
policy is stable but must merge before full live proof. F0 must land before F1.
F1 is blocking for any G cutover that claims worker-fetch/content-byte proof.
G1 is an inert typed shell only; every production ownership move after G1 is a
separate compile-enforced cutover unit.

## Gate 0 - Planning Re-Anchor

Objective:

Reconfirm this plan's assumptions before any implementation branch starts. This
gate is read-only except for normal test/build artifacts produced by commands.

Required checks:

```bash
git status --short
git show --stat --oneline --decorate=short 64ec1f67 -- docs/specs/bridge-viewer-transport/local-first-comm-worker-architecture.md
git show 64ec1f67:docs/specs/bridge-viewer-transport/local-first-comm-worker-architecture.md | wc -l
wc -l docs/plans/2026-07-04-unified-content-demand-queue.md tmp/debug-workflows/2026-07-04-agent-studio-luna338-scroll-placeholder-survivor/debug-investigation.md docs/specs/bridge-viewer-transport/performance-demand-lanes.md
git show HEAD:BridgeWeb/src/review-viewer/content/visible-review-content-hydration.ts | wc -l
git show HEAD:BridgeWeb/src/review-viewer/trees/bridge-trees-panel.tsx | wc -l
git show HEAD:BridgeWeb/src/file-viewer/bridge-file-viewer-state.ts | wc -l
git show HEAD:Sources/AgentStudio/Features/Bridge/Transport/RPCRouter.swift | wc -l
```

Expected current anchors:

- `git status --short` is clean or every dirty path has a named owner before
  execution starts.
- `64ec1f67` is the current committed source for the comm-worker spec.
- `visible-review-content-hydration.ts` is 985 lines. The first slice that
  touches it owns split/dissolution work; do not grow it past the cap.
- `bridge-trees-panel.tsx` lives at
  `BridgeWeb/src/review-viewer/trees/bridge-trees-panel.tsx`, not directly
  under `review-viewer/`.
- `RPCRouter.swift` remains the current telemetry RPC intake path until A.

Stop conditions:

- Any source file named above has drifted enough that its defect anchor no
  longer exists.
- The worker-fetch proof from F1 already exists and contradicts this sequence.
- A test/lint/build failure outside the agreed slice appears; report it instead
  of editing harnesses, lint config, CI, or observability infrastructure.

## PR Boundary Proposal

1. PR 1: `bridge-telemetry-scheme-transport` implements A only.
2. PR 2: `bridge-review-pierre-scroll-cures` implements B only.
3. PR 3: `bridge-review-render-store-slicing` implements C only.
4. PR 4: `bridge-review-apply-pump` implements D only.
5. PR 5: `bridge-file-view-frame-parity` implements E only.
6. PR 6a: `bridge-worker-fetch-diagnostic-shell` implements F0 only: startup
   diagnostic enum/action, launcher trace-tag allowance, verifier script, and
   static/dry-run tests. No native proof claim.
7. PR 6b: `bridge-worker-fetch-native-proof` implements F1 only: bring
   `observability:up` first, launch the native debug app, and verify the worker
   scheme-fetch gate. If it fails, record the fallback/redesign decision and
   stop before G cutovers.
8. PR 7a: `bridge-comm-worker-typed-shell` implements G1 only: inert
   `BridgeWorkerContracts` types plus a non-owning client/shell. No production
   ownership, cache, queue/executor, telemetry transport, or R41-R48 proof
   claims.
9. PR 7b: `bridge-comm-worker-telemetry-cutover` converts telemetry transport
   with compile-dead deletion.
10. PR 7c: `bridge-comm-worker-review-cutover` converts Review content protocol.
11. PR 7d: `bridge-comm-worker-file-view-cutover` converts File View content
   protocol.
12. PR 7e: `bridge-comm-worker-demand-membership-cutover` converts demand
    membership.
13. PR 7f: `bridge-final-browser-native-rpc-cutover` compile-deletes the
    script-message RPC plane for ordinary Swift communication, keeps only the
    minimal one-shot page-load bootstrap exemption, proves scheme-fetch
    request/response plus streamed-fetch push, and runs full live gates.

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

Red patch first:

Add/modify these assertions only, run the command below, and record the expected
failure. Do not edit production until the red failure is observed.

- In `BridgeWeb/src/bridge/bridge-rpc-client.unit.test.ts`, change
  `attaches trace context outside params and records generic RPC telemetry` so
  the exact assertion becomes `expect(flushCount).toBe(0)` and
  `expect(flushForces).toEqual([])`.
- In `BridgeWeb/src/bridge/bridge-rpc-client.unit.test.ts`, rename/add
  `does not force telemetry flush while sending interactive commands` if the
  existing test name stops describing the new assertion.
- In `BridgeWeb/src/bridge/bridge-telemetry-event-sink.unit.test.ts`, replace
  `flushes batches through the exact system bridge telemetry method` with
  `posts telemetry batches to the dedicated scheme endpoint` and assert no
  `BridgeRPCClient.sendCommand` spy is called.
- In `BridgeWeb/src/foundation/telemetry/bridge-telemetry-buffer.unit.test.ts`,
  add `drops oldest optional samples by encoded byte cap and emits aggregate
  counters`.
- In
  `Tests/AgentStudioTests/Features/Bridge/RPCRouterTelemetryTests.swift`, add
  `interactiveRPCRejectsProductionBridgeTelemetryBatches`.
- In
  `Tests/AgentStudioTests/Features/Bridge/BridgeSchemeHandlerTests.swift`, add
  `telemetryPostRouteAdmitsSingleDecodedBatch`.
- In
  `Tests/AgentStudioTests/Features/Bridge/BridgeTelemetryBatchValidatorTests.swift`,
  add `sequenceGapRequiresMatchingDropCounter`.

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
- `scripts/verify-bridge-review-momentum-scroll-state-probe.sh`
- `.mise.toml`

First task:

Before adding any behavior, perform a behavior-neutral extraction split of
`visible-review-content-hydration.ts`: move scroll/apply/cache helpers into
focused support modules, keep call sites behavior-equivalent, and prove the
split with pre/post `wc -l`. `visible-review-content-hydration.ts` is 985
lines at committed `HEAD`; this slice is the first listed slice that touches
it, so it owns the split/dissolution work. Do not grow it past 1000 lines. D
and G may only wire through the extracted helpers; they must not add logic to
the 985-line file before B's split lands.

Red patch first:

Add/modify these assertions and files only, run the command below, and record
the expected failure. Do not edit production until the red failure is observed.

- In `BridgeWeb/src/review-viewer/content/visible-review-content-hydration.unit.test.ts`,
  add `keeps cache landing immediate while deferring non-selected DOM apply
  during scroll momentum`.
- In `BridgeWeb/src/review-viewer/content/visible-review-content-hydration.unit.test.ts`,
  add `delegates scroll apply decisions through extracted hydration helpers`.
- In `BridgeWeb/src/review-viewer/code-view/bridge-code-view-materialization.hydration.unit.test.ts`,
  add `preserves placeholder height while materialization is skipped before
  materialize`.
- In `BridgeWeb/src/review-viewer/trees/bridge-trees-panel.unit.test.ts`, add
  `coalesces rendered-window publication to one requestAnimationFrame per
  scroll burst`.
- In `BridgeWeb/src/app/bridge-pierre-tree-adapter.unit.test.ts`, add
  `uses append and patch updates for projection deltas and reserves setItems
  for source reset`.
- Create
  `scripts/verify-bridge-review-momentum-scroll-state-probe.sh` with a dry-run
  red assertion named `momentum scroll state probe requires live debug marker`.
- Add `.mise.toml` task `verify-bridge-review-momentum-scroll-state-probe`
  pointing at that script; the red run must fail because the verifier and live
  marker are not implemented yet.

Red-first proof:

```bash
wc -l BridgeWeb/src/review-viewer/content/visible-review-content-hydration.ts
pnpm --dir BridgeWeb exec vitest run src/review-viewer/trees/bridge-trees-panel.unit.test.ts src/app/bridge-pierre-tree-adapter.unit.test.ts src/review-viewer/code-view/bridge-code-view-materialization.unit.test.ts src/review-viewer/code-view/bridge-code-view-materialization.hydration.unit.test.ts src/review-viewer/content/visible-review-content-hydration.unit.test.ts
pnpm --dir BridgeWeb exec vitest --config vitest.browser.config.ts run --project integration-browser src/review-viewer/test-support/bridge-viewer-browser.integration-scroll.browser.test.tsx src/review-viewer/test-support/bridge-viewer-browser.virtualizer.browser.test.tsx src/review-viewer/content/visible-review-content-hydration.browser.test.tsx
mise run verify-bridge-review-momentum-scroll-state-probe
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
mise run verify-bridge-review-momentum-scroll-state-probe
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
- Momentum probe script proves, on a live debug app, that
  `truncatedVisibleItemCount == 0` and `untrackedItemCount` drains to 0 after
  bounded settle.

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

Red patch first:

Add/modify these assertions only, run the command below, and record the expected
failure. Do not edit production until the red failure is observed.

- In `BridgeWeb/src/review-viewer/state/review-viewer-store.unit.test.ts`, add
  `selection subscribers observe only selection slice and selected row paint
  slice`.
- In `BridgeWeb/src/app/bridge-app-review-metadata-package.scaling.unit.test.ts`,
  add `single selection invalidates selected plus visible delta not package
  size`.
- In `BridgeWeb/src/app/bridge-app-review-selection-controller.unit.test.ts`,
  add `selection interaction cannot subscribe to review root snapshot`.
- In `BridgeWeb/src/app/bridge-app.unit.test.ts`, add `review interaction path
  keeps protocol state out of FE render slices`.
- In
  `BridgeWeb/src/review-viewer/test-support/bridge-viewer-browser.integration-large.browser.test.tsx`,
  add `large package click reports bounded subscriber and invalidated key
  counts`.

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

Red patch first:

Add/modify these assertions only, run the command below, and record the expected
failure. Do not edit production until the red failure is observed.

- In
  `BridgeWeb/src/review-viewer/code-view/bridge-code-view-materialization.unit.test.ts`,
  add `seeds apply pump budget from time-sliced materialization policy`.
- In
  `BridgeWeb/src/review-viewer/content/visible-review-content-hydration.unit.test.ts`,
  add `selected unit receives the first pump slot before visible
  non-selected work`.
- In
  `BridgeWeb/src/review-viewer/content/visible-review-content-hydration.unit.test.ts`,
  add `visible non-selected work makes bounded progress under selected churn`.
- Create `BridgeWeb/src/core/rendering/bridge-frame-apply-pump.unit.test.ts`
  with `drops stale pending apply units within the policy scan cap`.
- In `Tests/AgentStudioTests/Features/Bridge/AppPoliciesBridgeTests.swift`,
  add `bridgeApplyPumpPolicyMatchesBridgeWebMirror`.
- D may wire only through B's extracted helpers and the committed hotfix
  materialization primitives; it must not reimplement identity stability,
  skip-before-materialize, or time-sliced materialization in parallel.

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

Red patch first:

Add/modify these assertions only, run the command below, and record the expected
failure. Do not edit production until the red failure is observed.

- In `BridgeWeb/src/file-viewer/bridge-file-viewer-source-structure.unit.test.ts`,
  add `prunes empty directory rows with bounded map lookups not nested full
  scans`.
- In `BridgeWeb/src/file-viewer/bridge-file-viewer-app.unit.test.ts`, add
  `frame intake yields projection replay and open-file reconciliation across
  pump ticks`.
- In `BridgeWeb/src/file-viewer/state/bridge-file-viewer-store.unit.test.ts`,
  add `interaction subscribers do not observe root snapshot state`.
- In
  `BridgeWeb/src/worktree-file-surface/worktree-file-surface-runtime.demand.integration-suite.ts`,
  add `file view demand intake publishes apply units through the shared pump`.
- In `BridgeWeb/src/file-viewer/bridge-file-viewer-app.browser.test.tsx`, add
  `large file tree remains responsive while frames are chunked`.

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

Split the worker-fetch gate into a static diagnostic shell (F0) and a native
observability proof (F1). Until F1 passes, no slice may treat
`bridgePierreWorkerContentFetchProbeResult` or Pierre worker descriptor fetch as
production proof; plaintext fallback remains intact.

### F0 - Diagnostic Action And Verifier Shell

Objective:

Add the startup diagnostic enum/action, launcher trace-tag allowance, verifier
script, and static/dry-run tests without launching the debug app.

Files touched:

- `BridgeWeb/src/bridge/bridge-resource-url.ts`
- `BridgeWeb/src/bridge/bridge-resource-url.unit.test.ts`
- Existing or new worker probe under `BridgeWeb/src/review-viewer/workers/`
  or `BridgeWeb/src/core/bridge-host/`.
- Startup diagnostic hook files under `Sources/AgentStudio/App/Boot/`.
- `scripts/run-debug-observability.sh`
- `scripts/verify-bridge-worker-fetch-scheme-smoke.sh`
- `.mise.toml`
- `Tests/AgentStudioTests/Features/Bridge/BridgeWebKitSpikeTests.swift`
- `Tests/AgentStudioTests/Features/Bridge/WebKitSerializedTests.swift`

Red patch first:

Create or modify these tests/files only, run the command below, and record the
expected failure. Do not edit production until the red failure is observed.

- In `Tests/AgentStudioTests/App/AgentStudioStartupDiagnosticActionTests.swift`,
  add `startup diagnostic action parses bridge worker fetch scheme smoke
  command`.
- In `Tests/AgentStudioTests/Scripts/ObservabilityDebugLaunchScriptsTests.swift`,
  add `debug launcher allows bridge worker fetch scheme smoke trace tags`.
- Create
  `Tests/AgentStudioTests/Scripts/BridgeWorkerFetchSchemeSmokeScriptTests.swift`
  with `worker fetch scheme smoke verifier requires worker fetch marker and
  byte observation`.
- In `scripts/verify-bridge-worker-fetch-scheme-smoke.sh`, add a dry-run
  assertion path that emits `requires worker fetch marker and byte observation`.
- In `BridgeWeb/src/bridge/bridge-resource-url.unit.test.ts`, add
  `builds worker fetch probe URL without raw filesystem path leakage`.
- Add `.mise.toml` task `verify-bridge-worker-fetch-scheme-smoke` pointing at
  the verifier script.

Red-first proof:

```bash
CI=true mise run test -- --filter "WebKitSerializedTests|BridgeWebKitSpikeTests|BridgeWorkerFetchStartupDiagnosticTests"
bash scripts/verify-bridge-worker-fetch-scheme-smoke.sh --dry-run
mise run verify-bridge-worker-fetch-scheme-smoke -- --dry-run
```

Expected failure before implementation:

- No `AgentStudioStartupDiagnosticAction` case exists for
  `bridge-worker-fetch-scheme-smoke`.
- `run-debug-observability.sh` does not admit the diagnostic action/trace tags.
- The verifier script and `.mise.toml` task do not exist.
- Probe URL tests cannot prove safe scheme URL construction.

Green proof:

```bash
CI=true mise run test -- --filter "WebKitSerializedTests|BridgeWebKitSpikeTests|BridgeWorkerFetchStartupDiagnosticTests"
bash scripts/verify-bridge-worker-fetch-scheme-smoke.sh --dry-run
mise run verify-bridge-worker-fetch-scheme-smoke -- --dry-run
```

### F1 - Native WKWebView Worker-Fetch Proof

Objective:

After F0 is green, prove in a real debug app that a Web Worker can `fetch()`
through the registered content `WKURLSchemeHandler`. This is a blocking gate
for G. If it fails, record a fallback decision: page-fetch-and-transfer while
preserving R44 worker byte/cache/retry ownership, or stop and revise R44.

Files touched:

- `Sources/AgentStudio/Features/Bridge/Transport/BridgeSchemeHandler.swift`
- `Tests/AgentStudioTests/Features/Bridge/BridgeSchemeHandlerTests.swift`
- F0 verifier/probe files only if native proof reveals a verifier gap.

Red patch first:

Add/modify these assertions only, run the command below, and record the expected
failure. Do not edit production until the red failure is observed.

- In `Tests/AgentStudioTests/Features/Bridge/BridgeSchemeHandlerTests.swift`,
  add `workerFetchSchemeProbeServesBytesWithContentAdmission`.
- In `scripts/verify-bridge-worker-fetch-scheme-smoke.sh`, add live assertions
  `worker fetch marker exists`, `scheme handler served worker request`, and
  `worker observed returned byte count`.
- Add verifier failure text that distinguishes collector/setup/action-missing
  failures from a real WebKit worker-fetch failure.

Red-first proof:

```bash
CI=true mise run test -- --filter "BridgeSchemeHandlerTests"
mise run observability:up
AGENTSTUDIO_IPC_UNSAFE_NO_AUTH=1 AGENTSTUDIO_IPC_DEBUG_TOKEN_ESCROW=1 AGENTSTUDIO_STARTUP_DIAGNOSTIC_ACTION=bridge-worker-fetch-scheme-smoke AGENTSTUDIO_TRACE_TAGS="app.startup,performance,bridge.performance.*" mise run run-debug-observability -- --detach
mise run verify-debug-observability
mise run verify-bridge-worker-fetch-scheme-smoke
```

Expected failure before implementation:

- No native debug-app startup diagnostic proves worker custom-scheme fetch.
- No verifier can prove worker-originated `fetch(agentstudio://resource/...)`
  reaches `BridgeSchemeHandler` and returns bytes.
- If the debug proof exists but fails with WebKit delivery/registration error,
  G must remain blocked.

Green proof:

```bash
CI=true mise run test -- --filter "BridgeSchemeHandlerTests"
mise run observability:up
AGENTSTUDIO_IPC_UNSAFE_NO_AUTH=1 AGENTSTUDIO_IPC_DEBUG_TOKEN_ESCROW=1 AGENTSTUDIO_STARTUP_DIAGNOSTIC_ACTION=bridge-worker-fetch-scheme-smoke AGENTSTUDIO_TRACE_TAGS="app.startup,performance,bridge.performance.*" mise run run-debug-observability -- --detach
mise run verify-debug-observability
mise run verify-bridge-worker-fetch-scheme-smoke
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

- F0 green is mandatory before F1.
- F1 red/green launches must run `mise run observability:up` before the debug
  app, so collector/action setup noise cannot masquerade as worker-fetch proof.
- Depends on A only if verifier telemetry uses the dedicated endpoint.
- Blocks all G content-byte streaming cutovers and any production proof claim
  based on `bridgePierreWorkerContentFetchProbeResult` or Pierre worker
  descriptor fetch.

Lane boundary:

- Native WebKit proof writer owns Swift tests/diagnostic/verifier script.
- BridgeWeb worker-probe writer owns only probe code and unit tests.

## Slice G - Comm-Worker Migration Units

Objective:

Move protocol truth, cache truth, queue/executor truth, telemetry batching, and
Swift synchronization into a comm worker. FE keeps zero protocol state. This is
not one PR unless a reviewer accepts the blast radius; use per-viewer/protocol
compile-enforced cutover units. The normative channel contract is the spec's
`Channel Topology And Typed Contracts`: G must use `BridgeWorkerContracts` for
the typed main <-> server-worker schema; all Swift communication after the
one-shot page-load bootstrap must use scheme-fetch request/response RPC plus
long-lived streamed-fetch push; Pierre's own API is the only Pierre edge; and
the listed forbidden edges are source-scanned. G1 is an inert typed shell only;
production ownership moves only in later cutover units with deletion sets.

Files touched by the shared worker core:

- New comm-worker modules under `BridgeWeb/src/core/comm-worker/`, for example:
  `bridge-comm-worker-entry.ts`, `bridge-comm-worker-client.ts`,
  `bridge-worker-contracts.ts`, `bridge-comm-worker-protocol.ts`,
  `bridge-comm-worker-cache.ts`, `bridge-comm-worker-reconciler.ts`,
  `bridge-comm-worker-executor.ts`, `bridge-comm-worker-telemetry.ts`, and
  hostile server test support.
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

Objective:

Create an inert typed shell: `BridgeWorkerContracts`, version fences, validation
types, and a non-owning client/worker harness. G1 must not own production
protocol/cache/queue/telemetry state and must not claim R41-R48 proof. It can
compile and unit-test typed messages only.

Red patch first:

Create the missing test files first, run the command below, and record the
expected failure from missing implementation. Do not edit production until the
red failure is observed.

- Create `BridgeWeb/src/core/comm-worker/bridge-worker-contracts.unit.test.ts`
  with `rejects untyped main to server worker messages at schema boundary`.
- Create `BridgeWeb/src/core/comm-worker/bridge-comm-worker-protocol.unit.test.ts`
  with `encodes select viewport hover markViewed and mode commands through
  BridgeWorkerContracts`.
- Create `BridgeWeb/src/core/comm-worker/bridge-comm-worker-client.unit.test.ts`
  with `does not issue Swift fetch telemetry or demand side effects from the
  inert shell`.
- Create
  `BridgeWeb/src/core/comm-worker/bridge-comm-worker-hostile-server.unit.test.ts`
  with `drops duplicate reorder stale and never resolving replies without FE
  protocol ownership`.

Red-first proof:

```bash
pnpm --dir BridgeWeb exec vitest run src/core/comm-worker/bridge-worker-contracts.unit.test.ts src/core/comm-worker/bridge-comm-worker-protocol.unit.test.ts src/core/comm-worker/bridge-comm-worker-client.unit.test.ts src/core/comm-worker/bridge-comm-worker-hostile-server.unit.test.ts
pnpm --dir BridgeWeb exec tsc --noEmit
```

Expected failure before implementation: test files compile against missing
`BridgeWorkerContracts` and inert shell modules. The red failure is missing
typed shell implementation, not hostile-worker production ownership.

Green proof:

```bash
pnpm --dir BridgeWeb exec vitest run src/core/comm-worker/bridge-worker-contracts.unit.test.ts src/core/comm-worker/bridge-comm-worker-protocol.unit.test.ts src/core/comm-worker/bridge-comm-worker-client.unit.test.ts src/core/comm-worker/bridge-comm-worker-hostile-server.unit.test.ts
pnpm --dir BridgeWeb exec tsc --noEmit
```

Deletes: none. G1 is compile-only scaffolding and must leave all production
ownership where it was.

### G2 - Telemetry Transport Cutover

Red patch first:

Create or modify these assertions only, run the command below, and record the
expected failure. Do not edit production until the red failure is observed.

- Create
  `BridgeWeb/src/core/comm-worker/bridge-comm-worker-telemetry.unit.test.ts`
  with `batches telemetry through worker buffer and dedicated scheme post`.
- In `BridgeWeb/src/foundation/telemetry/bridge-telemetry-recorder.unit.test.ts`,
  add `main recorder hands samples to worker telemetry client without owning
  flush order`.
- In `Tests/AgentStudioTests/Features/Bridge/RPCRouterTelemetryTests.swift`,
  add `productionSystemBridgeTelemetryRouteIsCompileDead`.
- In
  `Tests/AgentStudioTests/Features/Bridge/BridgeTelemetryBatchValidatorTests.swift`,
  add `workerTelemetryPostPreservesSequenceAndDropCounters`.

Red-first proof:

```bash
pnpm --dir BridgeWeb exec vitest run src/core/comm-worker/bridge-comm-worker-telemetry.unit.test.ts src/foundation/telemetry/bridge-telemetry-recorder.unit.test.ts
mise run test -- --filter "RPCRouterTelemetryTests|BridgeTelemetryBatchValidatorTests"
```

Expected failure before implementation: telemetry batching still lives on the
main-thread telemetry path or interactive RPC route instead of the worker-owned
dedicated telemetry transport.

Green proof:

```bash
pnpm --dir BridgeWeb exec vitest run src/core/comm-worker/bridge-comm-worker-telemetry.unit.test.ts src/foundation/telemetry/bridge-telemetry-recorder.unit.test.ts
mise run test -- --filter "RPCRouterTelemetryTests|BridgeTelemetryBatchValidatorTests"
pnpm --dir BridgeWeb exec tsc --noEmit
```

Compile-enforced deletion set: telemetry transport.

- Interactive RPC telemetry send/force-flush path.
- Shared-command-queue telemetry.
- Any production `system.bridgeTelemetry` route.
- Main-thread telemetry flush-order ownership for converted telemetry.

### G3 - Review Content Protocol Cutover

Red patch first:

Create or modify these assertions only, run the command below, and record the
expected failure. Do not edit production until the red failure is observed.

- In `BridgeWeb/src/review-viewer/content/review-content-demand-loader.unit.test.ts`,
  add `review content loader receives worker paint-ready slices instead of
  package-first bodies`.
- In `BridgeWeb/src/review-viewer/content/visible-review-content-hydration.unit.test.ts`,
  add `review hydration wires only through B extracted helpers for worker
  slices`.
- In `BridgeWeb/src/review-viewer/state/review-viewer-store.unit.test.ts`, add
  `review FE store rejects generation sequence staleness and cache membership
  truth`.
- In `BridgeWeb/src/app/bridge-app-review-selection-controller.unit.test.ts`,
  add `selection path cannot start FE content retry or parking`.
- In
  `BridgeWeb/src/review-viewer/test-support/bridge-viewer-browser.integration.browser.test.tsx`,
  add `review content paints from worker slice without package-first body load`.

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
- Any direct logic added to `visible-review-content-hydration.ts`; G3 may wire
  only through B's extracted helpers.

### G4 - File Viewer Content Protocol Cutover

Red patch first:

Create or modify these assertions only, run the command below, and record the
expected failure. Do not edit production until the red failure is observed.

- In `BridgeWeb/src/file-viewer/bridge-file-viewer-app.unit.test.ts`, add
  `file view receives worker paint-ready frames instead of raw body package
  intake`.
- In `BridgeWeb/src/file-viewer/state/bridge-file-viewer-store.unit.test.ts`,
  add `file view FE store rejects generation sequence staleness and retry
  ownership`.
- In
  `BridgeWeb/src/worktree-file-surface/worktree-file-surface-runtime.demand.integration-suite.ts`,
  add `file view demand protocol is worker owned for converted surfaces`.
- In `BridgeWeb/src/file-viewer/bridge-file-viewer-app.browser.test.tsx`, add
  `file view browser path has no dual reader for converted protocol surface`.

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

### G5 - Demand Membership Cutover

Red patch first:

Create or modify these assertions only, run the command below, and record the
expected failure. Do not edit production until the red failure is observed.

- Create
  `BridgeWeb/src/core/comm-worker/bridge-comm-worker-reconciler.unit.test.ts`
  with `worker owns demand membership without membership caps or parked retry
  versions`.
- Create
  `BridgeWeb/src/core/comm-worker/bridge-comm-worker-executor.unit.test.ts`
  with `worker executor applies pacing and backoff without becoming membership
  truth`.
- In `BridgeWeb/src/core/demand/bridge-content-demand-reconciler.unit.test.ts`,
  add `main demand reconciler is compile-dead for converted surfaces`.
- In `BridgeWeb/src/core/demand/bridge-resource-executor.unit.test.ts`, add
  `main resource executor cannot retain converted demand membership`.

Red-first proof:

```bash
pnpm --dir BridgeWeb exec vitest run src/core/comm-worker/bridge-comm-worker-reconciler.unit.test.ts src/core/comm-worker/bridge-comm-worker-executor.unit.test.ts src/core/demand/bridge-content-demand-reconciler.unit.test.ts src/core/demand/bridge-resource-executor.unit.test.ts
pnpm --dir BridgeWeb exec tsc --noEmit
```

Expected failure before implementation: demand membership still lives in
legacy staging buffers, pending eviction, parked retry versions, or
main-thread demand modules for converted surfaces.

Green proof:

```bash
pnpm --dir BridgeWeb exec vitest run src/core/comm-worker/bridge-comm-worker-reconciler.unit.test.ts src/core/comm-worker/bridge-comm-worker-executor.unit.test.ts src/core/demand/bridge-content-demand-reconciler.unit.test.ts src/core/demand/bridge-resource-executor.unit.test.ts src/review-viewer/workers/pierre/bridge-pierre-worker-pool.rank.unit.test.ts
pnpm --dir BridgeWeb exec tsc --noEmit
```

Compile-enforced deletion set: demand membership.

- Legacy staging buffers for converted surfaces.
- Membership caps.
- Pending eviction as membership policy.
- Parked retry versions.
- Main-thread membership truth in demand/resource executor modules for
  converted surfaces.

Keep only worker reconciler membership and executor-stage pacing/backoff.

### G6 - Final Browser/Native RPC Cutover And Live Proof

Red patch first:

Create or modify these assertions only, run the command below, and record the
expected failure. Do not edit production until the red failure is observed.

- Create
  `Tests/AgentStudioTests/Features/Bridge/BridgeCommWorkerServerSeamRecordedTrafficTests.swift`
  with
  `server seam replays worker scheme fetch request response and streamed push`.
- In
  `Tests/AgentStudioTests/Features/Bridge/BridgeCommWorkerServerSeamRecordedTrafficTests.swift`,
  add
  `converted surfaces reject reset unhealthy and stale source traffic without
  FE protocol ownership`.
- In `Tests/AgentStudioTests/Features/Bridge/RPCRouterTelemetryTests.swift`,
  add `no production telemetry route remains on interactive RPC`.
- Create
  `Tests/AgentStudioTests/Features/Bridge/BridgeBrowserNativeRPCCutoverSourceScanTests.swift`
  with `old demand telemetry and content paths are compile-dead for converted
  surfaces`.
- In
  `Tests/AgentStudioTests/Features/Bridge/BridgeBrowserNativeRPCCutoverSourceScanTests.swift`,
  add `script message RPC plane is compile-dead except one shot page load
  bootstrap`.

Red-first proof:

```bash
mise run test -- --filter "BridgeSchemeHandler|BridgeContentDemandAdmission|BridgeReviewContentStreamTransport|BridgeWorktreeFileSurfaceDemandTransport|BridgeCommWorkerServerSeamRecordedTrafficTests|BridgeBrowserNativeRPCCutoverSourceScanTests|RPCRouterTelemetryTests|BridgeTelemetryBatchValidatorTests"
pnpm --dir BridgeWeb exec tsc --noEmit
```

Expected failure before implementation: Swift tests do not yet replay recorded
worker traffic for content scheme serving, telemetry POST admission,
`BridgeContentDemandAdmission`, reset/unhealthy responses, and source authority
for converted surfaces; source scans still find ordinary command, telemetry,
content, subscription, or push traffic using the script-message RPC plane.

Green proof:

```bash
mise run test -- --filter "BridgeSchemeHandler|BridgeContentDemandAdmission|BridgeReviewContentStreamTransport|BridgeWorktreeFileSurfaceDemandTransport|BridgeCommWorkerServerSeamRecordedTrafficTests|BridgeBrowserNativeRPCCutoverSourceScanTests|RPCRouterTelemetryTests|BridgeTelemetryBatchValidatorTests|AgentStudioOTLP"
pnpm --dir BridgeWeb exec tsc --noEmit
```

Compile-enforced deletion set: final browser/native RPC cutover
(`WKScriptMessage` / `__bridge_command` script-message plane).

- Ordinary command, telemetry, content, subscription, push, and ack traffic over
  `WKScriptMessage`, `__bridge_command`, content-world command listeners, nonce
  command dispatch, `RPCMessageHandler`, `RPCRouter`, or script-message ingress.
- Any main-thread Swift client that bypasses scheme-fetch RPC after page-load
  identity bootstrap.
- Any Swift push path that bypasses long-lived streamed-fetch responses.

Keep only:

- The minimal one-shot page-load bootstrap handshake before `fetch()` is
  possible.
- Scheme-fetch typed POST request/response RPC and long-lived streamed-fetch push
  for all ordinary Swift communication.

Also delete:

- `system.bridgeTelemetry` production route if any remains.
- Handler-splitting comments or tests that claim WebKit IPC isolation.
- FE server lifetime/protocol state visible to the user.
- Any old content-demand path for converted surfaces.

Dependencies:

- F1 green proof is mandatory before any R44 worker-fetch cutover.
- G2, G3, G4, and G5 can be separate PRs only if each has its own
  compile-enforced old-path deletion for that unit.

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
| R42 every datum has one truth owner | C, G1-G6 | FE zero protocol state source scans; inert typed shell tests; per-cutover deletion scans for telemetry transport, Review content protocol, File View content protocol, demand membership, and final browser/native RPC cutover |
| R43 telemetry dedicated lane | A, G2/G6 | Browser telemetry sink/buffer/recorder tests; worker telemetry tests; `BridgeSchemeHandler` telemetry POST tests; `RPCRouterTelemetryTests` proving old RPC route removed or production-dead |
| R44 content bytes stream to worker | F1, G3-G6 | Native worker-fetch smoke; Review/File View browser tests showing FE gets paint-ready structures only; server seam recorded worker traffic tests |
| R45 FE render store sliced | C | Store unit tests; large browser fixture subscriber/invalidation counters bounded by selected + visible delta |
| R46 main-thread apply pump | D, B, E | Pump unit tests; policy tests; browser scroll proof; no-starvation/stale-drop counters |
| R47 File View projection/pruning parity | E, G4 | File View unit/browser tests; O(N^2) prune regression test; chunked/yielding apply counters |
| R48 proof seams match boundaries | A-G | FE hostile fake worker tests; worker hostile mock server tests; Swift recorded worker traffic tests; native WKWebView gates; Victoria proof |
| PHASE 2 telemetry shared-channel compounding | A | `bridge-rpc-client` no-force-flush test; dedicated scheme endpoint tests; no-interactive-contention test |
| PHASE 2 560ms click floor | C, D, live gates | O(selected + visible delta) invalidation proof; apply pump counters; VictoriaMetrics improvement vs 560ms baseline |
| PHASE 2 severe freezes | D, E, live gates | Apply pump tests; File View chunk/prune tests; Victoria/Momentum proof showing 1.5s choke gone and no severe apply stalls |
| PHASE 2 R32 dormant / multi-authority | G5-G6 | Comm-worker reconciler/executor tests; FE protocol-state deletion scans; source scans for old authorities |
| Channel Topology And Typed Contracts | G1-G6 | `BridgeWorkerContracts` tests; scheme-fetch RPC plus streamed-push server seam tests; final script-message deletion source scans; forbidden-edge source scans |
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
- Worker custom-scheme fetch is not assumed; F1 is a blocking live gate.

## Session Phase And Timer Gate Annex

No wall-clock, frame, rAF, idle, settle, timeout, or streamed-response gate may
execute unless it has a row here.

| Gate | Phase | Trigger | Release condition | Instrument | Failure rule |
| --- | --- | --- | --- | --- | --- |
| B hydration split line cap | Pre-behavior extraction | Slice B starts before production behavior | Pre/post `wc -l` proves `visible-review-content-hydration.ts` shrank or stayed under cap after helper extraction | `wc -l BridgeWeb/src/review-viewer/content/visible-review-content-hydration.ts` | Stop before behavior edits if the split is not behavior-neutral or the file grows past 1000 lines |
| B rendered-window rAF coalescing | Scroll momentum | Scroll burst publishes rendered-window facts | At most one publication per animation frame while moving | Tree panel unit/browser counters | Fail if any scroll event path publishes directly outside the coalescer |
| B scroll-active non-selected apply hold | Scroll momentum | Non-selected CodeView content becomes ready while momentum continues | Cache lands immediately; DOM/Pierre apply releases only at idle or bounded rAF budget | Hydration/materialization unit tests and scroll browser proof | Fail if non-selected ready content applies synchronously during momentum |
| B momentum-scroll live probe | Live debug scroll settle | Debug app runs Review momentum-scroll scenario | `truncatedVisibleItemCount == 0` and `untrackedItemCount` drains to 0 after bounded settle | `mise run verify-bridge-review-momentum-scroll-state-probe` / `scripts/verify-bridge-review-momentum-scroll-state-probe.sh` | Fail if the probe is missing, not wired in `.mise.toml`, or relies on unbounded sleep |
| D R46 apply pump budget | Frame apply | Selected or visible apply units enter the pump | Selected unit receives first slot; visible non-selected units make bounded progress under policy-owned budget | Pump tests, hydration tests, AppPolicies mirror tests | Fail if budget literals are duplicated, starvation is possible, or stale scan cap is unbounded |
| E File View frame/parity pump | File View frame intake | Large frame/projection/replay/open-file work arrives | Work yields across policy pump ticks and preserves interaction responsiveness | File View unit/browser tests | Fail if any converted File View path performs unbounded synchronous apply/projection |
| F1 worker-fetch native debug launch | Native proof | `observability:up` is healthy and F0 diagnostic action exists | Worker-originated scheme fetch marker, scheme handler served request, worker-observed byte count | `mise run verify-debug-observability`; `scripts/verify-bridge-worker-fetch-scheme-smoke.sh` | Fail distinctly for collector/action setup noise; block G cutovers on WebKit delivery failure |
| G streamed-push worker channel | Worker/server cutover | Swift sends push/fact/content/failure/reconnect traffic | Server worker validates stream/epoch/sequence and publishes O(delta) slices | Recorded worker traffic tests and browser slice tests | Fail if main becomes a verbatim Swift relay or any untyped message crosses the channel |
| G final browser/native RPC cutover | Final network-boundary cutover | Any ordinary Swift communication after page-load bootstrap | Scheme-fetch typed POST/stream RPC is the only live Swift communication path; page-load bootstrap remains one-shot only | `BridgeBrowserNativeRPCCutoverSourceScanTests`; source scans for `WKScriptMessage`, `__bridge_command`, `RPCMessageHandler`, `RPCRouter`, and content-world command listeners | Fail if script-message ordinary command, telemetry, content, subscription, push, or ack traffic remains live |
| Final debug Review smoke | Live debug app | `bridge-review-observability-smoke` launches | Victoria marker verifies launch; Review journey verifier passes | `mise run verify-debug-observability`; `mise run verify-bridge-review-journey-smoke` | Fail if marker is stale, LaunchServices/debug app is already running, or verifier cannot bind to the current marker |
| Final debug Review-to-File smoke | Live debug app | `bridge-review-to-file-view-observability-smoke` launches | Victoria marker verifies launch; mode-idle verifier passes | `mise run verify-debug-observability`; `mise run verify-bridge-mode-idle-smoke` | Fail if a stale marker or wrong app identity satisfies the gate |
| VictoriaMetrics improvement | Performance proof | A-E and required G cutovers are green | Metrics improve against measured baseline with non-lossy required telemetry streams | VictoriaMetrics queries from repo verifiers | Fail if required streams shed samples or the baseline comparison is missing |

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

Before the final G browser/native RPC cutover PR is ready:

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
- Ordinary Swift communication no longer uses the `WKScriptMessage` /
  `__bridge_command` script-message RPC plane; only the minimal one-shot
  page-load bootstrap exemption remains.
- No compatibility shim, feature flag, or dual reader keeps old and new paths
  live for one converted viewer/protocol surface.

Required source scans:

```bash
rg -n "flush\\(\\{ force: true \\}\\)|system\\.bridgeTelemetry|BridgeTelemetryEventSink|bridgeTelemetryBatchAdmissionPriority" BridgeWeb/src Sources/AgentStudio Tests
rg -n "streamId|sourceGeneration|generation|sequence|staleness|retryAfterVersion|cacheMembership|demandMembership" BridgeWeb/src/app BridgeWeb/src/review-viewer BridgeWeb/src/file-viewer
rg -n "setItems\\(|applyItemUpdate|getRenderedItems|visibleContentHydrationItemLimit|reviewContentPrefetch|useBridgeReviewContentPrefetchController" BridgeWeb/src
rg -n "pruneEmptyWorktreeFileTreeDirectories|for \\(const \\[path, treeRow\\].*treeRowsByPath\\)|for \\(const candidate of treeRowsByPath\\.values\\(\\)\\)" BridgeWeb/src/file-viewer
rg -n "__bridge_command|WKScriptMessage|RPCMessageHandler|BridgeBootstrap|content-world command|bridge-content-world-rpc|RPCRouter" BridgeWeb/src Sources/AgentStudio Tests
```

Expected green scan results:

- Matches are either deleted, production-dead tests asserting absence, the
  minimal one-shot page-load bootstrap exemption, or explicitly
  server/worker-owned vocabulary. FE converted surfaces must not own protocol
  truth, and the script-message RPC plane must not carry ordinary Swift
  communication.

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
    F0 static/dry-run tests, `mise run observability:up`,
    `AGENTSTUDIO_STARTUP_DIAGNOSTIC_ACTION=bridge-worker-fetch-scheme-smoke`,
    `mise run verify-debug-observability`, and
    `mise run verify-bridge-worker-fetch-scheme-smoke`.
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

13. No wall-clock, frame/timer, rAF, idle, settle, timeout, or
    streamed-response gate executes unless it has a row in the
    `Session Phase And Timer Gate Annex`.
14. Momentum-scroll probe runner passes. It must prove, on a live debug app,
    that `truncatedVisibleItemCount == 0` and `untrackedItemCount` drains to 0
    after bounded settle:

```bash
mise run verify-bridge-review-momentum-scroll-state-probe
```

15. VictoriaMetrics evidence compares against measured baselines and shows:
    the 560ms click commit floor is gone, the 1.5s RPC dispatch choke is gone,
    required telemetry streams are non-lossy, and click-to-paint improves
    against the baseline artifact.
16. User confirms the Review momentum-scroll UX no longer leaves visible items
    stuck as placeholders and click-to-visible-content feels responsive.
17. Source scans show old protocol/demand/telemetry paths and ordinary
    script-message RPC paths are gone or compile-dead for converted surfaces.
18. Every touched TS/TSX file over 800 lines has pre/post `wc -l` proof, and no
    TS/TSX file exceeds 1000 lines.
19. If any telemetry attribute is added, OTLP projection and telemetry validator
    tests were red-first and then green, with unsafe data scrubbed.
20. `implementation-review-swarm` reviews the final diff before merge.

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
