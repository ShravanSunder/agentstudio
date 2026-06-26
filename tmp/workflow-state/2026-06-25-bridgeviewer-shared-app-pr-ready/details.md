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
  does not close FileViewer responsiveness, preload disposition, scheduler queue
  behavior, or Review route-fanout/content-pressure proof

0.a.5 file-load responsiveness/preload and route-pressure proof
  proves FileViewer selected-file opens reach visible Pierre CodeView/File
  content from real browser clicks with recorded disposition, queue state, and
  click-to-ready timing; a screenshot stuck on `Loading file` keeps this open
  current provider-cache checkpoint reduces the dev-server file-content read by
  serving the accepted descriptor cursor directly; full preload/scheduler
  disposition telemetry remains open. 0.a.5 also owns visible, nearby,
  speculative, and recently-updated-file preload behavior plus Review
  route-fanout/content-pressure closure.
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
      `tmp/bridge-viewer-worktree-dev-server/2026-06-26T07-11-01-784Z/worktree-dev-server-proof.json`
  open contract gates:
    - demand scheduler admission failures must be observable per descriptor and
      per lane. Queue-full or byte-limit rejection cannot disappear into only an
      aggregate counter; `openFile`, `refreshOpenFile`, and visible/preload
      demand dispatch need saturation tests.
    - `worktree.reset.replacementDescriptor` must either materialize through the
      runtime/open-file reconcilers or be removed from the protocol contract.
      A reset-with-inline-replacement test is required before this gate closes.
    - multi-file preload/demand work must use settled-result accounting unless
      a path documents and tests an all-or-nothing contract. Review direct
      content fallback loading still needs an explicit atomic-vs-partial
      decision before PR-ready.

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

2026-06-26 demand/preload review checkpoint:

- Implementation review found no new `Promise.all` regression in the touched
  FileViewer demand path. Multi-file preload dispatch uses settled-result
  accounting.
- Fixed immediate visible-demand issues:
  - non-fetchable visible rows no longer enter preload demand.
  - visible descriptor refs are deduped before scheduler dispatch.
  - overlapping visible-demand batches use a latest-request guard so stale
    batches cannot overwrite newer viewport telemetry.
  - Pierre tree model updates schedule demand publication, so expand/collapse
    state changes are not dependent on a scroll event.
  - reset-path browser fixtures now build generation-matched replacement
    descriptors and parse descriptors/frames through the existing Zod schemas.
- Current Pierre constraint: exact viewport/scroll observation still requires a
  scoped DOM adapter because the public `FileTree` React model exposes
  `subscribe()` and item handles but does not expose public visible-row or scroll
  range APIs. Keep that adapter centralized and covered by browser proof until a
  typed Pierre API exists.

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
  latency proof. Recently-updated-file stimuli must be proved directly:
  debounced updates from the active FileViewer source enqueue descriptor-backed
  `speculative` preloads, or `nearby` preloads when adjacent to the selected,
  open, or visible row band; they must not become foreground work unless the
  user opens or refreshes that file.

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

- implementation-execute-plan must address accepted implementation-review
  findings before Gate 0.a can close
- hidden FileViewer inactive-context gating: Files mode must pause/cancel
  foreground surface subscriptions, polling, and hidden loading-state mutation
  while Review is active
- hidden Review inactive-context proof: zero new foreground content requests,
  `review.markFileViewed`, route-level foreground telemetry, and visible
  loading/selection mutations while Files is active
- Review diff proof must use a real actionability-checked Review tree/search
  interaction instead of synthetic `__bridge_select_review_item`
- Review file-target routing/proof must bind comparison/source lineage,
  `reviewItemId` or resolved file ref, version, `targetKind`, and active
  context; path-only selection is not enough
- explicit Files -> Review handoff must not be blocked by retained Review
  search/filter state that hides the requested target
- repeated identical navigation commands must replay when the current target
  moved elsewhere
- browser-visible context memory proof for rail search/filter state and
  rail/canvas scroll restoration
- neutral shared-chrome primitive ownership: the target design is BridgeViewer
  shared chrome, not permanent Review-namespaced primitives
- review-content cancellation/route fanout audit
- file-click responsiveness/preload telemetry slice
- native Agent Studio Swift-hosted Bridge/WKWebView proof
- final PR-ready wrapup

## 2026-06-26 Accepted-C Visual Refresh And Implementation Review Reduction

Fresh dev-server proof:

- `pnpm --dir BridgeWeb run test:dev-server:worktree`
- Exit: 0
- Artifact:
  `tmp/bridge-viewer-worktree-dev-server/2026-06-26T06-06-36-494Z/worktree-dev-server-proof.json`

Fresh accepted-C screenshots and geometry:

- `tmp/bridge-viewer-design-proof/2026-06-26T06-10-55-797Z-accepted-c-refresh/files.png`
- `tmp/bridge-viewer-design-proof/2026-06-26T06-10-55-797Z-accepted-c-refresh/review-diff.png`
- `tmp/bridge-viewer-design-proof/2026-06-26T06-10-55-797Z-accepted-c-refresh/review-file-target.png`
- `tmp/bridge-viewer-design-proof/2026-06-26T06-10-55-797Z-accepted-c-refresh/accepted-c-design-proof.json`

The geometry artifact records all three routes with content topbar `left=0`,
`right=1708`, `height=36`; right rail `left=1708`, `width=340`, `top=0`; code
canvas `top=36`; and accepted-C predicates true for shared shell, header ending
before rail, rail at `y=0`, canvas below header, switcher inside topbar, and
controls inside topbar.

Browser/onlook agent `019f028e-c7a5-7732-b06e-7f65a0601fb9` passed this
visual/layout proof with no concrete layout mismatches. The pass is scoped to
visual/layout only and does not close inactive side effects, Review file-target
lineage, neutral chrome ownership, context memory persistence/behavior, or
file-load/preload behavior.

Implementation review reduction accepted the following as open implementation
work, not spec-loop work:

- Hidden FileViewer remains mounted and is suspected to keep foreground
  worktree surface polling/subscription alive after switching to Review.
- Hidden Review no-foreground-work proof is incomplete; returning ready is not
  proof of zero inactive foreground work.
- Review diff selection proof still uses a synthetic app event and must be
  converted to visible tree/search interaction proof.
- Review file-target selection is still too path-shaped; it must prefer
  `reviewItemId`, validate comparison/source lineage, and record lineage in the
  verifier artifact.
- Retained Review filters/search can hide the explicit Files -> Review target;
  explicit target navigation must override that instead of falling back to the
  first visible item.
- Repeated identical navigation commands can become lifetime no-ops after the
  first application; de-dupe must be target-state aware, not command-id-only.
- Context memory proof must cover browser-visible search/filter and scroll
  restoration.
- Neutral shared-chrome extraction remains open while FileViewer/header import
  Review-namespaced chrome primitives.

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
  a high review file-target route hit count. This belongs to 0.a.5
  scheduler/content-pressure work, not the shell geometry fix.
- File click-to-ready latency plus visible, nearby, speculative, and
  recently-updated-file preload lanes still need telemetry-backed proof.
- Initial 0.a.5 proof gates are conservative and not production tuning:
  one foreground content request per selected target epoch; recorded route hits,
  cancellations, stale drops, queue depth, in-flight counts, lane upgrades, and
  byte admission/defer/drop decisions; no foreground work blocked behind lower
  lanes; no lane above its declared executor cap; no admitted bytes without a
  recorded source/lane budget.
- Native Agent Studio Bridge/WKWebView proof is still required before PR-ready.

## 2026-06-26 Accepted-C Visual Refresh

Accepted decision C is now the named shared-shell design target:

- one `BridgeViewerAppShell`;
- content topbar/header only over the left content canvas;
- title/source on the left of that header;
- `Files | Review` switcher plus content actions on the right of that header;
- Pierre right rail remains full-height and top-aligned at `y=0`;
- FileViewer and ReviewViewer use the same compact shared chrome/control scale.

Fresh screenshots and geometry proof:

- `tmp/bridge-viewer-design-proof/2026-06-26T05-41-43-291Z-accepted-c-refresh/files.png`
- `tmp/bridge-viewer-design-proof/2026-06-26T05-41-43-291Z-accepted-c-refresh/review-diff.png`
- `tmp/bridge-viewer-design-proof/2026-06-26T05-41-43-291Z-accepted-c-refresh/review-file-target.png`
- `tmp/bridge-viewer-design-proof/2026-06-26T05-41-43-291Z-accepted-c-refresh/accepted-c-design-proof.json`
- `tmp/workflow-state/2026-06-25-bridgeviewer-shared-app-pr-ready/accepted-c-visual-onlook-2026-06-26.md`

