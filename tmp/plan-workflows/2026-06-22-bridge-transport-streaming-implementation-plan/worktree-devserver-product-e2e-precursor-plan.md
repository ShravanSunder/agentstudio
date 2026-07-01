# Worktree Dev-Server Product E2E Precursor Plan

Date: 2026-06-24
Status: Gate 0.a reopened; 2026-06-27 takeover supersedes the old
dev-server-only precursor boundary. The active blocker is now streaming-resource
realignment plus native/debug-app proof: the shared BridgeViewer route set must
stay product-correct, and the implementation must also obey the transport spec's
separation between metadata/event/intake paths and content/resource streams.
Ticket: 06P / Gate 0.a Shared BridgeViewer Navigation And Renderer Precursor

## Current Proof Status

Gate 0.a is not closed. Earlier proof artifacts and reviewer fixes are useful
history, but the live product contract is stronger than "make WorktreeFileApp
product-like." The current checkpoint stack is:

- `47933c48` proves direct current-worktree Review file-target routing in the
  shared Review shell.
- `6ce7ef9d` proves Files context can hand off a selected worktree file to
  Review context inside the same BridgeViewer app root.
- `85b1faa0` proves the shared context toggle and per-context memory at the
  dev-server verifier layer:
  `BridgeApp` owns one `BridgeViewerAppShell`, FileViewer and ReviewViewer are
  mounted as mode bodies, and a Files-to-Review-to-Files-to-Review round trip
  preserves the selected file/review target.
- `85e98cd6` proves the corrected shared content chrome:
  FileViewer and ReviewViewer use one shared content header, title form
  `source / selected target`, content-only topbar, right rail top-aligned outside
  the header, Pierre FileTree, Pierre CodeView/File, Shiki/Pierre worker path,
  and zero standalone `WorktreeFileApp` roots.
- Fresh proof command:
  `pnpm --dir BridgeWeb run test:dev-server:worktree`
- Fresh proof artifact:
  `tmp/bridge-viewer-worktree-dev-server/2026-06-26T14-30-10-348Z/worktree-dev-server-proof.json`
- Screenshot artifacts:
  - `tmp/bridge-viewer-worktree-dev-server/2026-06-26T14-30-10-348Z/worktree-file-ready.png`
  - `tmp/bridge-viewer-worktree-dev-server/2026-06-26T14-30-10-348Z/worktree-file-search-result.png`
  - `tmp/bridge-viewer-worktree-dev-server/2026-06-26T14-30-10-348Z/worktree-file-stale-refresh.png`
  - `tmp/bridge-viewer-worktree-dev-server/2026-06-26T14-30-10-348Z/worktree-review-ready.png`
  - `tmp/bridge-viewer-worktree-dev-server/2026-06-26T14-30-10-348Z/worktree-review-file-target-ready.png`
- Critical artifact rows:
  `sharedShellProof.contentTitleText = dev-worktree-source / BridgeWeb/pnpm-lock.yaml`,
  `sharedShellProof.contentTopbarStopsBeforeSidebar = true`,
  `sharedShellProof.sidebarStartsAtContentTopbar = true`,
  `sharedShellProof.contextSwitcherInsideContentTopbar = true`,
  `sharedShellProof.workerPoolState = ready`,
  `sharedShellProof.codeOwner = CodeView.file`,
  `sharedShellProof.treeOwner = FileTree`, and
  `fileToReviewHandoffProof.standaloneWorktreeFileAppCount = 0`.
- Real-click rows:
  FileViewer -> Review handoff uses `.gitignore` as the FileViewer tree target
  and proves `selectedMaterializedItemType=file`, `sharedShellMode=review`,
  Files -> Review -> Files -> Review memory, and no standalone app root.
  Review tree search uses `Sources/AgentStudio/AtomRegistry.swift` and proves
  `reviewSelectionProof.selectionMethod=playwright-review-tree-search-click`,
  `searchInputValue=sources/agentstudio/atomregistry.swift`,
  `clickedRowItemPath=Sources/AgentStudio/AtomRegistry.swift`,
  `clickedRowItemType=file`, and `clickedRowVisible=true`.
  Review file-target routing uses the same AtomRegistry path with
  `presentation=file&version=current` and proves the Review-owned
  Pierre/Shiki file rendering path.
- DiffsHub/Pierre chrome rows:
  content header and right rail use `#181825`; code canvas remains `#1E1E2E`;
  shared FileViewer/ReviewViewer controls use compact `h-6`/`w-6` sizing,
  `#313244` hover, `#B4BEFE` focus, and the same active-fill token. This is the
  neutral shared-chrome correction for the current checkpoint; exact
  performance tuning and route-fanout pressure remain 0.a.5 proof rows.
- Expanded FileViewer search proof rows:
  `productControlsProof.searchChromeProof.searchInputHeight = 24`,
  `searchInputFontSize = 11px`, `searchToggleHeight = 24`,
  `searchToggleFontSize = 11px`, `regexToggleHeight = 24`, and
  `regexToggleFontSize = 11px`. The screenshot-driven regression where the
  opened search field looked like a larger form field is now covered by both
  Vitest Browser and the dev-server verifier.
- Expanded search containment rows:
  `searchInputContainedInRail = true`, `searchInputLeft = 1397`,
  `searchInputRight = 1720`, `searchRailLeft = 1389`, and
  `searchRailRight = 1728`. This closes the onlook-caught overflow where
  `w-full` plus horizontal margin put the search field beyond the rail edge.

2026-06-27 orchestrator takeover correction:

- 2026-07-01 goal reset correction:
  file data includes metadata. Production Swift/native owns authoritative
  Worktree/File and worktree-backed Review metadata production: file-tree rows,
  paths, names, parent/depth, status/change facts, size/line/extent facts,
  descriptor refs, invalidations, resets, and deltas. BridgeWeb consumes and
  applies that metadata; it sends compact metadata-interest updates and
  schedules content demand, but it does not discover or synthesize the native
  file tree. Vite/dev-server must mimic this same stream contract for fast
  proof only.
- The metadata stream is persistent for the accepted source. Demand lanes for
  metadata are browser-to-provider interest signals that reprioritize Swift
  metadata production on that stream: selected/open target and ancestors are
  `foreground`, visible tree/review ranges are `visible`, adjacent/lookahead
  ranges are `nearby`, predictions are `speculative`, and remaining manifest
  completion is `idle` with no-starvation. Metadata needed for visible/selected
  UI must not wait behind idle manifest crawling or content warming.
- Performance targets are requirements. The implementation must produce
  Victoria/OTel-backed p95/p99 metrics for page load, file click,
  tree-scroll-to-visible-rows, review click, review tree scroll,
  metadata-interest-to-frame, metadata apply, content fetch, queue wait by lane,
  stale drops, aborts, and idle/no-starvation progress. File click p95 must be
  under 100ms and p99 under 200ms for normal text/source files. File tree and
  review tree scroll must report p95/p99 and must have zero blank windows and
  zero wrong visible rows.
- This branch is no longer allowed to continue from the old assumption that a
  resource URL plus later `fetch().text()`/whole-body promise is sufficient.
  `agentstudio://resource/...` identifies a leased `ContentStreamPath` resource
  or stream descriptor. The content/resource path must be stream-capable and
  bounded; it may use whole-body integrity at completion for authoritative
  first-slice validation, but transfer and materialization must not be shaped as
  RPC/event/intake/store blob delivery.
- Continuous event streams carry compact lifecycle/provider facts:
  readiness, heartbeat, source status, descriptor availability, invalidation,
  gap/reset/close, stream ids, cursors, and source identity. They do not carry
  file bodies, diff bodies, package bodies, or other body payloads.
- Intake streams carry ordered app projection and metadata frames:
  Review snapshots/deltas/invalidation/reset and Worktree/File snapshots,
  tree-window rows, tree deltas, status patches, file descriptors, and rich reset
  details. Tree/review/file metadata stays here as structured frames; it is not
  hidden behind descriptor-backed body resources before the tree/projection can
  render.
- Content/resource streams carry only body/range bytes through
  `ContentStreamPath`: file text, diff text, markdown source, and bounded body
  chunks/windows. They do not carry authoritative tree manifests, review package
  startup metadata, or semantic delta operation lists.
- The written spec currently keeps first authoritative integrity at whole-body
  hash validation when an integrity hash is issued, while ranged/chunked reads
  are preview-only until chunk manifests exist. This is not permission to
  implement blob-shaped transfer. If authoritative partial range/chunk reads are
  required for this slice, update the spec and plan first to promote chunk
  manifests/ranged integrity.
- First-slice progressive materialization is allowed only as provisional state:
  chunks/windows may update visible renderer deltas while a whole-body resource
  is still streaming, but final cache/render/review authority requires successful
  whole-hash validation when integrity is issued. On abort, stale completion,
  truncation, or hash mismatch, provisional materialization must be dropped or
  marked failed for that descriptor epoch.
- Current residual 06P.S drift that this plan must address before further UX
  polish:
  `BridgeWeb/src/core/demand/bridge-resource-executor.ts` still resolves a
  whole-result promise above the fetch boundary; FileViewer/Worktree and Review
  materializers still collapse resources into strings before useful progressive
  rendering; non-authoritative preview bytes still need explicit state gating so
  they cannot satisfy final ready markers; Swift Review `content` resources
  still load whole `Data` before chunk emission; native Review load still builds
  a whole package through `reviewPipeline.loadPackage(...)` before useful
  lifecycle/projection frames can reach the browser; Review startup identity is
  still requester-minted instead of provider-issued; and `review-package` /
  `review-delta` resources exist but their body facts/serving are still
  startup-serialization shaped rather than producer-backed.
  Superseded drift: Worktree/File native file content now has source-backed
  chunk emission with descriptor/body drift negatives; dev Review metadata no
  longer pushes `data.package`; `review-package` / `review-delta` are no longer
  merely decorative descriptors; and explicit IPC body/package DTO transport has
  focused Swift coverage as removed/metadata-only.
- Native proof must use the debug app identity `oq4s` and Agent Studio IPC /
  WKWebView. The stable `/Applications/AgentStudio.app`, mocked backends,
  jsdom, and Vite/dev-server proof cannot satisfy native proof. Current native
  Review package acquisition fails with
  `loadFailed:package:providerFailed:git.treeFilesystemFallback:failed:status=fileReadFailed:tree=fileReadFailed`
  in artifact
  `tmp/bridge-viewer-native-ipc-proof/2026-06-27T10-37-24Z-oq4s-fresh/`.
- Subagents should be used for bounded spec/code/browser/native evidence lanes
  where practical. The parent controller still owns integration, proof mapping,
  and completion claims.

## 2026-07-01 Native Metadata Stream Cutover Plan

### Goal

Hard-cut FileView and worktree-backed Review to a native-owned, persistent,
lane-aware metadata stream. Vite remains a fast adapter proving the same
contract; it must not define file-tree metadata production.

### Non-goals

- Do not make BridgeWeb scan the filesystem or authoritatively build the native
  file tree.
- Do not move metadata into descriptor-backed blobs to avoid designing stream
  priority.
- Do not let content preloading or body fetches block selected/visible metadata.
- Do not keep old package/blob-first Review startup as compatibility.

### Vertical Slices

1. Metadata interest contract
   - Behavior: BridgeWeb reports selected/open path, visible range, expanded
     subtree, adjacent/lookahead range, prediction, and idle-manifest interest
     with lane priority against an accepted source.
   - Swift owns: validating interest against the accepted source and using it
     only to prioritize provider-produced metadata frames.
   - BridgeWeb owns: deriving interest from Pierre tree viewport, selection,
     expansion, search/hover, and context state.
   - Proof: strict Swift/TypeScript contract fixtures, rejected stale/cross-pane
     interest, and a unit proof that JS interest does not carry metadata bodies.

