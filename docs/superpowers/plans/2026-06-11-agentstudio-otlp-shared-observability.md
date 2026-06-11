# AgentStudio OTLP Shared Observability Implementation Plan

Date: 2026-06-11
Status: draft implementation plan, not executed
Source spec: `docs/superpowers/specs/2026-06-11-agentstudio-otlp-shared-observability-design.md`

## Planning Boundary

This plan implements the AgentStudio producer side of the approved design. It does not implement or vendor the shared VictoriaMetrics, VictoriaLogs, VictoriaTraces, or OpenTelemetry Collector Docker stack.

The shared host stack is an external dependency, expected to live in shared developer tooling such as `devfiles`. AgentStudio should be able to emit to `http://127.0.0.1:4318` when that collector exists, and should remain healthy when it does not.

## Source Coverage

- Source spec line count: 695 lines.
- Read coverage: lines 1-180, 181-360, 361-540, and 541-695.
- Key source decisions used by this plan:
  - AgentStudio is a producer, not the owner of compose or Victoria service lifecycle.
  - Debug and beta builds should emit to a local collector if present, with `AGENTSTUDIO_TRACE_TAGS=off` as a hard disable.
  - Stable/full app remains opt-in unless an explicit tracing environment is provided.
  - Exported OTLP data must be a reduced, allowlisted projection of existing JSONL records.
  - Worktree identity uses a hash of the canonical path plus branch name; raw paths stay local-only.
  - One shared Victoria target is used across projects; segregation happens through resource attributes and labels, not service-specific stacks.

## Current Repo Evidence

- `Sources/AgentStudio/Infrastructure/Diagnostics/AgentStudioTraceConfiguration.swift`
  - `AgentStudioTraceBackend` currently supports only `.jsonl`.
  - `AGENTSTUDIO_TRACE_BACKEND=otlp` is treated as an unsupported selector and falls back to JSONL.
  - `AGENTSTUDIO_TRACE_TAGS` currently controls enablement directly; missing tags disables tracing.

- `Sources/AgentStudio/Infrastructure/Diagnostics/AgentStudioTraceRuntime.swift`
  - `AgentStudioTraceRuntime.record(...)` is the central app-facing trace API.
  - The runtime already imports `OTel` and `Tracing`, but only writes JSONL.
  - The existing resource includes local identifiers such as `agentstudio.session.id` and `process.pid`; these must remain JSONL-only in the OTLP projection.

- `Sources/AgentStudio/Infrastructure/Diagnostics/AgentStudioTraceRecord.swift`
  - The record shape is already OTel-aligned enough to support a sink fanout.

- `Sources/AgentStudio/Infrastructure/Diagnostics/AgentStudioTraceEventQueue.swift`
  - Async emission already funnels back into `AgentStudioTraceRuntime.record(...)`, so a runtime-level fanout preserves existing call sites.

- `Sources/AgentStudio/App/Boot/AppDelegate.swift`
  - `AgentStudioTraceRuntime.fromEnvironment()` is created once at app delegate initialization.
  - The same runtime is passed to startup, workspace SQLite, terminal activity, inbox, and Ghostty action tracing.

- `Sources/AgentStudio/App/Boot/AppDelegate+Termination.swift`
  - Termination already drains trace queues and calls `traceRuntime.flush()`.
  - OTLP service shutdown should fit this existing termination path with a bounded wait.

- `Sources/AgentStudio/Infrastructure/AppDataPaths.swift`
  - Existing release-channel and debug-build logic can anchor runtime flavor: debug, beta, or stable.

- `Package.swift`
  - App target already depends on `swift-otel`.
  - Test target does not currently depend directly on `OTel`, `Logging`, or `ServiceLifecycle`; add only if a focused test imports those modules directly.

- `.mise.toml`
  - Authoritative gates are `mise run lint`, `mise run test`, and targeted `swift test --filter ...` commands during development.

