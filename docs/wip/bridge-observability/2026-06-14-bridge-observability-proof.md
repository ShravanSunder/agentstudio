# Bridge Observability Proof

Date: 2026-06-14

Branch: `luna-337-bridge-review-foundation-next`

Head: `3d07b483a3ec6232cbd8cdb57d5ff74dcd93dc3a`

## Purpose

This ledger records the current proof that Bridge debug observability is wired
through the shared Victoria stack for the pre-Pierre Bridge foundation. It is a
proof artifact, not a design source. The design source is
`docs/superpowers/specs/2026-06-14-bridge-debug-telemetry-observability.md`; the
execution plan is
`docs/superpowers/plans/2026-06-14-bridge-observability-implementation.md`.

The proof covers the three Bridge communication mechanisms:

- Swift to BridgeWeb package/delta push notifications
- BridgeWeb to Swift typed JSON-RPC
- BridgeWeb to Swift to BridgeWeb content fetch through
  `agentstudio://resource/content/...`

## Fresh Marker

State file:
`tmp/debug-observability/latest-observability.env`

```text
AGENTSTUDIO_OBSERVABILITY_STATUS=running
AGENTSTUDIO_OBSERVABILITY_MARKER=bridge-observability-1781487476
AGENTSTUDIO_OBSERVABILITY_RUNTIME_FLAVOR=debug
AGENTSTUDIO_OBSERVABILITY_DEBUG_CODE=oq4s
AGENTSTUDIO_OBSERVABILITY_LAUNCH_METHOD=launchservices
AGENTSTUDIO_OBSERVABILITY_QUERY_START=2026-06-15T01:38:31Z
AGENTSTUDIO_OBSERVABILITY_PID=11057
AGENTSTUDIO_OBSERVABILITY_APP=/Users/shravansunder/.agentstudio-db/oq4s/apps/app-20260614213830-4909/AgentStudio\ Debug\ oq4s.app
AGENTSTUDIO_OBSERVABILITY_STARTUP_DIAGNOSTIC_ACTION=bridge-review-observability-smoke
AGENTSTUDIO_OBSERVABILITY_BUILD_PATH=.build-agent-1
```

Proof scenario: `package_apply_content_fetch_v1`

Startup diagnostic action: `bridge-review-observability-smoke`

## Shared Stack

Command:

```bash
mise run observability:status
```

Result: exit 0. Collector, VictoriaMetrics, VictoriaLogs, and VictoriaTraces were
all running. VictoriaMetrics, VictoriaLogs, and VictoriaTraces reported healthy.

Command:

```bash
mise run observability:smoke
```

Result: exit 0.

Smoke marker:

```text
ai-tools-smoke-1781482051-71806
```

The shared-stack smoke verified logs, metrics, traces, and sensitive-canary
scrubbing across all three Victoria lanes.

## Debug App Proof

Command:

```bash
mise run verify-debug-observability
```

Result: exit 0.

Relevant output:

```text
debug observability ok:
{"_msg":"app.zmx_startup_reconciliation.completed","agentstudio.zmx.startup.inventory_outcome":"skipped","agentstudio.zmx.startup.live_session_count":"0","agentstudio.zmx.startup.hydrated_anchor_count":"0","agentstudio.zmx.startup.protected_session_count":"0","agentstudio.zmx.startup.unresolved_candidate_count":"0","agentstudio.zmx.startup.unmatched_live_session_count":"0"}
```

The debug verifier also checked the startup diagnostic render proof for
`bridge-review-observability-smoke`. The verifier now accepts both JSON boolean
`true` and string `"true"` because VictoriaLogs may serialize the field either
way.

## Bridge Verifier

Command:

```bash
mise run verify-bridge-observability
```

Result: exit 0.

Output:

```text
bridge observability ok:
marker=bridge-observability-1781487476
scenario=package_apply_content_fetch_v1
logs=13 metrics=6 traces=3
telemetry_self_rpc=absent
```

The verifier first delegates to `scripts/verify-debug-observability.sh`, then
requires marker- and scenario-scoped Bridge records in VictoriaLogs,
VictoriaMetrics, and VictoriaTraces. Positive log, metric, and trace checks use
bounded waits because VictoriaMetrics can lag the log lane by a few seconds
after a fresh debug launch.

Required VictoriaLogs event families verified:

```text
performance.bridge.swift.package_build
performance.bridge.swift.delta_build
performance.bridge.swift.content_register
performance.bridge.swift.content_load
performance.bridge.swift.telemetry_ingest
performance.bridge.webkit.package_push
performance.bridge.webkit.rpc_dispatch
performance.bridge.webkit.rpc_response
performance.bridge.webkit.telemetry_batch
performance.bridge.web.package_apply
performance.bridge.web.rpc_send
performance.bridge.web.content_fetch
performance.bridge.web.first_render
```

Required VictoriaMetrics counters verified:

```text
performance.bridge.swift.package_build
performance.bridge.swift.content_load
performance.bridge.webkit.package_push
performance.bridge.web.package_apply
performance.bridge.web.content_fetch
performance.bridge.web.first_render
```

Required VictoriaTraces spans verified:

```text
package_build span: marker + scenario + phase=package_build + transport=swift
content fetch span: marker + scenario + phase=fetch + transport=content
review RPC dispatch span: marker + scenario + phase=dispatch + transport=rpc + method_class=review
```

Negative privacy and recursion queries verified:

```text
agentstudio.bridge.item_id does not survive in Bridge OTLP logs
system.bridgeTelemetry self-RPC records do not survive in Bridge OTLP logs
system.bridgeTelemetry self-RPC spans do not survive in VictoriaTraces
```

## Victoria Counts

Marker: `bridge-observability-1781487476`

Scenario: `package_apply_content_fetch_v1`

