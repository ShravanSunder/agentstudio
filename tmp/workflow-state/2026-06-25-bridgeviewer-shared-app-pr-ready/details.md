# BridgeViewer Shared App PR-Ready Goal Details

Goal id: `2026-06-25-bridgeviewer-shared-app-pr-ready`
Status: active
Current workflow: `shravan-dev-workflow:implementation-execute-plan`
Next workflow: `shravan-dev-workflow:implementation-review-swarm`

Workflow precedence note: the latest valid `shravan-dev-workflow:orchestrator-goal`
event in `events.jsonl` owns current/next workflow. This header reflects the
2026-06-26T02:17:07Z checkpoint transition from implementation execution to
implementation review after the shared content-header/right-rail correction was
implemented and proven.

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

0.a.5 file-load responsiveness/preload proof
  proves FileViewer selected-file opens reach visible Pierre CodeView/File
  content from real browser clicks with recorded disposition, queue state, and
  click-to-ready timing; a screenshot stuck on `Loading file` keeps this open
  current provider-cache checkpoint reduces the dev-server file-content read by
  serving the accepted descriptor cursor directly; full preload/scheduler
  disposition telemetry remains open
  proof:
    - provider integration:
      `pnpm --dir BridgeWeb exec vitest run scripts/dev-server/bridge-worktree-dev-provider.integration.test.ts`
    - file target query browser component proof:
      `pnpm --dir BridgeWeb exec vitest --config vitest.browser.config.ts run --project integration-browser src/file-viewer/bridge-file-viewer-app.browser.test.tsx`
    - dev-server product gate:
      `pnpm --dir BridgeWeb run test:dev-server:worktree`
    - browser screenshot:
      `tmp/bridge-viewer-worktree-provider-cache-proof/2026-06-26T-provider-cache/files-ready.png`
    - browser proof JSON:
      `tmp/bridge-viewer-worktree-provider-cache-proof/2026-06-26T-provider-cache/proof.json`
    - file target query screenshot:
      `tmp/bridge-viewer-worktree-file-target-proof/2026-06-26T-file-query-target-rerun/file-target-query.png`
    - file target query proof JSON:
      `tmp/bridge-viewer-worktree-file-target-proof/2026-06-26T-file-query-target-rerun/proof.json`
    - latest dev-server proof JSON:
      `tmp/bridge-viewer-worktree-dev-server/2026-06-26T04-24-15-308Z/worktree-dev-server-proof.json`

0.a.6 Agent Studio Bridge/WKWebView proof
  proves Files context, Review diff context, Review file-target context, and
  Files-to-Review handoff in the Swift-hosted local worktree path with
  marker-correlated logs/metrics/traces where available
```

## Implementation Checkpoints

2026-06-26 design/spec checkpoint:

- The shared chrome contract now explicitly requires the content header to live
  only over the left content region. It must not span over the right rail, create
  a full-window top strip, push the right rail toolbar down, or leave a
  centered/floating `Files | Review` switcher.
- FileViewer and ReviewViewer controls for the same interaction semantics must
  use the shared BridgeViewer primitive layer over shadcn/base UI. A
  FileViewer-only raw toolbar/search visual language is a blocker even if it is
  built from shadcn/base primitives underneath.
- Fresh Playwright screenshots were captured from the running Vite dev server:
  - [Files screenshot](/Users/shravansunder/Documents/dev/project-dev/agent-studio.bridge-start/tmp/bridge-viewer-design-proof/2026-06-26T03-43-59-852Z-shared-chrome-c-final/files.png:1)
  - [Review diff screenshot](/Users/shravansunder/Documents/dev/project-dev/agent-studio.bridge-start/tmp/bridge-viewer-design-proof/2026-06-26T03-43-59-852Z-shared-chrome-c-final/review-diff.png:1)
  - [Review file-target screenshot](/Users/shravansunder/Documents/dev/project-dev/agent-studio.bridge-start/tmp/bridge-viewer-design-proof/2026-06-26T03-43-59-852Z-shared-chrome-c-final/review-file-target.png:1)
  - [Design proof JSON](/Users/shravansunder/Documents/dev/project-dev/agent-studio.bridge-start/tmp/bridge-viewer-design-proof/2026-06-26T03-43-59-852Z-shared-chrome-c-final/design-proof.json:1)
- The proof JSON records all three routes with
  `contentHeaderEndsBeforeRail=true`, `railStartsAtTop=true`,
  `canvasBelowHeader=true`, and `switcherInsideTopbar=true`.
- The Files screenshot still shows `Loading file`, so this checkpoint is only
  design/chrome geometry proof. It does not close FileViewer content-load,
  preload, scheduler, or latency proof.

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
- Resolved implementation-review blocker: a prior dev-server artifact recorded
  the legacy compatibility Files URL as the main Files proof. The current
  verifier proves and records the explicit
  `?fixture=worktree&viewer=file&workers=on&scenario=current-worktree` route.
- Resolved implementation-review finding: the prior worktree verifier could fall
  back to synthetic DOM `dispatchEvent` clicks. Current product E2E proof removes
  that fallback and uses actionability-checked browser interactions with bounded
  waits.
- Fix proof, 2026-06-25: `BridgeWeb/scripts/verify-bridge-viewer-worktree-dev-server.ts`
  now normalizes the canonical Files proof URL to explicit `viewer=file`, records
  the required Files, Review, and Review file-target route set in the
  JSON/console proof, removes synthetic tree-row and filter-option click
  fallbacks, and proves row selection through Playwright's actionability-checked
  click path. The Bridge menu dismissal guard only sends Escape when a visible
  Bridge portal exists, blurs the focused element first, and asserts FileViewer
  search, regex, filter, and status state is preserved so a filtered proof cannot
  be silently weakened.
  `pnpm --dir BridgeWeb run test:dev-server:worktree` exited 0 and wrote
  `tmp/bridge-viewer-worktree-dev-server/2026-06-26T00-45-05-123Z/worktree-dev-server-proof.json`.
  The artifact records
  `devServerUrl = http://127.0.0.1:5173/?fixture=worktree&viewer=file&workers=on&scenario=current-worktree`,
  matching `observedLocationHref` and `observedPageUrl`.