The proof records Files, Review diff, and Review file-target routes with:

- `shellOwner=BridgeViewerAppShell`;
- `contentHeaderEndsBeforeRail=true`;
- `railStartsAtTop=true`;
- `canvasBelowHeader=true`;
- `switcherInsideTopbar=true`;
- `railToolbarHeight=28`;
- `searchControlHeight=28`;
- `standaloneWorktreeFileAppCount=0`.

Second-agent/onlook result:

- PASS for accepted-C topbar placement, rail top alignment, switcher placement,
  compact shared controls, and no standalone/minimal second app.

This refresh proves the accepted design geometry only. It does not close
FileViewer click-to-ready latency, speculative preload behavior, Review route
fanout/content pressure, implementation review, or native Agent Studio
Bridge/WKWebView proof.

## 2026-06-26 Option-C Spec Tightening And Ready Pictures

Spec/plan updates:

- `docs/specs/bridge-viewer-transport/spec.md` and the tmp spec copy now state
  that Review-namespaced shared chrome is only an explicitly tracked failing
  intermediate state. It cannot close a visible UX checkpoint. Gate 0.a requires
  neutral BridgeViewer shared primitives over the existing shadcn/base UI
  substrate.
- `docs/specs/bridge-viewer-transport/spec.md` now has a dedicated Review tree
  interaction proof row. The accepted verifier path is a real Playwright click
  through the visible Review tree/search UI, currently using Pierre's
  `file-tree-container button[data-item-path]` hook until app-owned row hooks
  exist. `__bridge_select_review_item` and direct DOM dispatch are explicitly
  rejected as user-interaction proof.
- `docs/specs/bridge-viewer-transport/review-protocol.md` and the tmp protocol
  copy now distinguish the immediate `reviewItemId` fix from strict
  `comparisonId` enforcement. `reviewItemId` already exists in the navigation
  model and must be preferred before path fallback. Strict comparison authority
  needs a Review package/runtime contract extension before it can be honestly
  enforced.
- The active plan now names the next failing tests:
  `applies review file target by reviewItemId before path fallback`,
  `reapplies same review navigation command after selection moved elsewhere`,
  explicit-target filter/search refinement tests, and replacement of the
  dev-server Review synthetic selector helper with the real tree/search click.

Fresh product proof:

- `pnpm --dir BridgeWeb run test:dev-server:worktree`
- Exit: `0`
- Artifact:
  `tmp/bridge-viewer-worktree-dev-server/2026-06-26T06-39-57-805Z/worktree-dev-server-proof.json`
- Key facts recorded:
  - `selectedContentState=ready`
  - `selectedDisplayPath=BridgeWeb/pnpm-lock.yaml`
  - `treePathCount=478`
  - `sharedShellOwner=BridgeViewerAppShell`
  - `codeOwner=CodeView.file`
  - `treeOwner=FileTree`
  - `shikiRendering=pierre`
  - `workerPoolState=ready`
  - `contentTopbarStopsBeforeSidebar=true`
  - `sidebarStartsAtContentTopbar=true`
  - `standaloneWorktreeFileAppCount=0`

Fresh ready screenshots and geometry:

- `tmp/bridge-viewer-design-proof/2026-06-26T06-41-32-966Z-accepted-c-doc-refresh-ready/files.png`
- `tmp/bridge-viewer-design-proof/2026-06-26T06-41-32-966Z-accepted-c-doc-refresh-ready/review-diff.png`
- `tmp/bridge-viewer-design-proof/2026-06-26T06-41-32-966Z-accepted-c-doc-refresh-ready/review-file-target.png`
- `tmp/bridge-viewer-design-proof/2026-06-26T06-41-32-966Z-accepted-c-doc-refresh-ready/accepted-c-design-proof.json`
- `tmp/bridge-viewer-worktree-dev-server/2026-06-26T07-11-01-784Z/worktree-file-ready.png`
- `tmp/bridge-viewer-worktree-dev-server/2026-06-26T07-11-01-784Z/worktree-file-search-result.png`
- `tmp/bridge-viewer-worktree-dev-server/2026-06-26T07-11-01-784Z/worktree-file-stale-refresh.png`
- `tmp/bridge-viewer-worktree-dev-server/2026-06-26T07-11-01-784Z/worktree-dev-server-proof.json`

The screenshot proof records:

- `allHeadersEndBeforeRail=true`;
- `allRailsStartAtTop=true`;
- `allCanvasesBelowHeader=true`;
- `allSwitchersInsideTopbar=true`;
- `allControlsInsideTopbar=true`;
- `noStandaloneWorktreeFileApp=true`;
- `noSourcePending=true`.

Open implementation blockers remain:

- hidden FileViewer inactive-context gating;
- hidden Review no-foreground-work proof;
- Review tree interaction verifier still needs the real click path;
- Review file-target resolver/proof must prefer `reviewItemId` and record
  lineage honestly;
- explicit Review targets must clear retained Review search/filter refinements
  that hide the requested target;
- repeated deterministic navigation commands must replay when the current
  selection moved away;
- neutral BridgeViewer shared chrome extraction;
- route fanout/content pressure and file-load/preload telemetry;
- native Agent Studio Bridge/WKWebView proof.

2026-06-26 current spec/design refresh:

- Parent and tmp specs are byte-aligned after the refresh. The parent spec now
  states that Worktree/File and dev query paths provide selector intent only;
  Review must accept the selector before app composition may create a
  `reviewComparison` navigation command.
- Worktree/File child protocol now points to the canonical parent navigation
  shape instead of defining a weaker path-only Review file target. Its required
  Review file-target proof URL includes `workers=on`,
  `scenario=current-worktree`, and `version=<base|head|current>`.
- Neutral shared chrome now has a concrete forbidden edge: shared
  BridgeViewer shell/header/context switcher/rail-control code must not
  permanently import Review-only chrome modules through direct imports,
  re-export wrappers, or aliases.
- Security wording is protocol-neutral: forged page-world frames from Review,
  Worktree/File, dev fixtures, markdown, or agent communication can corrupt UI
  projection at worst; byte authority still requires a Swift-issued lease.
- Fresh dev-server proof passed:
  `pnpm --dir BridgeWeb run test:dev-server:worktree`.
- Fresh proof artifact:
  `tmp/bridge-viewer-worktree-dev-server/2026-06-26T07-11-01-784Z/worktree-dev-server-proof.json`.
- Fresh pictures inspected:
  `tmp/bridge-viewer-worktree-dev-server/2026-06-26T07-11-01-784Z/worktree-file-ready.png`,
  `tmp/bridge-viewer-worktree-dev-server/2026-06-26T07-11-01-784Z/worktree-file-search-result.png`,
  and
  `tmp/bridge-viewer-worktree-dev-server/2026-06-26T07-11-01-784Z/worktree-file-stale-refresh.png`.
- Focused implementation anchors are now red for expected reasons:
  `applies review file target by reviewItemId before path fallback`,
  `reapplies same review navigation command after selection moved elsewhere`,
  and `explicit review file target clears retained filters hiding the target`.

2026-06-26 implementation/design checkpoint after accepting option C:

- Focused Review navigation anchors are now green:
  `pnpm --dir BridgeWeb exec vitest run src/review-viewer/code-view/bridge-code-view-materialization.unit.test.ts src/app/bridge-app.integration.test.tsx -t "file-target loading|review file target|same review navigation command|explicit review file target" --reporter verbose`
  exited 0 with 2 files passed, 6 tests passed, 59 skipped.
- Broader BridgeApp/CodeView focused suite is green:
  `pnpm --dir BridgeWeb exec vitest run src/review-viewer/code-view/bridge-code-view-materialization.unit.test.ts src/review-viewer/code-view/bridge-code-view-controller.unit.test.ts src/app/bridge-app.integration.test.tsx --reporter verbose`
  exited 0 with 3 files passed, 69 tests passed.
- Fresh dev-server proof passed:
  `pnpm --dir BridgeWeb run test:dev-server:worktree`.
- Fresh dev-server proof artifact:
  `tmp/bridge-viewer-worktree-dev-server/2026-06-26T07-29-01-656Z/worktree-dev-server-proof.json`.
- Fresh Files screenshots:
  `tmp/bridge-viewer-worktree-dev-server/2026-06-26T07-29-01-656Z/worktree-file-ready.png`,
  `tmp/bridge-viewer-worktree-dev-server/2026-06-26T07-29-01-656Z/worktree-file-search-result.png`,
  and
  `tmp/bridge-viewer-worktree-dev-server/2026-06-26T07-29-01-656Z/worktree-file-stale-refresh.png`.
