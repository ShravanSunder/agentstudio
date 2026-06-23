# Ticket 01 Fifth Review Fix Report

## Scope

This report covers the post-`e076fc4b` ticket-01 fifth-review fix and the
follow-up patch after review of `57601c5b`. Ticket 02 remains blocked until the
latest authority follow-up is reviewed.

Accepted findings addressed:

- P1: content store activation could become visible before the
  revocation-revision-checked lease replacement succeeded.
- P1: IPC content loads read directly from `BridgeContentStore` after teardown
  without consulting the synchronous review/content authority gate.
- P2: direct lease registration could bypass the revocation-revision contract.
- P2: same-generation content preservation used full `BridgeContentHandle`
  equality instead of the explicit content authority identity.
- P2: workflow-state/checkpoint text still pointed at the third-review pass.
- P2: the previous fourth-review proof packet overclaimed green-only proof.

Additional accepted findings from review of `57601c5b`:

- P1: teardown could still be captured as the expected revocation revision by
  an in-flight `loadDiff` after `clearReviewContentAuthority()` suspended.
- P1: active content-policy fields were not fully enforced when cache or
  in-flight bytes were re-used.
- P2: `BridgeTransportResourceLeaseRegistry.replace` still allowed callers to
  omit the expected revocation revision.
- P2: IPC proof covered teardown before a call but not teardown while a
  provider-backed content load was in flight.
- P2: the proof packet overclaimed the lease-first activation fix without a
  strong enough post-review proof set.

Additional accepted findings from review of `b68c70ea`:

- P1: a superseding review load could still leave the previous content
  authority usable while the new load was waiting on provider comparison work.
- P1: scheme-handler content emission checked lease authority before yielding,
  but revocation could land between the final check and response/data emission.
- P2: the oversized-content scheme-handler proof asserted the final thrown
  error, but did not prove that zero response/data events were emitted first.

Non-blocking follow-up from review of `b68c70ea`:

- Cache hits and coalesced content reads now rehash full payloads when active
  policy is revalidated. This is correct for ticket 01 authority, but should be
  revisited as a performance follow-up before larger content workloads.

## Implementation

- `BridgePaneController+DiffCommands.activateReviewContentHandles` now installs
  review/content leases through the revocation-revision-fenced registry before
  activating handles in `BridgeContentStore`.
- `BridgePaneController+IPCProjection.loadContentForIPC` checks the
  synchronous review/content revocation gate before and after content load.
- `BridgeTransportResourceLeaseRegistry.register` now requires an
  `expectedRevocationRevision` argument and passes it through the same
  authority gate as `replace`.
- `BridgeContentStore` now names `ContentHandleAuthority` explicitly and uses
  that identity for post-await validation. Non-authority metadata such as
  MIME type, language, cache key, and size byte hints no longer invalidates an
  otherwise identical same-generation in-flight load.
- Bridge tests were updated to pass the expected initial revision for direct
  registrations, with a dedicated stale-revision regression.

Follow-up implementation in `b68c70ea`:

- `BridgePaneController` now carries a review-content authority lifetime fence.
  `loadDiff` and refresh capture that lifetime before clearing authority, and
  activation rejects if teardown advanced it before or after lease replacement.
- `BridgeContentStore` normalizes cached, coalesced, and provider-loaded bytes
  onto the current active handle before returning them. It revalidates active
  policy including hash algorithm, binary flag, and active byte cap.
- `BridgeTransportResourceLeaseRegistry.replace` now requires an
  `expectedRevocationRevision` argument.
- IPC and scheme tests now prove in-flight teardown, active byte-cap
  invalidation, stale replace rejection, and oversized content rejection at the
  materialization boundary.

Follow-up implementation in `4c4c7773`:

- `loadDiff` now synchronously revokes the previous review/content authority
  before any async provider comparison work can suspend. The async cleanup keeps
  the already-advanced revocation revision stable for the replacement fence.
- Teardown reuses the same synchronous review/content revocation path and then
  performs async store/lease cleanup without advancing the authority revision a
  second time.
- Scheme-handler response and body emission now run under the same synchronous
  authority gate used by revocation. That closes the check/yield gap for
  revoked content leases.
- The oversized-content scheme-handler test now records emitted events and
  asserts zero response/data events before the oversized-content failure.
- A controller regression proves a second `loadDiff` revokes the previous
  content authority while the reload is still blocked inside provider
  comparison.

## Red / Green Notes

Green proof was collected on the current worktree.

Red-proof attempt:

- A detached scratch worktree was created at `tmp/red-proof-e076fc4b` pinned to
  `e076fc4b`.
- The new content-store same-authority metadata regression was injected into
  that old checkout.