2. Swift metadata producer scheduler
   - Behavior: the native provider emits metadata frames on the persistent
     stream using lane order: foreground, visible, nearby, speculative, idle.
     Idle manifest completion gets a no-starvation budget.
   - Swift owns: filesystem/git truth, ignore policy, source generation/cursor,
     row/range/delta production, and cancellation on reset.
   - Proof: Swift provider tests for selected-path foreground before idle
     continuation, visible range before idle continuation, idle no-starvation,
     and stale-generation drop.

3. BridgeWeb application state split
   - Behavior: metadata loading and content loading are separate typed states.
     The tree keeps last-good rows while newer metadata is active. Content keeps
     last-good/provisional state independently.
   - BridgeWeb owns: applying metadata frames, preserving shell/tree/code panel
     composition, and emitting metadata interest without remounting the app
     frame.
   - Proof: Vitest Browser/React tests for no blank tree during active metadata,
     no content blanking due to metadata continuation, and no shell/header
     remount on FileView/Review context switches.
   - Mount rule: metadata stream controllers, materializers, demand-lane state,
     and lightweight stores mount outside lazy/Suspense visual shells, so source
     subscription, metadata intake, last-good state, and per-context memory
     survive visual chunk loading.

4. Content demand isolation
   - Behavior: selected/visible content streams use content lanes and executor
     pressure, but content warming cannot starve selected/visible metadata.
   - Swift owns: leased content resources and chunk emission.
   - BridgeWeb owns: scheduler/executor pressure and stale completion drops for
     bodies.
   - Proof: demand-pressure test where idle/speculative content is active while
     visible metadata interest still reaches frame application within budget.

5. Native performance and observability proof
   - Behavior: marker-scoped native proof reports metadata latency separately
     from content latency.
   - Required metrics: metadata interest-to-frame, metadata frame apply,
     content fetch, click-to-first-visible-content, scroll-to-visible-rows,
     queue wait by lane, stale drops, aborts, and no-starvation idle progress.
   - Proof: Victoria-backed debug app runs for FileView and Review with p95/p99
     reports and screenshots/interaction artifacts.

### Execution DAG

```text
gate 0: re-anchor spec/plan and current code evidence
  |
  +-- slice 1: metadata interest contract
  |
  +-- slice 2: Swift metadata producer scheduler
  |
  +-- slice 3: BridgeWeb state split and interest emission
  |
integration gate: Swift frames + BridgeWeb interest/apply interop
  |
slice 4: content demand isolation under pressure
  |
slice 5: native performance/observability proof
  |
implementation-review-swarm
```

### Requirements / Proof Matrix

| Requirement | Source | Owning slice | Proof layer | Evidence |
| --- | --- | --- | --- | --- |
| Swift owns file-tree metadata production | `spec.md` R15, `worktree-file-surface-protocol.md` Ownership | 1, 2 | Swift unit/integration, TS contract | no JS metadata body/discovery path; provider emits rows |
| Metadata stream is persistent and lane-aware | `spec.md` R16 | 1, 2, 3 | Swift integration, browser integration | interest updates reorder next frames on same stream |
| Selected/visible metadata beats idle manifest/content warming | `spec.md` R16/R17 | 2, 4 | Swift integration, browser pressure, native smoke | foreground/visible interest-to-frame p95/p99 |
| UI never blanks because metadata is active | Worktree/File proof expectations | 3 | Vitest Browser, native WKWebView | last-good tree/content retained during newer work |
| Content streams remain body/range only | `spec.md` R17 | 4 | contract/unit/security | content resources do not carry authoritative tree manifest |
| Native proof uses same contract as Vite | `performance-demand-lanes.md` | 5 | native smoke/e2e/Victoria | same metric names and scenario shape |
| File click meets latency target | `performance-demand-lanes.md` | 3, 4, 5 | browser/native performance | normal text/source p95 <100ms, p99 <200ms |
| Tree scroll is stable and measured | `performance-demand-lanes.md` | 2, 3, 5 | browser/native performance | p95/p99 reported, blank window count 0, wrong visible row count 0 |
| Vite page load records startup latency | `performance-demand-lanes.md` page-load-current-worktree | 3, 5 | browser performance | non-exploratory artifact with run marker, runtime, worker mode, commit SHA |
| Vite file click has enough samples | `performance-demand-lanes.md` file-click-random-100 | 3, 4, 5 | browser performance | >=100 samples, p95/p99, lane queue wait, content latency separated from metadata |
| Vite tree scroll has enough samples | `performance-demand-lanes.md` tree-scroll-sampled-100 | 2, 3, 5 | browser performance | >=100 samples, p95/p99, blank windows 0, wrong visible rows 0 |
| Review click and tree scroll are measured separately | `performance-demand-lanes.md` review-click-random-100 and review-tree-scroll-sampled-100 | 2, 3, 4, 5 | browser/native performance | separate Review scenario rows and p95/p99; no FileView-only substitution |
| Demand pressure proves no starvation | `performance-demand-lanes.md` demand-pressure-no-starvation | 2, 4, 5 | browser/native performance | selected/visible metadata interest-to-frame under pressure; idle manifest progress recorded |
| Native WKWebView emits same metric names | `performance-demand-lanes.md` native parity scenarios | 5 | native smoke/e2e/Victoria | native page-load/file-click/tree-scroll and trace-stitching visible in Victoria |

Exploratory fast-loop runs with fewer than 100 click or scroll samples may guide
debugging, but they must be labeled exploratory and cannot satisfy the
performance gate.

### Split / Replan Triggers

- If Swift cannot prioritize metadata production from compact interest without
  a new protocol method, split a dedicated `metadataInterest` RPC/control slice
  before touching UI rendering.
- If Pierre tree viewport APIs cannot provide stable visible ranges, split a
  UI adapter proof slice before changing native scheduling.
- If native performance proof lacks metadata/content separated metrics, split
  instrumentation before tuning constants.

Closed visual/chrome cleanup inventory from the 2026-06-26 scout pass:

- `BridgeWeb/src/review-viewer/shell/review-viewer-shell.tsx` now renders the
  Review projection mode control through the owned `ToggleGroup` /
  `ToggleGroupItem` -> `Button` primitive path instead of raw route-local
  segmented buttons. Vitest Browser proof asserts `data-slot=toggle-group`,
  `data-toggle-group-slot=toggle-group-item`, 24px segment height, and 11px
  font size.
- `BridgeWeb/src/review-viewer/code-view/bridge-code-view-panel.tsx` now renders
  the collapse/expand header control through the owned `Button` primitive and
  shared BridgeViewer chrome icon/button classes while preserving aria labels,
  expanded state, item id data, test id, and click propagation behavior.
- Existing jsdom/unit tests may remain as lower-layer state guards only. They do
  not satisfy visible UX proof. Future visible checkpoint records must cite
  Vitest Browser, Playwright/dev-server, or native WKWebView evidence.

2026-06-26 raw-control cleanup proof:

- `pnpm --dir BridgeWeb exec vitest --config vitest.browser.config.ts run --project integration-browser src/app/bridge-viewer-content-header.browser.test.tsx --reporter verbose`
  passed with 1 file and 2 tests. The second test covers the Review projection
  mode control through the owned compact toggle-group primitive.
- `pnpm --dir BridgeWeb exec vitest run src/review-viewer/code-view/bridge-code-view-panel-scroll.unit.test.tsx -t "collapse|collapsed|expand" --reporter verbose`
  passed with 1 file, 4 tests passed, and 22 skipped.
- `pnpm --dir BridgeWeb exec vitest run src/review-viewer/shell/review-viewer-shell.integration.test.tsx -t "review mode" --reporter verbose`
  passed with 1 file, 1 test passed, and 12 skipped.
- `pnpm --dir BridgeWeb run check` passed with existing warnings only.
- `pnpm --dir BridgeWeb run test:dev-server:worktree` passed with full
  browser/dev-server proof. Fresh artifact:
  `tmp/bridge-viewer-worktree-dev-server/2026-06-26T15-04-44-655Z/worktree-dev-server-proof.json`.
- Fresh proof fields include `sharedShellProof.sharedShellOwner =
  BridgeViewerAppShell`, `codeOwner = CodeView.file`, `treeOwner = FileTree`,
  `codeViewOverflow = wrap`, content/rail headers at 36px, context buttons and
  rail buttons at 24px, `contentTopbarStopsBeforeSidebar = true`, Review tree
  selection by `playwright-review-tree-search-click`, and Review file-target
  route ready for `Sources/AgentStudio/AtomRegistry.swift`.

2026-06-26 raw-control cleanup review-fix proof:

- Implementation review found that the CodeView collapse/expand cleanup had
  only lower-layer unit proof and the dev-server artifact did not publish a
  visible primitive/style proof row for the actual selected Review CodeView
  header control.
- Added `reviewRouteProof.reviewCollapseControlProof` to the worktree
  dev-server verifier. The proof reads the visible selected CodeView header
  collapse button from light DOM or Pierre shadow DOM and records item id,
  `data-slot`, height, computed font size, and `aria-expanded`.
- Added lower-layer proof predicates in
  `BridgeWeb/scripts/verify-bridge-viewer-worktree-review-proof.ts` and unit
  coverage in
  `BridgeWeb/scripts/verify-bridge-viewer-worktree-dev-server.unit.test.ts`.
- Red/green proof:
  `pnpm --dir BridgeWeb exec vitest run scripts/verify-bridge-viewer-worktree-dev-server.unit.test.ts -t "publishes visible CodeView collapse-control" --reporter verbose`
  first failed because the verifier source did not publish
  `reviewCollapseControlProof`, then passed after the verifier wiring.
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
  `primitiveSlot=button`, `height=24`, `ariaExpanded=true`,
  `itemId=worktree-review-0f8a4e04bc89-sources-agentstudio-atomregistry-swift`,
  and `fontSize=13px`. Font size is recorded as telemetry for this icon-only
  control; the pass/fail contract is owned Button primitive plus compact 24px
  geometry and aria state.

2026-06-26 raw-control cleanup review-fix tightening:

- Implementation review then found two proof-quality gaps in the previous
  review-fix checkpoint:
  - the verifier could select a hidden or stale collapse-control candidate before
    the visible selected Review CodeView header control;
  - the route artifact proof needed to fail when
    `reviewRouteProof.reviewCollapseControlProof` was absent, instead of only
    source-grepping for the verifier helper.
- Added visible-candidate selection in
  `BridgeWeb/scripts/verify-bridge-viewer-worktree-dev-server.ts`: the verifier
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

The remaining blocking outcome is now:

```text
remove or bypass the second app path and prove FileViewer uses the shared
BridgeViewer shell with Pierre FileTree + Pierre CodeView/File + Shiki workers
and prove shared context navigation/memory, DiffsHub-like top chrome/search UX,
responsive file-load behavior, and native Agent Studio Bridge proof
```

New checkpoint rule from the 2026-06-25 UX review:

- UX behavior must be proved at every implementation checkpoint that changes
  visible app behavior.
- jsdom is not an accepted UX proof layer for this project unless explicitly
  requested by the user for a narrow lower-level state guard.
- New UX proof must use Vitest Browser, Playwright/dev-server, or native
  Agent Studio/WKWebView proof as appropriate.
- Each UX checkpoint must include screenshot or video artifacts plus a
  second-agent browser/code onlook that compares the visible surface against
  the intended product contract. The onlook must inspect both screenshots and
  relevant source paths before the checkpoint is accepted.
- A checkpoint is not accepted if it proves only DOM attributes, JSON output,
  route state, or jsdom behavior while the visible UX is broken.
- Before implementing visible chrome changes, capture or inspect the current
  FileViewer, ReviewViewer, and DiffsHub/Pierre screenshots/source and draw the
  intended shared shell state in the plan or proof packet. The design target is
  a gate input, not something inferred from a passing DOM test.

