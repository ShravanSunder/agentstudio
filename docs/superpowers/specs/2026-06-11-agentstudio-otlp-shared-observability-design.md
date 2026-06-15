# AgentStudio OTLP Shared Observability Design

## Status

Design approved for spec draft. Implementation plan not written yet.

## Purpose

Add OTLP output to AgentStudio without replacing the existing JSONL diagnostic
path.

The target is not an AgentStudio-private Victoria stack. The target is a shared
local observability host for this machine. AgentStudio is one producer into that
host. Other unrelated local projects should be able to use the same collector,
VictoriaMetrics, VictoriaLogs, and VictoriaTraces stack.

The design keeps app launch fast and safe:

- AgentStudio never starts Docker or Docker Compose during app launch.
- Debug and beta builds may emit to a loopback OTLP collector when available.
- Stable release builds remain JSONL/env opt-in only.
- Missing or unhealthy collector endpoints never crash or block the app.
- Local JSONL remains the agent-readable forensic artifact.

## Scope Boundary

This is the AgentStudio producer spec. It defines how AgentStudio emits safe OTLP
to a shared local collector.

AgentStudio owns:

- local backend selection
- debug/beta/stable enablement policy
- non-blocking collector absence behavior
- JSONL plus OTLP sink fanout
- source-side OTLP projection and payload reduction
- process-static resource attributes
- late-bound workspace/repo identity on records once available
- a thin docs pointer to the shared host tooling

AgentStudio does not permanently own:

- Docker Compose lifecycle
- Victoria service topology
- collector config rendering
- shared retention or storage defaults
- shared host service names beyond the producer endpoint contract
- shared Victoria smoke/e2e tests

The shared observability host should live in `~/dev/ai-tools/observability`,
outside the AgentStudio product runtime. If any compose/config assets
temporarily land in this repo, they must be marked temporary, generic, and
external to AgentStudio product runtime.

## Current State

AgentStudio already has an app-scoped diagnostics runtime:

- `AgentStudioTraceRuntime.fromEnvironment()` is created in `main.swift` before
  app boot and before Ghostty startup tracing.
- `AgentStudioTraceRuntime.record(...)` is the central emission point for the
  JSONL tracer.
- `AgentStudioTraceBackend` currently supports only `jsonl`; unsupported values
  such as `otlp` fall back to JSONL with a startup diagnostic.
- Existing trace records are OpenTelemetry-shaped JSONL records, but they are
  not real OTLP exports.
- Production code does not bootstrap SwiftLog, Swift Metrics, or Swift
  Distributed Tracing globally today. The only tracing bootstrap evidence is in
  diagnostics tests.

The earlier LUNA-368 design intentionally left OTLP as future backend work. It
also set the invariant that JSONL-only mode must not create fake no-op spans just
to look like OpenTelemetry.

## External Shared Observability Host Contract

The shared host is the local machine service plane. It is owned outside
AgentStudio product runtime by `~/dev/ai-tools/observability`. This AgentStudio
repo may carry a thin pointer in `AGENTS.md` plus temporary developer
instructions, but the stack itself should not be conceptually owned by
AgentStudio.

Recommended shared stack identity:

```text
compose project
  ai-tools-observability

services
  ai-tools-otel-collector
  ai-tools-victoria-metrics
  ai-tools-victoria-logs
  ai-tools-victoria-traces
  ai-tools-grafana               optional

docker network
  ai-tools-observability

default host bindings
  127.0.0.1:4317  -> collector OTLP gRPC
  127.0.0.1:4318  -> collector OTLP HTTP
  127.0.0.1:13133 -> collector health

optional debug host bindings
  127.0.0.1:8428  -> VictoriaMetrics
  127.0.0.1:9428  -> VictoriaLogs
  127.0.0.1:10428 -> VictoriaTraces
```

The default shared stack should publish only collector ingest and collector
health on the host. VictoriaMetrics, VictoriaLogs, and VictoriaTraces remain
inside the compose network by default. Publishing their query/write ports is an
explicit debug profile choice, not the safe default, because any local process
can talk to loopback ports.

Durable storage should live under a shared machine-local root, not under a repo
checkout and not under an app data directory:

```text
~/.local/share/ai-tools-observability/metrics
~/.local/share/ai-tools-observability/logs
~/.local/share/ai-tools-observability/traces
```

