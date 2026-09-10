# Rolling subscription update history

This supplements the existing PR A transport reliability boundary. It does not
change File/Review presentation, comment persistence, metadata content policy,
or the three product transport routes.

Decision owner: Agent Studio owner. Source: the 2026-09-06 discussion selecting
a rolling window/ring buffer rather than a lifetime history cap.

| ID | Authorized need | Affected consumers | Priority and authority |
| --- | --- | --- | --- |
| RU-U1 | Long-lived subscriptions continue processing valid interest changes without exhausting a lifetime history count. | File and Review users; their shared metadata transport | Required for PR A stability; owner-authorized |
| RU-U2 | Recent accidental update-ID reuse remains detectable with bounded memory; older labels need not be remembered forever. | Worker/native protocol consumers | Required within the selected rolling-window correction; owner-authorized |
| RU-U3 | Retries, stale requests, malformed batches and failed commits must not duplicate or partially apply work. | All shared transport consumers | Existing transport guarantee retained by owner direction |

The selected complexity boundary is existing-owner, count-based rolling history;
no timers, persistence, heartbeat, restart system, new wire route or payload body.
Unknown native recovery and aggregate/release readiness remain separate proof
obligations; this correction alone does not establish completion of PR A.

Observable contract: [R64](../bridge-viewer-transport/local-first-comm-worker-architecture.md#r64-swift-product-requests-and-streams-are-framed-capable-and-cancellable).
Internal realization: [Recent subscription update IDs](../../architecture/bridge/bridge_product_transport_architecture.md#recent-subscription-update-ids).