Shared shell design target for Gate 0.a, accepted as decision C:

```text
BridgeViewerAppShell
  ┌──────────────────────────────────────────────────────────────┬─────────────┐
  │ content header only for the left content region              │ right rail  │
  │   title: <source> / <selected target>                         │ Review-     │
  │   compact controls: Files | Review and content actions        │ styled      │
  ├──────────────────────────────────────────────────────────────┤ Pierre      │
  │ primary Pierre CodeView/File canvas                          │             │
  │   Review diff target  -> Pierre diff items                   │ selection   │
  │   Review file target  -> Pierre/Shiki file item              │ status      │
  │   Files file target   -> Pierre/Shiki file item              │ expansion   │
  └──────────────────────────────────────────────────────────────┴─────────────┘
```

The content header is left-content-only. It must not cover the right rail and
must not push the right rail down. The title uses the accepted
`source / selected target` form, and FileViewer/ReviewViewer controls must share
the ReviewViewer/DiffsHub-like compact primitive sizing. ReviewViewer's right
rail is the styling baseline for FileViewer's right rail: only functionality may
differ.

The accepted header placement is:

```text
viewer width
┌──────────────────────────────────────────────────────────────┬─────────────┐
│ content header                                               │ right rail  │
│  left: source / target                                       │ y starts 0  │
│  right: Files | Review plus content actions                  │ own toolbar │
├──────────────────────────────────────────────────────────────┤             │
│ Pierre CodeView/File canvas                                  │ Pierre tree │
└──────────────────────────────────────────────────────────────┴─────────────┘
```

Accepted decision C uses "top right" to mean the right slot of the left content
header, not the top right of the full viewport. The switcher belongs beside
content actions in that slot. It must not be centered, detached into a separate
strip, or placed over/in the right rail. The title/source belongs in the left
slot. The right rail starts at y=0 and owns its own toolbar.

Current unresolved visual parity rows from the 2026-06-26 screenshot review:

- BridgeWeb reusable React controls must be built from owned shadcn-style
  primitives in `BridgeWeb/src/components/ui/`. DeepWiki-backed shadcn guidance
  identifies `ToggleGroup` as the proper primitive family for compact option
  sets such as `Files | Review`; use that primitive unless source inspection
  finds an equivalent owned shadcn primitive already in the repo. The current
  custom `Files | Review` switcher is not accepted as the final primitive. Add
  the missing shadcn-style primitive source, customize it for Agent Studio
  tokens, then compose it through a neutral BridgeViewer wrapper;
- content header height must equal right-rail toolbar height in Files, Review
  diff, and Review file-target routes;
- top-bar icon buttons and right-rail icon buttons must use one compact visual
  box size, icon size, focus ring, selected fill, hover fill, and border radius;
- the `Files | Review` segmented toggle must match the adjacent button height
  and selected-fill rhythm instead of looking like a larger independent widget;
- content header and right-rail toolbar must share the same darker chrome color,
  bottom border, vertical padding, and top-edge alignment;
- the header title/provenance text must be defined and compact: `mode source /
  selected target`, one line, truncated inside the left slot, no duplicate rail
  prose, and no height growth;
- FileViewer right-rail toolbar must not show visible count/source metadata such
  as `480/480 dev-worktree-source...`. For this checkpoint, remove the visible
  toolbar prose entirely and keep any count/source facts in sr-only status text,
  data attributes, tooltips, or a later approved compact status/footer surface;
- FileViewer and ReviewViewer may expose different actions, but any shared
  action must be rendered through the same BridgeViewer chrome primitive layer;
- proof must capture screenshots plus geometry for content header, rail toolbar,
  representative content buttons, representative rail buttons, and the
  segmented toggle. A subagent/onlook must review this exact list before the
  checkpoint can be accepted.

Immediate 0.b visual-control inventory before goal restart:

1. Add/own the missing shadcn-style `ToggleGroup` primitive under
   `BridgeWeb/src/components/ui/` or choose the equivalent existing local
   primitive if one exists at implementation time.
2. Replace the custom `BridgeViewerContextSwitcher` segmented-control markup
   with a neutral BridgeViewer wrapper around that primitive.
3. Replace `BridgeReviewProjectionMenu` raw route-local segmented button markup
   with the same neutral `ToggleGroup` primitive family.
4. Remove visible FileViewer rail metadata text from the toolbar row; keep
   count/source facts only in non-visible status/proof surfaces until a compact
   visible surface is explicitly approved.
5. Ensure `BridgeReviewButton`, search, filters, FileViewer rail actions, and
   the context switcher all share one compact size contract through shared
   primitives rather than route-local class patches.
6. Move shared chrome ownership out of Review-namespaced modules. ReviewViewer
   and FileViewer may import neutral BridgeViewer shared wrappers; shared
   shell/header/rail-control code must not depend on Review-only chrome as the
   permanent implementation.
7. Keep the content header scoped only to the left content region; keep the
   right rail full-height and top-aligned.
8. Extend Playwright/dev-server proof to assert header/rail height parity,
   button box parity, segmented-toggle box parity, absence of visible rail
   metadata text, absence of raw route-local segmented controls for the two
   switchers, and screenshot artifacts for Files, Review diff, and Review
   file-target.

It is a failure if the next visible checkpoint shows a full-width black/header
strip over the right rail, a centered/floating mode switcher, route-local
FileViewer buttons/search styling that is larger than ReviewViewer rail chrome,
or different primitive families for the same button/input/toggle interactions.
The visual proof must compare FileViewer and ReviewViewer control size,
selected state, focus ring, icon box, border treatment, and spacing from
screenshots, not only DOM attributes. Controls may expose different actions per
mode, but shared interactions must look interchangeable at the same zoom level.
Review-namespaced wrappers may appear only as an explicitly tracked failing
intermediate state during a local refactor. They cannot close a visible UX
checkpoint. The proof target is neutral BridgeViewer shared chrome over the
existing shadcn/base UI substrate, not a second FileViewer design language and
not permanent Review-owned shared app chrome.

The blocker now starts with understandable dev navigation for both current
worktree contexts. Dev-server query params are allowed because they are a test
harness, but they must initialize or mutate the same BridgeViewer navigation
store that production Swift intents will mutate internally. Query params are not
the production navigation API.

Plan sequence changed after the 2026-06-25 navigation decision:

```text
0.a.1a shared navigation/store red proof
  -> proves viewer=file and viewer=review are store state, not separate app roots

0.a.2 Files context source adapter proof
  -> proves current-worktree file browsing in shared BridgeViewer shell

0.a.2a Review context dev route proof
  -> proves current-worktree review comparison and Review file target
  -> status: dev-server proof passed in commits 47933c48 and 6ce7ef9d

0.a.3 shared chrome/layout proof
  -> proves DiffsHub-like top chrome, shared shadcn primitives, context toggle,
     search/filter placement, and per-context memory
  -> status: reopened for exact visual parity after fresh screenshots:
     content header must be left-content-only, title/source left, Files/Review
     plus actions right, right rail top-aligned and independent, and FileViewer
     controls must reuse the shared BridgeViewer primitive layer instead of
     route-local oversized toolbar/search controls

0.a.4 visual/e2e/negative-substitute proof
  -> proves live dev-server behavior, Pierre/Shiki/worker ownership, and no
     standalone second app or stale bundle substitute
  -> does not own FileViewer click-to-ready latency, preload disposition,
     scheduler queue behavior, or Review route-fanout/content-pressure closure;
     those are 0.a.5 proof gates
  -> status: checkpointed for the shared visual shell in artifact
     2026-06-26T02-32-00-284Z; reopened for a fresh screenshot set after the
     chrome parity correction. Required pictures: Files context, Review diff
     context, Review file-target context, and a geometry/topbar/right-rail
     record showing the header stops at the rail and the rail starts at y=0.
     Fresh accepted-C refresh:
     `tmp/bridge-viewer-design-proof/2026-06-26T07-56-40-567Z-accepted-c-user-refresh-ready/accepted-c-design-proof.json`
     plus `files.png`, `review-diff.png`, and `review-file-target.png`.
     Browser/onlook agent `019f028e-c7a5-7732-b06e-7f65a0601fb9` passed this
     visual/layout proof with no Accepted-C mismatches. This pass is scoped to
     layout only and does not close inactive side effects, Review file-target
     lineage, neutral chrome ownership, context memory behavior, or
     file-load/preload behavior.
     Fresh implementation proof on 2026-06-26T07:29Z reran
     `pnpm --dir BridgeWeb run test:dev-server:worktree` and produced
     `tmp/bridge-viewer-worktree-dev-server/2026-06-26T07-29-01-656Z/worktree-dev-server-proof.json`.
     The verifier saved Files screenshots only, so supplemental Playwright
     screenshots were captured for Review diff and Review file-target under
     `tmp/bridge-viewer-worktree-dev-server/2026-06-26T07-29-01-656Z/manual-review-mode-screenshots/`.
     Browser/onlook agent `019f02d6-d856-7db0-95f1-db3475872a4a` judged the
     Files screenshots sufficient for the Files-context C slice but
     insufficient for full accepted-C closure without the supplemental Review
     captures; those supplemental captures now record `materializedType=diff`
     for Review diff and `materializedType=file` for Review file-target.

0.a.5 file-load responsiveness/preload and route-pressure proof
  -> proves FileViewer selected-file opens, refreshes, visible/nearby/
     speculative preloads, recently-updated-file stimuli, and Review
     route-fanout/content pressure through measured scheduler telemetry
  -> status: pending; browser proof may use conservative initial gates for
     route hits, queue depth, in-flight counts, and byte-budget admission, but
     production tuning constants still require Victoria/OTel before graduation

0.a.6 native Agent Studio Bridge/WKWebView proof
  -> proves Files context, Review diff context, Review file-target context, and
     Files-to-Review handoff in the Swift-hosted local worktree path with
     marker-correlated logs/metrics/traces where available
  -> status: pending after the dev-server content/scheduler proof is no longer
     showing unresolved `Loading file` behavior for the selected target
```

This order is mandatory for Gate 0.a. Later gates must not treat a FileViewer
layout screenshot as sufficient proof of the shared app boundary.

The dev-server route set must be re-proved against the current live app before
this precursor can advance again.

- Canonical command:
  `pnpm --dir BridgeWeb run test:dev-server:worktree`
- Required Files URL:
  `http://127.0.0.1:5173/?fixture=worktree&viewer=file&workers=on&scenario=current-worktree`
- Required Review diff URL:
  `http://127.0.0.1:5173/?fixture=worktree&viewer=review&workers=on&scenario=current-worktree`
- Required Review file-target URL:
  `http://127.0.0.1:5173/?fixture=worktree&viewer=review&presentation=file&path=<path>&version=<base|head|current>&workers=on&scenario=current-worktree`
- Legacy compatibility URL:
  `http://127.0.0.1:5173/?fixture=worktree&workers=on&scenario=current-worktree`
- Required fresh proof artifact:
  a new `tmp/bridge-viewer-worktree-dev-server/<timestamp>/worktree-dev-server-proof.json`
  plus screenshots captured after this correction. The artifact must record all
  required URLs and cannot pass from the legacy compatibility URL alone.

Historical green artifacts are not terminal proof for the reopened gate unless
they are rerun and visually/reviewer-validated against the current live dev
server. The proof must fail if the page renders the file tree/search on the
left and file content on the right, because the shared UX contract is primary
code/file canvas on the left and Pierre FileTree/right rail on the right.
The proof must also fail if the context switch/search/filter UX is visually
inconsistent with the accepted shared-shell contract: content-only left header
with context controls, right rail top-aligned outside that header, and rail-owned
compact search/filter/status controls using the ReviewViewer primitive style.
It must also fail if visible FileViewer search/filter/action controls are still
owned by route-local toolbar classes or raw/custom controls instead of the shared
BridgeViewer/shadcn primitive layer. It may record file-click latency or route
pressure as open 0.a.5 blockers, but 0.a.4 must not claim responsiveness,
preload, queue, or content-pressure closure.