- Legacy URL observation, 2026-06-25: the compatibility URL
  `?fixture=worktree&workers=on&scenario=current-worktree` was live-debugged and
  currently reaches `BridgeApp`/`BridgeViewerAppShell` in File mode, but did not
  expose the FileTree/CodeView owner markers or selected content required by
  Gate 0.a. It is not included as a required passing route for this checkpoint.
- Accepted performance design update: FileViewer click latency must be treated
  as scheduler/preload work. Current code has generic scheduler lanes and
  Worktree/File demand stimuli, but the FileViewer runtime/UI does not yet emit
  viewport, adjacent, hover/focus, or recently-updated-file preload stimuli.
  The next implementation slice should add an app-specific
  `dispatchDemandStimuli(...)` seam, descriptor-backed body-registry preloads,
  scoped cancellation groups, preload disposition telemetry, and click-to-ready
  latency proof.

## 2026-06-26 Checkpoint: Shared Content Header And Right-Rail Alignment

Status:
the Gate 0.a shared visible-shell correction is implemented and committed in
`85e98cd6` (`Align BridgeViewer shared file review chrome`). The workflow event
`88b92d37` records the checkpoint. This closes the specific UX blocker where
the header/switcher could appear app-wide or visually disconnected from the
content region, and where FileViewer/ReviewViewer screenshots were not tied to
the accepted `source / selected target` title contract. It does not close Gate
0.a as a whole.

Implemented/proven:

- FileViewer and ReviewViewer use one shared BridgeViewer content header.
- The header belongs only to the left content region; it does not cover the
  right rail and does not push the right rail down.
- The title uses the accepted `source / selected target` form.
- The right rail starts at the top of the viewer and keeps Review-style compact
  toolbar sizing.
- Files context still renders through Pierre FileTree, Pierre CodeView/File,
  Shiki/Pierre, and the worker path when `workers=on`.
- The dev-server verifier still proves the explicit Files, Review, and Review
  file-target route set and rejects standalone `WorktreeFileApp`.

Proof:

- `pnpm --dir BridgeWeb run check`
  - Exit: 0
  - Result: type-aware oxlint, architecture check, oxfmt, and `tsc --noEmit`
    passed. Existing non-fatal `no-await-in-loop` warnings remain in the
    dev-server verifier script.
- `pnpm --dir BridgeWeb run test:dev-server:worktree`
  - Exit: 0
  - Artifact:
    `tmp/bridge-viewer-worktree-dev-server/2026-06-26T02-32-00-284Z/worktree-dev-server-proof.json`
  - Key artifact facts:
    `sharedShellProof.contentTitleText = dev-worktree-source / BridgeWeb/pnpm-lock.yaml`,
    `sharedShellProof.contentTopbarStopsBeforeSidebar = true`,
    `sharedShellProof.sidebarStartsAtContentTopbar = true`,
    `sharedShellProof.contextSwitcherInsideContentTopbar = true`,
    `sharedShellProof.codeOwner = CodeView.file`,
    `sharedShellProof.treeOwner = FileTree`,
    `sharedShellProof.shikiRendering = pierre`,
    `sharedShellProof.workerPoolState = ready`,
    `fileToReviewHandoffProof.standaloneWorktreeFileAppCount = 0`,
    and `scrollExtentCanary.stableAnchorPass = true`.