The exact root should be overrideable with a single environment variable such as
`AI_TOOLS_OBSERVABILITY_DATA_DIR`. Generated collector config and compose files
may live under an ignored runtime/config directory, but durable Victoria data is
not temporary runtime state.

## Producer Contract

All local projects send OTLP to one local collector endpoint:

```text
OTEL_EXPORTER_OTLP_ENDPOINT=http://127.0.0.1:4318
OTEL_EXPORTER_OTLP_PROTOCOL=http/protobuf
```

The collector owns routing to Victoria-specific endpoints:

```text
metrics -> http://ai-tools-victoria-metrics:8428/opentelemetry/v1/metrics
logs    -> http://ai-tools-victoria-logs:9428/insert/opentelemetry/v1/logs
traces  -> http://ai-tools-victoria-traces:10428/insert/opentelemetry/v1/traces
```

AgentStudio should not know Victoria backend paths. It should know only the
collector endpoint. This keeps direct Victoria backend quirks out of app code and
lets unrelated projects share the same host.

## AgentStudio Backend Modes

Keep the existing selector and extend it:

```text
AGENTSTUDIO_TRACE_BACKEND=jsonl
AGENTSTUDIO_TRACE_BACKEND=otlp
AGENTSTUDIO_TRACE_BACKEND=both
```

Default behavior:

```text
stable release
  jsonl unless explicitly configured otherwise

debug build
  both-auto: JSONL immediately, OTLP to loopback collector when configured or
  when the local default endpoint is usable

beta release
  both-auto: JSONL immediately, OTLP to loopback collector when configured or
  when the local default endpoint is usable
```

`both-auto` is a policy concept, not necessarily a user-visible backend string.
It means the app keeps JSONL and attempts local OTLP export without treating
collector absence as a product failure.

Collector absence behavior:

- App launch continues.
- JSONL stays active when enabled.
- A startup diagnostic records that the local OTLP collector was unavailable or
  export failed.
- No crash, alert, modal, or retry loop that can make launch feel broken.

For tests and explicit developer sessions, an env flag may require collector
readiness, but that must not be the default app behavior.

## Trace Tag Defaults

The current tracer is tag-gated. Adding an OTLP backend is not enough if no tags
are enabled. Debug and beta should therefore get a conservative safe baseline.

Default tag policy:

```text
stable release
  no default tags; diagnostics remain env opt-in

debug build
  safe baseline tags unless AGENTSTUDIO_TRACE_TAGS is set

beta release
  safe baseline tags unless AGENTSTUDIO_TRACE_TAGS is set
```

Recommended safe baseline:

```text
app.startup
terminal.startup
runtime
surface
persistence.recovery
```

Excluded from the default baseline:

```text
atoms
eventbus
terminal.activity
ui.interaction
inbox
paneInbox
persistence.snapshot
```

Those tags can be high-volume, more user-specific, or more likely to include
domain data that should remain explicit opt-in.

`AGENTSTUDIO_TRACE_TAGS=off` disables tracing even in debug/beta. Explicit
selectors such as `runtime,eventbus` or `terminal.*` override the baseline.
Trace tags are the instrumentation selection boundary. New high-volume emitters
must use `AgentStudioTraceTag` selectors such as `atoms`; do not add ad-hoc
per-emitter environment variables such as `AGENTSTUDIO_TRACE_ATOM_METRICS`.

## Swift OTel Integration Boundary

Swift OTel is the backend path for SwiftLog, Swift Metrics, and Swift
Distributed Tracing. It does not expose a public generic API for "send this
AgentStudioTraceRecord as an arbitrary OTLP log record."

That creates two design rules:

1. Keep the existing AgentStudio instrumentation call sites on
   `AgentStudioTraceRuntime.record(...)`.
2. Add OTLP behind the runtime, not by rewriting every emitter.

The diagnostics runtime should become a fanout over sinks:

```text
AgentStudioTraceRuntime
  -> AgentStudioJSONLTraceSink
  -> AgentStudioOTLPSink
```

The JSONL sink preserves current behavior. The OTLP sink owns Swift OTel
bootstrap and maps the reduced AgentStudio trace record into supported Swift OTel
signals.

Initial signal mapping:

```text
existing record(...) events
  OTLP logs first, using event name/body plus reduced metadata

explicit future timed operations
  real spans through Swift Distributed Tracing

explicit future counters/timers
  Swift Metrics instruments
```