Native Agent Studio Bridge/WKWebView proof remains outside this precursor and
is still required before PR-ready.

## Historical Problem And Current Blocker

The original worktree dev URL booted a Worktree/File protocol route, but it
reached a second app path instead of the shared BridgeViewer shell. That URL is
now historical evidence and a compatibility route. The reopened gate must prove
the explicit Files URL, Review diff URL, and Review file-target URL listed above.
The original compatibility URL was:

```text
http://127.0.0.1:5173/?fixture=worktree&workers=on&scenario=current-worktree
```

Original red evidence captured on 2026-06-24:

- HTTP bootstrap returns 200.
- `/__bridge-worktree/surface?scenario=current-worktree` returns 432 frames and
  431 visible file rows.
- `document.documentElement[data-bridge-app-protocol]` is `worktree-file`.
- Tree/content panes render after data load.
- Required product controls are absent:
  - search input: 0 matches
  - regex toggle: 0 matches
  - filter/status controls: 0 matches
- Screenshot artifact:
  `tmp/bridge-worktree-devserver-proof-recovery/current-worktree-route-after-3s.png`
- JSON artifact:
  `tmp/bridge-worktree-devserver-proof-recovery/current-worktree-route-diagnostics.json`

Former Gate 0.a red evidence:

- Worktree exact URL renders `.worktree-file-tree` on the left and
  `.worktree-file-content` on the right.
- Mock/root route renders the intended Bridge/Pierre shell with CodeView on the
  left and right rail on the right.
- `BridgeWeb/src/app/bridge-app-protocol-router.tsx` routes
  `worktree-file` to `WorktreeFileApp`.
- `BridgeWeb/src/worktree-file-surface/worktree-file-app.tsx` owns a custom
  file list/search/filter shell and renders opened content in raw `<pre>`.
- Pierre source proof shows CodeView supports mixed `file` and `diff` items,
  File rendering uses Shiki, and file rendering uses the worker pool when
  `WorkerPoolContextProvider` is active.

Current 2026-06-25 blocker:

- Local code now routes `worktree-file` through `BridgeApp viewerMode="file"`,
  but that does not close Gate 0.a by itself.
- The user's live dev-server screenshots show the file tree/search surface on
  the left and file content on the right.
- That visible layout violates the shared UX contract even if hidden ownership
  markers say `BridgeApp`.
- The next implementation checkpoint must restart/reload the Vite dev server,
  run the required route set in a real browser, and prove the visible surface has
  the primary Pierre CodeView/File canvas on the left and Pierre FileTree/right
  rail on the right in Files context plus the Review diff/file-target surfaces.

Fresh contrast proof:

- `pnpm --dir BridgeWeb run test:dev-server:worktree` passed on 2026-06-24 and
  wrote `tmp/bridge-viewer-worktree-dev-server/2026-06-24T12-51-13-807Z`.
- That green result proves the existing narrow route/data/scroll contract only.
  It does not satisfy this precursor because it does not require search, regex,
  filter/status controls, product-shell provenance, or negative-substitute
  assertions.

This means prior proof only establishes a narrow route/data-loading regression.
It does not prove shared BridgeViewer product readiness because it can pass while
the required route set still violates the shared-shell visible UX contract or
uses stale/mock/raw/custom-renderer substitutes.

## Blocking Outcome

Before downstream Bridge transport, scheduler, renderer, telemetry, or Ticket 02
closure claims continue, the dev server must prove the shared BridgeViewer
navigation/store contract and render the current worktree in both Files and
Review contexts with browser proof.

The precursor is complete only when Playwright evidence proves all required
behaviors and fails if the route regresses to a mock/raw/minimal substitute,
route-local app root, stale Vite bundle, or standalone `WorktreeFileApp`/raw
`<pre>` path.

This precursor is the fast-loop Vite/dev-server product proof. It does not
replace Agent Studio Bridge/WKWebView runtime proof for the full PR-ready epic.
The later implementation plan must add native app-hosted Bridge proof with
marker-correlated evidence that the same protocol/source/resource behavior works
through Swift, WKWebView, the Bridge host wiring, and packaged app assets.

## Vertical Slice Contract

Each implementation slice in this plan is a deliverable, not a task bucket. A
slice is ready only when it has:

- one user-visible or protocol-visible behavior target
- one named source/spec contract it satisfies
- unit or component proof for the state/model boundary it changes
- integration proof for any provider/store/protocol seam it touches
- browser/dev-server proof when the behavior is visible in BridgeWeb
- native Agent Studio/WKWebView proof implication when the behavior must exist in
  the Swift-hosted app before PR-ready
- artifact output: command, exit code, JSON/screenshot/log/metric paths, or an
  explicit blocked/not-run reason

Do not split a slice so small that it cannot be tested as a real behavior. Do
not combine slices so large that a failure cannot identify the broken boundary.
The intended rhythm is vertical: contract -> model/store proof -> provider or
renderer proof -> dev-server visible proof -> native proof when required.

## Scope

In scope:

- `BridgeWeb/src/worktree-file-surface/`
- `BridgeWeb/src/review-viewer/shell/`
- `BridgeWeb/src/review-viewer/code-view/`
- `BridgeWeb/src/review-viewer/workers/pierre/`
- `BridgeWeb/src/features/worktree-file/`
- `BridgeWeb/src/app/bridge-viewer-*` or equivalent app-level shared
  navigation/store modules
- `BridgeWeb/src/app/bridge-app-dev-worktree.ts`
- `BridgeWeb/src/app/bridge-app-protocol-router.tsx`
- `BridgeWeb/scripts/verify-bridge-viewer-worktree-dev-server.ts`
- focused unit/component/browser tests needed for this route
- proof artifacts under `tmp/bridge-viewer-worktree-dev-server/` or a named
  precursor proof directory

Out of scope:

- full Review renderer rewrite
- final scheduler tuning numbers
- PR merge
- changing unrelated Review mock fixtures except where the verifier needs a
  negative assertion
- polishing or preserving `WorktreeFileApp` as a separate product surface

Scope correction for 2026-06-27 takeover:

- The line that previously excluded native Swift host streaming implementation is
  superseded for the active goal. The old boundary applied only to the original
  dev-server precursor. The active goal explicitly includes native
  Agent Studio Bridge/WKWebView proof and the Swift/resource transport changes
  needed to make content bytes travel through stream-capable
  `ContentStreamPath` resources instead of RPC, push/store, or blob-shaped
  package paths.

## Product Contract

The shared BridgeViewer product route set must expose these observable regions:

0. Bridge Viewer App model
   - One app owns both viewer modes.
   - `ReviewViewer` handles diffs, changesets, and review packages.
   - `FileViewer` handles worktree file browsing, single-file reading, and live
     file view.
   - Worktree, mock fixture, live changeset stream, static review package, and
     file content stream are data sources or protocol inputs, not separate
     product apps.
   - Zustand owns navigation/view state for active source refs, active context,
     active target, rail state, canvas anchors, and lightweight status facts.
   - Zustand must not store large file bodies, raw diff bodies, streams, worker
     instances, Pierre instances, or resource executors.
   - The app exposes Review and Files contexts with a toggle. Each context
     remembers source identity, selected target, rail search/filter/expansion/
     selection/scroll, and canvas scroll anchor.
   - Canvas presentation is target-driven:
     - Review context + diff target renders a Pierre diff.
     - Review context + file target renders a Pierre/Shiki file without leaving
       the review context.
     - Files context + file target renders a Pierre/Shiki file.
     - Files context + diff target is a future affordance only; any diff target
       must bind to Review/comparison identity and must not be satisfied from
       Worktree/File protocol data alone.
   - Rich preview is out of scope; markdown and text-like files render through
     Pierre/Shiki file view.

0.a. Dev navigation contract
   - `viewer=file|review` is the dev-only query control for opening current
     worktree Files or Review context.
   - `presentation=diff|file`, optional `path=<path>`, and optional
     `version=<base|head|current>` may seed the initial target for proof/debug
     loops.
   - Path parameters are hints. Review file-target proof must resolve them into a
     typed Review target with comparison id, source identity, review item or file
     ref, version, target kind, and active context `review`. A path-only proof is
     not enough because it can accidentally prove a Worktree/File content load
     while bypassing the Review comparison boundary.
   - The old exact URL
     `?fixture=worktree&workers=on&scenario=current-worktree` may default to
     `viewer=file` for compatibility, but proof must also cover explicit
     `viewer=file` and `viewer=review`.
   - The dev UI must provide an understandable way to navigate between current
     worktree Review and Files contexts without editing source code.
   - Production Swift uses internal `BridgeViewerNavigationCommand` messages, not
     visible query parameters.

1. Shared content-header title/provenance slot
   - Shows route identity and source provenance in the shared BridgeViewer
     content header's `source / selected target` title slot.
   - Does not add a second Files-only header row. Extra provenance/status, if
     needed, must live in the same content header slot or in the right-rail
     toolbar.
   - The header row exists only over the left content/canvas region. It does not
     span over the right rail, create a full-window top strip, or push the right
     rail toolbar down.
   - The mode switcher and content actions live in the content header's right
     slot. They must not float in the middle of the viewport.
   - DOM exposes protocol/source facts for Playwright:
     `worktree-file`, source id, worktree/repo id, generation or revision token.

2. Shared BridgeViewer shell
   - Uses the same product shell contract as ReviewViewer/FileViewer.
   - Primary code/file canvas is on the left.
   - Pierre FileTree/right rail is on the right.
   - No required URL can mount `WorktreeFileApp` or a route-local custom shell.

3. Pierre FileTree/right rail
   - Shows selectable file rows with stable selected state.
   - Keeps tree scroll extent derived from size facts before all content bodies
     are loaded.
   - Supports tree filtering without fetching every file body.
   - Worktree/File and worktree-backed Review source adapters respect gitignore
     and repository ignore policy before publishing tree rows, descriptors,
     route bootstrap targets, review candidates, or preload demand. Ignored
     paths are absent from canonical viewer candidates unless a later explicit
     "show ignored files" mode is accepted.
   - Production Swift/native git data prep uses `agentstudio-git` for status,
     diff, ignore-policy, and candidate preparation. Any TypeScript git helper
     remains clearly marked and scoped to Vite dev-server utilities or test
     fixture utilities.

4. Pierre CodeView/File content pane
   - Shows opened file identity.
   - Shows loading, ready, stale, unavailable, and refresh states.
   - Keeps large-file scroll extent stable from declared line/row facts.
   - Renders file content through Pierre `CodeView`/`File`, Shiki, and worker
     backed highlighting when `workers=on`.
   - Uses the shared BridgeViewer Pierre CodeView options with `overflow:
     'wrap'` by default for Review diff targets, Review file targets, and Files
     file targets.

5. Query controls
   - Search text input with product-specific selector.
   - Regex toggle with product-specific selector.
   - Filter/status controls with product-specific selector.
   - User interaction must change observable state and visible results.
   - FileViewer and ReviewViewer controls for the same interaction semantics use
     the same BridgeViewer shared primitive layer and compact sizing. A
     FileViewer-only raw toolbar/search design is a blocker, even if it is built
     on shadcn/base UI underneath.

6. Provenance and negative-substitute guard
   - Verifier must reject the root Review mock route.
   - Verifier must reject a bare two-pane file list plus `<pre>`.
   - Verifier must reject `WorktreeFileApp` or route-local custom tree/content
     rendering.
   - Verifier must reject raw JSON/frame dumps.

## Implementation Slices

