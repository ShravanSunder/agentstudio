# Ticket 01 Implementation Review Report

Date: 2026-06-22
Goal id: `2026-06-22-bridge-transport-streaming`
Reviewed range: `bbf9e51c..00d22ce0`
Reviewed commit: `00d22ce0 feat: add bridge transport contracts`
Mode: implementation review

## Verdict

`not_ready`

Ticket 01 must route back to `shravan-dev-workflow:implementation-execute-plan`
before ticket 02 begins.

Reason:

- The page-world command relay still forwards method-only privileged RPC names,
  which can become a ticket-02 stream-open bypass.
- Resource capability authority is still URL-string membership, not
  descriptor-bound lease authority.
- The implemented core contracts do not fully match the architecture contract:
  id grammar, integrity variants, URL/resource parity, and registry lifecycle
  are under-specified in code.
- Ticket proof is strong for the implemented subset, but it does not prove the
  full ticket-01 trust-boundary contract.

## Accepted Findings

### 1. Blocker: page-world relay can still forward method-only privileged RPC

Evidence:

- `Sources/AgentStudio/Features/Bridge/Transport/BridgeBootstrap.swift:123`
  forwards nonce-bearing `__bridge_command` payloads unless `protocol` is
  present.
- `Sources/AgentStudio/Features/Bridge/Transport/BridgeBootstrap.swift:170`
  writes the nonce onto `documentElement`, so page-world code can read it.
- `Sources/AgentStudio/Features/Bridge/Transport/RPCRouter.swift:264` dispatches
  by `method`; the current Swift RPC envelope does not enforce protocol
  provenance.
- `Tests/AgentStudioTests/Features/Bridge/BridgeContentWorldIsolationTests.swift:59`
  only proves the `{ protocol: "review", method: "stream.open" }` shape is
  rejected.
- `tmp/spec-workflows/2026-06-22-bridge-transport-streaming-spec/spec.md:420`
  requires Bridge APIs to exist only in the isolated Bridge content world.

Scenario:

When ticket 02 registers a privileged method such as `review.openStream`,
page-world script can dispatch `__bridge_command` with a readable nonce and
`method: "review.openStream"` but no `protocol`. The bootstrap forwards it to
Swift, and the router dispatches by method.

Smallest useful fix:

- Make page-world `__bridge_command` a narrow legacy allowlist or reject all
  privileged method names regardless of `protocol`.
- Add a Swift-side provenance guard for privileged protocol methods so the host
  does not depend only on bootstrap filtering.

Proof:

- Add a WebKit negative test that sends page-world
  `method: "review.openStream"` without `protocol` and proves the RPC handler
  receives nothing.
- Keep the content-world positive path passing.

Sources: security/trust-boundary lane, contracts/proof lane, parent reducer.
Confidence: high.

### 2. Blocker: descriptor and lease authority are not descriptor-bound

Evidence:

- `BridgeWeb/src/core/models/bridge-resource-descriptor.ts:35` accepts any
  non-empty `resourceUrl`.
- `BridgeWeb/src/core/resources/bridge-resource-registry.ts:39` validates schema
  and ref identity but never parses or matches `descriptor.resourceUrl`.
- `Sources/AgentStudio/Features/Bridge/Transport/BridgeTransportResourceLeaseRegistry.swift:3`
  stores only canonical URL strings.
- `Sources/AgentStudio/Features/Bridge/Transport/BridgeSchemeHandler.swift:78`
  authorizes leased content with protocol/kind checks, generation presence, and
  `contains(resource)`.
- `tmp/spec-workflows/2026-06-22-bridge-transport-streaming-spec/spec.md:400`
  requires lease binding to pane, protocol/kind, source/package identity,
  generation/revision/cursor, descriptor id, limits, and expiry/revocation.

Scenario:

An accepted descriptor can point its `resourceUrl` at a different capability
than its ref/identity. On the Swift side, a capability is authorized by URL
membership instead of the descriptor id and authority tuple. Resets, revokes,
cross-pane replay, changed limits, or changed cursor/revision are therefore not
structurally enforced before ticket 02 consumes descriptor-backed resources.

Smallest useful fix:

- Parse and canonicalize `descriptor.resourceUrl` at registration time.
- Require URL protocol/kind/generation/revision/cursor to match the attached
  descriptor ref and identity.
- Replace the Swift URL set with a structured lease record keyed by descriptor
  authority: pane id, descriptor id, protocol/kind, source/package identity,
  generation/revision/cursor, limits, and expiry/revoked/reset state.
