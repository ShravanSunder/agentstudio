# BridgeViewer Shared App PR-Ready Goal Details

Goal id: `2026-06-25-bridgeviewer-shared-app-pr-ready`
Status: active
Current workflow: `shravan-dev-workflow:implementation-execute-plan`
Next workflow: `shravan-dev-workflow:implementation-review-swarm`

Workflow precedence note: the latest valid `shravan-dev-workflow:orchestrator-goal`
event in `events.jsonl` owns current/next workflow. This header reflects the
2026-06-25T20:00:00-04:00 needs-revision transition back to implementation after
review accepted proof blockers and the FileViewer preload/performance contract
was added to spec and plan.

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
- Every visible UX checkpoint is covered by real browser/native proof,
  screenshot or video artifacts, and a second-agent visual/code onlook against
  current FileViewer, ReviewViewer, and DiffsHub/Pierre expectations.
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
  proves shadcn/shared primitives, DiffsHub-like top chrome, toggle, controls,
  state restoration, and second-agent screenshot/source onlook

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
component tests, architecture/static import checks where feasible, Vitest
Browser or Playwright proof, screenshot/video artifacts, and second-agent
visual/code onlook against FileViewer, ReviewViewer, and DiffsHub/Pierre
source/screenshots.
Proof owner:
implementation-execute-plan and implementation-review-swarm.
Stale-proof guard:
must cover buttons, inputs, toggles/icons, filters, context toggle, search
placement, active source identity, and the top-chrome/right-rail design target.
jsdom-only proof is not accepted.

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
Bridge/WKWebView proof and implementation review disposition. After the
2026-06-25 UX review, this checkpoint is historical proof only and must be
followed by a browser-visible UX correction checkpoint before Gate 0.a can
advance.

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

Review findings to fix before the next checkpoint:

- P1: Hidden ReviewViewer stays live while Files is active. Gate user-visible
  side effects such as `review.markFileViewed` on active Review mode and decide
  whether review-only listeners should suspend while inactive.
- P2: Replace/demote the jsdom shared-context memory proof. The UX contract must
  be proved with Vitest Browser or Playwright/dev-server; jsdom can remain only
  as an explicitly lower-level state guard if it still earns its keep.
- P2: Browser proof must re-sample Review item identity and materialization
  after toggling Files -> Review -> Files -> Review, not only display path.
- UX: FileViewer chrome/search/filter placement does not yet match the intended
  ReviewViewer/DiffsHub-like top-bar contract. Use subagents to compare
  DiffsHub/Pierre source and screenshots against current FileViewer/ReviewViewer
  before changing the visible chrome. The next implementation checkpoint must
  draw or attach the intended shared shell design before coding the fix.
- Performance: file-click loading in the large current-worktree fixture feels
  slow. Add measured browser/Victoria evidence or explicitly carry this as the
  next performance/backpressure ticket before claiming readiness.

Checkpoint proof rule:

- Every implementation checkpoint that changes visible BridgeViewer behavior
  must prove the UX works in a real browser or native WKWebView.
- Required proof includes screenshot or video artifacts, real interaction
  assertions, source/protocol provenance, and a second-agent visual/code critique.
- The second-agent onlook must inspect both screenshots and source paths, and
  its accepted findings must be fixed or explicitly carried in the active plan
  before a checkpoint commit.
- jsdom, DOM-only attributes, route state, JSON-only artifacts, or screenshots
  without interaction/provenance cannot close a UX checkpoint unless the user
  explicitly requested that narrow proof layer.

## 2026-06-25 Checkpoint: Shared FileViewer Chrome And Browser UX Proof

Status:
the Gate 0.a shared FileViewer chrome correction is implemented and committed in
`44423afa` (`Unify FileViewer rail chrome`). This closes the specific
needs-revision item that FileViewer was still presenting a second-app-looking
rail with route-local search/filter controls. It does not close Gate 0.a as a
whole.

Implemented/proven:

- FileViewer keeps using the shared `BridgeViewerAppShell` and `viewer=file`
  mode.
- FileViewer uses the shared Review rail primitives for visible chrome:
  `BridgeReviewSearchControl`, `BridgeReviewFilterMenu`, shadcn dropdown
  trigger, and shared review-style action buttons.
- The visible search input starts closed, matching the shared compact rail
  chrome instead of the old full-width FileViewer-only search field.
- The rail still proves Pierre ownership: Pierre FileTree on the right, Pierre
  `CodeView.file`/Shiki rendering on the left, and the worker pool ready when
  `workers=on`.
- The dev-server verifier covers Files, Review, and Review file-target URLs and
  rejects standalone `WorktreeFileApp`/second-app substitutes.

Proof:

- `pnpm --dir BridgeWeb exec vitest --config vitest.browser.config.ts run --project integration-browser src/file-viewer/bridge-file-viewer-app.browser.test.tsx --reporter verbose`
  - Exit: 0
  - Result: 1 browser test passed
- `pnpm --dir BridgeWeb exec vitest run src/file-viewer/bridge-file-viewer-app.unit.test.tsx src/worktree-file-surface/worktree-file-app.integration.test.tsx --reporter verbose`
  - Exit: 0
  - Result: 2 files passed, 17 tests passed
- `pnpm --dir BridgeWeb run test:dev-server:worktree`
  - Exit: 0
  - Artifact:
    `tmp/bridge-viewer-worktree-dev-server/2026-06-25T23-35-53-157Z/worktree-dev-server-proof.json`
  - Key artifact facts:
    `sharedShellProof.sharedShellOwner = BridgeViewerAppShell`,
    `sharedShellProof.sharedShellMode = file`,
    `shellOwner = BridgeViewerApp.FileViewer`,
    `codeOwner = CodeView.file`,
    `treeOwner = FileTree`,
    `sidebarIsRight = true`,
    `shikiRendering = pierre`,
    `workerPoolState = ready`,
    `substituteGuardProof.standaloneWorktreeFileAppCount = 0`,
    `visibleAppProof.searchInputCount = 0`,
    `visibleAppProof.searchControlCount = 1`,
    `visibleAppProof.filterMenuCount = 1`,
    `visibleAppProof.sharedRailToolbarCount = 1`,
    `visibleAppProof.sharedRailToolbarUsesSharedAttr = true`.
- `pnpm --dir BridgeWeb run check`
  - Exit: 0
  - Result: type-aware oxlint, architecture check, oxfmt, and `tsc --noEmit`
    passed. Existing non-fatal `no-await-in-loop` warnings remain in the
    dev-server verifier script.
- `git diff --check`
  - Exit: 0
- Browser/onlook artifacts:
  `/tmp/bridgeviewer-verification/final-1.png`,
  `/tmp/bridgeviewer-verification/final-2.png`,
  `/tmp/bridgeviewer-verification/final-3.png`.
  The onlook passed the shared-shell, left-canvas/right-rail,
  search-closed, and no-standalone-app checks against the current dev server.
- Architecture onlook:
  passed the current-code check that FileViewer imports/reuses the shared review
  rail primitives and is still composed under the shared Bridge app path.

Disposition of prior findings:

- Addressed: jsdom is no longer the UX proof for this visible checkpoint. The
  accepted proof is Vitest Browser plus Playwright/dev-server/onlook evidence.
- Addressed: FileViewer rail chrome no longer uses its old full-width visible
  search and route-local filter buttons for the shared shell path.
- Still open: hidden inactive ReviewViewer side effects need review/fix before
  the active/inactive context contract can be called production-ready.
- Still open: review-route aborted `__bridge-worktree/review-content/...`
  requests were seen by the browser onlook while selected content still rendered
  ready. Keep this visible for review-route fetch/cancellation analysis.
- Still open: file-click responsiveness and scroll extent stability remain
  performance/backpressure proof items, especially for large current-worktree
  fixtures.
- Still open: Agent Studio Swift-hosted Bridge/WKWebView proof has not yet been
  captured for the current checkpoint.
- Accepted implementation-review blocker: the latest dev-server artifact records
  the legacy compatibility Files URL as the main Files proof. The next verifier
  slice must prove and record the explicit
  `?fixture=worktree&viewer=file&workers=on&scenario=current-worktree` route.
- Accepted implementation-review finding: the current worktree verifier can fall
  back to synthetic DOM `dispatchEvent` clicks. Product E2E proof must remove
  that fallback and use actionability-checked browser interactions with bounded
  waits.
- Accepted performance design update: FileViewer click latency must be treated
  as scheduler/preload work. Current code has generic scheduler lanes and
  Worktree/File demand stimuli, but the FileViewer runtime/UI does not yet emit
  viewport, adjacent, hover/focus, or recently-updated-file preload stimuli.
  The next implementation slice should add an app-specific
  `dispatchDemandStimuli(...)` seam, descriptor-backed body-registry preloads,
  scoped cancellation groups, preload disposition telemetry, and click-to-ready
  latency proof.

Recommended next workflow:
`shravan-dev-workflow:implementation-review-swarm` for source-backed review of
`44423afa`, the visible UX proof, and the remaining Gate 0.a blockers before the
next implementation slice.

Phase skills must return:

```text
phase_result: complete | blocked | needs_revision | not_applicable
evidence: <commands with exit codes, artifact paths, findings, or explicit
not-run/blocked reasons; transcript notes are supplemental only>
recommended_next_workflow: <shravan-dev-workflow skill or terminal>
recommended_transition_reason: <one sentence>
```
