# Unified Content Demand Queue Implementation Plan

Date: 2026-07-04
goal_id: 2026-07-04-bridge-scroll-demand-queue

## Goal

Land one PR that hard-cuts BridgeWeb content demand to the unified reconciler
contract. The PR deletes the legacy browser demand scheduler, visible hydration
membership/retry parking, the review content prefetch pump, executor membership
truncation, and every compatibility residue that could keep a second demand
path alive. It must be executable slice-by-slice, but it lands as one greenfield
cutover: no dual demand paths, no dormant adapter, no `retryAfterVersion`.

## Context Summary

Normative source:

- `docs/specs/bridge-viewer-transport/performance-demand-lanes.md`, especially
  "Unified Content Demand Queue (Reconciler Contract)" and R20-R40. Source
  coverage checked: 1091 lines.
- `tmp/debug-workflows/2026-07-04-agent-studio-luna338-scroll-placeholder-survivor/debug-investigation.md`.
  Source coverage checked: 142 lines. The current root cause is 12-cap
  membership truncation: rendered items beyond `visibleContentHydrationItemLimit`
  are never demanded, emit no telemetry, and can be pruned back to placeholders.
- `docs/wip/2026-07-04-cold-architecture-review-bridge-demand-system.md`.
  Source coverage checked: 106 lines. The plan must not regress wedge classes
  W1-W6, especially W6: non-foreground starvation and parked retry states.

Live code anchors read for planning:

- Delete target: `BridgeWeb/src/core/demand/bridge-demand-scheduler.ts`.
- Keep core, remove membership drops: `BridgeWeb/src/core/demand/bridge-resource-executor.ts`.
- Delete membership/retry logic, keep result/probe/prune helpers:
  `BridgeWeb/src/review-viewer/content/visible-review-content-hydration.ts`
  and `BridgeWeb/src/review-viewer/content/visible-review-content-hydration-support.ts`.
- Delete targets:
  `BridgeWeb/src/app/bridge-app-review-content-prefetch-controller.ts`,
  `BridgeWeb/src/review-viewer/content/review-content-prefetch-policy.ts`,
  and legacy demand-policy responsibilities in
  `BridgeWeb/src/review-viewer/content/review-content-demand-policy.ts`.
- Reconciler derivation seeds:
  `BridgeWeb/src/features/review/demand/review-demand-policy.ts` and
  `BridgeWeb/src/features/worktree-file/demand/worktree-file-demand-policy.ts`.
- Keep serving-side valve:
  `Sources/AgentStudio/Features/Bridge/Transport/BridgeContentDemandAdmission.swift`.
- Fix R40 defect:
  `Sources/AgentStudio/Infrastructure/AppPolicies.swift` currently sets both
  `contentCacheMaxBytes` and `contentMaxBytesPerItem` to 50 MB.

Planning-lane note: no subagents were spawned because the available subagent
tool requires explicit delegation permission. The lane analysis is embedded
here. Reasoning-effort policy for execution lanes: use high effort for slices
1-5 and medium effort for slice 6 closeout proof.

Security context: applicable, bounded. The work touches descriptor-backed
content fetches and telemetry projection. Do not add raw paths, item ids, URLs,
content hashes, payload text, or raw errors to telemetry. Any new telemetry
attribute must first fail a red projection/validator test and then be added to
`Sources/AgentStudio/Infrastructure/Diagnostics/AgentStudioOTLPTraceProjection.swift`
and `Sources/AgentStudio/Features/Bridge/Runtime/Telemetry/BridgeTelemetryBatchValidator+Allowlists.swift`.

## Execution DAG

```text
gate 0: re-read spec/debug/audit anchors and confirm no pre-existing target plan
  |
slice 1: red survivor proof against the real visible hydration seam
  |
slice 2: reconciler and pure derivations, still using the existing executor
  |
slice 3: unified queue/executor cutover and legacy scheduler deletion
  |
slice 4: background tier integration and prefetch-pump deletion
  |
slice 5: worker-rank propagation, Shiki/highlight cache proof, R40 Swift cap fix
  |
slice 6: cutover cleanup, compile-enforced deletions, live proof and PR gates
```

Only narrow test authoring in slice 1 can run in parallel with review-only
preparation for slice 2. Slices 2-6 must serialize because they touch shared
BridgeWeb demand types, runtime construction, and tests that should fail at
compile time if any legacy path remains.

## Four Laws

These laws are the execution shorthand for the R32-R40 contract:

