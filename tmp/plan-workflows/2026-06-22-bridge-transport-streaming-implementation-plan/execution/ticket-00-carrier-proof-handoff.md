# Ticket 00 Carrier Proof Handoff

Date: 2026-06-22
Ticket: `slices/00-carrier-proof.md`
Status: implementation proof collected; review blockers fixed; Victoria bridge verifier blocked by stale running debug app marker handoff.

## Selected Carrier

The existing WebKit page-event path remains viable as the first concrete intake carrier for ordered frame delivery and lifecycle-safe page intake.

Evidence:

- Generic browser intake receiver enforces contiguous sequence, duplicate, stale, reset, and closed-frame behavior.
- Generic browser event carrier validates nonce, measures UTF-8 bytes before parse, rejects oversized JSON before receiver mutation, parses Zod-backed intake frames, and delegates lifecycle acceptance to the receiver.
- Swift encoder and TypeScript parser now agree on data frames versus lifecycle frames:
  - `snapshot` / `delta` / `invalidate` carry top-level `payload`.
  - `reset` / `close` carry no `payload`.
  - `error` carries top-level `message`.
- Real WKWebView proof sends eight concurrent `pushJSON` requests through the existing `__bridge_push_json` event path and observes ordered page-side delivery for the test-owned burst token.
- Real WKWebView proof sends Swift-encoded `__bridge_intake_json` frames through bridge-world `applyIntakeFrameJSON` into page world and verifies reset recovery, stale close rejection, post-close rejection, error message propagation, and UTF-8 byte-bound rejection.

## Changed Paths

- `BridgeWeb/src/core/models/bridge-intake-frame.ts`
- `BridgeWeb/src/core/models/bridge-intake-frame.unit.test.ts`
- `BridgeWeb/src/core/intake/bridge-intake-receiver.ts`
- `BridgeWeb/src/core/intake/bridge-intake-receiver.unit.test.ts`
- `BridgeWeb/src/core/intake/bridge-intake-carrier.ts`
- `BridgeWeb/src/core/intake/bridge-intake-carrier.unit.test.ts`
- `Sources/AgentStudio/Features/Bridge/Runtime/BridgePushEnvelopeEncoder.swift`
- `Sources/AgentStudio/Features/Bridge/Transport/BridgeBootstrap.swift`
- `Tests/AgentStudioTests/Features/Bridge/BridgeBootstrapTests.swift`
- `Tests/AgentStudioTests/Features/Bridge/BridgeIntakeCarrierWebKitTests.swift`
- `Tests/AgentStudioTests/Features/Bridge/Runtime/BridgePushEnvelopeEncoderTests.swift`
- `Tests/AgentStudioTests/Features/Bridge/BridgeTransportIntegrationTests.swift`
- `scripts/swift-test-helpers.sh`

## RED / GREEN Evidence

- RED: `pnpm --dir BridgeWeb exec vitest run src/core/intake/bridge-intake-receiver.unit.test.ts`
  - Exit 1: missing `bridge-intake-receiver.js`.
- GREEN: same command after implementation.
  - Exit 0: 1 file, 1 test passed.
- RED: receiver reset recovery.
  - Exit 1: reset frame rejected as `reset_required`.
- GREEN: receiver reset recovery.
  - Exit 0: 1 file, 2 tests passed.
- RED: duplicate vs stale distinction.
  - Exit 1: duplicate returned `stale_sequence`.
- GREEN: duplicate vs stale distinction.
  - Exit 0: 1 file, 3 tests passed.
- RED: close lifecycle.
  - Exit 1: close frame returned active status.
- GREEN: close lifecycle.
  - Exit 0: 1 file, 4 tests passed.
- RED: `pnpm --dir BridgeWeb exec vitest run src/core/models/bridge-intake-frame.unit.test.ts`
  - Exit 1: missing `bridge-intake-frame.js`.
- GREEN: model and receiver tests.
  - Exit 0: 2 files, 6 tests passed.
- RED: `pnpm --dir BridgeWeb exec vitest run src/core/intake/bridge-intake-carrier.unit.test.ts`
  - Exit 1: missing `bridge-intake-carrier.js`.
- GREEN: carrier, receiver, model tests.
  - Exit 0: 3 files, 8 tests passed.
- RED: `swift test --filter BridgePushEnvelopeEncoderTests`
  - Exit 1: missing `BridgeIntakeFrameMetadata` and `encodeIntakeFrame`.
- GREEN: same command after encoder implementation.
  - Exit 0: 4 tests passed.
- RED: encoder lifecycle parity.
  - Exit 1: `BridgeIntakeFrameMetadata` had no `message` argument for `.error` frames.
- GREEN: encoder lifecycle parity.
  - Exit 0: 6 tests passed.
- RED: carrier UTF-8 byte bound.
  - Exit 1: Unicode frame accepted because the carrier used JavaScript string length instead of encoded bytes.
- GREEN: carrier UTF-8 byte bound.
  - Exit 0: model plus carrier tests passed, 2 files and 5 tests.
- RED: bootstrap intake JSON dispatch.
  - Exit 1: generated bootstrap had no `applyIntakeFrameJSON` or `__bridge_intake_json` dispatch path.
- GREEN: bootstrap intake JSON dispatch.
  - Exit 0: focused bootstrap test passed.