- Supplemental Review screenshots because the verifier saved only Files route
  screenshots:
  `tmp/bridge-viewer-worktree-dev-server/2026-06-26T07-29-01-656Z/manual-review-mode-screenshots/review-diff.png`,
  `tmp/bridge-viewer-worktree-dev-server/2026-06-26T07-29-01-656Z/manual-review-mode-screenshots/review-file-target.png`,
  and
  `tmp/bridge-viewer-worktree-dev-server/2026-06-26T07-29-01-656Z/manual-review-mode-screenshots/manual-review-mode-screenshots.json`.
- The supplemental Review screenshot JSON records:
  `reviewDiff.materializedType=diff`,
  `reviewFileTarget.materializedType=file`,
  `contentTopbar.right=1388`,
  `codePanel.top=36`,
  `reviewRail.top=6`,
  and `contextSwitcherInsideTopbar=true` for both Review routes.
- Browser/onlook agent `019f02d6-d856-7db0-95f1-db3475872a4a` found no P0/P1/P2
  issues, passed the Files-context C slice, and correctly marked the automated
  screenshot set insufficient for full accepted-C closure until Review
  screenshots were supplied.
- `pnpm --dir BridgeWeb run check` initially failed only on formatting for
  `src/app/bridge-app.tsx`; `pnpm --dir BridgeWeb exec oxfmt --write
  src/app/bridge-app.tsx` fixed that. Re-run `pnpm --dir BridgeWeb run check`
  before committing.

2026-06-26 accepted-C design clarification refresh:

- Parent and tmp specs now clarify that accepted decision C uses "top right" to
  mean the right slot of the left content header, not the top right of the full
  viewport. The title/source belongs in the left slot; `Files | Review` and
  content actions belong in the right slot; the right rail starts at y=0 and is
  not covered or pushed by the header.
- The plan now requires screenshot comparison of shared control size, selected
  state, focus ring, icon box, border treatment, and spacing. DOM-only proof is
  not enough for this chrome parity item.
- Fresh pictures captured from the live dev server:
  `tmp/bridge-viewer-design-proof/2026-06-26T07-56-40-567Z-accepted-c-user-refresh-ready/files.png`,
  `tmp/bridge-viewer-design-proof/2026-06-26T07-56-40-567Z-accepted-c-user-refresh-ready/review-diff.png`,
  and
  `tmp/bridge-viewer-design-proof/2026-06-26T07-56-40-567Z-accepted-c-user-refresh-ready/review-file-target.png`.
- Fresh geometry artifact:
  `tmp/bridge-viewer-design-proof/2026-06-26T07-56-40-567Z-accepted-c-user-refresh-ready/accepted-c-design-proof.json`.
- The geometry artifact records all three routes with content topbar `left=0`,
  `right=1708`, `height=36`; right rail `left=1708`, `width=340`, `top=0`;
  code canvas `top=36`; and `contentHeaderEndsBeforeRail=true`,
  `railStartsAtTop=true`, `canvasBelowHeader=true`,
  `switcherInsideTopbar=true`, `controlsInsideTopbar=true`, and
  `switcherRightAlignedInContentHeader=true`.
- This is a design/spec proof refresh only. It does not close remaining
  implementation gates: real Review tree interaction proof, neutral shared
  chrome ownership, route fanout/content pressure, file-load/preload telemetry,
  or native Agent Studio Bridge/WKWebView proof.

2026-06-26 accepted-C verifier screenshot refresh:

- `BridgeWeb/scripts/verify-bridge-viewer-worktree-dev-server.ts` now records
  Review and Review file-target screenshots in the verifier proof instead of
  leaving Review visual proof as a manual supplemental capture.
- Earlier verifier screenshot-refresh proof passed:
  `pnpm --dir BridgeWeb run test:dev-server:worktree`.
- Earlier proof artifact:
  `tmp/bridge-viewer-worktree-dev-server/2026-06-26T08-25-12-296Z/worktree-dev-server-proof.json`.
- Earlier pictures inspected:
  `tmp/bridge-viewer-worktree-dev-server/2026-06-26T08-25-12-296Z/worktree-file-ready.png`,
  `tmp/bridge-viewer-worktree-dev-server/2026-06-26T08-25-12-296Z/worktree-review-ready.png`,
  `tmp/bridge-viewer-worktree-dev-server/2026-06-26T08-25-12-296Z/worktree-review-file-target-ready.png`,
  `tmp/bridge-viewer-worktree-dev-server/2026-06-26T08-25-12-296Z/worktree-file-search-result.png`,
  and
  `tmp/bridge-viewer-worktree-dev-server/2026-06-26T08-25-12-296Z/worktree-file-stale-refresh.png`.
- Parent inspection confirmed the accepted-C layout remained visually correct in
  Files, Review diff, and Review file-target: title/source left, `Files |
  Review` plus content actions right in the content-only header, right rail
  top-aligned outside the header, Pierre FileTree on the right, and
  Pierre/Shiki CodeView/File on the left.
- Durable spec, tmp spec, and active plan now point at this verifier-owned
  screenshot packet and the exact Review tree search selectors required for the
  next real-click verifier implementation.
- Still open: the Review route verifier still uses
  `__bridge_select_review_item`; next implementation step must replace it with
  the real Pierre tree search click path before the Review tree interaction
  proof can close.

2026-06-26 accepted-C user confirmation and fresh picture refresh:

- User confirmed option C as the design direction.
- Durable spec and tmp spec now include accepted decision C in the design
  decision ledger: content header only over the left canvas; title/source left;
  `Files | Review` plus content actions right; Pierre right rail outside the
  header, full-height, top-aligned, and using compact rail-owned toolbar.
- Earlier user-confirmed option-C proof passed:
  `pnpm --dir BridgeWeb run test:dev-server:worktree`.
- Earlier proof artifact:
  `tmp/bridge-viewer-worktree-dev-server/2026-06-26T08-35-04-033Z/worktree-dev-server-proof.json`.
- Earlier pictures inspected:
  `tmp/bridge-viewer-worktree-dev-server/2026-06-26T08-35-04-033Z/worktree-file-ready.png`,
  `tmp/bridge-viewer-worktree-dev-server/2026-06-26T08-35-04-033Z/worktree-review-ready.png`,
  and
  `tmp/bridge-viewer-worktree-dev-server/2026-06-26T08-35-04-033Z/worktree-review-file-target-ready.png`.
- Earlier proof fields:
  `contentTopbarStopsBeforeSidebar=true`,
  `contextSwitcherInsideContentTopbar=true`,
  `sidebarStartsAtContentTopbar=true`,
  `sidebarIsRight=true`,
  `workerPoolState=ready`.
- The pictures match option C visually across Files, Review diff, and Review
  file-target: one shared BridgeViewer shell, content-only header, right rail
  top-aligned, Pierre FileTree on the right, and Pierre/Shiki CodeView/File on
  the left.
- Still open and not hidden by this proof: Review verifier real-click work,
  neutral shared-chrome ownership, hidden inactive-context side-effect proof,
  Review content route fanout/content pressure, FileViewer preload latency,
  recently-updated-file preload behavior, and native Agent Studio Bridge/WKWebView
  proof. The fresh Review file-target proof records
  `reviewContentRouteHitCount=292`, so 0.a.5 remains a real pressure blocker.

2026-06-26 Review real-click verifier checkpoint:

- `BridgeWeb/scripts/verify-bridge-viewer-worktree-dev-server.ts` now selects
  the Review target through the visible Pierre tree search UI instead of
  synthetic `__bridge_select_review_item` / `document.dispatchEvent`.
- Lower-layer guard passed:
  `pnpm --dir BridgeWeb exec vitest run scripts/verify-bridge-viewer-worktree-dev-server.unit.test.ts --reporter verbose`
  with 1 file passed, 6 tests passed.
- Full dev-server proof passed:
  `pnpm --dir BridgeWeb run test:dev-server:worktree`.
- Fresh proof artifact:
  `tmp/bridge-viewer-worktree-dev-server/2026-06-26T10-13-26-058Z/worktree-dev-server-proof.json`.
- Fresh pictures inspected:
  `tmp/bridge-viewer-worktree-dev-server/2026-06-26T10-13-26-058Z/worktree-file-ready.png`,
  `tmp/bridge-viewer-worktree-dev-server/2026-06-26T10-13-26-058Z/worktree-review-ready.png`,
  and
  `tmp/bridge-viewer-worktree-dev-server/2026-06-26T10-13-26-058Z/worktree-review-file-target-ready.png`.
