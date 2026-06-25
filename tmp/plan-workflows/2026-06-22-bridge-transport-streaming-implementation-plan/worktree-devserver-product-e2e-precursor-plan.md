# Worktree Dev-Server Product E2E Precursor Plan

Date: 2026-06-24
Status: Gate 0.a reopened; shared BridgeViewer navigation/store correction is
the active blocker before downstream gates
Ticket: 06P / Gate 0.a Shared BridgeViewer Navigation And Renderer Precursor

## Current Proof Status

Gate 0.a is not closed. Earlier proof artifacts and reviewer fixes are useful
history, but the live product contract is stronger than "make WorktreeFileApp
product-like." Three implementation checkpoints are now historical proof only
until the browser UX proof gaps below are fixed:

- `47933c48` proves direct current-worktree Review file-target routing in the
  shared Review shell.
- `6ce7ef9d` proves Files context can hand off a selected worktree file to
  Review context inside the same BridgeViewer app root.
- `85b1faa0` proves the shared context toggle and per-context memory at the
  dev-server verifier layer:
  `BridgeApp` owns one `BridgeViewerAppShell`, FileViewer and ReviewViewer are
  mounted as mode bodies, and a Files-to-Review-to-Files-to-Review round trip
  preserves the selected file/review target.
- Fresh proof command:
  `pnpm --dir BridgeWeb run test:dev-server:worktree`
- Fresh proof artifact:
  `tmp/bridge-viewer-worktree-dev-server/2026-06-25T13-48-26-677Z/worktree-dev-server-proof.json`
- Critical artifact row:
  `fileToReviewHandoffProof` records one app root, unchanged dev URL,
  Review mode, `.gitignore`, Pierre materialized item type `file`, 92 rendered
  lines, one hidden preserved FileViewer shell after switch, toggle-back to
  Files with `.gitignore` still selected, toggle-back to Review with `.gitignore`
  still selected, one review package route hit, and 17 review content route hits.

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

Shared shell design target for Gate 0.a:

```text
BridgeViewerAppShell
  ┌──────────────────────────────────────────────────────────────┬─────────────┐
  │ shared top chrome                                            │ right rail  │
  │   Files | Review context toggle                              │             │
  │   search / regex / filters / active source identity          │ Pierre      │
  ├──────────────────────────────────────────────────────────────┤ FileTree    │
  │ primary Pierre CodeView/File canvas                          │             │
  │   Review diff target  -> Pierre diff items                   │ selection   │
  │   Review file target  -> Pierre/Shiki file item              │ status      │
  │   Files file target   -> Pierre/Shiki file item              │ expansion   │
  └──────────────────────────────────────────────────────────────┴─────────────┘
```

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
  -> status: needs revision; current toggle exists but visible UX does not yet
     match the expected top-bar/search contract and jsdom proof must be removed
     or demoted from the UX gate
  -> first action: use a browser/subagent onlook to compare current FileViewer,
     current ReviewViewer, and DiffsHub/Pierre screenshots/source, then update
     implementation against the shared-shell design target above

0.a.4 visual/e2e/negative-substitute proof
  -> proves live dev-server behavior, Pierre/Shiki/worker ownership, and no
     standalone second app or stale bundle substitute
  -> status: needs revision; dev-server proof passed mechanically but must be
     extended with screenshot review, subagent visual critique, and browser
     coverage for top chrome/search and Review memory identity after toggle-back

0.a.5 file-load responsiveness/performance proof
  -> proves clicking files does not feel slow under the large worktree fixture,
     or records measured latency/backpressure defects as the next performance
     ticket
  -> status: pending; must be tied to Victoria/browser metrics or a browser
     performance canary before tuning constants are called ready
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
inconsistent with the ReviewViewer/DiffsHub-style top chrome, if the search
bar appears only as a route-local right-rail control when the shared product
chrome expects top-bar search, or if file-click content loading lacks measured
latency/backpressure evidence.

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
- native Swift host streaming implementation
- final scheduler tuning numbers
- PR merge
- changing unrelated Review mock fixtures except where the verifier needs a
  negative assertion