### Slice 06P.1 / 0.a.1: Red Shared Renderer Contract

Add or tighten the Playwright verifier so it fails against the required route
set for the right current reason. The Files URL must fail if the live page shows
tree/search on the left and file content on the right. The Review diff URL must
fail if it reaches a mock fixture or FileViewer. The Review file-target URL must
fail if it leaves Review context or renders outside Pierre/Shiki. Every required
URL must fail if the dev server is serving stale output or if the route reaches
any mock/raw/custom substitute instead of the shared BridgeViewer app.

Proof:

- Run the verifier before implementation and capture failure.
- Failure message names the visible shared-shell violation: wrong left/right
  composition, missing Pierre FileTree/right rail, missing Pierre CodeView/File
  canvas, missing Shiki/worker path, stale dev-server output, or mock/raw/custom
  substitute.
- Failure is not a timeout-only assertion.
- Keep a focused router/bootstrap composition assertion that
  `worktree-file` resolves through `BridgeApp viewerMode="file"`, but do not use
  that as sufficient proof. The browser proof must validate the visible surface
  and fail if `WorktreeFileApp`, a route-local custom shell, custom tree
  rendering, raw `<pre>` content, or a stale Vite bundle is visible or reachable.

### Slice 06P.1a / 0.a.1a: Red Dev Navigation And Store Contract

Add failing unit/component/browser proof for the current missing navigation
contract before implementing it.

The red proof must cover:

- `parseBridgeAppDevFixtureOptions` or the replacement dev query model accepts
  `fixture=worktree&viewer=file&scenario=current-worktree` and
  `fixture=worktree&viewer=review&scenario=current-worktree` without collapsing
  the viewer choice.
- The dev adapter maps query params to BridgeViewer store actions or initial
  state, not to separate application roots.
- Zustand has separate remembered context state for Review and Files.
- Review context can select a file target for a review item without switching
  to a standalone FileViewer app.
- No large body/content field appears in the navigation store model.
- The current implementation fails this proof for the expected reason, not by
  timeout or unrelated bootstrap failure.

### Slice 06P.2 / 0.a.2: Source Adapter Into Shared FileViewer

Route worktree data through the shared BridgeViewer FileViewer mode instead of
`WorktreeFileApp`. Worktree remains a source adapter/provider. The shared
BridgeViewer store owns lightweight navigation/view state for the Files context;
the Worktree/File adapter owns descriptor/provider facts and consumes validated
Worktree/File descriptors. Keep large bodies out of Zustand/state and render
only references plus materialized content.

Proof:

- Unit/component test for provenance derivation.
- Unit/component test for router/bootstrap composition: exact `worktree-file`
  protocol input resolves to shared BridgeViewer FileViewer, not
  `WorktreeFileApp` or an equivalent wrapper around it.
- Browser assertion for protocol/source DOM attributes.
- Screenshot shows BridgeViewer/FileViewer shell, not raw/minimal/second-app
  route.

### Slice 06P.2a / 0.a.2a: Current Worktree Review Context Dev Route

Add a dev-only adapter that can open Review context from the current worktree.
This adapter behaves as a provider/source adapter: it may use dev-server
fixture utilities to mint provider-owned Review comparison identity, stream
lineage, descriptors, and projection frames for the browser ReviewViewer. The
browser never becomes the Git diff authority, never mints package/source cursor
authority, and never receives raw package/diff bodies through route bootstrap or
navigation state. It must remain separate from the Worktree/File source adapter
so FileViewer does not become the diff engine.

Proof:

- Unit/integration test proves current-worktree provider exposes enough
  base/head metadata/content descriptors for a Review source without placing raw
  bodies in route bootstrap, RPC, intake/event paths, or the navigation store.
- Dev-route integration proof shows `review.openComparison` or the dev
  equivalent returns provider-owned comparison identity, stream lineage, and
  descriptors before content is demanded.
- Browser/dev-server proof for
  `?fixture=worktree&viewer=review&workers=on&scenario=current-worktree`
  reaches BridgeViewer Review context, not a mock fixture and not FileViewer.
- Browser proof shows right rail file list/tree and left Pierre diff canvas.
- Browser proof can switch a selected review item to file target and render the
  file through Pierre/Shiki while remaining in Review context.
- Proof artifact records the source/comparison identity: base ref, target
  worktree/source cursor or revision token, selected item/file ref, target kind,
  target version, and active context `review`.

### Slice 06P.2b / 0.a.2b: Files To Review Typed Handoff

Add proof for the required same-app handoff from Files context into Review
context. Direct Review dev URLs prove bootstrap coverage only; they do not prove
this product transition.

Flow:

```text
Files context selection
  -> OpenReviewComparisonIntent
  -> ReviewComparisonSelector
  -> review.openComparison
  -> accepted | rejected | deferred
  -> accepted path emits provider-owned ReviewComparisonSpec
  -> BridgeViewerNavigationCommand activates Review context
  -> Files context memory remains available for toggle-back
```

Proof:

- Unit proof for `OpenReviewComparisonIntent` accepted/rejected/deferred outcomes.
- Unit/integration proof that Worktree/File supplies selection and source hints
  only; it must not mint Review endpoints, comparison id, package id, source
  cursors, or diff authority.
- Component/store proof that accepted handoff uses the shared
  `BridgeViewerNavigationCommand` path and does not require a new pane id.
- Browser proof starts in Files context, invokes the handoff, reaches Review
  context in the same BridgeViewer app, and toggles back to Files with source,
  rail, target, and scroll memory preserved.
- Native proof must cover the same handoff before PR-ready.

### Slice 06P.3 / 0.a.3: Shared Shell, Right Rail, Query And Filter Controls

Add or reuse tree/file search, regex mode, and filter/status controls inside the
shared BridgeViewer shell. Filtering should operate on descriptors and metadata,
not file bodies. The rail side must match the shared UX contract: primary
content left, Pierre FileTree/right rail right.
All controls should use shared `components/ui` primitives and the existing
Bridge design system where applicable. Shared BridgeViewer chrome primitives
must have a neutral owner. Review-namespaced button/icon primitives may be a
temporary checkpoint implementation detail only if the implementation review
records the debt and a follow-up cutover; they are not the target architecture.
The closure invariant is explicit: shared BridgeViewer shell/header/context
switcher/rail-control code must not permanently import Review-only chrome
modules through direct imports, re-export wrappers, or aliases. The implementation
checkpoint must either move the shared primitive ownership to a neutral
BridgeViewer/shared UI module or record the remaining Review-owned import as
open debt that blocks PR-ready status.
Do not add route-local raw buttons,
inputs, or one-off styling when a shared primitive exists or should be extended.
The visible chrome should be reconciled against DiffsHub/Pierre and the existing
ReviewViewer chrome before implementation. In particular, the context switcher,
search affordance, filter buttons, and regex toggle must feel like one app
surface, not a bolted-on FileViewer rail. The accepted top-bar contract is a
content-only header over the left canvas, with the right rail top-aligned outside
that header; proof must keep asserting that geometry from screenshots before
this slice can close.

Proof:

- Unit tests cover plain text search, regex search, invalid regex handling, and
  status/filter composition.
- Browser/subagent design-onlook proof captures current FileViewer,
  ReviewViewer, and DiffsHub/Pierre screenshots/source before the chrome fix and
  records the intended target layout from the shared-shell sketch.
- Vitest Browser proof covers the context toggle and per-context remembered
  rail/canvas location. jsdom-only proof is not accepted for this UX contract.
- Positive proof that the right rail is Pierre FileTree: use a composition test
  or a browser-visible marker from the shared Pierre tree path. A custom tree
  with equivalent row counts does not satisfy this slice.
- Browser proof types a query, toggles regex, changes a filter, and observes a
  stable state/result transition.
- Browser proof records before/after visible row counts or sampled visible path
  sets for each query/filter interaction so decorative controls cannot pass.
- Browser proof toggles Review <-> Files and verifies each context restores its
  selected target and scroll/rail location.
- Browser/protocol proof verifies inactive mounted contexts do not start new
  foreground content fetches or mutate visible loading/selection state. Allowed
  inactive work must be explicit background/speculative demand with source,
  generation, and active-context stale-drop checks.
- Screenshot proof compares FileViewer, ReviewViewer, and DiffsHub/Pierre chrome
  placement. A subagent must inspect the screenshots and relevant source paths
  and report UX mismatches before this checkpoint can be accepted.
- Checkpoint commit is blocked until the parent has inspected the screenshot
  artifacts and the subagent/onlook report, not only the JSON proof file.

Current checkpoint note, 2026-06-25:

- Implemented FileViewer rail chrome cutover to shared `BridgeReviewSearchControl`
  and `BridgeReviewFilterMenu`; search input starts closed and opens through the
  shared search control.
- Added Vitest Browser proof at
  `BridgeWeb/src/file-viewer/bridge-file-viewer-app.browser.test.tsx`.
- Fresh dev-server proof passed:
  `tmp/bridge-viewer-worktree-dev-server/2026-06-25T23-35-53-157Z/worktree-dev-server-proof.json`.
  The proof asserts `BridgeViewerAppShell`, FileViewer mode, `CodeView.file`,
  right-side `FileTree`, Pierre/Shiki workers ready, zero standalone
  `WorktreeFileApp`, one shared rail toolbar, one shared search control, one
  shadcn filter menu, and zero visible search input at initial load.
- Browser/onlook screenshots:
  `/tmp/bridgeviewer-verification/final-1.png`,
  `/tmp/bridgeviewer-verification/final-2.png`,
  `/tmp/bridgeviewer-verification/final-3.png`.
  The onlook passed the shared-shell/left-canvas/right-rail/search-closed/no
  standalone-app checks.
- Non-blocking observation for a later telemetry/transport audit: the browser
  onlook saw aborted `__bridge-worktree/review-content/...` requests on review
  routes while selected content still rendered ready. This does not block 0.a.3
  shell/chrome acceptance, but it should be kept visible for the review-route
  fetch/cancellation follow-up.
- Resolved implementation review finding, 2026-06-25: a prior dev-server
  artifact recorded the legacy Files URL as the main Files proof. The verifier
  fix makes the canonical Files proof use the explicit
  `?fixture=worktree&viewer=file&workers=on&scenario=current-worktree` URL and
  records that URL in the artifact. The legacy compatibility URL may remain an
  extra observation, not the primary or required proof.
- Resolved implementation review finding, 2026-06-25: `clickWorktreeFilePath`
  could fall back to synthetic DOM `dispatchEvent` after a failed browser click.
  Product E2E proof now uses actionability-checked browser interactions with
  bounded waits so a broken user click cannot pass.
- Browser/onlook update, 2026-06-25: fresh live screenshots were captured at
  `/tmp/bridgeviewer-verification/current-onlook-file.png`,
  `/tmp/bridgeviewer-verification/current-onlook-review.png`, and
  `/tmp/bridgeviewer-verification/current-onlook-review-file-target.png`. The
  onlook passed all three live URLs for shared shell, no standalone app, left
  canvas/right rail on Files, and usable search/regex/filter affordances where
  expected. It repeated the low-priority review-content `ERR_ABORTED` note.
- Verifier fix proof, 2026-06-25: `test:dev-server:worktree` now uses explicit
  `viewer=file` as the canonical Files URL and records `requiredRouteUrls` for
  the explicitly proven Files, Review, and Review file-target URLs. It no longer
  synthetic-dispatches tree-row clicks or filter-option clicks after a real
  browser action miss. The menu-dismiss path only sends Escape for a visible
  Bridge menu portal, blurs the active element first, and asserts the FileViewer
  search, regex, filter, and status control state is preserved so filtered proof
  cannot be silently weakened. The latest passing artifact is
  `tmp/bridge-viewer-worktree-dev-server/2026-06-26T00-45-05-123Z/worktree-dev-server-proof.json`.