- Screenshot artifacts:
  - `tmp/bridge-viewer-worktree-dev-server/2026-06-26T02-32-00-284Z/manual-shared-shell-proof/file.png`
  - `tmp/bridge-viewer-worktree-dev-server/2026-06-26T02-32-00-284Z/manual-shared-shell-proof/review.png`
  - `tmp/bridge-viewer-worktree-dev-server/2026-06-26T02-32-00-284Z/manual-shared-shell-proof/reviewFileTarget.png`
- Geometry artifact:
  `tmp/bridge-viewer-worktree-dev-server/2026-06-26T02-32-00-284Z/manual-shared-shell-proof/geometry.json`.
- Screenshot geometry refresh:
  File, Review, and Review file-target modes recorded content topbar `left=0`,
  `right=1388`, `height=36`; right rail `left=1388`, `width=340`, `top=0`;
  and code canvas `top=36`.

Still open:

- implementation-review-swarm over the current checkpoint
- neutral shared-chrome primitive ownership review/fix: the target design is
  BridgeViewer shared chrome, not permanent Review-namespaced primitives
- Review file-target proof must record comparison/source identity, not only a
  path/version/content result
- hidden inactive ReviewViewer side effects review/fix if accepted
- review-content cancellation/abort audit if accepted
- file-click responsiveness/preload telemetry slice
- native Agent Studio Swift-hosted Bridge/WKWebView proof
- final PR-ready wrapup

Recommended next workflow:
`shravan-dev-workflow:implementation-review-swarm` for source-backed review of
`85e98cd6`, the fresh visible UX proof, and the remaining Gate 0.a blockers
before the next implementation slice.

Spec/plan reconciliation update, 2026-06-26:

- Promoted the visible-shell design from "ReviewViewer style baseline" to a
  neutral BridgeViewer shared chrome ownership contract. Review-namespaced
  button/icon reuse is implementation debt unless moved or explicitly accepted
  by implementation review.
- Clarified the active/inactive viewer context contract. Hidden mounted contexts
  may retain memory and accept lifecycle invalidations, but cannot initiate new
  foreground content work or visible loading/selection mutations. Any inactive
  work must be explicitly background/speculative and stale-droppable by active
  context, source, and generation.
- Clarified Review file-target proof. A Review file target must carry accepted
  Review comparison identity, source identity, review item or file ref, version,
  target kind, and active context. Path-only proof is not enough.
- The next review should treat these as design-contract corrections to inspect
  against current code before the next implementation slice.

Phase skills must return:

```text
phase_result: complete | blocked | needs_revision | not_applicable
evidence: <commands with exit codes, artifact paths, findings, or explicit
not-run/blocked reasons; transcript notes are supplemental only>
recommended_next_workflow: <shravan-dev-workflow skill or terminal>
recommended_transition_reason: <one sentence>
```

## 2026-06-26 Design Geometry Refresh

The shared BridgeViewer shell design is now tightened in the durable spec:
title/source lives on the left side of the content header, the `Files | Review`
switcher and content actions live on the right side of that same content
header, and the header belongs only to the left content region. The right rail
starts at the top of the app and is not covered or pushed down by the content
header.

Updated specs:

- `docs/specs/bridge-viewer-transport/spec.md`
- `tmp/spec-workflows/2026-06-22-bridge-transport-streaming-spec/spec.md`

Fresh screenshots captured with Playwright driving local Google Chrome against
the live Vite dev server on `127.0.0.1:5173`:

- `tmp/bridge-viewer-design-proof/2026-06-26T03-04-21-148Z/file.png`
- `tmp/bridge-viewer-design-proof/2026-06-26T03-04-21-148Z/review.png`
- `tmp/bridge-viewer-design-proof/2026-06-26T03-04-21-148Z/review-file-target.png`
- `tmp/bridge-viewer-design-proof/2026-06-26T03-04-21-148Z/geometry.json`

Geometry facts from the capture:

- Files, Review diff, and Review file-target routes all recorded content topbar
  `left=0`, `right=1708`, `height=36`.
- The right rail recorded `left=1708`, `width=340`, and `top=0`.
- The code canvas recorded `top=36`.
- All three routes recorded `contentHeaderEndsBeforeRail=true`,
  `railStartsAtTop=true`, and `canvasBelowHeader=true`.

