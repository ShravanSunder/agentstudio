# Gate 0.a Force-Lineage And Retry Implementation Re-Review Packet

Date: 2026-06-25
Mode: implementation
Review class: source-backed, plan-backed, risk-triggered
Whole-source trace: required
Source-backed verdict attempted: true

## Accepted Request

Gate 0.a is the first mandatory blocker before any downstream Bridge
transport/review work. The exact dev-server URL must render the intended
FileViewer product surface inside the shared BridgeViewer app:

```text
http://127.0.0.1:5173/?fixture=worktree&workers=on&scenario=current-worktree
```

Required user-facing model:

```text
Bridge Viewer App
  Viewer modes
    ReviewViewer: diffs / changesets / review package
    FileViewer: worktree file browsing / single file / live file view
  Shared UX contract
    primary code/file canvas on left
    Pierre file tree / right rail on right
    Shiki/Pierre rendering path
    same search/filter/selection chrome style
  Data sources
    mock fixture
    current worktree
    live changeset stream
    static diff/review package
    file content stream
```

This re-review is specifically for the follow-up fix after reviewers found that
the split-reset proof could still be satisfied by ordinary poll reloads and that
stale retry behavior could race against forced reset streams. Reviewers must
attack whether the exact URL can still pass while the forced reset lineage is not
actually delivered, while stale refresh retry is polluted by reset-stream state,
or while duplicate same-version replacement frames regress a successfully
refreshed file.

Do not accept proof that can pass through `WorktreeFileApp`, a route-local
FileViewer shell, route-local custom shell/tree, raw `<pre>` content,
Review/mock lineage, DOM-only ready markers, local extent synthesis,
bootstrap-only worker evidence, verifier-created untracked mutations,
self-reported URL strings, marker-only shared-shell assertions, unasserted
content-route requests, hidden-only provenance, unavailable body fetches,
stale reset sessions that cannot refresh, unrelated post-reset descriptors
unblocking stale pre-reset content, programmatic FileTree selection reopening
stale files, ordinary poll reloads masquerading as forced reset proof, forced
reset stream races inside stale retry proof, or duplicate same-version
replacement frames regressing a refreshed file.

## Source Spec

- Parent spec:
  `tmp/spec-workflows/2026-06-22-bridge-transport-streaming-spec/spec.md`
- Review protocol spec:
  `tmp/spec-workflows/2026-06-22-bridge-transport-streaming-spec/review-protocol.md`
- Worktree/File protocol spec:
  `tmp/spec-workflows/2026-06-22-bridge-transport-streaming-spec/worktree-file-surface-protocol.md`
- Reconciliation review:
  `tmp/spec-workflows/2026-06-22-bridge-transport-streaming-spec/reconciliation-review-2026-06-24.md`

## Source Plan

- Implementation plan:
  `tmp/plan-workflows/2026-06-24-bridge-transport-review-pr-ready-implementation-plan/implementation-plan.md`
- Gate 0 ticket:
  `tmp/plan-workflows/2026-06-24-bridge-transport-review-pr-ready-implementation-plan/tickets/00-gate0-worktree-product-e2e.md`
- Workflow details:
  `tmp/workflow-state/2026-06-24-bridge-transport-review-pr-ready/details.md`
- Workflow transition log:
  `tmp/workflow-state/2026-06-24-bridge-transport-review-pr-ready/events.jsonl`

## Implementation Scope

Current working-tree checkpoint under review. Commit hash should be filled in
after local commit.

Changed implementation/test/proof files:

- `BridgeWeb/scripts/verify-bridge-viewer-worktree-dev-server.ts`
- `BridgeWeb/src/app/bridge-app-dev-worktree.ts`
- `BridgeWeb/src/app/bridge-app-dev-worktree.unit.test.ts`
- `BridgeWeb/src/components/ui/dropdown-menu.tsx`
- `BridgeWeb/src/file-viewer/bridge-file-viewer-app.tsx`
- `BridgeWeb/src/file-viewer/bridge-file-viewer-app.unit.test.tsx`
- `tmp/workflow-state/2026-06-24-bridge-transport-review-pr-ready/details.md`
- `tmp/workflow-state/2026-06-24-bridge-transport-review-pr-ready/events.jsonl`

Key implementation changes to verify against code, not summary:

- Dev worktree force reload diagnostics are force-specific. The verifier waits
  for `bridgeWorktreeDevLastReloadRequest = force-split-reset`,
  `bridgeWorktreeDevLastForceSplitReloadStatus = delivered`, and the expected
  force split-reset source cursor.
- The stale refresh proof uses ordinary incremental reloads instead of forced
  split-reset reloads. Forced lineage and retry behavior are separate proofs.
- FileViewer explicit refresh keeps the latest known descriptor while
  refreshing.
- FileViewer ignores invalidation/replacement frames that identify the same
  content version as the currently displayed descriptor, so duplicate frames
  cannot regress a successful retry to stale.
- Dropdown menu prop types derive from actual React components with
  `ComponentProps<typeof ...>` so BridgeWeb type-aware lint stays green without
  casts.

## Proof Claims

Focused force-lineage/runtime/app tests:

```bash
pnpm --dir BridgeWeb exec vitest run src/app/bridge-app-dev-worktree.unit.test.ts src/file-viewer/bridge-file-viewer-app.unit.test.tsx src/worktree-file-surface/worktree-file-surface-runtime.integration.test.ts --reporter verbose
```

