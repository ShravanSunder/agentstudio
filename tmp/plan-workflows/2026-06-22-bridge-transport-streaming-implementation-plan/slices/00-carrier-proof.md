# 00 Intake Carrier Proof Ticket

## Ticket Output

Prove the first concrete intake carrier before migrating any app protocol.

The transport model is already decided:

```text
RPC -> commands, metadata, stream setup
Intake stream -> snapshots, deltas, invalidations, resets, source facts
Resource/content path -> large bodies, file content, patch bodies
```

This ticket proves whether the existing Bridge push/event path can serve as the
first intake-frame carrier in real WKWebView. If it cannot, stop and document
the exact carrier blocker before Review or Worktree/File protocol migration.

## Source References

- `spec.md` section 5 transport pathways
- `spec.md` section 7.3 stream lifecycle
- `spec.md` OD1 continuous stream carrier
- `plan-review-report.md` B1
- `BridgePaneController+PushTransport.swift` notes overlapping WebKit delivery
  loss

## Write Scope

Browser:

- `BridgeWeb/src/core/models/**`
- `BridgeWeb/src/core/intake/**`
- compatibility wrappers in `BridgeWeb/src/core/bridge-host/**` or existing
  `BridgeWeb/src/bridge/**` if the file has not moved yet

Swift:

- `Sources/AgentStudio/Features/Bridge/Runtime/BridgePaneController+PushTransport.swift`
- `Sources/AgentStudio/Features/Bridge/Runtime/BridgePushEnvelopeEncoder.swift`
- focused tests under `Tests/AgentStudioTests/Features/Bridge/**`

Do not migrate Review or Worktree/File payloads in this ticket.

## Red Tests First

- Duplicate, missing, out-of-order, stale, and post-reset frames fail closed.
- Frames after cancel or stale close cannot commit.
- Browser memory/queue caps reject or shed bounded work instead of growing
  unbounded queues.
- Swift encoder emits stream metadata without raw paths, source text, resource
  URLs, or capability handles.
- Swift and TypeScript intake parser fixtures agree for valid frames, duplicate
  frames, gaps, reset, cancel, stale close, malformed identity, and unknown
  protocol/kind cases.
- Real WKWebView proof covers ordered burst delivery, cancel, reset, stale
  close, error propagation, and bounded memory behavior.

## Implementation Notes

1. Add minimal generic intake frame identity and lifecycle schemas.
2. Add receiver state machine for `opening -> active -> gapDetected ->
   resetRequired -> closed/replaced`.
3. Add Swift envelope metadata needed for stream id, sequence, cursor, identity,
   and trace context.
4. Add the first shared intake fixture corpus or extend the existing BridgeWeb
   fixture corpus for parser parity before ticket 01 adds protocol/resource
   descriptor breadth.
5. Keep carrier-specific code small and replaceable until proof passes.
6. Record selected carrier or exact blocker in the ticket handoff.

## Proof Gates

TDD/unit:

```bash
pnpm --dir BridgeWeb vitest run \
  src/core/intake/bridge-intake-receiver.unit.test.ts \
  src/core/intake/bridge-intake-carrier.unit.test.ts
```

Legacy compatibility tests stay in scope while files still live under
`src/bridge/**`:

```bash
pnpm --dir BridgeWeb vitest run \
  src/bridge/bridge-push-envelope.unit.test.ts \
  src/bridge/bridge-push-receiver.unit.test.ts
```

Swift/WebKit:

```bash
mise run test-webkit
```

Use or add focused `BridgeWebKitSpikeTests` / `BridgeTransportIntegrationTests`
cases for burst, cancel, reset, stale-close, and bounded memory. If those files
become too noisy, split the proof into
`Tests/AgentStudioTests/Features/Bridge/BridgeIntakeCarrierWebKitTests.swift`.
Do not replace the WKWebView proof with TS unit tests.

Pressure proof:

- if the selected carrier remains the push/event path, add and run a focused
  pressure case adjacent to
  `Tests/AgentStudioTests/Features/Bridge/Push/PushPerformanceBenchmarkTests.swift`
  or `Tests/AgentStudioTests/Features/Bridge/BridgeIntakeCarrierWebKitTests.swift`;
  it must cover burst ordering and bounded memory/backpressure, not only
  throughput.

Fixture parity:

```bash
bash scripts/bridge-web-sync-fixtures.sh --check
```

Run after adding the shared intake parser fixture corpus. If ticket 00 proves
the carrier without changing shared fixtures, the handoff must state why
fixture sync was not applicable and where parser parity is proven.

Quality:

```bash
pnpm --dir BridgeWeb run check
```

Run only if Browser files changed.

## Handoff Output

- selected carrier or blocker
- accepted/rejected frame cases
- Swift/TypeScript parser parity fixture result or not-applicable reason
- reset/stale-close/cancel evidence
- real WKWebView proof evidence
- changed paths and commit hash if checkpoint committed

## Stop / Replan

Stop if the existing push/event path cannot prove ordered, bounded, stale-safe
delivery in real WKWebView. Do not continue to ticket 01 protocol migration
without a carrier decision or explicit design reconvergence.
