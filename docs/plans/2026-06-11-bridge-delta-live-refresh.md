# Bridge Delta Live Refresh: DeltaBuilder, Change-Index Feeding, And Push Of Package Deltas

Planned at: 578c1084 (branch bridge-start)
Repo: /Users/shravansunder/Documents/dev/project-dev/agent-studio.bridge-start
Status: proposed

## Problem

The live-refresh layer from the spec's pipeline ("Agent/FS event → EventBus
fact → BridgeChangeIndex → BridgeReviewDelta → BridgeWeb item registry") has
its receiving end built and its producing end missing:

- `BridgeReviewDeltaBuilder` does not exist (master plan Task 3, unchecked;
  verified — no file anywhere in the tree). The `BridgeReviewDelta` model and
  the BridgeWeb `applyBridgeReviewDelta` consumer both exist and are tested.
- `BridgeChangeIndex` is a pure recording actor: no provider injection, not
  fed from pane filesystem facts, and never constructed in production
  (master plan Task 5 unchecked items; verified by grep).

Without this layer, any package shown in the review pane goes stale the moment
the agent or user touches a file, and the only recovery is a full package
rebuild.

## Current Evidence

- `find . -name "BridgeReviewDeltaBuilder*"` → nothing (verified by parent).
- `grep -rn "BridgeChangeIndex(" Sources/` → no production construction
  (verified by parent).
- `Sources/AgentStudio/Features/Bridge/Runtime/ReviewFoundation/BridgeChangeIndex.swift`
  — records endpoints/checkpoints/package revisions; no provider field, no
  event ingestion.
- `BridgeWeb/src/foundation/review-package/bridge-review-delta.ts:20-63` —
  `applyBridgeReviewDelta` handles addItems/updateItems/removeItems/moveItems/
  updateGroups/updateSummary/invalidateContent; the consumer is ready.
- Master plan: `docs/plans/2026-06-08-bridge-agent-review-foundation.md:804`
  (delta builder), `:862-866` (provider injection + filesystem feed + thin
  main-actor entry), `:892` (collation policy coverage list, partially
  unchecked).
- Spec: `docs/superpowers/specs/2026-06-10-bridge-review-foundation.md:100-113`
  (deltas update the item registry; no raw line/hunk streaming),
  `:184-190` (off-main boundary).
- Upstream fact source exists:
  `Sources/AgentStudio/Core/State/MainActor/Atoms/PaneFilesystemProjectionAtom.swift`
  (pane-scoped filesystem facts; per master plan Current Code Evidence).

## Non-Goals

- No Pierre CodeView integration (LUNA-338) — deltas stop at the BridgeWeb
  item registry contract.
- No new event-bus namespaces and no commands on the bus (decision table:
  bus is facts-only; Bridge consumes downstream of the existing projection).
- No durable checkpoint storage (runtime-local identity only, per spec).
- No provider implementation work (protocol + fake only).

## Scope

Write surfaces:
- Create
  `Sources/AgentStudio/Features/Bridge/Runtime/ReviewFoundation/BridgeReviewDeltaBuilder.swift`
  — pure delta assembly over change-index facts + package-local revisions.
- `Sources/AgentStudio/Features/Bridge/Runtime/ReviewFoundation/BridgeChangeIndex.swift`
  — provider injection; ingestion API for filesystem facts and explicit
  source loads; stale-generation discipline.
- `Sources/AgentStudio/Features/Bridge/Runtime/BridgePaneController.swift` /
  `BridgeRuntime.swift` — construct and feed the index from pane filesystem
  context (thin main-actor entry: collect fact, hand to actor, publish
  resulting delta metadata).
- Tests: new `BridgeReviewDeltaBuilderTests.swift`,
  `BridgeChangeIndexTests.swift` expansion, controller-level feed test with
  the fake provider.

Read-only context:
- `Sources/AgentStudio/Features/Bridge/Runtime/ReviewFoundation/BridgeChangeCollator.swift`
  — grouping semantics deltas must respect.
- `docs/architecture/swift_react_bridge_design.md` §6 — push plane the delta
  envelope rides.

## Task Sequence

1. **`BridgeReviewDeltaBuilder` (pure).** Inputs: current package snapshot
   facts (ordered IDs, descriptors, groups, summary, generation, revision) +
   a set of changed/added/removed paths with provenance. Output:
   `BridgeReviewDelta` with explicit operations and bumped package-local
   revision; item updates bump `itemVersion` and cache keys for
   render-significant changes; content invalidation ops for loaded handles.
   Property: applying the delta to the old package equals rebuilding from the
   new facts. Assertion scope: equality on `itemsById`, `orderedItemIds`,
   `groups`, and `summary`; ignore `revision` and
   `generatedAtUnixMilliseconds` (differ by design). Scope the property to
   fixed-point endpoint fixtures (commits/snapshots) — working-tree endpoints
   can mutate between build and delta, so they are covered by the
   content-invalidation ops, not by equivalence. Precondition: verify
   `BridgeEndpointComparison.changedFiles` ordering is deterministic for the
   same endpoint pair (the builder consumes it order-sensitively); pin with a
   comment + test if undocumented.
