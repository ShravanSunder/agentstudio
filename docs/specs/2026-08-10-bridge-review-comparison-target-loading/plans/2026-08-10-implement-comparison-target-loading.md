# Implement Bridge Review Comparison Target Loading

Planning result: `draft`

## Governing authority

- Requirements: [`../user-requirements.md`](../user-requirements.md)
- Specification: [`../specification.md`](../specification.md)
- Program Design: [`../program-design.md`](../program-design.md)
- Accepted design identity: Agent Studio branch `review-comments` at
  `a9f100f45c135f287545f3f5c316eda821a8a7e2`.
- Design-review boundary: the owner accepted the corrected design after the
  completed external and Claude Opus review/remediation work and explicitly
  prohibited another design review. This plan adds no design-review gate.
- Planned upstream source: `agentstudio-git` worktree
  `/Users/shravansunder/Documents/dev/project-dev/agentstudio-git.pr0-review-contribution`,
  branch `pr0-review-contribution`, at
  `8525ebd88abdd85a0879a3bc20f9949aa606bc14`, matching its remote branch at
  planning time.

This plan is governed only by the three artifacts in this folder. The older
PR0 plan is historical context and is not execution authority for target
discovery, loading, transport, or catalog UI.

## Goal and boundary

Correct the existing PR0 implementation so Review initialization carries only
compact current-comparison truth, while activating Branch selection performs
one bounded request through the established command and content routes.

```text
Review initialization                   Branch selection activates
        │                                         │
        ▼                                         ▼
resolve one default ref                    typed command request
load core.sqlite intent                           │
        │                                         ▼
        ▼                                  bounded Git capture
compact metadata                                  │
                                                  ▼
                                         one content descriptor
                                                  │
                                                  ▼
                                        virtualized Combobox rows
```

In scope:

- the two focused `agentstudio-git` reads;
- compact default-target identity in current Review presentation;
- `review.comparisonTargets.query` plus
  `review.comparisonTargets` content;
- one pane-session-owned pending/claimed descriptor body;
- worker query lifecycle and virtualized Branch selector;
- the accepted modal aesthetics using existing Base UI/shadcn-style owners;
- development-server, packaged-app, SQLite-regression, and full PR proof.

Out of scope:

- comparison semantics, basis choices, or Base Branch state-block redesign;
- any `core.sqlite` schema or durable-intent change;
- caches, pagination, prefetch, services, watchers, fetches, new transports, or
  metadata subscriptions;
- annotations, comments, delivery, or agent IPC;
- staged/unstaged redesign or a generalized Git client.

## Current repository evidence

- `BridgePaneController.adoptInitialContributionTargetIfEligible` currently
  calls `reviewComparisonTargets()`, publishes the complete catalog, and uses
  it to initialize the default target.
- `BridgePaneRefreshAdmissionCoordinator` and
  `BridgePaneReviewComparisonPresentation` currently retain `targetCatalog`,
  which moves every row through `pane.presentation`.
- `BridgeDevelopmentProductHost` performs a second eager catalog load during
  construction.
- `BridgeReviewComparisonControl` and
  `BridgeReviewComparisonBranchSelector` consume the metadata catalog and map
  every matching branch row into the DOM.
- The current owned `Combobox` source exists under
  `BridgeWeb/src/components/ui/`; `@tanstack/react-virtual` is not currently a
  BridgeWeb dependency.
- Existing product calls, descriptor-authorized content, foreground refresh
  admission, comm-worker abort/work-generation state, and
  `.selectedVisibleContent` Git scheduling are the required seams. No new
  route, queue, or scheduler is needed.
- `agentstudio-git` currently exposes one unbounded
  `reviewComparisonTargets(for:)` operation. Its catalog rows have no tip
  commit time and its reader enumerates before resolving the default.

## Slice graph

```text
S1 agentstudio-git bounded contracts/readers/publish
                         │
                         ▼
S2 compact native truth + request-scoped command/content
                         │
                         ▼
S3 worker lifecycle + virtualized accepted picker UI
                         │
                         ▼
S4 development + packaged integration proof
                         │
                         ▼
S5 focused implementation review, remediation, PR readiness
```

