# Ticket 00: Gate 0 Worktree/File Product E2E

Status: Gate 0.a Vite/dev-server reviewer fixes complete; pending implementation-review-swarm
Depends on: accepted Bridge transport spec review
Blocks: Gates 1-4 implementation claims

## Deliverable

Make the exact Vite dev-server URL render and operate FileViewer inside the
shared BridgeViewer shell:

```text
http://127.0.0.1:5173/?fixture=worktree&workers=on&scenario=current-worktree
```

The route must not pass as a Review mock route, raw frame dump, concatenated
path dump, standalone `WorktreeFileApp`, route-local custom shell, custom file
tree, or minimal two-pane list plus `<pre>` renderer.

## Proof Surface Boundary

This ticket proves the Vite dev-server/browser product loop only. It is still a
real product proof gate, not a mock gate: the verifier must launch or attach to
the dev server, open the exact URL, interact with the rendered page, capture
screenshots and JSON diagnostics, and assert visible product behavior.

Native Agent Studio Bridge/WKWebView proof is deliberately not satisfied here.
Ticket 04 must rerun equivalent product behavior through the native app-hosted
Bridge path before PR-ready.

## Current Proof Status

Gate 0.a Vite/dev-server proof is green as of 2026-06-25 00:46 -04:00
after shared-app implementation-review reduction fixes.

Proof:

- `pnpm --dir BridgeWeb run test:dev-server:worktree`
  - exit: 0
  - exact URL:
    `http://127.0.0.1:5173/?fixture=worktree&workers=on&scenario=current-worktree`
  - artifact:
    `tmp/bridge-viewer-worktree-dev-server/2026-06-25T04-46-20-464Z/worktree-dev-server-proof.json`
  - screenshots:
    - `tmp/bridge-viewer-worktree-dev-server/2026-06-25T04-46-20-464Z/worktree-file-ready.png`
    - `tmp/bridge-viewer-worktree-dev-server/2026-06-25T04-46-20-464Z/worktree-file-search-result.png`
    - `tmp/bridge-viewer-worktree-dev-server/2026-06-25T04-46-20-464Z/worktree-file-stale-refresh.png`
- `pnpm --dir BridgeWeb exec vitest run src/app/bridge-app-protocol-router.contract.unit.test.tsx src/file-viewer/bridge-file-viewer-app.unit.test.tsx src/worktree-file-surface/worktree-file-surface-runtime.integration.test.ts scripts/dev-server/bridge-worktree-dev-provider.integration.test.ts --reporter verbose`
  passed: 4 files, 24 tests.
- `pnpm --dir BridgeWeb exec tsc --noEmit` passed.
- `pnpm --dir BridgeWeb run check` passed with existing verifier
  `no-await-in-loop` warnings only.

The canonical verifier now proves shared BridgeViewer FileViewer ownership,
Pierre FileTree/right rail ownership, Pierre CodeView/File ownership, Shiki
rendering, worker-backed highlighting request plus ready worker pool/theme
state, search/regex/filter controls against actual rendered Pierre rows,
provider-backed tree visual extent facts, stale/refresh, tree/content scroll
extent stability, selected content requests through the dev-server content
front door, visible source provenance, unavailable descriptor opens without
content fetches, and negative substitute guards against `WorktreeFileApp`,
route-local custom shell/tree, raw `<pre>` content, mock/review lineage, and
DOM-only content-ready markers.

The earlier `2026-06-25T01-45-02-791Z` artifact is superseded because
implementation reviewers found worker, row-filter, and provider-extent
false-green gaps.

The later `2026-06-25T02-16-36-219Z` artifact is also superseded because
reviewers found two remaining gaps: stale-refresh proof mutated the worktree by
creating its own untracked file, and failed explicit refresh could blank stale
content into failed state. The current artifact uses an existing tracked file
and restores it, and the added FileViewer unit regression proves failed refresh
keeps stale content visible and retryable.

The `2026-06-25T04-04-26-634Z` and `2026-06-25T04-33-31-259Z` artifacts are
superseded because implementation
re-review found remaining proof gaps: router entry could be inferred from DOM
markers instead of proving `BridgeApp viewerMode="file"` directly; selected
content route hits were not asserted; visible provenance was hidden in
attributes only; unavailable opens were not clicked/proven; unavailable deleted
text descriptors were mislabeled as binary; and source-reset replacement
descriptors could leave an open session non-refreshable. The latest focused
runtime test also proves unrelated post-reset descriptors cannot unblock stale
pre-reset content. The current artifact and focused tests close those gaps.

This does not satisfy native Agent Studio Bridge/WKWebView proof. That remains
required before PR-ready.

## Historical Red Evidence

- `tmp/bridge-worktree-devserver-proof-recovery/current-worktree-route-after-3s.png`
- `tmp/bridge-worktree-devserver-proof-recovery/current-worktree-route-diagnostics.json`
- Backend returned 432 frames and 431 rows.
- Browser protocol attribute was `worktree-file`.
- Tree/content rendered after wait.
- Required product controls were absent:
  - search input: 0
  - regex toggle: 0
  - filter/status controls: 0
- Current Gate 0.a failure is sharper than missing controls: the exact route
  reaches `WorktreeFileApp`, which owns a custom file list and raw `<pre>`
  content path instead of the shared BridgeViewer/Pierre FileViewer path.

Old narrow green proof:

- `pnpm --dir BridgeWeb run test:dev-server:worktree`
- Latest observed artifact:
  `tmp/bridge-viewer-worktree-dev-server/2026-06-24T12-51-13-807Z`
- This proof is retained as a regression signal only. It is not Gate 0 proof.

