# Bridge Debug Telemetry Observability Spec

> Status: design source for Bridge telemetry implementation. Active execution
> plan:
> [Bridge Observability Implementation Plan](../plans/2026-06-14-bridge-observability-implementation.md).
> Created: 2026-06-14
> Depends on: [Bridge Review Foundation Spec](2026-06-10-bridge-review-foundation.md)
> Depends on: [AgentStudio OTLP Shared Observability Design](2026-06-11-agentstudio-otlp-shared-observability-design.md)
> Architecture companions: [Bridge Viewer Architecture](../../architecture/bridge_viewer_architecture.md) and [Bridge Native Runtime Architecture](../../architecture/bridge_native_runtime_architecture.md)

This spec defines how Bridge performance and lifecycle telemetry should work for
the pre-Pierre Bridge foundation and the future Pierre/Shiki/Trees viewer. It
captures the required architecture, boundaries, activation model, folder
ownership, privacy rules, and proof expectations. The implementation plan linked
above maps these requirements to code and proof gates.

## Purpose

Bridge will become a high-throughput review surface:

- Swift builds review packages, deltas, content handles, and resource responses.
- WebKit moves small state and metadata between Swift and BridgeWeb.
- BridgeWeb hydrates content on demand.
- Future Pierre/Shiki/Trees work will virtualize, highlight, and navigate large
  file and diff regions.

We need observability for that pipeline before the viewer becomes complex. The
goal is to answer questions such as:

- how long package building takes
- whether content handle fetches are slow or stale
- whether BridgeWeb first render is dominated by package apply, content fetch,
  worker preparation, or viewer reconciliation
- whether the hot, warm, and cold Bridge communication lanes are competing with
  each other
- whether future Pierre/Shiki worker work is bounded and off the UI thread
- whether a test or performance fixture regressed

The telemetry layer must not become part of the hot Bridge data path. It must
not mutate source files, add Bridge persistence, create a new atom, or bypass
the existing AgentStudio OTLP safety model.

## Product Boundary

Bridge telemetry is debug instrumentation for engineering and performance
proof. It is not product analytics.

In scope:

- debug-only Bridge performance events and summaries
- debug-only BridgeWeb timing summaries sent through Swift
- Swift-side OTLP export through the existing AgentStudio diagnostics runtime
- JSONL forensic output when the trace runtime is configured for it
- collector-backed Victoria proof in explicit observability/performance gates
- future Pierre/Shiki/Trees scope names reserved for the viewer milestone

Out of scope:

- stable-release Bridge telemetry by default
- beta-release Bridge telemetry by default
- direct browser OTLP from packaged `agentstudio://app/*` BridgeWeb assets
- source text, prompts, terminal output, tool output, or raw paths in OTLP
- telemetry as a new Bridge atom, Core store, or SQLite-backed state model
- per-scroll, per-line, per-item, per-frame, or per-selection telemetry in the
  shipped debug path

## Current-State Constraints

The existing diagnostics runtime already provides the right export shape:

- `AgentStudioTraceRuntime.record(...)` is the central trace emission point.
- `AgentStudioTraceEventQueue` drains trace work through a detached worker.
- `AgentStudioPerformanceTraceRecorder` records `performance.*` events only
  when the `.performance` tag is enabled.
- `AgentStudioOTLPTraceProjection` is an explicit OTLP allowlist and drops raw
  identifiers, paths, payload-like fields, and error-like fields.
- `AgentStudioOTLPPerformanceMetrics` derives metrics from projected
  `performance.*` records.

Bridge also has a strict trust and data-flow model:

- BridgeWeb may fetch only Swift-issued content handle URLs.
- `agentstudio://app/*` serves immutable packaged BridgeWeb assets and worker
  chunks.
- `agentstudio://resource/content/{handleId}?generation={reviewGeneration}`
  serves review-package-scoped content bytes.
- Review packages and deltas are metadata-first; file bytes move through lazy
  content fetches.
- WebKit, SwiftUI, AppKit, atoms, observable UI state, and pane lifecycle are
  MainActor boundaries.