Important caveat:

- This is design-geometry evidence only. The FileViewer screenshot still shows
  `Loading file`, so content-load latency/preload behavior is not closed by this
  refresh and remains part of the FileViewer scheduler/content proof gate.

## 2026-06-26 Spec Review Delta

Spec-review lanes accepted these bounded corrections before implementation
continues:

- Review file-target identity is now a parent-spec invariant, not only a child
  protocol note. Review-context file targets must bind to an accepted
  `reviewComparison` source and proof must record comparison id, source
  identity, review item id or resolved file ref, version, target kind, and active
  context.
- Inactive viewer contexts now have an explicit proof row: hidden/mounted
  contexts may keep memory and safe background/speculative work, but cannot emit
  new foreground fetches, route-level foreground telemetry, visible
  loading/selection mutations, or mark-viewed-style user-visible side effects.
- Worktree/File provenance belongs in the shared content-header title slot or
  right-rail toolbar. It must not reintroduce a second Files-only top row.
- FileViewer click-to-ready timing starts at a browser actionability-checked
  click or refresh and ends when the selected file identity is visible and Pierre
  CodeView/File has rendered non-loading file lines for that target.
- The remaining Gate 0.a order is: implementation review disposition, dev-server
  content/load proof, then native Agent Studio Bridge/WKWebView proof.

## 2026-06-26 Active Context Retention Checkpoint

The Review inactive-context fix is narrower than "turn Review off." The current
contract is:

- keep Review projection/model memory alive across Files/Review toggles;
- pause or abort inactive Review foreground content work and user-visible
  effects;
- keep the content header over the left content region only;
- keep the right rail top-aligned and independently tooled;
- prove all of this with real browser screenshots and the dev-server verifier.

Implementation delta:

- `BridgeWeb/src/app/bridge-app.tsx` passes `isActive` into File and Review
  mode hosts.
- Review projection coordination continues to receive `reviewPackage`; this
  preserves Review item order/materialized identity while hidden.
- Inactive Review visible content hydration receives `null`.
- Inactive Review selected-content requests abort.
- Inactive Review app-control/select-item listeners detach.
- Inactive Review markdown preview work aborts.
- Inactive Review first-render telemetry and `review.markFileViewed` RPC do not
  run.
- `BridgeWeb/src/components/ui/dropdown-menu.tsx` now imports Base UI named prop
  types instead of `ComponentProps<typeof ...>` so BridgeWeb `check` is not
  blocked by the redundant-type lint rule.

Fresh proof:

- `pnpm --dir BridgeWeb run test:dev-server:worktree`
- Exit: `0`
- Artifact:
  `tmp/bridge-viewer-worktree-dev-server/2026-06-26T05-20-18-995Z/worktree-dev-server-proof.json`
- Key facts recorded:
  - `sharedShellOwner=BridgeViewerAppShell`
  - `codeOwner=CodeView.file`
  - `treeOwner=FileTree`
  - `shikiRendering=pierre`
  - `workerPoolState=ready`
  - `contentTopbarStopsBeforeSidebar=true`
  - `sidebarStartsAtContentTopbar=true`
  - `standaloneWorktreeFileAppCount=0`
  - Files -> Review handoff selected `.gitignore`
  - Review file target materialized as `file` with 92 lines
  - Return to Files and back to Review preserved `.gitignore`

Screenshot/onlook artifacts:

- `tmp/bridge-viewer-browser-onlook/2026-06-26T05-02-19-553Z/1-file-current-worktree-gitignore.png`
- `tmp/bridge-viewer-browser-onlook/2026-06-26T05-02-19-553Z/1-file-current-worktree-gitignore--open-review-comparison.png`
- `tmp/bridge-viewer-browser-onlook/2026-06-26T05-02-19-553Z/1-file-current-worktree-gitignore--open-review-comparison--steady.png`
- `tmp/bridge-viewer-browser-onlook/2026-06-26T05-02-19-553Z/2-review-current-worktree.png`
- `tmp/bridge-viewer-browser-onlook/2026-06-26T05-02-19-553Z/3-review-presentation-file-gitignore-current.png`
- `tmp/bridge-viewer-browser-onlook/2026-06-26T05-02-19-553Z/capture-results.json`

Current open work:

- Review content route fanout is still visible in the proof artifact, including
  a high review file-target route hit count. This belongs to scheduler/content
  pressure work, not the shell geometry fix.
- File click-to-ready latency and speculative preload lanes still need
  telemetry-backed tuning.
- Native Agent Studio Bridge/WKWebView proof is still required before PR-ready.
