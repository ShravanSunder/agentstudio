# Bridge Observability Plane Design

> Status: design source for the follow-up Bridge telemetry taxonomy cutover.
> Created: 2026-06-15
> Builds on: [Bridge Debug Telemetry Observability Spec](2026-06-14-bridge-debug-telemetry-observability.md)
> Implementation plan: [Bridge Observability Plane Implementation Plan](../plans/2026-06-15-bridge-observability-plane-implementation.md)

## Purpose

The first Bridge observability slice proved logs, metrics, and traces across
Swift pushes, BridgeWeb RPC, and content fetches. It also exposed a vocabulary
problem: telemetry is currently described using product push concepts such as
`lane = hot | warm | cold`.

That vocabulary makes dashboards and optimization decisions ambiguous. A
`cold` product push can be real review data; a telemetry batch is diagnostic
and may be dropped without product impact. They should not share the same
semantic axis.

This spec defines a hard separation between Bridge product traffic and Bridge
observability traffic.

## Current Evidence

Bridge product pushes are observation-driven. After `bridge.ready`,
`BridgePaneController` starts push plans for:

- `diff`
- `review`
- `connection`
- `agent`

`PushLevel` currently defines product cadence:

```text
hot   immediate
warm  12 ms debounce
cold  32 ms debounce
```

Those values are transport/product priority, not diagnostics priority.

The current telemetry validator accepts browser-originated `.web` samples and
allowlisted attributes. The allowlist currently includes
`agentstudio.bridge.lane = hot | warm | cold`, so browser telemetry and native
telemetry can describe diagnostic work with product cadence terms.

The proof ledger recorded:

```text
performance.bridge.webkit.package_push     954.525 ms over 44 pushes
performance.bridge.webkit.telemetry_batch  127.797 ms over 9 telemetry batches
```

`performance.bridge.webkit.package_push` measures all WebKit push transport
work through `BridgePaneController.pushJSON(...)`, not only review package
payloads. That event needs a finite push-slice attribute before it can support
package-specific optimization.

## Design Decision

Bridge telemetry must use three independent concepts:

```text
plane
  what kind of system behavior this event describes

priority
  how important this event is to product correctness or responsiveness

slice
  the finite Bridge subsystem or product slice that produced the event
```

`hot`, `warm`, and `cold` remain product/data/control priorities. They are
semantic labels about user-visible correctness and responsiveness. They are not
aliases for `PushLevel` debounce cadence, even when the current implementation
uses similar names. Telemetry is not a cold product lane. It is an
observability plane with best-effort priority.

## Plane Vocabulary

Use this closed enum:

```text
agentstudio.bridge.plane = data | control | observability
```

Meanings:

```text
data
  Review packages, deltas, file descriptors, content handles, and content
  fetches. Losing data-plane traffic can break the review surface.

control
  Bridge readiness, typed RPC commands, command acknowledgements, selection,
  mark-file-viewed, navigation commands, and other operational control.
  Losing control-plane traffic can break interaction correctness.

observability
  Telemetry transport, telemetry ingestion, drop summaries, proof markers, and
  diagnostic accounting. Losing observability-plane traffic must not break
  Bridge product behavior.
```

`system.bridgeTelemetry` is observability ingress over the existing RPC carrier.
It is not a product command and is not part of the generic RPC telemetry stream.

## Priority Vocabulary

Use this closed enum:

```text
agentstudio.bridge.priority = hot | warm | cold | best_effort
```

Rules:

- Product `data` and `control` events may use `hot`, `warm`, or `cold`.
- `observability` events must use `best_effort`.
- Do not export OS task priority, queue internals, raw caller strings, or
  user-facing urgency text as priority.
- Do not use `best_effort` for product traffic unless a later design explicitly
  defines a non-diagnostic background product lane.

`PushLevel` can continue to exist in product push code. Telemetry code must not
derive semantic priority directly from `PushLevel`. Product push telemetry must
use an explicit event-owned mapping from the finite slice to semantic priority,
so future debounce tuning cannot silently rewrite historical priority meaning.

## Slice Vocabulary

Use finite, compile-time values. Initial values:

```text
agentstudio.bridge.slice =
  diff_status |
  diff_package_metadata |
  diff_package_delta |
  diff_files |
  review_threads |
  review_viewed_files |
  connection_health |
  command_acks |
  review_rpc |
  content_fetch |
  telemetry_batch |
  telemetry_ingest |
  telemetry_drop |
  unknown
```

Rules:

- Do not derive slices from entity keys, file paths, UUIDs, item IDs, handle
  IDs, `__pushId`, command IDs, revisions, epochs, package IDs, checkpoint IDs,
  payload keys, or content hashes.
- Prefer `unknown` over exporting a dynamic value.
- Product push transport must set the slice from the known push slice name, not
  from payload data.
- Do not reconstruct slice from `StoreKey`, `PushOp`, payload shape, or
  BridgeWeb post-parse behavior when the producer had a more precise slice.
- Metrics may include `agentstudio.bridge.slice` only while this enum remains
  small and compile-time controlled.

## Attribute Schema

Required Bridge attributes:

```text
agentstudio.bridge.plane
agentstudio.bridge.transport
agentstudio.bridge.phase
```

Conditionally required:

```text
agentstudio.bridge.priority
  required for product data/control and observability accounting

agentstudio.bridge.slice
  required when the event belongs to a known Bridge slice or diagnostic bucket

agentstudio.bridge.rpc.method_class
  required for generic RPC telemetry; values remain review | telemetry | other
```

`agentstudio.bridge.lane` is historical vocabulary. New Bridge telemetry records
must not emit it to JSONL, web samples, validator tests, verifier scripts,
generated BridgeWeb assets, logs, metrics, or traces. Historical docs may still
mention it when describing the pre-cutover design.

## Event Classification

Initial classification:

```text
performance.bridge.swift.package_build
  plane=data
  priority=cold
  slice=diff_package_metadata
  transport=swift

performance.bridge.swift.delta_build
  plane=data
  priority=warm
  slice=diff_package_delta
  transport=swift

performance.bridge.swift.content_register
  plane=data
  priority=cold
  slice=diff_package_metadata
  transport=swift

performance.bridge.swift.content_load
  plane=data
  priority=hot
  slice=content_fetch
  transport=content

performance.bridge.webkit.package_push
  plane=data or control, depending on push slice
  priority=explicit semantic mapping from finite push slice
  slice=exact finite push slice from producer
  transport=push

performance.bridge.webkit.rpc_dispatch
  plane=control
  priority=warm
  slice=review_rpc
  transport=rpc

performance.bridge.webkit.rpc_response
  plane=control
  priority=warm
  slice=review_rpc
  transport=rpc

performance.bridge.web.package_apply
  plane=data
  priority=explicit semantic mapping from producer slice
  slice=exact finite push slice from push envelope
  transport=push

performance.bridge.web.rpc_send
  plane=control
  priority=warm
  slice=review_rpc
  transport=rpc

performance.bridge.web.content_fetch
  plane=data
  priority=hot
  slice=content_fetch
  transport=content

performance.bridge.web.first_render
  plane=data
  priority=hot
  slice=first accepted diff/review push slice that produced rendered content
  transport=push

performance.bridge.webkit.telemetry_batch
  plane=observability
  priority=best_effort
  slice=telemetry_batch
  transport=rpc

performance.bridge.swift.telemetry_ingest
  plane=observability
  priority=best_effort
  slice=telemetry_ingest
  transport=swift

performance.bridge.web.telemetry_drop
  plane=observability
  priority=best_effort
  slice=telemetry_drop
  transport=rpc
```

## Privacy And Cardinality Rules

The vocabulary is intentionally closed because Bridge telemetry crosses a trust
boundary and may become metric labels.

Allowed:

- closed enum strings from this spec
- bucketed numeric values
- boolean facts with allowlisted keys
- trace IDs only as trace/span fields

Disallowed:

- raw filesystem paths
- source or diff text
- selected text
- prompts
- model or tool output
- raw errors
- item IDs
- handle IDs
- pane IDs
- tab IDs
- session IDs
- prompt IDs
- operation IDs
- request IDs
- command IDs
- `__pushId`
- raw trace IDs as ordinary attributes
- content hashes
- package IDs
- checkpoint IDs
- dynamic push/entity keys