- endpoint comparison, checkpoint collation, content hashing, content loading,
  package building, delta building, and large JSON/data preparation belong
  off-main.

Bridge telemetry must extend those boundaries instead of inventing a side
channel around them.

## Core Decision

Default design:

```text
Swift Bridge work
  -> BridgePerformanceTraceRecorder
  -> AgentStudioTraceRuntime
  -> JSONL / OTLP projection
  -> shared loopback collector
  -> Victoria stack

BridgeWeb / future Pierre / future workers
  -> local BridgeWeb telemetry recorder
  -> bounded interaction summaries
  -> debug-only WebKit telemetry batch
  -> Swift BridgeTelemetryIngestor actor
  -> BridgePerformanceTraceRecorder
  -> AgentStudioTraceRuntime
  -> JSONL / OTLP projection
  -> shared loopback collector
  -> Victoria stack
```

Direct browser OTLP is not part of the packaged product surface. If it is ever
needed for a local experiment, it must live outside shipped BridgeWeb assets,
pin to loopback, stay default-off, and use the same safe low-cardinality schema.
That experiment must not be a fallback path for normal Bridge telemetry.

The same trace context must be able to connect all three Bridge communication
mechanisms:

```text
Swift -> BridgeWeb
  push state/package/delta notifications

BridgeWeb -> Swift
  typed JS bridge commands/RPC

BridgeWeb -> Swift -> BridgeWeb
  fetch content through agentstudio://resource/content/...
```

That context is for trace/span linkage and debug proof. It is not a metric label
and it is not a product identifier.

### Why Not Browser Direct By Default

Direct browser OTLP has attractive properties: it can use standard
OpenTelemetry JS exporters, it sees browser timings close to the source, and it
does not require Swift to translate frontend summaries.

It pays costs that are wrong for Bridge:

- CORS and custom-origin friction from `agentstudio://app/*` to loopback
  collector endpoints.
- exporter and batching overhead inside the WebView process.
- a second trust boundary that bypasses Swift's OTLP projection allowlist.
- easy accidental export of paths, item IDs, handle IDs, pane IDs, prompt IDs,
  raw errors, or source-adjacent metadata.
- harder correlation with Swift package/content timings.

BridgeWeb should measure locally and send bounded summaries to Swift. Swift is
the only default OTLP producer for Bridge.

## Activation Model

Bridge telemetry is explicit opt-in and debug-only.

Required gates:

```text
compile gate
  DEBUG build only for active Bridge telemetry sinks

runtime gate
  explicit trace tag or proof-runner environment selection

scope gate
  only enabled Bridge scopes record or batch work

sink gate
  missing collector remains fail-open for app launch
```

Do not widen the zero-config debug baseline just to make Bridge data visible.
Debug and beta builds currently have conservative safe defaults in the generic
diagnostics runtime; Bridge performance telemetry is not part of that safe
baseline. A developer or proof runner should opt in with tags such as:

```text
AGENTSTUDIO_TRACE_TAGS=bridge.performance.swift,bridge.performance.web
AGENTSTUDIO_TRACE_TAGS=bridge.performance.*
```

`AGENTSTUDIO_TRACE_TAGS=off` must disable Bridge telemetry even in debug
builds.

Release builds may keep inert type definitions and no-op composition points, but
they must not instantiate active Bridge telemetry sinks, allocate telemetry
batches, register debug telemetry RPC methods, or perform measurement work.

Bridge performance tags are not part of the safe debug/beta baseline. The
ordinary safe baseline may continue to emit startup/runtime/surface diagnostics,
but Bridge telemetry needs an explicit Bridge performance selection in the
runtime configuration or an explicit Bridge proof scenario.

## Scope Vocabulary

Use trace tags as OpenTelemetry instrumentation scopes. The trace runtime turns
tags into scope names such as `agentstudio.<tag>`, and its selector parser
supports prefix selectors for enum cases that exist.

Initial Bridge tags:

```text
bridge.performance.swift
bridge.performance.web
bridge.performance.webkit
```

Reserved downstream tags, added only when the real viewer path exists:

```text
bridge.performance.pierre
bridge.performance.shiki
bridge.performance.worker
bridge.performance.trees
```

