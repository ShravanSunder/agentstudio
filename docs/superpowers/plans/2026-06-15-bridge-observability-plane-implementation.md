# Bridge Observability Plane Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use
> `superpowers:subagent-driven-development` or
> `superpowers:executing-plans` to implement this plan task-by-task.

## Goal

Cut over Bridge telemetry taxonomy so observability is a separate best-effort
plane, not a cold product lane. Add low-cardinality `plane`, `priority`, and
`slice` attributes; carry exact push-slice identity through native push
transport and BridgeWeb envelopes; split broad WebKit push timing by concrete
finite push slice; align drop reason wire vocabulary; and prove the result
through Swift tests, BridgeWeb tests, OTLP projection tests, and the Victoria
verifier.

## Source Coverage

Design/spec sources:

- `docs/superpowers/specs/2026-06-15-bridge-observability-plane-design.md`
- `docs/superpowers/specs/2026-06-14-bridge-debug-telemetry-observability.md`
  - 909 lines, read in chunks 1-220, 221-440, 441-700, and 701-909.
- `docs/superpowers/plans/2026-06-14-bridge-observability-implementation.md`
  - 1367 lines, read in chunks 1-280, 281-560, 561-920, and 921-1367.
- `docs/wip/bridge-observability/2026-06-14-bridge-observability-proof.md`
  - 304 lines, inspected for measured push and telemetry batch evidence.

Repo evidence:

- `Sources/AgentStudio/Features/Bridge/State/Push/PushTransport.swift`
- `Sources/AgentStudio/Features/Bridge/State/Push/PushPlan.swift`
- `Sources/AgentStudio/Features/Bridge/State/Push/Slice.swift`
- `Sources/AgentStudio/Features/Bridge/State/Push/EntitySlice.swift`
- `Sources/AgentStudio/Features/Bridge/Runtime/BridgePaneController.swift`
- `Sources/AgentStudio/Features/Bridge/Runtime/Telemetry/BridgeTelemetryIngestor.swift`
- `Sources/AgentStudio/Features/Bridge/Models/Telemetry/*`
- `Sources/AgentStudio/Features/Bridge/Runtime/Telemetry/*`
- `Sources/AgentStudio/Features/Bridge/Transport/RPCRouter.swift`
- `Sources/AgentStudio/Features/Bridge/Transport/BridgeSchemeHandler.swift`
- `Sources/AgentStudio/Infrastructure/Diagnostics/AgentStudioOTLPTraceProjection.swift`
- `Sources/AgentStudio/Infrastructure/Diagnostics/AgentStudioOTLPPerformanceMetrics.swift`
- `BridgeWeb/src/foundation/telemetry/*`
- `BridgeWeb/src/bridge/bridge-rpc-client.ts`
- `BridgeWeb/src/bridge/bridge-push-envelope.ts`
- `BridgeWeb/src/app/bridge-app.tsx`
- `Sources/AgentStudio/Resources/BridgeWeb/app/*`
- `scripts/run-debug-observability.sh`
- `scripts/verify-bridge-observability.sh`

External grounding:

- OpenTelemetry semantic convention guidance recommends low-cardinality span
  names and careful attribute selection.
- OpenTelemetry attribute requirement guidance says metric attributes that may
  have high cardinality can only be opt-in.
- OpenTelemetry metrics SDK guidance includes aggregation cardinality limits.

References:

- https://opentelemetry.io/docs/specs/semconv/how-to-write-conventions/
- https://opentelemetry.io/docs/specs/semconv/general/attribute-requirement-level/
- https://opentelemetry.io/docs/specs/otel/metrics/sdk/

## Non-Goals

- No direct browser OTLP.
- No new Bridge atom, Core store, SQLite table, or persistence model.
- No change to package/delta/content correctness behavior.
- No product retry, backpressure, or ordering behavior based on telemetry
  success.
- No Git, SQLite, Worktrunk, or Pierre/Shiki/Trees implementation work.
- No optimization of push behavior until push-slice attribution is proven.
- No lossy push-slice inference from `StoreKey`, `PushOp`, payload shape, or
  entity keys when producer-owned slice identity can be carried.

