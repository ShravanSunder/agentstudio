# Ticket 04 Review-Fix Implementation Review

Date: 2026-06-24
Reviewed commit: `6724fae3`
Review range: `f5701c94..HEAD`
Mode: implementation re-review

## Verdict

`not_ready`

Reason: the first Ticket 04 review-fix pass closed the original scroll/loading
proof issues, but re-review found live-stream correctness and provider
containment gaps that still blocked Ticket 04 readiness.

## Accepted Findings

1. blocker: open-file invalidation did not fence an in-flight load.
   Evidence: `BridgeWeb/src/worktree-file-surface/worktree-file-app.tsx`
   guarded completion only by the user-selection request id, while
   `worktree.fileInvalidated` marked the open file stale without retiring the
   pending request. A late old body could return the panel to `ready`.

2. important: invalidation-only frame batches wiped the rendered tree.
   Evidence: `applyFramesToRuntime` rebuilt render state only from the latest
   frame batch, so an invalidation-only delta left `descriptors=[]` and
   `treeSizeFacts=null`.

3. important: stale invalidation dead-ended the open-file flow instead of
   honoring explicit refresh.
   Evidence: the stale state cleared rendered body bytes and rendered no
   refresh path even though the Worktree/File contract says stale content stays
   stable until explicit refresh.

4. important: changed-file symlinks could escape the worktree root in the Vite
   dev provider.
   Evidence: `readWorktreeFileText` checked only the lexical resolved path, not
   the real symlink target, before `readFile`.

5. blocker: the review-fix packet lacked ticket-local red proof.
   Evidence: the packet and workflow state recorded green commands but not the
   failing pre-fix commands for the changed behavior.

## Rejected Or Deferred Candidates

- follow-up: the live dev-server canary should also fail if the selected deep
  path is not present in before/after measured tree item ids. The current live
  artifacts do include the selected path and non-zero scroll, so this is proof
  hardening rather than a Ticket 04 blocker.

## Follow-through Fix

The accepted findings were fixed in the same parent session after reducer
verification:

- Added red integration tests proving symlink escape, in-flight invalidation,
  stale-body continuity, explicit refresh, and invalidation-only tree
  preservation.
- Updated the Worktree/File app to keep accumulated tree render state across
  delta-only frame batches.
- Updated matching invalidation frames to retire the active open-file request
  token so stale completions cannot commit.
- Kept the previous rendered body visible in stale state and added an explicit
  refresh button that calls `runtime.refreshOpenFile`.
- Updated the dev provider to check both lexical containment and `realpath`
  target containment before reading changed files.

## Review Proof

Red proof:

- `pnpm --dir BridgeWeb exec vitest run
  src/worktree-file-surface/worktree-file-app.integration.test.tsx
  scripts/dev-server/bridge-worktree-dev-provider.integration.test.ts
  --reporter verbose`: exit 1 before the fix, with expected failures:
  symlink provider promise resolved instead of rejecting; invalidation-only
  batch removed the tree row; in-flight invalidation returned `ready` after the
  old content resolved.

Green proof after the follow-through fix:

- `pnpm --dir BridgeWeb exec vitest run
  src/worktree-file-surface/worktree-file-app.integration.test.tsx
  scripts/dev-server/bridge-worktree-dev-provider.integration.test.ts
  --reporter verbose`: exit 0, 2 files passed, 16 tests passed.
- `pnpm --dir BridgeWeb exec vitest run
  src/worktree-file-surface/worktree-file-app.integration.test.tsx
  src/worktree-file-surface/worktree-file-surface-runtime.integration.test.ts
  scripts/dev-server/bridge-worktree-dev-provider.integration.test.ts
  scripts/dev-server/bridge-dev-telemetry.unit.test.ts --reporter verbose`:
  exit 0, 4 files passed, 26 tests passed.
- `pnpm --dir BridgeWeb run check`: exit 0.
- `pnpm --dir BridgeWeb run test:browser:integration --
  src/worktree-file-surface/worktree-file-app.browser.test.tsx --reporter
  verbose`: exit 0, 2 files passed, 32 tests passed.
- `BRIDGE_VIEWER_WORKTREE_DEV_SERVER_URL='http://127.0.0.1:5173/?fixture=worktree&workers=on&scenario=current-worktree'
  pnpm --dir BridgeWeb run test:dev-server:worktree`: exit 0 with artifact
  `tmp/bridge-viewer-worktree-dev-server/2026-06-24T01-32-58-887Z/worktree-dev-server-proof.json`,
  `descriptorCount=419`, `treeScrollTopBeforeSelection=2372`,
  `treeScrollTopAfterReady=2372`, `treeHeightDeltaPixels=0`,
  `contentHeightDeltaPixels=0`, `stableAnchorPass=true`, and
  `exactSizeTolerancePass=true`.
- `rg -n "/Users/|agentstudio://resource"
  tmp/bridge-viewer-worktree-dev-server/2026-06-24T01-32-58-887Z/worktree-dev-server-proof.json || true`:
  exit 0 with no matches.
- `git diff --check`: exit 0.
- touched Worktree/File TS hygiene grep for casual casts, `any`, suppressions,
  and `JSON.parse`: exit 0 with no matches.
- `mise run lint`: exit 0.

## Swarm Coverage

- Spec/proof compliance: found the in-flight invalidation blocker and missing
  red proof.
- Reliability/performance: found in-flight invalidation and invalidation-only
  tree state loss.
- Contracts/tests/code quality: found stale-flow refresh/continuity gap and
  duplicated in-flight invalidation concern.
- Security/trust boundary: found the symlink escape in the dev provider.
- Artifact convention lane: confirmed this report should live beside
  `review-packet.md`, with workflow state in `details.md` and `events.jsonl`.

## Routing Follow-through

Official workflow should route back to
`shravan-dev-workflow:implementation-review-swarm` for another Ticket 04
re-review before Ticket 04 can advance to cleanup or PR-ready wrapup.