1. Membership law: membership is reconciler-derived from bounded inputs and is
   never truncated by queue, executor, hydration hook, or prefetch pump.
2. Priority law: selected/click is the strict head of immediate demand and
   can preempt inside a saturated lane; comparator order cannot be
   lane-then-`localeCompare`.
3. Liveness law: members are re-demanded until cache-present or generation
   supersedes them; retry parking and exhausted membership states do not exist.
4. Landing law: generation-fresh ready results always land in cache, while UI
   commit is gated by current membership/generation.

## Slice 1 - Red Survivor Proof

Objective:

Write the mandatory red-first test before any reconciler code. It must drive
the real visible-content seam with a rendered report larger than the legacy cap
and assert every reported item is eventually demanded and painted. The test must
fail today because only the first 12 normalized items become members.

Files touched:

- `BridgeWeb/src/review-viewer/content/visible-review-content-hydration.browser.test.tsx`
- `BridgeWeb/src/review-viewer/content/visible-review-content-hydration.unit.test.ts`
- test-support only if already shared by those suites:
  `BridgeWeb/src/review-viewer/content/review-content-demand-loader.test-support.ts`

Red-first proof:

```bash
pnpm --dir BridgeWeb exec vitest --config vitest.browser.config.ts run --project integration-browser src/review-viewer/content/visible-review-content-hydration.browser.test.tsx
```

Expected failure on current code: the new >12 rendered report scenario observes
`window.__bridgeVisibleHydrationStateProbe.truncatedVisibleItemCount > 0` and
some reported item ids never reach ready/painted state. Exit code must be
non-zero for the expected assertion, not a harness error.

Green proof after later slices:

```bash
pnpm --dir BridgeWeb exec vitest --config vitest.browser.config.ts run --project integration-browser src/review-viewer/content/visible-review-content-hydration.browser.test.tsx
pnpm --dir BridgeWeb exec vitest run src/review-viewer/content/visible-review-content-hydration.unit.test.ts
```

Deletes in this slice:

- None. This is red-test-only by design.

Dependencies:

- None. Must run before slice 2 implementation.

## Slice 2 - Reconciler And Pure Derivations Against Existing Executor

Objective:

Introduce the pure content-demand reconciler and empirical scenario tables
without deleting the current scheduler yet. Build from the existing review and
worktree-file demand policy seeds. The reconciler owns bounded membership,
tier derivation, dedupe to highest role, ordering, generation-stamped plans,
promotion/demotion/cancellation plans, pause-state start eligibility, and
loadedSet = cache-present. Memoization may cache results by inputs but may not
decide membership.

Files touched:

- `BridgeWeb/src/core/demand/bridge-content-demand-reconciler.ts` (new)
- `BridgeWeb/src/core/demand/bridge-content-demand-reconciler.unit.test.ts` (new)
- `BridgeWeb/src/core/models/bridge-demand-models.ts`
- `BridgeWeb/src/core/models/bridge-demand-models.unit.test.ts`
- `BridgeWeb/src/features/review/demand/review-demand-policy.ts`
- `BridgeWeb/src/features/review/demand/review-demand-policy.unit.test.ts`
- `BridgeWeb/src/features/worktree-file/demand/worktree-file-demand-policy.ts`
- `BridgeWeb/src/features/worktree-file/demand/worktree-file-demand-policy.unit.test.ts`
- `BridgeWeb/src/review-viewer/content/review-content-demand-types.ts`
- `BridgeWeb/src/review-viewer/content/review-content-demand-policy.ts`

Red-first proof:

```bash
pnpm --dir BridgeWeb exec vitest run src/core/demand/bridge-content-demand-reconciler.unit.test.ts src/features/review/demand/review-demand-policy.unit.test.ts src/features/worktree-file/demand/worktree-file-demand-policy.unit.test.ts
```

Expected failure before implementation: missing reconciler module and/or
scenario rows fail for membership-not-truncated, selected in-lane preemption,
generation epoch reset, loadedSet cache-present, pause not gating selected,
and promote-not-restart.

Green proof:

```bash
pnpm --dir BridgeWeb exec vitest run src/core/demand/bridge-content-demand-reconciler.unit.test.ts src/features/review/demand/review-demand-policy.unit.test.ts src/features/worktree-file/demand/worktree-file-demand-policy.unit.test.ts src/core/models/bridge-demand-models.unit.test.ts
pnpm --dir BridgeWeb exec tsc --noEmit
```

Deletes in this slice:

- No production deletions yet. Tests should add TODO-failing compile references
  to the future cutover fields only if they are quarantined to this slice's
  new tests.