The slices are serial because Agent Studio must pin a remotely reachable
upstream contract before the hard cutover compiles, and each later slice proves
the real output of the preceding one. Aesthetic advice may run while S1/S2 are
implemented, but it cannot change the accepted product shape.

## S1 — Replace the upstream unbounded catalog API

Repository:
`/Users/shravansunder/Documents/dev/project-dev/agentstudio-git.pr0-review-contribution`

Write surfaces:

- `Sources/AgentStudioGitContracts/AgentStudioGitSDK.swift`
- `Sources/AgentStudioGitContracts/GitReviewComparisonContracts.swift`
- `Sources/AgentStudioGitLocal/LibGit2AgentStudioGitLocalClient.swift`
- focused readers under `Sources/AgentStudioGitLocal/Review/`
- focused contract, real-Git integration, blocking-executor, and consumer
  compatibility tests under `Tests/AgentStudioGitTests/`

Change:

1. Replace `reviewComparisonTargets(for:)` with a constant-scope
   `resolveReviewDefaultTarget` operation and one bounded
   `captureReviewComparisonTargets` operation.
2. The resolver opens only `refs/remotes/origin/HEAD`, validates its symbolic
   remote-tracking target, opens that target, and peels one commit.
3. The capture accepts `capturedAt`, `cutoff`, `maximumRows`, and an optional
   current canonical branch identity. It enumerates local and remote-tracking
   branches once, excludes symbolic remote `HEAD`, reads exact tip OID and
   commit time, deduplicates by canonical ref identity, retains default/current
   exceptions, applies `cutoff <= tip time <= capturedAt`, orders
   deterministically, and reports truncation.
4. Use the current libgit2 read-only repository/executor patterns. Add no fetch,
   ref write, worktree mutation, or Git lock.
5. Hard-cut every package consumer and fake to the two new contracts; leave no
   local compatibility API.

Red/green proof:

- Add failing tests first for constant-scope default lookup; malformed,
  missing, direct, dangling, and unsupported default refs; cutoff edges and
  future-dated tips; mandatory old default/current rows; duplicate role
  collapse; stable ordering; row truncation; symbolic remote `HEAD` exclusion;
  no-fetch/read-only behavior; and Codable/consumer compatibility.
- Run focused package suites while iterating, then `mise run check` from the
  `agentstudio-git` root.

Publication gate:

- Commit and push the focused upstream change, obtain a remotely reachable
  exact revision, and require its PR/checks to be current before Agent Studio
  pins it. Do not merge either repository without separate authorization.

Stop/replan if the existing libgit2 executor cannot perform both reads without
a new ownership model or a write/lock-producing API.

## S2 — Cut native presentation to compact truth and add on-demand content

Write surfaces:

- `Sources/AgentStudio/Infrastructure/AppPolicies.swift`
- Review comparison transport contracts and strict JSON under
  `Sources/AgentStudio/Features/Bridge/Models/Transport/`
- `BridgePaneController+ReviewContribution.swift`
- `BridgePaneRefreshAdmissionCoordinator.swift`
- `BridgeDevelopmentProductHost.swift` and
  `BridgeDevelopmentProductHost+ReviewComparison.swift`
- `AgentStudioGitBridgeReviewDataClient*` and Review source-provider contracts
- `BridgePaneProductSchemeProvider` plus adjacent control/content dispatch and
  demand-authority owners
- `Package.swift`, `Package.resolved`, and focused Swift tests/fixtures

Change:

1. Pin the exact published S1 revision and update the dependency identity test.
2. Replace presentation `targetCatalog` with nullable compact
   `repositoryDefaultTarget { remoteName, branchName }`; update both packaged
   and development hosts to resolve only the designated default during Review
   initialization/attempts.
3. Preserve the existing `core.sqlite` intent and target-selection mutation.
   Default identity is derived presentation truth and is never persisted.
4. Before default lookup, clear the prior compact identity and capture the
   existing repository, Review generation, product admission, and foreground
   work admission. Publish only a current completion; a current failure leaves
   identity absent.