- Legacy URL observation, 2026-06-25: the compatibility URL
  `?fixture=worktree&workers=on&scenario=current-worktree` was live-debugged and
  currently boots the shared app shell in File mode, but it did not expose the
  FileTree/CodeView ownership markers or selected content required by Gate 0.a.
  It is not advertised as a required or passing route in this checkpoint.

Current checkpoint note, 2026-06-26:

- Commit `85e98cd6` implements the accepted content-header correction:
  FileViewer and ReviewViewer share one content-only header over the left
  content region, the header title uses `source / selected target`, and the
  right rail remains top-aligned outside the header.
- Fresh dev-server proof passed:
  `tmp/bridge-viewer-worktree-dev-server/2026-06-26T02-32-00-284Z/worktree-dev-server-proof.json`.
  The proof asserts `contentTopbarStopsBeforeSidebar`,
  `sidebarStartsAtContentTopbar`, `contextSwitcherInsideContentTopbar`,
  `CodeView.file`, `FileTree`, `shikiRendering = pierre`, worker readiness,
  stable scroll canary, and zero standalone `WorktreeFileApp`.
- Screenshot artifacts:
  - `tmp/bridge-viewer-worktree-dev-server/2026-06-26T02-32-00-284Z/manual-shared-shell-proof/file.png`
  - `tmp/bridge-viewer-worktree-dev-server/2026-06-26T02-32-00-284Z/manual-shared-shell-proof/review.png`
  - `tmp/bridge-viewer-worktree-dev-server/2026-06-26T02-32-00-284Z/manual-shared-shell-proof/reviewFileTarget.png`
- Geometry artifact:
  `tmp/bridge-viewer-worktree-dev-server/2026-06-26T02-32-00-284Z/manual-shared-shell-proof/geometry.json`
  records File, Review, and Review file-target routes with content topbar
  `left=0`, `right=1388`, `height=36`; right rail `left=1388`, `width=340`,
  `top=0`; and code canvas `top=36`.
- Parent-refreshed screenshot geometry recorded content topbar `left=0`,
  `right=1388`, `height=36`; right rail `left=1388`, `width=340`, `top=0`;
  and code canvas `top=36` in Files, Review, and Review file-target modes.
- Current route after this checkpoint:
  `shravan-dev-workflow:implementation-review-swarm` before the next
  implementation slice. Remaining Gate 0.a work includes implementation review,
  neutral shared-chrome primitive ownership review/fix, inactive-context
  side-effect proof/fix, Review file-target comparison identity proof, file-load
  responsiveness/preload telemetry, native Agent Studio Bridge/WKWebView proof,
  and final PR-ready wrapup.

Current checkpoint note, 2026-06-26 active-context retention:

- `BridgeWeb/src/app/bridge-app.tsx` now separates retained Review model work
  from inactive foreground work. Review projection coordination continues to
  receive `reviewPackage` while Review is inactive, so item order/materialized
  identity survives Files -> Review -> Files -> Review toggles. Inactive Review
  visible content hydration receives `null`, selected-content requests abort,
  app-control and select-item listeners detach, markdown preview work aborts,
  and first-render / `review.markFileViewed` effects require Review to be
  active.
- Fresh dev-server proof passed:
  `tmp/bridge-viewer-worktree-dev-server/2026-06-26T05-20-18-995Z/worktree-dev-server-proof.json`.
  The proof records `BridgeViewerAppShell`, `CodeView.file`, `FileTree`,
  `shikiRendering=pierre`, `workerPoolState=ready`,
  `contentTopbarStopsBeforeSidebar=true`, `sidebarStartsAtContentTopbar=true`,
  and `standaloneWorktreeFileAppCount=0`.
- The same proof records Files -> Review handoff for `.gitignore`,
  `selectedMaterializedItemType=file`, `selectedMaterializedFileLineCount=92`,
  then return to Files and back to Review with `.gitignore` still selected and
  ready. This closes the regression where gating the inactive Review projection
  collapsed Review into `Review projection unavailable` on return.
- Browser/onlook screenshots captured:
  - `tmp/bridge-viewer-browser-onlook/2026-06-26T05-02-19-553Z/1-file-current-worktree-gitignore.png`
  - `tmp/bridge-viewer-browser-onlook/2026-06-26T05-02-19-553Z/1-file-current-worktree-gitignore--open-review-comparison.png`
  - `tmp/bridge-viewer-browser-onlook/2026-06-26T05-02-19-553Z/1-file-current-worktree-gitignore--open-review-comparison--steady.png`
  - `tmp/bridge-viewer-browser-onlook/2026-06-26T05-02-19-553Z/2-review-current-worktree.png`
  - `tmp/bridge-viewer-browser-onlook/2026-06-26T05-02-19-553Z/3-review-presentation-file-gitignore-current.png`
  - `tmp/bridge-viewer-browser-onlook/2026-06-26T05-02-19-553Z/capture-results.json`
- Still open for the next implementation slice:
  - Hidden FileViewer must honor inactive-context gating. The current mounted
    Files mode is suspected to keep its worktree surface subscription/polling
    alive after switching to Review.
  - Hidden Review no-foreground-work proof is still incomplete. The checkpoint
    proves Review returns ready, but not that hidden Review emits zero
    foreground content requests, `review.markFileViewed`, or route-level
    foreground telemetry while Files is active.
  - Review diff proof must stop using the synthetic
    `__bridge_select_review_item` event and select the Review item through a
    real actionability-checked tree/search UI interaction. The smallest
    accepted verifier path is: open
    `button[data-testid="bridge-review-search-toggle"]`, type into the Pierre
    tree search input
    `[data-testid="bridge-review-trees-panel"] file-tree-container input[data-file-tree-search-input]`,
    click the matching
    `[data-testid="bridge-review-trees-panel"] file-tree-container button[data-item-path="<path>"][data-item-type="file"]:not([data-file-tree-sticky-row]):not([data-item-parked])`
    row through Playwright actionability, then prove selected display path,
    selected item id, selected content state, content-route hit for the expected
    Review item, and a screenshot captured after the click.
  - Review file-target routing must prefer `reviewItemId`, validate
    comparison/source lineage, and only fall back to provider-approved file-ref
    mapping. The verifier must record `comparisonId`, source identity,
    `reviewItemId` or resolved file ref, version, `targetKind`, and active
    context. First implementation proof should prefer `target.reviewItemId`
    over path fallback because that field is already in the navigation model.
    Strict `comparisonId` enforcement needs a Review package/runtime authority
    extension before it can be honestly enforced; do not fake it with path-only
    proof.
  - Explicit Files -> Review handoff must clear retained Review search/filter
    refinements that hide the requested target before selecting, so the target
    row becomes visible and the selected item lineage can be inspected.
    Silently selecting a hidden target or falling back to the first visible
    projected item is a bug.
  - Repeating the same navigation intent must reapply when the current target
    has moved elsewhere; lifetime command-id latching is too broad.
  - Context memory proof must be browser-visible for rail search/filter state
    and rail/canvas scroll restoration, not jsdom/path-only.
  - Neutral shared-chrome primitive ownership remains open while shared
    FileViewer/header controls import Review-namespaced primitives.
  - Review content route fanout remains visible in the proof artifact,
    including high review route hit counts. Slice 06P.5/0.a.5 owns closing the
    Review route-fanout/content-pressure observation together with FileViewer
    preload latency, using browser proof plus Victoria-backed telemetry. Native
    Agent Studio Bridge/WKWebView product proof is still required by 0.a.6 and
    cannot be satisfied by Vite/dev-server screenshots alone.

Test-first anchors for the next implementation slice:

- Add `applies review file target by reviewItemId before path fallback` in
  `BridgeWeb/src/app/bridge-app.integration.test.tsx`, using a package with two
  items that share a path but have distinct item ids. Current code should fail
  because `itemIdForReviewFileNavigationTarget` path-matches first.
- Add `reapplies same review navigation command after selection moved elsewhere`
  in the same file. Current code should fail because
  `appliedNavigationCommandIdRef` drops the repeated command id even when the
  current selected item no longer satisfies the target.
- Add explicit-target refinement tests for retained Review filters/search.
  Current code should fail because explicit target application can fall back to
  the first projected item or keep the target row hidden when retained
  refinements exclude it.
- Completed current checkpoint: the dev-server Review selection verifier now
  replaces `__bridge_select_review_item` with the real tree/search click path
  above. A source-text guard covers the lower-layer regression, and
  `pnpm --dir BridgeWeb run test:dev-server:worktree` proves the Playwright
  click path with `reviewSelectionProof.selectionMethod =
  playwright-review-tree-search-click`.

Current visual/layout note, 2026-06-26 accepted-C refresh:

- Fresh user-confirmed option-C dev-server proof passed:
  `tmp/bridge-viewer-worktree-dev-server/2026-06-26T08-35-04-033Z/worktree-dev-server-proof.json`.
- Fresh pictures inspected:
  - `tmp/bridge-viewer-worktree-dev-server/2026-06-26T08-35-04-033Z/worktree-file-ready.png`
  - `tmp/bridge-viewer-worktree-dev-server/2026-06-26T08-35-04-033Z/worktree-review-ready.png`
  - `tmp/bridge-viewer-worktree-dev-server/2026-06-26T08-35-04-033Z/worktree-review-file-target-ready.png`
- The fresh proof records `contentTopbarStopsBeforeSidebar=true`,
  `contextSwitcherInsideContentTopbar=true`, `sidebarStartsAtContentTopbar=true`,
  `sidebarIsRight=true`, and `workerPoolState=ready`.
- The fresh Review file-target proof records `.gitignore` in Review context
  through the file renderer, but also records `reviewContentRouteHitCount=292`.
  That fanout remains a real 0.a.5 pressure/scheduler blocker, not a reason to
  claim Gate 0.a done.
- This confirms accepted decision C visually after the latest user alignment:
  content header only over the left canvas; title/source left; `Files | Review`
  plus content actions right; right rail full-height, top-aligned, and outside
  the content header.
- Review real-click verifier checkpoint is now closed for the dev-server slice:
  `tmp/bridge-viewer-worktree-dev-server/2026-06-26T10-13-26-058Z/worktree-dev-server-proof.json`
  records `searchOpened=true`,
  `searchInputValue=sources/agentstudio/atomregistry.swift`,
  `clickedRowItemPath=Sources/AgentStudio/AtomRegistry.swift`,
  `clickedRowItemType=file`, `clickedRowVisible=true`, and
  `selectionMethod = playwright-review-tree-search-click`.
  Fresh pictures inspected:
  - `tmp/bridge-viewer-worktree-dev-server/2026-06-26T10-13-26-058Z/worktree-file-ready.png`
  - `tmp/bridge-viewer-worktree-dev-server/2026-06-26T10-13-26-058Z/worktree-review-ready.png`
  - `tmp/bridge-viewer-worktree-dev-server/2026-06-26T10-13-26-058Z/worktree-review-file-target-ready.png`

- Earlier verifier screenshot-refresh proof passed:
  `tmp/bridge-viewer-worktree-dev-server/2026-06-26T08-25-12-296Z/worktree-dev-server-proof.json`.
- The verifier now saves Review screenshots directly in `screenshotPaths`
  instead of requiring manual supplemental Review captures. Historical packet:
  - `tmp/bridge-viewer-worktree-dev-server/2026-06-26T08-25-12-296Z/worktree-file-ready.png`
  - `tmp/bridge-viewer-worktree-dev-server/2026-06-26T08-25-12-296Z/worktree-review-ready.png`
  - `tmp/bridge-viewer-worktree-dev-server/2026-06-26T08-25-12-296Z/worktree-review-file-target-ready.png`
  - `tmp/bridge-viewer-worktree-dev-server/2026-06-26T08-25-12-296Z/worktree-file-search-result.png`
  - `tmp/bridge-viewer-worktree-dev-server/2026-06-26T08-25-12-296Z/worktree-file-stale-refresh.png`
