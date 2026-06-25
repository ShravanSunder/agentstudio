# Gate 0.a Reset Lineage And Quiescence Implementation Re-Review Packet

Date: 2026-06-25
Mode: implementation
Review class: source-backed, plan-backed, risk-triggered
Whole-source trace: required

## Accepted Request

Gate 0.a is the first mandatory blocker before downstream Bridge transport,
Review protocol, scheduler, and Pierre renderer work can continue.

The exact dev-server URL must render the product FileViewer inside the shared
Bridge Viewer app:

```text
http://127.0.0.1:5173/?fixture=worktree&workers=on&scenario=current-worktree
```

User-approved architecture:

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

Important framing: `ReviewViewer` and `FileViewer` are modes of one Bridge
Viewer app. `worktree` is a data source, not permission to mount a separate
application. A `WorktreeFileApp`, route-local file shell, route-local tree, raw
`<pre>` renderer, or custom non-Pierre file viewer is a contract violation for
Gate 0.a even when it displays correct bytes.

This re-review is for the latest follow-up after the previous reviewers found
four false-green paths:

1. Dev-backend pause could acknowledge while an ordinary poll was still in
   flight, so a poll could masquerade as a forced split-reset transition.
2. Malformed frame `sequence` or `generation` tokens were not rejected.
3. Forced reset replacement frames used hardcoded stream/generation lineage
   rather than one accepted stream/generation with continuous ordering.
4. Exact URL proof did not prove stale Refresh was disabled before replacement
   descriptor readiness and enabled only after readiness.

Reviewers must verify those issues are fixed in code and in proof. Do not
accept summary claims without tracing source, tests, and the artifact.

## Source Spec And Plan

- Parent spec:
  `tmp/spec-workflows/2026-06-22-bridge-transport-streaming-spec/spec.md`
- Review protocol spec:
  `tmp/spec-workflows/2026-06-22-bridge-transport-streaming-spec/review-protocol.md`
- Worktree/File protocol spec:
  `tmp/spec-workflows/2026-06-22-bridge-transport-streaming-spec/worktree-file-surface-protocol.md`
- Reconciliation review:
  `tmp/spec-workflows/2026-06-22-bridge-transport-streaming-spec/reconciliation-review-2026-06-24.md`
- Implementation plan:
  `tmp/plan-workflows/2026-06-24-bridge-transport-review-pr-ready-implementation-plan/implementation-plan.md`
- Gate 0 ticket:
  `tmp/plan-workflows/2026-06-24-bridge-transport-review-pr-ready-implementation-plan/tickets/00-gate0-worktree-product-e2e.md`
- Workflow details:
  `tmp/workflow-state/2026-06-24-bridge-transport-review-pr-ready/details.md`
- Workflow transitions:
  `tmp/workflow-state/2026-06-24-bridge-transport-review-pr-ready/events.jsonl`

## Implementation Scope

Latest commit under review:

```text
412be0bf Fix Gate 0a reset lineage quiescence
```

Review the latest fix relative to the previously reviewed authority packet:

```text
1072ea43..412be0bf
```

Changed files in the latest fix:

- `BridgeWeb/scripts/verify-bridge-viewer-worktree-dev-server.ts`
- `BridgeWeb/src/app/bridge-app-dev-worktree.ts`
- `BridgeWeb/src/app/bridge-app-dev-worktree.unit.test.ts`
- `tmp/workflow-state/2026-06-24-bridge-transport-review-pr-ready/details.md`
- `tmp/workflow-state/2026-06-24-bridge-transport-review-pr-ready/events.jsonl`

Relevant prior files to inspect because they define the Gate 0.a product route:

- `BridgeWeb/src/app/bridge-app.tsx`
- `BridgeWeb/src/app/bridge-app-protocol-router.tsx`
- `BridgeWeb/src/app/bridge-app-dev-worktree.ts`
- `BridgeWeb/src/file-viewer/bridge-file-viewer-app.tsx`
- `BridgeWeb/src/app/bridge-viewer-app-shell.tsx`
- `BridgeWeb/src/review-viewer/code-view/bridge-file-viewer-code-panel.tsx`
- `BridgeWeb/src/review-viewer/trees/bridge-file-viewer-tree-panel.tsx`
- `BridgeWeb/src/worktree-file-surface/worktree-file-surface-runtime.ts`
- `BridgeWeb/src/review-viewer/workers/pierre/bridge-pierre-worker-pool.tsx`

Key latest changes to verify against source, not summary:

- Dev backend pause reports `pausing` while a reload is in flight and publishes
  `paused` only after the in-flight reload is idle.
- Forced split-reset replacement frames derive `streamId`, `generation`, and
  next `sequence` from previously accepted frames.
- Replacement reset/snapshot/descriptor frames preserve one stream/generation
  lineage and continuous sequence ordering.
- Malformed `sequence` or `generation` values are rejected with
  `Number.isSafeInteger` checks.
- Exact URL verifier has a deterministic dev-only replacement delay knob so it
  can observe stale Refresh disabled before descriptor readiness.
- Exact URL verifier records and asserts
  `refreshDisabledAtFirstStale=true` and
  `refreshEnabledAfterReplacement=true`.

## Proof Claims

Focused tests:

```bash
pnpm --dir BridgeWeb exec vitest run src/app/bridge-app-dev-worktree.unit.test.ts src/file-viewer/bridge-file-viewer-app.unit.test.tsx src/worktree-file-surface/worktree-file-surface-runtime.integration.test.ts --reporter verbose
```

Claimed result: exit 0, 3 files passed, 27 tests passed.

Typecheck:

```bash
pnpm --dir BridgeWeb exec tsc --noEmit
```