5. Add `review.comparisonTargets.query` to the exhaustive call registries and
   `review.comparisonTargets` to the exhaustive content registries. The browser
   supplies no repository/ref/capacity authority.
6. Project live repository and current symbolic target at query admission,
   acquire existing foreground work, schedule S1 capture as
   `.selectedVisibleContent`, apply 30-day/2,000-row policy, encode within the
   1 MiB Bridge policy, then revalidate before installing descriptor backing.
7. Keep one immutable query body per pane session in the existing scheme
   provider actor: pending is replaced by a newer query, open claims once, and
   terminal/cancel/reset/session teardown releases it. Add no TTL or cache.
8. Map the new content kind explicitly to selected demand and ordinary
   foreground refresh admission; do not use Review-body continuation admission.
9. Remove every catalog row from presentation, metadata fixtures, and strict
   metadata key corpora. The command response contains only the descriptor.

Focused proof:

- Swift contract/strict-JSON tests reject `targetCatalog` and accept only the
  compact default identity.
- Host/controller tests prove restored intent still resolves default identity,
  absent intent initializes once, stale/failing lookup cannot publish a false
  marker, and post-construction target mutations are read live in both hosts.
- Query-source tests prove row/byte bounds, single claim, newer-query pending
  replacement, cancellation/admission loss before install and during stream,
  and cleanup at every terminal/session edge.
- Demand/scheduler tests prove `.selected` plus foreground admission and
  `.selectedVisibleContent` rather than `.unspecified` or Review continuation.
- Existing workspace restart proof remains green and confirms no catalog,
  resolved OID, or query state enters `core.sqlite`.

Integration gate S2→S3: one native typed query must yield a descriptor whose
content frames decode to the bounded catalog while the corresponding metadata
frame contains only compact current-comparison state.

## S3 — Move query lifetime into the worker and render the accepted picker

Required skill: apply `agentstudio-bridgeweb-react-ui` before visible edits.

Write surfaces:

- `BridgeWeb/src/core/comm-worker/bridge-product-*-contracts.ts`
- worker product controller, runtime protocol, RPC client, and pane-presentation
  projection files adjacent to the existing comparison path
- `BridgeWeb/src/app/bridge-review-comparison-control.tsx`
- `BridgeWeb/src/app/bridge-review-comparison-branch-selector.tsx`
- `BridgeWeb/src/components/ui/combobox.tsx` only for reusable owned-primitive
  corrections
- `BridgeWeb/package.json` and lockfile for `@tanstack/react-virtual`
- focused unit, browser, integration, accessibility, and Vite E2E tests

Change:

1. Add one worker comparison-query controller that issues the typed call,
   opens the returned descriptor through existing content transport, validates
   and decodes it, and returns only the newest correlated result.
2. Bind each query to the existing pane `workSignal`, work-admission generation,
   pane session, and request identity. Closing, Commit mode, pane replacement,
   foreground loss, or a newer request rejects late results and leaves current
   comparison untouched.
3. Keep picker states limited to `idle | loading | ready | empty | failed`.
   Remembered Commit mode focuses commit input and sends no query; Branch
   activation focuses search and sends one query; failure offers retry.
4. Keep the accepted `COMPARE WORKTREE` hierarchy and separate compact Base
   Branch state block. Do not redesign comparison semantics or move a basis
   dropdown into status text.
5. Reuse the owned Combobox input/item/list primitives and current theme
   tokens. Normalize hierarchy, spacing, boundaries, typography, and row states
   from the bounded Claude Opus aesthetic advice only where they fit the
   accepted shape and existing design system.
6. Use Base UI external virtualization with `@tanstack/react-virtual` and eight
   overscan rows. Filtering covers the complete returned catalog; highlight,
   active-descendant, keyboard selection, and scroll-to-highlight work for
   unmounted rows.
7. Every ready/empty result shows a quiet previous-30-days explanation.
   Truncation adds the capacity/exact-commit note. Rows preserve local/remote
   distinction, default/current roles, abbreviated revision, and full assistive
   revision without a noisy second descriptive line.

Red/green and visual proof:

- Add failing tests first for Commit-no-query, Branch query/focus, mode-switch
  focus, loading/ready/empty/failed/retry, latest-request-wins, close/admission
  cancellation, and current-comparison non-mutation.
