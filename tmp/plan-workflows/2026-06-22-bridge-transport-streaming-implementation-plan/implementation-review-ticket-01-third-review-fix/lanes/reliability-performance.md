# Reliability / Performance Lane

Agents:

- `019ef29f-144a-7a52-86bf-cff85b620cfd`
- `019ef29f-40d9-7c93-9621-8d6233d02c65`
- `019ef29e-8053-7320-a61c-f537b9774996`

Verdict: important findings accepted and fixed.

Accepted findings:

- `BridgeContentStore.deactivate()` did not invalidate in-flight provider loads
  that ignored cancellation because `activeReviewGeneration == nil` was treated
  as success by generation validation.
- `BridgePaneController.teardown()` only enqueued async lease/store cleanup, so
  a first post-teardown fetch could observe still-live review/content leases.
- The first refresh-failure test encoded an inconsistent state: old package
  metadata visible while old content authority was revoked.

Disposition:

- Accepted.
- `BridgeContentStore` now tracks an authority revision. In-flight loads capture
  the revision and fail if activation/deactivation changes authority before the
  provider result returns.
- `BridgeTransportResourceLeaseRegistry` now has a synchronous authority gate.
  `BridgePaneController.teardown()` closes the review/content gate before it
  returns, while the actor still performs async cleanup.
- Refresh failures that occur before new authority is installed now preserve the
  old package and old authority together.

Proof:

- `BridgeContentStoreTests.contentStoreRejectsInFlightLoadsAfterDeactivation`
  failed before the authority-revision patch and passed after it.
- `BridgePaneControllerContentAuthorityTests.teardown_synchronously_revokes_review_content_leases`
  passed in the WebKit serialized lane.
- `BridgePaneControllerContentAuthorityTests.refresh_preserves_previous_content_authority_when_new_metadata_is_invalid`
  passed in the WebKit serialized lane.
