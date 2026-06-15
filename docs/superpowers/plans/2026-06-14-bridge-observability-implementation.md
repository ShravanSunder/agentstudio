# Bridge Observability Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add debug-only, scope-gated Bridge observability with correlated logs, metrics, and real OTLP traces across Swift push, BridgeWeb RPC, and `agentstudio://resource/content` fetch flows, then use the shared Victoria stack to find and improve Bridge performance hotspots before the Pierre/Shiki/Trees milestone.

**Architecture:** Keep AgentStudio as a producer into the shared `~/dev/ai-tools/observability` stack. Swift owns OTLP export, projection, privacy, and trace backend lifecycle; BridgeWeb owns local timing and bounded summaries only. Bridge feature code records domain-safe events through a Bridge telemetry runtime that routes into `Infrastructure/Diagnostics` without adding atoms, persistence, direct browser OTLP, or source mutation.

**Tech Stack:** Swift 6.2, Swift Testing, Swift OTel, Swift Distributed Tracing, Swift Metrics, ServiceLifecycle, WebKit, Vite, React 19, TypeScript 5.7, Zod, Vitest, oxlint, oxfmt, VictoriaMetrics, VictoriaLogs, VictoriaTraces.

---

## Execution Status: 2026-06-14

This plan is active on the LUNA-337 Bridge branch. The current implementation
has landed the debug-only Swift diagnostics plumbing, Bridge telemetry models
and runtime, BridgeWeb summary recorder, Bridge smoke startup diagnostic, and
the `scripts/verify-bridge-observability.sh` verifier. The remaining completion
work is current validation, Victoria-backed proof, performance-cycle evidence,
and implementation review.

Current proof ledger:
`docs/wip/bridge-observability/2026-06-14-bridge-observability-proof.md`.

Fresh Victoria marker: `bridge-observability-1781487476`.

The first Victoria cycle proved all three Bridge communication lanes and found a
real export reliability gap: BridgeWeb RPC send and content fetch events were
recorded locally but not flushed consistently at boundary crossings. That issue
is fixed by forcing BridgeWeb telemetry flushes after non-telemetry RPC send
records and content fetch records. The same cycle identified telemetry batch
noise under repeated package pushes. That is fixed by using the existing
`minimumFlushIntervalMilliseconds` telemetry config for non-forced flushes; the
fresh proof marker shows `performance.bridge.webkit.telemetry_batch` reduced
from 14 to 9 while `rpc_send` and `content_fetch` remained present. Review
swarm follow-up also tightened browser telemetry to `.web`-only ingress,
release-style telemetry disablement, oversized-batch drop accounting, failed
flush retry behavior, review-push trace parent selection, and controlled
`agentstudio.bridge.rpc.method_class` attribution for RPC traces. Remaining
push timing work should be handled in a separate measured performance slice
after adding a low-cardinality push-slice discriminator; the current
`performance.bridge.webkit.package_push` event aggregates WebKit push
transport, not only review package payloads.

Current implementation choices that supersede earlier open wording in this
plan:

- The fixed proof scenario is
  `package_apply_content_fetch_v1`.
- The startup diagnostic action is
  `bridge-review-observability-smoke`.
- The deterministic smoke provider is DEBUG-only and in-memory.
- The Bridge verifier is `mise run verify-bridge-observability`.
- Logs and traces are scoped by both current `agentstudio.trace.name` marker and
  `agentstudio.bridge.test.scenario`; metrics stay marker/event scoped to avoid
  widening metric label cardinality.
- BridgeWeb receives only browser-owned telemetry scopes. Browser-originated
  batches may emit `.web` samples; Swift and WebKit samples are native-only.
- Generic RPC telemetry uses `agentstudio.bridge.rpc.method_class` with
  controlled values `review`, `telemetry`, and `other`. The verifier requires a
  review RPC trace and rejects telemetry self-RPC logs or spans.
- Content fetch defaults to summary correlation. The direct `traceparent`
  custom-header proof is guarded by
  `AGENT_STUDIO_WEBKIT_TRACEPARENT_FETCH_PROOF=on` because the headless WebKit
  custom-scheme header lane can crash outside this slice.

## Source Coverage

- `docs/superpowers/specs/2026-06-14-bridge-debug-telemetry-observability.md` is the canonical Bridge telemetry spec, 799 lines, read in full.
- `docs/superpowers/specs/2026-06-11-agentstudio-otlp-shared-observability-design.md` is the generic AgentStudio producer/OTLP spec, 697 lines, read in full.
- `docs/superpowers/specs/2026-06-10-bridge-review-foundation.md` is the pre-Pierre Bridge review foundation spec, 329 lines, read in full.
- `docs/architecture/swift_react_bridge_design.md` is 2914 lines. The plan is grounded in the current-state table, three-stream architecture, MainActor boundary, content lifecycle, SLO budget, LUNA-337 checkpoint, transport phases, invariants, and folder map sections.
- `docs/architecture/directory_structure.md` is 440 lines. The plan uses the hybrid feature/infrastructure ownership rule and the explicit `New bridge protocol method or push slice -> Features/Bridge/` placement.
- `AGENTS.md` is 694 lines and establishes the shared observability producer boundary, debug launch proof path, no wall-clock test rule, Bridge folder arcs, and proof-gate expectations.
- Current source inspected: `Sources/AgentStudio/Infrastructure/Diagnostics/*`, `Sources/AgentStudio/Features/Bridge/{Models,Runtime,State,Transport}/*`, `BridgeWeb/src/{app,bridge,foundation,review-viewer}/*`, `Tests/AgentStudioTests/{Infrastructure/Diagnostics,Features/Bridge}/*`, `BridgeWeb/package.json`, `.mise.toml`, and the shared stack README plus status/smoke commands.

## Current-State Findings

The implementation is not starting from a blank telemetry surface.

- `AgentStudioTraceRuntime.record(...)` already carries optional `traceID`, `spanID`, and `parentSpanID` through `AgentStudioTraceRecord`.
- `AgentStudioOTLPTraceProjection` currently strips trace/span IDs and allowlists only existing non-Bridge attributes.
- `AgentStudioOTLPBootstrapper` currently creates logging and metrics backends, sets `configuration.traces.enabled = false`, and does not include a tracing backend service.
- Swift OTel exposes `OTel.makeTracingBackend(configuration:)`; the returned tracer and service can be composed with the existing bootstrapper service group.
- Swift Distributed Tracing exposes `LegacyTracer.startAnySpan(...)`, `Span.end(at:)`, `Instrument.inject(...)`, and `Instrument.extract(...)`; a small carrier wrapper can propagate W3C `traceparent` without making Bridge depend on OTel internals.
- Bridge currently has three relevant communication surfaces:
  - `BridgePaneController.pushJSON(...)` for Swift-to-BridgeWeb push envelopes.
  - `RPCRouter.dispatch(json:isBridgeReady:)` for BridgeWeb-to-Swift typed JSON-RPC.
  - `BridgeSchemeHandler.reply(for:)` for app assets and `agentstudio://resource/content/{handleId}?generation=...` content fetches.
- `BridgeBootstrap.applyEnvelope(...)` is part of the push transport. It currently lifts only store/op/payload/revision/epoch into the page-world event, so push trace metadata will be lost unless `BridgeBootstrap.swift` is included in the cutover.
- `BridgeContentStore` owns content cache-hit, cold-load, in-flight, stale-generation, binary, oversize, and hash-mismatch decisions. Content telemetry must observe store-owned outcomes instead of inferring them in `BridgeSchemeHandler`.
- The normal typed RPC method path decodes params before invoking handlers. Bridge telemetry batches are the largest debug-only command payload in this design, so `system.bridgeTelemetry` must have a raw bounded handoff path and decode inside `BridgeTelemetryIngestor`.
- BridgeWeb currently has domain-shaped foundations and valid test naming:
  - `BridgeWeb/src/bridge/bridge-push-envelope.ts`
  - `BridgeWeb/src/bridge/bridge-rpc-client.ts`
  - `BridgeWeb/src/foundation/content/content-resource-loader.ts`
  - `*.unit.test.ts`, `*.integration.test.tsx`, and related variants.

## Non-Goals

- Do not add Bridge persistence, a Bridge atom, or SQLite work.
- Do not move or own the shared Victoria stack in this repo.
- Do not add direct browser OTLP to packaged `agentstudio://app/*` assets.
- Do not export prompts, source text, raw paths, raw errors, tool output, model output, handle IDs, item IDs, pane IDs, command IDs, or raw correlation IDs over OTLP.
- Do not add Pierre/Shiki/Trees placeholder telemetry before the real viewer milestone.
- Do not optimize without before/after measurements from the observability loop.
- Do not replace existing Bridge review/package/query contracts.

