# Bridge Observability Plane Taxonomy Proof

Date: 2026-06-15

Branch: `luna-337-bridge-review-foundation-next`

Working tree base: `00602511`

## Purpose

This ledger records current proof for the Bridge observability-plane taxonomy
cutover. It is a proof artifact, not the design source. The design source is
`docs/superpowers/specs/2026-06-15-bridge-observability-plane-design.md`; the
execution plan is
`docs/superpowers/plans/2026-06-15-bridge-observability-plane-implementation.md`.

The cutover changes Bridge telemetry from the historical product `lane`
attribute to finite `plane`, `priority`, and `slice` attributes:

- `plane=data|control|observability`
- `priority=hot|warm|cold|best_effort`
- finite Bridge slice values such as `diff_package_metadata`,
  `content_fetch`, `review_rpc`, `telemetry_batch`, `telemetry_ingest`, and
  `telemetry_drop`

## Static And Unit Proof

Command:

```bash
mise run lint
```

Result: exit 0. `swift-format` passed, SwiftLint reported 0 violations across
1154 files, Core boundary imports passed, and release script checks passed.

Command:

```bash
git diff --check
```

Result: exit 0.

Command:

```bash
rg -n "agentstudio\\.bridge\\.lane|\\blane:" Sources/AgentStudio/Features/Bridge BridgeWeb/src -g '*.swift' -g '*.ts' -g '*.tsx'
```

Result: exit 0 before implementation review, with only negative BridgeWeb test
assertions referencing `agentstudio.bridge.lane`. After implementation review,
the stricter command below was run and returned no matches:

```bash
rg -n "agentstudio\\.bridge\\.lane" Sources/AgentStudio BridgeWeb/src Tests/AgentStudioTests scripts/verify-bridge-observability.sh -g '*.swift' -g '*.ts' -g '*.tsx' -g '*.sh'
```

Production Bridge source, tests, and verifier scripts no longer contain the
literal historical Bridge lane key.

## Swift Test Proof

Command:

```bash
mise run test -- --filter SliceTests
```

Result: exit 0. 13 tests in 2 suites passed.

Command:

```bash
mise run test -- --filter BridgeBootstrapTests
```

Result: exit 0. 14 tests in 1 suite passed, including coverage that
`BridgeBootstrap.applyEnvelope` preserves the finite `slice` field when
relaying Swift pushes into page-world `__bridge_push` events.

Command:

```bash
mise run test -- --filter BridgeTelemetry
```

Result: exit 0. 19 tests in 5 suites passed, including historical lane
rejection, event-specific auxiliary-attribute rejection, required
taxonomy-field validation, browser content-fetch attributes, telemetry
self-RPC absence, and release-style telemetry policy disabling.

Post-review rerun result: exit 0. 20 tests in 5 suites passed.

Command:

```bash
mise run test -- --filter RPCRouterTelemetry
```

Result: exit 0. 1 test passed, covering oversized telemetry-batch drop
accounting.

Command:

```bash
mise run test -- --filter AgentStudioOTLP
```

Result: exit 0. 16 tests in 4 suites passed, including projection, complete
Bridge taxonomy requirements for metric export, metrics, sink behavior, and
loopback OTLP smoke.

Command:

```bash
mise run test -- --filter BridgePaneControllerTests
```

Result: exit 0. 26 tests in 2 suites passed, including WebKit-serialized Bridge
controller tests, `pushJSON` failure, and dedup behavior.

Command:

```bash
mise run test -- --filter BridgePaneControllerTelemetryTests
```

Result: exit 0. 2 tests in 2 suites passed, including correlated Swift review
telemetry and release-style telemetry disablement.

Command:

```bash
mise run test -- --filter RPCRouter
```

Result: exit 0. 36 tests in 2 suites passed, including telemetry self-RPC
non-observation and oversize telemetry rejection.

Command:

```bash
mise run test -- --filter Push
```

Result: exit 0. 34 tests in 8 suites passed, including push pipeline
integration and push performance benchmark suites.

Post-review rerun result: exit 0. 35 tests in 9 suites passed.

Command:

```bash
mise run test -- --filter BridgeSchemeHandlerTests
```

