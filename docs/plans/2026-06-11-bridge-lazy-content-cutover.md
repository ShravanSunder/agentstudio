# Bridge Lazy Content Cutover: Remove Eager Preload From Package Construction

Planned at: 578c1084 (branch bridge-start)
Repo: /Users/shravansunder/Documents/dev/project-dev/agent-studio.bridge-start
Status: proposed

## Problem

The canonical spec (`docs/superpowers/specs/2026-06-10-bridge-review-foundation.md`,
"Delivery Pipeline") mandates metadata push + lazy content pull, and explicitly
names this failure mode: "If current implementation code eagerly preloads
handle contents during package construction, treat that as an implementation
gap against this spec." That gap is real and verified:
`BridgeReviewPipeline.loadPackage` builds the package, then loops **every item
descriptor × every role handle** and calls `provider.loadContent(...)` +
`contentStore.register(...)` before returning. Package publication is blocked
on loading all file bytes — for a 1,000-file comparison that's 1,000+
provider loads and the full byte set resident in the content store before the
user sees anything.

This plan also owns the two unchecked Task 3 items from the master plan that
only make sense in the lazy model: cancellation and stale-review-generation
behavior at the actor boundary.

## Current Evidence

- `Sources/AgentStudio/Features/Bridge/Runtime/ReviewFoundation/BridgeReviewPipeline.swift:35-47`
  — the eager loop (verified by parent read):
  `for descriptor in package.itemsById.values { for handle in
  descriptor.contentRoles.allHandles { try await provider.loadContent(...) ;
  await contentStore.register(result) } }` before
  `return BridgeReviewPipelineResult(package:, registeredContentHandles:)`.
- `Sources/AgentStudio/Features/Bridge/Runtime/ReviewFoundation/BridgeContentStore.swift:29-42`
  — `load(handleId:requestedGeneration:)` serves only pre-registered content
  and throws `missingContent` otherwise; there is no on-miss provider fetch,
  which is why the pipeline preloads.
- `Tests/AgentStudioTests/Features/Bridge/BridgeReviewPipelineTests.swift`
  (~lines 42-61) — asserts content is loaded into the store as a side effect
  of `loadPackage`, pinning the wrong behavior.
- Master plan unchecked items:
  `docs/plans/2026-06-08-bridge-agent-review-foundation.md:805`
  ("cancellation and stale-review-generation behavior at the actor boundary")
  and `:899` (`diff.requestFileContents` redundancy decision interacts with
  the single-content-path outcome here).
- Spec: `docs/superpowers/specs/2026-06-10-bridge-review-foundation.md:142-164`
  (Delivery Pipeline), `:128-140` (content handles are the only lazy pointer).

## Non-Goals

- No change to contract model shapes (`BridgeContentHandle`,
  `BridgeReviewPackage`, descriptors) — only to when bytes move.
- No BridgeWeb changes (the TS `content-resource-loader` already fetches
  lazily by handle URL).
- No provider implementation work (git lane owns that); the lazy fetch path is
  expressed against the `BridgeReviewSourceProvider` protocol and proven with
  the existing fake.
- Wiring the pipeline into `BridgePaneController` is the production-wiring
  plan (`2026-06-11-bridge-foundation-production-wiring.md`), not this one.

## Scope

Write surfaces:
- `Sources/AgentStudio/Features/Bridge/Runtime/ReviewFoundation/BridgeReviewPipeline.swift`
  — remove the preload loop; register handle *identities* only.
- `Sources/AgentStudio/Features/Bridge/Runtime/ReviewFoundation/BridgeContentStore.swift`
  — on-miss lazy load through an injected provider, single-flight per handle,
  generation validation before and after load, bounded cache.
- `Sources/AgentStudio/Features/Bridge/Models/ReviewFoundation/BridgeReviewPipelineResult.swift`
  — replace `registeredContentHandles` (loaded) with registered-handle
  identities or drop the field.
- Tests: `BridgeReviewPipelineTests.swift`, `BridgeContentStoreTests.swift`,
  `BridgeSchemeHandlerTests.swift`.

Read-only context:
- `Sources/AgentStudio/Features/Bridge/Transport/BridgeSchemeHandler.swift` —
  the consumer of `contentStore.load`; its reply path must not change shape.
- `docs/superpowers/specs/2026-06-10-bridge-review-foundation.md` — Delivery
  Pipeline + trust boundary sections.

## Task Sequence

