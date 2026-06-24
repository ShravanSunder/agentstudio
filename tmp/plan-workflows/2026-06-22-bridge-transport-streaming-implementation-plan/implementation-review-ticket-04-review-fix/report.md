# Ticket 04 Review-Fix Implementation Review

Date: 2026-06-24
Reviewed commits: `6724fae3`, `66f03af5`, `4d1cfe6f`, `9141c177`
Review ranges: `f5701c94..6724fae3`, `4d1cfe6f..HEAD`
Mode: implementation re-review with focused proof addendum

## Verdict

`ready`

Reason: the original Ticket 04 review-fix pass returned `not_ready`, but all
accepted blocker/important findings have now been patched and proven. The final
focused addendum at `9141c177` closes the remaining browser proof uncertainty
for post-refresh rendered-DOM capability URL scrubbing, and two focused
re-review lanes found no blocker or important findings.

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
- follow-up: `realpath` containment still has a theoretical local
  time-of-check/time-of-use race if another local writer swaps a checked parent
  directory between validation and read. Static outside-root symlink escape is
  fixed and proven for Ticket 04; descriptor-safe traversal/openat-style
  hardening is deferred.

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

Second re-review follow-through:

- A second focused review accepted one remaining blocker: stale invalidation and
  explicit refresh were proven only in jsdom, while the Ticket 04 matrix calls
  for browser/dev-server proof.
- Added browser-mode coverage for stale-with-body, no auto-fetch, explicit
  Refresh, latest content commit, and preserved tree row after invalidation.
- Added post-refresh rendered-DOM scrubbing proof so the same browser flow
  asserts `document.body.innerHTML` does not expose `agentstudio://resource`
  after the refreshed content is visible.

Final focused re-review addendum:

- Proof closure lane reviewed `4d1cfe6f..HEAD` and reported no findings with
  high confidence. It verified the new assertion is post-Refresh, post-ready,
  checks rendered DOM, and does not weaken stale invalidation / no-auto-fetch /
  explicit Refresh coverage.
- Security/trust-boundary lane reviewed the same addendum and reported no
  findings with high confidence. It confirmed `document.body.innerHTML` is the
  widest rendered DOM/body surface this browser test exercises and that the
  assertion placement after refresh is meaningful for the bounded capability URL
  leakage claim.

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
  verbose`: exit 0, 2 files passed, 33 tests passed.
- `BRIDGE_VIEWER_WORKTREE_DEV_SERVER_URL='http://127.0.0.1:5173/?fixture=worktree&workers=on&scenario=current-worktree'
  pnpm --dir BridgeWeb run test:dev-server:worktree`: exit 0 with artifact
  `tmp/bridge-viewer-worktree-dev-server/2026-06-24T01-45-24-843Z/worktree-dev-server-proof.json`,
  `descriptorCount=421`, `treeScrollTopBeforeSelection=2396`,
  `treeScrollTopAfterReady=2396`, `treeHeightDeltaPixels=0`,
  `contentHeightDeltaPixels=0`, `stableAnchorPass=true`, and
  `exactSizeTolerancePass=true`.
- `rg -n "/Users/|agentstudio://resource"
  tmp/bridge-viewer-worktree-dev-server/2026-06-24T01-45-24-843Z/worktree-dev-server-proof.json || true`:
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
`shravan-dev-workflow:implementation-execute-plan` for Ticket 05 cleanup / hard
cutover before PR-ready wrapup.
