# AgentStudio OTLP Shared Observability Implementation Plan

Status: draft implementation plan, pending plan-review-swarm.
Date: 2026-06-11
Spec source: `docs/superpowers/specs/2026-06-11-agentstudio-otlp-shared-observability-design.md`

## Goal

Add AgentStudio producer-side OTLP output so debug and beta builds can emit
reduced local telemetry to a loopback OpenTelemetry Collector when one is
running, while preserving the existing JSONL diagnostic output and keeping the
shared Victoria/Compose host out of this repo.

The v1 shape is:

```text
AgentStudio emitters
  -> AgentStudioTraceRuntime
     -> JSONL sink, current rich local diagnostics
     -> OTLP sink, reduced source-side projection
        -> 127.0.0.1 collector only, if configured/available
        -> shared Victoria stack owned by devfiles/shared tooling
```

## Non-goals

- Do not add Docker Compose, VictoriaMetrics, VictoriaLogs, VictoriaTraces, or
  collector config ownership to AgentStudio.
- Do not auto-start Docker or block app startup on collector readiness.
- Do not replace JSONL with OTLP.
- Do not rewrite every trace call site.
- Do not fake every JSONL event as a span.
- Do not emit raw paths, pane IDs, surface IDs, process IDs, session IDs,
  command IDs, correlation IDs, raw errors, terminal output, prompts, model
  payloads, or tool payloads over OTLP.
- Do not add remote OTLP endpoints or auth headers in this slice.
- Do not add dashboards in this repo.
- Do not add HEAD commit polling inside tracing unless a later reviewed plan
  adds commit to the Git enrichment model.

## Source Coverage

- Approved spec loaded with `wc -l`: 695 lines.
- Spec chunks read completely: lines 1-180, 181-360, 361-540, 541-695.
- Plan-create skill loaded from
  `/Users/shravansunder/.codex/plugins/cache/ai-tools/shravan-dev-workflow/1.6.15/skills/plan-create/SKILL.md`.
- Memory refresh used only for prior AgentStudio/Victoria observability context:
  AgentStudio remains OTLP-unimplemented, sibling Agent VM prior art says keep
  slow Docker/Compose prep out of fast app/controller startup, and source-side
  non-emission is the primary safety invariant.
- Upstream `swift-otel` check via DeepWiki for `swift-otel/swift-otel`:
  `OTel.bootstrap(configuration:)` returns a Service, SwiftLog is the log
  emission path, endpoint/protocol live in OTel configuration, and tests that
  bootstrap global logging/instrumentation should be isolated.

## Current Repo Evidence

- `Package.swift:15` and `Package.swift:26` already depend on
  `swift-otel` and the `OTel` product.
- `Package.resolved:221-226` pins `swift-otel` to 1.0.5.
- `Sources/AgentStudio/Infrastructure/Diagnostics/AgentStudioTraceConfiguration.swift:16-28`
  has only `.jsonl`; unsupported backend selectors fall back to JSONL.
- `Sources/AgentStudio/Infrastructure/Diagnostics/AgentStudioTraceConfiguration.swift:46-60`
  parses trace tags, trace file settings, flush mode, and backend from env.
- `Sources/AgentStudio/Infrastructure/Diagnostics/AgentStudioTraceRuntime.swift:11-18`
  owns one JSONL writer and immutable resource attributes today.
- `Sources/AgentStudio/Infrastructure/Diagnostics/AgentStudioTraceRuntime.swift:59-71`
  creates JSONL output only when tags are enabled.
- `Sources/AgentStudio/Infrastructure/Diagnostics/AgentStudioTraceRuntime.swift:92-138`
  records JSONL events and flushes only the JSONL writer.
- `Sources/AgentStudio/Infrastructure/Diagnostics/AgentStudioTraceRuntime.swift:144-160`
  currently puts `process.pid` and `agentstudio.session.id` into local resource
  attributes; OTLP projection must drop those.
- `Sources/AgentStudio/main.swift:24-31` creates trace runtime before
  `ghostty_init`, so early app startup can use the new backend.
- `Sources/AgentStudio/main.swift:74-77` passes that runtime into `AppDelegate`.
- `Sources/AgentStudio/Infrastructure/AppDataPaths.swift:12-30` exposes release
  channel and debug build facts.
- `Sources/AgentStudio/Infrastructure/AppDataPaths.swift:127-137` makes debug
  win over beta for data-root behavior; runtime flavor should mirror this.
