# UUIDv7 Identity Follow-up

## TODO

- Inventory remaining durable application entities whose default constructors still mint UUIDv4 values with `UUID()`.
- Cut those entity-owned defaults over to `UUIDv7.generate()` or their existing typed UUIDv7 helper.
- Preserve restored and imported identifiers verbatim.
- Add focused UUID-version tests and an architecture enforcement rule only after the intended durable-identity scope is settled.
- Keep ephemeral correlation, waiter, subscription, temporary-file, OAuth, and other opaque tokens outside this follow-up unless their owning contract explicitly changes.

This follow-up is intentionally separate from PR #254. The current PR changes only newly created `Tab` identities.