## File Ownership Map

### Infrastructure Diagnostics

- Modify: `Sources/AgentStudio/Infrastructure/Diagnostics/AgentStudioTraceTag.swift`
  - Add Bridge tag enum cases: `bridge.performance.swift`, `bridge.performance.web`, `bridge.performance.webkit`.
- Modify: `Sources/AgentStudio/Infrastructure/Diagnostics/AgentStudioOTLPTraceProjection.swift`
  - Preserve valid trace/span fields.
  - Add Bridge attribute allowlist.
  - Keep IDs out of ordinary attributes and metric labels.
- Modify: `Sources/AgentStudio/Infrastructure/Diagnostics/AgentStudioOTLPPerformanceMetrics.swift`
  - Continue requiring `performance.*` event names.
  - Promote numeric `agentstudio.bridge.*` samples only through an explicit safe label allowlist.
- Modify: `Sources/AgentStudio/Infrastructure/Diagnostics/AgentStudioOTLPBootstrapper.swift`
  - Add tracing backend service when OTLP is enabled.
  - Store a tracing helper behind diagnostics ownership, not Bridge ownership.
- Create: `Sources/AgentStudio/Infrastructure/Diagnostics/AgentStudioOTLPTracingBackend.swift`
  - Wrap the Swift OTel tracer and traceparent carrier helpers.
  - Expose a small `AgentStudioTraceSpanRecording` protocol for feature code.
- Create: `Sources/AgentStudio/Infrastructure/Diagnostics/AgentStudioTraceparentCarrier.swift`
  - Small `Dictionary` carrier implementing `Injector` and `Extractor`.

### Bridge Swift Models

- Create: `Sources/AgentStudio/Features/Bridge/Models/Telemetry/BridgeTraceContext.swift`
  - Codable, Sendable DTO for `traceId`, `spanId`, `parentSpanId`, and `sampled`.
  - Helpers for W3C `traceparent` serialization and validation.
- Create: `Sources/AgentStudio/Features/Bridge/Models/Telemetry/BridgeTelemetryBatch.swift`
- Create: `Sources/AgentStudio/Features/Bridge/Models/Telemetry/BridgeTelemetrySample.swift`
- Create: `Sources/AgentStudio/Features/Bridge/Models/Telemetry/BridgeTelemetryScope.swift`
- Create: `Sources/AgentStudio/Features/Bridge/Models/Telemetry/BridgeTelemetryDropReason.swift`
- Create: `Sources/AgentStudio/Features/Bridge/Models/Telemetry/BridgeTelemetrySinkState.swift`
- Create: `Sources/AgentStudio/Features/Bridge/Models/Telemetry/BridgeTelemetryBootstrapConfig.swift`
  - Codable, Sendable handshake DTO for scopes, limits, flush cadence, RPC method name, and proof scenario.

### Bridge Swift Runtime

- Create: `Sources/AgentStudio/Features/Bridge/Runtime/Telemetry/BridgePerformanceTraceRecorder.swift`
  - Cheap disabled guard first.
  - Records Swift/WebKit events and creates spans through diagnostics protocol.
- Create: `Sources/AgentStudio/Features/Bridge/Runtime/Telemetry/BridgeTelemetryIngestor.swift`
  - Actor for off-main validation, bucketing, drop accounting, and forwarding.
- Create: `Sources/AgentStudio/Features/Bridge/Runtime/Telemetry/BridgeTelemetryBatchValidator.swift`
- Create: `Sources/AgentStudio/Features/Bridge/Runtime/Telemetry/BridgeTelemetryScopeGate.swift`
- Create: `Sources/AgentStudio/Features/Bridge/Runtime/Telemetry/BridgeTelemetryAggregator.swift`
- Create: `Sources/AgentStudio/Features/Bridge/Runtime/Telemetry/BridgeTelemetryQueue.swift`
  - Per-pane bounded queue for raw telemetry batches before actor decode.
- Modify: `Sources/AgentStudio/Features/Bridge/Runtime/BridgePaneController.swift`
  - Inject recorder/ingestor.
  - Add push trace metadata only when enabled.
  - Route raw telemetry batches without owning decode, validation, or aggregation.
- Modify: `Sources/AgentStudio/Features/Bridge/Runtime/ReviewFoundation/BridgeContentStore.swift`
  - Return instrumentation-neutral content-load observations owned by the store.
  - Do not import diagnostics or OTLP types.
- Modify: `Sources/AgentStudio/Features/Bridge/Transport/RPCRouter.swift`
  - Decode optional `__traceContext` transport metadata.
  - Pass trace context to callbacks without placing it in method params.
  - Apply a raw byte/character cap before deep parsing `system.bridgeTelemetry`.
- Modify: `Sources/AgentStudio/Features/Bridge/Transport/RPCMessageHandler.swift`
  - Keep message validation only; no telemetry aggregation.
- Modify: `Sources/AgentStudio/Features/Bridge/Transport/BridgeSchemeHandler.swift`
  - Extract `traceparent` when WebKit provides it.
  - Route store-owned content-load observations into the recorder and header-support proof signal.
- Modify: `Sources/AgentStudio/Features/Bridge/Transport/BridgeBootstrap.swift`
  - Preserve `__traceContext` through `applyEnvelope(...)` into `__bridge_push`.
  - Carry replayable telemetry bootstrap config in `__bridge_handshake`.
- Modify: `Sources/AgentStudio/Features/Bridge/Transport/Methods/SystemMethods.swift`
  - Add exact debug-only method name `system.bridgeTelemetry`.
  - Register it only when Bridge telemetry is active in a DEBUG runtime.
  - This method is a raw bounded sink, not a normal typed `Params` method.
- Modify app composition files that construct `BridgePaneController`
  - Pass the diagnostics-backed recorder from the existing app composition path.
  - Do not introduce a singleton hidden in Bridge code.
- Modify: `Sources/AgentStudio/App/Boot/AgentStudioStartupDiagnosticAction.swift`
  - Add DEBUG-only diagnostic action `bridge-review-observability-smoke`.
- Modify: `Sources/AgentStudio/App/Boot/AppDelegate+StartupDiagnostics.swift`
  - Use the existing startup diagnostic lane to open the Bridge review pane and run the fixed observability scenario.
  - Do not add persistence, SQLite, or stable/beta behavior.

### BridgeWeb

- Create: `BridgeWeb/src/foundation/telemetry/bridge-trace-context.ts`
- Create: `BridgeWeb/src/foundation/telemetry/bridge-telemetry-event.ts`
- Create: `BridgeWeb/src/foundation/telemetry/bridge-telemetry-scope.ts`
- Create: `BridgeWeb/src/foundation/telemetry/bridge-telemetry-buffer.ts`
- Create: `BridgeWeb/src/foundation/telemetry/bridge-telemetry-recorder.ts`
- Create: `BridgeWeb/src/foundation/telemetry/bridge-telemetry-sink.ts`
- Create: `BridgeWeb/src/foundation/telemetry/bridge-telemetry-bootstrap-config.ts`
- Create: `BridgeWeb/src/bridge/bridge-telemetry-event-sink.ts`
- Create: `BridgeWeb/src/app/bridge-telemetry-composition.ts`
- Modify: `BridgeWeb/src/bridge/bridge-page-handshake.ts`
  - Decode replayed telemetry config from `__bridge_handshake`.
- Modify: `BridgeWeb/src/bridge/bridge-push-envelope.ts`
  - Decode optional `__traceContext`.
- Modify: `BridgeWeb/src/bridge/bridge-rpc-client.ts`
  - Attach optional `__traceContext` transport metadata.
- Modify: `BridgeWeb/src/foundation/content/content-resource-loader.ts`
  - Add optional `traceparent` request header when available.
- Modify: `BridgeWeb/src/app/bridge-app.tsx`
  - Compose null or active recorder from debug config.
- Modify: `BridgeWeb/src/review-viewer/shell/review-viewer-shell.tsx`
  - Record content fetch and first-render summaries only through injected recorder.

### Tests And Verifiers

- Create or modify Swift tests in:
  - `Tests/AgentStudioTests/Infrastructure/Diagnostics/`
  - `Tests/AgentStudioTests/Features/Bridge/`
- Create or modify BridgeWeb tests next to implementation files with names:
  - `*.unit.test.ts`
  - `*.unit.test.tsx`
  - `*.integration.test.ts`
  - `*.integration.test.tsx`