## Vertical Slices

### 00.1 Red Product Verifier

Add or tighten the browser verifier so it fails against the current route for
missing shared FileViewer/Pierre behavior.

Proof:

- Verifier fails before product implementation.
- Failure names missing product controls, second-app route violation,
  Pierre/Shiki/worker bypass, or shared-shell contract violation.
- Failure is not a timeout-only failure.
- Unit/component proof asserts the `worktree-file` router/bootstrap composition
  resolves to the shared BridgeViewer FileViewer owner, not `WorktreeFileApp`
  and not an equivalent wrapper around `WorktreeFileApp`.
- Negative assertions reject Review mock route, raw payload/frame dump,
  standalone `WorktreeFileApp`, route-local custom shell, custom tree, and
  minimal list plus `<pre>`.

### 00.2 Source Adapter Into Shared FileViewer

Route worktree data through FileViewer inside the shared BridgeViewer shell.
Worktree remains a source adapter/provider, not a UI app. Render source/status
provenance from Worktree/File protocol frames and keep large bodies out of
Zustand.

Proof:

- Unit/component proof for provenance derivation.
- Router/bootstrap composition proof that the exact `worktree-file` protocol
  path cannot dispatch through `WorktreeFileApp`.
- Browser proof for protocol/source DOM attributes.
- Screenshot shows shared BridgeViewer/FileViewer shell, not raw/minimal or
  second-app route.

### 00.3 Shared Shell, Right Rail, Query, Regex, And Filter Controls

Implement or reuse tree/file search, regex mode, and filter/status controls over
descriptors and metadata, not file bodies. The visible shell must place the
primary code/file canvas on the left and Pierre FileTree/right rail on the right.

Proof:

- Unit tests for plain search, regex search, invalid regex, and status/filter
  composition.
- Positive composition or browser proof for the right rail identity: the rail is
  the shared Pierre FileTree path with a machine-checkable marker, not a custom
  tree that merely looks similar.
- Browser proof changes query, regex mode, and filters.
- JSON artifact records before/after visible row count or sampled visible path
  set, active filter tokens, regex-valid/error state, and fixture-specific
  visible result deltas.

### 00.4 Pierre CodeView/File, Shiki, Workers, Stale, And Refresh

Render open worktree files through Pierre CodeView/File with Shiki highlighting
and worker-backed highlighting when `workers=on`. Make open-file states visible:
loading, ready, stale, unavailable, refreshing. If an open file is invalidated,
show stale/update state and require explicit refresh before replacing content.

Proof:

- Unit/component proof for invalidation state.
- Browser proof records ready -> stale/update -> refresh -> ready.
- Screenshot/JSON evidence proves refresh is user-invoked, not silent
  replacement.
- Browser proof rejects raw `<pre>` file rendering and records Pierre
  CodeView/File plus worker-ready markers.

### 00.5 Stable Scroll Extent

Use declared tree row and file line/extent facts so scroll size remains stable
before and after content hydration.

Proof:

- Browser proof records tree/content scrollHeight, scrollTop, selected row/open
  path before and after selection/hydration.
- Proof fails if scroll height collapses to visible materialized content.
- Proof fails on unexplained jump outside threshold.

### 00.6 Artifact And Inspection Gate

Write a proof artifact and screenshots that reviewers can inspect without
trusting hidden test state.

Proof artifact includes:

- exact URL
- timestamp
- browser executable/channel
- protocol/source facts
- selected file and open state
- search/regex/filter states
- per-interaction result deltas
- stale/refresh transition
- tree/content scroll canaries
- screenshot paths
- explicit negative-substitute assertions
- explicit assertion that `WorktreeFileApp`, route-local custom shell, route-local
  custom tree, and raw `<pre>` body rendering were not reached
- explicit positive assertions that the FileViewer route used shared
  BridgeViewer ownership, Pierre FileTree/right rail ownership, Pierre
  CodeView/File ownership, Shiki rendering, and worker-backed highlighting when
  `workers=on`

Completion requires parent/human/reviewer inspection of the artifacts. A failed
or disconnected subagent review does not satisfy or invalidate this gate by
itself.

## Required Commands

Canonical Gate 0.a regression command:

```bash
pnpm --dir BridgeWeb run test:dev-server:worktree
```

Ticket 00 must upgrade this command in place so the old narrow green route can
no longer pass. Downstream tickets consume this command as the standing Gate
0.a regression gate.

Red/green browser verifier:

```bash
pnpm --dir BridgeWeb run test:dev-server:worktree
```

Focused route/composition proof:

```bash
pnpm --dir BridgeWeb run test -- <focused router/bootstrap/FileViewer composition tests>
```

Focused supporting tests:

```bash
pnpm --dir BridgeWeb run test -- <focused worktree/product tests>
pnpm --dir BridgeWeb run check
```

Repo quality before ticket close:

```bash
mise run lint
```

## Not In This Ticket

- Native Agent Studio Bridge/WKWebView proof. This is required before PR-ready
  but belongs in Gate 4 unless implementation work naturally exposes it earlier.
- Full Review renderer cutover.
- Generic transport core rewrite beyond what the product route needs to prove
  Gate 0.

phase_result: complete_pending_re_review
evidence: Gate 0.a Vite/dev-server proof is green with exact URL artifact, screenshots, reviewer-fix focused tests, provider-backed extent proof, worker file-success proof, rendered-row control proof, and stale refresh regression proof; native proof remains out of this ticket.
recommended_next_workflow: shravan-dev-workflow:implementation-review-swarm
recommended_transition_reason: Gate 0.a reviewer fixes should be re-reviewed before Gate 1 execution.