- `swift-otel` public API evidence from local checkout and DeepWiki:
  - `OTel.bootstrap(configuration:)` returns a `Service` that must be run in a `ServiceGroup`.
  - `OTel.makeLoggingBackend(configuration:)` returns a logging factory and service for manual composition.
  - Process-global `LoggingSystem`, `MetricsSystem`, and `InstrumentationSystem` bootstraps can fatal if bootstrapped more than once.
  - Default OTLP protocol is HTTP/protobuf and default endpoint is `http://localhost:4318`, deriving `/v1/logs`, `/v1/metrics`, and `/v1/traces` for OTLP/HTTP.
  - Direct OTLP log exporter types are not the intended public application API; use SwiftLog unless implementation proof shows a safer public route.

## Goal

Add AgentStudio OTLP log export to the shared local collector while preserving the existing JSONL path and the existing app-facing tracing API.

The implementation should make debug and beta builds useful by default when a shared collector is running, without making that collector required for launch, tests, or normal development.

## Non-Goals

- No compose files, Victoria service definitions, storage volumes, or dashboards in AgentStudio.
- No AgentStudio-owned Victoria retention, storage, or port-publishing policy.
- No conversion of existing app events into true spans or metrics in this first implementation.
- No raw paths, terminal text, pane IDs, session IDs, process IDs, command IDs, correlation IDs, causation IDs, or raw error descriptions in OTLP output.
- No broad instrumentation sweep through every feature before the sink, projection, and identity model are proven.
- No dependency on the shared collector for app launch.

## Requirements and Proof Matrix

| ID | Requirement | Owning task | Proof layer | Required proof | Red/green required | Sized to pass |
| --- | --- | --- | --- | --- | --- | --- |
| R1 | `jsonl`, `otlp`, and `both` backend modes parse explicitly, with debug/beta auto policy and stable opt-in behavior. | T1 | Unit | `AgentStudioTraceConfigurationTests` covering missing env, `off`, explicit tags, explicit backend, debug, beta, stable. | Yes | Yes |
| R2 | Missing collector never crashes launch or trace recording. | T5, T7 | Unit + integration | Sink tests with unavailable loopback endpoint and app-runtime smoke using bounded flush/shutdown. | Yes | Yes |
| R3 | Existing JSONL output remains compatible. | T2 | Unit | Existing JSONL writer/runtime tests still pass; add fanout test that JSONL line is unchanged for representative records. | Yes | Yes |
| R4 | OTLP output is reduced and allowlisted. | T3 | Unit | Projection tests assert allowed keys present and forbidden raw fields absent. | Yes | Yes |
| R5 | Worktree segregation uses canonical-path hash plus branch name, not raw path. | T4 | Unit | Identity resolver tests with canonical path inputs, deterministic hash, branch name, and no raw path leakage. | Yes | Yes |
| R6 | One process can touch multiple worktrees without mislabeling everything as one global branch. | T4 | Unit | Per-record enrichment tests resolve identity from record context and use `unknown` when unresolved. | Yes | Yes |
| R7 | Swift OTel bootstrap/service lifecycle is proven before broad wiring. | T0, T5 | Unit + integration | Serialized lifecycle tests or spike test proving one service owner, one bootstrap path, flush/shutdown behavior. | Yes | Split if proof cannot pass |
| R8 | Default endpoint is local loopback; remote endpoints require explicit configuration. | T1, T5 | Unit | Endpoint parser/builder tests for default `http://127.0.0.1:4318`, accepted explicit endpoint, and rejected accidental non-loopback defaults. | Yes | Yes |
| R9 | Debug/beta default tags are conservative and can be disabled. | T1 | Unit | Runtime flavor tests: default debug/beta includes approved baseline tags; `AGENTSTUDIO_TRACE_TAGS=off` disables all. | Yes | Yes |
| R10 | Shared host instructions are discoverable without AgentStudio owning the host. | T8 | Docs | `AGENTS.md` or architecture doc points to external shared host commands and makes absence fail-open. | No, docs only | Yes |
| R11 | Final implementation passes repo proof gates. | T9 | Static + unit/integration | Targeted tests during development, then `mise run lint` and `mise run test`. | No red phase for full suite | Yes |