- Create: `Tests/BridgeContractFixtures/valid/rpc-command-bridge-telemetry.json`
- Create: `Tests/BridgeContractFixtures/valid/bridge-telemetry-bootstrap-config.json`
- Create: `Tests/BridgeContractFixtures/invalid/rpc-command-bridge-telemetry-oversized.json`
- Mirror fixtures through `scripts/bridge-web-sync-fixtures.sh` into `BridgeWeb/src/test-fixtures/bridge-contract-fixtures/`.
- Create: `scripts/verify-bridge-observability.sh`
  - Uses the existing debug observability state file and Victoria queries.
  - Does not start or own the shared stack.
- Create: `docs/wip/bridge-observability/2026-06-14-bridge-observability-proof.md`
  - Current proof ledger for stack state, fresh marker, privacy canaries, traces, and performance cycles.

## Hard Contract Decisions

These decisions close the open spec questions before implementation begins.

- Telemetry RPC method: `system.bridgeTelemetry`.
- RPC shape: JSON-RPC 2.0 command with transport metadata outside params:

```json
{
  "jsonrpc": "2.0",
  "method": "system.bridgeTelemetry",
  "params": {
    "schemaVersion": 1,
    "scenario": "package_apply_content_fetch_v1",
    "samples": []
  },
  "__commandId": "cmd_telemetry_sample",
  "__traceContext": {
    "traceId": "11111111111111111111111111111111",
    "spanId": "2222222222222222",
    "parentSpanId": null,
    "sampled": true
  }
}
```

- Registration rule: `system.bridgeTelemetry` is not registered unless this is a DEBUG runtime and Bridge telemetry is explicitly active. Release-style tests must see method-not-found.
- Decode rule: `system.bridgeTelemetry` bypasses the ordinary typed `RPCMethod.Params` decode path. `RPCRouter` performs method-name detection, a raw-size cap, and a raw `Data` handoff to `BridgeTelemetryIngestor`; the actor validates and decodes.
- Self-observation rule: `system.bridgeTelemetry` is excluded from generic RPC send/dispatch/response telemetry and from trace-context attachment by the generic RPC client. It emits only bounded `performance.bridge.webkit.telemetry_batch` and drop/accounting events.
- Activation/config carrier: the existing replayable `__bridge_handshake` detail carries optional `telemetryConfig`. BridgeWeb creates an active recorder only when that config is present and enabled. Absence means null recorder.
- Push propagation rule: `__traceContext` is added when any active Bridge telemetry scope needs cross-boundary correlation, not only when `bridge.performance.webkit` is enabled.
- Content propagation rule: prefer W3C `traceparent` request headers. If WebKit strips custom headers, the proof is summary-correlated only; trace IDs do not move into URLs.
- Initial proof scenario: `package_apply_content_fetch_v1`, driven by DEBUG startup diagnostic action `bridge-review-observability-smoke`.
- Scenario fixture: a deterministic in-memory Bridge review package with content handles and content bytes owned by the Bridge review foundation. It must not read user repositories, Git state, SQLite, or raw source paths.

## Required Event Inventory

The verifier must assert each required family for the fixed scenario. Wildcard "some Bridge event exists" checks are not sufficient.

| Event | Owner | Parent/Correlation | Required proof |
|---|---|---|---|
| `performance.bridge.swift.package_build` | `BridgeReviewPipeline` / recorder caller | root or push parent | Swift unit plus VictoriaLogs |
| `performance.bridge.swift.delta_build` | review refresh path | package trace when delta emitted | Swift unit or explicit not-emitted note for first scenario |
| `performance.bridge.swift.content_register` | `BridgeContentStore` activation/register | package trace | Swift unit |
| `performance.bridge.swift.content_load` | `BridgeContentStore` observation routed by `BridgeSchemeHandler` | content fetch parent when header supported, summary otherwise | Swift unit plus WebKit proof |
| `performance.bridge.swift.telemetry_ingest` | `BridgeTelemetryIngestor` | telemetry batch trace, no self-RPC recursion | Swift unit |
| `performance.bridge.webkit.package_push` | `BridgePaneController.pushJSON` | package build parent | Swift/WebKit test plus VictoriaTraces |
| `performance.bridge.webkit.rpc_dispatch` | generic RPC router, excluding `system.bridgeTelemetry` | RPC client parent plus `rpc.method_class=review` for review commands | `RPCRouterTests` plus VictoriaLogs/VictoriaTraces |
| `performance.bridge.webkit.rpc_response` | generic RPC router, excluding `system.bridgeTelemetry` | dispatch child plus controlled `rpc.method_class` | `RPCRouterTests` plus VictoriaLogs |
| `performance.bridge.webkit.telemetry_batch` | raw telemetry sink path | none or telemetry trace | Swift unit plus verifier |
| `performance.bridge.web.package_apply` | BridgeWeb app/review package apply | push trace context | Vitest plus VictoriaLogs |
| `performance.bridge.web.rpc_send` | BridgeWeb RPC client, excluding `system.bridgeTelemetry` | RPC interaction trace | Vitest plus VictoriaLogs |
| `performance.bridge.web.content_fetch` | content resource loader | fetch trace context | Vitest plus verifier |
| `performance.bridge.web.first_render` | review viewer shell | package/apply trace | Vitest plus verifier |
| `performance.bridge.web.telemetry_drop` | BridgeWeb buffer/sink | summarized cold-lane event | Vitest plus verifier |

`performance.bridge.web.rpc_ack` is intentionally not required in this plan.
BridgeWeb does not yet own a response-consumer lane for `__bridge_response` or
agent command-ack pushes; that belongs to a later bidirectional-response
milestone if the Bridge viewer starts reacting to command results directly.

## Requirements/Proof Matrix

| Requirement | Owning task | Proof owner: | Proof gate | Layer | stale-proof guard: | Red/green |
|---|---|---|---|---|---|---|
| Bridge spec covers logs, metrics, traces, and push/RPC/content fetch correlation. | Task 0 | parent | targeted `rg` checks over spec and plan plus whitespace check | docs/spec | Plan references exact spec path and line count. | no |
| AgentStudio exports real traces, not only logs/metrics. | Task 1 | executor | Diagnostics tests plus VictoriaTraces query from fresh marker | unit, integration, observability | Query must use current `AGENTSTUDIO_TRACE_NAME`; stale logs fail. | yes |
| Bridge telemetry is debug-only and scope-gated. | Task 1, Task 3, Task 4, Task 5 | executor | Tag parsing tests, disabled-path tests, BridgeWeb null-recorder tests, release-style method-not-found test | unit | `AGENTSTUDIO_TRACE_TAGS=off` and absent-handshake-config cases must be covered. | yes |
| Swift-to-BridgeWeb push has trace context and safe metrics. | Task 3, Task 7 | executor | Swift push tests, `BridgeBootstrapTests`, BridgeWeb envelope tests, Victoria trace query | unit, integration, observability | Push proof must include a package event emitted in the fresh run. | yes |
| BridgeWeb-to-Swift RPC has typed trace metadata outside method params. | Task 3, Task 4, Task 7 | executor | `RPCRouterTests`, `bridge-rpc-client.unit.test.ts`, Victoria trace query | unit, integration, observability | RPC proof must include a command from the mounted debug app. | yes |
| Content fetch is correlated by `traceparent` when WebKit supports custom headers. | Task 3, Task 4, Task 7 | executor | `BridgeTransportIntegrationTests` WebKit assertion and verifier output | integration, observability | If headers are stripped, proof must explicitly mark summary-correlated fallback. | yes |
| OTLP output is source-scrubbed and low-cardinality. | Task 1, Task 2, Task 7 | executor | Projection tests and negative Victoria canary queries | unit, observability | Negative query must use fresh unsafe sentinel. | yes |
| Bridge telemetry processing stays off MainActor except WebKit/UI routing. | Task 2, Task 3 | executor | raw-size guard tests, actor tests, and source review of `BridgeTelemetryIngestor` use | unit, review | No MainActor batch decode/aggregation in controller or typed RPC handler. | yes |
| BridgeWeb does not ship direct browser OTLP. | Task 4, Task 9 | executor | dependency/source/bundle scan and BridgeWeb tests | unit, static | Scan package dependencies and bundled source for OTLP exporter imports. | no |
| Performance improvements are data-driven and scoped. | Task 8 | parent plus executor | baseline/after VictoriaMetrics queries and proof doc | performance | Same scenario, same trace-tag configuration, current branch SHA recorded; stop if hotspot is outside Bridge telemetry/transport overhead. | no |
| No unrelated persistence, SQLite, Git backend, or Pierre implementation drift. | All tasks | parent plus review | `git diff --name-only`, lint boundary checks, review swarm | review, lint | Diff scan must show no SQLite/Git/Pierre files unless explicitly re-scoped. | no |

