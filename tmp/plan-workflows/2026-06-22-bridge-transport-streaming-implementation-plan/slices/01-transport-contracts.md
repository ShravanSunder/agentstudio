# 01 Core Transport Contracts Ticket

## Ticket Output

Create the generic Bridge contract layer shared by application protocols:
protocol ids, resource descriptors, descriptor refs, attached descriptor
handoff, stream identities, protocol-scoped resource URLs, content-world-only
privileged RPC, lease validation, integrity, and shared fixtures.

## Source References

- `spec.md` section 6 generic contracts
- `spec.md` section 7 resource URL contract
- `spec.md` section 7.1 capability URL authority
- `spec.md` section 7.2 RPC ingress boundary
- `spec.md` section 12 security and integrity
- `spec.md` section 13 proof expectations
- `plan-review-report.md` B2, I1, I3, I5

## Write Scope

Browser:

- `BridgeWeb/src/core/models/**`
- `BridgeWeb/src/core/resources/**`
- `BridgeWeb/src/core/bridge-host/**`
- shared fixtures under `BridgeWeb/src/test-fixtures/bridge-contract-fixtures/**`

Swift:

- `Sources/AgentStudio/Features/Bridge/Models/Transport/**`
- `Sources/AgentStudio/Features/Bridge/Transport/BridgeSchemeHandler.swift`
- `Sources/AgentStudio/Features/Bridge/Transport/BridgeBootstrap.swift`
- `Sources/AgentStudio/Features/Bridge/Transport/Methods/**` only for generic
  registration boundaries
- focused Bridge tests

Do not add Review or Worktree/File semantics to generic models.

## Red Tests First

- Browser parser accepts canonical protocol-scoped resource URLs.
- Browser parser rejects duplicate keys, unknown keys, traversal, malformed
  percent encoding, invalid generation/revision, bad cursor, wrong protocol,
  and wrong resource kind.
- Swift parser/scheme handler uses the same accept/reject corpus.
- Cross-pane, revoked, wrong protocol, wrong resource kind, wrong generation,
  wrong revision, wrong cursor, and post-reset fetches fail closed.
- Attached descriptor refs are registered before app materializer/policy can
  consume them.
- Page-world `__bridge_command`, `__bridge_ready`, and descriptor-like events
  cannot open streams, fetch resources, or reach Swift privileged methods.
- Content-world privileged RPC path works for allowlisted protocol methods.
- Tampered/truncated whole-body resources reject when integrity is issued.
- Ranged/chunked resources are preview-only and cannot commit authoritative
  state.
- Disabled comments/comms resource kinds and flags are unregistered/rejected.

## Implementation Notes

1. Add common Zod schemas and inferred TS types in `src/core/models/**`.
2. Add Swift transport models or fixture-backed parser/validator types.
3. Update resource URL parsing to protocol-scoped grammar.
4. Add host-side lease validation binding pane, protocol, kind, descriptor,
   identity, generation/revision/cursor, limits, and expiry/revocation.
5. Add content-world RPC integration boundary and retire privileged page-world
   command authority for new protocol commands.
6. Add whole-body integrity verification when an integrity hash exists.
7. Keep legacy Review resource compatibility only until ticket 02 proves the
   replacement.

## Proof Gates

Browser unit/integration:

```bash
pnpm --dir BridgeWeb vitest run \
  src/core/models/bridge-core-models.unit.test.ts \
  src/core/models/bridge-protocol-registry.unit.test.ts \
  src/core/resources/bridge-resource-url.unit.test.ts \
  src/core/resources/bridge-resource-descriptor.unit.test.ts \
  src/core/resources/bridge-resource-registry.unit.test.ts \
  src/core/resources/bridge-integrity.unit.test.ts \
  src/core/bridge-host/bridge-content-world-rpc.integration.test.ts
```

Compatibility tests remain in scope while migration is incomplete:

```bash
pnpm --dir BridgeWeb vitest run \
  src/bridge/bridge-resource-url.unit.test.ts \
  src/foundation/content/content-resource-loader.integration.test.ts
```

Fixture sync:

```bash
bash scripts/bridge-web-sync-fixtures.sh --check
```

Swift focused gate:

```bash
mise run test-fast
```

Use focused Bridge suites first, including `BridgeSchemeHandlerTests`,
`BridgeBootstrapTests`, `BridgeContentWorldIsolationTests`,
`BridgePrivilegedRPCIngressTests`, and `BridgeTransportIntegrationTests` where
applicable. Add `BridgePrivilegedRPCIngressTests.swift` if existing isolation
tests do not prove that page-world `__bridge_command` and `__bridge_ready`
cannot open streams, fetch resources, or reach Swift privileged methods.

Quality:

```bash
pnpm --dir BridgeWeb run check
```

## Handoff Output

- shared fixture corpus path and sync result
- browser parser and Swift parser/scheme proof
- content-world positive and page-world negative proof
- descriptor/lease/integrity proof
- comments/comms fail-closed proof
- changed paths and commit hash if checkpoint committed

## Stop / Replan

Stop if `BridgeSchemeHandler` cannot enforce protocol-scoped descriptor/lease
authority without ambiguous routing or if privileged RPC cannot be moved behind
the trusted Bridge content-world boundary.