Do not fake every JSONL event as a trace span. Real spans require deliberate
lifecycle APIs and bounded operations.

## Resource Identity

Segregation across apps, worktrees, beta/debug builds, and unrelated projects
comes from resource attributes and stable fields, not from separate Victoria
backends or prefixed metric names.

Process-static resource attributes are available when `AgentStudioTraceRuntime`
is created:

```text
service.name
service.version
dev.runtime.flavor        debug | beta | stable | custom
dev.build.config          DEBUG | RELEASE when meaningful
dev.release.channel       stable | beta when meaningful
```

AgentStudio-specific resource attributes:

```text
agentstudio.build.config
agentstudio.release_channel
agentstudio.runtime_flavor
```

Workspace and git identity are late-bound. They are not reliably available when
the process-level diagnostics runtime is created before workspace boot. Once the
workspace/repo context is known, the runtime should enrich new records with:

```text
dev.repo.hash
dev.worktree.hash
dev.branch.name
```

The implementation should use a runtime-owned enrichment provider updated after
workspace boot, not block process startup while trying to discover repository
state.

`dev.worktree.hash` is a stable hash of the canonical worktree path. The raw
worktree path must not be sent over OTLP by default. Branch name is allowed and
useful for grouping. This accepts that local branch names may reveal local issue
or project labels inside the loopback-only observability host. Commit is useful
for local debugging but is not exported by default because it is not required by
the current safe resource contract.

High-cardinality values such as process id, session id, pane id, tab id, and
request/correlation ids must not become VictoriaMetrics labels. They may appear
as log or trace fields when they are safe and useful.

## Naming Policy

Do not prepend worktree or runtime identity into metric names, span names, or log
event names.

Good:

```text
metric name: agentstudio.startup.duration
labels/resource: service.name=agentstudio, dev.branch.name=otel-integration
```

Avoid:

```text
metric name: otel-integration.debug.agentstudio.startup.duration
```

Stable names keep dashboards, queries, and alerts reusable. Identity dimensions
belong in attributes and labels with controlled cardinality.

## Scrubbing And Extension Model

The safety model has three layers.

### 1. Source-Side Non-Emission

AgentStudio must not emit:

- secrets, tokens, auth headers, cookies, API keys, private keys
- prompt text, model responses, raw terminal output, or tool payloads
- raw full filesystem paths over OTLP
- arbitrary error descriptions that can include paths, SQL, environment, or
  credential fragments

JSONL may remain richer for local forensic debugging. OTLP should use a reduced
payload set in v1.

### 1a. AgentStudio OTLP Projection Allowlist

The OTLP sink is a source-side trust boundary. It must project from
`AgentStudioTraceRecord` into a reduced OTLP-safe representation instead of
exporting the JSONL record wholesale.

Default projection rules:

```text
Always allowed when present
  time
  severity
  trace tag
  stable event name/body string
  process-static resource identity
  late-bound repo/worktree hash/branch/commit identity
  numeric durations and counts
  controlled enum/status values

Always local-only unless separately approved
  raw filesystem paths
  normalized sqlite database paths
  raw error descriptions
  process id
  session id
  pane id
  tab id
  surface id
  window id
  command id
  correlation id
  causation id
  runtime envelope id
  zmx session id
  terminal output
  prompt/model/tool payload text
```

Initial emitter policy:

```text
AgentStudioStartupTraceRecorder
  OTLP: event names, phases, controlled status, durations/counts
  JSONL only: pane/surface/zmx/session identifiers

WorkspaceSQLiteTraceRecorder
  OTLP: operation type, controlled result, recovery class, duration/counts
  JSONL only: workspace id, database path, raw error description

TerminalActivityRouter
  OTLP: controlled event class and aggregate counts when enabled
  JSONL only: pane ids, command ids, correlation/causation/event ids

GhosttyActionRouter+Tracing
  OTLP: action name and controlled route outcome
  JSONL only: pane/surface ids and any freeform route reason

AtomPerformanceTelemetry
  tag: atoms
  OTLP: controlled atom event names, kind/operation vocabulary, aggregate counts
  JSONL only: future local forensic fields, if explicitly needed
```

If a future investigation needs a local-only field in OTLP, the change must add
an explicit allowlist entry and test coverage proving it does not become a metric
label.