Do not add one trace tag per operation. Tags select lanes. Event names and
controlled attributes describe operations.

Metric/log body names should continue to start with `performance.` so the
existing performance-metric projection model can recognize them:

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
performance.bridge.web.telemetry_drop
```

Future viewer events:

```text
performance.bridge.pierre.item_update
performance.bridge.pierre.virtualized_range
performance.bridge.shiki.highlight
performance.bridge.worker.task
performance.bridge.trees.filter
```

Those future event names are reserved for the Pierre/Shiki/Trees milestone. The
pre-Pierre foundation should not emit placeholder Pierre measurements.

## BridgeWeb Telemetry Transport Contract

BridgeWeb sends debug telemetry summaries to Swift through one method:

```text
system.bridgeTelemetry
```

This method is debug-only and registered only when Bridge telemetry is active.
Release-style composition must not expose it. The method is a raw bounded sink,
not an ordinary typed RPC method that decodes params on the WebKit/MainActor
lane.

Required JSON-RPC envelope shape:

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

`__traceContext` is transport metadata and must not be placed inside method
params. `system.bridgeTelemetry` itself must be excluded from generic RPC
send/dispatch/response telemetry so it does not measure its own telemetry lane.

BridgeWeb activation config is delivered through the replayable
`__bridge_handshake` detail as optional `telemetryConfig`. If config is absent
or disabled, BridgeWeb composes a null recorder. The config must include:

```text
enabled
scopes
maxSamplesPerBatch
maxEncodedBatchBytes
maxPendingBatchesPerPane
minimumFlushIntervalMilliseconds
methodName = system.bridgeTelemetry
scenario = package_apply_content_fetch_v1
```

The browser-exposed scope set must be narrower than the native active scope set.
BridgeWeb may emit only browser-owned `.web` samples. Swift and WebKit events
are generated on the native side and must not be accepted from
`system.bridgeTelemetry` batches, even when the corresponding native trace tags
are enabled.

Generic RPC telemetry must use a low-cardinality method class instead of raw
method names:

```text
agentstudio.bridge.rpc.method_class = review | telemetry | other
```

`system.bridgeTelemetry` is classified only for negative verifier queries; the
generic RPC send/dispatch/response instrumentation must still exclude that
method so telemetry does not recursively measure its own transport.

The initial Victoria-backed proof scenario is:

```text
agentstudio.bridge.test.scenario = package_apply_content_fetch_v1
AGENTSTUDIO_STARTUP_DIAGNOSTIC_ACTION = bridge-review-observability-smoke
```

The scenario must be deterministic and in-memory: it opens the Bridge review
pane, pushes a Bridge review package, sends one normal review RPC, and fetches
content through `agentstudio://resource/content/...` without reading user
repositories, Git state, SQLite, or raw source paths.

## Trace Correlation Model

Bridge telemetry needs real trace linkage, not just shared event names.

Every user-visible Bridge review interaction should have one root trace context.
Examples:

- open review pane
- load or refresh a review package
- select a file
- fetch visible content
- apply a filter
- future Pierre visible-range render

The trace context must be safe to propagate across WebKit and URL-scheme
boundaries:

```text
BridgeTraceContext
  traceId       W3C/OpenTelemetry trace id
  spanId        current operation span id
  parentSpanId  optional parent operation span id
  sampled       debug/proof selection flag
```

Rules:

- `traceId`, `spanId`, and `parentSpanId` are trace fields, not metric labels.
- Do not copy raw trace IDs into ordinary OTLP attributes.
- Do not use pane IDs, item IDs, handle IDs, package IDs, prompt IDs, or command
  IDs as trace IDs.
- Do not expose trace context in user-visible UI.
- Do not require trace context for correctness. Missing or malformed trace
  context drops the correlation only; the Bridge operation still runs.

### Swift Push Correlation

Swift-originated package and delta pushes should create or continue a Bridge
interaction trace:

```text
BridgeReviewPipeline package build
  span: performance.bridge.swift.package_build
  -> Bridge push enqueue / dispatch
     span: performance.bridge.webkit.package_push
  -> BridgeWeb push receive / package apply
     span: performance.bridge.web.package_apply
```