- Proof fields:
  `reviewSelectionProof.selectionMethod=playwright-review-tree-search-click`,
  `searchOpened=true`,
  `searchInputValue=sources/agentstudio/atomregistry.swift`,
  `clickedRowItemPath=Sources/AgentStudio/AtomRegistry.swift`,
  `clickedRowItemType=file`, `clickedRowVisible=true`,
  `fileToReviewHandoffProof.expectedDisplayPath=.gitignore`,
  `fileToReviewHandoffProof.selectedMaterializedItemType=file`,
  `fileToReviewHandoffProof.reviewModeAfterReturnToFile=file`,
  `reviewFileTargetRouteProof.expectedDisplayPath=Sources/AgentStudio/AtomRegistry.swift`,
  `reviewFileTargetRouteProof.expectedVersion=current`, and
  `reviewFileTargetRouteProof.selectedMaterializedItemType=file`.
- This closes the Review tree interaction proof row for the dev-server slice.
  The DiffsHub/Pierre chrome pass is included in the same current checkpoint:
  header/right rail `#181825`, canvas `#1E1E2E`, compact shared controls,
  `#313244` hover, and `#B4BEFE` focus. It does not close Gate 0.a. Remaining
 blockers are hidden inactive-context side-effect proof, Review content route
 fanout/content pressure, FileViewer preload latency/telemetry, native Agent
 Studio Bridge/WKWebView proof, and implementation review disposition.

2026-06-26 visual parity correction required before next commit:

- User review rejected the latest visual checkpoint as incomplete. The specific
  misses are no longer allowed to stay implicit in "DiffsHub-like chrome" or
  "shared controls" language.
- User also clarified the BridgeWeb React UI rule: reusable controls must use
  owned shadcn-style primitives from `BridgeWeb/src/components/ui/`; if a
  primitive such as `ToggleGroup` is missing, add the primitive source and
  customize it rather than hand-rolling route-local toggles or toolbar controls.
- DeepWiki-backed shadcn guidance identifies `ToggleGroup` as the proper
  primitive family for compact option sets such as `Files | Review`; use that
  unless implementation-time source inspection finds an equivalent owned
  shadcn primitive already in the repo.
- The active spec and plan now require exact acceptance rows for content header
  height, right-rail toolbar height, button visual box size, icon size, focus
  ring, hover/selected fill, segmented toggle height, darker chrome color,
  border rhythm, title/provenance text, truncation, and rail metadata. The
  FileViewer rail toolbar must not show visible count/source metadata such as
  `480/480 dev-worktree-source...`.
- The custom `Files | Review` switcher and the Review projection-mode segmented
  control are both failing intermediates until they use the neutral
  BridgeViewer wrapper over the owned shadcn primitive. Shared shell/header/rail
  code must also move off permanent Review-namespaced chrome ownership.
- The next code checkpoint must update the UI against those rows and must prove
  them with Playwright/dev-server geometry plus screenshot inspection. Generic
  DOM proof, JSON proof, or a broad visual PASS is not enough.
- A browser/onlook subagent must receive the same atomic checklist and compare
  Files, Review diff, Review file-target, and the supplied DiffsHub/Pierre
  reference screenshots before the checkpoint can be accepted.

2026-06-26 renderer/source-boundary requirement additions:

- BridgeViewer Pierre rendering defaults to wrapped lines. The shared
  CodeView/File options must pass `overflow: 'wrap'` for Review diff targets,
  Review file targets, and Files file targets. Pierre's upstream default is
  `scroll`, so this is an explicit Bridge setting until a future app-state user
  preference overrides it.
- Worktree/File and worktree-backed Review source adapters must respect
  gitignore and repository ignore policy before publishing tree rows,
  descriptors, route bootstrap targets, review candidates, search candidates,
  or preload demand. This belongs at the provider/source-adapter boundary; it is
  not just a browser-side cosmetic filter.
- Production Swift/native source adapters must use the repo's `agentstudio-git`
  library for git status, diff, ignore-policy, and candidate preparation. Any
  TypeScript git shell helper is allowed only in a clearly marked Vite
  dev-server utility or test fixture utility and must not become production
  Bridge source-adapter plumbing.
- The next implementation checkpoint must include focused unit/integration proof
  for the ignored-path exclusion boundary and browser/dev-server proof that
  FileViewer, Review diff, and Review file-target rendering use wrapped Pierre
  CodeView/File settings.

2026-06-26 wrap/gitignore/source-boundary implementation checkpoint:

- Added BridgeViewer Pierre wrap contract to both Review and Files code surfaces:
  `data-bridge-code-view-overflow=wrap` on `bridge-code-view-panel` and
  `bridge-file-viewer-code-canvas`.
- Tightened the worktree dev-server verifier so Files, Review diff, and Review
  file-target routes fail unless the visible Pierre CodeView/File surface reports
  `overflow=wrap`.
- Tightened Review rendered-selection proof so a text-rendered diff no longer
  counts unless the Review CodeView also reports `overflow=wrap`.
- Added gitignore provider proof for ignored untracked files and documented the
  source-boundary: production Swift/native Bridge git data prep must use
  `agentstudio-git`; TypeScript git shell helpers are only dev-server or test
  fixture utilities.
- Focused proof passed:
  `pnpm --dir BridgeWeb exec vitest run src/review-viewer/code-view/bridge-code-view-panel-scroll.unit.test.tsx -t "passes compact DiffsHub-style CodeView options" --reporter verbose`
  with 1 file passed, 1 test passed, 25 skipped.
- Focused verifier proof passed:
  `pnpm --dir BridgeWeb exec vitest run scripts/verify-bridge-viewer-worktree-dev-server.unit.test.ts --reporter verbose`
  with 1 file passed, 6 tests passed.
- Focused gitignore provider proof passed:
  `pnpm --dir BridgeWeb exec vitest run scripts/dev-server/bridge-worktree-dev-provider.integration.test.ts -t "excludes gitignored untracked files" --reporter verbose`
  with 1 file passed, 1 test passed, 12 skipped.
- Full dev-server worktree browser proof passed:
  `pnpm --dir BridgeWeb run test:dev-server:worktree`.
- Fresh proof artifact:
  `tmp/bridge-viewer-worktree-dev-server/2026-06-26T11-57-15-262Z/worktree-dev-server-proof.json`.
- Fresh proof fields:
  `sharedShellProof.codeViewOverflow=wrap`,
  `sharedShellProof.codeOwner=CodeView.file`,
  `sharedShellProof.treeOwner=FileTree`,
  `sharedShellProof.workerPoolState=ready`,
  `reviewRouteProof.reviewRenderedSelectionProof.codeViewOverflow=wrap`,
  `reviewRouteProof.reviewRenderedSelectionProof.selectedMaterializedItemType=diff`,
  `reviewFileTargetRouteProof.selectedCodeViewOverflow=wrap`,
  `reviewFileTargetRouteProof.selectedMaterializedItemType=file`,
  `substituteGuardProof.standaloneWorktreeFileAppCount=0`,
  `treePathCount=484`, and `descriptorCount=484`.
- Dev server was still listening on `127.0.0.1:5173` after the proof run.

2026-06-26 compact shared toggle / dev-server geometry checkpoint:

- Replaced the visible oversized Files/Review control with the owned
  `ToggleGroup` primitive composed over the existing BridgeWeb `Button`
  primitive. The shared context switcher now keeps visible icon + label text,
  uses `Button size="sm"` for the same 24px control scale as the right-rail
  toolbar, preserves `aria-label`/`aria-pressed`, and avoids route-local
  bespoke toggle sizing.
- Added browser-mode proof for the context switcher. The regression now runs
  under Vitest Browser, not a new jsdom file:
  `pnpm --dir BridgeWeb exec vitest --config vitest.browser.config.ts run --project integration-browser src/app/bridge-viewer-content-header.browser.test.tsx --reporter verbose`
  with 1 file passed, 1 test passed. Red proof before the fix failed with
  `expected 20 to be 24`, proving the test catches the undersized/stale toggle
  item geometry.
- Tightened the worktree dev-server verifier so the real browser route proof
  fails unless the Files content header, Review content header, and Review
  right-rail toolbar use the same shared chrome geometry.
- Full BridgeWeb static gate passed:
  `pnpm --dir BridgeWeb run check`.
- Full worktree dev-server browser proof passed:
  `pnpm --dir BridgeWeb run test:dev-server:worktree`.
- Fresh proof artifact:
  `tmp/bridge-viewer-worktree-dev-server/2026-06-26T12-47-35-774Z/worktree-dev-server-proof.json`.
