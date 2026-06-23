# 04 Worktree/File Browser Surface

## Ticket Output

Build the first browser Worktree/File Surface on the generic Bridge runtime and
the native/provider boundary from ticket 03. The surface is one app protocol
family with tree, file content, and status subcontracts.

Deliverable:

- browser Worktree/File schemas, materializer, demand policy, and state
- tree surface with bounded tree-window demand
- file content panel with open-file session state
- initial tree/file scroll extent reserved from provider virtualized-size facts
  before body bytes, body hydration, or DOM measurement
- measured reconciliation preserves anchor item/offset and records objective
  extent diagnostics
- stale marker and manual refresh behavior
- dev-server worktree URL uses Worktree/File protocol instead of fabricated
  Review packages
- Worktree/File replacement path resolves content through registered
  descriptors/lease-backed refs, not raw resource URL text or handle ids as
  authority
- binary/oversized files render metadata-only or bounded preview

## Source References

- `worktree-file-surface-protocol.md` sections 1-14
- `spec.md` state placement and demand/backpressure sections
- `plan-review-report.md` B4, B5, I4

## Write Scope

Browser:

- `BridgeWeb/src/features/worktree-file/**`
- `BridgeWeb/src/worktree-file-surface/**`
- `BridgeWeb/src/app/**` surface routing
- `BridgeWeb/scripts/dev-server/bridge-worktree-dev-provider.ts`
- `BridgeWeb/scripts/verify-bridge-viewer-worktree-dev-server.ts`
- existing Review worktree dev scaffolding only as transition removal after
  replacement proof passes

Swift:

- Only narrow fixes to Worktree/File method/frame integration discovered during
  browser proof.

## Red Tests First

- Worktree snapshot registers tree/status descriptors before demand.
- Tree viewport stimulus maps demanded refs to `visible`.
- Initial tree render uses provider `pathCount`, declared row height, and window
  facts, or conservative estimated total extent, before hidden descendants or
  tree row bodies hydrate.
- Tree expansion maps visible windows to `visible` and optional nearby windows
  to `nearby`.
- File selected maps content descriptor to `foreground`.
- Open-file render uses descriptor `virtualizedExtentKind`, `lineCount`, or
  `estimatedContentHeightPixels` before file content bytes are fetched, streamed,
  hydrated, or measured.
- Non-reset measured reconciliation preserves anchor item identity.
- Compensated anchor drift stays within one declared row/line height.
- Total-height deltas are logged as measured-versus-estimated reconciliation,
  never silent jumps.
- Exact-count cases keep `scrollHeight` or virtualizer `totalSize` stable within
  one declared row/line height before versus after hydration.
- Open file invalidation marks open session stale and emits no auto-fetch in
  the first implementation.
- Explicit refresh maps latest descriptor to `foreground`.
- Manual refresh commits only if freshness/source identity is still current.
- `sourceReset` drops queued and in-flight tree/file work by
  `WorktreeFileSurfaceSourceIdentity`, and no late stale completion commits.
- Hidden subtree changes mark ancestors stale without hydrating descendants.
- Binary file renders metadata-only/unavailable.
- Oversized text renders bounded non-authoritative preview or metadata-only.
- Forged, stale, cross-source, or cross-pane resource URLs/handles cannot fetch
  Worktree/File content unless they resolve through the accepted descriptor
  registry and host lease.
- Comments/comms flags and resource kinds fail closed.
- Zustand snapshots contain refs/status/facts only.
- Pierre/renderer inputs are prepared items/paths and render deltas only, never
  fetchable Bridge URLs or descriptor authority.
- Worktree/File telemetry canary excludes raw paths, source text, handles,
  capability URLs, comments, and comms while retaining allowlisted audit and
  extent-diagnostic fields.

## Implementation Notes

1. Add Worktree/File Zod schemas and inferred types in
   `src/features/worktree-file/models/**`.