Claimed result: exit 0.

BridgeWeb quality:

```bash
pnpm --dir BridgeWeb run check
```

Claimed result: exit 0, with existing verifier `no-await-in-loop` warnings
only.

Exact dev-server product proof:

```bash
pnpm --dir BridgeWeb run test:dev-server:worktree
```

Claimed result: exit 0.

Artifact:

```text
tmp/bridge-viewer-worktree-dev-server/2026-06-25T08-14-48-622Z/worktree-dev-server-proof.json
```

Repo lint:

```bash
mise run lint
```

Claimed result: exit 0.

Live server state at packet creation:

```text
127.0.0.1:5173 LISTEN node PID 43623
```

Freshness update after packet creation:

```text
pnpm --dir BridgeWeb run test:dev-server:worktree
exit 0
proofArtifactPath =
  tmp/bridge-viewer-worktree-dev-server/2026-06-25T08-14-48-622Z/worktree-dev-server-proof.json
```

Post-review fix update:

```text
The implementation now stores raw provider frames for descriptor comparison and
accepted emitted frames for lineage continuation.

The exact URL verifier now requires:
  - exactly one selected-content route hit during target selection
  - exactly one app root, shell, code canvas, and sidebar
  - center-point ownership for the visible app root, shell, code canvas, and
    sidebar
  - strict integer parsing for reset generation/sequence/count diagnostics
```

## Artifact Facts To Verify

The artifact must be independently inspected. Expected facts include:

```text
devServerUrl =
  http://127.0.0.1:5173/?fixture=worktree&workers=on&scenario=current-worktree

result.sharedShellProof.appOwner = BridgeApp
result.sharedShellProof.sharedShellOwner = BridgeViewerAppShell
result.sharedShellProof.shellOwner = BridgeViewerApp.FileViewer
result.sharedShellProof.sharedShellMode = file
result.sharedShellProof.codeOwner = CodeView.file
result.sharedShellProof.treeOwner = FileTree
result.sharedShellProof.sidebarIsRight = true
result.sharedShellProof.shikiRendering = pierre
result.sharedShellProof.workerPoolState = ready
result.sharedShellProof.workerDiagnosticLastSuccessRequestType = file

result.substituteGuardProof.standaloneWorktreeFileAppCount = 0
result.substituteGuardProof.reviewEmptyShellCount = 0

result.selectedContentRouteProof.hitCount = 1
result.selectedContentRouteProof.selectedResourceUrlUsesDevServerFrontDoor =
  true

result.treeTotalSizeSource = providerFacts
result.scrollExtentCanary.exactSizeTolerancePass = true
result.scrollExtentCanary.stableAnchorPass = true
result.scrollExtentCanary.contentHeightDeltaPixels = 0

result.splitResetReplacementProof.devReloadFrameKinds starts with
  worktree.reset, worktree.snapshot
result.splitResetReplacementProof.devReloadFrameGenerations are all 2
result.splitResetReplacementProof.devReloadFrameStreamIds are all
  worktree-file:bridge-worktree-dev-pane
result.splitResetReplacementProof.devReloadFrameSequences are strictly
  increasing
result.splitResetReplacementProof.preDispatchContentRouteHitCount = 0
result.splitResetReplacementProof.postReplacementContentRouteHitCount = 0
result.splitResetReplacementProof.postRefreshContentRouteHitCount = 1
result.splitResetReplacementProof.refreshDisabledAtFirstStale = true
result.splitResetReplacementProof.refreshEnabledAfterReplacement = true
```

## Must-Verify Obligations

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

1. `gate0a-one-bridge-viewer-app`
   - Worktree/File route must enter the shared Bridge Viewer app and render the
     `FileViewer` mode.
   - Worktree must be a data source, not a separate application boundary.

2. `gate0a-pierre-fileviewer`
   - FileViewer must use Pierre `CodeView` file rendering, Pierre `FileTree`
     right rail, Shiki/Pierre highlighting, and worker-backed file rendering.

3. `gate0a-dev-pause-quiescence`
   - Pausing must be an actual quiescence barrier for in-flight reload work.
   - Ordinary poll reloads must not satisfy forced split-reset proof.

4. `gate0a-reset-lineage`
   - Forced replacement frames must use one accepted stream id, one replacement
     generation, and strictly increasing safe-integer sequences.
   - Malformed sequence/generation values must be rejected.

5. `gate0a-refresh-readiness`
   - Stale notification may appear immediately.
   - Refresh must be disabled until a replacement descriptor is materialized.
   - Replacement bytes must not be fetched before explicit Refresh.

6. `gate0a-real-proof`
   - Exact URL proof must be headless-browser proof against the real Vite route,
     not unit-only proof, mock-only proof, marker-only proof, self-reported URL
     strings, or raw payload text.

## Non-Goals And Known Deferred Work

- This is Vite/dev-server product proof for Gate 0.a.
- Native Agent Studio `WKWebView` / `agentstudio://` proof remains required
  before PR-ready.
- Gate 1 generic transport/protocol/scheduler implementation must not start
  until Gate 0.a implementation re-review passes or the human explicitly accepts
  the remaining risk.
- The dev-only delayed replacement knob is allowed only as proof instrumentation
  for deterministic stale-disabled observation. It must not become product
  behavior or mask missing readiness logic.

## Reviewer Instructions

Return findings first, ordered by severity. For each accepted finding, include:

```text
severity: P0/P1/P2/P3
file:line
source obligation violated
why this can pass falsely or break the product requirement
exact proof gap or code path
minimal recommended correction
```

If no blocking findings remain, say that directly and list residual risk
separately. Residual risk is not a pass blocker unless it violates Gate 0.a.
