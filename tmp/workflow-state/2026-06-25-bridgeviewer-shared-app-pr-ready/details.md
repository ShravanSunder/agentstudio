# BridgeViewer Shared App PR-Ready Goal Details

Goal id: `2026-06-25-bridgeviewer-shared-app-pr-ready`
Status: active
Current workflow: `shravan-dev-workflow:orchestrator-goal`
Next workflow: `shravan-dev-workflow:spec-review-swarm`

## Durable Objective

Finish the BridgeViewer shared-app work to PR-ready state without merging. The
product outcome is a dependable Agent Studio Bridge viewer that works both in the
Vite dev-server fast loop and in the Swift-hosted Agent Studio Bridge/WKWebView
path against a local worktree.

The goal is complete only when:

- BridgeViewer is one app with Review and Files contexts, not separate app roots.
- Dev-server query params are only a fast-loop adapter into the same browser
  navigation/store model.
- Production Agent Studio uses internal BridgeViewer intents/commands through the
  Swift Bridge host, not user-visible query params.
- Files context can browse a local worktree, select files, render file content
  through Pierre/Shiki with worker-backed highlighting, and show stale/update
  state with explicit refresh.
- Review context can show current-worktree review diffs and can open a selected
  review item as a file target without switching to a standalone FileViewer app.
- The shared shell uses the agreed UX: primary Pierre CodeView/File canvas on the
  left, Pierre FileTree/right rail on the right, and shared UI primitive styling
  for buttons, inputs, toggles, icons, filters, and navigation chrome.
- Large file bodies, raw diff bodies, streams, workers, Pierre instances, and
  resource executors stay out of Zustand.
- Search, regex, filter/status controls, selection, context toggle, per-context
  memory, scroll anchoring, stale refresh, and worker readiness are covered by
  proof.
- Dev-server proof and Agent Studio Bridge/WKWebView proof are both captured from
  the current worktree with fresh artifacts.
- Required implementation review findings are addressed or explicitly rejected.
- PR is opened or updated and proven ready, with checks/review-thread/mergeability
  freshly reported. Merge is not performed unless separately authorized.

## Why This Is A New Goal

The previous lane got stuck optimizing a FileViewer-only correction. That was the
wrong first boundary. Gate 0.a now starts with the shared BridgeViewer
navigation/store contract:

```text
shared navigation/store proof
  -> current-worktree Files context proof
  -> current-worktree Review context proof
  -> Review file-target proof
  -> shared chrome/layout/Pierre/Shiki/worker proof
  -> Agent Studio Bridge/WKWebView proof
  -> full implementation/review/PR-ready proof
```

Do not resume from old workflow state that says Gate 0.a proof already passed.
That proof is historical and narrower than this goal.

## Required Reading

- [spec.md](/Users/shravansunder/Documents/dev/project-dev/agent-studio.bridge-start/docs/specs/bridge-viewer-transport/spec.md:1)
- [review-protocol.md](/Users/shravansunder/Documents/dev/project-dev/agent-studio.bridge-start/docs/specs/bridge-viewer-transport/review-protocol.md:1)
- [worktree-file-surface-protocol.md](/Users/shravansunder/Documents/dev/project-dev/agent-studio.bridge-start/docs/specs/bridge-viewer-transport/worktree-file-surface-protocol.md:1)
- [worktree-devserver-product-e2e-precursor-plan.md](/Users/shravansunder/Documents/dev/project-dev/agent-studio.bridge-start/tmp/plan-workflows/2026-06-22-bridge-transport-streaming-implementation-plan/worktree-devserver-product-e2e-precursor-plan.md:1)
- [orchestrator-goal-2026-06-25-bridgeviewer-shared-app-pr-ready.md](/Users/shravansunder/Documents/dev/project-dev/agent-studio.bridge-start/tmp/plan-workflows/2026-06-22-bridge-transport-streaming-implementation-plan/orchestrator-goal-2026-06-25-bridgeviewer-shared-app-pr-ready.md:1)
- Historical only: [implementation-plan.md](/Users/shravansunder/Documents/dev/project-dev/agent-studio.bridge-start/tmp/plan-workflows/2026-06-22-bridge-transport-streaming-implementation-plan/implementation-plan.md:1)
- Historical stuck-lane state only: [old details.md](/Users/shravansunder/Documents/dev/project-dev/agent-studio.bridge-start/tmp/workflow-state/2026-06-24-bridge-transport-review-pr-ready/details.md:1)