Event counts from VictoriaLogs:

```text
performance.bridge.swift.content_load=1
performance.bridge.swift.content_register=1
performance.bridge.swift.delta_build=1
performance.bridge.swift.package_build=1
performance.bridge.swift.telemetry_ingest=9
performance.bridge.web.content_fetch=1
performance.bridge.web.first_render=1
performance.bridge.web.package_apply=9
performance.bridge.web.rpc_send=1
performance.bridge.webkit.package_push=44
performance.bridge.webkit.rpc_dispatch=1
performance.bridge.webkit.rpc_response=1
performance.bridge.webkit.telemetry_batch=9
```

Counter values from VictoriaMetrics:

```text
performance.bridge.swift.content_load=1
performance.bridge.swift.content_register=1
performance.bridge.swift.delta_build=1
performance.bridge.swift.package_build=1
performance.bridge.swift.telemetry_ingest=9
performance.bridge.web.content_fetch=1
performance.bridge.web.first_render=1
performance.bridge.web.package_apply=9
performance.bridge.web.rpc_send=1
performance.bridge.webkit.package_push=44
performance.bridge.webkit.rpc_dispatch=1
performance.bridge.webkit.rpc_response=1
performance.bridge.webkit.telemetry_batch=9
```

## Performance Observation

Top elapsed Bridge metrics for the proof marker:

```text
954.525ms performance.bridge.webkit.package_push
127.797ms performance.bridge.webkit.telemetry_batch
68.000ms performance.bridge.web.content_fetch
60.305ms performance.bridge.swift.package_build
12.096ms performance.bridge.webkit.rpc_response
7.343ms performance.bridge.swift.content_register
7.337ms performance.bridge.swift.delta_build
0.148ms performance.bridge.swift.content_load
```

The data-backed fix made during this proof cycle was reliability-oriented:
BridgeWeb RPC send and content fetch events were recorded locally but did not
flush consistently at boundary crossings. The implementation now flushes after
non-telemetry RPC send records and content fetch records, which made
`performance.bridge.web.rpc_send` and `performance.bridge.web.content_fetch`
appear in Victoria for the marker-scoped proof.

The measured optimization made in this slice uses the already-negotiated
`minimumFlushIntervalMilliseconds` BridgeWeb telemetry config. Burst push
flushes are throttled, while RPC and content-fetch boundary events force
delivery. The same smoke scenario still proves `rpc_send` and `content_fetch`,
and `performance.bridge.webkit.telemetry_batch` dropped from 14 in the
pre-optimization marker to 9 in the current stricter proof marker, which now
also includes `web.first_render` and `swift.telemetry_ingest`.

The remaining measured optimization candidate is Bridge WebKit push transport:
the marker recorded 44 `performance.bridge.webkit.package_push` counter
increments and 954.525ms aggregate elapsed time across those pushes. This event
currently aggregates Bridge push transport across review/package/delta and other
push slices; it is not yet a precise "review package only" hotspot. The next
performance slice should add a low-cardinality push-slice discriminator before
changing push coalescing or payload behavior.

## Review-Swarm Fixes Captured In This Marker

- Browser-originated telemetry batches accept only `.web` samples.
  Native `.swift` and `.webkit` events are emitted by Swift/WebKit code only.
- Release-style Bridge telemetry composition disables the recorder, ingestor,
  and `system.bridgeTelemetry` method even when test injections are present.
- BridgeWeb keeps review RPC/content fetch trace parents tied to the latest
  review/diff push, so later connection pushes do not steal the parent context.
- Oversized telemetry batches reach the router-level semantic guard, which can
  record a bounded drop event before rejecting the command.
- Non-forced BridgeWeb flush failures are retried immediately instead of being
  throttled by a failed attempt.
- RPC telemetry uses the controlled attribute
  `agentstudio.bridge.rpc.method_class=review|other|telemetry`, allowing the
  verifier to prove review RPC traces while excluding telemetry self-RPC.

## Known Proof Boundary

Content fetch uses summary correlation by default. Direct `traceparent` custom
header proof for `agentstudio://resource/content/...` is guarded behind
`AGENT_STUDIO_WEBKIT_TRACEPARENT_FETCH_PROOF=on` because the headless WebKit
custom-scheme header assertion can crash outside this slice. The default proof
still verifies the content fetch event family, content fetch metric, and content
fetch span through Swift-side correlation.

## Validation Ledger

Fresh gates on the current tree:

```text
git diff --check: exit 0
bash -n scripts/verify-bridge-observability.sh scripts/verify-debug-observability.sh: exit 0
mise run lint: exit 0, swift-format OK, swiftlint 0 violations, boundary checks passed
mise run verify-bridge-observability: exit 0, logs=13 metrics=6 traces=3, telemetry_self_rpc=absent
```

Earlier collector-free gates from this slice:

```text
mise run bridge-web-check: exit 0
mise run bridge-web-test: exit 0, 19 files / 54 tests
mise run bridge-web-build: exit 0
mise run test -- --filter BridgeTelemetryBatchValidatorTests: exit 0, 8 tests
mise run test -- --filter BridgeTelemetry: exit 0, 11 tests / 4 suites
mise run test -- --filter BridgePaneControllerTelemetryTests: exit 0, 2 tests / 2 suites
mise run test -- --filter BridgeObservabilityVerifierScriptTests: exit 0, 1 test
mise run test -- --filter RPCRouter: exit 0, 36 tests / 2 suites
mise run test -- --filter AgentStudioOTLP: exit 0, 14 tests / 4 suites
```

Known unrelated higher-layer blocker:

```text
mise run test-webkit currently fails outside this slice after
BridgeContentWorldIsolationTests reports pass, then the harness exits with
signal 11 / broken pipe. This proof did not edit that infrastructure layer.
```
