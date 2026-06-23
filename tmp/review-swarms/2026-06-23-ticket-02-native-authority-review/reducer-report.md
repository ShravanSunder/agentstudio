# Ticket 02 Native Authority Review Reducer

Date: 2026-06-23

Workflow:
`shravan-dev-workflow:implementation-review-swarm`

Scope:
Ticket 02 Review protocol vertical after the corrected closed-app boundary.
BridgeWeb is bundled in the Swift app; page-world Review frames are internal
transport/projection input. Native descriptor leases plus `BridgeSchemeHandler`
validation are byte-serving authority. HMAC/encryption are deferred hardening.

## Reviewer Lanes

Security/trust-boundary lane:

- Agent: `019ef5b8-3b8e-75f2-a23e-3d2d333f5a2a`
- Result: no findings.
- Basis: native lease/content authority tests and controller content authority
  tests cover stale, revoked, foreign/wrong-descriptor, replacement, oversized,
  teardown, failed reload, and invalid-handle authority rejection.
- Reducer decision: accepted as clean under the corrected closed-app boundary.

Spec/proof lane:

- Agent: `019ef5b7-df8c-7772-aac4-d7828ca5e820`
- Finding accepted: combined Swift proof did not honestly execute all named
  suites.
- Finding accepted: Ticket 02 proof text still treated full `test:dev-server`
  scroll canary as required, even though the red scroll canary is Ticket 03/04
  stable-extent work.
- Finding accepted: fixture sync and app-level telemetry/Zustand proof needed
  current evidence.

Reliability/contracts lane:

- Agent: `019ef5b8-96b0-7863-9674-3cd26f8f6524`
- Finding accepted: scheduler byte-cap wording overstated scheduler authority
  in the real selected Review demand path.
- Finding accepted: large bodies outside Zustand had inspection by code shape,
  but no focused regression test.

## Fixes Applied

- Removed the stale host-port-only Review protocol frame admission check from
  `BridgeWeb/src/app/bridge-app.tsx`. Review protocol frames can now materialize
  projection facts through the closed-app page-event path; native fetch authority
  remains with descriptor leases and the scheme handler.
- Updated the app integration test that previously expected page-world Review
  frames to be rejected at UI admission. It now asserts the corrected boundary:
  projection can render, but unauthorized content fetch rejection prevents body
  materialization.
- Added a Zustand boundary unit test in
  `BridgeWeb/src/review-viewer/state/review-viewer-store.unit.test.ts`, proving
  projection plus ready hydration status keeps fetched bodies, capability URLs,
  promises, controllers, and worker handles out of store state.
- Updated Ticket 02 plan/slice wording so Review selected-content demand uses
  the scheduler for per-role ordering and queue pressure, while the resource
  executor owns body-byte budgets.
- Updated Ticket 02 dev-server proof wording so `test:dev-server:worktree` and
  load/interaction smoke remain Ticket 02 proof, while the full
  `test:dev-server` bounded scroll canary remains Ticket 03/04 stable-extent
  work.

## Current Proof

Browser/TS:

- `pnpm --dir BridgeWeb run check`: exit 0.
- `pnpm --dir BridgeWeb exec vitest run src/review-viewer/state/review-viewer-store.unit.test.ts src/app/bridge-app.integration.test.tsx src/review-viewer/content/review-content-demand-loader.unit.test.ts --reporter dot`: exit 0, 3 files passed, 64 tests passed.
- `bash scripts/bridge-web-sync-fixtures.sh --check`: exit 0, 17 fixture files
  in sync.

Native authority:

- `SWIFT_TEST_TIMEOUT_SECONDS=120 SWIFT_TEST_PREBUILD_TIMEOUT_SECONDS=180 mise run test-fast -- --filter 'BridgeSchemeHandlerLeaseAuthorityTests|BridgeSchemeHandlerContentAuthorityTests'`: exit 0, 14 Swift Testing tests passed.
- Earlier same-boundary proof retained in workflow state:
  `AgentStudioTests.WebKitSerializedTests/BridgePaneControllerContentAuthorityTests`: exit 0, 6 Swift Testing tests passed.

Swift/WebKit split integration:

- `BridgeReviewProtocolFrameBuilderTests|BridgeBootstrapTests`: exit 0, 29
  Swift Testing tests passed.
- `AgentStudioTests.WebKitSerializedTests/BridgeTransportPushBoundaryTests`:
  exit 0, 1 Swift Testing test passed.
- Full `AgentStudioTests.WebKitSerializedTests/BridgeTransportIntegrationTests`:
  exit 1 with WebKit signal 5 after the first six tests passed and while
  starting `test_pushJSON_concurrentBurstDeliversOrderedPageEvents`.
- Split proof for remaining integration cases:
  `test_pushJSON_concurrentBurstDeliversOrderedPageEvents`,
  `test_handleDiffCommandWithSmokeProvider_rendersReviewViewerShell`,
  `test_contentFetch_traceparentHeaderReachesCustomSchemeHandler`, and
  `test_contentFetch_realDiffHandlesResolveAndDoNotRejectThroughReviewViewer`
  each exit 0 individually with 1 test passed.

Diff hygiene:

- `git diff --check` for touched browser/docs files: exit 0.

## Reducer Decision

Accepted review findings are addressed except for broad final validation still
to run after this reducer artifact lands. Ticket 02 can move to final
checkpoint packaging if `mise run lint` stays green and the handoff explicitly
records the WebKit full-suite signal as a split-proof harness caveat, not as a
hidden pass.
