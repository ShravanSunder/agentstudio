# Gate 0.a Implementation Review Fix Report

Date: 2026-06-24
Goal id: `2026-06-24-bridge-transport-review-pr-ready`
Status: shared-app boundary findings fixed; pending implementation-review-swarm re-review

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

11. The protocol router still owned a direct FileViewer shell path.
    - Fixed by routing `worktree-file` through `BridgeApp viewerMode="file"`.
      `BridgeApp` now owns both ReviewViewer and FileViewer modes, and the
      shared shell records `data-bridge-app-owner="BridgeApp"`.

12. Worker proof was not tied to the selected descriptor identity.
    - Fixed by recording Pierre worker file request/success cache keys and
      asserting the last file success matches the selected descriptor cache key.

13. Available/unavailable filter proof could be decorative or degenerate.
    - Fixed by deleting a tracked file fixture, proving it appears under the
      unavailable filter, proving fetchable/unavailable counts differ, and
      proving unavailable content fetch rejects because no body is registered.

14. Stale refresh proof did not prove the browser actually retried after a
    failed content request.
    - Fixed by routing content requests through a Playwright probe and asserting
      request counts `0 -> 1 -> 2` across stale, failed refresh, and successful
      retry.

## Proof

- `pnpm --dir BridgeWeb exec vitest run scripts/verify-bridge-viewer-worktree-dev-server-paths.unit.test.ts src/worktree-file-surface/worktree-file-surface-runtime.integration.test.ts src/file-viewer/bridge-file-viewer-app.unit.test.tsx src/app/bridge-app-protocol-router.unit.test.tsx --reporter verbose`
  - exit: 0
  - result: superseded by the combined focused proof below

- `pnpm --dir BridgeWeb exec vitest run scripts/dev-server/bridge-worktree-dev-provider.integration.test.ts src/worktree-file-surface/worktree-file-surface-runtime.integration.test.ts src/file-viewer/bridge-file-viewer-app.unit.test.tsx src/app/bridge-app-protocol-router.unit.test.tsx src/review-viewer/workers/pierre/bridge-pierre-worker-pool.unit.test.tsx scripts/verify-bridge-viewer-worktree-dev-server-paths.unit.test.ts --reporter verbose`
  - exit: 0
  - result: 6 files passed, 46 tests passed

- `pnpm --dir BridgeWeb exec tsc --noEmit`
  - exit: 0

- `pnpm --dir BridgeWeb run check`
  - exit: 0
  - note: existing verifier `no-await-in-loop` warnings remain warnings only

- `pnpm --dir BridgeWeb run test:dev-server:worktree`
  - exit: 0
  - artifact:
    `tmp/bridge-viewer-worktree-dev-server/2026-06-25T04-04-26-634Z/worktree-dev-server-proof.json`
  - screenshots:
    - `tmp/bridge-viewer-worktree-dev-server/2026-06-25T04-04-26-634Z/worktree-file-ready.png`
    - `tmp/bridge-viewer-worktree-dev-server/2026-06-25T04-04-26-634Z/worktree-file-search-result.png`
    - `tmp/bridge-viewer-worktree-dev-server/2026-06-25T04-04-26-634Z/worktree-file-stale-refresh.png`

- `pnpm --dir BridgeWeb run test:browser:integration -- src/review-viewer/test-support/bridge-viewer-browser.integration.browser.test.tsx -t "large fixture programmatic file reveal uses bounded CodeView motion"`
  - exit: 0
  - result: 2 files passed, 34 tests passed

## 2026-06-25 Split Reset Re-Review Reduction

Status: accepted implementation-review findings fixed; pending re-review.

Accepted findings addressed:

1. Reset/replacement proof was false-green at the FileViewer app layer.
   - Fixed `BridgeFileViewerApp` so `worktree.reset` preserves the open file as
     stale instead of moving it to unavailable when the replacement descriptor is
     delivered in a later callback.
   - Added a regression that split reset then matching replacement leaves the
     old body visible, keeps the refresh affordance, and fetches only after the
     user clicks refresh.
   - Added a negative regression that an unrelated post-reset descriptor does
     not unblock the stale pre-reset file.

2. Pierre FileTree selected-path synchronization silently reopened files.
   - Fixed `BridgeFileViewerTreePanel` so programmatic selection sync does not
     call `onOpenFile`; only user selection opens a file.
   - This prevents replacement descriptors from silently fetching and flipping a
     stale open file back to ready.

3. Source-less reset frames were not refreshable even though the protocol schema
   permits optional `source`.
   - Fixed `worktree-file-surface-runtime.ts` with a source-less reset scope:
     all open sessions become stale, and later matching descriptors make refresh
     possible.
   - Added runtime integration proof for source-less reset plus matching
     replacement descriptor.

4. Unavailable-file verifier watched only the expected content handle.
   - Fixed the product verifier to probe all
     `/__bridge-worktree/file-content/**` requests while opening an unavailable
     descriptor.
   - The proof now fails if any body fetch occurs during unavailable open, even
     for the wrong handle.