## Task Sequence

### T0 - Prove Swift OTel Log Export Shape

Purpose:
Verify the exact public `swift-otel` integration path before the implementation depends on it.

Work:
- Add a narrow test or spike inside the permanent test suite, not a throwaway script.
- Determine whether AgentStudio can create an OTLP SwiftLog `Logger` from `OTel.makeLoggingBackend(configuration:)` without bootstrapping the process-global `LoggingSystem`.
- If a per-logger factory path is available, prefer it for the OTLP sink so tests and other process-global systems remain isolated.
- If global `LoggingSystem.bootstrap` is required, introduce a single process owner and keep it outside normal unit tests except serialized lifecycle tests.
- Configure logs only; disable metrics and traces for this first implementation.
- Prove the service can be started, flushed, and shut down with a bounded lifecycle.

Likely write surfaces:
- `Sources/AgentStudio/Infrastructure/Diagnostics/AgentStudioOTLPService.swift`
- `Tests/AgentStudioTests/Infrastructure/Diagnostics/AgentStudioOTLPServiceTests.swift`
- `Package.swift` only if test target needs direct module dependencies.

Proof:
- Targeted `swift test --filter AgentStudioOTLPServiceTests`.

Split or replan trigger:
- If public `swift-otel` APIs force unsafe global bootstrap in a way that cannot be isolated, stop and replan before adding OTLP runtime fanout.

### T1 - Extend Trace Configuration and Runtime Flavor Policy

Purpose:
Make backend selection explicit and encode debug/beta behavior in one tested place.

Work:
- Extend `AgentStudioTraceBackend` to parse:
  - `jsonl`
  - `otlp`
  - `both`
- Keep unknown backend selectors as diagnostics, but do not silently reinterpret unsafe values.
- Add an effective policy layer that can distinguish:
  - explicit user configuration
  - default debug build
  - default beta release
  - stable/full app default
- Add runtime flavor fields derived from `AppDataPaths.isDebugBuild` and `AppDataPaths.ReleaseChannel.current`.
- Apply debug/beta default tag baseline only when `AGENTSTUDIO_TRACE_TAGS` is unset.
- Preserve `AGENTSTUDIO_TRACE_TAGS=off` as a hard disable.
- Use `http://127.0.0.1:4318` as AgentStudio's local default collector endpoint.
- Prefer OTel standard environment keys for collector override:
  - `OTEL_EXPORTER_OTLP_ENDPOINT`
  - `OTEL_EXPORTER_OTLP_PROTOCOL`
  - signal-specific keys if needed later
- Keep the default protocol HTTP/protobuf.

Likely write surfaces:
- `Sources/AgentStudio/Infrastructure/Diagnostics/AgentStudioTraceConfiguration.swift`
- `Sources/AgentStudio/Infrastructure/Diagnostics/AgentStudioRuntimeFlavor.swift`
- `Tests/AgentStudioTests/Infrastructure/Diagnostics/AgentStudioTraceConfigurationTests.swift`

Proof:
- Targeted `swift test --filter AgentStudioTraceConfigurationTests`.

### T2 - Introduce Trace Sink Fanout Behind the Existing Runtime API

Purpose:
Keep all current instrumentation call sites on `AgentStudioTraceRuntime.record(...)` while allowing JSONL and OTLP sinks to coexist.

Work:
- Introduce a small sink abstraction internal to diagnostics, such as `AgentStudioTraceSink`.
- Wrap the existing `AgentStudioJSONLTraceWriter` as the JSONL sink.
- Update `AgentStudioTraceRuntime` to build a sink list from effective configuration.
- Ensure attribute autoclosures are not evaluated when no enabled sink accepts the tag.
- Ensure a failure in one sink does not prevent the other sink from recording.
- Keep `flush()` fanout semantics and existing diagnostics for JSONL.
- Preserve existing `outputFileURL` behavior for JSONL users.