## Requirements And Proof Matrix

| Requirement | Owning task | Proof owner | Proof gate | Layer | Stale-proof guard | Red/green |
|---|---|---|---|---|---|---|
| Bridge telemetry has explicit `plane`, `priority`, and `slice` vocabulary. | Task 1 | executor | Swift model/validator tests and TS schema tests | unit | Tests must fail before enum/schema exists. | yes |
| Observability traffic is not classified as hot/warm/cold product lane. | Task 2, Task 3 | executor | Swift recorder tests, BridgeWeb recorder tests, verifier query | unit, observability | Search for `agentstudio.bridge.lane` in Bridge telemetry outputs. | yes |
| Observability failure cannot affect product behavior. | Task 2, Task 3 | executor | failing-sink callsite tests for RPC/content/ingest paths | unit, integration | Tests force telemetry validation/flush failure and still expect command/content success. | yes |
| Broad push timing can be grouped by concrete finite push slice. | Task 2, Task 3, Task 5 | executor | push transport tests, `BridgePaneControllerTelemetryTests`, BridgeWeb envelope tests, Victoria verifier | unit, observability | Verifier must query at least two known slices or prove the single-slice smoke fixture. | yes |
| Browser-originated telemetry remains `.web` only and cannot spoof native planes. | Task 1, Task 3 | executor | validator tests | unit | Invalid `.swift`/`.webkit` browser samples with allowed plane must still drop. | yes |
| OTLP projection preserves safe finite attributes and drops unsafe cardinality. | Task 4 | executor | `AgentStudioOTLPTraceProjectionTests`, metrics tests, bootstrap smoke tests | unit | Invalid enum canaries cover every disallowed class from the spec. | yes |
| VictoriaMetrics can group Bridge performance by bounded `plane`, `priority`, and `slice` dimensions. | Task 4, Task 5 | executor | metrics dimension tests plus PromQL verifier queries | unit, observability | Only closed enum values become labels; dynamic values are dropped. | yes |
| Drop reason wire values match between Swift and BridgeWeb. | Task 1, Task 3 | executor | Swift Codable tests and Vitest serialization tests | unit | `queue_saturated` must be accepted end to end. | yes |
| Verifier proves data/control/observability separation in Victoria. | Task 5 | executor | `mise run verify-bridge-observability` | observability | Uses fresh marker and scenario persisted in state file. | no |
| No direct browser OTLP is introduced. | Task 6 | executor | failing static scan helper and script tests | static | Scan package dependencies, `BridgeWeb/src`, and generated app assets. | yes |
| The change stays in Bridge/Diagnostics/BridgeWeb docs/tests. | Task 7 | parent plus reviewer | `git diff --name-only`, lint boundary checks | review, lint | Diff must not touch SQLite/Git/Pierre unless re-scoped. | no |

## Task 1: Contract Vocabulary Cutover

**Files:**

- Modify: `Sources/AgentStudio/Features/Bridge/Models/Telemetry/BridgeTelemetrySample.swift`
- Modify: `Sources/AgentStudio/Features/Bridge/Models/Telemetry/BridgeTelemetryDropReason.swift`
- Create or modify adjacent model files for:
  - `BridgeTelemetryPlane`
  - `BridgeTelemetryPriority`
  - `BridgeTelemetrySlice`
- Modify: `Sources/AgentStudio/Features/Bridge/Runtime/Telemetry/BridgeTelemetryBatchValidator.swift`
- Tests:
  - `Tests/AgentStudioTests/Features/Bridge/BridgeTelemetryBatchValidatorTests.swift`
  - `Tests/AgentStudioTests/Features/Bridge/BridgeTraceContextTests.swift` if fixture helpers need updates

Steps:

1. Add failing tests for allowed values:

   ```text
   plane = data | control | observability
   priority = hot | warm | cold | best_effort
   slice = finite enum from the design spec
   ```

2. Add failing tests that reject:

   ```text
   plane=review-<uuid>
   priority=/Users/example
   slice=diffFiles:<itemId>
   agentstudio.bridge.lane on new web samples
   ```