1. **Registry split in `BridgeContentStore`.** Separate "known handles"
   (identity + expected hash + generation, registered at package build) from
   "loaded content" (bytes). The store gains the provider via constructor
   injection (`init(provider: any BridgeReviewSourceProvider, ...)`) so tests
   exercise the lazy path with the existing fake in isolation — this makes
   task 2's zero-loadContent gate provable independently.
   `load(handleId:requestedGeneration:)` becomes: validate handle known →
   validate generation current → serve cached bytes or fetch via the injected
   provider, with single-flight de-duplication for concurrent requests to the
   same handle (per-handle in-flight `Task` map inside the actor — bounded by
   construction, no unbounded task spawn).
   Verify returned content hash matches the handle's `contentHash`; mismatch
   is a typed failure, not silent acceptance. The current
   `BridgeProviderFailure` vocabulary has no case for this (verified: 7 cases,
   `BridgeProviderFailure.swift:4-10`) — add
   `case contentHashMismatch(handleId: String, expectedHash: String,
   actualHash: String)` rather than overloading `providerFailed(message:)`,
   and mirror it in the TS failure type if provider failures cross the wire
   (verify catch sites first).
2. **Strip the preload loop.** `loadPackage` registers handle identities with
   the store and returns immediately after package build. Update
   `BridgeReviewPipelineResult` accordingly.
3. **Cancellation + staleness at the boundary.** When a new package/generation
   is activated for a pane source: in-flight `loadContent` tasks for prior
   generations are cancelled, queued requests for stale generations are
   rejected with `staleReviewGeneration`, and loaded bytes for dead
   generations are evicted. Coordination: the trust-boundary hardening plan
   (task 4) renames this failure's fields to
   `storedGeneration`/`requestedGeneration` — adopt the renamed shape here if
   that plan lands first; otherwise keep the current shape and let it rename.
   Apart from the new `contentHashMismatch` case in task 1, no other error
   vocabulary changes.
4. **Retarget tests.** Pipeline test asserts `loadPackage` performs **zero**
   `loadContent` calls (count on the fake provider); content store tests cover
   on-miss fetch, single-flight (N concurrent requests → 1 provider call),
   hash mismatch, stale-generation rejection mid-flight, and eviction on
   generation bump. Scheme handler test proves first fetch of an unloaded
   handle serves bytes end-to-end via the lazy path.
5. **Bounded cache policy.** Two-level eviction: (a) generation eviction is
   primary — activating a new generation drops all loaded bytes from prior
   generations (task 3 already requires this); (b) within the active
   generation, cap loaded bytes at
   `AppPolicies.Bridge.contentCacheMaxBytes` (propose 50 MB; byte-based, not
   count-based, since file sizes vary by orders of magnitude) with LRU
   eviction. Proof: a test fills past the cap and asserts oldest-accessed
   handles are evicted while the most recent stays served; a
   generation-bump test asserts prior-generation bytes are gone. Document the
   choice in the spec's Delivery Pipeline section if the cap is
   user-observable.

## Proof Gates

- Red/green: the zero-loadContent-during-loadPackage assertion fails before
  task 2 and passes after; single-flight and staleness tests are new. The
  slow-provider fake used for cancellation/staleness tests must gate on a
  test-controlled continuation or injected clock (repo rule: no `Task.sleep`
  in test bodies; deterministic resume points, not wall-clock delays).
- Focused validation:
  `mise run test -- --filter "BridgeReviewPipeline"`,
  `mise run test -- --filter "BridgeContentStore"`,
  `mise run test -- --filter "BridgeSchemeHandler"`.
- Full validation: `mise run test`, `mise run lint` — zero errors.
- Performance gate: synthetic 1,000-item comparison via the fake provider —
  `loadPackage` completes without any content I/O (assert provider call count
  and wall time bound with injected scheduling, no wall-clock sleeps).

## Stop Conditions

- Stop if single-flight + cancellation force the content store to grow beyond
  a focused actor (e.g. needing a request-coalescing subsystem) — propose the
  split before building it.
- Stop if hash verification reveals the provider contract cannot supply
  stable hashes for working-tree endpoints (mutating files) — that is a
  contract-semantics question for the spec, not a code workaround.

## Risks

- Working-tree content can change between package build and lazy fetch; hash
  mismatch handling (typed failure → BridgeWeb shows stale-item state, change
  index later issues a delta) must be explicit, not crash or silently serve
  mismatched bytes. The hash-mismatch test pins this.
- Cancellation interacting with WebKit scheme replies: the scheme handler
  already finishes its stream with an error on throw; ensure cancellation
  surfaces as a typed failure, not a hang.

## Handoff Prompt

```text
Use implementation-execute-plan on this plan.

Repo: /Users/shravansunder/Documents/dev/project-dev/agent-studio.bridge-start
Plan: docs/plans/2026-06-11-bridge-lazy-content-cutover.md
Start by validating the plan against current git state before editing files.
Execute tasks in order — task 1 (store split) gates everything. Parent owns
integration and final proof (mise run test, mise run lint).
```
