# Ticket 01 Review-Fix Implementation Review

Date: 2026-06-22
Goal id: `2026-06-22-bridge-transport-streaming`
Reviewed commit: `f09d768a fix: close bridge transport review findings`
Mode: implementation review

## Verdict

`not_ready`

Reason:

- The page-world method-only RPC bypass is fixed, but descriptor/lease
  authority remains incomplete on the Swift host side.
- The legacy compatibility content route still exposes unleased page-facing
  content URLs, and route fail-closed proof is incomplete.

Ticket 01 must route back to `shravan-dev-workflow:implementation-execute-plan`
before ticket 02 begins.

## Accepted Findings

### 1. [blocker] Swift lease authority is still URL/pane-based, not descriptor-bound

Evidence:

- `Sources/AgentStudio/Features/Bridge/Transport/BridgeTransportResourceLeaseRegistry.swift`
  stores leases in `[canonicalURL: BridgeTransportResourceLease]`.
- `contains(_:, paneId:)` checks only pane id and `resource == lease.resource`.
- `descriptorId` and `maxBytes` are stored but never used for authorization.
- `Sources/AgentStudio/Features/Bridge/Transport/BridgeSchemeHandler.swift`
  authorizes protocol-scoped content by calling `contains(resource, paneId:)`.
- `tmp/spec-workflows/2026-06-22-bridge-transport-streaming-spec/spec.md`
  section 7.1 requires binding to pane, protocol/kind,
  source/package identity, generation/revision/cursor, descriptor id,
  limits, and revocation/reset.

Scenario:

Two descriptors in the same pane can share a canonical resource URL while
differing by descriptor id, limits, or source lineage. The current registry
collapses them into one URL entry. A stale descriptor can be authorized by a
newer descriptor with the same URL, or revoking one descriptor can remove the
other because revocation is URL-wide.

Fix:

Key and validate leases by a descriptor authority token instead of URL text
alone. At minimum, authorization must validate pane id, descriptor id,
protocol/kind, resource identity, generation/revision/cursor, limits, and
revocation/reset state.

Proof:

- Swift tests for same canonical URL with different descriptor ids.
- Swift tests for wrong descriptor id, wrong revision/cursor, cross-pane, and
  post-reset rejection.
- Existing revoke-during-load proof should remain.

Sources:

- spec compliance lane
- implementation proof lane
- contracts/tests lane
- parent reducer verification

### 2. [blocker] Legacy content route bypasses host lease authority

Evidence:

- `BridgeSchemeHandler.classifyPath` still falls back to
  `agentstudio://resource/content/<handle>?generation=<n>`.
- The `.content` route calls `emitContent` with `leasedResource: nil`.
- `emitContent` only performs lease rechecks when `leasedResource` is present.
- `BridgeContentHandleIdentity.resourceUrl(...)` still generates legacy URLs.
- `BridgePaneController+IPCProjection.swift` still exposes
  `handle.resourceUrl` in page-facing IPC summaries.
- `BridgeWeb/src/foundation/content/content-resource-loader.ts` fetches those
  URLs directly.

Scenario:

The new protocol-scoped route has lease checks, but the shipped page-facing
payloads still contain unleased legacy content URLs. Page-world code that can
read projected handle summaries can fetch review content through the legacy
route without using the trusted bridge-world RPC path or the host lease table.

Fix:

Either stop exposing legacy content URLs to page-facing payloads in this
checkpoint, or make the compatibility route enforce a host-side lease before
serving bytes. If compatibility must remain until ticket 02, it still needs an
explicit bounded authority story in the execution fix.

Proof:

- Swift negative test: unleased legacy content URL fails closed.
- Integration or WebKit proof that page-facing content loads still work through
  the chosen lease-backed compatibility path.

Sources:

- security/trust-boundary lane
- parent reducer verification

### 3. [blocker] Descriptor registry does not bind URL opaque id to descriptor authority

Evidence:

- `BridgeWeb/src/core/resources/bridge-resource-registry.ts`
  validates descriptor URL protocol, resource kind, generation, revision, and
  cursor.
- It does not validate the parsed URL `opaqueId`.
- `BridgeDescriptorRef` and `BridgeIdentity` do not carry an expected opaque
  resource id.

Scenario:

A descriptor can point at another content handle/resource within the same
lineage and still register successfully. That leaves the descriptor-to-resource
binding incomplete and allows wrong-resource substitution before ticket 02
starts consuming descriptors.

Fix:

Add an explicit resource id binding to the descriptor/ref contract, or otherwise
make descriptor id/resource id equivalence enforceable. Reject descriptors whose
resource URL opaque id does not match that binding.

Proof:

- TypeScript registry test where protocol/kind/generation/revision/cursor match
  but opaque id differs and registration fails.

Sources:

- reliability/performance lane
- parent reducer verification

### 4. [important] OPTIONS/HEAD route contract is inconsistent

Evidence:

- `BridgeSchemeHandler.readMethod` accepts only `GET` and `HEAD`.
- `BridgeSchemeHandler.response(...)` still advertises
  `Access-Control-Allow-Methods: GET, OPTIONS`.
- `HEAD` is supported by code but omitted from the advertised methods.
- There is no permanent `OPTIONS` or `HEAD` route test.

Scenario:

If a Bridge resource request is preflighted, `OPTIONS` currently reaches the
unsupported-method path even though the response headers advertise it. HEAD also
has behavior but is not advertised.

Fix:

Implement an explicit `OPTIONS` response path with headers only, include `HEAD`
in the allowed methods header, and keep non-read methods such as `POST`
rejected.

Proof:

- Swift `OPTIONS` test returning CORS headers with no body/load.
- Swift `HEAD` test returning headers with no body/load.

Sources:

- reliability/performance lane
- parent reducer verification

### 5. [important] Legacy route fail-closed proof is incomplete

Evidence:

- `generationValue(from:)` now rejects duplicate/unknown query keys.
- Permanent Swift proof currently covers `POST` rejection, but not HEAD no-body,
  duplicate generation, or unknown query-key rejection on the legacy route.

Scenario:

The implementation may be correct, but the checkpoint proof does not lock the
legacy compatibility route's fail-closed behavior.

Fix:

Add focused permanent Swift tests for duplicate `generation`, unknown query
keys, and HEAD no-body behavior on legacy content URLs.

Proof:

- Focused `BridgeSchemeHandlerTests` cases.

Sources:

- implementation proof lane
- parent reducer verification

### 6. [important] Swift scheme handler still owns a hardcoded protocol/kind registry

Evidence:

- `BridgeSchemeHandler.allowedResourceKindsByProtocol` hardcodes
  `review` and `worktree-file` allowed resource kinds.
- TypeScript removed the generic default protocol registry after the first
  review.

Scenario:

Production Swift and TypeScript can drift: TS registration is caller-owned, but
Swift parser acceptance is hardcoded inside the scheme handler. That weakens
the generic Bridge boundary and makes future app protocol additions edit
transport code.

Fix:

Inject the allowed protocol/resource-kind registration into
`BridgeSchemeHandler` or move it to an app-owned registration boundary that the
scheme handler receives.

Proof:

- Swift tests proving `BridgeSchemeHandler` uses injected allowed kinds.
- Shared fixture path continues to validate the same accepted/rejected corpus.

Sources:

- contracts/tests lane
- parent reducer verification

## Verified Fixed From First Review

- Page-world method-only privileged RPC names are blocked in bootstrap and
  rejected again in `RPCRouter` when marked as `pageWorldLegacy`.
- TypeScript id grammar now matches the accepted dotted/hyphenated grammar.
- Integrity descriptors now use `wholeHash`, `chunkManifest`, and
  `previewOnly`, with chunk manifests fail-closed and preview-only
  non-authoritative.
- TypeScript resource URLs reject encoded and double-encoded path separators.
- Descriptor registry exposes lifecycle APIs, but the descriptor-bound
  authority model is still incomplete due the opaque-id and Swift-lease
  findings above.

## Review Proof

Implementation proof was checked against:

- `f09d768a`
- `implementation-execute-plan-brief.md`
- `implementation-review-ticket-01-report.md`
- `slices/01-transport-contracts.md`
- `spec.md` sections 6, 7, 7.1, 7.2, 12, and 13

Proof accepted as fresh:

- Browser contract tests: exit 0, 9 files / 42 tests.
- Fixture sync: exit 0, 17 files in sync.
- BridgeWeb check: exit 0.
- Real WebKit serialized lane: exit 0.
- Focused Swift Bridge gate: exit 0, 96 tests in 4 suites.
- `mise run lint`: exit 0.

Proof gap:

- The proof does not cover descriptor id/limit/reset authority in Swift leases.
- The proof does not cover opaque-id substitution in descriptor registration.
- The proof does not cover legacy HEAD/duplicate-query/unknown-query cases.

Broad Swift health:

- Still not claimed as green due the unrelated CommandBar title mismatch.

## Swarm Coverage

Lanes run:

- spec compliance: completed, raised descriptor-bound Swift lease blocker
- implementation proof: completed, raised lease proof and legacy proof gaps
- security/trust-boundary: completed, raised legacy unleased route blocker
- contracts/tests: completed, raised Swift lease and hardcoded registry issues
- reliability/performance: completed, raised OPTIONS/HEAD and opaque-id issues

External model lanes:

- none requested

## Routing Follow-Through

Accepted blocker and important implementation findings route back to
`shravan-dev-workflow:implementation-execute-plan`.

phase_result: not_ready
evidence: this report, `f09d768a`, lane outputs, and parent reducer validation
recommended_next_workflow: shravan-dev-workflow:implementation-execute-plan
recommended_transition_reason: Ticket 01 review-fix still has accepted
descriptor/lease authority blockers and route proof gaps before ticket 02 can
begin.