Push envelopes may carry a compact debug trace context in transport metadata
when Bridge telemetry is enabled. That metadata must stay outside review
package data and must be ignored by normal review-state reducers.

`__pushId` remains a transport de-dup/freshness aid. It is not a trace id and
must not be promoted to OTLP labels.

### Typed JS RPC Correlation

BridgeWeb-originated commands should create or continue a Bridge interaction
trace:

```text
BridgeWeb user action
  span: performance.bridge.web.rpc_send
  -> WebKit message handler / RPCRouter dispatch
     span: performance.bridge.webkit.rpc_dispatch
  -> typed method handler
     span: performance.bridge.swift.<operation>
  -> response / command ack
     span: performance.bridge.webkit.rpc_response
```

The trace context belongs in transport metadata such as `__traceContext`, not in
method params. Typed RPC method handlers should receive already-decoded safe
context through Bridge runtime infrastructure when they need to emit child
events.

`__commandId` remains a de-dup and acknowledgement key. It is not a trace id and
must not be promoted to OTLP labels.

BridgeWeb does not yet own a response-consumer lane for `__bridge_response` or
agent command-ack pushes. A future bidirectional-response milestone may add a
`performance.bridge.web.rpc_ack` event there, but it is not part of the current
Bridge observability proof.

### Content Fetch Correlation

Content fetches are pull-based resource requests:

```text
BridgeWeb content loader
  span: performance.bridge.web.content_fetch
  -> fetch(agentstudio://resource/content/{handleId}?generation=...)
     trace context header when supported
  -> BridgeSchemeHandler / BridgeContentStore load
     span: performance.bridge.swift.content_load
  -> response bytes back to BridgeWeb
```

Preferred propagation is W3C `traceparent` on the debug-only fetch request,
because it does not alter the content handle URL and does not make trace
identity part of resource addressing.

The implementation plan must verify whether `WKURLSchemeHandler` receives custom
headers for `agentstudio://resource/content` fetches. The default implementation
uses summary correlation for content fetch proof; a separate guarded WebKit
assertion may enable the direct-header proof when
`AGENT_STUDIO_WEBKIT_TRACEPARENT_FETCH_PROOF=on`. If WebKit strips those headers
or the headless WebKit harness is unstable for that assertion, the fallback is:

- BridgeWeb records the frontend content-fetch span in its local telemetry
  batch.
- Swift records the scheme-handler content-load span with the same safe phase
  and bucket attributes.
- The proof report marks the fetch as summary-correlated, not parent-span
  correlated, until a safe propagation path is proven.

Do not add trace identity to the content URL query string unless a later spec
explicitly accepts that tradeoff.

### Logs, Metrics, And Traces

The same Bridge event may produce:

- an OTLP log record with event name, scope, safe phase/outcome attributes, and
  trace context
- an OTLP metric sample derived from `performance.*` events and safe buckets
- a trace span when the operation has a real lifecycle boundary

Logs and spans may carry trace/span fields. Metrics must keep only stable,
low-cardinality labels and bucketed values.

The implementation must not claim end-to-end trace proof until the exported
records preserve enough trace/span linkage to query one Bridge interaction
across Swift push, typed RPC, and content fetch mechanisms in Victoria.

## Safe Attribute Schema

Bridge OTLP attributes must be low-cardinality and allowlisted. The
implementation plan must update `AgentStudioOTLPTraceProjection` tests before
expecting these fields to appear in OTLP.

Allowed string attributes:

```text
agentstudio.bridge.phase
agentstudio.bridge.operation
agentstudio.bridge.outcome
agentstudio.bridge.source
agentstudio.bridge.transport
agentstudio.bridge.lane
agentstudio.bridge.file_class
agentstudio.bridge.content_role
agentstudio.bridge.cache_result
agentstudio.bridge.generation_relation
agentstudio.bridge.telemetry.drop_reason
agentstudio.bridge.test.scenario
```

Allowed numeric attributes:

```text
agentstudio.performance.elapsed_ms
agentstudio.bridge.package.file_count_bucket
agentstudio.bridge.package.group_count_bucket
agentstudio.bridge.package.visible_item_count_bucket
agentstudio.bridge.content.byte_size_bucket
agentstudio.bridge.content.line_count_bucket
agentstudio.bridge.telemetry.event_count
agentstudio.bridge.telemetry.dropped_count
agentstudio.bridge.telemetry.batch_byte_count
agentstudio.bridge.transport.payload_byte_count_bucket
agentstudio.bridge.transport.queue_depth_bucket
```

Allowed boolean attributes:

```text
agentstudio.bridge.cache_hit
agentstudio.bridge.is_binary
agentstudio.bridge.is_stale
```

Disallowed in OTLP:

```text
raw filesystem paths
source text or diff text
selected text
prompt text
model output
tool output
raw errors
itemId
handleId
paneId
tabId
sessionId
promptId
operationId
requestId
raw correlationId as an attribute or metric label
raw causationId as an attribute or metric label
raw content hash
raw package id
raw checkpoint id
```

If JSONL needs richer local-only fields for a specific debugging session, those
fields must remain out of the OTLP projection unless a later spec explicitly
approves them.

## Folder Ownership

Swift ownership:

```text
Sources/AgentStudio/Infrastructure/Diagnostics/
  generic trace runtime
  generic JSONL and OTLP sinks
  generic OTLP projection allowlist
  generic performance metric projection
  no Bridge package/content/checkpoint knowledge

Sources/AgentStudio/Features/Bridge/Models/Telemetry/
  BridgeTelemetryBatch
  BridgeTelemetrySample
  BridgeTelemetryScope
  BridgeTelemetryDropReason
  BridgeTelemetrySinkState
  Sendable DTOs only
  Codable contract fixtures when crossing WebKit

Sources/AgentStudio/Features/Bridge/Runtime/Telemetry/
  BridgePerformanceTraceRecorder
  BridgeTelemetryIngestor actor
  BridgeTelemetryBatchValidator
  BridgeTelemetryScopeGate
  BridgeTelemetryAggregator
  off-main validation, bucketing, drop accounting, and trace forwarding

Sources/AgentStudio/Features/Bridge/Transport/
  typed debug telemetry bridge method
  decode and route only
  no aggregation, bucketing, or OTLP logic

Sources/AgentStudio/Features/Bridge/Runtime/
  BridgePaneController routes ready-gated telemetry batches
  BridgePaneController does not own telemetry schemas or aggregation logic
```

Do not place Bridge telemetry state in Core atoms, persistence wrappers, SQLite
repositories, or shared UI components. If telemetry needs cross-pane aggregation,
use a Bridge runtime actor/service and safe summaries, not app state.

BridgeWeb ownership:

```text
BridgeWeb/src/foundation/telemetry/
  bridge-telemetry-event.ts
  bridge-telemetry-scope.ts
  bridge-telemetry-buffer.ts
  bridge-telemetry-recorder.ts
  bridge-telemetry-sink.ts
  pure TypeScript, no DOM/WebKit coupling

BridgeWeb/src/bridge/
  bridge-telemetry-event-sink.ts
  concrete CustomEvent/WebKit relay sink
  ready-gated and nonce-aware where the bridge already requires it

BridgeWeb/src/app/
  bridge-telemetry-composition.ts
  app-level debug telemetry wiring and null-recorder selection

BridgeWeb/src/review-viewer/
  viewer-local instrumentation adapters when a real viewer exists

BridgeWeb/src/review-viewer/pierre/
  future Pierre-specific timing adapter after Pierre is integrated

BridgeWeb/src/review-viewer/workers/
  future worker timing helpers after worker code exists
```

Do not add generic `types.ts`, `utils.ts`, `store.ts`, `protocol.ts`, or
`helpers.ts`. Tests must follow the existing BridgeWeb naming policy:
`*.unit.test.ts`, `*.integration.test.ts`, or `*.e2e.test.ts` and their TSX
equivalents.

## Runtime Flow

### Swift-Side Operation