- RED: first WebKit lifecycle proof shape.
  - Exit 1: three separate WebKit tests passed individually but the class crashed with signal 5 on the second page.
- GREEN: consolidated WebKit carrier proof.
  - Exit 0: one page/session test covers lifecycle, error propagation, and UTF-8 byte bound.
- RED: `swift test --filter WebKitSerializedTests/BridgeTransportIntegrationTests/test_pushJSON_concurrentBurstDeliversOrderedPageEvents`
  - Exit 1: first version observed unrelated app push events in the page probe.
- GREEN: same command after burst-token filtering.
  - Exit 0: 1 WebKit test passed.
- RED: full `test-webkit` rerun exposed stale setup in existing `test_pushPackageMetadata_rendersReviewViewerShell`.
  - Exit 1: page diagnostics reported `fetch_error` because symbolic fixture handles had no registered bodies.
- GREEN: same existing test after replacing symbolic fixture with hash-valid registered content package.
  - Exit 0: 1 WebKit test passed.

## Final Proof Commands

- `pnpm --dir BridgeWeb exec vitest run src/core/models/bridge-intake-frame.unit.test.ts src/core/intake/bridge-intake-receiver.unit.test.ts src/core/intake/bridge-intake-carrier.unit.test.ts`
  - Exit 0: 3 files, 9 tests passed.
- `pnpm --dir BridgeWeb exec vitest run src/bridge/bridge-push-envelope.unit.test.ts src/bridge/bridge-push-receiver.unit.test.ts`
  - Exit 0: 2 files, 10 tests passed.
- `bash scripts/bridge-web-sync-fixtures.sh --check`
  - Exit 0: BridgeWeb fixtures in sync, 16 files.
- `pnpm --dir BridgeWeb run check`
  - Exit 0: oxlint, architecture check, oxfmt, and TypeScript passed.
- `swift test --filter BridgePushEnvelopeEncoderTests`
  - Exit 0: 6 tests passed.
- `swift test --filter BridgeBootstrapTests/test_applyIntakeFrameJSON_dispatches_string_payload_with_push_nonce`
  - Exit 0: 1 test passed.
- `swift test --filter WebKitSerializedTests/BridgeTransportIntegrationTests/test_pushJSON_concurrentBurstDeliversOrderedPageEvents`
  - Exit 0: 1 test passed.
- `swift test --filter WebKitSerializedTests/BridgeIntakeCarrierWebKitTests`
  - Exit 0: 1 test passed.
- `rg -n "Task\\.sleep|setTimeout|setInterval|sleep" BridgeWeb/src/core Tests/AgentStudioTests/Features/Bridge/BridgeIntakeCarrierWebKitTests.swift Tests/AgentStudioTests/Features/Bridge/BridgeTransportIntegrationTests.swift Tests/AgentStudioTests/Features/Bridge/Runtime/BridgePushEnvelopeEncoderTests.swift Sources/AgentStudio/Features/Bridge/Runtime/BridgePushEnvelopeEncoder.swift Sources/AgentStudio/Features/Bridge/Transport/BridgeBootstrap.swift`
  - Exit 1: no matches in changed carrier/test surfaces.
- `SWIFT_TEST_PREBUILD_TIMEOUT_SECONDS=180 mise run test-webkit`
  - Exit 0: WebKit serialized gate passed in 96.65s with the new `BridgeIntakeCarrierWebKitTests` filter included.
  - Note: plain `mise run test-webkit` first failed during cold prebuild at 60s, before test execution. Reruns used the same task with a larger prebuild timeout.
- `mise run lint`
  - Exit 0: swift-format, SwiftLint, architecture lint, and release script checks passed.

## Victoria / Observability

- `mise run observability:up`
  - Exit 0: VictoriaMetrics, VictoriaLogs, VictoriaTraces, and OTel collector were already running and healthy.
- `AGENTSTUDIO_STARTUP_DIAGNOSTIC_ACTION=bridge-review-observability-smoke mise run run-debug-observability -- --detach`
  - Exit 1: debug app already running for this worktree, PID 97068.
- `mise run verify-bridge-observability`
  - Exit 1: missing AgentStudio debug observability marker.

Blocker:

The existing debug app has the correct `AGENTSTUDIO_STARTUP_DIAGNOSTIC_ACTION=bridge-review-observability-smoke` process environment, but the launcher refusal overwrote `tmp/debug-observability/latest-observability.env` with `AGENTSTUDIO_OBSERVABILITY_STATUS=already_running` and no `AGENTSTUDIO_OBSERVABILITY_MARKER`. No marker was recoverable from `ps` or the debug data root. A fresh Bridge Victoria proof requires quitting PID 97068 and relaunching the debug observability diagnostic.

## Residual Risks

- Ticket 00 proves ordered burst delivery and lifecycle-safe intake in real WKWebView, but does not yet add Victoria lifecycle-specific metrics for reset/cancel/stale-close/bounded memory. Existing Victoria verifier proves broader Bridge package-push telemetry once the marker handoff is fresh.
- The generic TS event carrier is not wired to the legacy Review app path yet. That is intentional; ticket 00 proves the carrier and lifecycle primitives before ticket 01/02 protocol migration.
- Cancel semantics remain represented by receiver `close()` and close frames in the browser primitive. Host-level cancel/reset RPC wiring belongs to ticket 01.