- Fresh proof fields:
  `sharedShellProof.contentHeaderHeight=36`,
  `sharedShellProof.railToolbarHeight=36`,
  `sharedShellProof.contentHeaderMatchesRailToolbarHeight=true`,
  `sharedShellProof.contextSwitcherHeight=24`,
  `sharedShellProof.contextFileButtonHeight=24`,
  `sharedShellProof.contextReviewButtonHeight=24`,
  `sharedShellProof.contextSegmentMatchesRailButtonHeight=true`,
  `reviewRouteProof.reviewHeaderMatchesRailToolbarHeight=true`,
  `reviewRouteProof.reviewRailToolbarUsesSharedAttr=true`,
  `reviewFileTargetRouteProof.reviewHeaderMatchesRailToolbarHeight=true`,
  `reviewFileTargetRouteProof.reviewRailToolbarUsesSharedAttr=true`,
  `sharedShellProof.codeViewOverflow=wrap`,
  `sharedShellProof.codeOwner=CodeView.file`,
  `sharedShellProof.treeOwner=FileTree`,
  `sharedShellProof.workerPoolState=ready`,
  and `substituteGuardProof.standaloneWorktreeFileAppCount=0`.
- A parallel worker also found and fixed one inactive Review foreground-work
  bug: deactivating Review now clears stale `rendering` markdown preview state
  after abort so reactivation can restart foreground markdown work. The focused
  lower-layer regression passed:
  `pnpm --dir BridgeWeb exec vitest run src/app/bridge-app.integration.test.tsx -t "keeps inactive Review mode" --reporter verbose`
  with 1 file passed, 1 test passed, 53 skipped. This lower-layer regression is
  not counted as the browser proof gate because the existing file is jsdom.
- Remaining open before Gate 0.a/PR-ready closure: route fanout/content
  pressure, FileViewer preload latency/telemetry, native Agent Studio
  Bridge/WKWebView proof, implementation review disposition, and follow-up
  browser/native proof for inactive-context no-foreground-work if this remains
  a gate-level blocker.

2026-06-26 compact switcher text-size follow-up checkpoint:

- Fixed the remaining visual miss where the Files/Review segmented control used
  the correct 24px box height but still rendered oversized label text. The owned
  `ToggleGroupItem` primitive now applies the shared compact chrome text size
  for `size="sm"` controls, and `BridgeViewerContextButton` composes the same
  shared chrome class used by other BridgeViewer controls instead of keeping
  route-local visual scale.
- This is still the owned shadcn-style primitive path:
  `BridgeViewerContextSwitcher` -> `ToggleGroup` -> `ToggleGroupItem` ->
  BridgeWeb `Button`.
- Added/kept Vitest Browser proof for both geometry and typography:
  `pnpm --dir BridgeWeb exec vitest --config vitest.browser.config.ts run --project integration-browser src/app/bridge-viewer-content-header.browser.test.tsx --reporter verbose`
  with 1 file passed, 1 test passed. The browser test now asserts
  `contextSwitcherHeight=24`, Files and Review button heights at 24px, and
  computed `font-size=11px` for both labels.
- Full worktree dev-server browser proof passed after the fix:
  `pnpm --dir BridgeWeb run test:dev-server:worktree`.
- Fresh proof artifact:
  `tmp/bridge-viewer-worktree-dev-server/2026-06-26T13-38-19-464Z/worktree-dev-server-proof.json`.
- Fresh proof fields:
  `sharedShellProof.contentHeaderHeight=36`,
  `sharedShellProof.railToolbarHeight=36`,
  `sharedShellProof.contentHeaderMatchesRailToolbarHeight=true`,
  `sharedShellProof.contentHeaderBackground=rgb(24, 24, 37)`,
  `sharedShellProof.railToolbarBackground=rgb(24, 24, 37)`,
  `sharedShellProof.contentHeaderMatchesRailToolbarBackground=true`,
  `sharedShellProof.contextSwitcherHeight=24`,
  `sharedShellProof.contextFileButtonHeight=24`,
  `sharedShellProof.contextReviewButtonHeight=24`,
  `sharedShellProof.contextSegmentMatchesRailButtonHeight=true`,
  `visibleAppProof.filterCountMeaningfullyVisible=false`,
  `visibleAppProof.sourceProvenanceMeaningfullyVisible=false`,
  `fileToReviewHandoffProof.selectedDisplayPath=BridgeWeb/scripts/dev-server/bridge-worktree-dev-provider.ts`,
  and `substituteGuardProof.standaloneWorktreeFileAppCount=0`.
- Browser/onlook subagent `019f042b-b148-7132-891d-f1bb98b25846` passed the
  focused audit: live runtime measured the Files and Review buttons at 24px
  height and 11px font size, confirmed the `ToggleGroupItem` -> `Button`
  primitive path, confirmed the content topbar ends at the right rail boundary,
  and captured `/tmp/bridge-viewer-audit-current.png`.
- Added `BridgeWeb/AGENTS.md` so future BridgeWeb React UI work starts from the
  durable rule: use owned shadcn-style primitives, do not hand-roll route-local
  chrome, and do not use jsdom as UX checkpoint proof.

2026-06-26 expanded rail search checkpoint:

- A fresh browser/onlook subagent caught the remaining visible mismatch after
  the first compactness pass: the expanded FileViewer search input had the
  correct 24px height and 11px text, but inherited `w-full` plus horizontal
  margin, which overflowed the right rail (`right=1736` while the rail ended at
  `1728` in Vitest Browser red proof).
- Fixed the shared BridgeViewer search chrome token so the input is a compact
  rail-contained row: `h-6`, `!text-[11px]`, and
  `w-[calc(100%-1rem)]` with the existing rail margins.
- Added Vitest Browser proof for the exact regression:
  `pnpm --dir BridgeWeb exec vitest --config vitest.browser.config.ts run --project integration-browser src/file-viewer/bridge-file-viewer-app.browser.test.tsx --reporter verbose`
  first failed with `expected 1736 to be less than or equal to 1728`, then
  passed with 1 file passed, 2 tests passed.
- Combined focused browser proof passed:
  `pnpm --dir BridgeWeb exec vitest --config vitest.browser.config.ts run --project integration-browser src/file-viewer/bridge-file-viewer-app.browser.test.tsx src/app/bridge-viewer-content-header.browser.test.tsx --reporter verbose`
  with 2 files passed, 3 tests passed.
- Full BridgeWeb static gate passed:
  `pnpm --dir BridgeWeb run check`.
- Full worktree dev-server browser proof passed:
  `pnpm --dir BridgeWeb run test:dev-server:worktree`.
- Fresh proof artifact:
  `tmp/bridge-viewer-worktree-dev-server/2026-06-26T14-30-10-348Z/worktree-dev-server-proof.json`.
- Fresh proof fields:
  `productControlsProof.searchChromeProof.searchInputHeight=24`,
  `productControlsProof.searchChromeProof.searchInputFontSize=11px`,
  `productControlsProof.searchChromeProof.searchInputContainedInRail=true`,
  `productControlsProof.searchChromeProof.searchInputLeft=1397`,
  `productControlsProof.searchChromeProof.searchInputRight=1720`,
  `productControlsProof.searchChromeProof.searchRailLeft=1389`,
  `productControlsProof.searchChromeProof.searchRailRight=1728`,
  `productControlsProof.searchChromeProof.searchToggleHeight=24`,
  `productControlsProof.searchChromeProof.searchToggleFontSize=11px`,
  `productControlsProof.searchChromeProof.regexToggleHeight=24`,
  `productControlsProof.searchChromeProof.regexToggleFontSize=11px`,
  `sharedShellProof.contentHeaderHeight=36`,
  `sharedShellProof.railToolbarHeight=36`,
  `sharedShellProof.contextFileButtonHeight=24`,
  `sharedShellProof.contextReviewButtonHeight=24`,
  `sharedShellProof.railSearchButtonHeight=24`,
  `sharedShellProof.railFilterButtonHeight=24`,
  `sharedShellProof.contentHeaderBackground=rgb(24, 24, 37)`,
  and `sharedShellProof.railToolbarBackground=rgb(24, 24, 37)`.
- Remaining scout inventory that is not closed by this checkpoint:
  `BridgeWeb/src/review-viewer/shell/review-viewer-shell.tsx` still has a raw
  route-local Review projection segmented button group, and
  `BridgeWeb/src/review-viewer/code-view/bridge-code-view-panel.tsx` still has
  a raw collapse/expand chrome button. These are recorded in the active plan as
  cleanup blockers for the shared-chrome lane, not silently deferred.

2026-06-26 raw-control cleanup checkpoint:

- Replaced the Review projection mode raw segmented-control implementation in
  `BridgeWeb/src/review-viewer/shell/review-viewer-shell.tsx` with the owned
  `ToggleGroup` / `ToggleGroupItem` primitive path.
- Replaced the CodeView header collapse/expand raw button in
  `BridgeWeb/src/review-viewer/code-view/bridge-code-view-panel.tsx` with the
  owned `Button` primitive and shared BridgeViewer icon/button chrome classes.