## Workflow Order

1. `shravan-dev-workflow:spec-review-swarm`
   - Review the changed shared BridgeViewer navigation/store spec and protocol
     edits.
   - Attack contradictions around Review file target, Files/Review context
     memory, dev query params, Swift internal intents, and large-data state
     boundaries.

2. `shravan-dev-workflow:plan-creation-swarm`
   - Rewrite the active implementation plan around the corrected sequence.
   - Produce vertical slices with red/green proof, integration proof, browser
     proof, Agent Studio proof, and review checkpoints.

3. `shravan-dev-workflow:plan-review-swarm`
   - Review the plan against the spec and prior failure mode.
   - The reviewer packet must explicitly say the previous attempt failed by
     treating a FileViewer visual fix as enough.

4. `shravan-dev-workflow:implementation-execute-plan`
   - Implement one proven checkpoint at a time.
   - Use TDD where behavior changes.
   - Commit at verified checkpoints when scoped files changed.

5. `shravan-dev-workflow:implementation-review-swarm`
   - Review implementation against the spec, plan, and proof artifacts.
   - Accepted findings route back to implementation before PR-ready.

6. `shravan-dev-workflow:implementation-pr-wrapup`
   - Open or update PR, report checks/review threads/mergeability, and stop
     before merge.

## Gate 0.a Required First Implementation Sequence

The first implementation sequence after plan review is:

```text
0.a.1a red shared navigation/store proof
  proves viewer=file and viewer=review are store-backed contexts

0.a.2 Files context current-worktree proof
  proves worktree file browsing through shared BridgeViewer shell

0.a.2a Review context current-worktree proof
  proves current worktree as review diff and Review file target

0.a.3 shared chrome and context-memory proof
  proves shadcn/shared primitives, toggle, controls, and state restoration

0.a.4 live dev-server e2e proof
  proves exact URLs, visible layout, Pierre/Shiki/worker ownership, and negative
  assertions against stale/mock/raw/second-app substitutes

0.a.5 Agent Studio Bridge/WKWebView proof
  proves Files context, Review diff context, Review file-target context, and
  Files-to-Review handoff in the Swift-hosted local worktree path with
  marker-correlated logs/metrics/traces where available
```

## Implementation Checkpoints

2026-06-25 checkpoint:

- Commit `47933c48` proves the current-worktree Review file-target URL route:
  `viewer=review&presentation=file&path=.gitignore&version=current` renders
  `.gitignore` as a Pierre `file` item inside Review context, not a standalone
  FileViewer app.
- Commit `6ce7ef9d` proves the Files-to-Review in-app handoff. FileViewer emits
  a typed selected-file review intent; BridgeApp switches the same app root from
  Files context to Review context; the URL remains the dev Files URL; Review
  materializes `.gitignore` as a Pierre `file` item.
- Fresh dev-server proof:
  `pnpm --dir BridgeWeb run test:dev-server:worktree`
  exited 0 and wrote
  `tmp/bridge-viewer-worktree-dev-server/2026-06-25T13-32-08-430Z/worktree-dev-server-proof.json`.
- Artifact highlights:
  `fileToReviewHandoffProof.appRootCount = 1`,
  `sharedShellMode = review`,
  `selectedDisplayPath = .gitignore`,
  `selectedMaterializedItemType = file`,
  `selectedMaterializedFileLineCount = 92`,
  `fileViewerShellCountAfterSwitch = 0`,
  `reviewPackageRouteHitCount = 1`,
  `reviewContentRouteHitCount = 24`.

