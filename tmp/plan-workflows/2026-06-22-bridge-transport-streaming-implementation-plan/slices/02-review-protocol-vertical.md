# 02 Review Protocol Vertical With Descriptor-Backed Demand

## Ticket Output

Review runs through app protocol frames end-to-end, and the generic demand
runtime becomes authoritative only after Review frames attach descriptors.

Deliverable:

- Swift emits Review snapshot/delta/invalidation/reset frames with attached
  descriptors.
- Browser registers descriptors before materializer and demand policy run.
- Review materializer emits facts/references/render deltas without storing large
  bodies in Zustand.
- Review demand policy maps Review stimuli onto generic lanes.
- Generic scheduler/executor/body registry are proven through Review.
- Existing Review UX, browser integration, and dev-server proof pass.
- Worktree dev proof remains supported until ticket 04 replaces the old Review
  package scaffolding.

## Source References

- `spec.md` section 9 demand scheduling and backpressure
- `spec.md` section 10 invalidation semantics
- `spec.md` section 11 Pierre boundary
- `review-protocol.md` sections 5-9
- `review-protocol.md` section 11 proof expectations
- `plan-review-report.md` B3, B4, I2, I3

## Write Scope

Browser:

- `BridgeWeb/src/core/demand/**`
- `BridgeWeb/src/core/resources/**` only for descriptor registry integration
- `BridgeWeb/src/features/review/**`
- Review adapters under `BridgeWeb/src/review-viewer/content/**`
- Review projection adapters under `BridgeWeb/src/review-viewer/projections/**`
- Review app bootstrap and test fixtures under `BridgeWeb/src/app/**` and
  `BridgeWeb/src/review-viewer/test-support/**`
- first app protocol router in `BridgeWeb/src/app/**`; ticket 04 extends this
  router for Worktree/File instead of inventing a second app shell

Swift:

- `Sources/AgentStudio/Features/Bridge/Models/ReviewProtocol/**`
- `Sources/AgentStudio/Features/Bridge/Runtime/ReviewProtocol/**`
- existing `ReviewFoundation` only as transition source until proof passes

Do not remove Worktree dev Review-package scaffolding in this ticket unless
`test:dev-server:worktree` has a replacement proof.

## Red Tests First

Review frames and materialization:

- `review.snapshot` registers attached descriptors before projection/demand.
- `review.delta` preserves same-lineage renderer identity where possible.
- `review.reset` revokes stale descriptors and drops late completions.
- Raw descriptor strings in Review frames cannot become fetchable demand.
- Swift fixture frames match TS schemas.

Demand and scheduler:

- `reviewItemSelected` and explicit refresh map to `foreground`.
- Selected invalidated descriptors map to `foreground`.
- Open invalidated descriptors map to `active` unless app policy chooses manual
  refresh.
- Visible descriptors map to `visible`; hover maps to `speculative`.
- Hidden invalidated descriptors emit no demand.
- Unknown, stale, foreign, or unregistered descriptor refs emit no demand.
- Review changeset cluster metadata is preserved for live/closed/pinned,
  degraded-confidence, overflow/fresh-scan, and non-authoritative cases.
- Scheduler orders `foreground > active > visible > nearby > speculative > idle`.
- Scheduler dedupes by `dedupeKey`, replaces stale queued work, and has bounded
  queue ceilings.
- Executor enforces concurrency and byte/work caps, coalesces in-flight work,
  propagates abort intent, applies retry/cooldown, and drops stale completions
  by `freshnessKey`.

State/security/telemetry:

- Page-world descriptor-like data cannot trigger Review demand or fetch.
- Zustand snapshots contain facts/refs/status only.
- Review markdown source remains inert and cannot leak or render Bridge
  capability URLs, remote loads, scripts, event handlers, or `javascript:` URLs.
- Pierre/renderer inputs are prepared items/paths and render deltas only, never
  fetchable Bridge URLs or descriptor authority.
- Telemetry canary excludes raw path, source text, prompt, capability URL,
  comment, and comms seeds while retaining safe scheduler audit fields.

App/browser:

- Existing Review browser integration still passes.
- Search, regex, filters, selection, reveal, and markdown click/reveal paths
  remain functional or are explicitly captured as remaining implementation bugs
  before moving on.
- Dev-server Review URL works after migration.
- `test:dev-server:worktree` remains supported through the transition.

## Implementation Notes

1. Add Review protocol schemas and fixtures under `src/features/review/**`.
2. Add Swift Review frame models and frame builder.
3. Attach descriptors during Swift Review package/frame construction.
4. Extract Review frame application out of `BridgeApp` into Review materializer.
5. Add the first protocol router around the current Review-only `BridgeApp`
   root so Review is an app protocol surface, not the only app shape.