Dependencies:

- Depends on slice 1 red proof.
- Feeds slice 3 queue/executor cutover.

## Slice 3 - Unified Queue/Executor Cutover And Scheduler Deletion

Objective:

Replace the staging-buffer scheduler with the reconciler-owned queue and update
all Review and Worktree/File content demand consumers to admit every member.
The executor remains the start/concurrency/freshness/abort owner, but it no
longer rejects membership due to `canQueueUnderPressure`, pending byte pressure,
or pending load count. F2 selected in-lane preemption must be real: the executor
comparator must understand selected sub-rank and demand rank, not just
lane-then-`orderingKey`.

Files touched:

- DELETE `BridgeWeb/src/core/demand/bridge-demand-scheduler.ts`
- DELETE `BridgeWeb/src/core/demand/bridge-demand-scheduler.unit.test.ts`
- `BridgeWeb/src/core/demand/bridge-resource-executor.ts`
- `BridgeWeb/src/core/demand/bridge-resource-executor.unit.test.ts`
- `BridgeWeb/src/core/demand/bridge-demand-runtime.integration.test.ts`
- `BridgeWeb/src/review-viewer/content/review-content-demand-loader.ts`
- `BridgeWeb/src/review-viewer/content/review-content-demand-loader.core.unit-suite.ts`
- `BridgeWeb/src/review-viewer/content/review-content-demand-loader.cache.unit-suite.ts`
- `BridgeWeb/src/review-viewer/content/review-content-demand-loader.pressure.unit-suite.ts`
- `BridgeWeb/src/review-viewer/content/review-content-demand-loader.unit.test.ts`
- `BridgeWeb/src/review-viewer/content/review-content-demand-telemetry.ts`
- `BridgeWeb/src/review-viewer/content/review-content-demand-types.ts`
- `BridgeWeb/src/app/bridge-app-review-runtime.ts`
- `BridgeWeb/src/app/bridge-app-review-controller.ts`
- `BridgeWeb/src/app/bridge-app-review-descriptors.ts`
- `BridgeWeb/src/app/bridge-app-review-intake-controller.ts`
- `BridgeWeb/src/app/bridge-app-review-selection-controller.ts`
- `BridgeWeb/src/app/bridge-app-review-selected-content-controller.ts`
- `BridgeWeb/src/app/bridge-app-review-visible-content-controller.ts`
- `BridgeWeb/src/app/bridge-app-review-viewer-mode.tsx`
- `BridgeWeb/src/app/bridge-app.unit.test.ts`
- `BridgeWeb/src/app/bridge-app.unit.test-support.ts`
- `BridgeWeb/src/app/bridge-app-review-metadata-package.preservation.unit.test.ts`
- `BridgeWeb/src/worktree-file-surface/worktree-file-surface-runtime.ts`
- `BridgeWeb/src/worktree-file-surface/worktree-file-surface-runtime-support.ts`
- `BridgeWeb/src/worktree-file-surface/worktree-file-surface-runtime.demand.integration-suite.ts`

Red-first proof:

```bash
pnpm --dir BridgeWeb exec vitest run src/core/demand/bridge-resource-executor.unit.test.ts src/core/demand/bridge-demand-runtime.integration.test.ts src/review-viewer/content/review-content-demand-loader.unit.test.ts src/worktree-file-surface/worktree-file-surface-runtime.demand.integration-suite.ts
```

Expected failure before implementation: pressure scenarios still return
`concurrency_exceeded` from queue membership, pending lower-priority members are
evicted, and selected same-lane preemption is not guaranteed when visible work
occupies executor slots.

Green proof:

```bash
pnpm --dir BridgeWeb exec vitest run src/core/demand/bridge-resource-executor.unit.test.ts src/core/demand/bridge-demand-runtime.integration.test.ts src/review-viewer/content/review-content-demand-loader.unit.test.ts src/worktree-file-surface/worktree-file-surface-runtime.demand.integration-suite.ts src/app/bridge-app.unit.test.ts src/app/bridge-app-review-metadata-package.preservation.unit.test.ts
pnpm --dir BridgeWeb exec tsc --noEmit
```

Deletes in this slice:

- `BridgeWeb/src/core/demand/bridge-demand-scheduler.ts`
- `BridgeWeb/src/core/demand/bridge-demand-scheduler.unit.test.ts`
- All imports, exported types, constructor wiring, and telemetry fields that
  expose `BridgeDemandScheduler`.
