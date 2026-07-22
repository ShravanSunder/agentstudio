# Ticket 01 Third Review-Fix Report

Date: 2026-06-23
Goal id: `2026-06-22-bridge-transport-streaming`
Branch: `luna-338-pierreshikitrees-review-viewer-2`

## Verdict

Initial review verdict: `not_ready`.

Current disposition: accepted findings were fixed in the same checkpoint follow-up
and are ready for another implementation-review pass before ticket 02.

## Accepted Findings

1. Review content activation accepted too broad a URL allowlist and ignored
   `replace(false)`.
2. `BridgeContentStore.deactivate()` did not invalidate in-flight loads when
   provider tasks ignored cancellation.
3. Review-viewer allowlist narrowing lacked a permanent negative test.
4. `teardown()` left a post-return lease-authority race because cleanup was only
   enqueued asynchronously.
5. The first refresh-failure regression test asserted an inconsistent shell:
   old metadata visible with old authority revoked.

## Fixes

- Added `BridgeResourceProtocolRegistry.reviewContentResourceKinds` for
  content-handle activation.
- Changed content-handle activation to construct and validate the lease batch
  before mutating store authority.
- Treat `replace(false)` as fail-closed: clear authority and abort.
- Added an authority revision to `BridgeContentStore` so deactivation invalidates
  in-flight provider loads.
- Added a synchronous lease-authority gate to
  `BridgeTransportResourceLeaseRegistry`.
- Made `BridgePaneController.teardown()` synchronously close the review/content
  lease gate before returning.
- Corrected refresh failure behavior: invalid new metadata preserves the old
  package and old leases together.
- Added permanent regression tests for all accepted findings.

## Proof

Red proof:

- `SWIFT_TEST_TIMEOUT_SECONDS=60 SWIFT_TEST_PREBUILD_TIMEOUT_SECONDS=180 mise run test-fast -- --filter 'BridgeContentStoreTests|BridgeSchemeHandlerTests'`
  - exit 1 before the fix
  - `content store rejects in-flight loads after deactivation` failed because the
    stale provider load succeeded after deactivation.

Green proof:

- `SWIFT_TEST_TIMEOUT_SECONDS=60 SWIFT_TEST_PREBUILD_TIMEOUT_SECONDS=180 mise run test-fast -- --filter 'BridgeContentStoreTests|BridgeSchemeHandlerTests'`
  - exit 0
  - 70 tests in 2 suites passed.
- `SWIFT_TEST_TIMEOUT_SECONDS=60 SWIFT_TEST_PREBUILD_TIMEOUT_SECONDS=180 mise run test-webkit`
  - exit 0
  - WebKit serialized lane passed in 90.70s.
  - Explicitly ran 3 `BridgePaneControllerContentAuthorityTests`:
    failed reload revokes, invalid refresh preserves old authority, teardown
    synchronously revokes.

## Remaining Scope Guard

Broad Swift health is still not claimed. The unrelated
`CommandBarDataSourceTests/test_commandsScope_includesOpenBridgeReview` title
mismatch remains outside ticket-01 transport/security scope.

## Next Workflow

`shravan-dev-workflow:implementation-review-swarm`

Reason: ticket 01 still changes trust and transport boundaries. The fixed
authority path should be re-reviewed before ticket 02 starts.