3. Add failing tests for drop reason wire values. `queue_saturated` must decode
   to Swift and survive validator allowlists.

4. Implement the Swift model changes with Sendable Codable enums. Prefer
   snake_case raw values for wire format and idiomatic enum case names in Swift.

5. Update `BridgeTelemetryBatchValidator` allowlists. Browser-originated
   samples still accept only `.web` scope.

Proof:

```bash
mise run test -- --filter BridgeTelemetryBatchValidatorTests
git diff --check
```

Expected: exit 0.

## Task 2: Native Recorder Classification

**Files:**

- Modify: `Sources/AgentStudio/Features/Bridge/Runtime/Telemetry/BridgePerformanceTraceRecorder.swift`
- Modify: `Sources/AgentStudio/Features/Bridge/Runtime/Telemetry/BridgeTelemetryIngestor.swift`
- Modify: `Sources/AgentStudio/Features/Bridge/State/Push/PushTransport.swift`
- Modify: `Sources/AgentStudio/Features/Bridge/State/Push/PushPlan.swift`
- Modify: `Sources/AgentStudio/Features/Bridge/State/Push/Slice.swift`
- Modify: `Sources/AgentStudio/Features/Bridge/State/Push/EntitySlice.swift`
- Modify: `Sources/AgentStudio/Features/Bridge/Runtime/BridgePaneController.swift`
- Modify: `Sources/AgentStudio/Features/Bridge/Runtime/BridgePaneController+DiffCommands.swift`
- Modify: `Sources/AgentStudio/Features/Bridge/Transport/RPCRouter.swift`
- Modify: `Sources/AgentStudio/Features/Bridge/Transport/BridgeSchemeHandler.swift`
- Tests:
  - `Tests/AgentStudioTests/Features/Bridge/BridgePerformanceTraceRecorderTests.swift`
  - `Tests/AgentStudioTests/Features/Bridge/BridgeTelemetryIngestorTests.swift`
  - `Tests/AgentStudioTests/Features/Bridge/BridgePaneControllerTelemetryTests.swift`
  - `Tests/AgentStudioTests/Features/Bridge/RPCRouterTelemetryTests.swift`
  - `Tests/AgentStudioTests/Features/Bridge/BridgeSchemeHandlerTests.swift`

Steps:

1. Add failing-first tests for native classification:

   ```text
   performance.bridge.swift.telemetry_ingest
     plane=observability
     priority=best_effort
     slice=telemetry_ingest

   performance.bridge.webkit.package_push
     carries exact producer slice for diff_package_metadata,
     diff_package_delta, diff_files, and connection_health
   ```

2. Add exact push-slice carriage to the push path.

   The source of truth should be the known slice name from the push plan, not
   payload data. Carry the canonical slice from the declared slice owner through
   `Slice`, `EntitySlice`, `PushPlan`, and `PushTransport` into
   `BridgePaneController.pushJSON(...)`.

   Do not fall back to `StoreKey`/`PushOp` mapping. It collapses distinct
   slices such as `diff_status` vs `diff_package_metadata` and
   `diff_package_delta` vs `diff_files`.

3. Replace `agentstudio.bridge.lane` in new Bridge telemetry records with:

   ```text
   agentstudio.bridge.priority
   agentstudio.bridge.plane
   agentstudio.bridge.slice
   ```

4. Classify native telemetry events according to the design spec.

   Product `priority` must come from an explicit event-owned mapping, not from
   `PushLevel` directly. Add a mapping test that proves a future debounce
   retune cannot silently change emitted semantic priority.

5. Keep `system.bridgeTelemetry` excluded from generic RPC telemetry. Its
   accounting events are `plane=observability`, `priority=best_effort`,
   `slice=telemetry_batch`.

6. Add callsite-level failure-isolation tests where telemetry validation or
   recording fails but product RPC dispatch, content fetch, and push delivery
   continue to behave as before.

Proof:

```bash
mise run test -- --filter BridgePerformanceTraceRecorderTests
mise run test -- --filter BridgeTelemetryIngestorTests
mise run test -- --filter BridgePaneControllerTelemetryTests
mise run test -- --filter RPCRouterTelemetryTests
mise run test -- --filter BridgeSchemeHandlerTests
git diff --check
```

Expected: exit 0.

Replan trigger:

- If exact push slice cannot be propagated through the push transport and
  BridgeWeb envelope in this PR, stop and split a smaller push-transport
  taxonomy plan. Do not ship guessed, store-derived, payload-derived, or dynamic
  slices.

## Task 3: BridgeWeb Telemetry Classification

**Files:**

- Modify: `BridgeWeb/src/foundation/telemetry/bridge-telemetry-event.ts`
- Modify: `BridgeWeb/src/foundation/telemetry/bridge-telemetry-recorder.ts`
- Modify: `BridgeWeb/src/foundation/telemetry/bridge-telemetry-buffer.ts`
- Modify: `BridgeWeb/src/bridge/bridge-rpc-client.ts`
- Modify: `BridgeWeb/src/bridge/bridge-push-envelope.ts`
- Modify: `BridgeWeb/src/foundation/content/content-resource-loader.ts`
- Modify: `BridgeWeb/src/app/bridge-app.tsx`
- Modify: `BridgeWeb/src/review-viewer/shell/review-viewer-shell.tsx`
- Tests: adjacent `*.unit.test.ts` and `*.integration.test.tsx`

Steps:

1. Add TS schema/types for plane, priority, and slice. Use `z.enum(...)` and
   explicit readonly types.

2. Add failing-first BridgeWeb tests for exact attributes and failure
   isolation:

   - RPC send still dispatches when telemetry recording/flush fails.
   - Content fetch still resolves when telemetry recording/flush fails.
   - Full package, delta, file, status, and connection push envelopes carry the
     producer slice into web telemetry.

3. Extend the BridgeWeb push envelope schema to carry the finite producer slice.
   Do not infer slice after parsing payload shape.

4. Update BridgeWeb telemetry call sites:

   - `rpc_send`: `plane=control`, `priority=warm`, `slice=review_rpc`
   - `content_fetch`: `plane=data`, `priority=hot`, `slice=content_fetch`
   - `package_apply`: `plane` and `priority` from explicit producer-slice
     mapping; `slice` from the push envelope
   - `first_render`: `plane=data`, `priority=hot`, `slice` from the first
     accepted diff/review envelope that produced rendered content
   - `telemetry_drop`: `plane=observability`, `priority=best_effort`,
     `slice=telemetry_drop`

5. Align BridgeWeb drop reason string values with the Swift wire enum.

6. Remove `agentstudio.bridge.lane` from new BridgeWeb telemetry samples.

Proof:

```bash
mise run bridge-web-check
mise run bridge-web-test
git diff --check
```

Expected: exit 0.

## Task 4: OTLP Projection And Metrics Safety

**Files:**

- Modify: `Sources/AgentStudio/Infrastructure/Diagnostics/AgentStudioOTLPTraceProjection.swift`
- Modify: `Sources/AgentStudio/Infrastructure/Diagnostics/AgentStudioOTLPPerformanceMetrics.swift`
- Tests:
  - `Tests/AgentStudioTests/Infrastructure/Diagnostics/AgentStudioOTLPTraceProjectionTests.swift`
  - `Tests/AgentStudioTests/Infrastructure/Diagnostics/AgentStudioOTLPPerformanceMetricsTests.swift`
  - `Tests/AgentStudioTests/Infrastructure/Diagnostics/AgentStudioOTLPBootstrapSmokeTests.swift`

Steps:

1. Add failing projection tests proving allowed attributes survive:

   ```text
   agentstudio.bridge.plane
   agentstudio.bridge.priority
   agentstudio.bridge.slice
   ```

2. Add failing negative tests proving unsafe values are dropped:

   ```text
   plane=review-<uuid>
   priority=/Users/example
   slice=diffFiles:<itemId>
   tab_id
   session_id
   operation_id
   request_id
   handle_id
   pane_id
   prompt_id
   __pushId
   command_id
   package_id
   checkpoint_id
   content_hash
   dynamic_entity_key
   path
   prompt
   text
   output
   error
   ```