- Parent visual inspection of those verifier screenshots confirmed the
  accepted-C geometry and shared visual language for Files, Review diff, and
  Review file-target. This picture refresh was superseded by the 10:13
  real-click/chrome checkpoint above.
- Earlier accepted-C screenshots and geometry:
  - `tmp/bridge-viewer-design-proof/2026-06-26T07-56-40-567Z-accepted-c-user-refresh-ready/files.png`
  - `tmp/bridge-viewer-design-proof/2026-06-26T07-56-40-567Z-accepted-c-user-refresh-ready/review-diff.png`
  - `tmp/bridge-viewer-design-proof/2026-06-26T07-56-40-567Z-accepted-c-user-refresh-ready/review-file-target.png`
  - `tmp/bridge-viewer-design-proof/2026-06-26T07-56-40-567Z-accepted-c-user-refresh-ready/accepted-c-design-proof.json`
- The geometry artifact records all three routes with content topbar `left=0`,
  `right=1708`, `height=36`; right rail `left=1708`, `width=340`, `top=0`;
  code canvas `top=36`; and all accepted-C predicates true:
  `allRoutesUseSharedShell`, `allHeadersEndBeforeRail`, `allRailsStartAtTop`,
  `allCanvasesBelowHeader`, `allSwitchersInsideTopbar`, and
  `allControlsInsideTopbar`.
- Browser/onlook agent `019f028e-c7a5-7732-b06e-7f65a0601fb9` passed the
  visual/layout proof with no concrete layout mismatches and reiterated that
  this proof does not cover the implementation gates listed above.

### Slice 06P.S / Streaming Resource Contract Realignment

This slice is the mandatory first implementation slice for the 2026-06-27
takeover. It exists because the current branch has useful scheduler/proof work
but still has blob-shaped resource/materialization paths that can violate the
transport spec even when dev-server UX proof passes.

Objective:

- Keep RPC, continuous event streams, intake frames, push/store updates, and
  Zustand free of large file/diff/review bodies.
- Make the Vite/browser dev loop the first faithful implementation of the
  production protocol architecture. Dev may swap the backend source adapter, but
  it must still use the same three lanes as Swift/native: RPC for control,
  continuous/intake streams for metadata/projection/descriptors, and
  `ContentStreamPath` resource streams for all content bytes.
- Treat any browser/dev fixture that injects Zustand state directly, pushes a
  package object as metadata, uses RPC for metadata/body transfer, or resolves a
  resource as the primary proof path through a whole blob as a non-faithful
  component fixture, not as dev-loop product proof.
- Make `ContentStreamPath` the only path for content bytes and bounded
  body/window data.
- Preserve first-slice authoritative integrity as whole-body validation when an
  integrity hash is issued, unless this plan explicitly promotes chunk manifests
  and ranged integrity.
- Keep preview ranges/windows non-authoritative until chunk manifests exist.
- Fix native Review startup so useful Review projection/status can reach the
  browser without requiring a whole package blob to be built first.

Required red/audit proof before implementation:

- Isomorphism proof that dev/Vite and Swift/native expose the same lane
  contract to BridgeWeb: `RPC/control`, `metadata/change stream`, and
  `ContentStreamPath` body stream. The proof must name the only allowed
  difference as backend/source implementation, not browser-visible protocol
  shape.
- Unit or static contract proof that browser resource executor APIs are not
  whole-body-only promises for in-scope file/review bodies.
- Unit or integration proof that FileViewer/Worktree resource loading does not
  require `response.text()` whole-body materialization as the default product
  path.
- Unit/integration proof that streamed whole-body resources can materialize
  provisional chunks/windows, then either commit after whole-hash validation or
  roll back/mark failed on abort, stale completion, truncation, or hash mismatch.
- Swift unit/integration proof that `BridgeSchemeHandler` can emit multiple
  bounded data chunks for content resources and enforces leases/byte limits
  across the stream.
- Review transport proof that snapshot/delta intake frames attach descriptors
  and do not require `DiffPackageMetadataSlice` to carry materialized package
  bodies through the diff store path.
- Descriptor handoff proof that every schedulable body/window arrives as a
  `BridgeAttachedResourceDescriptor`, is registered before app demand policy
  receives a `BridgeDescriptorRef`, and raw descriptor strings or unregistered
  URLs cannot drive demand or fetch.
- Continuous-event-lineage proof that Review and Worktree/File startup expose
  pane-scoped `ready`, heartbeat/source-status, descriptor-available,
  invalidated, gap, reset, and closed facts without body transfer, and that
  matching intake/content work stale-drops or rebinds after gap/reset/close.
- Security/integrity negative proof that forged or stale resource authority
  fails closed: cross-pane replay, stale generation/cursor, revoked lease during
  stream, oversized resource, truncated/tampered whole-body mismatch, and
  preview ranges remaining non-authoritative until chunk manifests exist.
- Capability-leak proof that `agentstudio://resource/...` bearer URLs never leak
  into DOM-visible proof state, telemetry, provider errors, markdown, comments,
  agent communications, screenshots' JSON metadata, or exported proof artifacts;
  only safe descriptor refs, hashes, or source-scrubbed identifiers may appear.
- Inactive-context proof that toggling Files <-> Review while work is queued or
  in flight emits no new foreground fetches, no route-level foreground telemetry,
  no visible loading/selection mutation for inactive contexts, and stale-drops
  by active context, source identity, generation, and consumer epoch.
- Native IPC proof that failure to build a whole package does not prevent the
  browser from receiving a usable loading/error/projection lifecycle frame with
  source/comparison identity and stream lineage.

Implementation guidance:

- Dev-loop first: implement and prove the browser/Vite loop as the source of
  truth for the protocol contract before native proof. Native then proves the
  same contract through Swift IPC, AgentStudioGit, WKWebView, and
  `agentstudio://resource`, not a different startup/materialization path.
- Browser: evolve the generic resource executor around stream/window
  consumption, abort, stale-drop, byte accounting, and completion integrity
  rather than returning only `Promise<{ body, byteLength }>`.
- Browser: FileViewer and Review materializers should consume streamed chunks or
  bounded windows through registries/materializers outside Zustand; Zustand keeps
  only refs, identities, status, freshness keys, and small facts.
- Browser: a full-string assembler may remain only as an explicitly leaf-level
  adapter for small/current renderer APIs. It must not be the generic executor
  contract, the demand result type, or the proof of streaming behavior.
- Swift: keep `WKURLSchemeHandler`/`BridgeSchemeHandler` stream semantics real by
  yielding bounded chunks/windows and validating lease authority before and
  during emission. A single `.data(wholeBody)` yield cannot be the final
  product path for large content resources.
- Swift: current bounded-chunk emission from already-materialized `Data` is only
  an interim safety improvement. The final resource path must stream or window
  from the source/store layer so large files do not require full allocation
  before first byte emission.
- Review/native: separate provider/source lifecycle and descriptor publication
  from full package acquisition. `reviewPipeline.loadPackage(...)` may remain a
  provider implementation detail only after the visible stream/demand contract
  is satisfied; it must not be the user-facing gate that blocks all Review
  projection/lifecycle frames.
- Review/native: semantic Review snapshots, windows, and deltas must stream as
  intake metadata. Remove `review-package` and `review-delta` from startup and
  projection authority unless a later export/debug slice defines them as
  non-startup, non-authoritative byte resources with separate proof. They cannot
  remain decorative descriptors, and they cannot be used to satisfy tree,
  projection, or metadata readiness.
- IPC: `getContent` and `getPackage` must not be used as body/package transport
  proof. IPC may expose small status and descriptor metadata only; bytes and
  package/delta bodies must move through content/resource descriptors.
- Integrity: if the implementation can only prove whole-body integrity, stream
  incrementally and validate the whole hash at completion. Do not claim
  authoritative partial reads until chunk manifests and tamper fixtures exist.

Proof:

- Dev-loop proof must be protocol-faithful before it is accepted: no direct
  Zustand injection for Review/File data, no RPC body/metadata transfer, no
  push/store package body, and no whole-body blob fetch used as the proof of the
  content stream contract. Tests may assemble final text at renderer leaf
  boundaries only after streamed read, byte-budget enforcement, stale/abort
  handling, and final integrity gating are proven.
- Focused TypeScript unit/integration proof for the resource executor stream API,
  abort, stale completion, byte-budget accounting, and whole-hash completion
  validation.
- Focused FileViewer and Review tests proving streamed/windowed materialization
  without storing bodies/promises/streams in Zustand.
- Focused descriptor registry tests proving only registered `BridgeDescriptorRef`
  values can schedule demand/fetch and that raw, stale, foreign, or page-world
  descriptor-like strings fail closed.
- Focused Swift tests for chunked `BridgeSchemeHandler` emission, lease
  revocation during a stream, over-limit rejection, and `HEAD`/`GET` behavior.
- Focused Swift/Review tests proving `review-package` and `review-delta`
  descriptors are either real leased resources or absent from advertised frames.
- Focused negative authority/integrity fixtures for stale/cross-pane resource
  URLs, forged descriptor identity, mid-stream revocation, truncated/tampered
  bodies, and preview-only range handling.
- Focused redaction fixtures proving capability URLs are absent from telemetry,
  DOM-visible diagnostics, provider errors, and proof JSON while authorized
  resource fetches still work.
- Dev-server browser proof for Files, Review diff, and Review file-target routes
  still passing after the resource executor/materializer change, including
  queue depth, in-flight bytes, stale drops, aborts, latency, and scroll canary
  fields.
- Dev-server and native visible proof must include screenshots/video artifacts
  plus second-agent/onlook review when startup/loading or visible
  materialization behavior changes.
- Native `oq4s` IPC/WKWebView proof for the same routes and Review package
  acquisition path. The proof must not use stable AgentStudio, jsdom, or Vite as
  a substitute for native.
- If a proof layer cannot pass because the spec requires a larger chunk-manifest
  contract, stop and update the spec/plan before continuing code.

### Slice 06P.5 / 0.a.5: File Load Demand, Preload, And Content Pressure Proof

Render opened worktree files through Pierre CodeView/File. Shiki highlighting
and the Pierre worker pool must be active when `workers=on`. Make open-file
state explicit and visible: loading, ready, stale, unavailable, and refresh. If
the currently open file changes while open, show an update notification/refresh
affordance rather than silently replacing content.
Opened-file latency is part of this slice, not a subjective polish follow-up.
0.a.5 owns FileViewer responsiveness, preload/disposition proof, and Review
route-fanout/content-pressure closure. Visual/shared-shell proof in 0.a.4 can
surface these as blockers, but cannot close them.

The FileViewer should use the shared demand scheduler to warm likely next files:
selected/open file and refresh are `foreground`, visible tree rows are bounded
`visible` preloads, adjacent selected/open rows are `nearby`, hover/focus and
provider predictions are `speculative`, debounced recently-updated files from
the current open FileViewer source are `speculative` unless they are adjacent to
the selected/open/visible region, and broad warming is `idle`. All preloads
remain descriptor-backed, byte-budgeted, deduped, abortable, and stale-dropped;
large bodies stay out of Zustand.

Proof:

- Unit test for invalidation of the open descriptor.
- Unit/integration proof for FileViewer demand policy mapping selected,
  viewport-visible, adjacent, hover/focus, recently-updated-file, and idle
  stimuli to scheduler lanes.
- Unit/integration proof that recently-updated-file stimuli from the active
  FileViewer source enqueue descriptor-backed preloads as `speculative` or
  `nearby` by row proximity, never as foreground work unless the user explicitly
  opens or refreshes that file.