- `Sources/AgentStudio/App/Boot/AppDelegate+WorkspaceBoot.swift:120-185` creates
  the SQLite datastore and restores workspace state with the trace runtime
  already available.
- `Sources/AgentStudio/App/Boot/AppDelegate+WorkspaceBoot.swift:249-304` wires
  runtime bus, cache coordinator, terminal activity router, and command surfaces.
- `Sources/AgentStudio/App/Boot/AppDelegate+WorkspaceBoot.swift:320-360` replays
  topology and arms cache observation after boot; this is the late identity
  refresh point.
- `Sources/AgentStudio/App/Boot/AppDelegate+Termination.swift:45-82` already
  drains trace producers and flushes the trace runtime on termination.
- `Sources/AgentStudio/Core/Models/StableKey.swift:4-11` already derives a
  SHA-256 16-character stable key from paths.
- `Sources/AgentStudio/Core/Models/Worktree.swift:3-14` documents Worktree as
  structure-only and exposes `stableKey`.
- `Sources/AgentStudio/Core/Models/WorktreeEnrichment.swift:3-11` owns
  rebuildable branch/status enrichment.
- `Sources/AgentStudio/Core/RuntimeEventSystem/Contracts/PaneRuntimeEvent.swift:159-178`
  shows `GitWorkingTreeSnapshot` has branch but not commit SHA.
- `Sources/AgentStudio/App/Coordination/WorkspaceCacheCoordinator.swift:229-251`
  writes branch changes into `RepoCacheAtom`.
- `Sources/AgentStudio/Core/State/MainActor/Atoms/WorkspaceRepositoryTopologyAtom.swift:39-98`
  can resolve repo/worktree from CWD; it also owns topology worktree lookup.
- `Sources/AgentStudio/Core/State/MainActor/Atoms/RepoCacheAtom.swift:137-170`
  exposes repo/worktree enrichment and PR counts.
- `Sources/AgentStudio/Core/State/SQLite/WorkspaceSQLiteTraceRecorder.swift:168-190`
  emits workspace IDs, database paths, and raw errors into JSONL attributes.
- `Sources/AgentStudio/Features/Terminal/Routing/TerminalActivityRouter.swift:465-485`
  emits pane IDs, event IDs, command IDs, correlation IDs, and causation IDs.
- `Sources/AgentStudio/Features/Terminal/Ghostty/GhosttyActionRouter+Tracing.swift:61-85`
  emits action names, payload classes, pane IDs, surface IDs, and route reasons.
- `Tests/AgentStudioTests/Infrastructure/Diagnostics/AgentStudioTraceConfigurationTests.swift:156-170`
  asserts OTLP is currently unsupported.
- `Tests/AgentStudioTests/Infrastructure/Diagnostics/AgentStudioTraceRuntimeTests.swift:33-76`
  asserts the current JSONL record shape.
- `Tests/AgentStudioTests/Infrastructure/Diagnostics/AgentStudioTraceRuntimeTests.swift:236-257`
  already touches global `InstrumentationSystem.bootstrap`, so real OTel
  bootstrap tests must be isolated from broad unit runs.
- `.mise.toml:101-114` defines the authoritative lint gate.
- `.mise.toml:145-169` shows the build task uses build slots.

## Requirements And Proof Matrix

| ID | Requirement | Owning task | Proof gate | Layer | Red/green required |
| --- | --- | --- | --- | --- | --- |
| R1 | Debug/beta default to safe tracing baseline and stable stays opt-in | T1 | `AgentStudioTraceConfigurationTests` | Unit | Yes |
| R2 | `AGENTSTUDIO_TRACE_TAGS=off` disables debug/beta tracing | T1 | `AgentStudioTraceConfigurationTests` | Unit | Yes |
| R3 | Backends parse as `jsonl`, `otlp`, `both`; unknown falls back safely | T1 | `AgentStudioTraceConfigurationTests` | Unit | Yes |
| R4 | OTLP endpoint is loopback-only and absence/unhealthy collector is fail-open | T1, T4 | config tests plus fake collector/absent collector smoke | Unit + integration | Yes |
| R5 | JSONL remains rich and existing JSONL tests keep passing | T2, T3 | existing diagnostics tests | Unit | Yes |
| R6 | Runtime fans out to sinks without duplicating call-site logic | T2 | sink/fanout runtime tests | Unit | Yes |
| R7 | OTLP projection exports only allowlisted fields | T3 | projection allowlist/drop-list tests | Unit | Yes |
| R8 | Process identity includes runtime flavor/build/channel/service attrs | T1, T3 | resource identity/projection tests | Unit | Yes |
| R9 | Worktree segregation uses stable hash plus branch when available, without raw paths | T5 | identity projection tests with fake topology/enrichment | Unit | Yes |
| R10 | Multiple worktrees in one app process do not become process-global resource lies | T5 | pane/worktree identity snapshot tests | Unit | Yes |
| R11 | Real `swift-otel` bootstrap is owned once and shut down on termination | T4 | isolated bootstrap smoke or scripted subprocess smoke | Integration/smoke | Yes |
| R12 | Global bootstrap does not contaminate ordinary unit tests | T4 | default `mise run test` after focused tests | Unit | Yes |
| R13 | AgentStudio docs point to shared host without owning it | T6 | docs diff review plus link/text check | Docs | Yes |
| R14 | Final repo gates pass | T7 | `mise run lint`, `mise run test`, scoped smoke | Static + unit + integration/smoke | Yes |

