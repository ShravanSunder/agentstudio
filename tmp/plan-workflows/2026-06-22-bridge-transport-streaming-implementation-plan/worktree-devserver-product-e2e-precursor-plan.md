# Worktree Dev-Server Product E2E Precursor Plan

Date: 2026-06-24
Status: Gate 0.a Vite/dev-server proof complete after shared-app boundary proof pass; pending implementation re-review
Ticket: 06P / Gate 0.a Shared FileViewer Renderer Precursor

## Current Proof Status

Gate 0.a Vite/dev-server proof is green as of 2026-06-25 00:04 -04:00 after
the shared-app boundary proof pass.

- Canonical command:
  `pnpm --dir BridgeWeb run test:dev-server:worktree`
- Exact URL:
  `http://127.0.0.1:5173/?fixture=worktree&workers=on&scenario=current-worktree`
- JSON artifact:
  `tmp/bridge-viewer-worktree-dev-server/2026-06-25T04-04-26-634Z/worktree-dev-server-proof.json`
- Screenshots:
  - `tmp/bridge-viewer-worktree-dev-server/2026-06-25T04-04-26-634Z/worktree-file-ready.png`
  - `tmp/bridge-viewer-worktree-dev-server/2026-06-25T04-04-26-634Z/worktree-file-search-result.png`
  - `tmp/bridge-viewer-worktree-dev-server/2026-06-25T04-04-26-634Z/worktree-file-stale-refresh.png`
- Supporting proof:
  - `pnpm --dir BridgeWeb exec vitest run scripts/dev-server/bridge-worktree-dev-provider.integration.test.ts src/worktree-file-surface/worktree-file-surface-runtime.integration.test.ts src/file-viewer/bridge-file-viewer-app.unit.test.tsx src/app/bridge-app-protocol-router.unit.test.tsx src/review-viewer/workers/pierre/bridge-pierre-worker-pool.unit.test.tsx scripts/verify-bridge-viewer-worktree-dev-server-paths.unit.test.ts --reporter verbose`
    passed: 6 files, 46 tests
  - `pnpm --dir BridgeWeb exec tsc --noEmit` passed
  - `pnpm --dir BridgeWeb run check` passed with existing verifier
    `no-await-in-loop` warnings only
  - `pnpm --dir BridgeWeb run test:browser:integration -- src/review-viewer/test-support/bridge-viewer-browser.integration.browser.test.tsx -t "large fixture programmatic file reveal uses bounded CodeView motion"`
    passed: 2 files, 34 tests

The verifier now fails closed against the old second-app path and proves the
exact worktree URL renders FileViewer inside the shared BridgeViewer shell with
Pierre FileTree/right rail, Pierre CodeView/File, Shiki rendering, worker-backed
highlighting request, product controls, stale/refresh, and stable tree/content
scroll extents. It also asserts the observed browser URL, shared-shell DOM
containment, `BridgeApp` ownership, no router-local direct FileViewer mount,
worker file-success baseline and selected-descriptor cache key, descriptor-path
containment before verifier writes, collision-safe verifier restore, nontrivial
available/unavailable filter behavior, visible stale notice geometry, and
retryable stale state after a failed explicit refresh with request counts
`0 -> 1 -> 2`.

Native Agent Studio Bridge/WKWebView proof remains outside this precursor and
is still required before PR-ready.

## Historical Problem

The current worktree dev URL boots a Worktree/File protocol route, but it is
reaching a second app path instead of the shared BridgeViewer shell. The exact
URL is:

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

Latest Gate 0.a red evidence:

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

Fresh contrast proof:

- `pnpm --dir BridgeWeb run test:dev-server:worktree` passed on 2026-06-24 and
  wrote `tmp/bridge-viewer-worktree-dev-server/2026-06-24T12-51-13-807Z`.
- That green result proves the existing narrow route/data/scroll contract only.
  It does not satisfy this precursor because it does not require search, regex,
  filter/status controls, product-shell provenance, or negative-substitute
  assertions.

This means prior proof only establishes a narrow route/data-loading regression.
It does not prove FileViewer product readiness because it can pass while the
exact worktree URL is still a standalone mini-app with custom rendering.

## Blocking Outcome

Before downstream Bridge transport, scheduler, renderer, telemetry, or Ticket 02
closure claims continue, the exact URL must render and operate FileViewer inside
the shared BridgeViewer shell with browser proof.

