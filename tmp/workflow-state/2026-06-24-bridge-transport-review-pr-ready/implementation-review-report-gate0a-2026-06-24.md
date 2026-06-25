# Gate 0.a Implementation Review Fix Report

Date: 2026-06-24
Goal id: `2026-06-24-bridge-transport-review-pr-ready`
Status: reviewer findings fixed; pending implementation-review-swarm re-review

## Scope

This report covers Gate 0.a only: the exact Vite/dev-server Worktree/File URL
must render FileViewer inside the shared BridgeViewer shell with Pierre
FileTree/right rail, Pierre CodeView/File, Shiki, and worker-backed rendering.
It does not satisfy native Agent Studio Bridge/WKWebView proof or downstream
Gate 1-4 work.

Exact URL:

```text
http://127.0.0.1:5173/?fixture=worktree&workers=on&scenario=current-worktree
```

## Accepted Findings Fixed

1. Tree extent proof accepted locally synthesized fallback values.
   - Fixed by requiring provider-backed tree extent facts and source labels.
   - Provider integration proof now rejects path-count-only fallback as the
     proof source.

2. Product control proof did not prove rendered Pierre row changes or invalid
   regex behavior.
   - Fixed by recording rendered row samples, visible result counts, invalid
     regex status, and tree-size source for each control state.

3. Worker proof only showed bootstrap labels.
   - Fixed by requiring actual Pierre worker file success count, last request
     type `file`, file-cache size, initialized manager state, ready worker pool,
     and ready theme state.

4. Stale-refresh proof created its own untracked file in the scanned worktree.
   - Fixed by mutating an existing tracked descriptor-backed file and restoring
     it in verifier cleanup.

5. Failed explicit refresh blanked the stale body into failed state.
   - Fixed with a FileViewer unit regression: failed explicit refresh keeps the
     old body visible, keeps stale state, and leaves refresh retryable.

## Proof

- `pnpm --dir BridgeWeb exec vitest run src/file-viewer/bridge-file-viewer-app.unit.test.tsx --reporter verbose`
  - exit: 0
  - result: 1 file passed, 1 test passed

- `pnpm --dir BridgeWeb exec vitest run scripts/dev-server/bridge-worktree-dev-provider.integration.test.ts src/app/bridge-app-protocol-router.unit.test.tsx --reporter verbose`
  - exit: 0
  - result: 2 files passed, 14 tests passed

- `pnpm --dir BridgeWeb exec tsc --noEmit`
  - exit: 0

- `pnpm --dir BridgeWeb run check`
  - exit: 0
  - note: existing verifier `no-await-in-loop` warnings remain warnings only

- `pnpm --dir BridgeWeb run test:dev-server:worktree`
  - exit: 0
  - artifact:
    `tmp/bridge-viewer-worktree-dev-server/2026-06-25T02-49-34-424Z/worktree-dev-server-proof.json`
  - screenshots:
    - `tmp/bridge-viewer-worktree-dev-server/2026-06-25T02-49-34-424Z/worktree-file-ready.png`
    - `tmp/bridge-viewer-worktree-dev-server/2026-06-25T02-49-34-424Z/worktree-file-search-result.png`
    - `tmp/bridge-viewer-worktree-dev-server/2026-06-25T02-49-34-424Z/worktree-file-stale-refresh.png`

## Re-Review Packet Reminder

Implementation reviewers must still ask whether the exact URL can pass while
the user-visible product is wrong. In particular, re-review must attack
`WorktreeFileApp`, route-local custom shell/tree, raw `<pre>` content,
Review/mock lineage, DOM-only ready markers, local extent synthesis, worker
bootstrap-only evidence, and verifier-created worktree mutations.