6. Add generic scheduler, executor, and body registry in `src/core/demand/**`.
7. Add Review demand policy as the first app policy using the generic runtime.
8. Adapt selected content and visible hydration through demand intents.
9. Keep old Review package push compatibility only until this ticket proves the
   new Review path.
10. Preserve Worktree dev proof until ticket 04 replaces it.

## First Implementation Scheduler Defaults

These are starter constants for proof, not final tuning:

- max in-flight foreground: 2
- max in-flight active: 2
- max in-flight visible: 4
- max in-flight nearby/speculative/idle combined: 2
- max queued intents per lane: 256
- max queued bytes estimate per pane: 32 MiB hard ceiling across queued and
  in-flight resource intents; foreground admission may drop lower-priority
  queued work first, but no lane may bypass the ceiling silently
- body registry: bounded LRU by descriptor/freshness key, with explicit stale
  eviction on reset
- overload behavior: drop or downgrade speculative/idle first; never block
  foreground behind speculative/idle

If profiling proves these wrong, adjust constants with stress tests in this
ticket or record a follow-up tuning ticket. Do not leave them implicit.

## Proof Gates

Review model/materializer/demand unit:

```bash
pnpm --dir BridgeWeb vitest run \
  src/features/review/models/review-protocol-models.unit.test.ts \
  src/features/review/materialization/review-materializer.unit.test.ts \
  src/features/review/demand/review-demand-policy.unit.test.ts
```

Generic demand unit:

```bash
pnpm --dir BridgeWeb vitest run \
  src/core/demand/bridge-demand-scheduler.unit.test.ts \
  src/core/demand/bridge-resource-executor.unit.test.ts \
  src/core/demand/bridge-body-registry.unit.test.ts \
  src/core/demand/bridge-demand-runtime.integration.test.ts
```

Compatibility tests remain in scope while Review adapters still depend on old
Review package shapes:

```bash
pnpm --dir BridgeWeb vitest run \
  src/foundation/review-package/bridge-review-package-schema.unit.test.ts \
  src/foundation/review-package/bridge-review-delta.unit.test.ts \
  src/foundation/review-package/bridge-review-item-registry.unit.test.ts \
  src/review-viewer/content/review-content-loader.unit.test.ts \
  src/review-viewer/content/review-content-registry.unit.test.ts \
  src/review-viewer/content/visible-review-content-hydration.unit.test.tsx
```

Review integration:

```bash
pnpm --dir BridgeWeb vitest run src/app/bridge-app.integration.test.tsx
```

Markdown/security:

```bash
pnpm --dir BridgeWeb vitest run \
  src/review-viewer/markdown/bridge-markdown-preview.unit.test.tsx \
  src/review-viewer/markdown/bridge-markdown-render-mode.unit.test.ts
```

Extend these suites, or add a focused Review markdown-source fixture, if the
Review protocol migration changes markdown source descriptors, fetching,
sanitization, or DOM rendering. The proof must cover scripts, event handlers,
remote loads, `javascript:` URLs, and embedded Bridge capability URLs.

Telemetry canary:

- add or extend an app integration telemetry canary, for example
  `BridgeWeb/src/app/bridge-telemetry-canary.integration.test.tsx`, seeded with
  raw path, source text, prompt, capability URL, comment, comms, and handle
  strings; the proof must show exported telemetry keeps only allowlisted
  scheduler audit fields.

Scheduler/pressure:

```bash
pnpm --dir BridgeWeb run benchmark:viewer
pnpm --dir BridgeWeb run test:benchmark:browser
```

Run targeted benchmark/pressure scenarios when ticket 02 changes queue
ceilings, viewport churn behavior, invalidation storms, or foreground
preemption. If no pressure path changed, record the not-applicable reason.

Browser:

```bash
pnpm --dir BridgeWeb run test:browser:integration -- \
  src/review-viewer/test-support/bridge-viewer-browser.integration.browser.test.tsx
```

Dev server:

```bash
pnpm --dir BridgeWeb run test:dev-server
pnpm --dir BridgeWeb run test:dev-server:worktree
```

Quality:

```bash
pnpm --dir BridgeWeb run check
```

Swift focused gate:

```bash
mise run test-fast
```

Use focused Bridge review suites where possible, then broader Swift gates at
milestone/final proof.

## Handoff Output

- Review frame schema and Swift fixture parity proof
- descriptor attachment and stale reset proof
- changeset metadata preservation and non-authority proof
- scheduler/executor pressure proof
- Zustand body-boundary proof
- markdown inert rendering and renderer-boundary proof
- telemetry canary proof
- browser/dev-server results, including Worktree dev preservation result
- statement whether CodeView/Pierre identity needed a narrow touch
- changed paths and commit hash if checkpoint committed

## Stop / Replan

Stop if Review materialization still requires CodeView remount identity to
include every package revision. Stop if generic demand can only work by reading
old Review package resource URLs as authority. Refine the boundary before
continuing.