### 2. Collector Scrubbing

The shared collector is the main backend-neutral scrubber.

Recommended processors:

```text
resource/drop-sensitive
  delete unsafe resource attributes

attributes/drop-sensitive
  delete unsafe span/log/metric datapoint attributes

attributes/hash-stable-identity
  hash accidental raw path identity fields when deletion would remove useful
  grouping; this is for local grouping, not secret protection

transform/log-policy
  rewrite or empty risky log bodies for producer profiles that cannot guarantee
  safe structured bodies

filter/noisy-or-unsafe
  narrowly drop known unsafe/noisy telemetry; avoid broad filters that can
  orphan trace/log relationships

batch
  batch after scrubbing
```

The collector config should be generated from a base profile plus producer
profiles. AgentStudio gets an AgentStudio profile. Other projects can add their
own profile without editing AgentStudio code.

Recommended shared-host extension shape:

```text
base.yaml
  receivers, exporters, common processors, common pipelines

profiles/agentstudio.yaml
  AgentStudio-specific allowlist/drop/hash rules

profiles/<project>.yaml
  producer-specific rules

render command
  validates and renders one collector config for docker compose
```

This extension shape belongs to the shared host package, not to AgentStudio
product code.

Do not depend on Victoria backends as the first scrub layer. Victoria can ignore
or enrich fields at ingestion, but the collector is where cross-signal policy
belongs.

### 3. Victoria Ingestion Guards

VictoriaLogs:

- Use `VL-Stream-Fields` to keep stream identity small and stable.
- Use `VL-Ignore-Fields` to drop known unsafe fields at VictoriaLogs ingestion.
- Use `VL-Extra-Fields` only for safe shared enrichment.

Recommended stream fields:

```text
service.name,dev.repo.hash,dev.worktree.hash,dev.branch.name,dev.runtime.flavor
```

VictoriaMetrics:

- Do not allow all resource attributes to become metric labels.
- Promote only a small allowlist needed for local grouping.
- Avoid pid, session id, request id, pane id, tab id, trace id, or raw paths as
  labels.
- Convert delta metrics to cumulative in the collector if the producer emits
  delta temporality.

Recommended promoted labels:

```text
service.name
service.version
dev.repo.hash
dev.worktree.hash
dev.branch.name
dev.runtime.flavor
dev.release.channel
agentstudio.release_channel
```

VictoriaTraces:

- Use `service.name` and span name intentionally, because VictoriaTraces uses
  those as stream fields.
- Treat `VT-Extra-Fields` as enrichment, not scrubbing.
- Delete/hash unsafe trace attributes in the collector before export.

## Debug And Beta Defaults

Debug and beta are independent facts:

```text
debug
  compile-time build config

beta
  runtime release channel from bundle metadata
```

AgentStudio runtime flavor should be:

```text
debug   when DEBUG is true
beta    when release build and release channel is beta
stable  when release build and release channel is stable
```

Debug wins over beta for runtime flavor, matching existing data-root behavior.

Beta OTLP must be loopback-only by default. No remote collector, auth header, or
off-machine telemetry is enabled without explicit environment configuration.

## Developer Commands And Documentation

AgentStudio should document how to use the shared stack, but should not own it.

Recommended AGENTS.md guidance:

```text
To collect OTLP locally, start the shared observability stack from ai-tools:

  mise run observability:up
  mise run observability:status
  mise run observability:smoke
  mise run observability:down

AgentStudio debug/beta builds emit to http://127.0.0.1:4318 when local OTLP is
enabled/available. Stable release builds require explicit env opt-in.
```

If the shared stack temporarily lives in this repo before promotion to ai-tools,
the implementation plan must mark that as temporary and keep service names,
compose project names, data directories, and labels generic.

## Data Flow

```text
AgentStudio trace call sites
  -> AgentStudioTraceRuntime.record(...)
  -> JSONL sink
  -> OTLP sink
  -> http://127.0.0.1:4318
  -> ai-tools-otel-collector
  -> collector processors
  -> VictoriaMetrics / VictoriaLogs / VictoriaTraces
```

The app sees only the collector endpoint. Victoria-specific paths, stream fields,
ignore fields, metric label promotion, and trace enrichment stay in the shared
collector/stack config.

## Alternatives Considered