Gate 0.a is not complete yet. Remaining proof must still cover context toggle
and per-context memory explicitly, then Agent Studio Bridge/WKWebView proof
against the local worktree.

## Required Dev URLs

The dev server must support and prove:

```text
http://127.0.0.1:5173/?fixture=worktree&viewer=file&workers=on&scenario=current-worktree
http://127.0.0.1:5173/?fixture=worktree&viewer=review&workers=on&scenario=current-worktree
http://127.0.0.1:5173/?fixture=worktree&viewer=review&presentation=file&path=<path>&version=<base|head|current>&workers=on&scenario=current-worktree
```

The legacy URL may default to Files context, but it is not enough by itself:

```text
http://127.0.0.1:5173/?fixture=worktree&workers=on&scenario=current-worktree
```

## Requirements/proof Matrix

Requirement / claim:
One BridgeViewer app owns Review and Files contexts.
Proof source:
unit/component ownership tests plus browser DOM/provenance proof.
Proof owner:
implementation-execute-plan with implementation-review-swarm verification.
Stale-proof guard:
must run against a freshly restarted Vite dev server and current worktree bundle.

Requirement / claim:
Zustand stores navigation/view refs and facts only.
Proof source:
store model/unit tests and store snapshot inspection.
Proof owner:
implementation-execute-plan.
Stale-proof guard:
must include Review and Files context states after navigation/toggle operations.

Requirement / claim:
Dev query params mutate the same store as production intents.
Proof source:
unit tests for dev param parsing/adaptation and production intent reducer tests.
Proof owner:
plan-creation-swarm defines exact implementation rows; execution proves them.
Stale-proof guard:
must reject separate app roots and route-local state stores.

Requirement / claim:
Files context renders local worktree files through Pierre/Shiki workers.
Proof source:
dev-server Playwright proof, screenshot, JSON artifact, worker readiness marker.
Proof owner:
implementation-execute-plan.
Stale-proof guard:
must assert current-worktree source identity, `workers=on`, and no raw `<pre>`.

Requirement / claim:
Review context supports current worktree as review diff and selected item as file
target.
Proof source:
dev-server Playwright proof for `viewer=review` and `presentation=file`.
Proof owner:
implementation-execute-plan.
Stale-proof guard:
must prove Review context remains active during file target rendering.

Requirement / claim:
Files context can transition to Review through the typed
`OpenReviewComparisonIntent` handoff.
Proof source:
unit/integration proof for accepted/rejected/deferred handoff outcomes plus
browser proof that a Files-context selection activates Review context in the same
BridgeViewer app and preserves Files-context memory for toggle-back.
Proof owner:
implementation-execute-plan with implementation-review-swarm verification.
Stale-proof guard:
must reject ad hoc route mutation, new pane id dependency, Worktree-built diff
authority, and direct Review-only fixture shortcuts.

Requirement / claim:
Shared UI chrome uses the existing shared primitive/design system layer.
Proof source:
component tests, architecture/static import checks where feasible, and visual
browser proof.
Proof owner:
implementation-execute-plan and implementation-review-swarm.
Stale-proof guard:
must cover buttons, inputs, toggles/icons, filters, and context toggle.

Requirement / claim:
Scroll extent is stable enough for large worktrees and large files.
Proof source:
browser scroll canary plus Victoria/OTel metrics where available.
Proof owner:
implementation-execute-plan.
Stale-proof guard:
must record source identity, scrollTop/totalSize before/after, anchor id/offset,
and reconciliation reason.

Requirement / claim:
Agent Studio Swift-hosted Bridge path works against a local worktree.
Proof source:
Agent Studio debug observability run, WKWebView/Bridge proof, screenshots or
browser/native visual evidence, JSON proof where applicable, and Victoria
marker-correlated evidence.
Proof owner:
implementation-execute-plan.
Stale-proof guard:
must use current build/worktree identity and must cover native Files context,
Review diff context, Review file-target context, and Files-to-Review handoff.
It must inherit the dev-server product-surface assertions: shared shell/store,
visible layout, Pierre/Shiki/worker ownership, search/regex/filter behavior,
stale/refresh, scroll canaries, and negative guards against mock/minimal/raw or
wrong-surface proof. Vite-only proof, one-scenario-only proof, screenshot-only
proof, and uncorrelated logs are insufficient.