OpenTelemetry semantic convention guidance says span names should be
low-cardinality, and metric attributes that may have high cardinality should be
opt-in. This design follows that by keeping `plane`, `priority`, and `slice`
finite and allowlisted.

References:

- https://opentelemetry.io/docs/specs/semconv/how-to-write-conventions/
- https://opentelemetry.io/docs/specs/semconv/general/attribute-requirement-level/
- https://opentelemetry.io/docs/specs/otel/metrics/sdk/

## Trust Boundary

BridgeWeb remains an untrusted telemetry producer relative to OTLP export:

```text
BridgeWeb
  can emit .web summaries only
  cannot emit native .swift or .webkit samples
  cannot export OTLP directly

Swift Bridge telemetry validator
  validates schema, scope, event names, attributes, and limits
  rejects unsafe enum values
  records bounded drop reasons

Infrastructure diagnostics projection
  is the final OTLP allowlist
  drops unsafe identifiers, paths, payloads, errors, and text
```

Adding `plane`, `priority`, and `slice` requires updates at both validation
layers. Updating only Bridge validation would still hide fields at OTLP
projection time. Updating only OTLP projection would allow unsafe browser input
too far into the system.

## Drop Reason Compatibility

Drop reason vocabulary must be canonical across Swift and BridgeWeb. Current
Swift raw values are camelCase, while BridgeWeb emits `queue_saturated` for
buffer pressure. The implementation must pick one wire vocabulary and update
both sides in one cutover.

Preferred wire spelling:

```text
decoding_failed
disabled_scope
encoded_batch_too_large
invalid_duration
invalid_trace_context
queue_saturated
too_many_samples
unsafe_attribute
unsafe_event_name
unsupported_schema_version
```

Swift may map these to idiomatic enum cases internally, but the JSON/OTLP wire
values should be stable snake_case.

## Non-Goals

- No direct browser OTLP.
- No new Bridge atom, Core store, SQLite table, or persistence model.
- No product retry or backpressure behavior based on telemetry success.
- No new source/content payload export.
- No Pierre/Shiki/Trees placeholder telemetry.
- No optimization of `package_push` until the push slice is known.
- No long-term compatibility layer for both `lane` and `priority` in OTLP.
- No lossy `StoreKey`/`PushOp` reconstruction for push-slice telemetry when the
  producer can carry the exact slice.

## Validation Expectations

Collector-free proof:

- Swift validator accepts only allowed `plane`, `priority`, and `slice` values.
- Swift validator rejects invalid enum values and raw ID/path/text-like values.
- OTLP projection preserves allowed values and drops unsafe values.
- Metrics tests prove allowed finite labels survive as bounded dimensions and
  unsafe cardinality does not.
- BridgeWeb tests prove telemetry samples use observability-plane attributes for
  telemetry batches and drop summaries.
- Drop reason tests prove Swift and BridgeWeb use the same wire vocabulary.

Collector-backed proof:

- `mise run verify-bridge-observability` proves product data/control events and
  observability events are queryable separately.
- The verifier proves `performance.bridge.webkit.package_push` can be grouped
  by concrete finite `agentstudio.bridge.slice` values in logs, traces, and
  metrics.
- Negative queries prove forbidden IDs, paths, text, and invalid enum canaries
  do not survive in VictoriaLogs or VictoriaTraces.
- A direct-browser-OTLP scan proves packaged BridgeWeb assets do not contain
  browser OTLP exporters or collector endpoints.

## Fixed Decisions Before Implementation

- Remove `agentstudio.bridge.lane` from new Bridge telemetry records entirely,
  including JSONL and BridgeWeb-originated samples.
- Carry exact push slice through the push transport and BridgeWeb envelope
  instead of reconstructing it from store/op/payload data.
- Add bounded metrics dimensions for `plane`, `priority`, and `slice` rather
  than claiming slice grouping only from logs/traces.
- Keep existing trace tag scopes such as `bridge.performance.swift`,
  `bridge.performance.web`, and `bridge.performance.webkit`; this cutover
  changes event attributes, not the debug scope names.