Fresh proof:

- `pnpm --dir BridgeWeb exec vitest run src/file-viewer/bridge-file-viewer-app.unit.test.tsx --reporter verbose`
  - red before fix: 2 tests failed because reset produced `unavailable`
  - green after fix: 1 file passed, 4 tests passed
- `pnpm --dir BridgeWeb exec vitest run src/worktree-file-surface/worktree-file-surface-runtime.integration.test.ts --reporter verbose`
  - red before fix: source-less reset replacement test failed because session
    stayed `fresh`
  - green after fix: 1 file passed, 10 tests passed
- `pnpm --dir BridgeWeb exec vitest run src/app/bridge-app-protocol-router.contract.unit.test.tsx src/file-viewer/bridge-file-viewer-app.unit.test.tsx src/worktree-file-surface/worktree-file-surface-runtime.integration.test.ts scripts/dev-server/bridge-worktree-dev-provider.integration.test.ts --reporter verbose`
  - exit: 0
  - result: 4 files passed, 27 tests passed
- `pnpm --dir BridgeWeb exec tsc --noEmit`
  - exit: 0
- `pnpm --dir BridgeWeb run check`
  - exit: 0
  - note: existing verifier `no-await-in-loop` warnings remain warnings only
- `pnpm --dir BridgeWeb run test:dev-server:worktree`
  - exit: 0
  - artifact:
    `tmp/bridge-viewer-worktree-dev-server/2026-06-25T05-16-01-036Z/worktree-dev-server-proof.json`
  - screenshots:
    - `tmp/bridge-viewer-worktree-dev-server/2026-06-25T05-16-01-036Z/worktree-file-ready.png`
    - `tmp/bridge-viewer-worktree-dev-server/2026-06-25T05-16-01-036Z/worktree-file-search-result.png`
    - `tmp/bridge-viewer-worktree-dev-server/2026-06-25T05-16-01-036Z/worktree-file-stale-refresh.png`
- `pnpm --dir BridgeWeb run test:browser:integration -- src/review-viewer/test-support/bridge-viewer-browser.integration.browser.test.tsx -t "large fixture programmatic file reveal uses bounded CodeView motion"`
  - exit: 0
  - result: 2 files passed, 34 tests passed
- `mise run lint`
  - exit: 0
  - result: swift-format OK, SwiftLint 0 violations, architecture lint OK,
    release script verification passed
- `git diff --check`
  - exit: 0

- `git status --short`
  - result: `.github/workflows/ci.yml` and `.gitignore` restored clean; only
    intentional Gate 0.a implementation/doc changes remain

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

## 2026-06-25 Re-Review Reduction

Status: accepted implementation-review findings fixed; pending re-review.

Accepted findings addressed:

1. Router entry proof could be spoofed by shared-shell DOM markers.
   - Fixed with `bridge-app-protocol-router.contract.unit.test.tsx`, which
     mocks `BridgeApp` and asserts `worktree-file -> viewerMode="file"` and
     `review -> viewerMode="review"` directly.

2. Selected-file content proof did not assert the dev-server content front door.
   - Fixed by recording `selectedContentRouteProof` in the canonical artifact.
     Current proof records one
     `/__bridge-worktree/file-content/<selected-handle>` request for
     `BridgeWeb/pnpm-lock.yaml`.

3. Visible provenance was only hidden attribute proof.
   - Fixed by recording `visibleAppProof.sourceProvenanceText` and
     `sourceProvenanceRect`. Current proof records
     `sourceProvenanceText=dev-worktree-source`.

4. Unavailable rows were not opened in the product proof.
   - Fixed by clicking `.github/workflows/ci.yml` under the unavailable filter
     and recording `unavailableOpenProof`: `selectedContentState=unavailable`,
     `selectedLineCount=0`, and `contentRouteHitCount=0`.

5. Deleted unavailable text descriptors were mislabeled as binary.
   - Fixed in the dev provider and FileViewer filter/open contract:
     deleted metadata-only descriptors use `virtualizedExtentKind=unavailable`
     and `isBinary=false`; FileViewer fetchability excludes unavailable
     descriptors.

6. Source reset replacement descriptors did not update runtime open sessions.
   - Fixed in `worktree-file-surface-runtime.ts`: matching
     `worktree.fileDescriptor` frames update an open session's latest
     descriptor/ref, and source reset staleness also matches the original
     descriptor source. Added runtime proof that reset plus replacement remains
     refreshable, plus a negative regression that an unrelated post-reset
     descriptor does not unblock stale pre-reset content.

7. `packageForbiddenTextAbsent` was hardcoded in the artifact.
   - Fixed by deriving it from
     `visibleAppProof.forbiddenTextAbsentOutsideIntentionalUi`.

Fresh proof:

- `pnpm --dir BridgeWeb exec vitest run src/app/bridge-app-protocol-router.contract.unit.test.tsx src/file-viewer/bridge-file-viewer-app.unit.test.tsx src/worktree-file-surface/worktree-file-surface-runtime.integration.test.ts scripts/dev-server/bridge-worktree-dev-provider.integration.test.ts --reporter verbose`
  - exit: 0
  - result: 4 files passed, 24 tests passed
- `pnpm --dir BridgeWeb exec tsc --noEmit`
  - exit: 0

## 2026-06-25 Second Split Reset Re-Review Reduction

Status: accepted implementation-review findings fixed; pending re-review or
explicit human acceptance before Gate 1.

Accepted findings addressed:

1. Exact URL proof only proved same-handle stale refresh and did not prove
   source-less split reset with a replacement content handle.
   - Fixed the dev provider to version content handles by content hash.
   - Added exact URL proof for old/replacement handles, replacement hash,
     source cursor, zero body fetch before user refresh, and one replacement
     body fetch after user refresh.

2. Source-less reset over-accepted later descriptors.
   - Fixed runtime admission so source-less reset replacements require a
     post-reset snapshot source anchor.
   - Added negative and positive runtime tests for old-stream descriptors,
     anchored refresh, and anchored open.

3. Matching replacement descriptors could update metadata while leaving the
   open file `ready`.
   - Fixed FileViewer reconciliation so matching `worktree.fileDescriptor`
     frames mark the open file stale and keep the stale body visible.
   - Added FileViewer UI proof for descriptor replacement without invalidation.

4. Force split reset verifier events could be dropped behind the dev poller.
   - Fixed the dev backend so force split reset reloads are sticky until the
     in-flight reload completes.
   - Added browser-visible dev reload diagnostics used by verifier failures.

Fresh proof:

- `pnpm --dir BridgeWeb exec vitest run src/app/bridge-app-dev-worktree.unit.test.ts src/file-viewer/bridge-file-viewer-app.unit.test.tsx src/worktree-file-surface/worktree-file-surface-runtime.integration.test.ts --reporter verbose`
  - exit: 0
  - result: 3 files passed, 21 tests passed
- `pnpm --dir BridgeWeb exec tsc --noEmit`
  - exit: 0
- `pnpm --dir BridgeWeb run test:dev-server:worktree`
  - exit: 0
  - artifact:
    `tmp/bridge-viewer-worktree-dev-server/2026-06-25T05-53-31-358Z/worktree-dev-server-proof.json`
  - key artifact facts:
    - exact URL:
      `http://127.0.0.1:5173/?fixture=worktree&workers=on&scenario=current-worktree`
    - descriptor count: 456
    - shared shell owner: `BridgeViewerAppShell`
    - app owner: `BridgeApp`
    - shell owner: `BridgeViewerApp.FileViewer`
    - code owner: `CodeView.file`
    - tree owner: `FileTree`
    - standalone `WorktreeFileApp` count: 0
    - review empty shell count: 0
    - split reset proof path: `.mise.toml`
    - split reset body route hits: `0 -> 0 -> 1`
    - stale retry proof path: `.gitignore`
    - stale retry body route hits: `0 -> 1 -> 2`
- `pnpm --dir BridgeWeb run check`
  - exit: 0
  - note: existing verifier `no-await-in-loop` warnings remain warnings only
- `pnpm --dir BridgeWeb run test:browser:integration -- src/review-viewer/test-support/bridge-viewer-browser.integration.browser.test.tsx -t "large fixture programmatic file reveal uses bounded CodeView motion"`
  - exit: 0
  - result: 2 files passed, 34 tests passed
- `mise run lint`
  - exit: 0
  - result: swift-format OK, SwiftLint 0 violations, architecture lint OK,
    release script verification passed
- `git diff --check`
  - exit: 0
- `pnpm --dir BridgeWeb run test:dev-server:worktree`
  - exit: 0
  - artifact:
    `tmp/bridge-viewer-worktree-dev-server/2026-06-25T04-46-20-464Z/worktree-dev-server-proof.json`
  - screenshots:
    - `tmp/bridge-viewer-worktree-dev-server/2026-06-25T04-46-20-464Z/worktree-file-ready.png`
    - `tmp/bridge-viewer-worktree-dev-server/2026-06-25T04-46-20-464Z/worktree-file-search-result.png`
    - `tmp/bridge-viewer-worktree-dev-server/2026-06-25T04-46-20-464Z/worktree-file-stale-refresh.png`
- `pnpm --dir BridgeWeb run check`
  - exit: 0
  - note: existing verifier `no-await-in-loop` warnings remain warnings only
- `mise run lint`
  - exit: 0
  - result: swift-format OK, SwiftLint 0 violations, architecture lint OK,
    release script verification passed
- `pnpm --dir BridgeWeb run test:browser:integration -- src/review-viewer/test-support/bridge-viewer-browser.integration.browser.test.tsx -t "large fixture programmatic file reveal uses bounded CodeView motion"`
  - exit: 0
  - result: 2 files passed, 34 tests passed