Requirement / claim:
The branch reaches PR-ready state but is not merged.
Proof source:
lint/typecheck/tests, dev-server proof, Agent Studio proof, implementation
review disposition, PR checks/review-thread/mergeability report.
Proof owner:
implementation-pr-wrapup.
Stale-proof guard:
fresh PR state after final push.

## Stop, Blocked, And Checkpoint Rules

Stop only when the terminal condition is met or a real blocker requires user
input. Do not stop at phase boundaries, subagent completion, plan creation, or
dev-server-only proof.

Blocked condition:

- the same material blocker recurs under the host blocked-state rules, or
- a required decision cannot be inferred from the spec/code and a reasonable
  assumption would be risky, or
- required proof cannot run because of an external environment failure outside
  the agreed write scope.

Checkpoint rhythm:

- checkpoint after accepted spec revision
- checkpoint after accepted plan revision
- checkpoint after each proven implementation slice
- checkpoint after implementation-review fixes
- checkpoint after PR-ready wrapup
- commit scoped files at verified checkpoints when repo policy permits

## 2026-06-25 Checkpoint: Shared Context Toggle And Memory

Status:
dev-server and focused BridgeWeb checks passed for the shared app context
toggle/memory slice. Gate 0.a remains open for native Agent Studio
Bridge/WKWebView proof and implementation review disposition.

Implemented/proven:

- `BridgeApp` owns one `BridgeViewerAppShell`.
- FileViewer and ReviewViewer are mode bodies under the shared shell, not
  separate apps.
- The context switcher uses the shared shadcn `Button` primitive and records
  selected Files/Review state.
- The inactive FileViewer remains mounted but hidden after Files-to-Review
  handoff so per-context memory can be restored.
- Dev-server proof toggles Files -> Review -> Files -> Review and verifies
  `.gitignore` remains selected in both contexts.
- Negative guard still proves zero standalone `WorktreeFileApp` roots.

Proof:

- `pnpm --dir BridgeWeb exec vitest run src/app/bridge-app-protocol-router.unit.test.tsx src/app/bridge-app.integration.test.tsx --reporter verbose`
  - Exit: 0
  - Result: 2 files passed, 53 tests passed
- `pnpm --dir BridgeWeb run check`
  - Exit: 0
  - Result: passed with existing `no-await-in-loop` warnings in
    `scripts/verify-bridge-viewer-worktree-dev-server.ts`
- `pnpm --dir BridgeWeb run test:dev-server:worktree`
  - Exit: 0
  - Artifact:
    `tmp/bridge-viewer-worktree-dev-server/2026-06-25T13-48-26-677Z/worktree-dev-server-proof.json`
  - Key artifact facts:
    `sharedShellProof.appRootCount = 1`,
    `sharedShellProof.shellParentIsModeHost = true`,
    `sharedShellProof.fileContextButtonSelected = true`,
    `sharedShellProof.workerPoolState = ready`,
    `fileToReviewHandoffProof.fileViewerShellCountAfterSwitch = 1`,
    `fileToReviewHandoffProof.fileViewerShellHiddenAfterSwitch = true`,
    `fileToReviewHandoffProof.fileViewerSelectedPathAfterReturnToFile = .gitignore`,
    `fileToReviewHandoffProof.reviewSelectedDisplayPathAfterReturnToReview = .gitignore`,
    `fileToReviewHandoffProof.standaloneWorktreeFileAppCount = 0`.

Phase skills must return:

```text
phase_result: complete | blocked | needs_revision | not_applicable
evidence: <commands with exit codes, artifact paths, findings, or explicit
not-run/blocked reasons; transcript notes are supplemental only>
recommended_next_workflow: <shravan-dev-workflow skill or terminal>
recommended_transition_reason: <one sentence>
```