- Re-check lease validity after async content load and before yielding response
  or data.

Proof:

- TS unit tests: reject attached descriptors whose `resourceUrl` disagrees with
  ref protocol/kind/generation/revision/cursor or is malformed.
- Swift tests: reject cross-pane, revoked, post-reset, wrong revision/cursor,
  and revoked-during-load fetches.

Sources: spec-compliance lane, security/trust-boundary lane,
reliability/adversarial lane, contracts/proof lane, parent reducer.
Confidence: high.

### 3. Blocker: core contract implementation does not yet match the spec contract

Evidence:

- `tmp/spec-workflows/2026-06-22-bridge-transport-streaming-spec/spec.md:214`
  says schema examples are architecture contracts and fields/invariants must be
  represented.
- `BridgeWeb/src/core/models/bridge-core-models.ts:3` models protocol ids and
  resource kinds as `z.string().min(1)`.
- `BridgeWeb/src/core/models/bridge-resource-descriptor.ts:10` models integrity
  as `{ algorithm, value }`, not the spec union with `wholeHash`,
  `chunkManifest`, and `previewOnly`.
- `BridgeWeb/src/core/models/bridge-protocol-registry.ts:54` seeds `review` and
  `worktree-file` defaults in generic core.
- `Tests/BridgeContractFixtures/valid/transport-resource-url-corpus.json:2`
  contains hyphenated protocol/resource names that contradict the current spec
  regex.

Scenario:

Ticket 02 would build Review demand/materialization on a contract surface that
already disagrees with the accepted spec. The next slice would either encode
extra compatibility into Review or silently fork the source of truth.

Smallest useful fix:

- Reconcile the spec grammar with actual intended names before implementation
  continues. Either the spec regex must allow hyphenated ids/kinds, or the
  default names must change.
- Implement the agreed id/kind grammar in TS and Swift fixtures.
- Model integrity as the agreed discriminated union. First implementation may
  keep `chunkManifest` reserved and `previewOnly` non-authoritative, but the
  contract must be expressible.
- Move seeded app protocol registrations out of generic core into app/test
  wiring or clearly mark them as test fixtures.

Proof:

- Unit tests that accepted protocol ids/resource kinds pass the canonical
  grammar on both TS and Swift sides.
- Integrity tests for `wholeHash`, `previewOnly`, and reserved/fail-closed
  `chunkManifest`.

Sources: spec-compliance lane, contracts/proof lane, parent reducer.
Confidence: high.

### 4. Important: legacy scheme route still bypasses fail-closed parser and method contract

Evidence:

- `Sources/AgentStudio/Features/Bridge/Transport/BridgeSchemeHandler.swift:156`
  falls back to the legacy `/content/<handle>?generation=<n>` route.
- `Sources/AgentStudio/Features/Bridge/Transport/BridgeSchemeHandler.swift:185`
  reads the first `generation` query item and ignores duplicate/unknown query
  keys.
- `Sources/AgentStudio/Features/Bridge/Transport/BridgeSchemeHandler.swift:32`
  does not inspect `request.httpMethod`.
- `tmp/spec-workflows/2026-06-22-bridge-transport-streaming-spec/spec.md:379`
  requires duplicate/unknown query rejection and GET/HEAD-only reads.

Scenario:

The live compatibility route can still load bytes for
`agentstudio://resource/content/<handle>?generation=7&generation=8&path=/tmp/a`
or non-GET methods. That keeps the currently shipped content path outside the
new parser contract while it remains enabled.

Smallest useful fix:

- Enforce GET/HEAD-only before serving app/resource routes.
- Apply duplicate/unknown-key rejection to the legacy route while it remains
  live, or route legacy URLs through an explicit compatibility parser with the
  same fail-closed posture.

Proof:

- Swift tests for POST rejection and HEAD no-body behavior.
- Swift tests for duplicate/unknown query rejection on the legacy content route.

Sources: security/trust-boundary lane, contracts/proof lane, parent reducer.
Confidence: high.

### 5. Important: TS/Swift resource URL parity misses encoded path separators

Evidence:

- `BridgeWeb/src/core/resources/bridge-resource-url.ts:108` decodes each path
  segment but does not reject decoded `/`.
- `Sources/AgentStudio/Features/Bridge/Models/Transport/BridgeTransportResourceURL.swift:72`
  rejects decoded segments containing `/`.