If any row cannot pass at the planned task size, split the task before
implementation rather than waiving proof.

## Task Sequence

### T0. Preflight

Do before code edits:

1. Run `git status --short --branch`.
2. Re-open this plan and the approved spec.
3. Confirm no shared-host files are being edited in this repo.
4. Confirm current `swift-otel` pin and package layout still match this plan.

No write surfaces.

### T1. Configuration, Runtime Flavor, And Endpoint Policy

Write surfaces:

- `Sources/AgentStudio/Infrastructure/Diagnostics/AgentStudioTraceConfiguration.swift`
- New diagnostics identity/config helper if needed, for example
  `Sources/AgentStudio/Infrastructure/Diagnostics/AgentStudioTraceRuntimeIdentity.swift`
- `Tests/AgentStudioTests/Infrastructure/Diagnostics/AgentStudioTraceConfigurationTests.swift`
- Possibly `Package.swift` only if direct `Logging` product import is needed later

Implementation shape:

1. Add `AgentStudioTraceRuntimeFlavor` with `debug`, `beta`, `stable`, and
   `custom` if needed for explicit env overrides.
2. Compute flavor from `AppDataPaths.isDebugBuild` and
   `AppDataPaths.ReleaseChannel.current`; debug wins over beta.
3. Extend `AgentStudioTraceBackend` to support `jsonl`, `otlp`, and `both`.
4. Keep unsupported backend fallback non-fatal with a startup diagnostic.
5. Add effective defaults:
   - stable, no explicit tags: disabled JSONL-compatible behavior.
   - debug/beta, no explicit tags: safe baseline tags from the spec.
   - `AGENTSTUDIO_TRACE_TAGS=off`: disabled in all flavors.
   - explicit `AGENTSTUDIO_TRACE_TAGS`: replaces the safe baseline.
6. Add OTLP config parsing:
   - prefer standard `OTEL_EXPORTER_OTLP_ENDPOINT`;
   - default to `http://127.0.0.1:4318` only for debug/beta effective OTLP;
   - prefer/require `OTEL_EXPORTER_OTLP_PROTOCOL=http/protobuf` for v1 unless
     implementation proof shows the package only supports gRPC without extra
     flags;
   - accept only loopback hosts: `127.0.0.1`, `localhost`, and `::1`;
   - reject remote endpoints with a diagnostic and disable OTLP.
7. Keep collector readiness outside the app startup contract. Developer helpers
   may health-check the shared collector before enabling OTLP, but app runtime
   behavior remains fail-open.

Proof:

- Add failing tests first for safe defaults, off override, backend parsing,
  endpoint defaulting, and loopback rejection.
- Then implement until focused config tests pass.

### T2. Sink Fanout While Preserving JSONL

Write surfaces:

- `Sources/AgentStudio/Infrastructure/Diagnostics/AgentStudioTraceRuntime.swift`
- New diagnostics sink files, for example:
  - `AgentStudioTraceSink.swift`
  - `AgentStudioJSONLTraceSink.swift`
  - `AgentStudioOTLPTraceSink.swift` stub/fake-ready surface
- `Tests/AgentStudioTests/Infrastructure/Diagnostics/AgentStudioTraceRuntimeTests.swift`
- Existing trace recorder tests only if constructor signatures change

Implementation shape:

1. Introduce a small sink protocol for `record(_:)`, `flush()`, and diagnostics.
2. Wrap the existing `AgentStudioJSONLTraceWriter` as the JSONL sink.
3. Keep `AgentStudioTraceRuntime.record(...)` as the single call-site API.
4. Evaluate autoclosure attributes only when at least one enabled sink needs the
   record.
