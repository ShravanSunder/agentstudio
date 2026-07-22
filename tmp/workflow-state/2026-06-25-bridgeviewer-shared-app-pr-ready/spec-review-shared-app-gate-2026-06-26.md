# Shared BridgeViewer Spec Review Gate

Date: 2026-06-26
Goal: 2026-06-25-bridgeviewer-shared-app-pr-ready
Workflow: shravan-dev-workflow:spec-review-swarm

## Scope

Reviewed and reconciled the shared BridgeViewer architecture/protocol artifacts:

- `docs/specs/bridge-viewer-transport/spec.md`
- `docs/specs/bridge-viewer-transport/review-protocol.md`
- `docs/specs/bridge-viewer-transport/worktree-file-surface-protocol.md`
- `tmp/spec-workflows/2026-06-22-bridge-transport-streaming-spec/spec.md`
- `tmp/spec-workflows/2026-06-22-bridge-transport-streaming-spec/review-protocol.md`
- `tmp/spec-workflows/2026-06-22-bridge-transport-streaming-spec/worktree-file-surface-protocol.md`
- `tmp/plan-workflows/2026-06-22-bridge-transport-streaming-implementation-plan/worktree-devserver-product-e2e-precursor-plan.md`

## Result

Verdict: ready to continue implementation.

Accepted requirements now explicit in the spec/protocol copies:

- `FileViewer` and `ReviewViewer` are modes inside one shared
  `BridgeViewerApp` shell.
- Gate 0.a proof must cover explicit dev URLs:
  `viewer=file`, `viewer=review`, and Review file-target presentation.
- Visible UX proof must be Vitest Browser, Playwright/dev-server, or native
  WKWebView proof. `jsdom` may only be used as a lower-layer state guard when
  explicitly scoped that way.
- Tree row click proof must use real actionability-checked browser interaction;
  synthetic DOM `dispatchEvent` fallback is prohibited.
- Scheduler/preload latency remains a real follow-up slice. Immediate dev proof
  records current latency/disposition facts; production scheduler tuning remains
  Gate 0.a.5.

## Evidence

Commands:

- `git diff --no-index --stat docs/specs/bridge-viewer-transport/spec.md tmp/spec-workflows/2026-06-22-bridge-transport-streaming-spec/spec.md; true`
  - exit 0, no diff output after reconciliation
- `git diff --no-index --stat docs/specs/bridge-viewer-transport/review-protocol.md tmp/spec-workflows/2026-06-22-bridge-transport-streaming-spec/review-protocol.md; true`
  - exit 0, no diff output after reconciliation
- `git diff --no-index --stat docs/specs/bridge-viewer-transport/worktree-file-surface-protocol.md tmp/spec-workflows/2026-06-22-bridge-transport-streaming-spec/worktree-file-surface-protocol.md; true`
  - exit 0, no diff output after reconciliation
- `git diff --check`
  - exit 0
- `pnpm --dir BridgeWeb run test:dev-server:worktree`
  - exit 0
  - proof artifact:
    `tmp/bridge-viewer-worktree-dev-server/2026-06-26T01-11-10-652Z/worktree-dev-server-proof.json`
  - artifact records explicit `viewer=file`, `viewer=review`, and Review
    file-target URLs, one shared shell, `CodeView.file`, `FileTree`, worker
    `ready`, and current-worktree source provenance.

Browser onlook:

- Agent: `019f0170-f12b-7062-abcd-57ec9ef8bc39`
- Result: pass
- Checked:
  - `http://127.0.0.1:5173/?fixture=worktree&viewer=file&workers=on&scenario=current-worktree`
  - `http://127.0.0.1:5173/?fixture=worktree&viewer=review&workers=on&scenario=current-worktree`
  - `http://127.0.0.1:5173/?fixture=worktree&viewer=review&workers=on&scenario=current-worktree&presentation=file&path=.gitignore&version=current`
- Observed one shared shell, FileViewer canvas left, Pierre FileTree/right rail
  right, Pierre/Shiki rendering, workers ready, and real click-to-change content.
- Screenshot artifacts:
  - `tmp/bridge-viewer-worktree-dev-server/2026-06-26T01-00-31-415Z/worktree-file-ready.png`
  - `tmp/bridge-viewer-worktree-dev-server/2026-06-26T01-00-31-415Z/worktree-file-search-result.png`
  - `tmp/bridge-viewer-worktree-dev-server/2026-06-26T01-00-31-415Z/worktree-file-stale-refresh.png`
  - `tmp/http___127_0_0_1_5173__fixture_worktree_viewer_file_workers_on_scenario_current_worktree.png`
  - `tmp/http___127_0_0_1_5173__fixture_worktree_viewer_review_workers_on_scenario_current_worktree.png`
  - `tmp/http___127_0_0_1_5173__fixture_worktree_viewer_review_workers_on_scenario_current_worktree_presentation_file_path__gitig.png`

Spec reviewer:

- Agent: `019f0174-e313-7c80-98dc-3d25cbb645c3`
- Result: no P0/P1 blockers.
- Accepted P2: parent proof row omitted `speculative-preloaded` and `refreshed`
  and did not state the 0.a.5 phase boundary.
- Disposition: fixed in both parent spec copies.

## Phase Result

phase_result: complete
evidence: this report, reconciled spec/protocol diffs, browser onlook proof,
`git diff --check`
recommended_next_workflow: shravan-dev-workflow:implementation-execute-plan
recommended_transition_reason: Spec/protocol artifacts are aligned and the
remaining work is implementation proof for the explicit dev-server and native
Bridge/WKWebView gates.