Likely write surfaces:
- `Sources/AgentStudio/Infrastructure/Diagnostics/AgentStudioTraceRuntime.swift`
- `Sources/AgentStudio/Infrastructure/Diagnostics/AgentStudioTraceSink.swift`
- `Sources/AgentStudio/Infrastructure/Diagnostics/AgentStudioJSONLTraceSink.swift`
- `Tests/AgentStudioTests/Infrastructure/Diagnostics/AgentStudioTraceRuntimeTests.swift`

Proof:
- Targeted `swift test --filter AgentStudioTraceRuntimeTests`.
- Existing JSONL trace tests continue to pass.

### T3 - Add the OTLP Projection Allowlist

Purpose:
Stop the rich local JSONL record from becoming the network contract.

Work:
- Add an `AgentStudioOTLPTraceProjection` type that accepts `AgentStudioTraceRecord` and returns:
  - stable body/event name
  - severity
  - timestamp
  - safe resource attributes
  - safe event attributes
- Do not pass `record.resource` through wholesale.
- Allow numeric durations, counts, controlled status/result enums, trace tag, and approved runtime flavor fields.
- Reject or omit:
  - raw paths
  - SQLite paths
  - raw error strings
  - process IDs
  - session IDs
  - pane IDs
  - tab IDs
  - surface IDs
  - window IDs
  - command IDs
  - runtime envelope IDs
  - zmx IDs
  - terminal output
  - prompt/model/tool payload text
  - correlation and causation IDs
- Treat existing local-only attributes as internal input only; they may help resolve hash identity but must not be exported.

Likely write surfaces:
- `Sources/AgentStudio/Infrastructure/Diagnostics/AgentStudioOTLPTraceProjection.swift`
- `Tests/AgentStudioTests/Infrastructure/Diagnostics/AgentStudioOTLPTraceProjectionTests.swift`

Proof:
- Projection tests for representative startup, SQLite, terminal, and Ghostty records.
- Negative tests for each forbidden family.

### T4 - Add Worktree and Runtime Identity Resolution

Purpose:
Give the shared Victoria target enough labels to separate worktrees and runtime flavors without leaking raw paths or mislabeling multi-worktree processes.

Work:
- Add a diagnostics-owned identity model for OTLP projection:
  - `service.name=agentstudio`
  - `service.version`
  - `dev.runtime.flavor`
  - `dev.build.config`
  - `dev.release.channel`
  - `dev.worktree.hash`
  - `git.branch.name`
  - `git.commit.sha` when known and safe
- Hash canonical worktree paths with a deterministic, non-reversible digest.
- Do not export the canonical path.
- Resolve identity per record when possible, rather than assuming the whole process has one active worktree.
- Use an explicit unknown value when no worktree/branch can be resolved.
- Add an update or resolver seam that can be populated from workspace boot, repo topology, git runtime events, or record-local context without making diagnostics own workspace domain state.
- Inventory current trace attributes before wiring identity; if current records do not carry enough context for a lane, add the smallest explicit context at the recording owner.

Likely write surfaces:
- `Sources/AgentStudio/Infrastructure/Diagnostics/AgentStudioOTLPResourceIdentity.swift`
- `Sources/AgentStudio/Infrastructure/Diagnostics/AgentStudioWorktreeIdentityResolver.swift`
- `Sources/AgentStudio/App/Boot/AppDelegate+WorkspaceBoot.swift` only if boot wiring is needed.
- Narrow trace call sites only when they need to pass a worktree context that already belongs to them.
- `Tests/AgentStudioTests/Infrastructure/Diagnostics/AgentStudioWorktreeIdentityResolverTests.swift`

Proof:
- Deterministic hash tests.
- Multi-worktree resolution tests.
- No raw path leakage tests.
- Unknown fallback tests.

