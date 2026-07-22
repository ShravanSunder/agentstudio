# Bridge Foundation Production Wiring: Pipeline, Provider Seam, And Query-Backed loadDiff

Planned at: 578c1084 (branch bridge-start)
Repo: /Users/shravansunder/Documents/dev/project-dev/agent-studio.bridge-start
Status: proposed

## Problem

The review foundation is structurally correct but **unreachable from any
production code path**. Verified: `BridgeReviewPipeline`,
`BridgeGitReviewSourceProvider`, and `BridgeChangeIndex` are constructed only
in tests; the only production-instantiated piece is the content store
(`BridgePaneController.swift:55`). Meanwhile `diff.loadDiff` still computes
patch stats and never submits a `BridgeReviewQuery` or publishes a
`BridgeReviewPackage` — the master plan's own unchecked Task 6 item. Until
this wiring exists, every downstream milestone (shell proof, deltas, Pierre)
has nothing to render.

Constraint from the sibling lane: the Git data-plane plan was judged
not-ready by the 2026-06-10 review swarm (concurrency-ownership and
contract-shape blockers), so this wiring must stand on the
`BridgeReviewSourceProvider` protocol with an injectable implementation —
production uses whatever provider is registered, tests and the interim build
use the existing fake. Bridge must not block on the git lane.

## Current Evidence

- `grep -rn "BridgeReviewPipeline(" Sources/` → only the default-argument in
  its own initializer; no production construction (verified by parent).
- `grep -rn "BridgeChangeIndex(\|BridgeGitReviewSourceProvider(" Sources/` →
  no production construction (verified by parent).
- `Sources/AgentStudio/Features/Bridge/Runtime/BridgePaneController.swift:55`
  — `let reviewContentStore = BridgeContentStore()` exists and feeds the
  scheme handler; the pipeline does not.
- `Sources/AgentStudio/Features/Bridge/Runtime/BridgePaneController+DiffCommands.swift:11-23`
  — `case .loadDiff` sets status, advances epoch, derives stats, ingests
  `.diffLoaded(stats:)`; no query, no package, no handles.
- Master plan unchecked items:
  `docs/plans/2026-06-08-bridge-agent-review-foundation.md:862-866` (provider
  injection, filesystem feed, thin main-actor entry points, fake provider in
  tests), `:897` (loadDiff → query/package), `:899`
  (`diff.requestFileContents` redundancy decision).
- Spec: `docs/superpowers/specs/2026-06-10-bridge-review-foundation.md:166-190`
  (MainActor boundary — controller collects context, awaits off-main, then
  publishes compact metadata).
- Memory/context: git foundation plan review verdict not_ready (2026-06-10
  swarm) — provider seam must tolerate a missing real backend.

## Non-Goals

- No git backend implementation and no changes to
  `docs/superpowers/plans/2026-06-08-agentstudio-git-bridge-foundation.md`
  (its boundary language was audited and is correct).
- No delta/live-refresh work (`2026-06-11-bridge-delta-live-refresh.md` owns
  `BridgeReviewDeltaBuilder` and change-index feeding).
- No eager-vs-lazy content changes (owned by
  `2026-06-11-bridge-lazy-content-cutover.md`; this plan should land after it
  or rebase on it).
- No BridgeWeb rendering work beyond what the existing push plane already
  delivers.

## Scope

Write surfaces:
- `Sources/AgentStudio/Features/Bridge/Runtime/BridgePaneController.swift` —
  own a `BridgeReviewPipeline` (constructed with the injected provider and
  the existing `reviewContentStore`); provider injection seam.
- `Sources/AgentStudio/Features/Bridge/Runtime/BridgePaneController+DiffCommands.swift`
  — `loadDiff` (or a successor `review.loadPackage` RPC method) builds a
  `BridgeReviewQuery`, awaits the pipeline off-main, publishes the package.
- `Sources/AgentStudio/Features/Bridge/State/BridgePaneState.swift` /
  `BridgeDomainState.swift` — hold the published package metadata for the
  push plane (runtime state only; no new atom or persistence per spec).
- `Sources/AgentStudio/Features/Bridge/Transport/Methods/DiffMethods.swift` —
  method surface alignment; resolve the `diff.requestFileContents` redundancy
  decision (scheme fetch is the single content path per spec — remove the RPC
  duplicate unless a concrete consumer remains).
- Tests: `BridgePaneControllerTests.swift`, push-plane tests, WebKit
  serialized tests as needed.

Read-only context:
- `docs/architecture/bridge_native_runtime_architecture.md` — Review build,
  publication, and product transport boundaries.
- `Sources/AgentStudio/Features/Bridge/State/Push/` — PushPlan/Slice
  infrastructure the package publication must reuse.

