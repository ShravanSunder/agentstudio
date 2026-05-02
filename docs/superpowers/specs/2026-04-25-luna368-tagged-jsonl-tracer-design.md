# LUNA-368 Tagged JSONL Tracer Design Spec

**Status:** SP1a implemented on `main`. SP1b and later backend/exporter work remain design material.

**Linear:** [LUNA-368](https://linear.app/askluna/issue/LUNA-368/debugging-harness-tagged-jsonl-tracer-debug-overlays-headless)

**Sibling:** [LUNA-370](https://linear.app/askluna/issue/LUNA-370/drag-testing-harness-headless-layers-ad-pure-mock-hidden) and the separate drag-debug branch own drag overlays and drag-specific shell tools. This spec owns the generic in-app observability substrate and local trace capture.

## Purpose

Build one opt-in diagnostic harness for app investigations:

- Tagged JSONL trace capture.
- Swift tracing libraries own context propagation where their public API supports it.
- Agent Studio JSONL file writer first, OTLP file/network exporters later.
- Per-run files.
- Ring buffer with explicit flush.
- Sampling/throttling for high-volume streams.
- Payload-by-correlation for heavy debug data.
- Record-experiment ergonomics.
- Generic shell tooling for trace triage.

This spec intentionally does not implement LUNA-361 notification behavior. LUNA-361 consumes this tracer in a separate spec.

## Stopping Points

### SP1a: No-Regret Foundation

LUNA-368 reaches its first useful stopping point when a developer can launch the app with selected trace tags enabled, reproduce an app investigation, flush a bounded JSONL trace, and run one generic shell triage command against the trace.

SP1a includes:

- `swift-distributed-tracing` adopted for `ServiceContext` propagation.
- `swift-otel` adopted as the standard future OTLP backend path, with local collector export disabled by default.
- Stable Agent Studio JSONL exporter schema: top-level keys, `agentstudio.*` namespace, resource fields, `time_unix_nano`, and trace/span/log-like event vocabulary.
- Propagation pattern established through one non-UI diagnostic flow that crosses at least one async boundary.
- Local JSONL file writer, ring buffer, explicit flush, rotation, env-var control, and per-run files.
- One local JSONL record proof on disk with resource, scope, attributes, and domain correlation IDs. `trace_id` and `span_id` are optional in JSONL-only mode and must not be faked by creating no-op spans.
- One generic trace triage script that can list recent traces or inspect a trace by correlation ID/tag.

SP1a does not require direct OpenTelemetry Collector ingestion and does not write OTLP JSON. It preserves the OTel-shaped internal vocabulary so an OTLP file exporter or OTLP network exporter can be added later as another sink without redesigning the tracing model.

### SP1b And Follow-Ups

These slide after SP1a without architectural regret:

- `eventbus`, `atoms`, `actions`, `surface`, and `restore` scopes.
- Throttling and payload references beyond the first high-volume stream that needs them.
- `Record Experiment`.
- Domain-specific shell tools.
- OTLP rollout once a real `swift-otel` backend/export path is wired.
- LUNA-361 notification observability consumers.
- Drag overlay and drag-specific tooling on the separate drag branch.

## Dependency Strategy

SP1a adopts both Swift tracing libraries:

```
swift-distributed-tracing
  ServiceContext propagation contract. Do not start spans unless a real tracing
  backend is bootstrapped and exporting them.

swift-otel
  Standard OTLP backend path. In swift-otel 1.0.5, span exporter types are package-internal,
  so Agent Studio cannot conform a custom JSONL exporter directly to OTelSpanExporter
  without a package change or adapter surface.

AgentStudioJSONLTraceWriter
  App-local writer for per-run JSONL files, fixtures, and agent-readable traces.
  Does not pretend to be OTLP. Keep its record shape OTel-aligned so later OTLP
  file/network export is an additional backend path, not a schema rewrite.
```

JSONL is the local diagnostic output format, not a separate observability vocabulary. The app-local writer serializes OTel-aligned records for local diagnostics. It must not create no-op spans just to look like OpenTelemetry. The later OTLP network path uses `swift-otel`; an OTLP JSON file exporter is custom work if we want collector-readable files on disk.

SP1a keeps `swift-otel` available as the future backend path but does not claim a custom exporter conformance that the public package surface does not expose. The production debugging flow writes Agent Studio JSONL locally so trace review, shell tools, and fixtures do not depend on a running collector or OTLP file reader.

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
```

## Trace Tags

Start with generic observability tags. Add consumer tags only when a real investigation needs them.

```
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
drag
app.focus
inbox
ui.surface
terminal.activity
drawer
style
```

These are consumer tags. They should not block the LUNA-368 tracer foundation. `drag` is explicitly owned by the separate drag-debug branch in this repo, not this notification-observability branch.

## Environment

```
AGENTSTUDIO_TRACE_TAGS=eventbus,runtime
AGENTSTUDIO_TRACE_NAME=runtime-envelope-smoke
AGENTSTUDIO_TRACE_DIR=/tmp
AGENTSTUDIO_TRACE_BACKEND=jsonl
```

Selectors:

```
AGENTSTUDIO_TRACE_TAGS=runtime,eventbus
AGENTSTUDIO_TRACE_TAGS=surface.*
AGENTSTUDIO_TRACE_TAGS=*
AGENTSTUDIO_TRACE_TAGS=off
```

Output:

```
/tmp/agentstudio-<trace-name>-<pid>.jsonl
```

Backend selector:

```
AGENTSTUDIO_TRACE_BACKEND=jsonl
  SP1a default. Writes Agent Studio JSONL only. Does not bootstrap spans.

AGENTSTUDIO_TRACE_BACKEND=otlp
  Reserved. Future mode that bootstraps a real swift-otel backend and exports
  spans/logs to an OTLP file or network endpoint.

AGENTSTUDIO_TRACE_BACKEND=both
  Reserved. Future mode that keeps local JSONL while also exporting OTLP.
```

Until `otlp` or `both` exists, unknown or unsupported backend values must fall back to `jsonl` with a startup diagnostic. The important invariant is that the app never starts a tracing span just to feed local JSONL. Spans are only valid when a real backend is bootstrapped and receives them.

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
    "agentstudio.trace.name": "runtime-envelope-smoke",
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
- Shell tools must not group by `trace_id` alone. Use domain IDs such as `command.id`, `runtime.session_id`, or `envelope.seq` when a record lacks a parent trace.

## Attribute Discipline

Keep the OTel layering intact:

```
resource
  App-run stable facts.
  Examples: service.name, process.pid, service.version.

scope
  Instrumentation scope facts.
  Examples: agentstudio.eventbus, agentstudio.actions, agentstudio.runtime.

attributes
  Per-record domain facts.
  Examples: envelope.seq, pane.id, command.id, runtime.session_id.
```

Do not move per-event domain IDs into `resource` or `scope`. Do not duplicate stable app identity into every event attribute.

## Propagation Model

Swift actor hops make implicit propagation risky. SP1a uses `swift-distributed-tracing` as the propagation contract, but does not assume implicit propagation works everywhere. The first implementation passes context explicitly across risky boundaries and proves one non-UI diagnostic flow across `Task`, actor hops, and file-writer actor boundaries.

```
ServiceContext
  Generic propagated context carrier.
  Trace/span identifiers are accessed through backend-provided keys/extensions.

Span / Tracer
  Native tracing operation and creation APIs. Use only when a real backend/exporter
  is bootstrapped, so span lifecycle data has a destination.
```

Rules:

- App/user ingress creates or receives a `ServiceContext`-backed trace context.
- Runtime/eventbus paths pass context explicitly where available, especially across AppKit callbacks, detached tasks, and nonisolated work.
- If no context exists, the local JSONL writer still emits the record with domain IDs.
- Do not rely only on TaskLocal propagation in SP1a.
- Do not create an app-owned `TraceContext` unless the library API leaves a concrete gap. Prefer `ServiceContext` plus domain IDs in record attributes.
- Document the proven propagation path as the pattern future scopes follow.

## Ownership And Concurrency

`Tracer` lives in `Infrastructure/Diagnostics`.

Design:

```
Tracer
  Static facade with cheap disabled checks.

AgentStudioJSONLTraceWriter
  App-local actor that writes OTel-aligned JSONL.
  It is not an OTelSpanExporter while swift-otel's exporter protocol is package-internal.

AgentStudioJSONLLogRecordExporter
  Only if this spec chooses log records for some diagnostics.

Processor chain
  Later OTLP work uses swift-otel batch/multiplex processor concepts where public APIs allow.

TraceWriter
  Actor owning mutable buffers and file I/O.
```

Blocking file writes must not run on `@MainActor`. Flush uses a writer actor or `@concurrent nonisolated` helper.

Disabled behavior must avoid allocation-heavy payload construction. Prefer autoclosure payload builders.

## Sink Strategy

```
SP1a
  AgentStudioJSONL writer with OTel-aligned record shape.
  Persistent local debugging and fixture capture.
  ServiceContext-shaped context propagated through one non-UI diagnostic flow.
  No no-op span lifecycle in the local JSONL path.
  AGENTSTUDIO_TRACE_BACKEND=jsonl is the only active backend mode.

SP1b+
  More trace tags and more shell tooling.

OTLP backend
  Later: AGENTSTUDIO_TRACE_BACKEND=otlp bootstraps swift-otel and exports to
  an OTLP file or network endpoint.

Multiplex backend
  Later: AGENTSTUDIO_TRACE_BACKEND=both writes Agent Studio JSONL and OTLP
  simultaneously.
```

Do not make a running collector or OTLP file reader mandatory in SP1a. The app-local Agent Studio JSONL writer is the default debug path. Keep the internal trace record close enough to OTel concepts that adding a custom OTLP JSON file exporter or swift-otel network exporter is a new backend path, not a model rewrite.

Ring buffering should stay close to the export/write boundary. Keep the app-owned writer actor as the local JSONL buffering boundary and document the later OTLP path separately.

## Sampling And Throttling

Required for high-volume tags such as `eventbus`, `atoms`, terminal activity, or future drag instrumentation.

API shape:

```swift
Tracer.throttled(
    .eventbus,
    key: envelopeStreamId,
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

- A high-volume stream with 200+ updates produces a compact but useful trace.
- Dropped counts are visible.

## Payload-By-Correlation

Heavy data should be dumped once and referenced later.

Examples:

- View ancestry.
- Atom before/after payloads.
- Event envelope summaries.
- Runtime state snapshots.

Record shape:

```json
{
  "body": "payload.dump",
  "attributes": {
    "payload.ref": "runtime-session-abc:view-tree",
    "payload.kind": "view-tree",
    "runtime.session_id": "abc"
  }
}
```

Later records use:

```json
{
  "body": "runtime.emitEnvelope",
  "attributes": {
    "payload.ref": "runtime-session-abc:view-tree"
  }
}
```

Payload retention follows the trace file lifecycle.

## Debug Overlays

Debug overlays are intentionally outside this notification-observability branch.

- Drag destination overlays belong to the separate drag-debug branch and LUNA-370-adjacent work.
- LUNA-368 may still define the generic trace/export substrate those overlays consume.
- Do not add split-view or drag-specific UI changes to this branch as part of SP1a.

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

Minimum generic scripts:

```
scripts/trace-recent
scripts/trace-flow <correlationID>
```

Acceptance:

- `trace-recent` lists recent trace files and their tags/counts.
- `trace-flow` prints all records matching `trace_id`, `agentstudio.correlation_id`, or a supplied domain ID.
- Scripts group by domain IDs first for domain-specific workflows. Command tools use `command.id`; runtime tools use `runtime.session_id` or `envelope.seq`; notification tools use `notification.id` or `pane.id`. `trace_id` is a flow correlation aid, not the only grouping key.
- Scripts format `time_unix_nano` into human-readable time on output.

## Implementation Tasks

### SP1a Task A: Tracer API, Schema, And Dependencies

- [ ] Define `TraceTag`.
- [ ] Define `TraceRecord`.
- [ ] Use `ServiceContext` as the propagation carrier; add app domain IDs as record attributes.
- [ ] Implement Agent Studio JSONL writer with an OTel-aligned record shape.
- [ ] Define disabled fast path.
- [ ] Define env parsing and wildcard matching.
- [ ] Treat `AGENTSTUDIO_TRACE_BACKEND=jsonl` as the only active SP1a backend mode; reserve `otlp` and `both` with diagnostics rather than silent behavior changes.
- [ ] Add the `swift-distributed-tracing` dependency and prove one local trace record carries caller-provided trace ID/span ID plus `ServiceContext` correlation fields.
- [ ] Add the `swift-otel` dependency for the future public OTLP backend path; do not create spans until a real backend/exporter is wired.

### SP1a Task B: JSONL + Ring Buffer

- [ ] Implement JSONL sink.
- [ ] Implement ring buffer behavior inside the processor/exporter path.
- [ ] Implement flush.
- [ ] Add per-run file naming.
- [ ] Add tests for disabled/enabled behavior.
- [ ] Add concurrent-emission tests from multiple actors: no corrupted or interleaved JSON lines.
- [ ] Add file-rotation tests for long sessions.
- [ ] Add unflushed-buffer/crash-safety policy tests. Default expectation: best effort, with the last buffered records allowed to be lost on SIGKILL unless `AGENTSTUDIO_TRACE_FLUSH=immediate` is set.

### SP1a Task C: Propagation Proof And Generic Triage

- [ ] Prove context/correlation propagation through one non-UI diagnostic flow.
- [ ] Add `scripts/trace-recent`.
- [ ] Add `scripts/trace-flow`.
- [ ] Capture one JSONL evidence file proving records can be inspected by tag and correlation ID.

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
- [ ] Add domain-specific trace tools only after a consumer spec needs them.
- [ ] Add `AGENTSTUDIO_TRACE_BACKEND=otlp` once a real swift-otel backend/export path is bootstrapped.
- [ ] Add `AGENTSTUDIO_TRACE_BACKEND=both` only after JSONL and OTLP can be multiplexed without duplicating instrumentation call sites.
- [ ] Decide whether always-available collector export belongs in the next implementation plan.

## Non-Goals

- Requiring a running OpenTelemetry Collector for local debugging.
- Metrics.
- Always-on production tracing.
- LUNA-361 notification behavior.
- Drag destination overlays or split-view UI changes.
- Drag-specific shell tools.
- LUNA-370 headless test layers.

## Open Questions

1. Which generic flow gets explicit `trace_id` creation first: command dispatch, runtime envelopes, eventbus delivery, or focus changes?
2. Should `eventbus.deliver` default to one summary record, with per-subscriber delivery under `eventbus.verbose`?
3. What are the first allowed heavy payload kinds?
4. Should `Record Experiment` write into `/tmp` only, or under an app diagnostics folder?
5. What UI shape should the debug menu take in release builds: hidden, disabled, or absent?
