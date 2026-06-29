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
| Global preferences | `<AppDataPaths.rootDirectory()>/preferences.global.json` | App-root scoped default observability posture |
| Instrumentation selection | `AGENTSTUDIO_TRACE_TAGS` | Which app emitters are enabled |
| Sink selection | `AGENTSTUDIO_TRACE_BACKEND`, `OTEL_EXPORTER_OTLP_ENDPOINT`, `OTEL_EXPORTER_OTLP_PROTOCOL` | JSONL, OTLP, or both |
| Proof handoff | `AGENTSTUDIO_OBSERVABILITY_*` state files | Marker, PID, app path, query window, launch status |

`AGENTSTUDIO_DATA_DIR` is only a root locator. It chooses the app data root
that contains `preferences.global.json`; it is not itself an observability
setting. Stable, beta, debug, generated debug, and custom app identities keep
separate roots, so each app identity gets its own global preferences file.

The preference file is loaded by App/Boot before `AgentStudioTraceRuntime` is
constructed. Diagnostics then resolves effective trace behavior in this order:
channel defaults, then global preferences, then environment overrides. This
keeps local prod/beta/debug defaults durable while preserving the existing
one-launch override contract. `AGENTSTUDIO_TRACE_TAGS=off` still disables
tracing for that launch, and `AGENTSTUDIO_TRACE_BACKEND`,
`OTEL_EXPORTER_OTLP_ENDPOINT`, and `OTEL_EXPORTER_OTLP_PROTOCOL` still win over
the preference file.

The v1 preference schema owns only durable choices:

```json
{
  "schemaVersion": 1,
  "observability": {
    "enabled": true,
    "traceTags": "*",
    "traceBackend": "otlp",
    "traceFlush": "buffered",
    "otlpEndpoint": "http://127.0.0.1:4318"
  }
}
```

`observability.enabled` is required. `traceTags`, `traceBackend`, `traceFlush`,
and `otlpEndpoint` are optional. `otlpEndpoint` must be loopback HTTP when
present. `otlpProtocol` is intentionally not a persisted preference; protocol
compatibility remains an environment-only escape hatch.

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

The strict debug and beta observability launchers may pass the standard
trace/backend variables plus app identity and state-file variables. Preference
proof launchers use sibling scripts and write `preferences.global.json` under an
isolated proof data root instead of injecting trace-selection variables. Neither
launcher family may grow feature-specific trace switches.

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
startup. This includes `atoms`, `eventbus`, `terminal.activity`,
`terminal.signal`, `inbox`, `paneInbox`, and `persistence.snapshot`.

Terminal signal instrumentation is controlled by the `terminal.signal` tag. It
captures low-volume Ghostty action/control facts such as desktop notification,
command-finished, progress, and routing outcomes. Terminal output growth and
debounced unseen-activity windows remain under `terminal.activity`. Keep raw
terminal payloads, pane ids, surface ids, and notification ids JSONL-only; OTLP
may export only controlled signal class, action name, route result, reason, and
safe aggregate counters.

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

Preference-honoring proof writes
`AGENTSTUDIO_OBSERVABILITY_PREFERENCES_MODE=honor_preferences` in the state
file. When that flag is present, verifiers must also require the
`app.preferences.global.loaded` startup event under the current marker. Strict
env-driven launchers must not write the flag.

State files may include existing proof handoff fields such as marker, PID, app
path, app identity, launch status, query window, data root, zmx root, and log
path. They must not include preference file paths, symlink targets, raw JSON,
parse messages, prompts, payloads, or tool output.

For atom or performance work, proof should include:

```text
logs     current marker contains expected event names
metrics  current marker contains expected metric series
safety   OTLP projection contains only allowlisted fields
tests    trace config, projection, metric mapping, and emitter tests pass
```

Do not accept stale Victoria rows, old JSONL files, screenshots, or unmarked
records as proof.

Use proof layers deliberately:

```text
unit/focused tests    -> deterministic logic and source projection
integration tests     -> real boundaries such as sinks, stores, processes
debug observability   -> debug app launch with marker-scoped Victoria proof
performance proof     -> VictoriaMetrics under the current workload marker
native UI proof       -> Peekaboo against a debug/beta app by PID
```

Peekaboo is visual/native interaction evidence. It can prove that a debug or
beta app launched, rendered, and accepted a UI interaction, but it does not
replace marker-scoped VictoriaLogs/VictoriaMetrics proof for telemetry or
focused tests for source-side projection and safety rules.

## Progressive Disclosure For Debugging

When explaining or debugging AgentStudio observability, start by separating the
control surfaces before naming specific events:

```text
instrumentation selection  -> AGENTSTUDIO_TRACE_TAGS
sink selection             -> AGENTSTUDIO_TRACE_BACKEND + OTLP endpoint/protocol
global preferences         -> <AppDataPaths.rootDirectory()>/preferences.global.json
data root locator          -> AGENTSTUDIO_DATA_DIR
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