Split or replan trigger:
- If correct per-record worktree identity requires broad feature instrumentation or new domain ownership, stop after the resolver/projection work and replan the identity wiring separately.

### T5 - Implement the OTLP Sink and Lifecycle Owner

Purpose:
Emit projected AgentStudio records as OTLP logs when configured, without slowing launch or requiring the collector.

Work:
- Add `AgentStudioOTLPTraceSink` that accepts only `AgentStudioOTLPTraceProjection`.
- Build a Swift OTel logs configuration:
  - logs enabled
  - metrics disabled
  - traces disabled
  - exporter OTLP
  - protocol HTTP/protobuf
  - endpoint default `http://127.0.0.1:4318`
  - resource attributes from the approved identity model
- Keep service lifecycle in a diagnostics owner object.
- Start the service asynchronously from app startup only when OTLP is an effective sink.
- Bound startup work so collector absence does not block launch.
- On record failure/export failure, write diagnostics but do not throw through app call sites.
- Add `shutdown()` or equivalent in addition to `flush()` if the OTel service requires graceful termination.

Likely write surfaces:
- `Sources/AgentStudio/Infrastructure/Diagnostics/AgentStudioOTLPTraceSink.swift`
- `Sources/AgentStudio/Infrastructure/Diagnostics/AgentStudioOTLPService.swift`
- `Sources/AgentStudio/Infrastructure/Diagnostics/AgentStudioTraceRuntime.swift`
- `Sources/AgentStudio/App/Boot/AppDelegate.swift`
- `Sources/AgentStudio/App/Boot/AppDelegate+Termination.swift`
- Tests under `Tests/AgentStudioTests/Infrastructure/Diagnostics/`

Proof:
- Targeted OTLP sink and lifecycle tests.
- Runtime fanout tests proving OTLP sink failures do not break JSONL.
- Termination flush/shutdown tests if lifecycle is app-owned.

### T6 - Keep JSONL Compatibility and Local Diagnostics

Purpose:
Preserve the existing debugging workflow while adding OTLP.

Work:
- Confirm JSONL record shape remains compatible for existing consumers.
- Keep unsupported selector and unknown tag diagnostics visible.
- Add diagnostics for:
  - effective backend
  - effective collector endpoint
  - local JSONL file path when JSONL is active
  - OTLP unavailable/export failure summaries
- Avoid noisy per-record stderr output for repeated collector failures.

Likely write surfaces:
- `Sources/AgentStudio/Infrastructure/Diagnostics/AgentStudioTraceRuntime.swift`
- `Sources/AgentStudio/Infrastructure/Diagnostics/AgentStudioTraceDiagnostics.swift` if a new helper earns its keep.
- Existing diagnostics tests.

Proof:
- Existing JSONL encoder/writer/runtime tests.
- New diagnostics tests for backend selection and one-time failure reporting.

### T7 - Add AgentStudio Collector Smoke Coverage

Purpose:
Prove the AgentStudio producer can send OTLP to a collector-shaped endpoint without making the shared Victoria stack a repo dependency.

Work:
- Add a default integration smoke using a local fake OTLP HTTP receiver if feasible.
- The fake receiver only needs to prove:
  - request arrives at `/v1/logs`
  - body is non-empty
  - app path remains healthy when receiver is absent
- Use bounded waits, not wall-clock sleeps.
- Add an opt-in real shared collector smoke, gated by an environment variable such as `AGENTSTUDIO_OTLP_REAL_COLLECTOR_SMOKE=1`.
- Do not require VictoriaMetrics, VictoriaLogs, or VictoriaTraces inside AgentStudio tests.

Likely write surfaces:
- `Tests/AgentStudioTests/Infrastructure/Diagnostics/AgentStudioOTLPSmokeTests.swift`
- Test helpers under the existing test tree if needed.

Proof:
- Targeted `swift test --filter AgentStudioOTLPSmokeTests`.
- Optional manual shared stack smoke documented but not required in default `mise run test`.

