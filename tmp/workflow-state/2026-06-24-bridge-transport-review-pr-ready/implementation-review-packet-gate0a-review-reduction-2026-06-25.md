# Gate 0.a Implementation Re-Review Packet

Date: 2026-06-25
Mode: implementation
Review class: source-backed, plan-backed, risk-triggered
Whole-source trace: required
Source-backed verdict attempted: true

## Accepted Request

Gate 0.a is the first blocker before any downstream transport/review work:
the exact dev-server URL
`http://127.0.0.1:5173/?fixture=worktree&workers=on&scenario=current-worktree`
must render FileViewer inside the shared BridgeViewer app, not a second
WorktreeFileApp or route-local file surface.

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

Reviewers must not accept proof that can pass through `WorktreeFileApp`,
route-local custom shell/tree, raw `<pre>` content, Review/mock lineage,
DOM-only ready markers, local extent synthesis, bootstrap-only worker evidence,
verifier-created worktree mutations, self-reported URLs, marker-only
shared-shell assertions, unasserted content-route requests, hidden-only
provenance, unavailable body fetches, stale reset sessions that cannot refresh,
or unrelated post-reset descriptors unblocking stale pre-reset content.

## Source Spec

- Parent spec:
  `tmp/spec-workflows/2026-06-22-bridge-transport-streaming-spec/spec.md`
- Worktree/File protocol spec:
  `tmp/spec-workflows/2026-06-22-bridge-transport-streaming-spec/worktree-file-surface-protocol.md`
- Prior Gate 0.a spec/review packet:
  `tmp/workflow-state/2026-06-24-bridge-transport-review-pr-ready/spec-review-packet-gate0a-2026-06-24.md`

## Source Plan

- Implementation plan:
  `tmp/plan-workflows/2026-06-24-bridge-transport-review-pr-ready-implementation-plan/implementation-plan.md`
- Gate 0 ticket:
  `tmp/plan-workflows/2026-06-24-bridge-transport-review-pr-ready-implementation-plan/tickets/00-gate0-worktree-product-e2e.md`

## Implementation Scope

Primary code commit under review:
`7789ab93 Tighten Gate 0a shared file viewer proof`

Changed implementation/test files:

- `BridgeWeb/src/app/bridge-app-protocol-router.contract.unit.test.tsx`
- `BridgeWeb/src/file-viewer/bridge-file-viewer-app.tsx`
- `BridgeWeb/src/file-viewer/bridge-file-viewer-app.unit.test.tsx`
- `BridgeWeb/src/worktree-file-surface/worktree-file-surface-runtime.ts`
- `BridgeWeb/src/worktree-file-surface/worktree-file-surface-runtime.integration.test.ts`
- `BridgeWeb/scripts/dev-server/bridge-worktree-dev-provider.ts`
- `BridgeWeb/scripts/dev-server/bridge-worktree-dev-provider.integration.test.ts`
- `BridgeWeb/scripts/verify-bridge-viewer-worktree-dev-server.ts`

Updated workflow/spec/plan state:

- `tmp/spec-workflows/2026-06-22-bridge-transport-streaming-spec/worktree-file-surface-protocol.md`
- `tmp/plan-workflows/2026-06-24-bridge-transport-review-pr-ready-implementation-plan/tickets/00-gate0-worktree-product-e2e.md`
- `tmp/workflow-state/2026-06-24-bridge-transport-review-pr-ready/details.md`
- `tmp/workflow-state/2026-06-24-bridge-transport-review-pr-ready/events.jsonl`
- `tmp/workflow-state/2026-06-24-bridge-transport-review-pr-ready/implementation-review-report-gate0a-2026-06-24.md`

## Proof Claims

Focused reviewer-reduction suite:

```bash
pnpm --dir BridgeWeb exec vitest run src/app/bridge-app-protocol-router.contract.unit.test.tsx src/file-viewer/bridge-file-viewer-app.unit.test.tsx src/worktree-file-surface/worktree-file-surface-runtime.integration.test.ts scripts/dev-server/bridge-worktree-dev-provider.integration.test.ts --reporter verbose
```