The precursor is complete only when Playwright evidence proves all required
behaviors and fails if the route regresses to a mock/raw/minimal substitute or
to the standalone `WorktreeFileApp`/raw `<pre>` path.

This precursor is the fast-loop Vite/dev-server product proof. It does not
replace Agent Studio Bridge/WKWebView runtime proof for the full PR-ready epic.
The later implementation plan must add native app-hosted Bridge proof with
marker-correlated evidence that the same protocol/source/resource behavior works
through Swift, WKWebView, the Bridge host wiring, and packaged app assets.

## Scope

In scope:

- `BridgeWeb/src/worktree-file-surface/`
- `BridgeWeb/src/review-viewer/shell/`
- `BridgeWeb/src/review-viewer/code-view/`
- `BridgeWeb/src/review-viewer/workers/pierre/`
- `BridgeWeb/src/features/worktree-file/`
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

The Worktree/File product route must expose these observable regions:

1. Source/status header
   - Shows route identity and source provenance.
   - DOM exposes protocol/source facts for Playwright:
     `worktree-file`, source id, worktree/repo id, generation or revision token.

2. Shared BridgeViewer shell
   - Uses the same product shell contract as ReviewViewer/FileViewer.
   - Primary code/file canvas is on the left.
   - Pierre FileTree/right rail is on the right.
   - The exact URL cannot mount `WorktreeFileApp` or a route-local custom shell.

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

Add or tighten the Playwright verifier so it fails against the current route for
the right reason: the exact worktree URL mounts the standalone `WorktreeFileApp`
path and bypasses Pierre FileTree, Pierre CodeView/File, Shiki, and workers.

Proof:

- Run the verifier before implementation and capture failure.
- Failure message names the second-app/custom-renderer violation or at least one
  missing shared-shell/Pierre renderer requirement.
- Failure is not a timeout-only assertion.
- Add a focused router/bootstrap composition assertion showing the
  `worktree-file` route currently reaches the forbidden second-app path; this
  proof must go green only when the route resolves directly to shared
  BridgeViewer FileViewer ownership.

### Slice 06P.2 / 0.a.2: Source Adapter Into Shared FileViewer

Route worktree data through the shared BridgeViewer FileViewer mode instead of
`WorktreeFileApp`. Worktree remains a source adapter/provider. FileViewer owns
selection/open-file UI state and consumes validated Worktree/File descriptors.
Keep large bodies out of Zustand/state and render only references plus
materialized content.

Proof:

- Unit/component test for provenance derivation.
- Unit/component test for router/bootstrap composition: exact `worktree-file`
  protocol input resolves to shared BridgeViewer FileViewer, not
  `WorktreeFileApp` or an equivalent wrapper around it.
- Browser assertion for protocol/source DOM attributes.
- Screenshot shows BridgeViewer/FileViewer shell, not raw/minimal/second-app
  route.

### Slice 06P.3 / 0.a.3: Shared Shell, Right Rail, Query And Filter Controls

Add or reuse tree/file search, regex mode, and filter/status controls inside the
shared BridgeViewer shell. Filtering should operate on descriptors and metadata,
not file bodies. The rail side must match the shared UX contract: primary
content left, Pierre FileTree/right rail right.

Proof:

- Unit tests cover plain text search, regex search, invalid regex handling, and
  status/filter composition.
- Positive proof that the right rail is Pierre FileTree: use a composition test
  or a browser-visible marker from the shared Pierre tree path. A custom tree
  with equivalent row counts does not satisfy this slice.
- Browser proof types a query, toggles regex, changes a filter, and observes a
  stable state/result transition.
- Browser proof records before/after visible row counts or sampled visible path
  sets for each query/filter interaction so decorative controls cannot pass.

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

- exact URL
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

- exact current-worktree URL
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
current-worktree URL
        │
        ▼
Vite dev bootstrap
        │
        ├─ sets protocol = worktree-file
        ├─ installs Worktree dev backend
        │
        ▼
Worktree/File product shell
        │
        ├─ source/status header
        ├─ query/filter controls
        ├─ tree pane from descriptors + tree size facts
        └─ file pane from selected descriptor + materialized content
              │
              ▼
      descriptor resource fetch
              │
              ▼
      content ready / stale / unavailable
```

## Gate

This precursor remains implementation-review pending until a reviewer can
inspect the proof artifacts and confirm that the exact dev-server URL is the
intended Worktree/File product surface. Passing the old narrow verifier is not
enough.
