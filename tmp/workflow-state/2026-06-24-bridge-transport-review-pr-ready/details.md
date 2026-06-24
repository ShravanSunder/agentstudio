# Bridge Transport Review PR-Ready Goal Details

Goal id: `2026-06-24-bridge-transport-review-pr-ready`
Status: active
Current workflow: spec/design reconciliation for expanded epic scope
Next workflow: `shravan-dev-workflow:spec-creation-swarm`

## Durable Objective

Finish the full Bridge transport/review epic to PR-ready state. Gate 0 is the
first mandatory prerequisite, not the final PR objective.

The work is complete only when:

- Gate 0 proves the Worktree/File dev-server product surface.
- The full Bridge transport/protocol/scheduler spec is implemented.
- Worktree/File and Review app protocols are implemented against the accepted
  contracts.
- Pierre/Review renderer integration is rewritten onto the new
  transport/materialization/scheduler model.
- The branch is PR-ready but not merged.

## Gates

### Gate 0: Worktree/File Dev-Server Product Proof

Exact URL:

```text
http://127.0.0.1:5173/?fixture=worktree&workers=on&scenario=current-worktree
```

Must prove:

- intended Worktree/File product surface, not Review mock route
- provenance/source assertions
- file click/open
- content render
- search input
- regex toggle
- filter/status controls
- large tree scroll stability
- large file scroll stability
- screenshot artifacts
- JSON proof artifact
- negative assertions against mock/raw/minimal substitutes

Gate 0 source plan:

- [worktree-devserver-product-e2e-precursor-plan.md](/Users/shravansunder/Documents/dev/project-dev/agent-studio.bridge-start/tmp/plan-workflows/2026-06-22-bridge-transport-streaming-implementation-plan/worktree-devserver-product-e2e-precursor-plan.md:1)

### Gate 1: Generic Bridge Transport/Core

Implement all accepted transport/protocol/scheduler items:

- Bridge host/core boundaries
- stream and RPC contracts
- Zod/TypeScript schemas
- resource descriptors
- demand lanes and policies
- backpressure
- materialization
- invalidation
- telemetry
- Victoria proof where required

### Gate 2: App Protocols

Implement Worktree/File and Review application protocols:

- live worktree stream semantics
- change-set semantics
- source/version/provenance contracts
- descriptor/content separation
- large-data-out-of-Zustand invariant
- bounded stream/request behavior

### Gate 3: Pierre/Review Renderer Integration

Complete the Review viewer rewrite/integration:

- Review viewer uses new transport/materialization/scheduler model.
- Static diffs are DiffsHub-like in smoothness and scroll stability.
- Live updates and change-set comparisons are first-class.
- Renderer does not regress markdown click/reveal, filters, or search behavior.

### Gate 4: PR-Ready Non-Merge Terminal

PR-ready means:

- implementation complete
- required proof pyramid passing or explicitly not applicable
- dev-server/browser E2E and visual proof captured
- performance/observability proof captured where required
- implementation review findings addressed or explicitly rejected
- lint/typecheck/tests green for agreed scope
- PR opened or updated
- PR checks, review comments, and mergeability freshly reported

Merge is out of scope unless explicitly authorized.

## Reviewer Critical Context

Every reviewer packet for this goal must include this section or an equivalent
summary. Reviewers must not receive only the latest happy-path artifact.

### Why Review Must Be Adversarial

Earlier artifacts incorrectly implied readiness because proof was too narrow.
The route could pass a verifier while the user-visible dev-server page still
rendered the wrong or insufficient surface. The lesson is that green lower-level
proof is not enough when the user asked for product behavior.

Reviewers must attack:

- whether the artifact proves the real product surface
- whether the proof can pass against a mock, raw dump, or minimal route
- whether the contract preserves full PR-ready scope rather than shrinking back
  to Gate 0 only
- whether the plan has real vertical slices with proof gates
- whether proof artifacts include screenshots and browser-visible state
- whether reviewers have enough prior failure context to critique honestly

### Prior Failure Modes To Include In Review Packets

1. The worktree dev URL previously showed raw/gibberish path text in the browser.
2. A narrow verifier could pass while the product surface remained insufficient.
3. The current route can load Worktree/File data and render tree/content, yet it
   lacks required search, regex, and filter/status controls.
4. Prior spec/review docs used readiness language that was too strong.
5. Subagent review attempts failed due local process/file-descriptor issues and
   must not be counted as completed review.
6. Signed commit failed once because the 1Password signing socket was
   unavailable; the checkpoint was committed unsigned under repo preference.
7. Playwright bundled Chromium was missing; installed Chrome was used for
   browser evidence.

### Current Evidence Split

Old narrow green proof:

- `pnpm --dir BridgeWeb run test:dev-server:worktree`
- Passed on 2026-06-24.
- Latest artifact observed:
  `tmp/bridge-viewer-worktree-dev-server/2026-06-24T12-51-13-807Z`
- This proves route/data/scroll/text behavior only.
- It does not satisfy Gate 0.

Current product red proof:

- `tmp/bridge-worktree-devserver-proof-recovery/current-worktree-route-after-3s.png`
- `tmp/bridge-worktree-devserver-proof-recovery/current-worktree-route-diagnostics.json`
- Backend returned 432 frames and 431 rows.
- Browser protocol attribute was `worktree-file`.
- Tree/content rendered after wait.
- Required product controls were absent:
  - search input: 0
  - regex toggle: 0
  - filter/status controls: 0

## Required Reviewer Packet Contents

Each spec, plan, implementation, or PR reviewer must receive:

- goal id and current gate
- exact URL for Gate 0 when relevant
- source specs and current plan paths
- the old green proof versus current red proof distinction
- prior failure modes above
- explicit question: "Can this proof pass while the user-visible product is
  still wrong?"
- expected output format: P0-P3 findings with file/line references, or an
  explicit "no findings" plus residual risk

## Source Artifacts

- [spec.md](/Users/shravansunder/Documents/dev/project-dev/agent-studio.bridge-start/tmp/spec-workflows/2026-06-22-bridge-transport-streaming-spec/spec.md:1)
- [review-protocol.md](/Users/shravansunder/Documents/dev/project-dev/agent-studio.bridge-start/tmp/spec-workflows/2026-06-22-bridge-transport-streaming-spec/review-protocol.md:1)
- [worktree-file-surface-protocol.md](/Users/shravansunder/Documents/dev/project-dev/agent-studio.bridge-start/tmp/spec-workflows/2026-06-22-bridge-transport-streaming-spec/worktree-file-surface-protocol.md:1)
- [reconciliation-plan-2026-06-24.md](/Users/shravansunder/Documents/dev/project-dev/agent-studio.bridge-start/tmp/plan-workflows/2026-06-22-bridge-transport-streaming-implementation-plan/reconciliation-plan-2026-06-24.md:1)
- [reconciliation-review-2026-06-24.md](/Users/shravansunder/Documents/dev/project-dev/agent-studio.bridge-start/tmp/spec-workflows/2026-06-22-bridge-transport-streaming-spec/reconciliation-review-2026-06-24.md:1)

## Transition Rules

- `events.jsonl` owns official workflow transitions after the goal text.
- Phase skills may recommend transitions but must not silently advance the goal.
- Accepted spec findings route back to spec creation.
- Accepted plan findings route back to plan creation.
- Accepted implementation findings route back to implementation execution.
- Gate 0 must close before downstream Gate 1-4 implementation claims.
