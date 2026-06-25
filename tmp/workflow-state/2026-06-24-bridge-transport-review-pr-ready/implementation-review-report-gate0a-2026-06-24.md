# Gate 0.a Implementation Review Fix Report

Date: 2026-06-24
Goal id: `2026-06-24-bridge-transport-review-pr-ready`
Status: second reviewer findings fixed; pending implementation-review-swarm re-review

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

6. The dev-server proof self-reported the configured URL instead of recording
   what the browser actually loaded.
   - Fixed by asserting and recording both `page.url()` and
     `window.location.href` for the exact current-worktree URL.

7. Shared-shell proof could pass on marker strings without proving containment.
   - Fixed by requiring `bridge-file-viewer-shell` to be a direct child of the
     shared `BridgeViewerAppShell` root.

8. Stale-refresh proof did not fail closed on unsafe or unrestored verifier
   writes.
   - Fixed by resolving descriptor paths through lexical and realpath
     containment checks, rejecting absolute/parent/symlink escapes, requiring
     git-tracked files, and verifying the original file hash after restore.

9. Worker proof was not bound to the selected-file render.
   - Fixed by recording the worker file-success count before target selection
     and requiring a post-selection increment plus `file` last-success type.

10. Retryability after a failed explicit refresh was only partially covered.
    - Fixed at the runtime state-machine level and the FileViewer UI level:
      failed explicit refresh keeps the session stale, a second refresh reaches
      ready, and the stale body remains visible until success.

## Proof

- `pnpm --dir BridgeWeb exec vitest run scripts/verify-bridge-viewer-worktree-dev-server-paths.unit.test.ts src/worktree-file-surface/worktree-file-surface-runtime.integration.test.ts src/file-viewer/bridge-file-viewer-app.unit.test.tsx src/app/bridge-app-protocol-router.unit.test.tsx --reporter verbose`
  - exit: 0
  - result: 4 files passed, 14 tests passed

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
    `tmp/bridge-viewer-worktree-dev-server/2026-06-25T03-25-29-946Z/worktree-dev-server-proof.json`
  - screenshots:
    - `tmp/bridge-viewer-worktree-dev-server/2026-06-25T03-25-29-946Z/worktree-file-ready.png`
    - `tmp/bridge-viewer-worktree-dev-server/2026-06-25T03-25-29-946Z/worktree-file-search-result.png`
    - `tmp/bridge-viewer-worktree-dev-server/2026-06-25T03-25-29-946Z/worktree-file-stale-refresh.png`

- `git status --short`
  - result: no stale-refresh proof file left dirty; only intentional Gate 0.a
    implementation/doc changes remain

- `mise run lint`
  - exit: 0
  - result: swift-format OK, SwiftLint 0 violations, AgentStudio architecture
    lint OK, release script verification passed

## Re-Review Packet Reminder

Implementation reviewers must still ask whether the exact URL can pass while
the user-visible product is wrong. In particular, re-review must attack
`WorktreeFileApp`, route-local custom shell/tree, raw `<pre>` content,
Review/mock lineage, DOM-only ready markers, local extent synthesis, worker
bootstrap-only evidence, verifier-created worktree mutations, self-reported
URLs, and marker-only shared-shell assertions.