```text
BridgeReviewQuery
  -> BridgeReviewPipeline actor/service
  -> BridgePerformanceTraceRecorder.measure(...)
  -> BridgeReviewPackage / BridgeReviewDelta
  -> MainActor BridgePaneController publishes metadata to WebKit
```

The trace recorder must be cheap when disabled. It should mirror the existing
performance recorder pattern: check enabled state first, then allocate
attributes, measure, enqueue, and flush asynchronously.

### Frontend Operation

```text
BridgeWeb receives package
  -> local recorder records package apply duration
  -> content loader records content fetch duration
  -> shell records first meaningful render
  -> local buffer aggregates interaction summary
  -> low-priority batch to Swift after interaction settles
```

Default frontend telemetry is summary-oriented. It must not drain per scroll,
line, render frame, selection, or individual item update.

### Swift Ingest From BridgeWeb

```text
WebKit message handler / bridge method
  -> MainActor decode envelope and capture Data/value
  -> BridgeTelemetryIngestor actor validates and buckets
  -> BridgePerformanceTraceRecorder records safe summaries
  -> AgentStudioTraceRuntime exports through configured sinks
```

MainActor work is limited to WebKit receipt and routing. Validation, bucketing,
drop accounting, and trace forwarding are off-main.

Clock domains stay separate:

- Swift durations use Swift clocks.
- BridgeWeb durations use browser `performance.now()` deltas.
- The system never subtracts JS timestamps from Swift timestamps.

### Communication Lanes

Bridge traffic should be measured by lane so performance work can separate hot
review operations from cold diagnostic work:

```text
hot
  package/delta pushes that unblock visible review
  visible content-handle fetches
  visible package apply and first render

warm
  user-triggered typed RPC
  select file
  filter tree
  refresh query
  annotation anchor selection

cold
  telemetry batches
  diagnostic summaries
  background prefetch
  checkpoint summaries
  non-visible enrichment
```

Telemetry itself belongs to the cold lane. It must not block hot push, content,
or first-render work.

## Batching And Backpressure

Bridge telemetry must be bounded at every hop.

Required limits:

- max frontend samples per batch: 64
- max encoded batch byte size: 16 KiB
- max pending batches per pane: 2
- max Swift ingest queue depth: 8
- minimum flush interval: 250 ms
- maximum drop-summary interval: 1000 ms
- explicit drop reason when a limit is hit

Flush triggers:

- bridge ready
- interaction settled
- package apply complete
- first meaningful render complete
- content fetch batch complete
- pane teardown
- explicit performance proof checkpoint

Default path should emit one bounded summary per meaningful interaction phase,
not one event per hot UI operation.

Drop accounting is telemetry too, but it must be summarized:

```text
performance.bridge.web.telemetry_drop
  agentstudio.bridge.telemetry.drop_reason = buffer_full | disabled | oversized | not_ready | invalid_scope
  agentstudio.bridge.telemetry.dropped_count = bucketed count
```

## Test Telemetry Enclosure

Normal unit and integration tests must not require a running collector or
Victoria stack.

Collector-free tests should cover:

- Swift DTO encoding/decoding
- Swift telemetry batch validation
- safe attribute bucketing
- OTLP projection allowlist for Bridge attributes
- disabled-path behavior
- BridgeWeb telemetry buffer limits
- BridgeWeb scope gating
- browser-originated `.swift` and `.webkit` sample rejection
- BridgeWeb sink serialization
- app composition selecting a null recorder when telemetry is disabled
- release-style composition rejecting `system.bridgeTelemetry`

Collector-backed tests belong in an explicit observability/performance proof
lane. They should use the existing shared observability flow:

```text
mise run observability:up
mise run run-debug-observability -- --detach
mise run verify-debug-observability
```

Bridge-specific collector proof uses `mise run verify-bridge-observability`.
It must still use the same debug app identity and shared collector contract.

Test telemetry must be enclosed with a trace name and controlled scenario:

```text
AGENTSTUDIO_TRACE_NAME=bridge-telemetry-<run-id>
agentstudio.bridge.test.scenario = package_apply_large_fixture
```

