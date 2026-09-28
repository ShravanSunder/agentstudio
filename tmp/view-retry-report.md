# View recovery retry implementation report

Branch: `bridge-stability-1-view-retry`
Base: `fe9d70ba9441aa7620c9b32d5e8c99a44960036e`
Scope: PR1 per-view recovery status and one Retry action on File, Comments, and Review.

## Changed

- Added the worker `viewRecoveryStatus` event and `viewRecoveryRetry` command contracts, schema validation, command admission/routing, and runtime dispatch.
- W2 now emits status only on transitions, validates registered recovery kinds, and resets/restarts a view on Retry. The entry publishes status over the installed product port. The only edits in `bridge-product-transport.ts` are the optional `onViewRecoveryStatus` prop and its conditional pass-through to W2.
- The pane runtime assigns status to the matching File or Review render store. File, Comments, and Review preserve the last good content and expose the owned shared Retry control. Retry dispatches the view retry plus the surface job: `fileRefreshRetry`, `annotationProjectionRetry`, or `reviewComparisonUpdate`.
- Added unit and Browser Mode proof. The Browser Mode cases capture:
  - `tmp/bridgeweb-file-view-retry.png`
  - `tmp/bridgeweb-comments-view-retry.png`
  - `tmp/bridgeweb-review-view-retry.png`

Changed source and test files:

**Worker contracts, routing, and state**

- `BridgeWeb/src/core/comm-worker/bridge-worker-view-recovery-contracts.ts` (new)
- `BridgeWeb/src/core/comm-worker/bridge-worker-contracts.ts`
- `BridgeWeb/src/core/comm-worker/bridge-comm-worker-protocol.ts`
- `BridgeWeb/src/core/comm-worker/bridge-comm-worker-command-admission.ts`
- `BridgeWeb/src/core/comm-worker/bridge-comm-worker-command-handler-contracts.ts`
- `BridgeWeb/src/core/comm-worker/bridge-comm-worker-command-handler.ts`
- `BridgeWeb/src/core/comm-worker/bridge-comm-worker-command-handler.unit.test.ts`
- `BridgeWeb/src/core/comm-worker/bridge-comm-worker-command-handler-view-recovery.unit.test.ts` (new)
- `BridgeWeb/src/core/comm-worker/bridge-comm-worker-runtime-command-routing.ts`
- `BridgeWeb/src/core/comm-worker/bridge-comm-worker-runtime-protocol.ts`
- `BridgeWeb/src/core/comm-worker/bridge-comm-worker-telemetry.ts`
- `BridgeWeb/src/core/comm-worker/bridge-comm-worker-entry.ts`
- `BridgeWeb/src/core/comm-worker/bridge-comm-worker-entry.unit.test.ts`
- `BridgeWeb/src/core/comm-worker/bridge-comm-worker-entry.test-support.ts`
- `BridgeWeb/src/core/comm-worker/bridge-comm-worker-install-lifecycle.unit.test.ts`
- `BridgeWeb/src/core/comm-worker/bridge-product-view-scope-owner.ts`
- `BridgeWeb/src/core/comm-worker/bridge-product-view-scope-owner.unit.test.ts`
- `BridgeWeb/src/core/comm-worker/bridge-product-transport.ts`
- `BridgeWeb/src/core/comm-worker/bridge-pane-runtime.ts`
- `BridgeWeb/src/core/comm-worker/bridge-pane-runtime-view-recovery.unit.test.ts` (new)
- `BridgeWeb/src/core/comm-worker/bridge-worker-rpc-client.ts`
- `BridgeWeb/src/core/comm-worker/bridge-main-render-snapshot-store.ts`
- `BridgeWeb/src/core/comm-worker/bridge-main-review-publication-integration.ts`

**File, Comments, and Review surfaces**

