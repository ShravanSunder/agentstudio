# Spec Review Packet: Bridge Transport Review PR-Ready Epic

Goal id: `2026-06-24-bridge-transport-review-pr-ready`
Review workflow: `shravan-dev-workflow:spec-review-swarm`
Status: accepted on 2026-06-24 after post-fix review; retained as reviewer
context for later phases

## Review Objective

Review the current spec/design reconciliation for the full Bridge
transport/review epic. Do not review this as a Gate-0-only recovery task.

The intended terminal state is PR-ready non-merge:

1. Gate 0 Worktree/File product proof.
2. Gate 1 generic Bridge transport/protocol/scheduler implementation.
3. Gate 2 Worktree/File and Review app protocol implementation.
4. Gate 3 Pierre/Review renderer rewrite/integration.
5. Gate 4 PR-ready wrapup with proof, implementation review, checks, PR state,
   review-thread state, and mergeability.

## Required Source Artifacts

Read the whole files before reviewing:

- [spec.md](/Users/shravansunder/Documents/dev/project-dev/agent-studio.bridge-start/tmp/spec-workflows/2026-06-22-bridge-transport-streaming-spec/spec.md:1)
- [review-protocol.md](/Users/shravansunder/Documents/dev/project-dev/agent-studio.bridge-start/tmp/spec-workflows/2026-06-22-bridge-transport-streaming-spec/review-protocol.md:1)
- [worktree-file-surface-protocol.md](/Users/shravansunder/Documents/dev/project-dev/agent-studio.bridge-start/tmp/spec-workflows/2026-06-22-bridge-transport-streaming-spec/worktree-file-surface-protocol.md:1)
- [reconciliation-plan-2026-06-24.md](/Users/shravansunder/Documents/dev/project-dev/agent-studio.bridge-start/tmp/plan-workflows/2026-06-22-bridge-transport-streaming-implementation-plan/reconciliation-plan-2026-06-24.md:1)
- [reconciliation-review-2026-06-24.md](/Users/shravansunder/Documents/dev/project-dev/agent-studio.bridge-start/tmp/spec-workflows/2026-06-22-bridge-transport-streaming-spec/reconciliation-review-2026-06-24.md:1)
- [worktree-devserver-product-e2e-precursor-plan.md](/Users/shravansunder/Documents/dev/project-dev/agent-studio.bridge-start/tmp/plan-workflows/2026-06-22-bridge-transport-streaming-implementation-plan/worktree-devserver-product-e2e-precursor-plan.md:1)
- [details.md](/Users/shravansunder/Documents/dev/project-dev/agent-studio.bridge-start/tmp/workflow-state/2026-06-24-bridge-transport-review-pr-ready/details.md:1)
- [events.jsonl](/Users/shravansunder/Documents/dev/project-dev/agent-studio.bridge-start/tmp/workflow-state/2026-06-24-bridge-transport-review-pr-ready/events.jsonl:1)

## Mandatory Reviewer Context

This context is part of the review input. Do not omit it.

The last full attempt was misleading because proof was too narrow. The
Worktree/File route could pass a verifier while the user-visible product surface
was still wrong or insufficient.

Known prior failure modes:

1. The worktree dev URL previously showed raw/gibberish path text in the browser.
2. A narrow verifier could pass while the product surface remained insufficient.
3. The current route can load Worktree/File data and render tree/content, yet it
   lacks required search, regex, and filter/status controls.
4. Earlier spec/review docs used readiness language that was too strong.
5. Subagent review attempts failed due local process/file-descriptor issues and
   must not be counted as completed review.
6. Vite/dev-server proof is required first, but final PR-ready proof must also
   include Agent Studio Bridge/WKWebView runtime evidence.

Current old-green proof:

- `pnpm --dir BridgeWeb run test:dev-server:worktree` passed on 2026-06-24.
- Latest observed artifact:
  `tmp/bridge-viewer-worktree-dev-server/2026-06-24T12-51-13-807Z`
- This proves route/data/scroll/text behavior only. It does not satisfy Gate 0.

Current product-red proof:

- `tmp/bridge-worktree-devserver-proof-recovery/current-worktree-route-after-3s.png`
- `tmp/bridge-worktree-devserver-proof-recovery/current-worktree-route-diagnostics.json`
- Backend returned 432 frames and 431 rows.
- Browser protocol attribute was `worktree-file`.
- Tree/content rendered after wait.
- Required product controls were absent:
  - search input: 0
  - regex toggle: 0
  - filter/status controls: 0

Every reviewer must explicitly ask:

```text
Can this proof pass while the user-visible product is still wrong?
```

## Review Questions

1. Does the parent spec now preserve the full Gate 0-4 PR-ready scope?
2. Is Gate 0 specified strongly enough to prevent another narrow green proof?
3. Does the spec distinguish Vite/dev-server proof from native Agent Studio
   Bridge/WKWebView proof?
4. Are Worktree/File and Review protocol ownership boundaries still clear?
5. Are generic Bridge transport/scheduler/backpressure responsibilities clear
   enough for plan creation?
6. Is the Pierre/Review renderer cutover requirement strong enough to prevent
   leaving the old path as an accidental bypass?
7. Does any status/readiness language still imply review or implementation is
   done when it is not?
8. Can a plan-creation agent derive real vertical slices and proof gates without
   inventing missing product behavior?

## Expected Reviewer Output

Return P0-P3 findings only when actionable. Each finding must include:

- severity
- file and line reference
- why it matters
- failure path
- smallest refinement target
- validation note

If there are no findings, say that explicitly and list residual risks. Do not
claim spec review is complete unless every required file was read.