5. Build an `AgentStudioTraceRecord` once, then fan it out.
6. Preserve `outputFileURL` for JSONL tests and local debugging.
7. Keep sink failures isolated:
   - JSONL failures remain local diagnostics.
   - OTLP failures do not stop JSONL and do not throw from normal record calls.
8. Add a low-noise OTLP diagnostic path for unavailable collector state.

Proof:

- Unit tests with fake sinks proving:
  - disabled runtime still does not evaluate attributes;
  - `.jsonl` only writes JSONL;
  - `.otlp` only calls OTLP sink and leaves `outputFileURL` nil;
  - `.both` fans out to both;
  - OTLP sink failure does not prevent JSONL append;
  - flush fans out to all live sinks.
- Existing JSONL tests must remain green or be updated only for intentional
  additions that do not remove local forensic fields.

### T3. Source-Side OTLP Projection

Write surfaces:

- New projection file, for example
  `Sources/AgentStudio/Infrastructure/Diagnostics/AgentStudioOTLPTraceProjection.swift`
- `Tests/AgentStudioTests/Infrastructure/Diagnostics/AgentStudioOTLPTraceProjectionTests.swift`
- Existing recorder tests only to add projection assertions, not to reduce JSONL

Implementation shape:

1. Add an explicit projection DTO independent of `AgentStudioTraceRecord`.
2. Project to OTLP logs first; do not create spans for every record.
3. Allow these categories:
   - time, severity, trace tag, stable body/event name;
   - process-static service/build/channel/runtime identity;
   - late-bound repo/worktree stable keys and branch;
   - controlled enum/status/outcome fields;
   - numeric durations/counts;
   - selected booleans that do not identify a user/session/pane.
4. Drop these categories even when present in JSONL:
   - raw or normalized paths;
   - SQLite database paths;
   - workspace UUIDs unless transformed into an approved stable local hash;
   - raw errors;
   - process ID and session ID;
   - pane/surface/window IDs;
   - command/correlation/causation/envelope IDs;
   - zmx session IDs;
   - terminal output or prompt/model/tool payload text.
5. Preserve route/action class fields but drop freeform route reasons unless the
   reason value is converted to a controlled enum allowlist.

Proof:

- Projection tests should build rich `AgentStudioTraceRecord` fixtures from
  startup, SQLite, terminal activity, and Ghostty action examples.
- Each fixture proves safe fields are kept and unsafe fields are dropped.
- Add negative canary values like `/Users/shravan/...`, UUIDs, and raw error
  text and assert they are absent from projected OTLP metadata/body.

### T4. Real Swift OTel Sink And Lifecycle

Write surfaces:

- `Package.swift` if direct `Logging` / `ServiceLifecycle` product dependencies
  are required by SwiftPM.
- New diagnostics files, for example:
  - `AgentStudioOTLPBootstrapper.swift`
  - `AgentStudioOTLPServiceRunner.swift`
  - `AgentStudioSwiftLogEmitter.swift`
- `Sources/AgentStudio/Infrastructure/Diagnostics/AgentStudioTraceRuntime.swift`
- `Sources/AgentStudio/App/Boot/AppDelegate+Termination.swift`
- Tests under `Tests/AgentStudioTests/Infrastructure/Diagnostics/`
- Optional script smoke under `scripts/` if an isolated subprocess is cleaner
  than a Swift Testing global-bootstrap test

Implementation shape:

1. Add an injectable `AgentStudioOTLPBootstrapper` so unit tests do not call
   global `OTel.bootstrap`.
2. Configure `OTel.Configuration` for logs-only v1:
   - service name `agentstudio`;
   - resource attrs from the safe projection identity;
   - traces disabled except future explicit span work;
   - metrics disabled except future Swift Metrics work;
   - logs enabled with OTLP exporter;
   - endpoint/protocol from T1.
3. Run the returned OTel service in a long-lived app-owned task or service group.
4. Add graceful shutdown/flush to the existing termination trace flush path.
5. Emit projected records through SwiftLog after OTel bootstrap.
6. If the collector is absent:
   - app launch continues;
   - JSONL stays active;
   - OTLP reports one startup diagnostic;
   - no modal, crash, or blocking retry loop.
7. Helper-driven beta launches health-check the shared collector before setting
   OTLP env and force JSONL-only env when the collector is unreachable.

Proof:

- Unit tests use fake bootstrapper/log emitter to avoid global bootstrap.
- One isolated smoke proves real bootstrap/export behavior. Prefer one of:
  - a scripted subprocess smoke with a tiny loopback HTTP collector returning
    200; or
  - a single filtered Swift test command that starts before other
    instrumentation tests and is not part of broad default execution.
- The smoke does not require Victoria. It proves AgentStudio can talk to an OTLP
  collector endpoint and exits cleanly.

Replan trigger:

- If `swift-otel` 1.0.5 requires unavailable compile traits for HTTP/protobuf or
  gRPC exporters, stop and update this plan before package flag work.
- If `OTel.bootstrap` conflicts with existing instrumentation tests in default
  `mise run test`, stop and move real bootstrap proof to a subprocess/script
  smoke rather than weakening the broad test gate.

### T5. Late-Bound Worktree Identity Projection

Write surfaces:

- New diagnostics identity files, for example:
  - `AgentStudioTraceIdentitySnapshot.swift`
  - `AgentStudioTraceIdentityStore.swift`
  - `AgentStudioTraceIdentityProjector.swift`
- `Sources/AgentStudio/Infrastructure/Diagnostics/AgentStudioTraceRuntime.swift`
- `Sources/AgentStudio/App/Boot/AppDelegate+WorkspaceBoot.swift`
- Possibly `Sources/AgentStudio/App/Coordination/WorkspaceCacheCoordinator.swift`
  if the cleanest refresh point is after topology/enrichment changes
- Tests under diagnostics and possibly app/coordinator helpers

Implementation shape:

1. Keep process-static identity separate from record-specific identity.
2. Add a trace identity store that holds safe, already-reduced identity:
   - `service.name`, `service.version`;
   - `dev.runtime.flavor`;
   - `dev.build.config`;
   - `dev.release.channel`;
   - `agentstudio.build.config`;
   - `agentstudio.release_channel`;
   - `agentstudio.runtime_flavor`;
   - `dev.repo.hash` from `Repo.stableKey`;
   - `dev.worktree.hash` from `Worktree.stableKey`;
   - `git.branch` from `WorktreeEnrichment.branch` when known.
3. Do not put raw repo/worktree paths into the identity store.
4. Keep `git.commit` optional and unset in v1 unless a current repo source
   already exposes it. Current `GitWorkingTreeSnapshot` has branch but not commit.
5. Build a safe map from local-only IDs to identity:
   - pane ID -> repo/worktree stable identity;
   - worktree ID -> repo/worktree stable identity.
6. The OTLP projection may consult raw JSONL-only IDs only inside process memory
   to find safe identity, then drops those IDs from the exported record.
7. Refresh identity:
   - after canonical store/cache restore;
   - after initial topology replay;
   - after topology or branch enrichment changes.

Proof:

- Unit tests with fake repos, worktrees, panes, and enrichment prove:
  - worktree hash and branch are added when available;
  - raw path, pane ID, worktree ID, and repo ID are not exported;
  - branch may appear as accepted local visibility;
  - startup records before workspace boot do not invent workspace identity;
  - multiple worktrees in one process get record-specific identity instead of
    one global process resource lie.

Replan trigger:

- If clean identity refresh requires new atom/store ownership, stop for design
  review before changing state boundaries.

### T6. Agent-Facing Docs Pointer

Write surfaces:

- `AGENTS.md`
- Possibly `docs/guides/agent_resources.md` if the repo already points agents
  there for local bootstrap guidance

Implementation shape:

1. Add a short pointer explaining:
   - AgentStudio emits OTLP only as a producer;
   - shared local observability stack lives in devfiles/shared tooling;
   - default endpoint is loopback collector `http://127.0.0.1:4318`;
   - missing collector is non-fatal;
   - debug/beta safe baseline and `AGENTSTUDIO_TRACE_TAGS=off`;
   - Victoria backend ports are not AgentStudio-owned.
2. Do not add Compose commands unless the shared host plan has landed in the
   owning repo and the command is stable.

Proof:

- Docs diff contains no local Compose ownership.
- Text names the external/shared host boundary.

### T7. Validation And Cleanup

Run proof in layers:

1. Focused unit tests while building:
   - `swift test --filter AgentStudioTraceConfigurationTests`
   - `swift test --filter AgentStudioTraceRuntimeTests`
   - `swift test --filter AgentStudioOTLPTraceProjectionTests`
   - any new identity/projection test filters
