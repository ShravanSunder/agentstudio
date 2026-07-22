# Gate 0.a Shared App Implementation Review Packet

Date: 2026-06-25
Goal id: `2026-06-24-bridge-transport-review-pr-ready`
Mode: implementation
review_class: source-backed + risk-triggered
source_backed_verdict_attempted: true
whole-source-trace: required

## Review Question

Can the exact worktree dev-server URL pass while the user-visible product is
still wrong?

The intended answer after this checkpoint should be no. Reviewers must attack
that claim.

Exact URL:

```text
http://127.0.0.1:5173/?fixture=worktree&workers=on&scenario=current-worktree
```

Commit under review:

```text
3a076cc3 Close Gate 0a shared app proof gaps
```

## Accepted Request

Gate 0.a is not "make WorktreeFileApp product-like." It is:

```text
remove/bypass the second app path and prove FileViewer uses the shared
BridgeViewer shell with Pierre FileTree + Pierre CodeView/File + Shiki workers.
```

Bridge Viewer app model:

```text
Bridge Viewer App
  ReviewViewer: diffs / changesets / review package
  FileViewer: worktree browsing / single file / live file view

Shared UX contract:
  primary Pierre CodeView/File canvas on left
  Pierre FileTree/right rail on right
  Shiki/Pierre rendering path
  same search/filter/selection chrome style

Data sources:
  mock fixture
  current worktree
  live changeset stream
  static diff/review package
  file content stream
```

## Source Spec And Plan

- `tmp/spec-workflows/2026-06-22-bridge-transport-streaming-spec/worktree-file-surface-protocol.md`
- `tmp/plan-workflows/2026-06-22-bridge-transport-streaming-implementation-plan/worktree-devserver-product-e2e-precursor-plan.md`
- `tmp/workflow-state/2026-06-24-bridge-transport-review-pr-ready/details.md`
- `tmp/workflow-state/2026-06-24-bridge-transport-review-pr-ready/implementation-review-report-gate0a-2026-06-24.md`

## Changed Files

```text
BridgeWeb/src/app/bridge-app.tsx
BridgeWeb/src/app/bridge-app-protocol-router.tsx
BridgeWeb/src/app/bridge-app-dev-bootstrap.tsx
BridgeWeb/src/app/bridge-viewer-app-shell.tsx
BridgeWeb/src/app/bridge-app-protocol-router.unit.test.tsx
BridgeWeb/src/file-viewer/bridge-file-viewer-app.tsx
BridgeWeb/src/review-viewer/code-view/bridge-file-viewer-code-panel.tsx
BridgeWeb/src/review-viewer/workers/pierre/bridge-pierre-worker-pool.tsx
BridgeWeb/src/review-viewer/workers/pierre/bridge-pierre-worker-pool.unit.test.tsx
BridgeWeb/src/worktree-file-surface/worktree-file-surface-runtime.ts
BridgeWeb/src/worktree-file-surface/worktree-file-surface-runtime.integration.test.ts
BridgeWeb/scripts/dev-server/bridge-worktree-dev-provider.ts
BridgeWeb/scripts/dev-server/bridge-worktree-dev-provider.integration.test.ts
BridgeWeb/scripts/verify-bridge-viewer-worktree-dev-server.ts
tmp/spec-workflows/2026-06-22-bridge-transport-streaming-spec/worktree-file-surface-protocol.md
tmp/plan-workflows/2026-06-22-bridge-transport-streaming-implementation-plan/worktree-devserver-product-e2e-precursor-plan.md
tmp/workflow-state/2026-06-24-bridge-transport-review-pr-ready/details.md
tmp/workflow-state/2026-06-24-bridge-transport-review-pr-ready/events.jsonl
tmp/workflow-state/2026-06-24-bridge-transport-review-pr-ready/implementation-review-report-gate0a-2026-06-24.md
```

## Implementation Claims

- `BridgeApp` now owns both viewer modes. `worktree-file` enters
  `BridgeApp viewerMode="file"` instead of the protocol router mounting a direct
  FileViewer shell/app path.
- Shared shell proof records `data-bridge-app-owner="BridgeApp"`,
  `sharedShellOwner="BridgeViewerAppShell"`, `shellOwner="BridgeViewerApp.FileViewer"`,
  `codeOwner="CodeView.file"`, `treeOwner="FileTree"`, and `sidebarIsRight=true`.
- Worktree FileViewer content still renders through Pierre CodeView/File and
  Shiki/Pierre workers, not a route-local `<pre>` renderer.
- Pierre worker diagnostics now bind file worker success to the selected
  descriptor cache key.
- Stale refresh failures remain stale/retryable; superseded refresh completions
  cannot mark stale content fresh.