- `canQueueUnderPressure`.
- `evictLowerPriorityPendingLoads` as membership eviction.
- Executor pending-eviction result paths that report concurrency as a member
  drop.

Dependencies:

- Depends on slice 2 reconciler plans.
- Blocks slice 4 because the background tier must use the same queue.

## Slice 4 - Background Tier And Prefetch-Pump Deletion

Objective:

Move review background warming into the reconciler's background tier and delete
the standalone prefetch pump. Background demand is browser-pulled, bounded to
roughly five windows, paced/yielding below every higher tier, and shares the
same membership, generation, loadedSet, backoff, and cancellation rules. F3/R36
must be explicit: cache admission is separate from selected/visible UI commit.
F5/R37 and F7/R38 must hold for background and pause release too.

Files touched:

- DELETE `BridgeWeb/src/app/bridge-app-review-content-prefetch-controller.ts`
- DELETE `BridgeWeb/src/app/bridge-app-review-content-prefetch-controller.browser.test.tsx`
- DELETE `BridgeWeb/src/review-viewer/content/review-content-prefetch-policy.ts`
- DELETE `BridgeWeb/src/review-viewer/content/review-content-prefetch-policy.unit.test.ts`
- `BridgeWeb/src/app/bridge-app-review-viewer-mode.tsx`
- `BridgeWeb/src/app/bridge-app-review-runtime.ts`
- `BridgeWeb/src/review-viewer/content/review-content-registry.ts`
- `BridgeWeb/src/review-viewer/content/review-content-demand-loader.ts`
- `BridgeWeb/src/review-viewer/content/review-content-demand-loader.cache.unit-suite.ts`
- `BridgeWeb/src/review-viewer/content/review-content-demand-loader.pressure.unit-suite.ts`
- `BridgeWeb/src/core/demand/bridge-content-demand-reconciler.ts`
- `BridgeWeb/src/core/demand/bridge-content-demand-reconciler.unit.test.ts`

Red-first proof:

```bash
pnpm --dir BridgeWeb exec vitest run src/core/demand/bridge-content-demand-reconciler.unit.test.ts src/review-viewer/content/review-content-demand-loader.unit.test.ts
```

Expected failure before implementation: background candidates are still owned
by the pump and its policy tests, background is not a reconciler tier, cache
landing/UI commit split is not directly proven, and queue-wait re-stamp after
pause release is absent.

Green proof:

```bash
pnpm --dir BridgeWeb exec vitest run src/core/demand/bridge-content-demand-reconciler.unit.test.ts src/review-viewer/content/review-content-demand-loader.unit.test.ts src/review-viewer/content/review-content-demand-loader.cache.unit-suite.ts src/review-viewer/content/review-content-demand-loader.pressure.unit-suite.ts
pnpm --dir BridgeWeb exec tsc --noEmit
```

Deletes in this slice:

- Review content prefetch hook and browser test.
- Review content prefetch policy constants and unit tests.
- `reviewContentRegistryPrefetchMaxEntries` import path; replacement capacity
  must be named as a cache/retention policy, not prefetch.
- All "background pump" language in production comments.

Dependencies:

- Depends on slice 3 deletion of the legacy scheduler.
- Must finish before slice 6 compile-enforced cutover scans.

## Slice 5 - Worker Rank, Shiki/Highlight Cache, And R40 AppPolicies

Objective:

Propagate demand rank through the worker/highlight/materialization boundary so
selected work cannot sit behind lower-rank worker jobs. Verify Shiki/highlight
cache behavior after rank propagation. Fix R40 by decoupling total byte cache
capacity from per-item cap in `AppPolicies.Bridge`.

Files touched:

- `BridgeWeb/src/review-viewer/workers/pierre/bridge-pierre-worker-pool.tsx`
- `BridgeWeb/src/review-viewer/workers/pierre/bridge-pierre-worker-content-descriptor.unit.test.ts`
- `BridgeWeb/src/review-viewer/workers/pierre/bridge-pierre-worker-initialization-probe.unit.test.ts`
- `BridgeWeb/src/review-viewer/test-support/bridge-viewer-browser.integration.test-support.ts`
- `BridgeWeb/src/review-viewer/test-support/bridge-viewer.browser.benchmark.tsx`
- `BridgeWeb/src/review-viewer/theme/bridge-shiki-runtime.unit.test.ts`
- `BridgeWeb/src/review-viewer/theme/bridge-pierre-bundled-theme-registry.unit.test.ts`
- `BridgeWeb/src/foundation/telemetry/bridge-viewer-telemetry-adapter.ts`
- `BridgeWeb/src/foundation/telemetry/bridge-telemetry-taxonomy.ts`
- `Sources/AgentStudio/Infrastructure/AppPolicies.swift`
- Swift tests for the policy cap, preferably a focused existing Bridge policy
  or transport test file under `Tests/AgentStudioTests/Features/Bridge/`.