2. Add Worktree/File materializer and demand policy.
3. Add minimal Worktree/File state surface with open file sessions.
4. Add a virtualized extent adapter that consumes ticket 03 provider facts before
   hydrated bodies are available.
5. Add anchor-preserving measured reconciliation and objective scroll-extent
   diagnostics.
6. Add UI/runtime surface under `src/worktree-file-surface/**`.
7. Update app routing to select Review or Worktree/File by app protocol/surface.
   This extends the router introduced in ticket 02 instead of creating a second
   root app shell.
8. Replace Vite worktree dev provider Review package fabrication with
   Worktree/File protocol frames and descriptors.
9. Keep optional Review handoff as an intent only; do not make Worktree/File a
   diff engine. Full `OpenReviewComparisonIntent` implementation is deferred
   unless the owner explicitly pulls that handoff into this epic.
10. Remove raw URL/handle authority from the Worktree/File replacement path
   before declaring the ticket cut over; raw URL parsing may remain only in
   explicitly named legacy fixtures until ticket 05 deletes or quarantines them.

## Proof Gates

Worktree/File feature unit:

```bash
pnpm --dir BridgeWeb vitest run \
  src/features/worktree-file/models/worktree-file-protocol-models.unit.test.ts \
  src/features/worktree-file/materialization/worktree-file-materializer.unit.test.ts \
  src/features/worktree-file/demand/worktree-file-demand-policy.unit.test.ts \
  src/features/worktree-file/state/worktree-file-state.unit.test.ts
```

Initial browser contract proof captured 2026-06-23:

- added Worktree/File browser Zod schemas and `z.infer` types under
  `BridgeWeb/src/features/worktree-file/models`
- added Worktree/File demand policy under
  `BridgeWeb/src/features/worktree-file/demand`
- added open-file session state primitives under
  `BridgeWeb/src/features/worktree-file/state`
- proved strict Worktree/File frame parsing, provider tree/file extent facts,
  no Review package lineage in Worktree/File invalidation frames, discriminated
  demand stimuli, generic lane mapping, stale-without-auto-fetch, manual refresh
  demand, and no file bodies stored in state
- red:
  `pnpm --dir BridgeWeb exec vitest run src/features/worktree-file/models/worktree-file-protocol-models.unit.test.ts src/features/worktree-file/demand/worktree-file-demand-policy.unit.test.ts src/features/worktree-file/state/worktree-file-state.unit.test.ts --reporter verbose`
  exited 1 before implementation because the Worktree/File model, demand, and
  state modules did not exist
- green:
  same command exited 0 with 3 files passed and 11 tests passed
- quality:
  `pnpm --dir BridgeWeb run check` exited 0 after formatting and type fixes
- hygiene:
  `rg -n "\\bas\\b|any|@ts-|eslint-disable|JSON\\.parse" BridgeWeb/src/features/worktree-file`
  found no matches, and `git diff --check` exited 0

Materializer descriptor-registration proof captured 2026-06-23:

- added Worktree/File browser materializer under
  `BridgeWeb/src/features/worktree-file/materialization`
- proved `worktree.snapshot` registers tree/status descriptors before publishing
  source facts
- proved rejected later snapshot descriptors roll back earlier registrations
- proved `worktree.fileDescriptor` registers content authority without storing
  body content in materialized deltas
- proved `worktree.fileInvalidated` remains stale metadata and does not
  register replacement content descriptors before explicit demand/refresh
- proved `worktree.reset` revokes Worktree/File source descriptors by native
  source identity
- red:
  `pnpm --dir BridgeWeb exec vitest run src/features/worktree-file/models/worktree-file-protocol-models.unit.test.ts src/features/worktree-file/materialization/worktree-file-materializer.unit.test.ts src/features/worktree-file/demand/worktree-file-demand-policy.unit.test.ts src/features/worktree-file/state/worktree-file-state.unit.test.ts --reporter verbose`
  exited 1 before implementation because `worktree-file-materializer.js` did not
  exist
- green:
  same command exited 0 with 4 files passed and 16 tests passed
