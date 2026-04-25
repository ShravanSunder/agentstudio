# LUNA-368 Tagged JSONL Tracer Design Spec

**Status:** Draft design spec. Do not execute until reviewed.

**Linear:** [LUNA-368](https://linear.app/askluna/issue/LUNA-368/debugging-harness-tagged-jsonl-tracer-debug-overlays-headless)

**Sibling:** [LUNA-370](https://linear.app/askluna/issue/LUNA-370/drag-testing-harness-headless-layers-ad-pure-mock-hidden) owns headless drag test layers. This spec owns in-app diagnostics and local trace capture.

## Purpose

Build one opt-in diagnostic harness for app investigations:

- Tagged JSONL trace capture.
- OTel trace model, JSONL sink first.
- Per-run files.
- Ring buffer with explicit flush.
- Sampling/throttling for high-volume streams.
- Payload-by-correlation for heavy debug data.
- Drag destination overlay and record-experiment ergonomics.
- Shell tooling for triage.

This spec intentionally does not implement LUNA-361 notification behavior. LUNA-361 consumes this tracer in a separate spec.

## Stopping Point 1

LUNA-368 is complete when a developer can launch the app with trace tags, reproduce a drag/runtime/focus issue, flush a bounded JSONL trace, visually inspect registered drag destinations, and run shell triage against the trace.

This stopping point is infrastructure-only.

## Terminology

Use OTel terms wherever they fit.

```
trace
  One diagnostic flow. Prefer trace_id per user flow.

session
  One app recording session/run. Stored as session_id.

span
  One bounded operation in the flow.

span event
  Timestamped fact inside an operation.

trace tag
  User-selectable category for enabling/filtering diagnostics.

attributes
  Structured key/value facts.
```

Domain correlation IDs remain explicit attributes:

```
pane.id
tab.id
window.id
command.id
envelope.seq
surface.id
drag.session_id
```

## Trace Tags

Start with the LUNA-368 ticket tags. Add more only when a real investigation needs them.

```
drag
  Destination register/enter/update/exit/performDrop plus source init/onAppear.

atoms
  State mutations with before/after summaries. Requires payload-by-correlation first.

eventbus
  Envelope post/deliver, subscriber counts, drops, stream finish.

actions
  PaneActionCommand resolve -> validate -> dispatch -> result.

runtime
  Session lifecycle, health checks, zmx connect/reconnect, runtime envelope emission.

surface
  Ghostty surface create/destroy/crash, view lifecycle, action callback routing.

restore
  Existing RestoreTrace content migrated under this tag.
```

Reserved later tags:

```
app.focus
inbox
ui.surface
terminal.activity
drawer
style
```

These are consumer tags. They should not block the LUNA-368 tracer foundation.

## Environment

```
AGENTSTUDIO_TRACE_TAGS=drag,eventbus,runtime
AGENTSTUDIO_TRACE_NAME=drawer-target-smoke
AGENTSTUDIO_TRACE_DIR=/tmp
```

Selectors:

```
AGENTSTUDIO_TRACE_TAGS=drag
AGENTSTUDIO_TRACE_TAGS=runtime,eventbus
AGENTSTUDIO_TRACE_TAGS=surface.*
AGENTSTUDIO_TRACE_TAGS=*
AGENTSTUDIO_TRACE_TAGS=off
```

Output:

```
/tmp/agentstudio-<trace-name>-<pid>.jsonl
```

## OTel-Aligned Record Shape

This is an app-local JSONL sink using OTel trace concepts. It is not an OTLP exporter yet.

```json
{
  "time_unix_nano": 1777134723123000000,
  "severity_text": "INFO",
  "body": "eventbus.post",
  "trace_id": "01JSP7V3Q6DJT4R5J3BMK6Y2QE",
  "span_id": "01JSP7V3Q6A1B2C3D4E5F6G7H8",
  "parent_span_id": "01JSP7V3Q66RUNTIME00000001",
  "resource": {
    "service.name": "AgentStudio",
    "process.pid": 12345
  },
  "scope": {
    "name": "agentstudio.eventbus",
    "version": "1"
  },
  "attributes": {
    "agentstudio.trace.name": "drawer-target-smoke",
    "agentstudio.trace.tag": "eventbus",
    "agentstudio.session.id": "01JSP7V3Q6SESSION",
    "event.name": "eventbus.post",
    "envelope.seq": 441
  }
}
```

Rules:

- Prefer `trace_id` per flow.
- Include `agentstudio.session.id` for the app run.
- Use `parent_span_id` only when propagation is explicit and trustworthy.
- Namespace custom fields with `agentstudio.*` unless they are established semantic attributes.
- Do not log raw command output by default.

## Propagation Model

Swift actor hops make implicit propagation risky. The first version uses explicit context.

```
TraceContext
  traceId
  spanId
  parentSpanId
  sessionId
```

Rules:

- App/user ingress creates a `TraceContext`.
- Runtime/eventbus paths pass context explicitly where available.
- If no context exists, the tracer may create an orphan span with `agentstudio.trace.orphan=true`.
- Do not rely on TaskLocal until a focused design proves behavior across `@MainActor`, `Task`, actor hops, and `@concurrent nonisolated`.

## Ownership And Concurrency

`Tracer` lives in `Infrastructure/Diagnostics`.

Design:

```
Tracer
  Static facade with cheap disabled checks.

TraceSink
  Protocol for JSONL, ring buffer, future OTLP, and multiplex sinks.

TraceWriter
  Actor owning mutable buffers and file I/O.
```

Blocking file writes must not run on `@MainActor`. Flush uses a writer actor or `@concurrent nonisolated` helper.

Disabled behavior must avoid allocation-heavy payload construction. Prefer autoclosure payload builders.

## Sink Strategy

```
JSONLTraceSink
  First implementation. Persistent local debugging and fixture capture.

RingBufferTraceSink
  Default when enabled but not flushed. Bounded memory.

MultiplexTraceSink
  Later: JSONL + OTLP simultaneously.

OTLPTraceSink
  Later: collector export through open-telemetry/opentelemetry-swift.
```

Do not use `swift-otel` for this harness unless the app later standardizes on Swift's native `swift-log` / `swift-distributed-tracing` stack.

## Sampling And Throttling

Required for `drag`.

API shape:

```swift
Tracer.throttled(
    .drag,
    key: dragSessionId,
    every: 25
) {
    TraceEvent(...)
}
```

Behavior:

- Emit the first event for a key.
- Emit every Nth event.
- Emit the final event when a session ends.
- Record `sample_rate` and `dropped_count`.

Acceptance:

- A drag session with 200+ updates produces a compact but useful trace.
- Dropped counts are visible.

## Payload-By-Correlation

Heavy data should be dumped once and referenced later.

Examples:

- Pasteboard type lists.
- View ancestry.
- Atom before/after payloads.
- Drag target rect collections.

Record shape:

```json
{
  "body": "payload.dump",
  "attributes": {
    "payload.ref": "drag-session-abc:view-tree",
    "payload.kind": "view-tree",
    "drag.session_id": "abc"
  }
}
```

Later records use:

```json
{
  "body": "drag.resolveTarget",
  "attributes": {
    "payload.ref": "drag-session-abc:view-tree"
  }
}
```

Payload retention follows the trace file lifecycle.

## Drag Overlay

The drag overlay is part of LUNA-368, not a follow-up.

UI:

```
Debug -> Show Drag Destinations
Shortcut: Option-Command-D
```

Behavior:

- Draw every `NSView` registered for drag types.
- Label owner tag, bounds, and accepted pasteboard types.
- Highlight the active destination during a drag.
- Include session ID in overlay labels when recording.

Acceptance:

- During a drawer drag, the overlay makes it obvious which view owns the active destination.
- The overlay can be toggled without restarting the app.

## Record Experiment

UI:

```
Debug -> Record Experiment
```

Behavior:

- Prompts for or derives `AGENTSTUDIO_TRACE_NAME`.
- Enables selected tags for the next interaction session.
- Flushes JSONL and payload dumps at session end.
- Optionally captures a view-tree snapshot.

Acceptance:

- A single run produces a ready-for-tracker JSONL file.

## Shell Tools

Minimum scripts:

```
scripts/drag-session <sessionID>
scripts/drag-diff <traceA> <traceB>
scripts/drag-repro <sessionID>
```

Acceptance:

- `drag-session` prints destination timeline, target distribution, pasteboard types, and drop result.
- `drag-diff` compares two traces side by side.
- `drag-repro` emits a test stub or fixture seed from captured positions.

## Implementation Tasks

### Task A: Tracer API And Schema

- [ ] Define `TraceTag`.
- [ ] Define `TraceContext`.
- [ ] Define `TraceRecord`.
- [ ] Define `TraceSink`.
- [ ] Define disabled fast path.
- [ ] Define env parsing and wildcard matching.

### Task B: JSONL + Ring Buffer

- [ ] Implement JSONL sink.
- [ ] Implement ring buffer sink.
- [ ] Implement flush.
- [ ] Add per-run file naming.
- [ ] Add tests for disabled/enabled behavior.

### Task C: Sampling And Payload References

- [ ] Implement `throttled`.
- [ ] Implement payload dump/reference API.
- [ ] Add tests for dropped counts and final-event emission.

### Task D: Restore And Core Tags

- [ ] Migrate `RestoreTrace` to `restore`.
- [ ] Add `eventbus` post/deliver summary tracing.
- [ ] Add initial `runtime` envelope emission tracing.
- [ ] Add `actions` validation/dispatch tracing.

### Task E: Drag Integration

- [ ] Add `drag` destination/source trace events.
- [ ] Add drag destination overlay.
- [ ] Add record-experiment menu path.
- [ ] Add shell scripts.

## Non-Goals

- Full OpenTelemetry collector export in the first implementation.
- Metrics.
- Always-on production tracing.
- LUNA-361 notification behavior.
- LUNA-370 headless test layers.

## Open Questions

1. Which flows get explicit `trace_id` creation first: drag sessions, command dispatch, runtime envelopes, or focus changes?
2. Should `eventbus.deliver` default to one summary record, with per-subscriber delivery under `eventbus.verbose`?
3. What are the first allowed heavy payload kinds?
4. Should `Record Experiment` write into `/tmp` only, or under an app diagnostics folder?
5. What UI shape should the debug menu take in release builds: hidden, disabled, or absent?