- Added Vitest Browser proof for the Review projection control:
  `pnpm --dir BridgeWeb exec vitest --config vitest.browser.config.ts run --project integration-browser src/app/bridge-viewer-content-header.browser.test.tsx --reporter verbose`
  passed with 1 file and 2 tests. The new Review projection test asserts
  `data-slot=toggle-group`, `data-toggle-group-slot=toggle-group-item`, 24px
  segment heights, 11px computed font size, selected aria state, and click
  behavior.
- CodeView focused lower-layer proof passed:
  `pnpm --dir BridgeWeb exec vitest run src/review-viewer/code-view/bridge-code-view-panel-scroll.unit.test.tsx -t "collapse|collapsed|expand" --reporter verbose`
  with 1 file, 4 tests passed, and 22 skipped.
- Review shell focused lower-layer proof passed:
  `pnpm --dir BridgeWeb exec vitest run src/review-viewer/shell/review-viewer-shell.integration.test.tsx -t "review mode" --reporter verbose`
  with 1 file, 1 test passed, and 12 skipped.
- Full BridgeWeb static gate passed:
  `pnpm --dir BridgeWeb run check`.
- Full worktree dev-server browser proof passed:
  `pnpm --dir BridgeWeb run test:dev-server:worktree`.
- Fresh proof artifact:
  `tmp/bridge-viewer-worktree-dev-server/2026-06-26T15-04-44-655Z/worktree-dev-server-proof.json`.
- Fresh proof fields include
  `result.sharedShellProof.sharedShellOwner=BridgeViewerAppShell`,
  `result.sharedShellProof.codeOwner=CodeView.file`,
  `result.sharedShellProof.treeOwner=FileTree`,
  `result.sharedShellProof.codeViewOverflow=wrap`,
  `result.sharedShellProof.contentHeaderHeight=36`,
  `result.sharedShellProof.railToolbarHeight=36`,
  `result.sharedShellProof.contextFileButtonHeight=24`,
  `result.sharedShellProof.contextReviewButtonHeight=24`,
  `result.sharedShellProof.railSearchButtonHeight=24`,
  `result.sharedShellProof.contentTopbarStopsBeforeSidebar=true`,
  `result.reviewRouteProof.reviewSelectionProof.selectionMethod=playwright-review-tree-search-click`,
  `result.reviewRouteProof.reviewSelectionSelectedContentState=ready`, and
  `result.reviewFileTargetRouteProof.selectedContentState=ready`.
- Remaining blockers after this checkpoint:
  implementation review disposition, native Agent Studio Bridge/WKWebView proof,
  route fanout/content pressure, FileViewer preload latency/telemetry, and
  inactive-context browser/native proof if kept as gate-level.

2026-06-26 raw-control cleanup review-fix checkpoint:

- Implementation review found that the CodeView collapse/expand cleanup had
  implementation and unit proof, but the dev-server artifact did not publish
  visible browser proof that the actual selected Review CodeView header
  collapse control uses the owned shared `Button` primitive.
- Added `reviewRouteProof.reviewCollapseControlProof` to
  `BridgeWeb/scripts/verify-bridge-viewer-worktree-dev-server.ts`. The verifier
  now reads the selected CodeView header collapse button from light DOM or
  Pierre shadow DOM and records item id, `data-slot`, height, computed font
  size, and `aria-expanded`.
- Added `ReviewCollapseControlProof` and `reviewCollapseControlSatisfied` in
  `BridgeWeb/scripts/verify-bridge-viewer-worktree-review-proof.ts`.
- Added unit coverage in
  `BridgeWeb/scripts/verify-bridge-viewer-worktree-dev-server.unit.test.ts`.
- Red/green proof:
  `pnpm --dir BridgeWeb exec vitest run scripts/verify-bridge-viewer-worktree-dev-server.unit.test.ts -t "publishes visible CodeView collapse-control" --reporter verbose`
  first failed because the verifier source did not contain
  `reviewCollapseControlProof`, then passed after wiring the verifier artifact.
- Focused unit proof passed:
  `pnpm --dir BridgeWeb exec vitest run scripts/verify-bridge-viewer-worktree-dev-server.unit.test.ts --reporter verbose`
  with 1 file and 8 tests.
- Full BridgeWeb static gate passed:
  `pnpm --dir BridgeWeb run check` with existing verifier warnings only.
- Full worktree dev-server browser proof passed:
  `pnpm --dir BridgeWeb run test:dev-server:worktree`.
- Fresh proof artifact:
  `tmp/bridge-viewer-worktree-dev-server/2026-06-26T15-59-47-610Z/worktree-dev-server-proof.json`.
- Fresh proof fields:
  `result.reviewRouteProof.reviewCollapseControlProof.present=true`,
  `result.reviewRouteProof.reviewCollapseControlProof.primitiveSlot=button`,
  `result.reviewRouteProof.reviewCollapseControlProof.height=24`,
  `result.reviewRouteProof.reviewCollapseControlProof.ariaExpanded=true`,
  `result.reviewRouteProof.reviewCollapseControlProof.itemId=worktree-review-0f8a4e04bc89-sources-agentstudio-atomregistry-swift`,
  and `result.reviewRouteProof.reviewCollapseControlProof.fontSize=13px`.
  Font size is recorded as telemetry for this icon-only control; the pass/fail
  contract is owned Button primitive plus compact 24px geometry and aria state.
- Remaining blockers after this review-fix checkpoint:
  implementation review disposition, native Agent Studio Bridge/WKWebView proof,
  inactive-context browser/native proof if kept as gate-level, route
  fanout/content pressure, FileViewer preload latency/telemetry, and PR-ready
  wrapup.

2026-06-26 raw-control cleanup review-fix tightening:

- Implementation review then found two proof-quality gaps in the previous
  review-fix checkpoint:
  - the verifier could select a hidden or stale collapse-control candidate before
    the visible selected Review CodeView header control;
  - the route artifact proof needed to fail when
    `reviewRouteProof.reviewCollapseControlProof` was absent, instead of only
    source-grepping for the verifier helper.
- Added visible-candidate selection in
  `BridgeWeb/scripts/verify-bridge-viewer-worktree-dev-server.ts`. The verifier
  now gathers light DOM and Pierre shadow DOM candidates, records whether each
  candidate is visible, and selects only the visible candidate whose item id
  matches the selected Review item.
- Added artifact-level predicate helpers in
  `BridgeWeb/scripts/verify-bridge-viewer-worktree-review-proof.ts`:
  `selectVisibleReviewCollapseControlProof` and
  `reviewRouteCollapseControlArtifactSatisfied`.
- Added unit coverage in
  `BridgeWeb/scripts/verify-bridge-viewer-worktree-dev-server.unit.test.ts` for
  hidden-stale candidate rejection and missing-artifact rejection.
- Focused unit proof passed:
  `pnpm --dir BridgeWeb exec vitest run scripts/verify-bridge-viewer-worktree-dev-server.unit.test.ts --reporter verbose`
  with 1 file and 9 tests.
- Focused format proof passed:
  `pnpm --dir BridgeWeb exec oxfmt --check scripts/verify-bridge-viewer-worktree-dev-server.ts scripts/verify-bridge-viewer-worktree-dev-server.unit.test.ts scripts/verify-bridge-viewer-worktree-review-proof.ts`.
- Full BridgeWeb static gate passed:
  `pnpm --dir BridgeWeb run check` with existing verifier warnings only.
- Full worktree dev-server browser proof passed:
  `pnpm --dir BridgeWeb run test:dev-server:worktree`.
- Fresh proof artifact:
  `tmp/bridge-viewer-worktree-dev-server/2026-06-26T16-40-45-386Z/worktree-dev-server-proof.json`.
- Fresh screenshots:
  - `tmp/bridge-viewer-worktree-dev-server/2026-06-26T16-40-45-386Z/worktree-file-ready.png`
  - `tmp/bridge-viewer-worktree-dev-server/2026-06-26T16-40-45-386Z/worktree-review-ready.png`
  - `tmp/bridge-viewer-worktree-dev-server/2026-06-26T16-40-45-386Z/worktree-review-file-target-ready.png`
  - `tmp/bridge-viewer-worktree-dev-server/2026-06-26T16-40-45-386Z/worktree-file-search-result.png`
  - `tmp/bridge-viewer-worktree-dev-server/2026-06-26T16-40-45-386Z/worktree-file-stale-refresh.png`