- Deleted tracked files become unavailable metadata-only descriptors so
  available/unavailable filters are nontrivial and unavailable bodies are not
  fetchable.
- The verifier mutates only tracked, contained paths and restores them
  collision-safely.

## Proof Claims

Fresh proof:

```text
pnpm --dir BridgeWeb exec vitest run scripts/dev-server/bridge-worktree-dev-provider.integration.test.ts src/worktree-file-surface/worktree-file-surface-runtime.integration.test.ts src/file-viewer/bridge-file-viewer-app.unit.test.tsx src/app/bridge-app-protocol-router.unit.test.tsx src/review-viewer/workers/pierre/bridge-pierre-worker-pool.unit.test.tsx scripts/verify-bridge-viewer-worktree-dev-server-paths.unit.test.ts --reporter verbose
exit 0; 6 files, 46 tests

pnpm --dir BridgeWeb exec tsc --noEmit
exit 0

pnpm --dir BridgeWeb run check
exit 0; existing verifier no-await-in-loop warnings only

pnpm --dir BridgeWeb run test:dev-server:worktree
exit 0

pnpm --dir BridgeWeb run test:browser:integration -- src/review-viewer/test-support/bridge-viewer-browser.integration.browser.test.tsx -t "large fixture programmatic file reveal uses bounded CodeView motion"
exit 0; 2 files, 34 tests

mise run lint
exit 0; swift-format OK, SwiftLint 0 violations, architecture lint OK, release script verification passed

git diff --check
exit 0

events.jsonl parse
exit 0
```

Fresh artifact:

```text
tmp/bridge-viewer-worktree-dev-server/2026-06-25T04-04-26-634Z/worktree-dev-server-proof.json
```

Screenshots:

```text
tmp/bridge-viewer-worktree-dev-server/2026-06-25T04-04-26-634Z/worktree-file-ready.png
tmp/bridge-viewer-worktree-dev-server/2026-06-25T04-04-26-634Z/worktree-file-search-result.png
tmp/bridge-viewer-worktree-dev-server/2026-06-25T04-04-26-634Z/worktree-file-stale-refresh.png
```

Important artifact fields:

```text
observedPageUrl == exact URL
observedLocationHref == exact URL
treeTotalSizeSource == providerFacts
targetPath == BridgeWeb/pnpm-lock.yaml
treePathCount == 453
sharedShellProof.appOwner == BridgeApp
sharedShellProof.sharedShellOwner == BridgeViewerAppShell
sharedShellProof.shellOwner == BridgeViewerApp.FileViewer
sharedShellProof.codeOwner == CodeView.file
sharedShellProof.treeOwner == FileTree
sharedShellProof.sidebarIsRight == true
sharedShellProof.workerDiagnosticLastFileSuccessCacheKey == selected descriptor cache key
productControlsProof.expectedUnavailablePath == .github/workflows/ci.yml
staleRefreshProof.refreshFetchHitsBeforeClick == 0
staleRefreshProof.refreshFetchHitsAfterFirstClick == 1
staleRefreshProof.refreshFetchHitsAfterSecondClick == 2
substituteGuardProof.standaloneWorktreeFileAppCount == 0
substituteGuardProof.reviewEmptyShellCount == 0
```

Dev server status at commit time:

```text
node PID 65785 listening on 127.0.0.1:5173
```

Verifier-mutated files `.github/workflows/ci.yml` and `.gitignore` were restored
clean after proof.

## Known Non-Goals

- This is Vite/dev-server product proof only.
- Native Agent Studio Bridge/WKWebView proof remains required before PR-ready.
- Gate 1 transport/core work must not start unless this review is ready or the
  human explicitly accepts the residual risk.
- No PR merge is in scope.

## Prior False-Green Failures Reviewers Must Remember

1. The route once showed raw/gibberish path text.
2. Narrow route/data proof passed while the product surface was wrong.
3. A standalone `WorktreeFileApp` mini-app could load real data but bypass the
   shared BridgeViewer/Pierre shell.
4. Previous proof overclaimed worker readiness, filter behavior, and tree extent
   stability.
5. Previous proof could mutate verifier-created worktree files and self-report
   configured URLs instead of observed browser URLs.

## Required Reviewer Output

Return candidate findings only. Parent reducer decides accepted truth.

For each finding:

```text
severity: blocker | important | follow-up | nit
title:
evidence: exact file:line, symbol, command output, or plan section
scenario:
smallest_fix:
proof:
confidence:
candidate_deviation_bucket:
candidate_route_target:
```

If no high-confidence findings, say `No findings.`

Always include lane-level confidence and remaining uncertainty.