### AgentStudio-private compose stack

This is simpler to implement inside this repo, but it duplicates infrastructure
for every project and makes the service names/data dirs AgentStudio-specific.
Reject for v1 because the desired target is shared across unrelated projects.

### Direct app-to-Victoria export

This removes the collector, but it leaks Victoria-specific endpoints and
scrubbing policy into app code. It also makes logs, metrics, and traces diverge
because the three Victoria products use different OTLP paths and ingestion
controls. Reject for v1.

### Shared collector-first local observability host

This is the recommended design. The collector gives one stable OTLP endpoint to
all local producers and centralizes routing, scrubbing, batching, and backend
quirks. The cost is one shared config/rendering surface and host smoke tests.

## Validation Strategy

Unit tests:

- backend selector parses `jsonl`, `otlp`, `both`, and auto defaults
- debug/beta/stable runtime flavor derivation
- resource attribute construction uses hash plus branch and never raw path
- process-static and late-bound resource identity stay separate
- reduced OTLP projection drops known path/error/session/id fields
- collector absence does not disable JSONL or throw

Shared host package snapshot/config tests:

- shared collector config routes metrics/logs/traces to the correct Victoria
  endpoints
- VictoriaLogs exporter includes `VL-Stream-Fields` and `VL-Ignore-Fields`
- VictoriaMetrics args disable all-resource promotion and promote only the
  metric label allowlist
- sensitive field list is present in resource/attribute processors

AgentStudio integration smoke:

- given a reachable loopback collector endpoint, AgentStudio exports a reduced
  OTLP-safe event without blocking startup
- given no reachable collector endpoint, AgentStudio keeps JSONL behavior and
  records a startup diagnostic
- tests may use a local fake collector or an env-gated real collector endpoint

Shared host smoke/e2e:

- optional and env-gated when Docker is available
- starts an isolated compose project by default
- targets an existing shared stack only with explicit opt-in
- sends safe OTLP log, metric, and trace canaries through the collector
- queries VictoriaLogs, VictoriaMetrics, and VictoriaTraces
- proves safe markers are queryable
- proves sensitive canaries are absent after collector/Victoria ingestion

Canary schema:

```text
positive safe field
  shravan.observability.canary.safe_marker

positive safe body marker
  only when log body retention is enabled for the profile under test

negative sensitive attribute
  shravan.observability.canary.secret

negative sensitive body marker
  a sentinel body string that must not survive when body scrubbing is enabled
```

Proof must include a field-based VictoriaLogs query after body scrubbing; a safe
marker that exists only in free-text body is not enough.

Tests may require collector readiness and fail closed. Normal app launch remains
fail-open when the collector is absent or misconfigured.

## Non-Goals

- Do not build dashboards in v1.
- Do not add remote telemetry defaults.
- Do not auto-start Docker from AgentStudio.
- Do not publish Victoria backend ports on the host by default.
- Do not rewrite all instrumentation call sites.
- Do not fake every diagnostic event as a span.
- Do not export raw worktree paths by default.
- Do not make pid/session/request ids VictoriaMetrics labels.
- Do not make AgentStudio the permanent owner of the shared observability stack.

## References

- `docs/superpowers/specs/2026-04-25-luna368-tagged-jsonl-tracer-design.md`
- `docs/superpowers/specs/2026-04-25-luna361-notification-output-observability.md`
- https://github.com/swift-otel/swift-otel
- https://docs.victoriametrics.com/victoriametrics/integrations/opentelemetry/
- https://docs.victoriametrics.com/victorialogs/data-ingestion/opentelemetry/
- https://docs.victoriametrics.com/victorialogs/data-ingestion/
- https://docs.victoriametrics.com/victoriatraces/data-ingestion/opentelemetry/
- https://docs.victoriametrics.com/victoriatraces/data-ingestion/
- https://opentelemetry.io/docs/collector/transforming-telemetry/
- https://github.com/open-telemetry/opentelemetry-collector-contrib/tree/main/processor/attributesprocessor
- https://github.com/open-telemetry/opentelemetry-collector-contrib/tree/main/processor/transformprocessor
- https://github.com/open-telemetry/opentelemetry-collector-contrib/tree/main/processor/filterprocessor
- https://github.com/open-telemetry/opentelemetry-collector-contrib/tree/main/processor/redactionprocessor