- `BridgeWeb/src/app/bridge-app-review-render-snapshot-controller.browser-harness.test-support.tsx`
- `BridgeWeb/src/app/bridge-app-review-render-snapshot-controller.browser.test.tsx`
- `BridgeWeb/src/app/bridge-app-review-render-snapshot-controller.ts`
- `BridgeWeb/src/app/bridge-app-review-viewer-mode.tsx`
- `BridgeWeb/src/app/bridge-review-metadata-recovery-warning.tsx` (new)
- `BridgeWeb/src/app/bridge-viewer-recovery-action-spec.ts` (new)
- `BridgeWeb/src/app/bridge-viewer-recovery-retry-button.tsx` (new)
- `BridgeWeb/src/file-viewer/bridge-file-viewer-app.tsx`
- `BridgeWeb/src/file-viewer/bridge-file-viewer-render-snapshot-controller.browser.test.tsx`
- `BridgeWeb/src/file-viewer/bridge-file-viewer-render-snapshot-controller.ts`
- `BridgeWeb/src/worktree-annotations/worktree-annotation-browser-test-support.ts`
- `BridgeWeb/src/worktree-annotations/worktree-annotation-edit-ownership.unit.test.ts`
- `BridgeWeb/src/worktree-annotations/worktree-annotation-recovery-and-history.browser.test.tsx`
- `BridgeWeb/src/worktree-annotations/worktree-annotation-recovery-warning.tsx`
- `BridgeWeb/src/worktree-annotations/worktree-annotation-surface-client.ts`

## Proof

| Command | Result | Exit |
|---|---|---:|
| `mise -C /Users/shravansunder/dev/agent-studio-worktrees/pr1-view-retry run test:bridge-web:unit` | 393 files passed; 2,484 tests passed; 1 expected failure (2,485 total) | 0 |
| `mise -C /Users/shravansunder/dev/agent-studio-worktrees/pr1-view-retry run test:bridge-web:browser -- src/file-viewer/bridge-file-viewer-render-snapshot-controller.browser.test.tsx src/app/bridge-app-review-render-snapshot-controller.browser.test.tsx src/worktree-annotations/worktree-annotation-recovery-and-history.browser.test.tsx` | 3 files passed; 21 tests passed | 0 |
| `mise -C /Users/shravansunder/dev/agent-studio-worktrees/pr1-view-retry run test:bridge-web:check` | Passed oxlint type-aware, architecture/style checks, formatting on 1,238 files, TypeScript, and product-contract checks | 0 |
| `git diff --check` | Passed | 0 |

The BridgeWeb check emitted existing warnings in unrelated files but no errors. Test logs are in `tmp/view-retry-unit.log`, `tmp/view-retry-browser.log`, and `tmp/view-retry-check.log`.

## Test-standard checklist

- [x] W2 status sequence covers `ready → recovering → failedRetryable`, certified-install reset to `ready`, retry reset, sibling-view isolation, and suppression of duplicate status emissions.
- [x] Entry test observes the exact `viewRecoveryStatus` message on a real `MessageChannel` product port; no source-text assertion is used.
- [x] Contract tests cover a valid event and reject an unknown status.
- [x] Main routing test confirms status reaches only the matching per-surface state.
- [x] Each Browser Mode test verifies one Retry control, clicks it, checks the surface-specific commands, and confirms last-good content remains visible after Retry.
- [x] Tests wait for observed messages or browser interactions; no sleep or polling wait was added.
- [x] Browser screenshots were captured and inspected for all three surfaces.
- [x] `bridge-product-transport.ts` contains only the two owner-approved recovery-status edits.

## Blocked or unverified

- No remaining blocker for the requested BridgeWeb scope. The first sandboxed unit run hit `listen EPERM` in an unrelated dev-server test; rerunning the required lane with loopback permission passed. Browser Mode also required loopback permission and passed on the final run.
- The full repository `mise run test` and native app lanes were not run; this Worker brief assigns BridgeWeb-only proof and leaves the remaining lanes to the orchestrator.
- No repository board home was found: local repository association returned no project, and the follow-up `Agent Studio Bridge` / `view retry` discovery searches returned no records. Returned to the orchestrator as `no-home: no project for agentstudio`.