## Task 0: Spec And Plan Baseline

**Files:**
- Modify: `docs/superpowers/specs/2026-06-14-bridge-debug-telemetry-observability.md`
- Create: `docs/superpowers/plans/2026-06-14-bridge-observability-implementation.md`

- [ ] **Step 1: Confirm the Bridge telemetry spec covers all three mechanisms**

Run:

```bash
rg -n "Swift -> BridgeWeb|BridgeWeb -> Swift|resource/content|Trace Correlation Model|traceparent|Victoria|system.bridgeTelemetry|package_apply_content_fetch_v1|bridge-review-observability-smoke" docs/superpowers/specs/2026-06-14-bridge-debug-telemetry-observability.md
rg -n "Required Event Inventory|performance.bridge.web.first_render|performance.bridge.webkit.telemetry_batch|BridgeBootstrap|BridgeContentStore" docs/superpowers/plans/2026-06-14-bridge-observability-implementation.md
```

Expected: hits in the trace correlation, content fetch, proof, event inventory, and ownership sections.

- [ ] **Step 2: Check plan/spec whitespace**

Run:

```bash
tmp_spec_check=$(mktemp)
git diff --no-index --check -- /dev/null docs/superpowers/specs/2026-06-14-bridge-debug-telemetry-observability.md >"$tmp_spec_check" || true
test ! -s "$tmp_spec_check"
tmp_plan_check=$(mktemp)
git diff --no-index --check -- /dev/null docs/superpowers/plans/2026-06-14-bridge-observability-implementation.md >"$tmp_plan_check" || true
test ! -s "$tmp_plan_check"
```

Expected: both `test ! -s ...` commands exit 0. `git diff --no-index` may return non-zero simply because the new file differs from `/dev/null`; the checked signal is no whitespace-error output.

- [ ] **Step 3: Commit planning artifacts after review**

Run after plan review is accepted:

```bash
git add docs/superpowers/specs/2026-06-14-bridge-debug-telemetry-observability.md docs/superpowers/plans/2026-06-14-bridge-observability-implementation.md
git commit -m "docs: plan bridge observability"
```

Expected: one docs-only commit.

## Task 1: Diagnostics OTLP Trace Substrate

**Files:**
- Modify: `Sources/AgentStudio/Infrastructure/Diagnostics/AgentStudioTraceTag.swift`
  - Add explicit-selection metadata needed by Bridge scope gating.
- Modify: `Sources/AgentStudio/Infrastructure/Diagnostics/AgentStudioOTLPTraceProjection.swift`
- Modify: `Sources/AgentStudio/Infrastructure/Diagnostics/AgentStudioOTLPPerformanceMetrics.swift`
- Modify: `Sources/AgentStudio/Infrastructure/Diagnostics/AgentStudioOTLPBootstrapper.swift`
- Create: `Sources/AgentStudio/Infrastructure/Diagnostics/AgentStudioOTLPTracingBackend.swift`
- Create: `Sources/AgentStudio/Infrastructure/Diagnostics/AgentStudioTraceparentCarrier.swift`
- Test: `Tests/AgentStudioTests/Infrastructure/Diagnostics/AgentStudioTraceConfigurationTests.swift`
- Test: `Tests/AgentStudioTests/Infrastructure/Diagnostics/AgentStudioOTLPTraceProjectionTests.swift`
- Test: `Tests/AgentStudioTests/Infrastructure/Diagnostics/AgentStudioOTLPPerformanceMetricsTests.swift`
- Test: `Tests/AgentStudioTests/Infrastructure/Diagnostics/AgentStudioOTLPBootstrapSmokeTests.swift`

- [ ] **Step 1: Write failing tag selection tests**

Add tests proving these selectors work:

```swift
@Test func bridgePerformancePrefixSelectorEnablesBridgePerformanceTags() {
    let selection = AgentStudioTraceTag.parseSelection("bridge.performance.*")

    #expect(selection.unknownSelectors.isEmpty)
    #expect(selection.tags.contains(.bridgePerformanceSwift))
    #expect(selection.tags.contains(.bridgePerformanceWeb))
    #expect(selection.tags.contains(.bridgePerformanceWebKit))
}
```

Add tests proving missing `AGENTSTUDIO_TRACE_TAGS` keeps Bridge performance out of the safe debug baseline, while explicit `bridge.performance.*` and explicit `*` can enable Bridge telemetry for proof runs.

Run:

```bash
mise run test -- --filter AgentStudioTraceConfigurationTests
```

Expected before implementation: compile failure for missing enum cases.

- [ ] **Step 2: Add Bridge trace tags**

Add enum cases with these raw values:

```swift
case bridgePerformanceSwift = "bridge.performance.swift"
case bridgePerformanceWeb = "bridge.performance.web"
case bridgePerformanceWebKit = "bridge.performance.webkit"
```

Run the same filtered test. Expected: pass.

Do not add Bridge performance tags to `AgentStudioTraceConfiguration.safeDefaultTags`.

- [ ] **Step 3: Write failing OTLP projection tests**

Add tests proving:

- valid 32-hex trace IDs and 16-hex span IDs are preserved as record fields
- invalid trace/span IDs are dropped
- Bridge allowlisted attributes survive
- disallowed IDs remain dropped from attributes

Example assertion shape:

```swift
#expect(projected.traceID == "11111111111111111111111111111111")
#expect(projected.spanID == "2222222222222222")
#expect(projected.attributes["agentstudio.bridge.phase"] == .string("package_build"))
#expect(projected.attributes["agentstudio.bridge.item_id"] == nil)
```

Run:

```bash
mise run test -- --filter AgentStudioOTLPTraceProjectionTests
```

Expected before implementation: fails because IDs and Bridge attributes are dropped.

- [ ] **Step 4: Implement safe projection**

Implementation rules:

- `traceID` must match 32 lowercase hex characters and not be all zeroes.
- `spanID` and `parentSpanID` must match 16 lowercase hex characters and not be all zeroes.
- Trace/span IDs are projected only into record trace fields, never ordinary attributes.
- `parentSpanID` is preserved as a projected record field when valid.
- Bridge string attributes are controlled enums from the spec.
- Bridge numeric attributes are only the spec allowlist plus existing duration/count suffixes.
- Bridge boolean attributes are only the spec allowlist.

Run the filtered projection test. Expected: pass.

- [ ] **Step 5: Write failing Bridge metric projection tests**

Add tests proving a `performance.bridge.*` event promotes safe numeric Bridge attributes and rejects unsafe IDs:

```swift
let event = AgentStudioOTLPPerformanceMetricEvent(record: projectedRecord)
#expect(event?.samples.contains {
    $0.label == "agentstudio_bridge_content_byte_size_bucket"
        && $0.value == 100000
} == true)
```

Run:

```bash
mise run test -- --filter AgentStudioOTLPPerformanceMetricsTests
```

Expected before implementation: safe Bridge metrics are ignored.

- [ ] **Step 6: Implement Bridge metric labels**

Extend `metricLabel(for:)` to accept only:

- `agentstudio.performance.elapsed_ms`
- numeric keys starting with `agentstudio.bridge.` that are in the Bridge numeric allowlist

Use `agentstudio_bridge_...` labels for Bridge gauges. Do not allow `id`, `path`, `hash`, `error`, `payload`, `text`, `prompt`, or `output` anywhere in a metric label.

Run the filtered metric test. Expected: pass.

- [ ] **Step 7: Add tracing backend wrapper**

`AgentStudioOTLPTracingBackend` should:

- call `OTel.makeTracingBackend(configuration:)`
- return the tracing service for the bootstrapper service group
- store the returned tracer as a diagnostics-owned `any LegacyTracer`
- expose methods to start/end spans by safe operation name
- expose traceparent inject/extract through `AgentStudioTraceparentCarrier`
- support backdated duration spans using `DefaultTracerClock.Timestamp`

Do not bootstrap `InstrumentationSystem` globally unless a later implementation review proves that is safer than direct tracer ownership.

- [ ] **Step 8: Wire tracing backend into OTLP bootstrapper**

When OTLP is enabled:

- set `configuration.traces.enabled = true`
- set `configuration.traces.exporter = .otlp`
- set `configuration.traces.otlpExporter.endpoint` to `/v1/traces`
- set `configuration.traces.otlpExporter.protocol = .httpProtobuf`
- add tracing service to the same `ServiceGroup` as logs and metrics
- keep normal app startup fail-open on bootstrap failure
- emit OTLP logs with span context attached through `ServiceContext` or another verified Swift OTel API; simply preserving `traceID`/`spanID` on an intermediate projected record is not enough

Run:

```bash
mise run test -- --filter AgentStudioOTLPBootstrapSmokeTests
```

Expected: pass with tests proving service composition includes trace capability without requiring the real collector.

- [ ] **Step 9: Prove log/span correlation survives OTLP bootstrap**

Extend `AgentStudioOTLPBootstrapSmokeTests` so a JS-originated Bridge record exports:

- an OTLP log carrying the expected trace/span context
- an OTLP span with the same trace id
- no raw unsafe attributes

If Swift OTel only attaches log span context from `ServiceContext.current`, implement the diagnostics-owned helper that emits the log inside a constructed span context before continuing to Bridge code.

## Task 2: Bridge Telemetry Contracts And Runtime Actors

**Files:**
- Create: `Sources/AgentStudio/Features/Bridge/Models/Telemetry/BridgeTraceContext.swift`
- Create: `Sources/AgentStudio/Features/Bridge/Models/Telemetry/BridgeTelemetryBatch.swift`
- Create: `Sources/AgentStudio/Features/Bridge/Models/Telemetry/BridgeTelemetrySample.swift`
- Create: `Sources/AgentStudio/Features/Bridge/Models/Telemetry/BridgeTelemetryScope.swift`
- Create: `Sources/AgentStudio/Features/Bridge/Models/Telemetry/BridgeTelemetryDropReason.swift`
- Create: `Sources/AgentStudio/Features/Bridge/Models/Telemetry/BridgeTelemetrySinkState.swift`
- Create: `Sources/AgentStudio/Features/Bridge/Runtime/Telemetry/BridgePerformanceTraceRecorder.swift`
- Create: `Sources/AgentStudio/Features/Bridge/Runtime/Telemetry/BridgeTelemetryIngestor.swift`
- Create: `Sources/AgentStudio/Features/Bridge/Runtime/Telemetry/BridgeTelemetryBatchValidator.swift`
- Create: `Sources/AgentStudio/Features/Bridge/Runtime/Telemetry/BridgeTelemetryScopeGate.swift`
- Create: `Sources/AgentStudio/Features/Bridge/Runtime/Telemetry/BridgeTelemetryAggregator.swift`
- Test: `Tests/AgentStudioTests/Features/Bridge/BridgeTraceContextTests.swift`
- Test: `Tests/AgentStudioTests/Features/Bridge/BridgeTelemetryBatchValidatorTests.swift`
- Test: `Tests/AgentStudioTests/Features/Bridge/BridgeTelemetryIngestorTests.swift`
- Test: `Tests/AgentStudioTests/Features/Bridge/BridgePerformanceTraceRecorderTests.swift`

- [ ] **Step 1: Write failing trace context tests**

Tests must cover:

- valid W3C trace IDs/span IDs
- invalid/all-zero IDs
- `traceparent` serialization
- `traceparent` parsing for content-fetch headers

Run:

```bash
mise run test -- --filter BridgeTraceContextTests
```

Expected before implementation: compile failure.

- [ ] **Step 2: Implement `BridgeTraceContext`**

Contract:

```swift
struct BridgeTraceContext: Codable, Equatable, Sendable {
    let traceId: String
    let spanId: String
    let parentSpanId: String?
    let sampled: Bool
}
```

Use explicit validation helpers. Do not import OTel types into this Bridge model.

- [ ] **Step 3: Write failing batch validation tests**

Validation must reject:

- disabled scopes
- raw telemetry messages over 16 KiB before deep decode
- oversized encoded batches
- too many samples
- invalid trace context
- unsafe event names
- unsafe attributes

It must return explicit `BridgeTelemetryDropReason` instead of raw error strings.

Run:

```bash
mise run test -- --filter BridgeTelemetryBatchValidatorTests
```

Expected before implementation: compile failure.

- [ ] **Step 4: Implement DTOs and validator**

Use small Sendable value types. Keep JS-originated text out of error descriptions.

Hard limits:

- `maxSamplesPerBatch = 64`
- `maxEncodedBatchBytes = 16 * 1024`
- `maxPendingBatchesPerPane = 2`
- `maxSwiftIngestQueueDepth = 8`
- `minimumFlushIntervalMilliseconds = 250`
- `maximumDropSummaryIntervalMilliseconds = 1000`

Allowed sample shape:

```swift
struct BridgeTelemetrySample: Codable, Equatable, Sendable {
    let scope: BridgeTelemetryScope
    let name: String
    let durationMilliseconds: Double?
    let traceContext: BridgeTraceContext?
    let stringAttributes: [String: String]
    let numericAttributes: [String: Double]
    let booleanAttributes: [String: Bool]
}
```

Do not accept arbitrary nested JSON payloads.

- [ ] **Step 5: Write failing recorder and ingestor tests**

Tests must prove:

- disabled recorder allocates no attributes and records nothing
- Swift package/content events record safe attributes
- ingestor runs as an actor and forwards summarized samples
- drop accounting emits `performance.bridge.web.telemetry_drop`
- raw oversized telemetry payloads are rejected before deep decode
- queue saturation records summarized drops without creating unbounded tasks
- pane teardown flushes or explicitly drops pending summaries with counted reasons

Run:

```bash
mise run test -- --filter BridgeTelemetryIngestorTests
mise run test -- --filter BridgePerformanceTraceRecorderTests
```

Expected before implementation: compile failure.

- [ ] **Step 6: Implement recorder and ingestor**

Rules:

- `BridgePerformanceTraceRecorder` checks tag enablement before building dictionaries.
- `BridgeTelemetryIngestor` is an actor.
- MainActor Bridge code does not create untracked fire-and-forget tasks. It either awaits an actor method from an already async path or uses a lifecycle-owned per-pane telemetry queue/task that is cancelled/flushed during `BridgePaneController.teardown()`.
- Duration spans are emitted only for real lifecycle operations.
- Web-originated durations become metrics plus a logical span with start time `now - duration` and end time `now`, because browser `performance.now()` is not a Unix clock.
- `system.bridgeTelemetry` decode and validation happen inside `BridgeTelemetryIngestor`, after the raw-size guard and queue admission check.

Run all Task 2 filtered tests. Expected: pass.

## Task 3: Swift Bridge Transport Instrumentation

**Files:**
- Modify: `Sources/AgentStudio/Features/Bridge/Runtime/BridgePaneController.swift`
- Modify: `Sources/AgentStudio/Features/Bridge/Runtime/ReviewFoundation/BridgeContentStore.swift`
- Modify: `Sources/AgentStudio/Features/Bridge/Transport/RPCRouter.swift`
- Modify: `Sources/AgentStudio/Features/Bridge/Transport/RPCMessageHandler.swift`
- Modify: `Sources/AgentStudio/Features/Bridge/Transport/BridgeSchemeHandler.swift`
- Modify: `Sources/AgentStudio/Features/Bridge/Transport/BridgeBootstrap.swift`
- Modify: `Sources/AgentStudio/Features/Bridge/Transport/Methods/SystemMethods.swift`
- Test: `Tests/AgentStudioTests/Features/Bridge/BridgePaneControllerTests.swift`
- Test: `Tests/AgentStudioTests/Features/Bridge/BridgeBootstrapTests.swift`
- Test: `Tests/AgentStudioTests/Features/Bridge/RPCRouterTests.swift`
- Test: `Tests/AgentStudioTests/Features/Bridge/RPCMessageHandlerTests.swift`
- Test: `Tests/AgentStudioTests/Features/Bridge/BridgeContentStoreTests.swift`
- Test: `Tests/AgentStudioTests/Features/Bridge/BridgeSchemeHandlerTests.swift`
- Test: `Tests/AgentStudioTests/Features/Bridge/BridgeTransportIntegrationTests.swift`

- [ ] **Step 1: Write failing push trace tests**

Test `BridgePaneController.pushJSON(...)` through a fake recorder:

- enabled path adds `__traceContext` when any active Bridge telemetry scope needs cross-boundary correlation
- disabled path does not add `__traceContext`
- `__pushId` remains distinct from trace IDs
- duplicate-push dedup still works
- `BridgeBootstrap.applyEnvelope(...)` preserves `__traceContext` through the `__bridge_push` event detail

Run:

```bash
mise run test -- --filter BridgePaneControllerTests
mise run test -- --filter BridgeBootstrapTests
```

Expected before implementation: missing trace metadata.

- [ ] **Step 2: Instrument push envelopes**

Add optional metadata:

```json
"__traceContext": {
  "traceId": "11111111111111111111111111111111",
  "spanId": "2222222222222222",
  "parentSpanId": null,
  "sampled": true
}
```

Only add it when Bridge telemetry is active and the scope gate says the push/RPC/content interaction needs cross-boundary correlation. Keep review payloads unchanged. Update `BridgeBootstrap.merge`, `BridgeBootstrap.replace`, and `BridgeBootstrap.applyEnvelope` so the metadata survives into page-world push events.

- [ ] **Step 3: Write failing RPC trace metadata tests**

Extend `RPCRouterTests` to prove:

- `__traceContext` decodes outside `params`
- invalid trace metadata does not reject a valid command
- valid trace metadata reaches a recorder callback
- command ack behavior is unchanged
- `system.bridgeTelemetry` is excluded from generic RPC dispatch/response telemetry
- `system.bridgeTelemetry` is absent or method-not-found in release-style composition

Run:

```bash
mise run test -- --filter RPCRouterTests
```

Expected before implementation: metadata ignored.

- [ ] **Step 4: Instrument RPC dispatch and response**

Add an optional trace-context callback or dispatch context to `RPCRouter`:

- `performance.bridge.webkit.rpc_dispatch`
- `performance.bridge.webkit.rpc_response`
- `agentstudio.bridge.transport = rpc`
- `agentstudio.bridge.lane = warm`

Do not add trace context to typed method params.

Add a special raw route for `system.bridgeTelemetry`:

- detect the method before typed params decode
- reject messages over 16 KiB before deep parsing
- admit at most two pending batches per pane
- hand raw `Data` to `BridgeTelemetryIngestor`
- return no response payload on accepted notifications
- emit `performance.bridge.webkit.telemetry_batch` or summarized drop accounting

- [ ] **Step 5: Write failing content-store observation tests**

Extend `BridgeContentStoreTests` to prove store-owned telemetry observations for:

- cache hit
- cold provider load
- in-flight coalesced load
- stale generation rejection
- binary rejection
- oversize rejection

Run:

```bash
mise run test -- --filter BridgeContentStoreTests
```

Expected before implementation: no content-load observation surface.

- [ ] **Step 6: Add content-store observation seam**

Add an instrumentation-neutral result alongside content loads. It may be a wrapper result or callback value, but it must be owned by `BridgeContentStore` and must not import diagnostics types.

`BridgeSchemeHandler` may add request/header facts, but it must not infer cache status, stale status, binary status, or provider-vs-cache result by duplicating store logic.

- [ ] **Step 7: Write failing content fetch header tests**

Use a real WebKit serialized test in `BridgeTransportIntegrationTests` to prove whether custom `traceparent` headers arrive in `URLRequest.allHTTPHeaderFields`. `BridgeSchemeHandlerTests` may cover parsing and fallback branches, but it cannot prove WebKit runtime header behavior.

Run:

```bash
mise run test -- --filter BridgeSchemeHandlerTests
mise run test-webkit
```

Expected before implementation: no explicit proof exists.

- [ ] **Step 8: Instrument content fetch**

Rules:

- if `traceparent` is present and valid, continue that context
- if absent, record unparented content-load telemetry with `generation_relation`, `cache_result`, byte bucket, line bucket, and stale/binary flags
- emit a safe proof attribute indicating `header_supported` or `header_missing`
- never log full content URL, handle ID, item ID, or path

Run Task 3 tests. Expected: pass or, if WebKit strips custom headers, tests must assert the documented summary-correlated fallback.

## Task 4: BridgeWeb Telemetry Foundation

**Files:**
- Create: `BridgeWeb/src/foundation/telemetry/bridge-trace-context.ts`
- Create: `BridgeWeb/src/foundation/telemetry/bridge-telemetry-event.ts`
- Create: `BridgeWeb/src/foundation/telemetry/bridge-telemetry-scope.ts`
- Create: `BridgeWeb/src/foundation/telemetry/bridge-telemetry-buffer.ts`
- Create: `BridgeWeb/src/foundation/telemetry/bridge-telemetry-recorder.ts`
- Create: `BridgeWeb/src/foundation/telemetry/bridge-telemetry-sink.ts`
- Create: `BridgeWeb/src/foundation/telemetry/bridge-telemetry-bootstrap-config.ts`
- Create: `BridgeWeb/src/bridge/bridge-telemetry-event-sink.ts`
- Create: `BridgeWeb/src/app/bridge-telemetry-composition.ts`
- Modify: `BridgeWeb/src/bridge/bridge-page-handshake.ts`
- Modify: `BridgeWeb/src/bridge/bridge-push-envelope.ts`
- Modify: `BridgeWeb/src/bridge/bridge-rpc-client.ts`
- Modify: `BridgeWeb/src/foundation/content/content-resource-loader.ts`
- Modify: `BridgeWeb/src/app/bridge-app.tsx`
- Modify: `BridgeWeb/src/review-viewer/shell/review-viewer-shell.tsx`
- Test: adjacent `*.unit.test.ts` and `*.integration.test.tsx` files.

- [ ] **Step 1: Write failing trace context tests**

Add `BridgeWeb/src/foundation/telemetry/bridge-trace-context.unit.test.ts`.

Test:

- W3C trace ID/span ID validation
- random context generation with `crypto.getRandomValues`
- `traceparent` serialization
- invalid context rejection
- bootstrap config decoding from `__bridge_handshake` telemetry metadata

Run:

```bash
pnpm --dir BridgeWeb test -- bridge-trace-context.unit.test.ts
```

Expected before implementation: file missing.

- [ ] **Step 2: Implement trace context foundation**

Types use explicit names and readonly fields:

```ts
export interface BridgeTraceContext {
	readonly traceId: string;
	readonly spanId: string;
	readonly parentSpanId: string | null;
	readonly sampled: boolean;
}
```

No `any`. Use `unknown` only at decoding boundaries with Zod.

Add `BridgeTelemetryBootstrapConfig` with:

- `enabled`
- `scopes`
- `maxSamplesPerBatch`
- `maxEncodedBatchBytes`
- `maxPendingBatchesPerPane`
- `minimumFlushIntervalMilliseconds`
- `methodName = "system.bridgeTelemetry"`
- `scenario = "package_apply_content_fetch_v1"`

The app should receive this through `installBridgePageHandshakeSession(...)`. If the handshake carries no config or `enabled` is false, composition must return the null recorder.

- [ ] **Step 3: Write failing buffer/recorder tests**

Add tests for:

- disabled null recorder
- max samples per batch
- max encoded byte size
- drop reasons
- flush on interaction complete
- no per-scroll/per-frame emission API

Run:

```bash
pnpm --dir BridgeWeb test -- bridge-telemetry-buffer.unit.test.ts bridge-telemetry-recorder.unit.test.ts
```

Expected before implementation: files missing.

- [ ] **Step 4: Implement telemetry buffer and recorder**

Rules:

- frontend timing uses `performance.now()` deltas only
- telemetry lane is cold
- batch payload is bounded and summary-oriented
- recorder API names describe domain events, not generic `track(...)`
- no direct OTLP dependency

- [ ] **Step 5: Write failing bridge transport tests**

Extend existing tests:

- `bridge-push-envelope.unit.test.ts` decodes optional `traceContext`
- `bridge-rpc-client.unit.test.ts` attaches optional `__traceContext`
- `content-resource-loader.integration.test.ts` sends `traceparent` header when provided
- `bridge-page-handshake.unit.test.ts` replays and exposes telemetry config
- `bridge-telemetry-event-sink.unit.test.ts` sends exact method `system.bridgeTelemetry`, respects readiness/nonce rules, and does not record RPC telemetry for its own telemetry batch
- `bridge-telemetry-composition.unit.test.ts` proves config present creates an active recorder, config absent creates a null recorder, and release-style config creates no active sink

Run:

```bash
pnpm --dir BridgeWeb test -- bridge-push-envelope.unit.test.ts bridge-rpc-client.unit.test.ts content-resource-loader.integration.test.ts bridge-telemetry-event-sink.unit.test.ts
```

Expected before implementation: tests fail for missing trace support.

- [ ] **Step 6: Implement BridgeWeb transport hooks**

Implementation rules:

- `__traceContext` lives in transport metadata, not method params.
- content fetch uses:

```ts
fetchContent(handle.resourceUrl, {
	headers: traceparent === null ? undefined : { traceparent },
});
```

- telemetry batch uses typed RPC command name from Task 3.
- app composition selects null recorder unless debug telemetry config is present.
- the generic RPC client skips trace-context attachment and RPC telemetry for `system.bridgeTelemetry`.

- [ ] **Step 7: Prove no direct browser OTLP**

Run a source and dependency scan:

```bash
rg -n "@opentelemetry|otlp|OTLP|collector|v1/traces|v1/logs|v1/metrics" BridgeWeb/package.json BridgeWeb/pnpm-lock.yaml BridgeWeb/src BridgeWeb/app || true
```

Expected: no hits for direct browser exporter dependencies or collector endpoints. Documentation comments that mention "no direct OTLP" are acceptable only outside shipped `BridgeWeb/app` assets.

- [ ] **Step 8: Run BridgeWeb validation**

Run:

```bash
mise run bridge-web-check
mise run bridge-web-test
```

Expected: both exit 0.

## Task 5: App Composition And Debug Activation

**Files:**
- Modify exact app composition files that construct `BridgePaneController` after locating them with:

```bash
rg -n "BridgePaneController\\(" Sources/AgentStudio Tests/AgentStudioTests
```

- Modify: `Sources/AgentStudio/Features/Bridge/Runtime/BridgePaneController.swift`
- Modify: relevant test support helpers such as `Tests/AgentStudioTests/Features/Bridge/BridgePaneControllerRefreshTestSupport.swift`

- [ ] **Step 1: Write failing composition tests**

Tests must prove:

- no recorder means disabled Bridge telemetry
- injected recorder receives push/RPC/content events
- release-style configuration does not allocate active BridgeWeb telemetry sinks
- release-style configuration does not register `system.bridgeTelemetry`
- startup diagnostic action `bridge-review-observability-smoke` is DEBUG-only and parses from `AGENTSTUDIO_STARTUP_DIAGNOSTIC_ACTION`

Run:

```bash
mise run test-fast -- --filter BridgePaneController
mise run test-fast -- --filter AgentStudioStartupDiagnosticActionTests
```

Expected before implementation: constructor lacks telemetry injection.

- [ ] **Step 2: Wire recorder through composition**

Rules:

- Bridge does not fetch a global singleton.
- Existing tests can still construct `BridgePaneController` with default no-op telemetry.
- Production debug launcher enables tags through environment, not through hardcoded Bridge flags.
- If `AGENTSTUDIO_TRACE_TAGS` is absent, the ordinary debug safe baseline must not activate Bridge telemetry just because Bridge enum cases exist.
- Bridge telemetry activates when the trace tag selection explicitly includes `bridge.performance.*`, `bridge.performance.swift`, `bridge.performance.web`, `bridge.performance.webkit`, or an explicit wildcard in a Bridge proof run.
- MainActor only coordinates WebKit and UI; heavy validation remains in actors.

- [ ] **Step 3: Run focused Swift validation**

Run:

```bash
mise run test-fast -- --filter BridgeTraceContextTests
mise run test-fast -- --filter BridgeTelemetry
mise run test-fast -- --filter BridgeContentStoreTests
mise run test-fast -- --filter AgentStudioOTLP
```

Expected: exit 0.

## Task 6: Bridge Observability Verifier

**Files:**
- Create: `scripts/verify-bridge-observability.sh`
- Modify: `.mise.toml`
- Modify: `Tests/AgentStudioTests/Scripts/ObservabilityDebugLaunchScriptsTests.swift`
  with the Bridge verifier contract assertion.
- Create/update: `docs/wip/bridge-observability/2026-06-14-bridge-observability-proof.md`

- [ ] **Step 1: Add a mise task**

Add:

```toml
[tasks.verify-bridge-observability]
description = "Verify Bridge logs, metrics, traces, and privacy canaries in the shared Victoria stack"
run = "/bin/bash scripts/verify-bridge-observability.sh"
```

- [ ] **Step 2: Implement verifier preflight**

The script must:

- source `tmp/debug-observability/latest-observability.env`
- require `AGENTSTUDIO_OBSERVABILITY_STATUS=running`
- require the recorded PID to still be alive
- require a fresh `AGENTSTUDIO_TRACE_NAME`
- query VictoriaLogs, VictoriaMetrics, and VictoriaTraces through loopback debug ports
- fail if the shared stack is absent with a clear "run `mise run observability:up`" message

- [ ] **Step 3: Implement positive queries**

The verifier must find:

- every event family in the Required Event Inventory for scenario `package_apply_content_fetch_v1`
- at least one Bridge metric sample in VictoriaMetrics
- a Swift package-build span, content-fetch span, and review RPC dispatch span
  in VictoriaTraces
- `agentstudio.bridge.test.scenario = package_apply_content_fetch_v1` on every collector-backed Bridge query
- no `system.bridgeTelemetry` self-RPC `rpc_send`, `rpc_dispatch`, or
  `rpc_response` records
- no telemetry self-RPC spans with
  `agentstudio.bridge.rpc.method_class=telemetry`

- [ ] **Step 4: Implement negative privacy queries**

The verifier must fail if it finds the fresh sentinel in Victoria outputs:

- `shravan.observability.canary.secret`
- raw path-like `/Users/`
- raw `handleId`
- raw `itemId`
- raw `paneId`
- raw prompt/source text sentinel generated by the verifier

- [ ] **Step 5: Run stack proof**

Run:

```bash
mise run observability:status
mise run observability:smoke
```

Expected: collector, VictoriaLogs, VictoriaMetrics, and VictoriaTraces healthy; smoke canaries pass.

- [ ] **Step 6: Add verifier script tests if query assembly is non-trivial**

If `scripts/verify-bridge-observability.sh` builds more than simple fixed
queries, cover the verifier contract in
`Tests/AgentStudioTests/Scripts/ObservabilityDebugLaunchScriptsTests.swift` or a
dedicated script test file. Current required assertions:

- `bridge-review-observability-smoke` is required
- generic debug proof is invoked first
- Swift, WebKit, and Web events are all queried
- VictoriaTraces queries include the current marker, scenario, and review
  `rpc.method_class`
- unsafe item IDs remain a negative query
- telemetry self-RPC is queried negatively in logs and traces
- `.mise.toml` exposes `verify-bridge-observability`

## Task 7: Full Bridge Observability Proof Run

**Files:**
- Modify proof doc: `docs/wip/bridge-observability/2026-06-14-bridge-observability-proof.md`

- [ ] **Step 1: Launch debug app through the standard runner**

Run:

```bash
AGENTSTUDIO_TRACE_TAGS=app.startup,terminal.startup,runtime,surface,persistence.recovery,bridge.performance.* \
AGENTSTUDIO_TRACE_BACKEND=both \
AGENTSTUDIO_TRACE_NAME=bridge-observability-$(date +%s) \
AGENTSTUDIO_STARTUP_DIAGNOSTIC_ACTION=bridge-review-observability-smoke \
AGENTSTUDIO_BRIDGE_OBSERVABILITY_SCENARIO=package_apply_content_fetch_v1 \
mise run run-debug-observability -- --detach
```

Expected: state file reports a running debug app with a fresh trace name and startup diagnostic action `bridge-review-observability-smoke`.

- [ ] **Step 2: Exercise the Bridge pane**

The startup diagnostic action must deterministically open the Bridge review pane and trigger:

- package push, with delta push optional for this first scenario
- `review.markFileViewed`
- content fetch through `agentstudio://resource/content/...`

The action is the proof driver. Do not add an ad hoc `#if DEBUG` test hook elsewhere. If the action cannot open the pane or load the deterministic fixture through existing app/Bridge seams, stop and replan the proof driver instead of manually clicking and calling the result repeatable.

- [ ] **Step 3: Verify generic debug observability**

Run:

```bash
mise run verify-debug-observability
```

Expected: exit 0.

- [ ] **Step 4: Verify Bridge-specific observability**

Run:

```bash
mise run verify-bridge-observability
```

Expected: exit 0 and proof output lists the current trace name, scenario id,
logs count, metrics count, `traces=3`, telemetry self-RPC recursion result, and
negative canary result.

- [ ] **Step 5: Record proof**

Update:

```text
docs/wip/bridge-observability/2026-06-14-bridge-observability-proof.md
```

Include commands, exit codes, trace name, branch SHA, stack status, canary result, and any content-header fallback.

## Task 8: Data-Driven Performance Cycles