3. Add metric projection tests proving finite labels become bounded dimensions
   for:

   ```text
   agentstudio.bridge.plane
   agentstudio.bridge.priority
   agentstudio.bridge.slice
   ```

   The metrics layer must still reject dynamic or unsafe values. Do not add a
   generic `agentstudio.bridge.*` string-label passthrough.

4. Implement the allowlist. Do not make all `agentstudio.bridge.*` string
   attributes legal.

5. Update bootstrap smoke tests so seeded Bridge telemetry uses
   `plane`/`priority`/`slice`, not `agentstudio.bridge.lane`.

Proof:

```bash
mise run test -- --filter AgentStudioOTLPTraceProjectionTests
mise run test -- --filter AgentStudioOTLPPerformanceMetricsTests
mise run test -- --filter AgentStudioOTLPBootstrapSmokeTests
git diff --check
```

Expected: exit 0.

## Task 5: Verifier And Proof Ledger

**Files:**

- Modify: `scripts/verify-bridge-observability.sh`
- Modify: `scripts/run-debug-observability.sh`
- Modify: `Tests/AgentStudioTests/Scripts/BridgeObservabilityVerifierScriptTests.swift`
- Modify: `docs/wip/bridge-observability/2026-06-14-bridge-observability-proof.md`

Steps:

1. Add failing-first script tests for query fragments and state-file behavior.
   The tests should fail before the verifier reads the scenario from the debug
   state file and before concrete slice queries exist.

2. Persist the selected Bridge observability scenario in the debug
   observability state file, then teach `verify-bridge-observability.sh` to read
   it. The verifier should remain marker-scoped and scenario-scoped.

3. Update positive Victoria queries to require:

   ```text
   plane=data
   plane=control
   plane=observability
   priority=best_effort for telemetry events
   concrete slice values on package_push
   ```

   Prefer at least two known slices in the smoke fixture. If a fixture really
   only emits one slice, record that explicitly in the proof doc and keep the
   script test pinned to the known single slice.

4. Update VictoriaMetrics queries to prove bounded `plane`, `priority`, and
   `slice` dimensions on Bridge performance metrics. The verifier should not
   claim metric grouping from logs/traces alone.

5. Update negative queries for:

   ```text
   agentstudio.bridge.lane on new Bridge OTLP records
   invalid plane/priority/slice canaries
   raw IDs and path/text/error fields from every disallowed class in the
   design spec
   telemetry self-RPC logs/spans
   ```

6. Update script tests to assert the new query fragments.

7. Run fresh Victoria proof through the existing debug runner. Use a new marker.

Proof:

```bash
mise run observability:status
mise run observability:smoke
AGENTSTUDIO_TRACE_TAGS=app.startup,terminal.startup,runtime,surface,persistence.recovery,bridge.performance.* \
AGENTSTUDIO_TRACE_BACKEND=both \
AGENTSTUDIO_TRACE_NAME=bridge-plane-$(date +%s) \
AGENTSTUDIO_STARTUP_DIAGNOSTIC_ACTION=bridge-review-observability-smoke \
AGENTSTUDIO_BRIDGE_OBSERVABILITY_SCENARIO=package_apply_content_fetch_v1 \
mise run run-debug-observability -- --detach
mise run verify-bridge-observability
mise run test -- --filter BridgeObservabilityVerifierScriptTests
git diff --check
```

Expected: exit 0. Proof doc records marker, counts, trace count, and
plane/priority/slice query evidence.

## Task 6: Direct Browser OTLP Absence Proof

**Files:**

- Modify tests if an existing script-test owner exists for static scans.
- Otherwise add a small assertion to
  `Tests/AgentStudioTests/Scripts/BridgeObservabilityVerifierScriptTests.swift`
  or a nearby script test.
- Create if useful: `scripts/verify-bridge-web-no-direct-otlp.sh`

Steps:

1. Add an executable static-scan helper that scans source, dependencies, and
   generated app assets:

   ```bash
   rg -n "@opentelemetry|otlp|OTLP|collector|v1/traces|v1/logs|v1/metrics" \
     BridgeWeb/package.json BridgeWeb/pnpm-lock.yaml BridgeWeb/src \
     Sources/AgentStudio/Resources/BridgeWeb/app
   ```

2. The helper must exit non-zero on any shipped asset, BridgeWeb source, or
   dependency-manifest hit that implies direct browser OTLP. Accept
   documentation-only hits outside shipped app assets only through an explicit
   allowlist in the helper or test.

3. Add a script test that proves a seeded bad OTLP string would fail the helper.
   Do not rely on `rg ... || true` as a proof gate.

Proof:

```bash
mise run bridge-web-build
mise run test -- --filter BridgeObservabilityVerifierScriptTests
bash scripts/verify-bridge-web-no-direct-otlp.sh
git diff --check
```

Expected: no shipped asset/dependency hits for direct browser OTLP.

## Task 7: Final Validation And Review

Steps:

1. Run collector-free validation:

   ```bash
   mise run bridge-web-build
   mise run bridge-web-check
   mise run bridge-web-test
   mise run test -- --filter BridgeTelemetry
   mise run test -- --filter BridgeTelemetryIngestorTests
   mise run test -- --filter BridgePaneControllerTelemetryTests
   mise run test -- --filter RPCRouterTelemetryTests
   mise run test -- --filter AgentStudioOTLP
   mise run test -- --filter BridgeObservabilityVerifierScriptTests
   bash scripts/verify-bridge-web-no-direct-otlp.sh
   ! rg -n "agentstudio\\.bridge\\.lane" \
     Sources/AgentStudio/Features/Bridge \
     Sources/AgentStudio/Infrastructure/Diagnostics \
     BridgeWeb/src \
     Sources/AgentStudio/Resources/BridgeWeb/app \
     Tests/AgentStudioTests/Features/Bridge \
     Tests/AgentStudioTests/Infrastructure/Diagnostics \
     scripts/verify-bridge-observability.sh
   mise run lint
   git diff --check
   ```

   Expected for the stale-label grep: no runtime, test, script, source, or
   generated asset hits. Historical docs may still mention `lane`.

2. Run collector-backed validation from Task 5.

3. Use `shravan-dev-workflow:implementation-review-swarm`.

4. Address accepted findings with failing proof first.

5. Commit and push only after checks and review fixes are complete.

Known guard:

- `mise run test-webkit` may still expose the unrelated signal 11 / broken-pipe
  harness issue after Bridge-owned assertions pass. Do not edit unrelated
  WebKit infrastructure without re-scoping.

## Rollback And Recovery

- This is a hard telemetry taxonomy cutover. Do not support both exported
  `lane` and exported `priority` for Bridge OTLP events.
- If Victoria dashboards still need the old label during transition, update the
  dashboard query or proof doc. Do not preserve old exported labels in code.
- If push-slice attribution cannot be made exact in this PR, stop and split a
  smaller push-transport taxonomy plan. Do not ship `unknown` or invented
  dynamic slices for `package_push` / `package_apply` when the producer has a
  known slice.
- If the verifier fails only because the shared Victoria stack is down, report
  that as an observability environment blocker and keep collector-free proof
  separate.

## Fixed Decisions

- `agentstudio.bridge.lane` is removed from all new Bridge telemetry records,
  including JSONL and BridgeWeb-originated samples.
- `agentstudio.bridge.slice` is carried exactly from producer-owned push slices
  through native push transport and BridgeWeb envelopes.
- `agentstudio.bridge.plane`, `agentstudio.bridge.priority`, and
  `agentstudio.bridge.slice` become bounded metrics dimensions for Bridge
  performance metrics.
- Existing trace tag scopes remain unchanged:
  `bridge.performance.swift`, `bridge.performance.web`, and
  `bridge.performance.webkit`.

## Recommended Next Step

Execute this plan task-by-task with `shravan-dev-workflow:implementation-execute-plan`
or the active orchestrator goal. After implementation, run
`shravan-dev-workflow:implementation-review-swarm` before PR wrap-up.