- polishing or preserving `WorktreeFileApp` as a separate product surface

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
     typed Review target with comparison id, review item or file ref, version, and
     active context `review`.
   - The old exact URL
     `?fixture=worktree&workers=on&scenario=current-worktree` may default to
     `viewer=file` for compatibility, but proof must also cover explicit
     `viewer=file` and `viewer=review`.
   - The dev UI must provide an understandable way to navigate between current
     worktree Review and Files contexts without editing source code.
   - Production Swift uses internal `BridgeViewerNavigationCommand` messages, not
     visible query parameters.

1. Source/status header
   - Shows route identity and source provenance.
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

4. Pierre CodeView/File content pane
   - Shows opened file identity.
   - Shows loading, ready, stale, unavailable, and refresh states.
   - Keeps large-file scroll extent stable from declared line/row facts.
   - Renders file content through Pierre `CodeView`/`File`, Shiki, and worker
     backed highlighting when `workers=on`.

5. Query controls
   - Search text input with product-specific selector.
   - Regex toggle with product-specific selector.
   - Filter/status controls with product-specific selector.
   - User interaction must change observable state and visible results.

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
This adapter may use the existing dev worktree provider's base/head file data
to materialize a review package or equivalent Review source for the browser
ReviewViewer. It must remain separate from the Worktree/File source adapter so
FileViewer does not become the diff engine.

Proof:

- Unit/integration test proves current-worktree provider exposes enough
  base/head metadata/content handles for a Review source without placing raw
  bodies in the navigation store.
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
Bridge design system where applicable. Do not add route-local raw buttons,
inputs, or one-off styling when a shared primitive exists or should be extended.
The visible chrome should be reconciled against DiffsHub/Pierre and the existing
ReviewViewer chrome before implementation. In particular, the context switcher,
search affordance, filter buttons, and regex toggle must feel like one app
surface, not a bolted-on FileViewer rail. The top-bar layout must be decided and
proved from screenshots before this slice can close.

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
- Screenshot proof compares FileViewer, ReviewViewer, and DiffsHub/Pierre chrome
  placement. A subagent must inspect the screenshots and relevant source paths
  and report UX mismatches before this checkpoint can be accepted.
- Checkpoint commit is blocked until the parent has inspected the screenshot
  artifacts and the subagent/onlook report, not only the JSON proof file.

### Slice 06P.4 / 0.a.4: Pierre CodeView/File, Shiki, And Worker Proof

Render opened worktree files through Pierre CodeView/File. Shiki highlighting
and the Pierre worker pool must be active when `workers=on`. Make open-file
state explicit and visible: loading, ready, stale, unavailable, and refresh. If
the currently open file changes while open, show an update notification/refresh
affordance rather than silently replacing content.

Proof:

- Unit test for invalidation of the open descriptor.
- Browser proof observes stale/update affordance.
- Browser proof clicks refresh and returns to ready state.
- Browser proof rejects raw `<pre>` file rendering.
- Browser proof records Pierre CodeView/File and worker-ready markers.

### Slice 06P.5 / 0.a.5: Scroll Extent Canary

Keep DiffsHub-style scroll stability as a first-class canary. Tree and file
scroll extents must be based on declared row/line facts and remain stable across
selection and content hydration.

Proof:

- Browser proof records tree and content `scrollHeight`, `scrollTop`, selected
  row, and open path before and after file selection.
- Proof fails if scroll height collapses to only materialized visible content.
- Proof fails if selecting a file causes an unexplained jump outside threshold.

### Slice 06P.6 / 0.a.6: Negative Proof And Artifact

Write a JSON proof artifact and screenshots that can be inspected by parent
agent and reviewer lanes.

Proof artifact must include:

- observed route set: Files URL, Review diff URL, Review file-target URL, and
  legacy compatibility URL when exercised
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

- later PR-ready gate runs Agent Studio Bridge/WKWebView proof for the same
  protocol path
- proof includes bridge route boot, source/protocol identity, resource/content
  requests, event stream readiness, and Victoria/log marker correlation
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

This precursor remains implementation-review pending until a reviewer can
inspect the proof artifacts and confirm that the dev-server route set enters one
shared BridgeViewer app, covers Files, Review diff, and Review file-target
contexts, and cannot pass from the old compatibility URL or narrow verifier
alone.