**Files:**
- Modify only files implicated by measured Bridge bottlenecks.
- Update proof doc: `docs/wip/bridge-observability/2026-06-14-bridge-observability-proof.md`

- [ ] **Step 1: Capture baseline**

Run the Bridge observability proof scenario at least three times with the same fixture:

```bash
for run in 1 2 3; do
  AGENTSTUDIO_TRACE_TAGS=app.startup,terminal.startup,runtime,surface,persistence.recovery,bridge.performance.* \
  AGENTSTUDIO_TRACE_BACKEND=both \
  AGENTSTUDIO_TRACE_NAME=bridge-baseline-${run}-$(date +%s) \
  AGENTSTUDIO_STARTUP_DIAGNOSTIC_ACTION=bridge-review-observability-smoke \
  AGENTSTUDIO_BRIDGE_OBSERVABILITY_SCENARIO=package_apply_content_fetch_v1 \
  mise run run-debug-observability -- --detach
  mise run verify-bridge-observability
  state_file=tmp/debug-observability/latest-observability.env
  pid=$(awk -F= '/^AGENTSTUDIO_OBSERVABILITY_PID=/{print $2}' "$state_file" | head -1)
  if [ -n "$pid" ]; then
    kill "$pid"
  fi
done
```

Expected: three fresh trace names and queryable Bridge metrics. The loop must not leave `AGENTSTUDIO_OBSERVABILITY_STATUS=already_running`; each PID must come from the debug observability state file for this worktree.

- [ ] **Step 2: Identify hotspots**

Use VictoriaMetrics and VictoriaTraces to rank:

- package build duration
- push payload byte bucket
- push dispatch duration
- RPC dispatch duration
- content load duration
- BridgeWeb package apply duration
- BridgeWeb content fetch duration
- first render duration

Record p50/p95 if the query supports it; otherwise record per-run values and explain the limitation.

- [ ] **Step 3: Pick one scoped improvement**

Only optimize a measured bottleneck inside Bridge telemetry/transport overhead. Examples of allowed scoped improvements:

- avoid duplicate attribute dictionary construction on disabled path
- reduce push payload envelope encoding work
- coalesce cold telemetry batches more aggressively
- skip BridgeWeb telemetry batch serialization when disabled/not ready
- bucket byte/line counts before crossing WebKit

Do not change unrelated SQLite, Git provider, or Pierre code.

If the largest hotspot is the review data provider, Git backend, future Pierre/Shiki rendering, or unrelated app startup work, record it and stop this plan's optimization loop. That follow-up needs its own ticket/plan.

- [ ] **Step 4: Prove the improvement**

Run before/after comparison with the same fixture and same trace-tag configuration.

Expected proof shape:

```text
hotspot: performance.bridge.webkit.package_push
baseline p95: <value> ms
after p95: <value> ms
delta: <value> ms / <percent>
commands: <exact commands>
trace names: <baseline>, <after>
```

Before optimizing this event, split it with a low-cardinality push-slice
attribute such as `review_package`, `review_delta`, `connection`, or `agent`.
The current event measures WebKit push transport as a whole, so it is useful for
detecting pressure but too broad for package-specific optimization claims.

- [ ] **Step 5: Repeat for up to three cycles**

Stop after three measured improvement cycles or when the next bottleneck requires a separate product/design discussion.

## Task 9: Final Validation And Review

**Files:**
- All changed files.
- Proof doc: `docs/wip/bridge-observability/2026-06-14-bridge-observability-proof.md`

- [ ] **Step 1: Run collector-free validation**

Run:

```bash
mise run bridge-web-check
mise run bridge-web-test
mise run test-fast -- --filter BridgeTraceContextTests
mise run test-fast -- --filter BridgeTelemetry
mise run test-fast -- --filter BridgeContentStoreTests
mise run test-fast -- --filter AgentStudioOTLP
mise run lint
git diff --check
```

Expected: all exit 0.

Run WebKit proof separately:

```bash
mise run test-webkit
```

Expected: Bridge-owned WebKit assertions for `BridgeTransportIntegrationTests` pass. If the known WebKit harness exits with signal/broken-pipe after Bridge-owned assertions pass, record the exact failure separately and do not edit unrelated WebKit infrastructure without re-scoping.

- [ ] **Step 2: Run observability validation**

Run:

```bash
mise run observability:status
mise run observability:smoke
AGENTSTUDIO_TRACE_TAGS=app.startup,terminal.startup,runtime,surface,persistence.recovery,bridge.performance.* \
AGENTSTUDIO_TRACE_BACKEND=both \
AGENTSTUDIO_TRACE_NAME=bridge-final-$(date +%s) \
AGENTSTUDIO_STARTUP_DIAGNOSTIC_ACTION=bridge-review-observability-smoke \
AGENTSTUDIO_BRIDGE_OBSERVABILITY_SCENARIO=package_apply_content_fetch_v1 \
mise run run-debug-observability -- --detach
mise run verify-debug-observability
mise run verify-bridge-observability
```

Expected: all exit 0. If the app is already running, stop only after confirming it is the debug app for this worktree; never kill stable/beta/user apps by name.

- [ ] **Step 3: Run review swarm**

Use:

```text
$shravan-dev-workflow:implementation-review-swarm
```

Review lanes must check:

- privacy/scrubbing and high-cardinality label risk
- trace correctness across push/RPC/content fetch
- disabled-path overhead
- MainActor boundary and actor isolation
- BridgeWeb folder naming and test naming
- no SQLite/Git/Pierre scope drift
- proof doc freshness

- [ ] **Step 4: Address accepted findings**

For each accepted finding:

- add or update the failing proof first
- implement the smallest scoped fix
- rerun the impacted proof gate
- update the proof doc

- [ ] **Step 5: Final goal closeout**

Do not mark the goal complete until:

- spec/design row is done
- plan row is done and reviewed
- implementation proof is done
- implementation review row is done
- Victoria proof row is done
- performance-cycle row is done or explicitly marked blocked by a scoped design decision

## Validation Command Set

Collector-free:

```bash
mise run bridge-web-check
mise run bridge-web-test
mise run test-fast -- --filter BridgeTraceContextTests
mise run test-fast -- --filter BridgeTelemetry
mise run test-fast -- --filter BridgeContentStoreTests
mise run test-fast -- --filter AgentStudioOTLP
mise run lint
git diff --check
```

Collector-backed:

```bash
mise run observability:status
mise run observability:smoke
AGENTSTUDIO_TRACE_TAGS=app.startup,terminal.startup,runtime,surface,persistence.recovery,bridge.performance.* \
AGENTSTUDIO_TRACE_BACKEND=both \
AGENTSTUDIO_TRACE_NAME=bridge-validation-$(date +%s) \
AGENTSTUDIO_STARTUP_DIAGNOSTIC_ACTION=bridge-review-observability-smoke \
AGENTSTUDIO_BRIDGE_OBSERVABILITY_SCENARIO=package_apply_content_fetch_v1 \
mise run run-debug-observability -- --detach
mise run verify-debug-observability
mise run verify-bridge-observability
```

Known repo-wide guard:

- `mise run test-webkit` may expose unrelated WebKit harness signal/broken-pipe behavior. If it fails after the owned Bridge telemetry assertions passed, record the exact signal and changed-surface proof separately before expanding scope.

## Risks And Replan Triggers

- If `WKURLSchemeHandler` does not receive custom headers for `agentstudio://resource/content`, do not put trace IDs in the URL. Use the summary-correlated fallback and document it in the proof.
- If direct tracer ownership through Swift OTel proves impossible under Swift's generic constraints, replan the diagnostics task around a process-global `InstrumentationSystem.bootstrap(...)` once-per-process guard before touching Bridge code.
- If VictoriaTraces does not expose enough query surface through the shared stack helper, add the smallest verifier query helper in this repo and keep generic Victoria lifecycle/config in `~/dev/ai-tools/observability`.
- If disabled Bridge telemetry shows measurable overhead in the baseline, fix disabled-path guards before adding more event scopes.
- If any improvement points at Git data-plane behavior, stop and hand that to the separate Git lane. This plan owns Bridge observability only.

## Execution Notes

- Use hard cutover. Do not leave old and new telemetry paths in parallel.
- Keep BridgeWeb telemetry files domain-named; do not add `types.ts`, `utils.ts`, `store.ts`, `protocol.ts`, or `helpers.ts`.
- Keep tests permanent. Do not create throwaway test files.
- Use `BridgeReviewGeneration` for review freshness and `__epoch` only for transport-local push staleness.
- Keep telemetry cold-lane and bounded. It must never block hot review pushes, content fetch, or first render.