Claimed result: exit 0, 3 files passed, 24 tests passed.

Typecheck:

```bash
pnpm --dir BridgeWeb exec tsc --noEmit
```

Claimed result: exit 0.

BridgeWeb quality:

```bash
pnpm --dir BridgeWeb run check
```

Claimed result: exit 0, with existing verifier `no-await-in-loop` warnings only.

Exact dev-server product proof:

```bash
pnpm --dir BridgeWeb run test:dev-server:worktree
```

Claimed result: exit 0.

Artifact:
`tmp/bridge-viewer-worktree-dev-server/2026-06-25T06-49-27-224Z/worktree-dev-server-proof.json`

Screenshots:

- `tmp/bridge-viewer-worktree-dev-server/2026-06-25T06-49-27-224Z/worktree-file-ready.png`
- `tmp/bridge-viewer-worktree-dev-server/2026-06-25T06-49-27-224Z/worktree-file-search-result.png`
- `tmp/bridge-viewer-worktree-dev-server/2026-06-25T06-49-27-224Z/worktree-file-stale-refresh.png`

Key artifact fields to verify:

```text
result.descriptorCount = 456
result.selectedDisplayPath = BridgeWeb/pnpm-lock.yaml
result.selectedLineCount = 6658
result.sharedShellProof.appOwner = BridgeApp
result.sharedShellProof.sharedShellOwner = BridgeViewerAppShell
result.sharedShellProof.shellOwner = BridgeViewerApp.FileViewer
result.sharedShellProof.codeOwner = CodeView.file
result.sharedShellProof.treeOwner = FileTree
result.sharedShellProof.sidebarIsRight = true
result.sharedShellProof.shikiRendering = pierre
result.sharedShellProof.workerPoolState = ready
result.sharedShellProof.workerDiagnosticFileSuccessCount = 2
result.substituteGuardProof.standaloneWorktreeFileAppCount = 0
result.substituteGuardProof.reviewEmptyShellCount = 0
result.splitResetReplacementProof.proofPath = .mise.toml
result.splitResetReplacementProof.devReloadRequest = force-split-reset
result.splitResetReplacementProof.devReloadStatus = delivered
result.splitResetReplacementProof.devReloadFrameKinds starts with
  worktree.reset, worktree.snapshot
result.splitResetReplacementProof.preDispatchContentRouteHitCount = 0
result.splitResetReplacementProof.postReplacementContentRouteHitCount = 0
result.splitResetReplacementProof.postRefreshContentRouteHitCount = 1
result.splitResetReplacementProof.replacementContentRouteHitCount = 1
result.splitResetReplacementProof.selectedContentStateAfterReset = stale
result.staleRefreshProof.refreshFetchHitsBeforeClick = 0
result.staleRefreshProof.refreshFetchHitsAfterFirstClick = 1
result.staleRefreshProof.refreshFetchHitsAfterSecondClick = 2
result.staleRefreshProof.refreshReturnedReady = true
result.productControlsProof.unavailableOpenProof.contentRouteHitCount = 0
```

Live dev server state at packet creation:

```text
Vite dev server expected live on 127.0.0.1:5173 for human inspection.
```

## Must-Verify Source Obligations

Use this matrix shape in the review output:

```text
source_obligation_id
source_anchor
source_requirement_or_boundary
plan_anchor
implementation_anchor
proof_anchor
reachability_status
coverage_status
false_substitute_risk
candidate_deviation_bucket
candidate_route_target
notes
```

Obligations:

1. `gate0a-shared-app-shell`
   - Worktree/File route must enter `BridgeApp` file mode and render
     `BridgeViewerApp.FileViewer` inside the shared `BridgeViewerAppShell`.
   - It must not mount a second app or route-local shell.

2. `gate0a-pierre-rendering`
   - FileViewer must use Pierre `CodeView.file`, Pierre `FileTree` right rail,
     Shiki/Pierre rendering, and worker-backed file highlighting.

3. `gate0a-forced-split-reset-lineage`
   - Exact URL proof must prove the forced split-reset request, delivered status,
     expected source cursor, and `worktree.reset -> worktree.snapshot` lineage.
   - Ordinary poll reloads must not satisfy this proof.

4. `gate0a-content-data-plane`
   - Selected fetchable file content must route through the dev-server
     `/__bridge-worktree/file-content/<handle>` front door with asserted hits.
   - Unavailable descriptors must not fetch bodies.
   - Replacement content after a source-less reset must not be fetched before
     explicit refresh.

5. `gate0a-stale-refresh-retry`
   - Failed explicit refresh keeps stale body visible and retryable.
   - Successful retry returns to ready.
   - Retry proof must not depend on forced split-reset stream behavior.

6. `gate0a-duplicate-replacement-stability`
   - Duplicate replacement descriptors for the same content version must not
     regress an already refreshed file from ready back to stale.

7. `gate0a-controls-and-filters`
   - Search, regex, fetchable/unavailable filters must operate against actual
     rendered Pierre rows, not status text or synthetic counts only.

## Required Verdict Format

Return P0-P3 findings first. Each finding needs:

- severity
- file and line reference
- exact source/proof obligation violated
- how the current proof can still pass while product behavior is wrong
- minimal fix or proof gap

If there are no P0-P2 findings, explicitly say so and list remaining P3/residual
risks. Gate 1 may not start from this packet unless implementation review passes
or the human explicitly accepts the remaining risk.
