# Gate 0.a Force Reset Authority Implementation Re-Review Packet

Date: 2026-06-25
Mode: implementation
Review class: source-backed, plan-backed, risk-triggered
Whole-source trace: required

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

This re-review is specifically for the follow-up fix after implementation
review found that the forced split-reset proof still had three ways to lie:

1. Source-less reset replacement frames could be emitted with invalid sequence
   lineage: reset at a high sequence followed by snapshot/descriptor frames at
   lower sequences.
2. The verifier could mutate a file while the ordinary dev poller was still
   running, allowing a poll update to masquerade as the forced split-reset
   transition.
3. The stale notice could expose Refresh before the replacement descriptor was
   materialized, allowing a user or verifier click to hit a non-refreshable
   reset state.

Reviewers must attack whether the exact URL can still pass while any of those
false-green paths remain.

Do not accept proof that can pass through `WorktreeFileApp`, a route-local
FileViewer shell, route-local custom shell/tree, raw `<pre>` content,
Review/mock lineage, DOM-only ready markers, local extent synthesis,
bootstrap-only worker evidence, verifier-created untracked mutations,
self-reported URL strings, marker-only shared-shell assertions, unasserted
content-route requests, hidden-only provenance, unavailable body fetches,
stale reset sessions that cannot refresh, unrelated post-reset descriptors
unblocking stale pre-reset content, programmatic FileTree selection reopening
stale files, ordinary poll reloads masquerading as forced reset proof,
out-of-order reset replacement sequences, Refresh clicks before descriptor
readiness, or unbounded proof output hiding failures.

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
- Workflow transition log:
  `tmp/workflow-state/2026-06-24-bridge-transport-review-pr-ready/events.jsonl`

## Implementation Scope

Commit under review:

```text
1072ea43 Fix Gate 0a force reset proof authority
```

Changed implementation/test/proof files:

- `BridgeWeb/scripts/verify-bridge-viewer-worktree-dev-server.ts`
- `BridgeWeb/src/app/bridge-app-dev-worktree.ts`
- `BridgeWeb/src/app/bridge-app-dev-worktree.unit.test.ts`
- `BridgeWeb/src/file-viewer/bridge-file-viewer-app.tsx`
- `BridgeWeb/src/file-viewer/bridge-file-viewer-app.unit.test.tsx`
- `tmp/workflow-state/2026-06-24-bridge-transport-review-pr-ready/details.md`
- `tmp/workflow-state/2026-06-24-bridge-transport-review-pr-ready/events.jsonl`

Key implementation changes to verify against code, not summary:

- Normal source-change reset and forced source-less reset paths rebase
  replacement surface frame sequences after the reset frame.
- Dev worktree diagnostics now publish forced split-reset frame sequences.
- The exact URL verifier pauses ordinary dev polling before mutating the proof
  file and resumes polling in `finally`.
- The exact URL verifier asserts force-specific delivery diagnostics and
  strictly increasing forced frame sequences.
- FileViewer disables stale Refresh until the latest descriptor for the open
  file is present in the current render state.
- The exact URL verifier waits for the stale Refresh button to become enabled
  before clicking it.
- The dev-server proof result no longer leaks full selected file text through
  stdout; console output is bounded to small frame samples while the full
  artifact remains on disk.

## Proof Claims

Focused force-lineage/runtime/app tests:

```bash
pnpm --dir BridgeWeb exec vitest run src/app/bridge-app-dev-worktree.unit.test.ts src/file-viewer/bridge-file-viewer-app.unit.test.tsx src/worktree-file-surface/worktree-file-surface-runtime.integration.test.ts --reporter verbose
```

Claimed result: exit 0, 3 files passed, 25 tests passed.

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
`tmp/bridge-viewer-worktree-dev-server/2026-06-25T07-21-13-935Z/worktree-dev-server-proof.json`

Key artifact fields to verify:

```text
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
result.substituteGuardProof.standaloneWorktreeFileAppCount = 0
result.substituteGuardProof.reviewEmptyShellCount = 0
result.splitResetReplacementProof.devReloadRequest = force-split-reset
result.splitResetReplacementProof.devReloadStatus = delivered
result.splitResetReplacementProof.devReloadFrameKinds starts with
  worktree.reset, worktree.snapshot
result.splitResetReplacementProof.devReloadFrameSequences is strictly
  increasing
result.splitResetReplacementProof.preDispatchContentRouteHitCount = 0
result.splitResetReplacementProof.postReplacementContentRouteHitCount = 0
result.splitResetReplacementProof.postRefreshContentRouteHitCount = 1
result.splitResetReplacementProof.replacementContentRouteHitCount = 1
```

Repo lint:

```bash
mise run lint
```

Claimed result: exit 0, swift-format OK, SwiftLint 0 violations,
AgentStudio architecture lint OK, release script verification passed.

Live dev server state at packet creation:

```text
Vite dev server expected live on 127.0.0.1:5173 for human inspection.
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

1. `gate0a-shared-app-shell`
   - Worktree/File route must enter `BridgeApp` file mode and render
     `BridgeViewerApp.FileViewer` inside the shared `BridgeViewerAppShell`.
   - It must not mount a second app or route-local shell.

2. `gate0a-pierre-rendering`
   - FileViewer must use Pierre `CodeView.file`, Pierre `FileTree` right rail,
     Shiki/Pierre rendering, and worker-backed file highlighting.

3. `gate0a-forced-split-reset-lineage`
   - Exact URL proof must prove forced request, delivered status, expected
     source cursor, reset/snapshot lineage, and strictly increasing frame
     sequences.
   - Ordinary poll reloads must not satisfy this proof.

4. `gate0a-refresh-readiness`
   - Stale notification is allowed immediately.
   - Refresh must remain disabled until a replacement descriptor is present.
   - Exact URL proof must wait for enabled Refresh before clicking.

5. `gate0a-content-data-plane`
   - Selected fetchable file content must route through the dev-server
     `/__bridge-worktree/file-content/<handle>` front door with asserted hits.
   - Replacement content after source-less reset must not be fetched before
     explicit refresh.

6. `gate0a-proof-quality`
   - Console proof must be bounded and inspectable.
   - Full details may live in the artifact, but stdout must not hide failures
     behind huge file text or full frame dumps.

## Required Verdict Format

Return P0-P3 findings first. Each finding needs:

- severity
- file and line reference
- exact source/proof obligation violated
- how the current proof can still pass while product behavior is wrong
- minimal fix or proof gap

If no findings, state:

```text
No P0-P3 findings for Gate 0.a force reset authority follow-up.
Residual risk: <short list>
Gate 1 status recommendation: proceed / hold
```