Do not treat JSONL fallback as Victoria proof. Report collector/Victoria proof
as a separate layer from collector-free unit and integration proof.

## Performance Rules

Disabled path:

- no batch construction
- no attributes dictionary construction
- no JSON serialization
- no WebKit telemetry message
- no OTLP exporter work
- one cheap scope/tag guard before returning

Enabled default path:

- aggregate before crossing WebKit
- emit controlled summaries
- keep payloads small
- avoid telemetry work during scroll/render hot loops
- use idle/settled flush points where practical
- fail open and drop boundedly under pressure

Deep trace path:

- must be explicit and separate from benchmark baselines
- may perturb performance
- may sample more frequently, but still must not export unsafe fields
- must be documented as diagnostic, not normal proof

## Security And Privacy

Swift remains the default OTLP exporter because it owns the source-side
projection allowlist and local endpoint validation.

Bridge telemetry must preserve the Bridge trust model:

- BridgeWeb still fetches only Swift-issued content handle URLs.
- `agentstudio://app/*` assets do not ship a default direct OTLP exporter.
- telemetry batches are typed, size-bounded, ready-gated, and decoded by Swift.
- telemetry method names are allowlisted and separate from review queries.
- invalid, oversized, stale, or disabled telemetry batches are dropped safely.

OTLP output must never contain raw source, raw paths, prompts, model/tool
payloads, arbitrary errors, or high-cardinality IDs.

## Implementation Plan Requirements

The implementation plan must be a hard-cutover plan for telemetry, not a
parallel diagnostics system.

It must include:

- exact Swift files to add or change
- exact BridgeWeb files to add or change
- exact trace tag enum cases
- exact OTLP projection allowlist changes
- exact bridge method name and contract fixture: `system.bridgeTelemetry`
- exact trace context propagation shape for push, typed RPC, and content fetch
- proof of whether `WKURLSchemeHandler` receives debug `traceparent` headers
- red/green Swift Testing tests
- red/green Vitest tests
- collector-free proof gates
- explicit observability proof gate when Victoria output is part of the claim
- launch/proof commands that use the existing debug observability runner

It must not include:

- a new Bridge atom
- a new persistence store
- direct browser OTLP in packaged BridgeWeb assets
- a generic TS telemetry store
- placeholder Pierre telemetry before the real viewer integration exists
- unrelated SQLite, Git backend, or app-wide diagnostics refactors

## Proof Gates For This Spec

This file is design-only. The proof gate for the spec change is:

```text
git diff --check
```

The implementation plan that follows must define the code proof pyramid. At a
minimum it should include:

```text
mise run bridge-web-check
mise run bridge-web-test
mise run test-fast -- --filter BridgeTelemetry
mise run test-fast -- --filter BridgeContentStoreTests
mise run test-webkit
mise run lint
```

When the implementation claims Victoria/OTLP proof, it must also include the
shared observability runner and the Bridge-specific verifier or query. The
minimum proof is the required Bridge event inventory, metrics, Swift package
span, content-fetch span, review RPC span, privacy canary, and telemetry
self-RPC negative query.

## Resolved Implementation Decisions

- Bridge owns a feature-local recorder that depends on diagnostics protocols
  rather than making BridgeWeb or Bridge runtime import OTLP.
- The debug telemetry bridge method is exactly `system.bridgeTelemetry`.
- The first implementation includes Swift package/content telemetry and the
  BridgeWeb summary buffer in the same PR because correlation across all three
  transport mechanisms is the point of this slice.
- The first Victoria-backed proof scenario is
  `package_apply_content_fetch_v1`, driven by
  `bridge-review-observability-smoke`.
- Browser-originated telemetry is `.web` only; `.swift` and `.webkit` are
  native-owned scopes.
- Review RPC trace proof uses
  `agentstudio.bridge.rpc.method_class=review`, and the verifier rejects
  telemetry self-RPC logs/spans.

## Follow-Up Questions Outside This Spec

- Which Pierre/Shiki/Trees spans should be added once those systems exist?
- Which Bridge review workload should become the long-running benchmark after
  the first deterministic proof scenario is stable?
