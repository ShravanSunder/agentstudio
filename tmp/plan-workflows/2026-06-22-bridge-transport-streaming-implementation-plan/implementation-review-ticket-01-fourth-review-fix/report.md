# Ticket 01 Fourth Review Follow-Up Fix

## Verdict

The follow-up review of `60fb99d7` returned `not_ready`.

Accepted findings fixed in this pass:

- Teardown could still be undone by an already-running `loadDiff` that reached
  content activation after teardown had synchronously revoked authority.
- Same-generation refreshes invalidated otherwise-valid in-flight content loads
  when the refreshed package preserved the same handle.
- Filtered lease resets silently black-holed surviving leases because the
  synchronous revocation gate ignored generation/revision/cursor filters.
- The invalid-refresh and teardown regression tests did not fully prove the
  stated contracts.
- The workflow event for the `60fb99d7` checkpoint recorded the wrong phase
  transition.

## Implementation Notes

- `BridgeTransportResourceLeaseRegistry` now tracks a revocation revision for
  review/content authority. Content activation captures the revision after its
  own authority reset and `replace(...)` refuses to re-authorize if teardown or
  another revocation advanced the revision before activation.
- Coarse `reset(...)` still closes the synchronous gate; filtered reset by
  generation/revision/cursor keeps its previous filter-accurate semantics.
- `BridgeContentStore` validates an in-flight result against the captured
  key/handle after awaits. If a same-generation refresh preserves the same
  handle, the load remains valid; if the handle is removed or authority is
  deactivated, it is rejected.
- Controller tests now prove invalid refresh preserves old package and old
  leases together, does not install the invalid new lease, and that teardown
  cannot be undone by a gated in-flight `loadDiff`.

## Proof

- `SWIFT_TEST_TIMEOUT_SECONDS=60 SWIFT_TEST_PREBUILD_TIMEOUT_SECONDS=180 mise run test-fast -- --filter 'BridgeContentStoreTests|BridgeSchemeHandlerLeaseAuthorityTests'`
  - exit 0
  - 22 tests in 2 suites passed.
- `SWIFT_TEST_TIMEOUT_SECONDS=60 SWIFT_TEST_PREBUILD_TIMEOUT_SECONDS=180 mise run test-webkit`
  - exit 0
  - WebKit serialized lane passed in 85.70s.
  - Explicitly ran 5 `BridgePaneControllerContentAuthorityTests`, including
    teardown-during-in-flight-loadDiff and invalid initial content handles.
- `mise run format`
  - exit 0
- `mise run lint`
  - exit 0
  - SwiftLint: 0 violations in 1307 files.
  - AgentStudio architecture lint: OK.
  - Release script verification: passed.
- `SWIFT_TEST_TIMEOUT_SECONDS=60 SWIFT_TEST_PREBUILD_TIMEOUT_SECONDS=180 mise run test-fast -- --filter 'BridgeContentStoreTests|BridgeSchemeHandlerTests|BridgeSchemeHandlerLeaseAuthorityTests'`
  - exit 0
  - 73 tests in 3 suites passed.

## Next Workflow

Route this fixed ticket-01 trust/transport authority pass back to
`shravan-dev-workflow:implementation-review-swarm` before ticket 02 begins.