- Unit/integration proof that Worktree/File and worktree-backed Review source
  adapters exclude gitignored paths before publishing descriptors, tree rows,
  route bootstrap targets, review candidates, and preload demand.
- Browser proof observes stale/update affordance.
- Browser proof clicks refresh and returns to ready state.
- Browser proof rejects raw `<pre>` file rendering.
- Browser proof records Pierre CodeView/File and worker-ready markers.
- Browser proof records Pierre `overflow: 'wrap'` for opened FileViewer files,
  Review diff targets, and Review file targets unless a future explicit
  app-state override is present.
- Browser/dev-server proof records click-to-ready latency, queue depth,
  in-flight count, byte-budget decisions, and whether opened content was
  cold-loaded, visible-preloaded, nearby-preloaded, speculative-preloaded, or
  refreshed.
- Browser/dev-server proof emits or injects a recently-updated-file event and
  records the resulting lane, dedupe key, queue admission/drop, byte-budget
  disposition, and stale-drop behavior.
- The canonical click-to-ready clock starts at the browser actionability-checked
  click or refresh action and ends when the selected file identity is visible and
  Pierre CodeView/File has rendered non-loading file lines for that target.
  Worker-highlight completion is recorded as a secondary phase unless the UI
  still displays loading because highlighting is pending.
- Victoria/OTel proof is required before production constants graduate. The
  first pass may keep conservative defaults, but it must emit enough telemetry
  to tell whether slow click-to-ready time comes from provider I/O, descriptor
  scheduling, worker rendering, or UI commit.
- Review route-fanout/content-pressure is part of this slice, not a detached
  follow-up. The proof artifact must record Review route hits, cancellations,
  stale drops, queue depth, in-flight count, and bytes admitted for Review
  file-target navigation as well as Files click-to-ready navigation.
- Initial route-pressure gate, before production tuning: each selected target
  epoch may have at most one foreground content request in flight. Extra same-
  target route hits must be attributed as bounded retry, cancellation, or stale
  drop, and duplicate foreground work after ready fails the gate.
- Initial queue/in-flight gate, before production tuning: the proof artifact
  must publish max queue depth, max in-flight count, configured executor cap,
  lane upgrades, cancellations, and drops per lane. Foreground work must not sit
  behind lower-lane preloads, and no lane may exceed its declared executor cap.
- Initial byte-budget gate, before production tuning: the proof artifact must
  publish admitted, deferred, and dropped bytes by lane and source. Admission
  over the configured source/lane budget, or admission without a recorded budget,
  fails the gate.

### Slice 06P.6 / 0.a.6: Native Agent Studio Bridge/WKWebView Proof

Prove the same shared-app behavior inside Agent Studio's native Bridge pane.
The dev server is the fast iteration loop, but PR-ready status requires native
Bridge/WKWebView proof.

This slice has a required headless Swift-plane subgate before visual WKWebView
proof. The headless gate opens Worktree/File and worktree-backed Review sources
from the current worktree through the Swift transport/provider plane, records
metadata frames and demand decisions without relying on Vite or visible
rendering, and writes a benchmark artifact that proves manifest completeness,
load order, lane priority, no-starvation, and p95/p99 timings.

Proof:

- Add or update Swift e2e/benchmark coverage that runs headlessly against this
  worktree and records:
  - expected eligible path count after gitignore/repository ignore policy
  - emitted metadata row count, remaining count, and completion
  - the load class for each row: startup first-window, foreground selected/open,
    visible viewport, nearby lookahead, speculative prediction, idle manifest
    continuation, delta, reset, or replacement
  - metadata-interest update sequence and provider emission order
  - queue wait by lane, stale drops, lane upgrades, aborts, and no-starvation
    progress for idle manifest completion
  - separated content descriptor/content stream timings
- The headless Swift artifact fails if only the initial bounded window is
  emitted and no continued manifest progress/completion is recorded.
- The headless Swift artifact reports p95/p99 for open-to-first-window,
  metadata-interest-to-frame, full-manifest-complete, metadata apply, queue wait
  by lane, file click content fetch, and review item content fetch.
- Launch through the repo-standard debug observability path:
  `mise run observability:up` and
  `mise run run-debug-observability -- --detach`.
- Use the native/browser visual harness to perform real interactions in the
  embedded Bridge pane: load Files current-worktree, open a file, switch to
  Review diff, open Review file target, perform Files -> Review handoff, and
  toggle back with context memory intact.
- Capture screenshots for Files, Review diff, Review file target, and handoff
  return-to-Files.
- Correlate native proof with marker-scoped Victoria logs/metrics from the
  launched debug app. Marker-only proof or screenshot-only proof does not close
  this slice.
- If the native interaction/screenshot harness cannot run, mark 0.a.6 blocked
  with launcher/process/log evidence instead of downshifting to dev-server-only
  proof.

Implementation notes from current-code research:

- Existing generic demand code already owns the right primitives:
  `BridgeWeb/src/core/models/bridge-demand-models.ts`,
  `BridgeWeb/src/core/demand/bridge-demand-scheduler.ts`, and
  `BridgeWeb/src/core/demand/bridge-resource-executor.ts`.
- Existing Worktree/File policy already defines app-specific stimuli:
  `fileSelected`, `openFileInvalidated`, `treeViewportChanged`,
  `treeExpanded`, `explicitRefresh`, `hoverChanged`, and `sourceReset` in
  `BridgeWeb/src/features/worktree-file/models/worktree-file-protocol-models.ts`.
- Current FileViewer runtime only drives selection/refresh demand:
  `BridgeWeb/src/worktree-file-surface/worktree-file-surface-runtime.ts`
  exposes `openFile` and `refreshOpenFile`, and `BridgeFileViewerApp.openFile`
  awaits selected-file loading on click. Viewport, adjacent, hover/focus, and
  recently-updated-file stimuli are defined but not yet emitted by the UI/runtime
  path.
- Add an app-specific runtime seam, not a new generic scheduler:
  `dispatchDemandStimuli(stimuli: readonly WorktreeFileDemandStimulus[])`.
- Preloads should populate the descriptor-backed body registry/content resource
  layer, not React/Zustand state. Store only lightweight descriptor refs,
  freshness keys, source/version/epoch, and preload disposition/status facts.
- Use shared dedupe keys per descriptor so a queued lower-lane preload upgrades
  cleanly to `foreground` when the user clicks.
- Make ordering app-specific:
  visible by viewport row index, nearby by distance from selected/open row,
  speculative by latest event wins.
- Split cancellation groups by scope instead of only source-wide:
  open session, viewport epoch, nearby selected-file epoch, and speculative
  epoch. This prevents viewport churn or recently-updated-file debounces from
  canceling the selected/open file path.
- Before implementation, verify whether the current Pierre tree wrapper exposes
  viewport/hover/focus callbacks. If it does not, the first slice must add a
  browser-local adapter or a measured fallback that emits bounded visible-window
  stimuli without reaching into Pierre internals.

### Slice 06P.5a / 0.a.5 Support: Scroll Extent Canary

Keep DiffsHub-style scroll stability as a first-class canary. Tree and file
scroll extents must be based on declared row/line facts and remain stable across
selection and content hydration.

Proof:

- Browser proof records tree and content `scrollHeight`, `scrollTop`, selected
  row, and open path before and after file selection.
- Proof fails if scroll height collapses to only materialized visible content.
- Proof fails if selecting a file causes an unexplained jump outside threshold.

### Slice 06P.4a / 0.a.4: Negative Proof Artifact

Write a JSON proof artifact and screenshots that can be inspected by parent
agent and reviewer lanes.

Proof artifact must include:

- observed route set: required Files URL, Review diff URL, Review file-target
  URL, and optional legacy compatibility observations only when exercised
- timestamp
- browser executable/channel
- protocol/source facts
- selected file and open state
- search/regex/filter states
- per-interaction result deltas: before/after visible row count or sampled
  visible path set, active filter tokens, regex-valid or regex-error state, and
  the expected fixture-specific visible result change
- tree/content scroll canaries
- screenshot paths
- explicit negative-substitute assertions
- explicit assertion that `WorktreeFileApp`, route-local custom shell, and raw
  `<pre>` body rendering were not reached
- explicit positive assertions that the route used shared BridgeViewer
  FileViewer ownership, Pierre FileTree/right rail ownership, Pierre
  CodeView/File ownership, Shiki rendering, and worker-backed highlighting when
  `workers=on`

## Test Pyramid

Unit:

- descriptor filtering policy
- regex parsing and invalid regex behavior
- provenance derivation
- open-file invalidation/refresh state

Component:

- Worktree/File shell renders product regions from validated frames
- Router/bootstrap composition resolves worktree data to shared BridgeViewer
  FileViewer, not the standalone worktree app path
- Right rail identity is positively tied to Pierre FileTree
- query controls update local state and visible tree rows
- stale refresh affordance renders from invalidated open descriptor

Integration:

- dev worktree provider returns validated metadata, descriptors, size facts, and
  descriptor resource URLs without file bodies in metadata
- content fetch uses descriptor authority and generation/cursor
- content fetch serves the descriptor body from the already-accepted surface
  cursor without re-running a whole-worktree snapshot; after a newer surface is
  accepted, older cursor-bound requests reject as stale

Browser/E2E:

- legacy current-worktree URL as compatibility-only proof
- explicit current-worktree Files URL:
  `?fixture=worktree&viewer=file&workers=on&scenario=current-worktree`
- explicit current-worktree Review URL:
  `?fixture=worktree&viewer=review&workers=on&scenario=current-worktree`
- explicit current-worktree Review file-target URL:
  `?fixture=worktree&viewer=review&presentation=file&path=<path>&version=<base|head|current>&workers=on&scenario=current-worktree`
- Review context can open a selected item as a file target
- Files context invokes `OpenReviewComparisonIntent` and activates Review context
  in the same app
- context toggle preserves per-context selected target and rail/canvas location
- product controls present and interactive
- file click renders content
- search/regex/filter proof
- scroll extent canary
- screenshots and JSON artifact
- negative substitute guard

Native runtime:

- native `oq4s` Agent Studio Bridge/WKWebView proof is an active 06P.S / 0.a.6
  gate and must be rerun after resource-stream changes for the same protocol path
- headless Swift-plane e2e/benchmark proof is an active 06P.S / 0.a.6 subgate
  and must pass before native WKWebView visual proof is accepted
- proof includes bridge route boot, source/protocol identity, resource/content
  requests, event stream readiness, and Victoria/log marker correlation
- proof includes manifest completeness for all non-ignored rows, loaded-by/lane
  classification, metadata emission order, queue timing, and p95/p99 metrics
- Vite-only proof must not be used as the final native Bridge proof

Quality:

- `pnpm --dir BridgeWeb run test:unit` for touched TS units when available
- focused browser verifier for the route
- `mise run lint` before claiming the ticket ready

## Execution Diagram

```text
current-worktree dev route set
        │
        ▼
Vite dev bootstrap
        │
        ├─ maps query params into shared BridgeViewer navigation/store state
        ├─ installs Worktree dev backend or Review dev source adapter
        │
        ▼
BridgeViewerApp(active context = Files or Review)
        │
        ├─ Files target: left Pierre CodeView/File, right Pierre FileTree
        └─ Review target: left Pierre diff or File target, right Pierre rail
              │
              ├─ descriptor/resource fetch
              └─ review comparison/source materialization
                    │
                    ▼
      content/diff ready / stale / unavailable
```

## Gate

This precursor remains implementation-execution pending until 06P.S streaming
resource residuals are implemented and proven: Browser stream/session or
authoritative leaf-boundary contract, preview-vs-authoritative gating, Swift
source/store-backed Review content streaming, provider-issued native Review
startup identity, dev-server product proof, native `oq4s` IPC/WKWebView proof,
then implementation-review-swarm. Historical dev-server route proof remains
useful but cannot close this transport gate by itself.