- Fresh proof fields:
  `result.sharedShellProof.sharedShellOwner=BridgeViewerAppShell`,
  `result.sharedShellProof.codeOwner=CodeView.file`,
  `result.sharedShellProof.treeOwner=FileTree`,
  `result.sharedShellProof.workerPoolState=ready`,
  `result.reviewRouteProof.reviewSelectionProof.selectionMethod=playwright-review-tree-search-click`,
  `result.reviewRouteProof.reviewCollapseControlProof.present=true`,
  `result.reviewRouteProof.reviewCollapseControlProof.primitiveSlot=button`,
  `result.reviewRouteProof.reviewCollapseControlProof.height=24`,
  `result.reviewRouteProof.reviewCollapseControlProof.ariaExpanded=true`, and
  `result.reviewRouteProof.reviewCollapseControlProof.itemId=worktree-review-0f8a4e04bc89-sources-agentstudio-atomregistry-swift`.
- Remaining pressure signals are still open and intentionally recorded by the
  same artifact: `result.reviewRouteProof.reviewContentRouteHitCount=224` and
  `result.fileToReviewHandoffProof.reviewContentRouteHitCount=325`. These
  remain 0.a.5 scheduler/content-pressure work, not 0.b visual proof closure.
  The closure proof must include route-hit attribution, queue depth, in-flight
  count, lane upgrades/cancellations/stale drops, and admitted/deferred/dropped
  bytes by lane/source; tuning constants still require Victoria/OTel before
  production graduation.
- Remaining blockers after this tightened review-fix checkpoint:
  implementation review disposition, native Agent Studio Bridge/WKWebView proof,
  inactive-context browser/native proof if kept as gate-level, route
  fanout/content pressure, FileViewer preload latency/telemetry, and PR-ready
  wrapup.

2026-06-26 0.a.5 route-pressure proof checkpoint:

- Implemented Review route-pressure artifact wiring in
  `BridgeWeb/scripts/verify-bridge-viewer-worktree-dev-server.ts`. The
  dev-server verifier now publishes
  `result.reviewRouteProof.reviewRoutePressureProof` and fails the Review route
  proof when exact duplicate content route URLs are observed for the same
  Review route run.
- Added route-pressure predicate helpers in
  `BridgeWeb/scripts/verify-bridge-viewer-worktree-review-proof.ts`:
  `buildReviewContentRoutePressureProof`,
  `reviewRoutePressureSatisfied`, and
  `reviewVisibleDemandTelemetryAttributed`.
- Added red/green verifier coverage in
  `BridgeWeb/scripts/verify-bridge-viewer-worktree-dev-server.unit.test.ts` for
  valid visible fanout attribution and duplicate exact Review content URL
  rejection.
- Real browser proof exposed a missing zero-valued DOM telemetry field:
  `data-review-visible-demand-foreground-intent-count` was absent, so the
  verifier read `foregroundIntentCount=null` for visible demand. Added the
  missing shell attribute in
  `BridgeWeb/src/review-viewer/shell/review-viewer-shell.tsx` and regression
  coverage in
  `BridgeWeb/src/review-viewer/shell/review-viewer-shell.integration.test.tsx`.
- Focused red/green proof:
  `pnpm --dir BridgeWeb exec vitest run scripts/verify-bridge-viewer-worktree-dev-server.unit.test.ts -t "route-pressure" --reporter verbose`
  first failed because the verifier source did not contain
  `reviewRoutePressureProof`; after the verifier patch it passed with 1 file,
  2 tests passed, 14 skipped.
- Shell red/green proof:
  `pnpm --dir BridgeWeb exec vitest run src/review-viewer/shell/review-viewer-shell.integration.test.tsx -t "zero-valued visible demand" --reporter verbose`
  first failed with `expected undefined to be +0`; after the shell patch it
  passed with 1 file, 1 test passed, 13 skipped.
- Focused verifier proof passed:
  `pnpm --dir BridgeWeb exec vitest run scripts/verify-bridge-viewer-worktree-dev-server.unit.test.ts --reporter verbose`
  with 1 file and 16 tests.
- Full BridgeWeb static/type/format gate passed:
  `pnpm --dir BridgeWeb run check` with existing non-fatal verifier warnings.
- Full worktree dev-server browser proof passed:
  `pnpm --dir BridgeWeb run test:dev-server:worktree`.
- Fresh proof artifact:
  `tmp/bridge-viewer-worktree-dev-server/2026-06-26T22-19-17-976Z/worktree-dev-server-proof.json`.
- Fresh proof fields:
  `result.sharedShellProof.sharedShellOwner=BridgeViewerAppShell`,
  `result.sharedShellProof.sharedShellMode=file`,
  `result.sharedShellProof.codeOwner=CodeView.file`,
  `result.sharedShellProof.treeOwner=FileTree`,
  `result.sharedShellProof.workerPoolState=ready`,
  `result.sharedShellProof.contentTopbarStopsBeforeSidebar=true`,
  `result.reviewRouteProof.reviewRoutePressureProof.routeHitCount=19`,
  `result.reviewRouteProof.reviewRoutePressureProof.uniqueRouteHitCount=19`,
  `result.reviewRouteProof.reviewRoutePressureProof.duplicateRouteCount=0`,
  `result.reviewRouteProof.reviewSelectedDemandTelemetryProof.foregroundIntentCount=2`,
  `result.reviewRouteProof.reviewSelectedDemandTelemetryProof.loadedCount=2`,
  `result.reviewRouteProof.reviewSelectedDemandTelemetryProof.admittedBytes=26999`,
  `result.reviewRouteProof.reviewSelectedDemandTelemetryProof.executorInFlightCountAfter=0`,
  `result.reviewRouteProof.reviewVisibleDemandTelemetryProof.visibleIntentCount=2`,
  `result.reviewRouteProof.reviewVisibleDemandTelemetryProof.foregroundIntentCount=0`,
  `result.reviewRouteProof.reviewVisibleDemandTelemetryProof.deferredCount=2`,
  `result.reviewRouteProof.reviewVisibleDemandTelemetryProof.deferredEstimatedBytesByLane.visible=39779`,
  and `result.reviewRouteProof.reviewVisibleDemandTelemetryProof.maxExecutorInFlightCount=4`.
- This closes the explicit Review route-pressure attribution proof for the
  current Review route run. Remaining 0.a.5 work still includes FileViewer
  preload/latency telemetry closure and deciding whether to apply a separate
  duplicate-pressure predicate to File-to-Review handoff or Review file-target
  routes, because their route patterns intentionally include broader visible
  fanout and need their own contract rather than reusing the exact Review route
  predicate blindly.

2026-06-26 0.a.5 FileViewer visible-preload pressure checkpoint:

- Implemented FileViewer visible demand telemetry as a first-class dev-server
  proof row in `BridgeWeb/scripts/verify-bridge-viewer-worktree-dev-server.ts`.
  The verifier now reads and gates visible preload lane/disposition, failed
  counts by lane/reason, and post-dispatch queue/executor drain state.
- Added proof predicate and explicit pressure-accounting contract in
  `BridgeWeb/scripts/verify-bridge-viewer-worktree-review-proof.ts`.
  `worktreeFileVisibleDemandTelemetrySatisfied` accepts bounded visible-lane
  pressure only when failures are attributed by lane and reason and both the
  scheduler and executor drain to zero.
- Added red/green verifier coverage in
  `BridgeWeb/scripts/verify-bridge-viewer-worktree-dev-server.unit.test.ts`.
  The focused test first failed because the verifier source did not contain
  `fileViewerVisibleDemandTelemetry`; after the verifier/runtime patch it
  passed. A later dev-server run exposed aggregate-only failures, so the test
  was tightened to reject `failedCount > 0` without `failedCountByLane` and
  `failedCountByReason`.
- Added DOM publication in
  `BridgeWeb/src/file-viewer/bridge-file-viewer-app.tsx` for visible demand
  failure buckets and drained queue/executor counters.
- Focused verifier proof passed:
  `pnpm --dir BridgeWeb exec vitest run scripts/verify-bridge-viewer-worktree-dev-server.unit.test.ts -t "FileViewer visible preload" --reporter verbose`
  with 1 file, 1 test passed, 16 skipped.
- Full verifier proof passed:
  `pnpm --dir BridgeWeb exec vitest run scripts/verify-bridge-viewer-worktree-dev-server.unit.test.ts --reporter verbose`
  with 1 file, 17 tests passed.
- FileViewer browser proof passed:
  `pnpm --dir BridgeWeb exec vitest --config vitest.browser.config.ts run --project integration-browser src/file-viewer/bridge-file-viewer-app.browser.test.tsx --reporter verbose`
  with 1 file, 5 tests passed.
- Worktree file surface runtime proof passed:
  `pnpm --dir BridgeWeb exec vitest run src/worktree-file-surface/worktree-file-surface-runtime.integration.test.ts --reporter verbose`
  with 1 file, 16 tests passed.
- Full BridgeWeb static/type/format gate passed:
  `pnpm --dir BridgeWeb run check` with existing non-fatal verifier warnings.
