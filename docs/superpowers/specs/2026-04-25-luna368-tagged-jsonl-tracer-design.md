# LUNA-368 Tagged JSONL Tracer Design Spec

**Status:** Draft design spec. Do not execute until reviewed.

**Linear:** [LUNA-368](https://linear.app/askluna/issue/LUNA-368/debugging-harness-tagged-jsonl-tracer-debug-overlays-headless)

**Sibling:** [LUNA-370](https://linear.app/askluna/issue/LUNA-370/drag-testing-harness-headless-layers-ad-pure-mock-hidden) owns headless drag test layers. This spec owns in-app diagnostics and local trace capture.

## Purpose

Build one opt-in diagnostic harness for app investigations:

- Tagged JSONL trace capture.
- Swift tracing libraries own span/context semantics.
- Agent Studio JSONL file exporter first, OTLP file/network exporters later.
- Per-run files.
- Ring buffer with explicit flush.
- Sampling/throttling for high-volume streams.
- Payload-by-correlation for heavy debug data.
- Drag destination overlay and record-experiment ergonomics.
- Shell tooling for triage.

This spec intentionally does not implement LUNA-361 notification behavior. LUNA-361 consumes this tracer in a separate spec.

## Stopping Points

### SP1a: No-Regret Foundation

LUNA-368 reaches its first useful stopping point when a developer can launch the app with drag tracing enabled, reproduce a drag issue, see the destination overlay, flush a bounded JSONL trace, and run one shell triage command against the trace.

SP1a includes:

- `swift-distributed-tracing` adopted for tracing/span/context APIs.
- `swift-otel` adopted as the standard OTLP backend path, with local collector export allowed to stay disabled by default.
- Stable Agent Studio JSONL exporter schema: top-level keys, `agentstudio.*` namespace, resource fields, `time_unix_nano`, and trace/span/log-like event vocabulary.
- Propagation pattern established through one end-to-end drag flow.
- Local JSONL file exporter, ring buffer, explicit flush, rotation, env-var control, and per-run files.
- One span/record proof on disk with trace ID, span ID, resource, scope, and attributes.
- Drag scope live with end-to-end trace evidence.
- Drag destination overlay.
- `scripts/drag-session` as the first shell triage tool.

SP1a does not require direct OpenTelemetry Collector ingestion and does not write OTLP JSON. It preserves the OTel-shaped internal vocabulary so an OTLP file exporter or OTLP network exporter can be added later as another sink without redesigning the tracing model.

### SP1b And Follow-Ups

These slide after SP1a without architectural regret:

- `eventbus`, `atoms`, `actions`, `surface`, and `restore` scopes.
- Throttling and payload references beyond what drag immediately needs.
- `Record Experiment`.
- `drag-diff` and `drag-repro`.
- Additional OTLP rollout beyond the SP1a compile/export proof.
- LUNA-361 notification observability consumers.

## Dependency Strategy

SP1a adopts both Swift tracing libraries:

```
swift-distributed-tracing
  Tracing API, span lifecycle, and ServiceContext propagation contract.

swift-otel
  Standard OTLP backend path for collector export.

AgentStudioJSONLTraceSink
  App-local exporter for per-run JSONL files, ring buffer, fixtures, and agent-readable traces.
```

JSONL is an exporter/sink, not a separate tracing model. Instrumentation creates spans and span events through the tracing API; the app-local JSONL sink serializes those records for local diagnostics. The later OTLP path uses `swift-otel` for network export, or an OTLP JSON file exporter if we want collector-readable files.

SP1a should include a compile/export proof for `swift-otel`: one span can be emitted through the Swift tracing stack and sent through the backend path in a controlled local/dev configuration. The production debugging flow still writes Agent Studio JSONL locally so drag sessions, shell tools, and fixtures do not depend on a running collector or OTLP file reader.

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

This is the app-local Agent Studio JSONL exporter shape. It serializes tracing records for local diagnostics; it is not OTLP and does not claim direct collector ingestion. Agents and shell tools are the first consumers. Later collector export uses `swift-otel` network export or an OTLP JSON file exporter. Prefer OTel-aligned structure over hand-optimized human prose. Shell tooling formats timestamps on read.

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
    "version": "0.1.0"
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
- `time_unix_nano` is canonical. Shell tools can format ISO time on read.
- `scope.name` is the instrumentation library identifier for the emitting code path.
- `scope.version` is the instrumentation scope release/schema version. Bump it when the emitted record shape for that scope changes.
- Shell tools must not group by `trace_id` alone. Use domain IDs such as `drag.session_id`, `command.id`, or `envelope.seq` when an orphan span lacks a parent trace.

## Attribute Discipline

Keep the OTel layering intact:

```
resource
  App-run stable facts.
  Examples: service.name, process.pid, service.version.

scope
  Instrumentation scope facts.
  Examples: agentstudio.eventbus, agentstudio.drag, agentstudio.runtime.

attributes
  Per-record domain facts.
  Examples: envelope.seq, pane.id, command.id, drag.session_id.
```

Do not move per-event domain IDs into `resource` or `scope`. Do not duplicate stable app identity into every event attribute.

## Propagation Model

Swift actor hops make implicit propagation risky. SP1a uses `swift-distributed-tracing` as the propagation contract, but does not assume implicit propagation works everywhere. The first implementation passes context explicitly across risky boundaries and proves one drag flow across AppKit ingress, `@MainActor`, `Task`, actor hops, and `@concurrent nonisolated`.

```
TraceContext
  traceId
  spanId
  parentSpanId
  sessionId
```

Rules:

- App/user ingress creates or receives a `ServiceContext`-backed trace context.
- Runtime/eventbus paths pass context explicitly where available, especially across AppKit callbacks, detached tasks, and nonisolated work.
- If no context exists, the tracer may create an orphan span with `agentstudio.trace.orphan=true`.
- Do not rely only on TaskLocal propagation in SP1a.
- Document the drag propagation path as the pattern future scopes follow.

## Ownership And Concurrency

`Tracer` lives in `Infrastructure/Diagnostics`.

Design:

```
Tracer
  Static facade with cheap disabled checks.

TraceSink
  Protocol for JSONL, ring buffer, later OTLP file/network, and multiplex sinks.

TraceWriter
  Actor owning mutable buffers and file I/O.
```

Blocking file writes must not run on `@MainActor`. Flush uses a writer actor or `@concurrent nonisolated` helper.

Disabled behavior must avoid allocation-heavy payload construction. Prefer autoclosure payload builders.

## Sink Strategy

```
SP1a
  AgentStudioJSONLTraceSink + RingBufferTraceSink.
  Persistent local debugging and fixture capture.
  ServiceContext-shaped context propagated through one drag flow.
  swift-otel compile/export proof for one span.

SP1b+
  More trace tags and more shell tooling.

MultiplexTraceSink
  Later: Agent Studio JSONL + OTLP file and/or OTLP network simultaneously.
```

Do not make a running collector or OTLP file reader mandatory in SP1a. The app-local Agent Studio JSONL exporter is the default debug path. Keep the internal trace record close enough to OTel concepts that adding an OTLP JSON file exporter or OTLP network exporter is a new sink, not a model rewrite.

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
- Scripts group by domain IDs first for domain-specific workflows. `drag-session` uses `drag.session_id`; command tools use `command.id`; runtime tools use `runtime.session_id` or `envelope.seq`. `trace_id` is a flow correlation aid, not the only grouping key.
- Scripts format `time_unix_nano` into human-readable time on output.

## Implementation Tasks

### SP1a Task A: Tracer API, Schema, And Dependencies

- [ ] Define `TraceTag`.
- [ ] Define `TraceContext` around the `swift-distributed-tracing` propagation contract.
- [ ] Define `TraceRecord`.
- [ ] Define `TraceSink`.
- [ ] Define disabled fast path.
- [ ] Define env parsing and wildcard matching.
- [ ] Add the `swift-distributed-tracing` dependency and prove one local trace record carries trace ID/span ID/context fields.
- [ ] Add the `swift-otel` dependency and prove one span can use the backend path in a controlled local/dev configuration.

### SP1a Task B: JSONL + Ring Buffer

- [ ] Implement JSONL sink.
- [ ] Implement ring buffer sink.
- [ ] Implement flush.
- [ ] Add per-run file naming.
- [ ] Add tests for disabled/enabled behavior.
- [ ] Add concurrent-emission tests from multiple actors: no corrupted or interleaved JSON lines.
- [ ] Add file-rotation tests for long sessions.
- [ ] Add unflushed-buffer/crash-safety policy tests. Default expectation: best effort, with the last buffered records allowed to be lost on SIGKILL unless `AGENTSTUDIO_TRACE_FLUSH=immediate` is set.

### SP1a Task C: Drag Propagation And Overlay

- [ ] Add `drag` destination/source trace events.
- [ ] Prove context propagation through one full drag flow.
- [ ] Add drag destination overlay.
- [ ] Add `scripts/drag-session`.
- [ ] Capture end-to-end trace evidence for a drawer drag.

### SP1b Task D: Sampling And Payload References

- [ ] Implement `throttled`.
- [ ] Implement payload dump/reference API.
- [ ] Add tests for dropped counts and final-event emission.

### SP1b Task E: Restore And Core Tags

- [ ] Migrate `RestoreTrace` to `restore`.
- [ ] Add `eventbus` post/deliver summary tracing.
- [ ] Add initial `runtime` envelope emission tracing.
- [ ] Add `actions` validation/dispatch tracing.
- [ ] Preserve existing restore-debug behavior in the new sink: same event coverage and equivalent fields, with documented field renames.

### SP1b Task F: Experiment Ergonomics And Extra Shell Tools

- [ ] Add record-experiment menu path.
- [ ] Add `drag-diff`.
- [ ] Add `drag-repro`.
- [ ] Decide whether always-available collector export belongs in the next implementation plan.

## Non-Goals

- Requiring a running OpenTelemetry Collector for local debugging.
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