Result: exit 0, 4 files passed, 24 tests passed.

Type/check:

```bash
pnpm --dir BridgeWeb exec tsc --noEmit
pnpm --dir BridgeWeb run check
```

Result: both exit 0. `BridgeWeb run check` has existing verifier
`no-await-in-loop` warnings only.

Product dev-server proof:

```bash
pnpm --dir BridgeWeb run test:dev-server:worktree
```

Result: exit 0.

Artifact:
`tmp/bridge-viewer-worktree-dev-server/2026-06-25T04-46-20-464Z/worktree-dev-server-proof.json`

Screenshots:

- `tmp/bridge-viewer-worktree-dev-server/2026-06-25T04-46-20-464Z/worktree-file-ready.png`
- `tmp/bridge-viewer-worktree-dev-server/2026-06-25T04-46-20-464Z/worktree-file-search-result.png`
- `tmp/bridge-viewer-worktree-dev-server/2026-06-25T04-46-20-464Z/worktree-file-stale-refresh.png`

Browser integration guard:

```bash
pnpm --dir BridgeWeb run test:browser:integration -- src/review-viewer/test-support/bridge-viewer-browser.integration.browser.test.tsx -t "large fixture programmatic file reveal uses bounded CodeView motion"
```

Result: exit 0, 2 files passed, 34 tests passed.

Repo quality:

```bash
mise run lint
git diff --check
node -e "parse events jsonl"
```

Result: all exit 0. `mise run lint` passed swift-format, SwiftLint,
AgentStudio architecture lint, and release script verification.

Independent browser subagent evidence:

- Artifact:
  `tmp/bridge-viewer-worktree-dev-server/2026-06-25T04-40-15-000Z/worktree-dev-server-proof.json`
- Reported `shellOwner=BridgeViewerApp.FileViewer`, `codeOwner=CodeView.file`,
  `treeOwner=FileTree`, `sidebarIsRight=true`,
  `standaloneWorktreeFileAppCount=0`, visible provenance, search/regex
  controls, and unavailable zero-fetch behavior.

## Must-Verify Source Obligations

Use this matrix shape in the review output.

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

3. `gate0a-current-worktree-source`
   - Exact `current-worktree` URL must use the dev worktree source and show
     visible source provenance.

4. `gate0a-content-data-plane`
   - Selected fetchable file content must route through the dev-server
     `/__bridge-worktree/file-content/<handle>` front door with an asserted hit.
   - Unavailable descriptors must not fetch bodies.

5. `gate0a-controls-and-filters`
   - Search, regex, fetchable/unavailable filters must operate against actual
     rendered Pierre rows, not status text or synthetic counts only.

6. `gate0a-reset-and-refresh`
   - Stale refresh must keep prior content visible, record real retry request
     counts, and recover.
   - Source reset plus same-file replacement must be refreshable.
   - Source reset plus unrelated descriptor must not unblock stale pre-reset
     content.

7. `gate0a-proof-integrity`
   - Proof must fail if the old WorktreeFileApp/raw-pre path returns.
   - Proof must not rely on verifier-created untracked mutations, hidden-only
     markers, self-reported URL strings, or bootstrap-only worker state.

## Known Deviations

- This remains Vite/dev-server product proof only.
- Native Agent Studio Bridge/WKWebView proof is still required before PR-ready.
- Gate 1 must not start until this re-review passes or the human explicitly
  accepts remaining risk.

## Reviewer Output Requirements

Return candidate findings only. Do not edit files.

For each candidate finding:

- severity: blocker | important | follow-up | nit
- title
- evidence: exact file line, symbol, command output, proof artifact field, or
  plan/spec section
- scenario
- smallest_fix
- proof
- confidence
- candidate_deviation_bucket
- candidate_route_target

If no high-confidence findings exist, say `No findings.` Include lane-level
confidence and remaining uncertainty.
