# Ticket 01 Second Review-Fix Response

Date: 2026-06-22
Goal id: `2026-06-22-bridge-transport-streaming`
Branch: `luna-338-pierreshikitrees-review-viewer-2`

## Verdict

The accepted second-review findings are addressed in the current worktree. This
checkpoint is ready to route back to `shravan-dev-workflow:implementation-review-swarm`
after commit.

## Accepted Findings Addressed

1. Dev-server and fixture URLs still used the legacy unscoped content route.
   - Updated the worktree dev provider, synced Swift/BridgeWeb contract
     fixtures, updated IPC and benchmark test fixtures, and added active-source
     stale URL sweeps.

2. Browser resource parser still allowed stable-decoded traversal and encoded
   slash shapes.
   - `resourcePathSegments` now stable-decodes path and segment values to a
     fixed point, rejects decoded `/` inside a segment, and keeps traversal
     rejection parity covered by unit tests.

3. `HEAD` on content still materialized provider bytes.
   - `BridgeContentStore.metadata` returns validated handle metadata without
     loading content.
   - `BridgeSchemeHandler` emits a response-only HEAD path and proves provider
     request count stays zero.

4. Controller-owned lease publication was not directly proven.
   - `BridgePaneControllerTests` now asserts the published package handle is
     registered in the controller's resource lease registry.

5. Failed reloads could leave previous content authority live.
   - `.loadDiff` now clears review content authority before starting a new
     generation, and a WebKit-serialized controller test proves the old lease is
     revoked after a failed reload.

6. Lease replacement had a transient invalid-route window.
   - `BridgeTransportResourceLeaseRegistry.replace` validates the full lease
     batch and then swaps matching pane/protocol/kind authority in one actor
     turn.

7. Swift worktree-file protocol registry advertised an unimplemented
   `file-content` kind.
   - The shared Swift registry now keeps `worktree-file` at `tree` only for this
     checkpoint.

8. Teardown left review content leases and store state alive.
   - `BridgePaneController.teardown` now schedules review content store
     deactivation and review/content lease reset.

9. The new WebKit controller companion suite was not in the serialized lane.
   - `scripts/swift-test-helpers.sh` now includes
     `WebKitSerializedTests/BridgePaneControllerContentAuthorityTests`, with a
     script guard test.

## Proof

Red evidence was captured before fixes for the stale dev-provider/fixture URL
path, stable-decoded traversal/slash parser cases, missing Swift lease
replacement API, and HEAD provider materialization behavior.

Green proof from the current worktree:

```bash
pnpm --dir BridgeWeb run check
```

Result: exit 0.

```bash
pnpm --dir BridgeWeb exec vitest run \
  src/core/resources/bridge-resource-registry.unit.test.ts \
  src/bridge/bridge-resource-url.unit.test.ts \
  src/review-viewer/content/review-content-registry.unit.test.ts \
  src/review-viewer/content/review-content-loader.unit.test.ts \
  src/review-viewer/projections/review-item-window-registry.unit.test.ts \
  src/review-viewer/test-support/bridge-viewer-mocked-backend.unit.test.ts \
  scripts/dev-server/bridge-worktree-dev-provider.integration.test.ts \
  src/foundation/review-package/bridge-contract-fixtures.unit.test.ts
```

Result: exit 0, 8 files passed, 68 tests passed.

```bash
pnpm --dir BridgeWeb exec vitest run \
  scripts/bridge-viewer-browser-benchmark-runner.unit.test.ts
```

Result: exit 0, 1 file passed, 8 tests passed.

```bash
bash scripts/bridge-web-sync-fixtures.sh --check
```

Result: exit 0, 17 fixture files in sync.

```bash
SWIFT_TEST_SKIP_PREBUILD=1 SWIFT_TEST_TIMEOUT_SECONDS=60 \
SWIFT_TEST_PREBUILD_TIMEOUT_SECONDS=180 mise run test-fast -- --filter \
  'BridgeSchemeHandlerTests|BridgeSchemeHandlerLeaseAuthorityTests|BridgeGitReviewSourceProviderTests|BridgeReviewDeltaBuilderTests|BridgePushEnvelopeEncoderTests|BridgeReviewFoundationContractTests'
```

Result: exit 0, 74 tests in 6 suites passed.

```bash
SWIFT_TEST_SKIP_PREBUILD=1 SWIFT_TEST_TIMEOUT_SECONDS=60 \
SWIFT_TEST_PREBUILD_TIMEOUT_SECONDS=180 mise run test-fast -- --filter \
  'AgentStudioIPCBridgeServiceTests|AgentStudioAppIPCServiceTests'
```

Result: exit 0, 31 tests in 2 suites passed.

```bash
SWIFT_TEST_SKIP_PREBUILD=1 SWIFT_TEST_TIMEOUT_SECONDS=60 \
SWIFT_TEST_PREBUILD_TIMEOUT_SECONDS=180 mise run test-webkit
```

Result: exit 0, WebKit serialized lane passed in 62.52s. The lane explicitly
ran `WebKitSerializedTests/BridgePaneControllerContentAuthorityTests`, including
`loadDiff revokes previous content authority before failed reload`.

```bash
mise run format && mise run lint
```

Result: exit 0, Swift format, SwiftLint, AgentStudio architecture lint, and
release script verification passed.

```bash
rg -n "agentstudio://resource/content/" BridgeWeb Sources Tests scripts \
  --glob '!BridgeWeb/scripts/check-bridgeweb-architecture.unit.test.ts' \
  --glob '!Tests/AgentStudioTests/Features/Bridge/BridgeSchemeHandlerTests.swift'
```

Result: exit 1, no active-source legacy content URL matches outside intentional
negative fixtures.

## Residual Scope Note

Broad Swift health is still not claimed for ticket 01. The previously recorded
external `CommandBarDataSourceTests/test_commandsScope_includesOpenBridgeReview`
title mismatch remains outside this ticket's transport/security write scope.

phase_result: complete
evidence: current worktree patch, this report, and the commands above
recommended_next_workflow: shravan-dev-workflow:implementation-review-swarm
recommended_transition_reason: Ticket 01 second-review findings are addressed
with fresh scoped proof; the Bridge trust/transport boundary needs review again
before ticket 02 begins.