- Command attempted:
  `MISE_TRUSTED_CONFIG_PATHS=.../tmp/red-proof-e076fc4b/.mise.toml SWIFT_TEST_TIMEOUT_SECONDS=60 SWIFT_TEST_PREBUILD_TIMEOUT_SECONDS=180 mise run test-fast -- --filter 'BridgeContentStoreTests/contentStorePreservesSameAuthorityInFlightLoadsWhenNonKeyMetadataChanges'`
- Result: blocked before test execution because the detached scratch checkout
  lacks the vendored `Frameworks/GhosttyKit.xcframework` artifact.
- This means the prior green-only proof gap is explicitly recorded rather than
  hidden. The current pass adds focused regressions for the accepted issues and
  proves them green in the primary worktree.

## Proof

- `SWIFT_TEST_TIMEOUT_SECONDS=60 SWIFT_TEST_PREBUILD_TIMEOUT_SECONDS=180 mise run test-fast -- --filter 'BridgeContentStoreTests|BridgeSchemeHandlerLeaseAuthorityTests'`
  - exit 0
  - 24 tests in 2 suites passed.
- `SWIFT_TEST_TIMEOUT_SECONDS=60 SWIFT_TEST_PREBUILD_TIMEOUT_SECONDS=180 mise run test-webkit`
  - exit 0
  - WebKit serialized lane passed in 96.77s.
  - Included `BridgePaneControllerIPCProjectionTests` with 6 tests, including
    `IPC content body rejects content after teardown revokes review authority`.
- `mise run lint`
  - exit 0
  - swift-format: OK.
  - SwiftLint: 0 violations in 1307 files.
  - AgentStudio architecture lint: OK.
  - release script verification: passed.
- `SWIFT_TEST_TIMEOUT_SECONDS=60 SWIFT_TEST_PREBUILD_TIMEOUT_SECONDS=180 mise run test-fast -- --filter 'BridgeContentStoreTests|BridgeSchemeHandlerTests|BridgeSchemeHandlerLeaseAuthorityTests'`
  - exit 0
  - 75 tests in 3 suites passed.

Post-review follow-up proof for `b68c70ea`:

- `mise run format`
  - exit 0
  - Swift sources formatted.
- `SWIFT_TEST_TIMEOUT_SECONDS=60 SWIFT_TEST_PREBUILD_TIMEOUT_SECONDS=180 mise run test-fast -- --filter 'BridgeContentStoreTests|BridgeSchemeHandlerLeaseAuthorityTests'`
  - exit 0
  - 27 tests in 2 suites passed.
- `SWIFT_TEST_TIMEOUT_SECONDS=60 SWIFT_TEST_PREBUILD_TIMEOUT_SECONDS=180 mise run test-webkit`
  - exit 0
  - WebKit serialized lane passed in 99.44s.
  - Included `BridgePaneControllerIPCProjectionTests` with 8 tests, including
    in-flight teardown and active byte-cap IPC regressions.
- `SWIFT_TEST_TIMEOUT_SECONDS=60 SWIFT_TEST_PREBUILD_TIMEOUT_SECONDS=180 mise run test-fast -- --filter 'BridgeContentStoreTests|BridgeSchemeHandlerTests|BridgeSchemeHandlerLeaseAuthorityTests'`
  - initial exit 1 because the oversized scheme-handler test still expected
    `.invalidRoute` after content-store byte-cap validation moved the rejection
    to `.oversizedContent`.
  - rerun exit 0 after correcting the test to the materialization boundary.
  - 78 tests in 3 suites passed.
- `mise run lint`
  - exit 0
  - swift-format: OK.
  - SwiftLint: 0 violations in 1307 files.
  - AgentStudio architecture lint: OK.
  - release script verification: passed.

Post-review follow-up proof for `4c4c7773`:

- `mise run format`
  - exit 0
  - Swift sources formatted.
- `SWIFT_TEST_TIMEOUT_SECONDS=60 SWIFT_TEST_PREBUILD_TIMEOUT_SECONDS=180 mise run test-fast -- --filter 'BridgeContentStoreTests|BridgeSchemeHandlerTests|BridgeSchemeHandlerLeaseAuthorityTests'`
  - exit 0
  - 78 tests in 3 suites passed.
- `mise run lint`
  - first exit 1 because `BridgeSchemeHandlerTests` crossed the 800-line type
    body cap at 803 lines after the zero-emission proof edit.
  - final exit 0 after compacting that proof without weakening it.
  - swift-format: OK.
  - SwiftLint: 0 violations in 1307 files.
  - AgentStudio architecture lint: OK.
  - release script verification: passed.
- `SWIFT_TEST_TIMEOUT_SECONDS=60 SWIFT_TEST_PREBUILD_TIMEOUT_SECONDS=180 mise run test-webkit`
  - exit 0
  - WebKit serialized lane passed in 99.82s.
  - Included `BridgePaneControllerContentAuthorityTests` with 6 tests,
    including the new in-flight reload synchronous revocation regression.

## Next Step

Route `4c4c7773` back to `shravan-dev-workflow:implementation-review-swarm`
before starting ticket 02.