Split or replan trigger:
- If Swift OTel cannot be driven against a fake collector deterministically in-process, keep projection/sink unit tests default and make the real collector smoke explicitly env-gated.

### T8 - Document Shared Host Expectations Without Owning the Host

Purpose:
Make the operational contract discoverable for agents and developers.

Work:
- Update AgentStudio docs or `AGENTS.md` with:
  - shared stack is external
  - AgentStudio defaults to loopback collector endpoint
  - collector absence is expected and fail-open
  - debug/beta default behavior
  - disable knob: `AGENTSTUDIO_TRACE_TAGS=off`
  - explicit backend examples: `jsonl`, `otlp`, `both`
  - pointer to the shared-host command location once that exists
- Do not add compose files or Victoria configs in AgentStudio.

Likely write surfaces:
- `AGENTS.md`
- `docs/architecture/README.md` or a diagnostics doc if one exists or is added.

Proof:
- `rg` for documented knobs.
- Docs included in `mise run lint` if lint covers docs-sensitive scripts; otherwise report docs-only proof separately.

### T9 - Final Validation and Scope Check

Purpose:
Prove the implementation meets the agreed scope and did not drift into shared-host ownership.

Commands:
- Targeted tests after each task:
  - `swift test --filter AgentStudioTraceConfigurationTests`
  - `swift test --filter AgentStudioTraceRuntimeTests`
  - `swift test --filter AgentStudioOTLPTraceProjectionTests`
  - `swift test --filter AgentStudioWorktreeIdentityResolverTests`
  - `swift test --filter AgentStudioOTLPServiceTests`
  - `swift test --filter AgentStudioOTLPSmokeTests`
- Final gates:
  - `mise run lint`
  - `mise run test`

Scope checks:
- `rg -n "victoria|compose|docker" Sources Tests Package.swift`
  - Should show no AgentStudio-owned Victoria/compose implementation.
- `rg -n "process.pid|session.id|pane.*id|surface.*id|correlation|causation|path" Sources/AgentStudio/Infrastructure/Diagnostics Tests/AgentStudioTests/Infrastructure/Diagnostics`
  - Inspect that forbidden keys appear only in JSONL/local tests or negative projection tests.

## Write Surfaces Summary

Expected product code:
- `Sources/AgentStudio/Infrastructure/Diagnostics/AgentStudioTraceConfiguration.swift`
- `Sources/AgentStudio/Infrastructure/Diagnostics/AgentStudioTraceRuntime.swift`
- `Sources/AgentStudio/Infrastructure/Diagnostics/AgentStudioTraceSink.swift`
- `Sources/AgentStudio/Infrastructure/Diagnostics/AgentStudioJSONLTraceSink.swift`
- `Sources/AgentStudio/Infrastructure/Diagnostics/AgentStudioOTLPTraceProjection.swift`
- `Sources/AgentStudio/Infrastructure/Diagnostics/AgentStudioOTLPTraceSink.swift`
- `Sources/AgentStudio/Infrastructure/Diagnostics/AgentStudioOTLPService.swift`
- `Sources/AgentStudio/Infrastructure/Diagnostics/AgentStudioOTLPResourceIdentity.swift`
- `Sources/AgentStudio/Infrastructure/Diagnostics/AgentStudioWorktreeIdentityResolver.swift`
- `Sources/AgentStudio/Infrastructure/Diagnostics/AgentStudioRuntimeFlavor.swift`
- `Sources/AgentStudio/App/Boot/AppDelegate.swift`
- `Sources/AgentStudio/App/Boot/AppDelegate+Termination.swift`
- Potential narrow workspace boot or trace call-site edits only if required by T4 identity proof.

Expected tests:
- Existing diagnostics tests under `Tests/AgentStudioTests/Infrastructure/Diagnostics/`
- New diagnostics tests for projection, identity, OTLP service, and smoke.
- Existing feature tests that assert JSONL traces for terminal, Ghostty, inbox, and SQLite should continue to pass.