- Full worktree dev-server browser proof passed:
  `pnpm --dir BridgeWeb run test:dev-server:worktree`.
- Fresh proof artifact:
  `tmp/bridge-viewer-worktree-dev-server/2026-06-26T22-55-15-002Z/worktree-dev-server-proof.json`.
- Fresh proof fields:
  `result.fileViewerVisibleDemandTelemetry.status=settled`,
  `result.fileViewerVisibleDemandTelemetry.stimulusCount=1`,
  `result.fileViewerVisibleDemandTelemetry.intentCount=50`,
  `result.fileViewerVisibleDemandTelemetry.loadedCount=2`,
  `result.fileViewerVisibleDemandTelemetry.failedCount=48`,
  `result.fileViewerVisibleDemandTelemetry.failedCountByLane.visible=48`,
  `result.fileViewerVisibleDemandTelemetry.failedCountByReason.concurrency_exceeded=48`,
  `result.fileViewerVisibleDemandTelemetry.firstLane=visible`,
  `result.fileViewerVisibleDemandTelemetry.firstDisposition=visible-preloaded`,
  `result.fileViewerVisibleDemandTelemetry.schedulerQueuedIntentCountAfter=0`,
  `result.fileViewerVisibleDemandTelemetry.schedulerQueuedEstimatedBytesAfter=0`,
  `result.fileViewerVisibleDemandTelemetry.executorInFlightCountAfter=0`,
  `result.fileViewerVisibleDemandTelemetry.executorInFlightBytesAfter=0`,
  `result.fileViewerVisibleDemandTelemetry.executorQueuedLoadCountAfter=0`,
  and `result.fileViewerVisibleDemandTelemetry.executorQueuedBytesAfter=0`.
- This closes the explicit FileViewer visible-preload pressure-accounting proof
  for 0.a.5. Remaining 0.a.5 work still includes click-to-ready latency if kept
  as a separate gate, separately scoped pressure contracts for File-to-Review
  handoff or Review file-target routes, native Agent Studio Bridge/WKWebView
  proof, implementation review disposition, and PR-ready wrapup.

2026-06-26 FileViewer click-to-ready/provenance checkpoint:

- Runtime provenance fix: when a file body was warmed by visible preload and the
  user later opens that file through the foreground path, the open telemetry now
  preserves the warm source as `visible-preloaded` instead of collapsing it to a
  generic `cache-hit`.
- Focused runtime red/green proof passed:
  `pnpm --dir BridgeWeb exec vitest run src/worktree-file-surface/worktree-file-surface-runtime.integration.test.ts -t "visible preload provenance" --reporter verbose`
  with 1 file, 1 test passed, 16 skipped.
- Full runtime integration proof passed:
  `pnpm --dir BridgeWeb exec vitest run src/worktree-file-surface/worktree-file-surface-runtime.integration.test.ts --reporter verbose`
  with 1 file, 17 tests passed.
- Verifier contract now publishes and gates
  `result.fileViewerClickToReadyTelemetry`.
- Focused verifier red/green proof passed:
  `pnpm --dir BridgeWeb exec vitest run scripts/verify-bridge-viewer-worktree-dev-server.unit.test.ts -t "click-to-ready" --reporter verbose`
  with 1 file, 1 test passed, 17 skipped.
- Full verifier proof passed:
  `pnpm --dir BridgeWeb exec vitest run scripts/verify-bridge-viewer-worktree-dev-server.unit.test.ts --reporter verbose`
  with 1 file, 18 tests passed.
- FileViewer browser proof passed:
  `pnpm --dir BridgeWeb exec vitest --config vitest.browser.config.ts run --project integration-browser src/file-viewer/bridge-file-viewer-app.browser.test.tsx --reporter verbose`
  with 1 file, 5 tests passed.
- Full BridgeWeb static/type/format gate passed:
  `pnpm --dir BridgeWeb run check` with existing non-fatal verifier warnings.
- Full worktree dev-server browser proof passed:
  `pnpm --dir BridgeWeb run test:dev-server:worktree`.
- Fresh proof artifact:
  `tmp/bridge-viewer-worktree-dev-server/2026-06-26T23-22-58-771Z/worktree-dev-server-proof.json`.
- Fresh proof fields:
  `result.fileViewerClickToReadyTelemetry.disposition=cold-loaded`,
  `result.fileViewerClickToReadyTelemetry.durationMilliseconds=265.2000000476837`,
  `result.fileViewerClickToReadyTelemetry.estimatedBytes=217243`,
  `result.fileViewerClickToReadyTelemetry.lane=foreground`,
  `result.fileViewerClickToReadyTelemetry.schedulerQueuedIntentCountAfter=0`,
  `result.fileViewerClickToReadyTelemetry.schedulerQueuedEstimatedBytesAfter=0`,
  `result.fileViewerClickToReadyTelemetry.executorInFlightCountAfter=0`,
  `result.fileViewerClickToReadyTelemetry.executorInFlightBytesAfter=0`,
  `result.fileViewerClickToReadyTelemetry.executorQueuedLoadCountAfter=0`,
  and `result.fileViewerClickToReadyTelemetry.executorQueuedBytesAfter=0`.
- The real dev-server clicked target was cold-loaded; warmed-click provenance is
  covered by the focused runtime test. This closes the 0.a.5 top-level
  click-to-ready telemetry publication/provenance slice. Remaining 0.a.5 work
  still includes nearby/speculative/recently-updated preload lanes if kept,
  separately scoped pressure contracts for File-to-Review handoff or Review
  file-target routes if kept, native Agent Studio Bridge/WKWebView proof,
  implementation review disposition, and PR-ready wrapup.

2026-06-26 recently-updated demand protocol checkpoint:

- Added the `recentlyUpdatedFile` Worktree/File demand stimulus to the Zod
  protocol schema with explicit `proximity: 'nearby' | 'remote'` and
  `sourceIdentity`.
- Demand policy maps `recentlyUpdatedFile` with `proximity='nearby'` to the
  `nearby` lane and `proximity='remote'` to the `speculative` lane. It does not
  create foreground demand for debounced file updates.
- Runtime integration proves recently-updated stimuli enqueue descriptor-backed
  nearby/speculative preloads, fetch through the scheduler/executor, drain
  queues, and do not create open file sessions.
- Updated durable and tmp spec snippets:
  `docs/specs/bridge-viewer-transport/spec.md`,
  `docs/specs/bridge-viewer-transport/worktree-file-surface-protocol.md`,
  `tmp/spec-workflows/2026-06-22-bridge-transport-streaming-spec/spec.md`,
  and
  `tmp/spec-workflows/2026-06-22-bridge-transport-streaming-spec/worktree-file-surface-protocol.md`.
- Focused red/green proof passed:
  `pnpm --dir BridgeWeb exec vitest run src/features/worktree-file/demand/worktree-file-demand-policy.unit.test.ts -t "recently updated" --reporter verbose`
  initially failed on the unhandled demand-policy case, then passed with 1 file,
  1 test passed, 4 skipped.
- Focused red/green proof passed:
  `pnpm --dir BridgeWeb exec vitest run src/features/worktree-file/models/worktree-file-protocol-models.unit.test.ts -t "loose demand stimuli" --reporter verbose`
  initially failed because the schema rejected `recentlyUpdatedFile`, then
  passed with 1 file, 1 test passed, 3 skipped.
- Focused runtime integration proof passed:
  `pnpm --dir BridgeWeb exec vitest run src/worktree-file-surface/worktree-file-surface-runtime.integration.test.ts -t "recently updated files" --reporter verbose`
  with 1 file, 1 test passed, 17 skipped.
- Full policy/model/runtime proof passed:
  `pnpm --dir BridgeWeb exec vitest run src/features/worktree-file/demand/worktree-file-demand-policy.unit.test.ts --reporter verbose`
  with 1 file, 5 tests passed;
  `pnpm --dir BridgeWeb exec vitest run src/features/worktree-file/models/worktree-file-protocol-models.unit.test.ts --reporter verbose`
  with 1 file, 4 tests passed; and
  `pnpm --dir BridgeWeb exec vitest run src/worktree-file-surface/worktree-file-surface-runtime.integration.test.ts --reporter verbose`
  with 1 file, 18 tests passed.
- Full BridgeWeb static/type/format gate passed:
  `pnpm --dir BridgeWeb run check` with existing non-fatal verifier warnings.
- This closes the protocol/policy/runtime portion of the recently-updated-file
  preload lane. It does not yet close the browser/dev-server injected-event proof
  row that must emit or inject a recently-updated-file event and record the
  resulting lane, dedupe key, queue admission/drop, byte-budget disposition, and
  stale-drop behavior.
