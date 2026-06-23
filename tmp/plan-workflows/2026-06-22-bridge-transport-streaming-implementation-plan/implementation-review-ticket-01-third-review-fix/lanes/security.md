# Security Lane

Agent: `019ef29e-e3ee-74a3-a2d0-9571767c0840`

Verdict: important finding accepted and fixed.

Finding:

- `activateReviewContentHandles` ignored `BridgeTransportResourceLeaseRegistry.replace`
  failure. A malformed refresh could cause replacement to fail while old
  review/content leases stayed live and the pane advanced to the new package
  state.

Disposition:

- Accepted.
- Content-handle activation now builds content-only leases before mutating the
  store, validates handle id, generation, kind, and byte count, and throws on
  invalid metadata.
- `replace == false` now clears review content authority and throws instead of
  silently preserving stale leases.
- Refresh validation failures before new authority installation leave the
  previous valid package and previous valid leases together.

Proof:

- `WebKitSerializedTests/BridgePaneControllerContentAuthorityTests`
  - `refresh preserves previous content authority when new metadata is invalid`
  - `loadDiff revokes previous content authority before failed reload`
  - `teardown synchronously revokes review content leases`
- Full WebKit serialized lane: exit 0, 90.70s.