- quality:
  `pnpm --dir BridgeWeb run check` exited 0 after formatting and type fixes
- hygiene:
  `rg -n "\\bas\\s+(const|[A-Z][A-Za-z0-9_]*|Readonly|Record|unknown|any|\\{)|@ts-|eslint-disable|JSON\\.parse" BridgeWeb/src/features/worktree-file`
  found no matches, and `git diff --check` exited 0

Surface runtime proof captured 2026-06-23:

- added non-React Worktree/File browser runtime under
  `BridgeWeb/src/worktree-file-surface`
- proved `worktree.fileDescriptor` materialization feeds descriptor-backed
  selected-file demand through the generic scheduler, resource executor, and
  body registry
- proved loaded file bodies stay out of Worktree/File surface state while body
  bytes are cached in `BridgeBodyRegistry`
- proved `worktree.fileInvalidated` marks open sessions stale, emits zero
  automatic content demand, and explicit refresh registers/fetches only the
  latest descriptor
- proved forged/unmaterialized descriptors fail closed before fetch
- proved source reset revokes source descriptors, marks open sessions stale for
  `sourceReset`, and prevents stale refresh commits
- red:
  `pnpm --dir BridgeWeb exec vitest run src/worktree-file-surface/worktree-file-surface-runtime.integration.test.ts --reporter verbose`
  exited 1 before implementation because
  `worktree-file-surface-runtime.js` did not exist
- green:
  `pnpm --dir BridgeWeb exec vitest run src/features/worktree-file/models/worktree-file-protocol-models.unit.test.ts src/features/worktree-file/materialization/worktree-file-materializer.unit.test.ts src/features/worktree-file/demand/worktree-file-demand-policy.unit.test.ts src/features/worktree-file/state/worktree-file-state.unit.test.ts src/worktree-file-surface/worktree-file-surface-runtime.integration.test.ts --reporter verbose`
  exited 0 with 5 files passed and 20 tests passed
- quality:
  `pnpm --dir BridgeWeb run check` exited 0 after exact optional property and
  formatting fixes
- hygiene:
  `rg -n "\\bas\\s+(const|[A-Z][A-Za-z0-9_]*|Readonly|Record|unknown|any|\\{)|\\bany\\b|@ts-|eslint-disable|JSON\\.parse" BridgeWeb/src/features/worktree-file BridgeWeb/src/worktree-file-surface`
  found no matches

App routing proof captured 2026-06-23:

- added `BridgeAppProtocolRouter` with Zod-validated app protocol metadata:
  `review` or `worktree-file`
- added the first minimal `WorktreeFileApp` mount point under
  `BridgeWeb/src/worktree-file-surface`
- updated packaged bootstrap to route through the protocol router while
  retaining Review as the default and invalid-protocol fallback
- red:
  `pnpm --dir BridgeWeb exec vitest run src/app/bridge-app-protocol-router.unit.test.tsx --reporter verbose`
  exited 1 before implementation because
  `bridge-app-protocol-router.js` did not exist
- green:
  `pnpm --dir BridgeWeb exec vitest run src/app/bridge-app-protocol-router.unit.test.tsx src/features/worktree-file/models/worktree-file-protocol-models.unit.test.ts src/features/worktree-file/materialization/worktree-file-materializer.unit.test.ts src/features/worktree-file/demand/worktree-file-demand-policy.unit.test.ts src/features/worktree-file/state/worktree-file-state.unit.test.ts src/worktree-file-surface/worktree-file-surface-runtime.integration.test.ts --reporter verbose`
  exited 0 with 6 files passed and 23 tests passed
- quality:
  `pnpm --dir BridgeWeb run check` exited 0 after formatting
- hygiene:
  `rg -n "\\bas\\s+(const|[A-Z][A-Za-z0-9_]*|Readonly|Record|unknown|any|\\{)|\\bany\\b|@ts-|eslint-disable|JSON\\.parse" BridgeWeb/src/app/bridge-app-protocol-router.tsx BridgeWeb/src/app/bridge-app-protocol-router.unit.test.tsx BridgeWeb/src/worktree-file-surface BridgeWeb/src/features/worktree-file`
  found no matches

