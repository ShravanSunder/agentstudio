# CI Swift build cache — Requirements

Status: reviewed (advisor rounds 4–5 in tmp/ci-speed/, round-5 remediation applied) · 2026-09-27 · Owner decision: option B.

Artifacts: [Requirements](2026-09-27-ci-swift-build-cache-requirements.md) · [Specification](2026-09-27-ci-swift-build-cache.md) · [Program Design](2026-09-27-ci-swift-build-cache-program-design.md)

## Requirements

| Id | Need | Authority |
|---|---|---|
| U1 | Pull-request Swift CI finishes faster, toward the 20-minute goal. | Owner, CI program 2026-09-26 |
| U2 | A PR's green result is as trustworthy as a cold build's: no stale object may make a changed input look unchanged. | Owner: "tests not be trash"; advisor rounds 4–5 |
| U3 | The repository's Actions cache stays inside 10 GB, cleaned up by the workflow, with no entry saved where nothing can restore it. | Owner cache constraint 2026-09-26; #386 |
| U4 | Main remains the uncompromised cold proof. | Owner decision B |

Non-goals: caching BridgeWeb, vendor or tool outputs (they have their own caches); speeding up the main job; an absolute repository-wide size guarantee (other writers and eviction exist; a miss is always a correct cold build).