2. Isolated OTLP smoke:
   - fake collector or env-gated real collector test as defined in T4.
   - no Victoria dependency in this repo.
3. Repo static gate:
   - `mise run lint`
4. Repo unit/integration gate:
   - `mise run test`
5. Optional manual shared-host e2e after the devfiles/shared stack exists:
   - start shared stack from owning repo;
   - run AgentStudio debug/beta with OTLP enabled;
   - query collector/Victoria canaries from shared tooling.

Do not call the AgentStudio implementation done unless 1-4 pass or a real
environment blocker is reported with exact failure output.

## Write Surface Summary

Expected AgentStudio code writes:

- `Sources/AgentStudio/Infrastructure/Diagnostics/AgentStudioTraceConfiguration.swift`
- `Sources/AgentStudio/Infrastructure/Diagnostics/AgentStudioTraceRuntime.swift`
- New diagnostics files under `Sources/AgentStudio/Infrastructure/Diagnostics/`
- `Sources/AgentStudio/App/Boot/AppDelegate+WorkspaceBoot.swift`
- `Sources/AgentStudio/App/Boot/AppDelegate+Termination.swift`
- Possibly `Sources/AgentStudio/App/Coordination/WorkspaceCacheCoordinator.swift`
- Possibly `Package.swift`
- Diagnostics tests under `Tests/AgentStudioTests/Infrastructure/Diagnostics/`
- Possibly focused app/coordinator tests if identity refresh is wired there
- `AGENTS.md` or one linked guide doc for the producer/shared-host pointer
- Optional `scripts/` smoke helper if needed to isolate real OTel bootstrap

Surfaces that must not be written in this AgentStudio plan:

- Docker Compose files for Victoria/collector.
- VictoriaMetrics, VictoriaLogs, VictoriaTraces config.
- Collector config rendering.
- Shared host storage/retention defaults.
- Cross-project observability service names beyond the endpoint contract.

## Shared-Host Companion Work

This plan intentionally does not implement the shared observability host. A
separate devfiles/shared-tooling plan should own:

- compose project `shravan-observability`;
- service names `obs-otel-collector`, `obs-victoria-metrics`,
  `obs-victoria-logs`, `obs-victoria-traces`, optional `obs-grafana`;
- default loopback bindings for collector OTLP/health only;
- debug profile bindings for Victoria backend ports;
- durable data directory policy;
- generated collector config with redaction/drop/hash processors;
- VictoriaLogs stream/ignore fields;
- VictoriaMetrics label limits and relabeling;
- VictoriaTraces attribute cleanup;
- shared canary/e2e tests with positive and negative scrub assertions.

AgentStudio should only link to that host once the owning repo has a stable
command.

## Rollback And Recovery

- Stable builds remain opt-in; if OTLP misbehaves, leave
  `AGENTSTUDIO_TRACE_TAGS` unset or set `AGENTSTUDIO_TRACE_TAGS=off`.
- Any build can force local-only JSONL with `AGENTSTUDIO_TRACE_BACKEND=jsonl`.
- OTLP endpoint rejection or collector absence is non-fatal by default.
- JSONL output remains the forensic fallback.
- The shared host can be stopped independently; AgentStudio should continue to
  launch and run.

## Risks

- `swift-otel` global bootstrap can make tests order-dependent. Mitigation:
  fake bootstrap in units and isolate real bootstrap smoke.
- OTLP HTTP/gRPC exporter availability may depend on package traits. Mitigation:
  verify before wiring real sink; replan if package flags are required.
- Worktree identity can become wrong if stored as process resource in a
  multi-worktree app. Mitigation: record-specific safe identity snapshot.
- Projection bugs can leak local paths or IDs. Mitigation: negative canary tests
  and source-side drop list before collector/Victoria.
- Endpoint config can accidentally enable remote telemetry. Mitigation:
  loopback-only endpoint policy in v1.
- Existing JSONL tests depend on rich local attributes. Mitigation: preserve
  JSONL shape and reduce only OTLP projection.

## Open Questions

1. Should the companion shared-host plan be created in `devfiles` immediately
   after this AgentStudio plan review, or should AgentStudio producer work land
   first with only fake-collector proof?
2. Should `git.commit` wait for a separate Git enrichment change? Current source
   has branch but not commit; this plan treats commit as optional/unset in v1.
3. Should explicit remote OTLP endpoints ever be supported for beta? This plan
   says no for v1.

## Recommended Next Step

Run `shravan-dev-workflow:plan-review-swarm` against this plan before executing
implementation.