## Task Sequence

1. **Provider seam.** Constructor injection: `BridgePaneController` has
   exactly one production construction site
   (`PaneCoordinator+ViewLifecycle.swift:128`, verified), so adding a
   `provider:` init parameter does not ripple — `PaneCoordinator` resolves the
   provider once per pane and passes it down. Production default:
   `BridgeGitReviewSourceProvider` only if its dependencies exist on this
   branch; otherwise an explicit placeholder. **Failure moment decision:**
   the placeholder's `init` succeeds; its first provider call throws
   `providerUnavailable` (defer failure to user action, so pane creation
   never fails on a missing backend) — never a silent stub. Tests inject the
   fake.
2. **Pipeline ownership.** Construct one `BridgeReviewPipeline` per pane
   controller wired to `reviewContentStore` so scheme-handler content serving
   and pipeline registration share the store (verify this is already true for
   the store instance — evidence says yes).
3. **Query-backed load.** Method name decision: **keep `diff.loadDiff`** —
   BridgeWeb has no RPC caller yet, but the method surface is a contract and
   renaming buys nothing this milestone; record `review.loadPackage` as a
   possible later rename in the method comment. Precondition: verify which
   push-plan slice carries `BridgeReviewPackage` metadata (architecture doc
   §6.8 + the live `diffPushPlan`/`reviewPushPlan` in `BridgePaneController`);
   if no slice fits, propose the slice shape explicitly before wiring (the
   stop condition below enforces this). Then replace the stats-only body:
   build `BridgeReviewQuery` from the command payload (payload shape: base +
   head endpoints, optional filter/grouping overrides — document in the
   method comment), mint the next `BridgeReviewGeneration`, await
   `pipeline.loadPackage`, publish package metadata through the push plane,
   and keep the main-actor body to collect-await-publish (spec MainActor
   boundary). Keep stats derivable from the package summary rather than a
   parallel code path.
4. **Method-surface cleanup.** Decide and execute the
   `diff.requestFileContents` question: with scheme-fetch as the single
   content path, remove the RPC content fetch (hard cutover, repo convention)
   or document the surviving consumer in the method comment.
5. **Failure publication.** Provider failures (including the placeholder's
   `providerUnavailable`) surface as a typed diff/review status in pane state
   — visible to BridgeWeb, no silent failure, no crash.
6. **Tests.** Controller test: dispatch loadDiff with fake provider → package
   published with correct generation, items, and registered handles;
   provider-unavailable test asserts the pane's diff/review state carries a
   typed failure value that the push plane delivers (assert on the state
   field, not just the thrown error — no silent offline behavior); pre-ready
   dispatch still rejected (existing router behavior, regression-pinned).

## Proof Gates

- Red/green: package-publication test fails against the stats-only handler.
- Focused validation:
  `mise run test -- --filter "BridgePaneController"`,
  `mise run test -- --filter "BridgeReviewPipeline"`, plus the WebKit
  serialized bridge lane via the project test command.
- Full validation: `mise run test`, `mise run lint` — zero errors.
- Manual: debug build, open a Bridge pane, trigger load — BridgeWeb receives a
  package envelope (observable via existing push logging) even with the
  placeholder provider returning a typed failure.

## Stop Conditions

- Stop if publishing package metadata through the existing push plane requires
  new push-plan slices whose shape is ambiguous in the architecture doc —
  surface the shape question before inventing one (architecture doc §6.8 is
  the contract).
- Stop if `loadDiff`'s command payload cannot express the minimal query
  (endpoints) without expanding the RPC method schema — propose the method
  change explicitly first (method surface is a contract with BridgeWeb).
- Stop if the git provider's dependencies are partially present and wiring it
  half-on would mask failures — prefer the explicit placeholder and report.

## Risks

- Sequencing with the lazy-content plan: if this lands first, the eager
  preload makes loads slow but correct; if lazy lands first, this plan's tests
  must assert zero content I/O at load. Either order works; rebase whichever
  is second.
- Method removal (`diff.requestFileContents`) is a BridgeWeb-visible contract
  change — BridgeWeb has no caller today (verified scaffold has no RPC
  client), so the cutover window is now, before one grows.

## Handoff Prompt

```text
Use implementation-execute-plan on this plan.

Repo: /Users/shravansunder/Documents/dev/project-dev/agent-studio.bridge-start
Plan: docs/plans/2026-06-11-bridge-foundation-production-wiring.md
Start by validating the plan against current git state before editing files.
Check whether 2026-06-11-bridge-lazy-content-cutover.md has landed and note
the sequencing consequence from the Risks section. Execute tasks in order.
Parent owns integration and final proof (mise run test, mise run lint, manual
push-envelope check).
```