- If any new telemetry attribute is introduced:
  `Sources/AgentStudio/Infrastructure/Diagnostics/AgentStudioOTLPTraceProjection.swift`,
  `Sources/AgentStudio/Features/Bridge/Runtime/Telemetry/BridgeTelemetryBatchValidator+Allowlists.swift`,
  and a red-first projection/validator test.

Red-first proof:

```bash
pnpm --dir BridgeWeb exec vitest run src/review-viewer/workers/pierre/bridge-pierre-worker-content-descriptor.unit.test.ts src/review-viewer/theme/bridge-shiki-runtime.unit.test.ts src/review-viewer/theme/bridge-pierre-bundled-theme-registry.unit.test.ts
mise run test -- --filter BridgeContentDemandAdmission
```

Expected failure before implementation: a new worker-pool integration/unit
scenario demonstrates selected rank can be delayed behind lower-rank
highlight/materialize work, and the Swift policy assertion fails because
`contentMaxBytesPerItem == contentCacheMaxBytes`.

Green proof:

```bash
pnpm --dir BridgeWeb exec vitest run src/review-viewer/workers/pierre/bridge-pierre-worker-content-descriptor.unit.test.ts src/review-viewer/workers/pierre/bridge-pierre-worker-initialization-probe.unit.test.ts src/review-viewer/theme/bridge-shiki-runtime.unit.test.ts src/review-viewer/theme/bridge-pierre-bundled-theme-registry.unit.test.ts
mise run test -- --filter "BridgeContentDemandAdmission|AppPolicies"
```

If telemetry allowlists change, add and run:

```bash
mise run test -- --filter "AgentStudioOTLP|BridgeTelemetryBatchValidator"
```

Deletes in this slice:

- Any worker FIFO-only assumption that ignores demand rank.
- Any tests that assert equal-rank FIFO as a selected-vs-visible ordering rule.

Dependencies:

- Depends on slice 2 rank shape and slice 3 executor rank.
- Can begin after slice 2 with a local branch, but must integrate after slice 3
  to avoid divergent demand-rank types.

## Slice 6 - Cutover Cleanup, Live Proof, And PR Gates

Objective:

Make the one-PR cutover compile-enforced and prove it through the required
layers. This slice removes lingering fields/exports so partial cutover fails at
typecheck, runs full BridgeWeb and Swift gates, then performs live debug
observability momentum-scroll proof.

Files touched:

- `BridgeWeb/src/review-viewer/content/visible-review-content-hydration.ts`
- `BridgeWeb/src/review-viewer/content/visible-review-content-hydration-support.ts`
- `BridgeWeb/src/review-viewer/content/visible-review-content-hydration.unit.test.ts`
- `BridgeWeb/src/review-viewer/content/visible-review-content-hydration.browser.test.tsx`
- Any remaining import site found by the required source scans below.
- No product code outside the slice's discovered cleanup set unless a scan
  proves it still imports deleted demand paths.

Red-first proof:

```bash
pnpm --dir BridgeWeb exec tsc --noEmit
```

Expected failure before cleanup: unresolved imports or types for deleted
`BridgeDemandScheduler`, `retryAfterVersion`, prefetch pump/policy, legacy
truncation exports, or scheduler rejection reasons. If it passes before cleanup,
the executor must add source scans because the cutover is not compile-enforced.

Required source scans:

```bash
rg -n "BridgeDemandScheduler|createBridgeDemandScheduler|bridge-demand-scheduler|retryAfterVersion|visibleContentHydrationItemLimit|reviewContentPrefetch|useBridgeReviewContentPrefetchController|canQueueUnderPressure|evictLowerPriorityPendingLoads" BridgeWeb/src
rg -n "contentMaxBytesPerItem|contentCacheMaxBytes" Sources/AgentStudio/Infrastructure/AppPolicies.swift Tests/AgentStudioTests
```

Expected green source-scan result: first command exits 1 with no matches for
deleted symbols except allowed historical text in tests that explicitly assert
absence. Second command shows both policy constants and a test proving
per-item cap is lower than total cache cap.

Green proof:

```bash
pnpm --dir BridgeWeb exec vitest run
pnpm --dir BridgeWeb exec tsc --noEmit
pnpm --dir BridgeWeb exec oxlint --type-aware
pnpm --dir BridgeWeb exec oxfmt --check .
mise run lint
mise run test -- --filter "BridgeContentDemandAdmission|AgentStudioOTLP|BridgeTelemetryBatchValidator"
```

Live proof gates:

```bash
mise run observability:up
AGENTSTUDIO_IPC_UNSAFE_NO_AUTH=1 AGENTSTUDIO_IPC_DEBUG_TOKEN_ESCROW=1 AGENTSTUDIO_TRACE_TAGS="app.startup,performance,bridge.performance.*" mise run run-debug-observability -- --detach
mise run verify-debug-observability
mise run verify-bridge-review-journey-smoke
mise run verify-bridge-mode-idle-smoke
```

Then run a live debug-observability momentum-scroll session in Review mode and
inspect `window.__bridgeVisibleHydrationStateProbe` through the fixed IPC
render-state path. Required settled state:

```text
truncatedVisibleItemCount == 0
untrackedItemCount drains to 0 after settle
```

User UX confirmation is required for this slice: the user must confirm that
fast momentum scroll no longer leaves visible review items stuck as
placeholders.

Deletes in this slice:

- Any remaining `retryAfterVersion` field/type/state.
- Any remaining hydration hook membership cap.
- Any compatibility export that allows the deleted scheduler/pump to compile.
- Any dormant dual demand path.

Dependencies:

- Depends on slices 1-5.
- Final integration gate for the one PR.

## Requirements / Proof Matrix

| Requirement | Proving slice | Proof command |
| --- | --- | --- |
| R20 strict content taxonomy; selected is absolute content preemptor | 2, 3, 5 | `pnpm --dir BridgeWeb exec vitest run src/core/demand/bridge-content-demand-reconciler.unit.test.ts src/core/demand/bridge-resource-executor.unit.test.ts`; worker proof in slice 5 |
| R21 visible tree work remains metadata-only | 2, 6 | `pnpm --dir BridgeWeb exec vitest run src/features/worktree-file/demand/worktree-file-demand-policy.unit.test.ts`; `mise run verify-bridge-mode-idle-smoke` |
| R22 hover speculation is cancellable | 2, 3 | `pnpm --dir BridgeWeb exec vitest run src/core/demand/bridge-content-demand-reconciler.unit.test.ts src/worktree-file-surface/worktree-file-surface-runtime.demand.integration-suite.ts` |
| R23 click cancels non-target speculation and promotes target work | 2, 3 | `pnpm --dir BridgeWeb exec vitest run src/core/demand/bridge-content-demand-reconciler.unit.test.ts src/core/demand/bridge-resource-executor.unit.test.ts` |
| R24 generation rotation is atomic cancellation | 2, 3, 6 | `pnpm --dir BridgeWeb exec vitest run src/core/demand/bridge-content-demand-reconciler.unit.test.ts src/review-viewer/content/review-content-demand-loader.unit.test.ts`; smoke gates in slice 6 |
| R25 one stream staleness authority | 2, 3 | `pnpm --dir BridgeWeb exec vitest run src/review-viewer/content/review-content-demand-loader.unit.test.ts src/worktree-file-surface/worktree-file-surface-runtime.demand.integration-suite.ts` |
| R26 every stale/reject path recovers or marks unhealthy | 3, 6 | Targeted demand loader/runtime tests plus `mise run verify-bridge-review-journey-smoke` and `mise run verify-bridge-mode-idle-smoke` |
| R27 reopen storm guard remains intact | 6 | `mise run verify-bridge-mode-idle-smoke`; do not modify native metadata-plane reopen logic in this PR |
| R28 review adjacent warming is speculative/bounded | 2, 4 | `pnpm --dir BridgeWeb exec vitest run src/core/demand/bridge-content-demand-reconciler.unit.test.ts src/review-viewer/content/review-content-demand-loader.unit.test.ts` |
| R29 speculative content lands in worker-backed/shared cache | 4, 5 | `pnpm --dir BridgeWeb exec vitest run src/review-viewer/content/review-content-demand-loader.cache.unit-suite.ts src/review-viewer/theme/bridge-shiki-runtime.unit.test.ts` |
| R30 speculative in-flight globally bounded as executor-stage start limit | 3, 4 | `pnpm --dir BridgeWeb exec vitest run src/core/demand/bridge-resource-executor.unit.test.ts src/review-viewer/content/review-content-demand-loader.pressure.unit-suite.ts` |
| R31 mode switch cancels or demotes inactive demand | 2, 6 | `pnpm --dir BridgeWeb exec vitest run src/core/demand/bridge-content-demand-reconciler.unit.test.ts`; `mise run verify-bridge-mode-idle-smoke` |
| R32 reconciler is only membership authority | 2, 6 | Reconciler unit scenario tables; source scan for deleted scheduler/hydration owners |
| R33 membership never truncates; concurrency bounds starts only | 1, 3, 6 | Red survivor browser test; executor pressure tests; live probe `truncatedVisibleItemCount == 0` |
| R34 no parked demand states; `retryAfterVersion` deleted | 2, 6 | Reconciler liveness tests; `pnpm --dir BridgeWeb exec tsc --noEmit`; source scan for `retryAfterVersion` |
| R35 selected preempts inside queue | 2, 3, 5 | Reconciler ordering tests; executor preemption tests; worker rank tests |
| R36 ready results always land in cache; UI commit membership-gated | 4, 6 | Demand-loader cache tests and live scroll proof |
| R37 generation is an epoch over whole derivation | 2, 3 | Reconciler epoch reset tests and runtime stale/cancel tests |
| R38 pause gates below-selected starts and re-stamps queue wait | 2, 4, 6 | Reconciler pause scenario table; live momentum-scroll session |
| R39 rank survives worker boundary | 5 | Worker pool rank integration/unit test and Shiki/highlight cache tests |
| R40 retention floor and byte cache are decoupled tiers | 5 | `mise run test -- --filter "BridgeContentDemandAdmission|AppPolicies"` |
| Law 1 membership law | 1, 2, 3, 6 | Red survivor test, reconciler tables, source scans, live probe |
| Law 2 priority law | 2, 3, 5 | Reconciler, executor, and worker rank tests |
| Law 3 liveness law | 2, 6 | Reconciler liveness tests, `retryAfterVersion` deletion scan |
| Law 4 landing law | 4, 6 | Cache/UI split tests and live proof |