Possible package changes:
- `Package.swift` test target dependencies only if tests import `OTel`, `Logging`, or `ServiceLifecycle` directly.

Docs:
- `AGENTS.md` or an AgentStudio diagnostics/architecture doc.

## Validation Gates by Layer

Unit:
- Configuration parsing and effective policy.
- Runtime fanout and sink failure isolation.
- OTLP projection allowlist.
- Worktree identity hashing and resolution.
- OTel service owner lifecycle at the smallest deterministic unit boundary.

Integration:
- Fake collector smoke for `/v1/logs` request path and non-empty OTLP payload, if deterministic.
- Collector-absent smoke proving record/flush/shutdown remain non-crashing.

Smoke:
- Optional real shared collector smoke behind explicit environment flag.
- No default AgentStudio smoke should require Docker or Victoria.

Static:
- `mise run lint`.

Full repo:
- `mise run test`.

Out of scope for this repo:
- VictoriaMetrics, VictoriaLogs, VictoriaTraces end-to-end query proof.
- Shared Docker compose lifecycle proof.
- Collector processor redaction/transform snapshot tests.

Those belong to the shared host package plan.

## Rollback and Recovery

- Runtime disable: `AGENTSTUDIO_TRACE_TAGS=off`.
- Backend rollback: `AGENTSTUDIO_TRACE_BACKEND=jsonl`.
- Stable app remains opt-in, so release impact is bounded.
- If OTLP sink misbehaves in debug/beta, set backend to `jsonl` or tags to `off`.
- If Swift OTel lifecycle introduces unacceptable process-global coupling, keep JSONL-only behavior and stop before broad wiring.
- If worktree identity cannot be resolved safely, emit `unknown` for OTLP identity rather than leaking raw paths.

## Security and Privacy Assumptions

- Loopback is trusted for local developer observability, but still treated as network egress.
- Branch names are allowed by user decision for local-loopback visibility.
- Raw paths are not allowed in OTLP.
- Collector-side scrubbing is defense in depth, not a substitute for AgentStudio source-side projection.
- The app must not send telemetry to a remote endpoint unless explicitly configured.
- Local JSONL can remain richer because it is already an explicit local diagnostics artifact.

## Risks

- Swift OTel global bootstrap could conflict with tests or future SwiftLog users. T0 must settle this first.
- One AgentStudio process can touch multiple worktrees; process-global worktree labels would be wrong. T4 must prove per-record or resolvable identity.
- Existing JSONL tests may rely on current resource keys. OTLP projection must not force JSONL to drop local fields.
- A fake collector may not be deterministic enough with the real Swift OTel async exporter. If so, keep it opt-in and document why.
- Debug/beta default enablement changes current behavior from disabled-by-default to useful-by-default. Tests must pin the exact conditions and the `off` escape hatch.
- Shared host documentation may point to a command that does not exist yet. Prefer landing the shared host plan first; otherwise mark the command location as external/future instead of inventing a local AgentStudio command.

## Open Questions

- Should the shared host tooling plan in `devfiles` land before AgentStudio implementation, or can AgentStudio ship producer support against a fake collector first?
- Should `both-auto` be an internal effective policy only, or should it be user-selectable as a backend spelling?
- What exact existing record attributes are sufficient to resolve worktree identity per event? T4 starts with an inventory and must stop if the answer requires a broader instrumentation design.
- Should real spans and metrics be a follow-up plan after logs are proven, or should startup duration metrics be added immediately after OTLP logs?

## Recommended Next Step

Run `shravan-dev-workflow:plan-review` or `shravan-dev-workflow:plan-review-swarm` against this plan before implementation. The highest-value review questions are:

- Does the plan keep AgentStudio producer-only and leave shared-host ownership outside this repo?
- Is the Swift OTel lifecycle proof strong enough before runtime fanout?
- Does T4 correctly avoid process-global worktree mislabeling?
- Are the validation gates sufficient for debug/beta default emission and collector absence?