Surface integration:

```bash
pnpm --dir BridgeWeb vitest run \
  src/worktree-file-surface/worktree-file-surface.integration.test.tsx \
  src/worktree-file-surface/worktree-open-file-session.integration.test.tsx
```

These suites must include source-reset stale-completion/drop behavior and
negative forged/stale/cross-identity descriptor or resource URL cases.

Dev server:

```bash
pnpm --dir BridgeWeb run test:dev-server:worktree
```

Quality:

```bash
pnpm --dir BridgeWeb run check
```

Browser proof:

```bash
pnpm --dir BridgeWeb run test:browser:integration -- \
  src/worktree-file-surface/test-support/worktree-file-surface.browser.integration.browser.test.tsx
```

Add this suite for stale marker, no auto-fetch, explicit refresh, tree viewport,
source-reset stale-drop, raw URL/handle rejection, renderer-boundary checks,
telemetry canary, and large/binary file behavior. Do not label jsdom/unit proof
as browser proof.

Benchmark/canary proof:

```bash
pnpm --dir BridgeWeb run benchmark:viewer
pnpm --dir BridgeWeb run test:benchmark:browser
```

These commands must include Worktree/File huge-tree window churn and open-file
extent reconciliation scenarios, or the handoff must name the exact replacement
benchmark command and artifact path. The benchmark cannot replace correctness
canaries; it records repeated viewport/load behavior under pressure.

The browser suite and dev-server proof must include:

- huge-worktree tree extent reserved from provider `treeSizeFacts` before the
  first tree-window body resolves
- open-file extent reserved for `exactLineCount`, `estimatedHeight`,
  `previewBounded`, and `unavailable` before the first content body resolves
- scroll-extent canary fields:
  `scrollTopBefore`, `scrollTopAfter`, `totalContentHeightBefore`,
  `totalContentHeightAfter`, `virtualizerTotalSizeBefore`,
  `virtualizerTotalSizeAfter`, `scrollHeightBefore`, `scrollHeightAfter`,
  `visibleRange`, `anchorItemId`, `anchorOffset`, `measuredItemIds`, and
  `reconciliationReason`
- canary pass/fail rules matching `worktree-file-surface-protocol.md` section
  14: stable anchor across non-reset reconciliation, drift within one declared
  row/line height after compensation, exact-count `scrollHeight` or
  `virtualizerTotalSize` drift within one declared row/line height before versus
  after hydration, and every estimated total-height delta attributed to
  measured-versus-estimated items
- benchmark artifacts must carry the same stable-anchor, bounded-drift, and
  exact-size-tolerance or attributed-height-delta fields for huge-worktree tree
  and open-file extent cases

## Handoff Output

- Worktree/File source identity and descriptor examples
- huge-worktree tree scroll canary sample
- open-file extent reconciliation canary sample
- explicit pass/fail readout for stable-anchor, bounded-drift, and
  exact-size-tolerance or attributed-height-delta rules
- stale marker -> no auto-fetch -> manual refresh proof
- dev-server URL and command result
- raw URL/handle rejection and descriptor/lease-backed fetch proof
- source-reset stale-completion drop proof
- renderer-boundary proof
- telemetry canary proof for path-rich Worktree/File interactions
- binary/oversized behavior proof
- confirmation that `BridgeReviewPackage` is not the Worktree/File product
  contract
- confirmation that optional Review handoff remains deferred or proof if the
  owner explicitly adds it to this epic
- changed paths and commit hash if checkpoint committed

## Stop / Replan

Stop if the browser surface can only pass by continuing to parse or push a
Review package as the Worktree/File contract. Stop if stale-open-file behavior
requires silent auto-replacement. Stop if the replacement path still treats raw
resource URL text, handle id, generation, or revision as fetch authority instead
of descriptor/lease-backed identity.