Proof seam honesty:

- Pure vitest scenario tables close only membership, ordering, cancellation,
  generation, dedupe, and promote-not-restart claims.
- Paint/queue budgets require the gated benchmark with VictoriaMetrics and
  at least 100 samples. Scenario tables do not close this.
- Momentum/pause tails require the live momentum-scroll session.
- Worker order requires worker-pool integration/unit proof, not the pure
  reconciler tests.
- WebKit delivery/cold-cache fetch requires native smoke.
- Cache eviction at scale requires soak or benchmark proof; do not claim it
  from unit tests.

## Lane Boundaries

One writer per file family:

- Reconciler/types lane owns `BridgeWeb/src/core/demand/` and
  `BridgeWeb/src/core/models/`.
- Review content lane owns `BridgeWeb/src/review-viewer/content/` and
  `BridgeWeb/src/app/bridge-app-review-*`.
- Worktree/File content lane owns `BridgeWeb/src/worktree-file-surface/` and
  `BridgeWeb/src/features/worktree-file/demand/`.
- Worker lane owns `BridgeWeb/src/review-viewer/workers/`,
  `BridgeWeb/src/review-viewer/theme/`, and worker telemetry changes.
- Swift policy/telemetry lane owns `Sources/AgentStudio/Infrastructure/`,
  `Sources/AgentStudio/Features/Bridge/Runtime/Telemetry/`, and matching Swift
  tests.

Line caps:

- BridgeWeb source-structure cap: keep every TS/TSX file under 1000 lines.
  `visible-review-content-hydration.ts` is already 861 lines, so extraction is
  required if edits would push it near the cap.
- SwiftLint caps remain 1000 file / 800 type / 100 function. Split before
  crossing them.

Command discipline:

- Run gates unpiped. Capture exit codes directly from the command, not from
  `tee`, `cat`, or shell pipelines.
- Do not edit test harnesses, lint config, CI, or observability infrastructure
  to make a demand-slice proof pass. If a failure is outside the agreed demand
  path, stop and report the scoped pass/fail plus blocker.

Parallelization:

- Parallel-safe: slice 1 red-test authoring and read-only worker-rank planning.
- Parallel-safe after slice 2 stabilizes: worker rank tests can be drafted
  while slice 3 integrates queue/executor, but the type merge must serialize.
- Must serialize: slices 2 -> 3 -> 4 -> 6.
- Swift R40 policy fix in slice 5 can be implemented in parallel with worker
  rank only if no telemetry attribute changes are needed; otherwise serialize
  with the telemetry allowlist writer.