Result: exit 0. 37 tests in 1 suite passed, including content-route telemetry
for traceparent-correlated and summary-only content fetches.

Command:

```bash
mise run test -- --filter BridgePerformanceTraceRecorder
```

Result: exit 0. 3 tests in 1 suite passed, including best-effort observability
drop summaries.

Command:

```bash
mise run test -- --filter Bridge
```

Result: exit 1. This broad substring filter ran many non-Bridge-slice suites
such as `WorkspaceSQLiteStoreBridge*`, keyboard bridge tests, command-bar bridge
tests, and WebKit tests, then exited with signal 11 after many passing tests.
This is not used as changed-surface proof for the taxonomy cutover; targeted
Bridge telemetry/controller/router/push/scheme gates above passed.

Command:

```bash
mise run test
```

Result: exit 1. The default parallel Swift test phase progressed through the
suite and the serialized WebKit phase then hit the known infrastructure failure
outside this slice: `BridgeContentWorldIsolationTests` reports its single test
passed, then the harness exits with unexpected signal code 5 and
`scripts/swift-test-helpers.sh` reports `echo: write error: Broken pipe`.
This is not fixed in this observability taxonomy slice.

## BridgeWeb Proof

Command:

```bash
mise run bridge-web-check
```

Result: exit 0. Fixtures were in sync; `oxlint --type-aware`, `oxfmt --check`,
and `tsc --noEmit` passed.

Command:

```bash
mise run bridge-web-test
```

Result: exit 0. 19 test files and 57 tests passed.

Post-review rerun result: exit 0. 19 test files and 61 tests passed.

Command:

```bash
mise run bridge-web-test -- bridge-app.integration.test.tsx bridge-push-envelope.unit.test.ts
```

Result: exit 0. 2 test files and 12 tests passed, covering package-scoped
trace correlation after a later hot `diff_status` push and runtime-aligned
push envelope fixture taxonomy.

Post-review targeted command:

```bash
mise run bridge-web-test -- bridge-app.integration.test.tsx bridge-rpc-client.unit.test.ts content-resource-loader.integration.test.ts
```

Result: exit 0. 3 test files and 19 tests passed, covering telemetry
failure-isolation for RPC and content fetch, accepted-delta trace-parent
refresh, and connection-push apply telemetry classification as control plane.

Command:

```bash
mise run bridge-web-build
```

Result: exit 0. Vite built the bundled app resource:
`Sources/AgentStudio/Resources/BridgeWeb/app/assets/index-BQYB5Ll6.js`.

Command:

```bash
bash scripts/verify-bridge-web-no-direct-otlp.sh
```

Result: exit 0. Source, package metadata, lockfile, and generated BridgeWeb app
assets contain no direct browser OTLP exporter hooks or loopback OTLP endpoint
strings.

The scanner now always includes the default BridgeWeb source/package/generated
asset roots and treats `BRIDGE_WEB_OTLP_SCAN_TARGETS` as additive rather than a
replacement. These commands both passed:

```bash
bash scripts/verify-bridge-web-no-direct-otlp.sh
BRIDGE_WEB_OTLP_SCAN_TARGETS=/dev/null bash scripts/verify-bridge-web-no-direct-otlp.sh
```

Swift script tests cover default-root scanning, additive env targets, safe grep
argument separation, and a throwaway bad target containing
`@opentelemetry/exporter-trace-otlp-http` that proves the scanner fails.

## Shared Observability Stack Proof

Command:

```bash
mise run observability:status
```

Result: exit 0. The shared collector, VictoriaLogs, VictoriaMetrics, and
VictoriaTraces containers were up; all Victoria services were healthy.

Command:

```bash
mise run observability:smoke
```

Result: exit 0.

Smoke marker:

```text
ai-tools-smoke-1781529592-92708
```

The shared-stack smoke verified logs, metrics, traces, and sensitive-canary
scrubbing across all three Victoria lanes.

## Live Debug Proof

Command:

```bash
AGENTSTUDIO_STARTUP_DIAGNOSTIC_ACTION=bridge-review-observability-smoke \
  mise run run-debug-observability -- --detach
```

Result: exit 0.

Output:

```text
[swift-build-slot] using .build-agent-1
marker: debug-observability-oq4s-1781530440-94440
pid: 3347
launch method: launchservices
log: /Users/shravansunder/.agentstudio-db/oq4s/logs/debug-observability-oq4s-1781530440-94440.log
observability state: /Users/shravansunder/Documents/dev/project-dev/agent-studio.bridge-start/tmp/debug-observability/latest-observability.env
```

State file:

```text
AGENTSTUDIO_OBSERVABILITY_STATUS=running
AGENTSTUDIO_OBSERVABILITY_MARKER=debug-observability-oq4s-1781530440-94440
AGENTSTUDIO_OBSERVABILITY_RUNTIME_FLAVOR=debug
AGENTSTUDIO_OBSERVABILITY_DEBUG_CODE=oq4s
AGENTSTUDIO_OBSERVABILITY_PID=3347
AGENTSTUDIO_OBSERVABILITY_STARTUP_DIAGNOSTIC_ACTION=bridge-review-observability-smoke
AGENTSTUDIO_OBSERVABILITY_DATA_DIR=/Users/shravansunder/.agentstudio-db/oq4s
AGENTSTUDIO_OBSERVABILITY_ZMX_DIR=/Users/shravansunder/.agentstudio-db/oq4s/z
```

Before the successful launch, the previous run was blocked by an older debug
process:

```text
11057     1 11:41:20 /Users/shravansunder/.agentstudio-db/oq4s/apps/app-20260614213830-4909/AgentStudio Debug oq4s.app/Contents/MacOS/AgentStudio
```

The user authorized quitting that process. After it exited, a first fresh launch
without `AGENTSTUDIO_STARTUP_DIAGNOSTIC_ACTION` correctly failed the Bridge
verifier startup-action guard. The app was relaunched with the required startup
diagnostic action above.

Command:

```bash
mise run verify-bridge-observability
```

Result: exit 0.

Output:

```text
bridge observability ok:
marker=debug-observability-oq4s-1781530440-94440
scenario=package_apply_content_fetch_v1
logs=17 metrics=12 traces=3
telemetry_self_rpc=absent
```

The verifier initially exposed a real contract mismatch: Swift
`performance.bridge.swift.content_load` emits `phase=success` on successful
content loads, while web `performance.bridge.web.content_fetch` emits
`phase=fetch`. The verifier and `BridgeObservabilityVerifierScriptTests` now
match that runtime contract.

## Review Status

Implementation review packet:
`tmp/implementation-review-swarms/2026-06-15-bridge-observability-plane-taxonomy/review-packet.md`.

Implementation review findings were accepted where they were material to this
goal and addressed in code:

- `BridgeBootstrap` now preserves `slice` across the Swift-to-page push relay.
- BridgeWeb follow-on content/RPC telemetry now uses the current package's
  trace parent instead of a global last-diff-push parent.
- Browser telemetry validation is event-specific rather than globally allowing
  every safe auxiliary key on every event.
- Bridge metrics require complete finite `phase`, `plane`, `priority`, and
  `slice` taxonomy and include `phase` as a metric dimension.
- The Victoria verifier now requires hot, warm, and cold package push/apply
  slices and rejects broad unlabeled `package_push` fallback series.
- Push contract fixtures now match the live runtime shape: `diff_status` is
  hot replace and `diff_package_delta` is warm merge.
- Producer-owned Swift push slices now require explicit
  `BridgeTelemetrySlice` values instead of deriving a fallback `.unknown`.
- Direct-browser-OTLP scanning cannot be bypassed with
  `BRIDGE_WEB_OTLP_SCAN_TARGETS=/dev/null`.
- Accepted `diff_package_delta` pushes refresh BridgeWeb's current package
  telemetry parent for follow-on browser samples.
- The Victoria verifier checks `content_load` with `transport=content`,
  matching the implemented source route.
- The Victoria verifier checks Swift `content_load` with `phase=success`,
  matching the scheme-handler success/error outcome contract.
- Browser-side connection-health push apply telemetry is recorded as
  control-plane telemetry.
- The historical `agentstudio.bridge.lane` field is no longer present as a
  literal in Bridge Swift, BridgeWeb, tests, or the Victoria verifier.

Live marker proof is complete for this branch.