2. **Change-index ingestion.** Add `ingest(filesystemFacts:)` and
   `ingest(explicitLoad:)` entry points on `BridgeChangeIndex`; the index
   correlates facts to the active package/generation and asks the delta
   builder for the resulting delta. Inject `any BridgeReviewSourceProvider`
   for descriptor refresh where a changed path needs re-classification or
   re-hashing (off-main, per spec).
3. **Stale-generation discipline.** Facts arriving for a generation that is no
   longer active are dropped with a trace, never built into deltas; a delta is
   published only if its generation matches the active package at publish
   time.
4. **Production feed.** Discovery first: `PaneFilesystemProjectionAtom`
   exposes polled state (`snapshotsByPaneId`/`contextsByPaneId`) and
   imperative setters — **no async stream** (verified). Decide the feed
   mechanism before coding: (a) `withObservationTracking` re-arm loop on the
   atom from the controller (matches existing app patterns), or (b) consume
   the pane runtime envelopes the projection itself is derived from,
   downstream of the bus (CLAUDE.md: bridge consumers work downstream of the
   pane filesystem projection). Pick (a) unless it double-fires per envelope;
   record the choice in the PR. The controller then forwards facts to the
   index and publishes resulting deltas through the push plane. Main-actor
   body stays collect-hand-off-publish.
5. **Coalescing.** Burst facts (rebase, install) must coalesce inside the
   index (injected clock; bounded window — propose 250ms: upstream FS
   debounce is already 500ms, so the index window only absorbs multi-batch
   bursts; document the combined latency budget) so BridgeWeb receives
   consolidated deltas, not one per file event. Cover the master plan's
   collation cases that apply at delta level (folder, file-class, change-kind
   at minimum).
6. **Tests.** Delta builder: add/update/remove/move/group/summary/invalidate
   ops + the rebuild-equivalence property. Index: ingestion → delta with
   correct generation/revision; stale-generation drop; coalescing under burst
   with injected clock. Controller: fact → published delta envelope with fake
   provider.

## Proof Gates

- Red/green: all new suites; rebuild-equivalence property is the keystone.
- Coalescing gate: with the injected clock held, N burst facts produce zero
  deltas; advancing the clock past the window produces exactly one
  consolidated delta. The same test with a `.zero`-window index must fail
  (proves the gate is live).
- Focused validation:
  `mise run test -- --filter "BridgeReviewDeltaBuilder"`,
  `mise run test -- --filter "BridgeChangeIndex"`.
- Full validation: `mise run test`, `mise run lint` — zero errors.
- Manual: with a loaded package in a Bridge pane (after production wiring
  plan), touch a file in the worktree — BridgeWeb receives a delta envelope
  (push logging) within the coalescing window; no full package re-push.

## Stop Conditions

- Stop if delta semantics require contract changes to `BridgeReviewDelta`
  (model is frozen by spec vocabulary) — propose the spec amendment first.
- Stop if feeding from `PaneFilesystemProjectionAtom` requires changing that
  atom's shape or the runtime event contracts — that is a Core boundary
  change needing discussion (CLAUDE.md atom-boundary rule).
- This plan depends on
  `2026-06-11-bridge-foundation-production-wiring.md` for the active
  package/generation to exist in production; execute after it.

## Risks

- Delta-vs-rebuild divergence is the classic failure of incremental systems —
  the rebuild-equivalence property test is the mitigation; keep it as a
  permanent invariant test, not a one-off.
- Burst coalescing windows interact with the FS pipeline's existing 500ms
  debounce upstream; pick the index window relative to that (document the
  combined latency budget in the plan PR).

## Handoff Prompt

```text
Use implementation-execute-plan on this plan.

Repo: /Users/shravansunder/Documents/dev/project-dev/agent-studio.bridge-start
Plan: docs/plans/2026-06-11-bridge-delta-live-refresh.md
Start by validating the plan against current git state before editing files.
Prerequisite: 2026-06-11-bridge-foundation-production-wiring.md must be
landed (active package in production). Tasks 1 and 2-3 can run as two
bounded slices; 4-6 integrate. Parent owns integration and final proof
(mise run test, mise run lint).
```