## Cutover Deletion Checklist

Before the PR is considered ready, these deletions must be true:

- `BridgeWeb/src/core/demand/bridge-demand-scheduler.ts` is deleted.
- `BridgeWeb/src/core/demand/bridge-demand-scheduler.unit.test.ts` is deleted.
- `BridgeDemandScheduler` and `createBridgeDemandScheduler` do not compile
  anywhere.
- `retryAfterVersion` does not exist in production or test types.
- `visibleContentHydrationItemLimit` is not used as a membership cap.
- `canQueueUnderPressure` is deleted.
- `evictLowerPriorityPendingLoads` is deleted or no longer performs membership
  eviction; prefer deletion.
- `BridgeWeb/src/app/bridge-app-review-content-prefetch-controller.ts` is
  deleted.
- `BridgeWeb/src/review-viewer/content/review-content-prefetch-policy.ts` is
  deleted.
- Prefetch pump tests are deleted or rewritten as reconciler background-tier
  tests.
- `active` is not a content-demand lane emitted by new reconciler plans; it may
  remain only in metadata-plane vocabulary and historical model compatibility
  until a separate model cleanup is approved.

## Explicit Non-Goals

- No Pierre fork.
- No app-side scroll anchors.
- No dual demand paths or compatibility adapters.
- No native demand owner; `BridgeContentDemandAdmission` stays a serving-side
  valve only.
- Metadata plane untouched except telemetry allowlists if required.
- No raw item/path/hash/url telemetry attributes.
- No review protocol wire-lineage redesign.
- No broad W1-W5 architecture fixes in this PR; avoid regressing them and leave
  those as separate transport/recovery work.

## Definition Of Done

The PR is done only when all of these are true and reported with commands,
exit codes, and pass/fail counts where available:

1. Slice-level red-first proofs were observed before implementation for slice
   1 and for each behavior-bearing slice's new scenario rows.
2. `pnpm --dir BridgeWeb exec vitest run` passes.
3. `pnpm --dir BridgeWeb exec tsc --noEmit` passes.
4. `pnpm --dir BridgeWeb exec oxlint --type-aware` passes.
5. `pnpm --dir BridgeWeb exec oxfmt --check .` passes.
6. `mise run lint` passes.
7. Targeted Swift tests pass:
   `mise run test -- --filter "BridgeContentDemandAdmission|AgentStudioOTLP|BridgeTelemetryBatchValidator"`.
8. Targeted BridgeWeb smoke/behavior tests from the slices pass.
9. `mise run verify-bridge-review-journey-smoke` passes.
10. `mise run verify-bridge-mode-idle-smoke` passes.
11. Live debug-observability momentum-scroll session proves
    `window.__bridgeVisibleHydrationStateProbe.truncatedVisibleItemCount == 0`
    and `untrackedItemCount` drains to 0 after settle.
12. User confirms the Review momentum-scroll UX no longer leaves visible items
    stuck as placeholders.
13. Source scans show no deleted legacy symbols remain.
14. Every BridgeWeb TS/TSX file remains under 1000 lines; SwiftLint size caps
    remain green.
15. If any new telemetry attribute was added, projection and validator tests
    were red-first and then green, and OTLP allowlists scrub unsafe data.

Full-performance closeout is not satisfied by this PR unless the executor also
runs the gated benchmark with VictoriaMetrics and at least 100 samples. If that
benchmark is not run, report it as an unclosed performance budget layer, not as
a substitute for the live correctness proof above.

## Contradictions And Planning Resolutions

- The request named `BridgeWeb/src/app/review-content-prefetch-policy.ts` and
  `BridgeWeb/src/app/review-content-demand-policy.ts`, but this checkout does
  not contain those files. The live files are
  `BridgeWeb/src/review-viewer/content/review-content-prefetch-policy.ts` and
  `BridgeWeb/src/review-viewer/content/review-content-demand-policy.ts`.
  The plan targets the live paths and keeps this contradiction explicit.
- The current `BridgeWeb/src/review-viewer/content/visible-review-content-hydration.ts`
  is 861 lines and is a required edit target. Because the BridgeWeb cap is 1000
  lines/file, any implementation that grows it materially must extract
  reconciler-facing support rather than piling more logic into the hook.
- The current executor uses both a deleted staging scheduler and its own pending
  queue. The plan resolves this by deleting scheduler membership authority while
  keeping executor start/backoff/freshness mechanics. Executor pending state is
  allowed only as start pacing, never as membership admission or eviction.