- The shared corpus has no `%2F` or `%252F` case.

Scenario:

`agentstudio://resource/review/content/a%2Fb?...` can parse in TS as opaque id
`a/b` but reject in Swift. Descriptor materialization can therefore accept a
resource that the host cannot fetch.

Smallest useful fix:

- Decide the grammar. The safer ticket-01 choice is to reject decoded `/` in
  every path segment.
- Add shared `%2F` and `%252F` reject fixtures and align TS with Swift.

Proof:

- Shared corpus cases pass in TS and Swift.

Sources: contracts/proof lane, parent reducer.
Confidence: high.

### 6. Important: descriptor registry has no lifecycle/reset surface

Evidence:

- `BridgeWeb/src/core/resources/bridge-resource-registry.ts:24` exposes only
  `register` and `lookup`.
- `BridgeWeb/src/core/resources/bridge-resource-registry.ts:34` stores
  descriptors in a monotonic map with no revoke/reset/delete path.

Scenario:

Ticket 02/04 need source reset, cursor replacement, and stale descriptor
cleanup. With no registry lifecycle API, callers either leak descriptors or
replace the entire registry out-of-band.

Smallest useful fix:

- Add explicit revoke/reset lifecycle operations keyed by descriptor authority,
  or scope registry instances to a lineage and make replacement explicit in the
  contract.

Proof:

- Unit tests for post-reset lookup failure and generation/cursor churn cleanup.

Sources: reliability/adversarial lane, parent reducer.
Confidence: high.

## Rejected Or Deferred Candidates

- The integrity helper not being wired into a production descriptor fetch path is
  not a separate runtime exploit in ticket 01 because that production path is not
  implemented yet. It is accepted as part of the broader contract/proof blocker.
- The broad Swift `test-fast` failure in `CommandBarDataSourceTests/
  test_commandsScope_includesOpenBridgeReview` remains outside ticket-01 scope.
  It is a broad health blocker for final/milestone proof, not an accepted
  implementation finding in this transport review.

## Review Proof

Checked implementation proof against the slice requirements:

- Passed scoped Browser/Vitest proof for the implemented models/resources/RPC
  helper.
- Passed fixture sync.
- Passed `pnpm --dir BridgeWeb run check`.
- Passed `mise run test-webkit`.
- Passed focused Swift `BridgeSchemeHandlerTests|BridgeBootstrapTests`.
- Passed `mise run lint`.
- Broad Swift health is open due the unrelated CommandBar title mismatch.

Proof gap:

The successful gates prove the implemented subset, but not the full ticket-01
contract. Missing proof includes page-world method-only privileged RPC negative
test, descriptor-bound lease authority, revoke/reset/cross-pane/stale lease
cases, legacy route fail-closed method/query behavior, integrity union semantics,
and TS/Swift encoded-slash parity.

No weakened proof lanes were accepted. The proof split for unrelated broad
Swift health remains valid.

## Swarm Coverage

- Spec compliance lane: `019ef237-26ca-77a3-8444-303008b47b2f`, completed,
  accepted findings 2, 3.
- Security/trust-boundary lane: `019ef237-7d35-7a30-ac51-10b4c8423b7c`,
  completed, accepted findings 1, 2, 4.
- Contracts/tests/proof lane: `019ef237-cb98-7182-b5a8-1936fdef8407`,
  completed, accepted findings 3, 4, 5.
- Reliability/performance/adversarial lane:
  `019ef238-0245-7963-8197-549ec9edc3cd`, completed, accepted findings 2, 3,
  6.
- External model lanes: none requested, none run.

## Routing Follow-Through

Route accepted findings back to `shravan-dev-workflow:implementation-execute-plan`.

Required next implementation batch before ticket 02:

1. Patch page-world privileged RPC rejection and host-side provenance/allowlist
   for privileged protocol methods.
2. Patch descriptor/resource/lease contracts so authority is descriptor-bound
   and lifecycle-aware.
3. Reconcile id/kind grammar and integrity union with the spec.
4. Patch legacy route method/query fail-closed behavior while compatibility
   remains live.
5. Patch shared URL corpus for encoded slash parity.
6. Add lifecycle/reset API or explicit lineage scoping for descriptor registry.
7. Re-run ticket-01 proof gates and update checkpoint proof.

Do not start ticket 02 until this review is addressed and re-reviewed or the
parent reducer records a narrower accepted residual risk with explicit user
approval.
