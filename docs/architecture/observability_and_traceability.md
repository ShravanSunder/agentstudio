# Observability And Traceability

AgentStudio is an observability producer. The shared collector, Victoria
services, retention, and smoke checks live outside this repo in
`~/dev/ai-tools/observability`. AgentStudio owns only source-side
instrumentation, launch markers, safe projection, and app-specific proof
scripts.

## Control Plane

Tracing has three separate control surfaces:

| Surface | Env or file | Owns |
| --- | --- | --- |
| Instrumentation selection | `AGENTSTUDIO_TRACE_TAGS` | Which app emitters are enabled |
| Sink selection | `AGENTSTUDIO_TRACE_BACKEND`, `OTEL_EXPORTER_OTLP_ENDPOINT`, `OTEL_EXPORTER_OTLP_PROTOCOL` | JSONL, OTLP, or both |
| Proof handoff | `AGENTSTUDIO_OBSERVABILITY_*` state files | Marker, PID, app path, query window, launch status |

Do not add one-off environment variables for individual emitters. A new
instrumentation lane must be represented as an `AgentStudioTraceTag`, or as an
event namespace under an existing tag when that tag already owns the lane.

Examples:

```text
Good:
  AGENTSTUDIO_TRACE_TAGS=atoms
  AGENTSTUDIO_TRACE_TAGS=performance,atoms
  AGENTSTUDIO_TRACE_TAGS=*

Bad:
  AGENTSTUDIO_TRACE_ATOM_METRICS=1
  AGENTSTUDIO_TRACE_SIDEBAR_EVENTS=1
  AGENTSTUDIO_TRACE_ENABLE_REPO_CACHE=1
```

The debug and beta observability launchers may pass the standard trace/backend
variables plus app identity and state-file variables. They must not grow
feature-specific trace switches.

## Tag Semantics

`AGENTSTUDIO_TRACE_TAGS` selects emitters. Debug and beta app startup has a safe
default baseline when the variable is unset. The strict
`run-debug-observability` and `run-beta-observability` proof helpers set
`AGENTSTUDIO_TRACE_TAGS=*` unless the caller explicitly overrides it, so full
local proof can include high-volume lanes with a fresh marker.

The standard git-refresh performance workload is different: it uses the narrow
`performance,app.startup,terminal.startup` tag set by default so the measured
hot path is not perturbed by high-volume atom tracing. Dedicated atom telemetry
proof can opt into `AGENTSTUDIO_TRACE_TAGS=atoms` or `*`.

High-volume or domain-sensitive lanes remain explicit opt-in for ordinary app
startup. This includes `atoms`, `eventbus`, `terminal.activity`, `inbox`,
`paneInbox`, and `persistence.snapshot`.

Atom instrumentation is controlled by the `atoms` tag. It emits reduced,
aggregate-safe events such as `performance.atom.read`,
`performance.atom.mutation`, and `performance.atom.derived`. The event names
describe the metric family, but the trace tag remains `atoms`; the tag is the
selection boundary.

## OTLP Projection

OTLP is a source-side trust boundary. The app projects trace records into a
reduced safe shape before export. New OTLP fields must be explicit allowlist
entries with tests proving they do not expose raw paths, UUIDs, prompts,
payloads, errors, terminal output, tokens, or tool output.

Allowed OTLP atom fields are aggregate or controlled vocabulary only:

```text
agentstudio.performance.atom.kind
agentstudio.performance.atom.operation
agentstudio.performance.atom.slot.count
agentstudio.performance.atom.cached_key.count
agentstudio.performance.atom.input_revision.count
agentstudio.performance.atom.accepted_change.count
agentstudio.performance.atom.cache_hit
```

Raw atom keys, repo paths, pane ids, workspace ids, object identifiers, and
dictionary payloads must not be exported over OTLP. If an investigation needs a
local forensic field, keep it JSONL-only unless a design update explicitly
extends the OTLP allowlist.

## Proof Model

The standard debug proof loop is:

```text
mise run observability:up
mise run run-debug-observability -- --detach
mise run verify-debug-observability
```

The launcher writes `tmp/debug-observability/latest-observability.env`. That
file is not proof by itself; it is the handoff containing the marker and process
identity. Verification must query Victoria using the current marker and expected
resource labels.

For atom or performance work, proof should include:

```text
logs     current marker contains expected event names
metrics  current marker contains expected metric series
safety   OTLP projection contains only allowlisted fields
tests    trace config, projection, metric mapping, and emitter tests pass
```

Do not accept stale Victoria rows, old JSONL files, screenshots, or unmarked
records as proof.

## Progressive Disclosure For Debugging

When explaining or debugging AgentStudio observability, start by separating the
control surfaces before naming specific events:

```text
instrumentation selection  -> AGENTSTUDIO_TRACE_TAGS
sink selection             -> AGENTSTUDIO_TRACE_BACKEND + OTLP endpoint/protocol
proof identity             -> AGENTSTUDIO_OBSERVABILITY_* state file
                             + marker + launch proof token
Victoria proof             -> marker/token-scoped logs and metrics queries
```

Then select one slice:

```text
atom emitter
  -> AgentStudioTraceTag.atoms
  -> AgentStudioTraceRuntime
  -> JSONL / OTLP sinks
  -> source-side OTLP projection
  -> VictoriaLogs + VictoriaMetrics under the current marker/token
```

Only after that should the explanation name concrete event bodies, attributes,
series names, or query strings. This prevents backend variables, proof-state
variables, and instrumentation flags from being blurred into one bucket.