- Browser tests prove a 2,000-row catalog filters and keyboard-navigates while
  only the visible rows plus bounded overscan are mounted.
- Run focused BridgeWeb unit, integration, and browser lanes.
- Use the Swift development backend plus Vite for screenshots and interaction
  proof of Branch loading/ready/empty/failed and Commit mode. Verify hierarchy,
  search boundary, focus, spacing, theme colors, keyboard navigation, and row
  mounting in the real production-backed path.

Stop/replan if achieving Base UI active-descendant semantics would require
replacing the owned Combobox or inventing a shared virtualization framework.

## S4 — Prove both production-backed hosts and the durable boundary

Integration proof:

1. Start the existing isolated Swift Bridge development backend and Vite using
   the repository AGENTS.md commands. Prove Review opens without a catalog
   query, Commit mode remains query-free, Branch activation performs command →
   descriptor → content, and selection uses the unchanged comparison update.
2. Use a production-scale fixture with recent, old, default, current,
   duplicate-role, and over-capacity branches. Prove deterministic retention,
   visible cutoff/truncation explanation, responsive search, focus, and bounded
   DOM rows.
3. Run `bash scripts/verify-workspace-comparison-intent-restart.sh` and prove
   existing `core.sqlite` target intent survives while catalog/query data does
   not persist.
4. Build and launch the actual debug app through the standard observability
   runner, exercise the packaged WKWebView path, and capture final native
   screenshots/interaction evidence. The development server is iteration proof;
   packaged app is the final host boundary.

Quality and regression gates:

- `mise run lint`
- focused Swift and BridgeWeb lanes named by S1–S3
- `mise run test`
- `git diff --check`

No PR-ready claim is allowed unless the complete `mise run test` gate passes on
the exact final Agent Studio HEAD and `mise run check` passes on the exact
pinned `agentstudio-git` revision.

## S5 — Bounded review and PR readiness

Review budget for the remainder of this goal is hard-capped:

```text
cycle 1  independent implementation review
             │
             ├─ no accepted findings → PR wrap-up
             └─ accepted findings → one focused remediation
                                      │
                                      ▼
cycle 2                         affected re-review only
                                      │
                                      ▼
                            PR wrap-up or exact blocker
```

- Validate every candidate finding against the Requirements, Specification,
  Program Design, current source, and observed proof before accepting it.
- Advisor aesthetic guidance is not an implementation-review cycle.
- Do not start a third review/remediation cycle. If cycle 2 finds a remaining
  material blocker, report that blocker instead of looping.
- After current review coverage and proof, push the scoped Agent Studio branch,
  update/open the non-draft PR, and verify exact head, checks, comments, review
  threads, and mergeability. Terminal is PR-ready and unmerged.

## Obligation-to-proof map

| Obligation | Slice | Proof |
| --- | --- | --- |
| CT-R1 / CT-U1 | S1, S2 | constant-scope resolver tests; initialization trace contains no catalog capture |
| CT-R2 / CT-U2 | S2, S3 | strict command/descriptor/content contracts; production-backed Vite journey |
| CT-R3 / CT-U3 | S1, S2, S3 | real-Git cutoff/exception/order tests; row/byte bounds; 2,000-row browser proof |
| CT-R4 | S3 | Base UI Combobox focus/a11y/keyboard tests, bounded mounted rows, screenshots |
| CT-R5 / CT-U5 | S2, S3 | cancellation/admission/query-identity interleavings; comparison remains unchanged |
| CT-R6 / CT-U4/U6 | S2, S4 | compact metadata corpus, SQLite restart, development and packaged host journeys |

## Risks and stop conditions

- Stop if current source contradicts the Program Design's named owner or call
  path; report the assumed model, observed source, and architectural effect
  before introducing a new seam.
- Stop before any new database table, transport, cache, actor, scheduler,
  watcher, fetch, pagination protocol, or shared UI abstraction.
- Preserve unrelated dirty/untracked work and stage only files changed for this
  correction.
- Do not work in either repository's default-branch worktree and do not merge
  without separate authorization.
